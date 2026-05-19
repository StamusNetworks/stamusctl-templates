#!/usr/bin/env bats
# Scirius web UI: nginx reverse proxy, authentication, REST API

load "../helpers/common.bash"

MANAGE_PY="/code/manage.py"

# --- Nginx reverse proxy ---

@test "nginx proxies to scirius (direct container check)" {
    local nginx
    nginx="$(get_container_by_service "nginx")"
    [[ -n "$nginx" ]] || skip "nginx container not running"

    # curl from inside nginx to scirius on the compose network
    run docker exec "$nginx" curl -sf -o /dev/null -w '%{http_code}' \
        "http://scirius:8000/" --max-time 10
    [[ "$status" -eq 0 ]] || {
        echo "nginx cannot reach scirius:8000 on compose network" >&2
        echo "HTTP status: $output" >&2
        return 1
    }
    # Scirius redirects unauthenticated requests to login
    [[ "$output" =~ ^(200|301|302)$ ]] || {
        echo "Unexpected HTTP status from scirius: $output" >&2
        return 1
    }
}

@test "nginx HTTPS terminates correctly" {
    local nginx
    nginx="$(get_container_by_service "nginx")"
    [[ -n "$nginx" ]] || skip "nginx container not running"

    # Check SSL from inside nginx (self-signed cert, so -k)
    run docker exec "$nginx" curl -skf -o /dev/null -w '%{http_code}' \
        "https://localhost/" --max-time 10
    [[ "$status" -eq 0 ]] || {
        echo "HTTPS not working on nginx: $output" >&2
        return 1
    }
    [[ "$output" =~ ^(200|301|302)$ ]]
}

# --- Scirius application ---

@test "scirius responds on port 8000" {
    local scirius
    scirius="$(get_container_by_service "scirius")"
    [[ -n "$scirius" ]] || skip "scirius container not running"

    run docker exec "$scirius" curl -sf -o /dev/null -w '%{http_code}' \
        "http://localhost:8000/" --max-time 10
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ ^(200|301|302)$ ]] || {
        echo "Scirius returned HTTP $output" >&2
        return 1
    }
}

@test "scirius login page is accessible" {
    local scirius
    scirius="$(get_container_by_service "scirius")"
    [[ -n "$scirius" ]] || skip "scirius container not running"

    run docker exec "$scirius" curl -sf "http://localhost:8000/accounts/login/" --max-time 10
    [[ "$status" -eq 0 ]] || {
        echo "Login page not accessible (status $status)" >&2
        echo "$output" | tail -5 >&2
        return 1
    }
    # Should contain a login form
    echo "$output" | grep -qi "login\|password\|csrfmiddlewaretoken" || {
        echo "Login page doesn't contain expected form elements" >&2
        echo "$output" | head -20 >&2
        return 1
    }
}

# --- Authentication ---

@test "scirius default user exists" {
    local scirius
    scirius="$(get_container_by_service "scirius")"
    [[ -n "$scirius" ]] || skip "scirius container not running"

    run docker exec "$scirius" python "$MANAGE_PY" shell -c \
        "from django.contrib.auth.models import User; u = User.objects.get(username='clearndr'); print(f'user={u.username} active={u.is_active} staff={u.is_staff}')"
    [[ "$status" -eq 0 ]] || {
        echo "Default user 'clearndr' not found:" >&2
        echo "$output" >&2
        return 1
    }
    echo "$output" | grep -q "user=clearndr" || {
        echo "Unexpected output: $output" >&2
        return 1
    }
    echo "$output"
}

@test "scirius login with default credentials succeeds" {
    local scirius
    scirius="$(get_container_by_service "scirius")"
    [[ -n "$scirius" ]] || skip "scirius container not running"

    # Django login requires CSRF token — fetch it from the login page first
    docker exec "$scirius" curl -sf -c /tmp/test-cookies \
        "http://localhost:8000/accounts/login/" --max-time 10 > /dev/null || {
        echo "Failed to fetch login page" >&2
        return 1
    }

    local csrf
    csrf="$(docker exec "$scirius" cat /tmp/test-cookies 2>/dev/null | grep csrftoken | awk '{print $NF}')" || true

    [[ -n "$csrf" ]] || {
        echo "Could not extract CSRF token from login page cookies" >&2
        return 1
    }

    # POST login with default credentials — 302 redirect means success
    local http_code
    http_code="$(docker exec "$scirius" curl -sf -o /dev/null -w '%{http_code}' \
        -b /tmp/test-cookies -c /tmp/test-cookies \
        -X POST "http://localhost:8000/accounts/login/" \
        -H "Referer: http://localhost:8000/accounts/login/" \
        -d "csrfmiddlewaretoken=${csrf}&username=clearndr&password=clearndr" \
        --max-time 10)" || {
        echo "Login POST failed" >&2
        return 1
    }

    [[ "$http_code" == "302" ]] || {
        echo "Login returned HTTP $http_code (expected 302 redirect on success)" >&2
        return 1
    }

    # Verify the redirect target is accessible with our session
    run docker exec "$scirius" curl -sf -o /dev/null -w '%{http_code}' \
        -b /tmp/test-cookies -L \
        "http://localhost:8000/" --max-time 10
    [[ "$output" == "200" ]] || {
        echo "Authenticated request returned HTTP $output (expected 200)" >&2
        return 1
    }

    # Clean up
    docker exec "$scirius" rm -f /tmp/test-cookies 2>/dev/null || true
    echo "Login successful (clearndr/clearndr → 302 → 200)"
}

@test "scirius REST API returns data after auth" {
    local scirius
    scirius="$(get_container_by_service "scirius")"
    [[ -n "$scirius" ]] || skip "scirius container not running"

    # Generate a REST API token via Django
    local token
    token="$(docker exec "$scirius" python "$MANAGE_PY" shell -c \
        "from django.contrib.auth.models import User; from rest_framework.authtoken.models import Token; u = User.objects.get(username='clearndr'); t, _ = Token.objects.get_or_create(user=u); print(t.key)" 2>/dev/null | tail -1)" || true

    [[ -n "$token" ]] || {
        echo "Failed to generate API token" >&2
        return 1
    }

    # Query the REST API with the token
    run docker exec "$scirius" curl -sf \
        -H "Authorization: Token ${token}" \
        "http://localhost:8000/rest/rules/system_settings/" --max-time 10
    [[ "$status" -eq 0 ]] || {
        echo "REST API request failed (status $status)" >&2
        echo "$output" >&2
        return 1
    }

    # Response should be JSON with data
    echo "$output" | grep -qP '^\{' || {
        echo "REST API did not return JSON:" >&2
        echo "$output" | head -5 >&2
        return 1
    }
    echo "REST API responding with token auth"
}
