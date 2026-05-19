#!/usr/bin/env bats
# Service health, container naming, and resource naming conventions

load "../helpers/common.bash"

@test "release seed is present in container names" {
    local seed
    seed="$(get_release_seed)"
    [[ -n "$seed" ]]

    # Check several core services have the seed in their container name
    for service in opensearch scirius suricata db fluentd rabbitmq; do
        local container
        container="$(docker ps --format '{{.Names}}' | grep "$service" | head -1)"
        [[ "$container" == *"$seed"* ]] || {
            echo "Container for '$service' ($container) does not contain seed '$seed'" >&2
            return 1
        }
    done
}

@test "all volumes contain the release seed" {
    local seed
    seed="$(get_release_seed)"
    [[ -n "$seed" ]]

    # Check that volumes created by the template contain the seed
    local volumes
    volumes="$(docker volume ls --format '{{.Name}}' | grep "$seed" || true)"
    [[ -n "$volumes" ]]

    # Specific volumes that should exist
    for vol_prefix in opensearch-data scirius-data scirius-static fluentd-pos; do
        echo "$volumes" | grep -q "$vol_prefix" || {
            echo "Expected volume with prefix '$vol_prefix' containing seed '$seed'" >&2
            echo "Available volumes:" >&2
            echo "$volumes" >&2
            return 1
        }
    done
}

@test "docker compose project is named with clearndr prefix" {
    local projects
    projects="$(docker compose ls --format json 2>/dev/null || docker compose ls 2>/dev/null)"
    echo "$projects" | grep -qi "clearndr" || {
        echo "No Docker Compose project with 'clearndr' prefix found" >&2
        echo "$projects" >&2
        return 1
    }
}

@test "network is named clearndr-<seed>" {
    local seed
    seed="$(get_release_seed)"
    [[ -n "$seed" ]]

    docker network ls --format '{{.Name}}' | grep -q "clearndr-${seed}" || {
        echo "Expected network 'clearndr-${seed}'" >&2
        docker network ls --format '{{.Name}}' >&2
        return 1
    }
}

@test "no containers are in restart loop" {
    local restarting
    restarting="$(docker ps --filter "status=restarting" --format '{{.Names}}' || true)"
    [[ -z "$restarting" ]] || {
        echo "Containers in restart loop:" >&2
        echo "$restarting" >&2
        return 1
    }
}
