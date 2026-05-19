#!/usr/bin/env bats
# LibreChat (AI Chat) integration tests
# Requires deployment with aichat.enabled=true (handled by justfile test-aichat recipe)

load "../helpers/common.bash"

@test "librechat-mongo is healthy" {
    assert_container_healthy "librechat-mongo"
}

@test "librechat-init completed successfully" {
    local container
    container="$(docker ps -a --filter "name=librechat-init" --format '{{.Names}}' | head -1)"
    [[ -n "$container" ]] || {
        echo "librechat-init container not found" >&2
        return 1
    }

    local exit_code
    exit_code="$(docker inspect --format='{{.State.ExitCode}}' "$container")"
    [[ "$exit_code" == "0" ]] || {
        echo "librechat-init exited with code $exit_code. Logs:" >&2
        docker logs "$container" >&2 || true
        return 1
    }
}

@test "scirius-token-init completed successfully" {
    local container
    container="$(docker ps -a --filter "name=scirius-token-init" --format '{{.Names}}' | head -1)"
    [[ -n "$container" ]] || {
        echo "scirius-token-init container not found" >&2
        return 1
    }

    local exit_code
    exit_code="$(docker inspect --format='{{.State.ExitCode}}' "$container")"
    [[ "$exit_code" == "0" ]] || {
        echo "scirius-token-init exited with code $exit_code. Logs:" >&2
        docker logs "$container" >&2 || true
        return 1
    }
}

@test "mcp-proxy is healthy" {
    assert_container_healthy "mcp-proxy"
}

@test "librechat is running" {
    local container
    container="$(docker ps --filter "name=librechat" --format '{{.Names}}' | grep -v mongo | grep -v init | grep -v proxy | head -1)"
    [[ -n "$container" ]] || skip "librechat container not running (port 3000 may be in use)"

    local state
    state="$(docker inspect --format='{{.State.Status}}' "$container")"
    [[ "$state" == "running" ]] || {
        echo "librechat is '$state', not running" >&2
        docker logs --tail 10 "$container" >&2 || true
        return 1
    }
    # Note: Docker healthcheck reports unhealthy because the image lacks curl.
    # The API responsiveness is verified in a separate test.
}

@test "librechat API is responding" {
    local container
    container="$(docker ps --filter "name=librechat" --format '{{.Names}}' | grep -v mongo | grep -v init | grep -v proxy | head -1)"
    [[ -n "$container" ]] || skip "librechat container not running (port 3000 may be in use)"

    # LibreChat image has wget and node, not curl
    run docker exec "$container" wget -qO- --timeout=5 "http://localhost:3000/" 2>&1
    [[ "$status" -eq 0 ]] || {
        # Fallback: check via node fetch
        run docker exec "$container" node -e "fetch('http://localhost:3000/').then(r=>{console.log(r.status);process.exit(r.ok?0:1)}).catch(()=>process.exit(1))"
        [[ "$status" -eq 0 ]] || {
            echo "LibreChat is not responding on port 3000:" >&2
            docker logs --tail 20 "$container" >&2 || true
            return 1
        }
    }
}

@test "librechat port 3000 is exposed on host" {
    if ss -tlnH sport = :3000 2>/dev/null | grep -q LISTEN; then
        local owner
        owner="$(docker ps --filter "publish=3000" --format '{{.Names}}' | head -1)"
        [[ "$owner" == *librechat* ]] || skip "Port 3000 is in use by $owner"
    else
        skip "Port 3000 is not listening"
    fi
    # Verify port is reachable from host (use wget or curl, whichever is available)
    run bash -c 'curl -sf --max-time 5 "http://localhost:3000/" 2>/dev/null || wget -qO- --timeout=5 "http://localhost:3000/" 2>/dev/null'
    [[ "$status" -eq 0 ]] || {
        echo "Port 3000 not reachable on host:" >&2
        echo "$output" >&2
        return 1
    }
}

@test "scirius token was created in shared volume" {
    local container
    container="$(docker ps --filter "name=mcp-proxy" --format '{{.Names}}' | head -1)"
    [[ -n "$container" ]] || skip "mcp-proxy container not running"

    run docker exec "$container" cat /shared/scirius-token
    [[ "$status" -eq 0 ]] || {
        echo "Scirius token file not found in shared volume" >&2
        return 1
    }
    # Token should be non-empty
    [[ -n "$output" ]] || {
        echo "Scirius token file is empty" >&2
        return 1
    }
    echo "Token present (${#output} chars)"
}

@test "default admin user exists in MongoDB" {
    local container
    container="$(docker ps --filter "name=librechat-mongo" --format '{{.Names}}' | head -1)"
    [[ -n "$container" ]] || skip "librechat-mongo container not running"

    local result
    result="$(docker exec "$container" mongosh --quiet --eval \
        "db.getSiblingDB('LibreChat').users.findOne({email: 'admin@clearndr.local'})" 2>/dev/null)" || {
        echo "Failed to query MongoDB" >&2
        return 1
    }

    [[ "$result" != "null" && -n "$result" ]] || {
        echo "Default admin user not found in MongoDB" >&2
        return 1
    }
    echo "Admin user exists in MongoDB"
}

@test "librechat container names contain release seed" {
    local seed
    seed="$(get_release_seed)"
    [[ -n "$seed" ]] || skip "Could not determine release seed"

    for service in librechat librechat-mongo mcp-proxy; do
        local container
        container="$(docker ps -a --format '{{.Names}}' | grep "$service" | head -1)"
        [[ "$container" == *"$seed"* ]] || {
            echo "Container '$container' for service '$service' missing seed '$seed'" >&2
            return 1
        }
    done
}
