#!/usr/bin/env bats
# Data pipeline: PCAP injection → Suricata → Fluentd → OpenSearch indexing

load "../helpers/common.bash"

setup() {
    require_pcap
}

@test "readpcap injects data without error" {
    run stamusctl_compose readpcap "$PCAP_FILE"
    [[ "$status" -eq 0 ]] || {
        echo "readpcap failed with status $status:" >&2
        echo "$output" >&2
        return 1
    }
    # Verify suricata actually processed events
    if ! eve_json_has_events; then
        echo "WARNING: eve.json is missing or empty after readpcap" >&2
        echo "readpcap output:" >&2
        echo "$output" | tail -10 >&2
    fi
}

@test "suricata wrote events to eve.json" {
    # Direct filesystem check — isolates readpcap issues from fluentd/opensearch
    local eve
    eve="$(eve_json_path)"
    [[ -f "$eve" ]] || {
        echo "eve.json not found at $eve" >&2
        local data_dir
        data_dir="$(containers_data_path)"
        echo "containers-data path: $data_dir" >&2
        ls -la "${data_dir}/suricata/logs/" >&2 || true
        return 1
    }
    [[ -s "$eve" ]] || {
        echo "eve.json exists but is empty" >&2
        return 1
    }
    local line_count
    line_count="$(wc -l < "$eve")"
    echo "eve.json has $line_count lines"
}

@test "opensearch has indexed documents after injection" {
    # Poll instead of fixed sleep — handles variable fluentd/opensearch latency
    wait_for_documents 1 60 || {
        echo "OpenSearch document count is 0 after PCAP injection" >&2
        echo "Checking if events are in eve.json..." >&2
        local eve
        eve="$(eve_json_path)"
        if [[ -f "$eve" ]]; then
            echo "eve.json has $(wc -l < "$eve") lines (events exist but fluentd may not be forwarding)" >&2
        else
            echo "eve.json not found (readpcap may have failed silently)" >&2
        fi
        echo "Fluentd logs:" >&2
        local fluentd_container
        fluentd_container="$(get_container_by_service "fluentd")"
        [[ -n "$fluentd_container" ]] && docker logs --tail 10 "$fluentd_container" >&2 || true
        echo "Indices:" >&2
        opensearch_query "/_cat/indices?v" >&2 || true
        return 1
    }

    local count
    count="$(opensearch_count)"
    # Save baseline count for upgrade tests
    save_state "baseline_count" "$count"
    echo "Indexed $count documents"
}

@test "logstash indices exist in opensearch" {
    local indices
    indices="$(opensearch_query "/_cat/indices?v")"

    echo "$indices" | grep -q "logstash" || {
        echo "No logstash indices found:" >&2
        echo "$indices" >&2
        return 1
    }
}

@test "suricata generated alerts from PCAP" {
    # Poll for alert events — fluentd buffers by event_type and may need time to flush
    local timeout=60
    local interval=5
    local elapsed=0
    local hit_count=0

    while (( elapsed < timeout )); do
        local result
        result="$(opensearch_query '/_search?q=event_type:alert&size=1')" || true
        hit_count="$(echo "$result" | grep -oP '"total"\s*:\s*\{"value"\s*:\s*\K\d+')" || hit_count=0
        [[ "$hit_count" -gt 0 ]] && break
        sleep "$interval"
        elapsed=$(( elapsed + interval ))
    done

    [[ "$hit_count" -gt 0 ]] || {
        echo "No Suricata alerts found in OpenSearch after ${timeout}s" >&2
        echo "The test PCAPs (EternalBlue/EternalRomance) should trigger ET Open rules" >&2
        # Check eve.json directly for alerts
        local eve
        eve="$(eve_json_path)"
        if [[ -f "$eve" ]]; then
            local eve_alerts
            eve_alerts="$(grep -c '"event_type":"alert"' "$eve" 2>/dev/null)" || eve_alerts=0
            echo "eve.json has $eve_alerts alert events (fluentd may not be forwarding them)" >&2
        fi
        echo "Total documents in OpenSearch:" >&2
        opensearch_count >&2 || true
        return 1
    }
    echo "Found $hit_count alert events in OpenSearch"
}

@test "fluentd container is not in error state" {
    local container
    container="$(get_container_by_service "fluentd")"
    [[ -n "$container" ]]

    local state
    state="$(docker inspect --format='{{.State.Status}}' "$container")"
    [[ "$state" == "running" ]] || {
        echo "Fluentd is '$state', not running. Logs:" >&2
        docker logs --tail 20 "$container" >&2 || true
        return 1
    }
}
