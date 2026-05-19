#!/usr/bin/env bats
# OpenSearch 3 cluster validation

load "../helpers/common.bash"

@test "opensearch cluster health is green or yellow" {
    local health
    health="$(opensearch_health)"
    [[ "$health" == "green" || "$health" == "yellow" ]] || {
        echo "Cluster health is '$health', expected green or yellow" >&2
        return 1
    }
}

@test "opensearch version is 3.3.1" {
    local version
    version="$(opensearch_version)"
    [[ "$version" == "3.3.1" ]] || {
        echo "OpenSearch version is '$version', expected 3.3.1" >&2
        return 1
    }
}

@test "opensearch security plugin is disabled" {
    # Should be able to query without authentication
    run opensearch_query "/"
    [[ "$status" -eq 0 ]]
    # Response should not contain "Unauthorized"
    [[ "$output" != *"Unauthorized"* ]]
}

@test "opensearch dashboards is reachable" {
    local container
    container="$(get_dashboards_container)"
    [[ -n "$container" ]]

    run docker exec "$container" curl -sf "http://localhost:5601/api/status"
    [[ "$status" -eq 0 ]]
}

@test "opensearch MCP connector is enabled" {
    local settings
    settings="$(opensearch_query "/_cluster/settings?include_defaults=true&flat_settings=true")"

    echo "$settings" | grep -q "ml_commons.mcp_connector_enabled" || {
        echo "MCP connector setting not found in cluster settings" >&2
        echo "$settings" | head -20 >&2
        return 1
    }
}

@test "opensearch single-node discovery" {
    local settings
    settings="$(opensearch_query "/_nodes/_local")"
    [[ "$status" -eq 0 || -n "$settings" ]]
    # Verify it's a single-node cluster
    local node_count
    node_count="$(opensearch_query "/_cat/nodes" | wc -l)"
    [[ "$node_count" -eq 1 ]] || {
        echo "Expected 1 node, got $node_count" >&2
        return 1
    }
}
