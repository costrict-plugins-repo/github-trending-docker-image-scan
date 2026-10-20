#!/usr/bin/env bash
#
# Build a container image from a Dockerfile, scan it with Trivy
# (run as a container), and clean up. Writes scan results to a JSON
# file and prints the file path on the last line of stdout.
#
# Usage: scan.sh <dockerfile-path>
# Exit codes:
#   0 - success
#   2 - invalid input
#   3 - no container runtime available
#   4 - container runtime not usable (daemon not running, etc.)
#   5 - image build failed
#   6 - scan failed

set -euo pipefail

DOCKERFILE_PATH="${1:-}"

if [[ -z "$DOCKERFILE_PATH" ]]; then
    echo "Error: no Dockerfile path provided" >&2
    echo "Usage: scan.sh <dockerfile-path>" >&2
    exit 2
fi

if [[ ! -f "$DOCKERFILE_PATH" ]]; then
    echo "Error: Dockerfile not found at: $DOCKERFILE_PATH" >&2
    exit 2
fi

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    RUNTIME="docker"
elif command -v podman >/dev/null 2>&1; then
    RUNTIME="podman"
elif command -v docker >/dev/null 2>&1; then
    echo "Error: docker is installed but the daemon is not running." >&2
    echo "Start Docker and try again, or install Podman." >&2
    exit 4
else
    echo "Error: neither docker nor podman is available." >&2
    echo "Install one of:" >&2
    echo "  - Docker: https://docs.docker.com/get-docker/" >&2
    echo "  - Podman: https://podman.io/docs/installation" >&2
    exit 3
fi

echo "Runtime: $RUNTIME" >&2

SCAN_TAG="claude-scan-$(date +%s)-$$"
SCAN_DIR=$(mktemp -d -t claude-image-scan.XXXXXX)
RESULTS_FILE="/tmp/claude-image-scan-results-$$.json"

cleanup() {
    "$RUNTIME" rmi "$SCAN_TAG" >/dev/null 2>&1 || true
    "$RUNTIME" rmi aquasec/trivy:latest >/dev/null 2>&1 || true
    rm -rf "$SCAN_DIR"
}
trap cleanup EXIT

BUILD_CONTEXT=$(dirname "$DOCKERFILE_PATH")

echo "Building image: $SCAN_TAG" >&2
if ! "$RUNTIME" build -t "$SCAN_TAG" -f "$DOCKERFILE_PATH" "$BUILD_CONTEXT" >&2; then
    echo "Error: image build failed." >&2
    exit 5
fi

echo "Scanning with Trivy..." >&2
if [[ "$RUNTIME" == "docker" ]]; then
    if ! docker run --rm \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v "$SCAN_DIR:/output" \
        aquasec/trivy:latest image \
            --format json \
            --output /output/trivy-results.json \
            --severity CRITICAL,HIGH,MEDIUM,LOW \
            "$SCAN_TAG" >&2; then
        echo "Error: Trivy scan failed." >&2
        exit 6
    fi
else
    if ! podman save -o "$SCAN_DIR/image.tar" "$SCAN_TAG" >&2; then
        echo "Error: podman save failed." >&2
        exit 6
    fi
    if ! podman run --rm \
        -v "$SCAN_DIR:/scan" \
        aquasec/trivy:latest image \
            --input /scan/image.tar \
            --format json \
            --output /scan/trivy-results.json \
            --severity CRITICAL,HIGH,MEDIUM,LOW >&2; then
        echo "Error: Trivy scan failed." >&2
        exit 6
    fi
fi

cp "$SCAN_DIR/trivy-results.json" "$RESULTS_FILE"

echo "$RESULTS_FILE"
