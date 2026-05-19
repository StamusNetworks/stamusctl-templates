#!/usr/bin/env bats
# Stack initialization and startup health checks

load "../helpers/common.bash"

@test "all core services are running" {
    wait_for_healthy "$STARTUP_TIMEOUT"
}

@test "opensearch is healthy" {
    assert_service_running "opensearch"
}

@test "opensearch-dashboards is healthy" {
    assert_service_running "opensearch-dashboards"
}

@test "scirius is healthy" {
    assert_service_running "scirius"
}

@test "suricata is running" {
    assert_service_running "suricata"
}

@test "fluentd is running" {
    assert_service_running "fluentd"
}

@test "nginx is running" {
    # nginx binds to port 80; skip if port is in use by a non-stack process
    if ss -tlnH sport = :80 2>/dev/null | grep -q LISTEN; then
        local owner
        owner="$(docker ps --filter "publish=80" --format '{{.Names}}' | head -1)"
        if [[ -z "$owner" ]] || ! echo "$owner" | grep -q "nginx"; then
            skip "Port 80 is in use by another process"
        fi
    fi
    assert_service_running "nginx"
}

@test "db (postgres) is running" {
    assert_service_running "db"
}
