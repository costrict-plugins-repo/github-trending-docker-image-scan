# Docker Image Scan

A [Claude Code](https://claude.com/claude-code) plugin that builds, scans, and analyzes container images for security vulnerabilities using [Trivy](https://github.com/aquasecurity/trivy) — with **no local Trivy installation required**.

Supports both **Docker** and **Podman** as the container runtime.

## What it does

`Docker Image Scan` automates the full container security workflow:

1. **Detect** the available container runtime (Docker or Podman)
2. **Build** the image from a Dockerfile
3. **Scan** for vulnerabilities using Trivy (pulled and run as a container)
4. **Report** findings with severity breakdown, CVE details, and fix recommendations
5. **Clean up** both the scanned image and the Trivy container image

Claude analyzes the raw scan results and provides actionable recommendations — base image upgrades, package fixes, and Dockerfile improvements.

## Prerequisites

One of the following container runtimes:

- [Docker](https://docs.docker.com/get-docker/)
- [Podman](https://podman.io/docs/installation)

That's it. Trivy is automatically pulled and run as a container — no separate installation needed.

## Installation

Add the official community marketplace and install:

```
/plugin marketplace add anthropics/claude-plugins-community
/plugin install docker-image-scan@claude-community
```

## Usage

### Scan a Dockerfile

```
/docker-image-scan:scan ./Dockerfile
```

### Scan a Dockerfile in a subdirectory

```
/docker-image-scan:scan ./docker/Dockerfile
```

## Example output

```
Container runtime detected: docker

Building image from ./Dockerfile...
Successfully built claude-scan-1710000000

Vulnerability Report for claude-scan-1710000000

| Severity | Count |
|----------|-------|
| CRITICAL | 2     |
| HIGH     | 5     |
| MEDIUM   | 12    |
| LOW      | 31    |

Critical Findings:
  CVE-2023-44487  curl 7.88.1  → Fix: upgrade to 8.4.0
  CVE-2023-38545  libssl3 3.0  → Fix: upgrade to 3.0.12

Recommendations:
  - Upgrade base image to nginx:1.27-alpine
  - Update curl and openssl packages

Cleanup complete: removed scanned image and Trivy image.
```

## How it works

The plugin is a Claude Code skill (`skills/scan/SKILL.md`) that delegates the entire build/scan/cleanup workflow to a single bundled bash script (`scripts/scan.sh`). This means you only see **one** permission prompt per scan, instead of one for each underlying shell command.

When invoked, the script:

1. Detects whether Docker or Podman is installed (prefers Docker if both are available and the Docker daemon is running)
2. Builds your container image from the provided Dockerfile
3. Pulls `aquasec/trivy:latest` and runs it as a container to scan the built image
4. Writes the JSON scan results to a temporary file
5. Removes both the built image and the `aquasec/trivy:latest` image (via a bash `EXIT` trap, so cleanup runs even if the scan fails)

Claude then reads the JSON results and presents a structured report.

No data leaves your machine — everything runs locally via your container runtime. (Trivy itself downloads its CVE database from `ghcr.io/aquasecurity/trivy-db` on each scan; see [Privacy](#privacy) below.)

## Skip the permission prompt entirely (optional)

To approve the scan script once and never see the prompt again, add this to your `~/.claude/settings.json` (or `.claude/settings.json` per project):

```json
{
  "permissions": {
    "allow": [
      "Bash(bash *scripts/scan.sh *)"
    ]
  }
}
```

This allows only the bundled scan script. It does **not** grant blanket access to Docker, Podman, or any other shell command.

## Privacy

This plugin runs entirely on your local machine. It does not collect, transmit, store, or share any user data.

- No telemetry
- No analytics
- No data sent to the plugin author or any third party
- Scan results are written to a local temporary file that is deleted after the report is presented
- Built images and the Trivy container image are removed from your local machine after the scan

The plugin itself initiates no network traffic. However, the tools it invokes do reach the internet for the following reasons:

- Your container runtime pulls the `aquasec/trivy:latest` image from its configured registry (Docker Hub by default) when it is not already cached
- Trivy itself downloads its vulnerability database (~50MB) from `ghcr.io/aquasecurity/trivy-db` on each scan unless the cache is fresh. If the image contains Java artifacts, Trivy also fetches `ghcr.io/aquasecurity/trivy-java-db`
- The base images referenced in your Dockerfile are pulled by your container runtime during the build

All of these are user-controlled — they go to the registries you have configured, not to the plugin author.

## License

MIT
