# stamusctl-public-templates
# Top-level task runner — delegates to sub-justfiles and wraps common commands.

set shell := ["bash", "-euo", "pipefail", "-c"]

# Template variants
templates := "clearndr tests"

# Default template for build/dev commands
default_template := "clearndr"

# --- Default ---

# List available recipes
default:
    @just --list

# --- Build ---

# Build Go hooks for a template (default: clearndr)
build-hooks template=default_template:
    make -C bin/{{template}}

# Build Go hooks for all templates
build-hooks-all:
    #!/usr/bin/env bash
    set -euo pipefail
    for t in {{templates}}; do
        if [[ -d "bin/$t" ]]; then
            echo "==> Building hooks for $t"
            make -C "bin/$t"
        fi
    done

# Build template Docker image (default: clearndr)
build-image template=default_template:
    docker build . -f Dockerfile --build-arg path={{template}} -t template:{{template}}

# Build all template Docker images
build-image-all:
    #!/usr/bin/env bash
    set -euo pipefail
    for t in {{templates}}; do
        echo "==> Building image for $t"
        docker build . -f Dockerfile --build-arg path="$t" -t "template:$t"
    done

# Build everything (hooks + images) for a template
build template=default_template: (build-hooks template) (build-image template)

# Build everything for all templates
build-all: build-hooks-all build-image-all

# --- Lint / Validate ---

# Lint Dockerfile with hadolint
lint-dockerfile:
    hadolint Dockerfile

# Lint a commit (pass SHA or "HEAD")
lint-commit sha="HEAD":
    pnpm run lint-commit:one {{sha}}

# Validate YAML files with yamllint (if available)
lint-yaml:
    @command -v yamllint >/dev/null 2>&1 || { echo "yamllint not found — skipping"; exit 0; }
    find data/ -name '*.yaml' -o -name '*.yml' | xargs yamllint

# Run all available linters
lint: lint-dockerfile lint-yaml

# --- Test ---

# Run integration tests (delegates to tests/justfile)
test *args:
    just -f tests/justfile {{args}}

# Run a specific test group (e.g., just test-group opensearch)
test-group group:
    just -f tests/justfile test-{{group}}

# Check test prerequisites
test-check:
    just -f tests/justfile check

# Show test stack status
test-status:
    just -f tests/justfile status

# Show test stack logs
test-logs service="":
    just -f tests/justfile logs {{service}}

# Tear down test stack
test-teardown:
    just -f tests/justfile teardown

# --- Dev ---

# Enter nix dev shell
dev:
    nix develop

# Install Node.js deps (for commitlint/semantic-release)
install:
    pnpm install

# Clean build artifacts
clean:
    rm -rf bin/*/dist
    @echo "Cleaned build artifacts"
