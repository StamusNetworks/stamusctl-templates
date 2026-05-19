#!/usr/bin/env bats
# Upgrade tests: deploy released → inject data → upgrade to local → verify data survives

load "../helpers/common.bash"

setup_file() {
    # Tear down any existing stack first (frees ports)
    stamusctl_compose down --volumes 2>/dev/null || true

    # Clean config directory before fresh init (leftover rendered templates crash re-init)
    find "${TEST_CONFIG}" -mindepth 1 -not -name '.gitignore' -exec rm -rf {} + 2>/dev/null || true

    # The released template binds nginx to port 80; skip if port is still in use
    if ss -tlnH sport = :80 2>/dev/null | grep -q LISTEN; then
        export UPGRADE_SKIP="Port 80 is in use (released template requires it)"
        return 0
    fi

    # Deploy from the registry (released version, no --template flag)
    local iface="${SURICATA_IFACE:-lo}"
    local scirius_arg=""
    [[ -n "${SCIRIUS_IMAGE:-}" ]] && scirius_arg="scirius.image=${SCIRIUS_IMAGE}"
    "$STAMUSCTL_BIN" compose init --default -c "$TEST_CONFIG" "suricata.interfaces=${iface}" $scirius_arg 2>/dev/null || {
        export UPGRADE_SKIP="Registry init failed (stamusctl bug or network issue)"
        return 0
    }
    stamusctl_compose up -d || {
        echo "Failed to start released stack" >&2
        return 1
    }
    fix_readpcap_paths

    # Wait for services to come up
    wait_for_healthy "$STARTUP_TIMEOUT" || {
        echo "Released stack did not become healthy" >&2
        stamusctl_compose ps >&2 || true
        return 1
    }

    # Inject PCAP if available
    local pcap
    pcap="$(find_pcap)" || {
        echo "No PCAP file found — upgrade data tests will verify structure only" >&2
        return 0
    }
    stamusctl_compose readpcap "$pcap" || true
    wait_for_documents 1 60 || true
}

teardown_file() {
    stamusctl_compose down --volumes 2>/dev/null || true
}

setup() {
    [[ -z "${UPGRADE_SKIP:-}" ]] || skip "$UPGRADE_SKIP"
}

@test "baseline: released stack is healthy" {
    wait_for_healthy 60
}

@test "baseline: capture document count" {
    local count
    count="$(opensearch_count 2>/dev/null)" || count=0
    save_state "pre_upgrade_count" "$count"
    echo "Pre-upgrade document count: $count"
}

@test "compose down preserves volumes" {
    stamusctl_compose down

    # Volumes should still exist
    local volumes
    volumes="$(docker volume ls --format '{{.Name}}')"
    echo "$volumes" | grep -q "opensearch-data\|elastic-data" || {
        echo "Data volumes not preserved after compose down:" >&2
        echo "$volumes" >&2
        return 1
    }
}

@test "upgrade to local template succeeds" {
    run stamusctl_compose update --template "$TEMPLATE_PATH"
    [[ "$status" -eq 0 ]] || {
        echo "Upgrade failed:" >&2
        echo "$output" >&2
        return 1
    }
}

@test "upgraded stack starts and is healthy" {
    stamusctl_compose up -d
    fix_readpcap_paths
    wait_for_healthy "$STARTUP_TIMEOUT"
}

@test "opensearch version is 3.3.1 after upgrade" {
    local version
    version="$(opensearch_version)"
    [[ "$version" == "3.3.1" ]] || {
        echo "Post-upgrade OpenSearch version is '$version', expected 3.3.1" >&2
        return 1
    }
}

@test "data survives upgrade" {
    local pre_count
    pre_count="$(load_state "pre_upgrade_count")"
    [[ -n "$pre_count" ]] || skip "No pre-upgrade count recorded"
    [[ "$pre_count" -gt 0 ]] || skip "No data was injected before upgrade"

    local post_count
    post_count="$(opensearch_count)"

    # Allow small variance (background processes might add/remove a few docs)
    local threshold=$(( pre_count * 95 / 100 ))
    [[ "$post_count" -ge "$threshold" ]] || {
        echo "DATA LOSS: pre-upgrade had $pre_count docs, post-upgrade has $post_count docs" >&2
        echo "Threshold (95%): $threshold" >&2
        opensearch_query "/_cat/indices?v" >&2 || true
        return 1
    }
    echo "Data survived: $pre_count → $post_count documents"
}

@test "new data can be injected after upgrade" {
    require_pcap

    local before
    before="$(opensearch_count)"

    stamusctl_compose readpcap "$PCAP_FILE"
    wait_for_documents "$((before + 1))" 60 || true

    local after
    after="$(opensearch_count)"

    [[ "$after" -gt "$before" ]] || {
        echo "Document count did not increase after re-injection: $before → $after" >&2
        return 1
    }
    echo "New data indexed: $before → $after documents"
}
