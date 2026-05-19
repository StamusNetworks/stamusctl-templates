#!/usr/bin/env bats
# ISM (Index State Management) policy validation

load "../helpers/common.bash"

# ISM setup-ism container runs Terraform to apply the policy.
# It may take a moment after stack startup to complete.
setup() {
    # Wait for the setup-ism container to have finished
    local timeout=120
    local elapsed=0
    while (( elapsed < timeout )); do
        local state
        state="$(docker ps -a --filter "name=setup-ism" --format '{{.Status}}' | head -1)"
        if echo "$state" | grep -q "Exited (0)"; then
            return 0
        fi
        if echo "$state" | grep -q "Exited"; then
            echo "setup-ism exited with error: $state" >&2
            docker logs "$(docker ps -a --filter "name=setup-ism" --format '{{.Names}}' | head -1)" >&2 || true
            return 1
        fi
        sleep 5
        elapsed=$(( elapsed + 5 ))
    done
    echo "setup-ism did not complete within ${timeout}s" >&2
    return 1
}

@test "ISM policy exists in opensearch" {
    local policy
    policy="$(opensearch_query "/_plugins/_ism/policies")"
    [[ -n "$policy" ]] || {
        echo "No ISM policies found" >&2
        return 1
    }
    echo "$policy" | grep -q "hot_warm_delete\|ClearNDR" || {
        echo "Expected ISM policy not found:" >&2
        echo "$policy" | head -30 >&2
        return 1
    }
}

@test "ISM policy warm state does NOT have close action" {
    local policy
    policy="$(opensearch_query "/_plugins/_ism/policies")"

    # Extract the warm state section from the JSON
    # The JSON has: "states":[...{"name":"warm","actions":[...]...}...]
    # Use grep -oP to pull out the warm state block
    local warm_section
    warm_section="$(echo "$policy" | grep -oP '"name"\s*:\s*"warm".*?"transitions"' || true)"

    [[ -n "$warm_section" ]] || {
        echo "Warm state not found in ISM policy" >&2
        echo "$policy" | head -40 >&2
        return 1
    }

    # Verify read_only is present in the warm state
    echo "$warm_section" | grep -q "read_only" || {
        echo "Warm state missing read_only action" >&2
        echo "Warm section: $warm_section" >&2
        return 1
    }

    # Verify close is NOT present (this is the fix being tested)
    if echo "$warm_section" | grep -q '"close"'; then
        echo "REGRESSION: Warm state still has 'close' action" >&2
        echo "Warm section: $warm_section" >&2
        return 1
    fi
}

@test "ISM policy has correct default retention ages" {
    local policy
    policy="$(opensearch_query "/_plugins/_ism/policies")"

    # Check warm transition age
    echo "$policy" | grep -q "7d" || {
        echo "Expected warm_min_index_age of 7d not found in policy" >&2
        return 1
    }

    # Check delete transition age
    echo "$policy" | grep -q "15d" || {
        echo "Expected delete_min_index_age of 15d not found in policy" >&2
        return 1
    }
}

@test "ISM policy targets logstash indices" {
    local policy
    policy="$(opensearch_query "/_plugins/_ism/policies")"

    echo "$policy" | grep -q "logstash" || {
        echo "ISM policy does not target logstash indices" >&2
        echo "$policy" | head -20 >&2
        return 1
    }
}
