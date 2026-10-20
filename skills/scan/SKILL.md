---
name: scan
description: Build a container image from a Dockerfile, scan it for security vulnerabilities using Trivy (via Docker or Podman), and clean up all images afterward.
---

# Container Image Security Scanner

Scan container images for vulnerabilities using Trivy. The entire build/scan/cleanup workflow runs as a single bundled bash script, so the user only sees one permission prompt per scan instead of one per shell command.

## Input

The user provides a **path to a Dockerfile**. The input is passed via `$ARGUMENTS`.

Examples:
- `/docker-image-scan:scan ./Dockerfile`
- `/docker-image-scan:scan ./docker/Dockerfile`
- `/docker-image-scan:scan /absolute/path/to/Dockerfile`

## Workflow

### Step 1 — Validate input

- If `$ARGUMENTS` is empty, ask the user to provide a path to a Dockerfile and stop.
- The script itself verifies the file exists and the runtime is available, so no further pre-checks are needed.

### Step 2 — Run the scan script

Execute the bundled script with the Dockerfile path:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/scan.sh" "$ARGUMENTS"
```

What the script does (for your awareness — do not replicate these steps manually):

1. Detects Docker or Podman (prefers Docker if both are available and the Docker daemon is running)
2. Builds the image with a unique tag like `claude-scan-<timestamp>-<pid>`
3. Runs Trivy as a container — via the Docker socket on Docker, or via an exported tarball on Podman
4. Writes scan results to a stable path under `/tmp/`
5. Removes the built image, the Trivy container image, and any temporary directories — even if the scan failed (via a bash `EXIT` trap)
6. Prints the results path as the **last line of stdout**

### Step 3 — Handle the script result

**On success (exit code 0):**
- Read the JSON file at the path printed on the last line of stdout
- Parse the vulnerability data into memory

**On failure (non-zero exit):**
- Inspect stderr for the error message and exit code
- Common exit codes the script uses: `2` (bad input), `3` (no runtime), `4` (Docker daemon not running), `5` (build failed), `6` (scan failed)
- Surface the error to the user clearly. Do not retry automatically.

### Step 4 — Present the report

**Summary table:**

| Severity | Count |
|----------|-------|
| CRITICAL | N     |
| HIGH     | N     |
| MEDIUM   | N     |
| LOW      | N     |

**Critical and High findings** — list each with:
- Package name and installed version
- Vulnerability ID (CVE)
- Fixed version (if available)
- Brief description

**Recommendations:**
- Suggest base image upgrades if the base image has known vulnerabilities
- Suggest package updates for fixable vulnerabilities
- Highlight any vulnerabilities with known exploits
- Suggest specific Dockerfile changes based on the provided Dockerfile

### Step 5 — Remove the results file

After presenting the report, remove the temporary results file:

```bash
rm -f <results-path-from-step-2>
```

## Important rules

- The script handles all runtime detection, building, scanning, and cleanup. Do not run `docker`, `podman`, `mktemp`, or `rm` commands directly — call the script and let it do the work.
- If the scan finds zero vulnerabilities, congratulate the user and confirm the image is clean.
- Keep the report concise — group LOW severity findings into a single count rather than listing each one.
- For very large reports, focus on CRITICAL and HIGH severity items and summarize the rest.
