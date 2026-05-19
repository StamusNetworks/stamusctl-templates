#!/usr/bin/env bash
# Common helpers for Bats integration tests

# --- Configuration ---
export STAMUSCTL_BIN="${STAMUSCTL_BIN:-stamusctl}"
export TEMPLATE_PATH="${TEMPLATE_PATH:-$(cd "$(dirname "${BATS_TEST_DIRNAME}")/.." && pwd)/data/clearndr}"
export TEST_CONFIG="${TEST_CONFIG:-$(cd "$(dirname "${BATS_TEST_DIRNAME}")" && pwd)/config}"
export STARTUP_TIMEOUT="${STARTUP_TIMEOUT:-300}"
export INDEX_WAIT="${INDEX_WAIT:-30}"
export PCAP_FILE="${PCAP_FILE:-}"

# --- stamusctl wrappers ---

stamusctl_cmd() {
    "$STAMUSCTL_BIN" "$@" -c "$TEST_CONFIG"
}

stamusctl_compose() {
    stamusctl_cmd compose "$@"
}

# --- Health / readiness ---

# Poll stamusctl compose ps until all services are running/healthy.
# Skips init containers (restart: "no") that have exited successfully.
wait_for_healthy() {
    local timeout="${1:-$STARTUP_TIMEOUT}"
    local interval=15
    local elapsed=0

    while (( elapsed < timeout )); do
        local output
        output="$(stamusctl_compose ps 2>&1)" || true

        # Fail-fast: skip if no output or error
        if [[ -z "$output" ]] || echo "$output" | grep -q "no such file"; then
            sleep "$interval"
            elapsed=$(( elapsed + interval ))
            continue
        fi

        # Check for containers still starting or unhealthy
        local not_ready=false

        # "health: starting" means healthcheck hasn't passed yet
        if echo "$output" | grep -qi "health: starting"; then
            not_ready=true
        fi

        # Check for containers in error/restart states (but not just unhealthy —
        # unhealthy containers may have broken healthchecks while running fine)
        if echo "$output" | grep -qiE '(Exit [1-9]|Restarting|Dead)'; then
            not_ready=true
        fi

        # Note: "Created" containers (e.g. port conflicts) are ignored —
        # the stack is considered healthy if all started containers are healthy.

        # If nothing is not-ready and we have running services, we're good
        if ! $not_ready && echo "$output" | grep -qiE '(running|healthy|Up)'; then
            return 0
        fi

        sleep "$interval"
        elapsed=$(( elapsed + interval ))
    done

    echo "Timeout after ${timeout}s waiting for services to be healthy" >&2
    echo "Last status:" >&2
    stamusctl_compose ps >&2 || true
    return 1
}

# --- Container discovery ---

get_opensearch_container() {
    docker ps --filter "name=opensearch" --format '{{.Names}}' | grep -v dashboard | head -1
}

get_dashboards_container() {
    docker ps --filter "name=opensearch-dashboards" --format '{{.Names}}' | head -1
}

get_container_by_service() {
    local service="$1"
    docker ps --filter "name=${service}" --format '{{.Names}}' | head -1
}

# --- OpenSearch queries ---

opensearch_query() {
    local endpoint="$1"
    local container
    container="$(get_opensearch_container)"
    [[ -n "$container" ]] || { echo "opensearch container not found" >&2; return 1; }
    docker exec "$container" curl -sf "http://localhost:9200${endpoint}"
}

opensearch_count() {
    local result
    result="$(opensearch_query "/_count")" || return 1
    echo "$result" | grep -oP '"count"\s*:\s*\K\d+'
}

opensearch_health() {
    local result
    result="$(opensearch_query "/_cluster/health")" || return 1
    echo "$result" | grep -oP '"status"\s*:\s*"\K[^"]+'
}

opensearch_version() {
    local result
    result="$(opensearch_query "/")" || return 1
    echo "$result" | grep -oP '"number"\s*:\s*"\K[^"]+'
}

# Wait for OpenSearch indexing to settle (simple sleep)
wait_for_indexing() {
    local wait="${1:-$INDEX_WAIT}"
    sleep "$wait"
}

# Poll OpenSearch until document count > threshold or timeout
# Usage: wait_for_documents [min_count] [timeout]
wait_for_documents() {
    local min="${1:-1}"
    local timeout="${2:-60}"
    local interval=5
    local elapsed=0

    while (( elapsed < timeout )); do
        local count
        count="$(opensearch_count 2>/dev/null)" || count=0
        if [[ "$count" -ge "$min" ]]; then
            return 0
        fi
        sleep "$interval"
        elapsed=$(( elapsed + interval ))
    done
    echo "Timeout after ${timeout}s waiting for documents (need >= $min, have $(opensearch_count 2>/dev/null || echo 0))" >&2
    return 1
}

# Resolve the actual containers-data path (follows symlinks)
containers_data_path() {
    local base="${TEST_CONFIG}/containers-data"
    if [[ -L "$base" ]]; then
        readlink -f "$base"
    elif [[ -d "$base" ]]; then
        echo "$base"
    else
        # Fallback: try the broken double-absolute path
        local broken
        broken="$(pwd)/${TEST_CONFIG#/}/containers-data"
        if [[ -d "$broken" ]]; then
            echo "$broken"
        else
            echo "$base"  # return expected path for error messages
        fi
    fi
}

# Check if eve.json has events (direct filesystem check, bypasses fluentd/opensearch)
eve_json_has_events() {
    local eve="$(containers_data_path)/suricata/logs/eve.json"
    [[ -f "$eve" ]] && [[ -s "$eve" ]]
}

# Get eve.json path
eve_json_path() {
    echo "$(containers_data_path)/suricata/logs/eve.json"
}

# --- PCAP helpers ---

find_pcap() {
    if [[ -n "$PCAP_FILE" && -f "$PCAP_FILE" ]]; then
        echo "$PCAP_FILE"
        return 0
    fi
    # Check for bundled fixture PCAPs
    local fixtures_dir
    fixtures_dir="$(cd "$(dirname "${BATS_TEST_DIRNAME}")" && pwd)/fixtures"
    if [[ -d "$fixtures_dir" ]]; then
        local fixture
        fixture="$(ls -t "$fixtures_dir"/*.pcap 2>/dev/null | head -1)"
        if [[ -n "$fixture" ]]; then
            echo "$fixture"
            return 0
        fi
    fi
    # Fallback: check ~/Downloads
    local found
    found="$(ls -t ~/Downloads/*.pcap ~/Downloads/*.pcapng 2>/dev/null | head -1)"
    if [[ -n "$found" ]]; then
        echo "$found"
        return 0
    fi
    return 1
}

require_pcap() {
    local pcap
    pcap="$(find_pcap)" || skip "No PCAP file found. Set PCAP_FILE or place one in ~/Downloads/"
    PCAP_FILE="$pcap"
    export PCAP_FILE
}

# --- Assertions ---

assert_service_running() {
    local service="$1"
    local output
    output="$(stamusctl_compose ps 2>&1)"
    echo "$output" | grep -qi "$service" || {
        echo "Service '$service' not found in compose ps output:" >&2
        echo "$output" >&2
        return 1
    }
    # Check it's not in an error state
    echo "$output" | grep -i "$service" | grep -qivE '(Exit [1-9]|Restarting|Dead)' || {
        echo "Service '$service' is in an error state:" >&2
        echo "$output" | grep -i "$service" >&2
        return 1
    }
}

assert_container_exists() {
    local pattern="$1"
    docker ps -a --format '{{.Names}}' | grep -q "$pattern" || {
        echo "No container matching '$pattern' found" >&2
        docker ps -a --format '{{.Names}}' >&2
        return 1
    }
}

assert_container_healthy() {
    local pattern="$1"
    local container
    container="$(docker ps --filter "name=${pattern}" --format '{{.Names}}' | head -1)"
    [[ -n "$container" ]] || { echo "Container '$pattern' not found" >&2; return 1; }

    local health
    health="$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null)" || true

    # Containers without healthcheck are considered OK if running
    if [[ "$health" == "healthy" ]] || [[ -z "$health" ]]; then
        local state
        state="$(docker inspect --format='{{.State.Status}}' "$container")"
        [[ "$state" == "running" ]] || { echo "Container '$container' is '$state', not running" >&2; return 1; }
        return 0
    fi

    [[ "$health" == "healthy" ]] || {
        echo "Container '$container' health is '$health', not healthy" >&2
        return 1
    }
}

# Get the release seed from the running deployment
get_release_seed() {
    # Extract seed from a container name: clearndr-<service>-<seed>
    local container
    container="$(docker ps --format '{{.Names}}' | grep 'opensearch' | grep -v dashboard | head -1)"
    [[ -n "$container" ]] || return 1
    # Container name format: <release-name>-opensearch-<seed>
    echo "$container" | sed 's/.*-opensearch-//'
}

# --- readpcap path fix ---
# Workaround for stamusctl readpcap path bug: creates symlink from
# clean config path to actual broken double-absolute path
fix_readpcap_paths() {
    local config="${TEST_CONFIG}"
    if [[ "$config" == /* ]]; then
        local broken_base
        broken_base="$(pwd)/${config#/}/containers-data"
        local clean="$config/containers-data"
        if [[ -d "$broken_base" ]] && [[ ! -e "$clean" ]]; then
            ln -sf "$broken_base" "$clean"
        fi
    fi
}

# --- State file for cross-test communication ---

STATE_DIR="${BATS_SUITE_TMPDIR:-/tmp/bats-test-state}"

save_state() {
    mkdir -p "$STATE_DIR"
    echo "$2" > "${STATE_DIR}/$1"
}

load_state() {
    cat "${STATE_DIR}/$1" 2>/dev/null
}
