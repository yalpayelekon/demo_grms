# GRMS Bundle Workflow (Windows + Linux)

This folder contains the GRMS web frontend, Go backend, and a launcher used to produce relocatable bundles for Windows and Linux.

## What gets built

- `tools/grms/flutter_grems_app` -> Flutter web build
- `tools/grms/testcomm_go` -> `testcomm_go.exe` (Windows) / `testcomm_go` (Linux)
- `tools/grms/grms_launcher` -> `grms_launcher.exe` (Windows) / `grms_launcher` (Linux)

Bundle outputs:

- `dist/grms_bundle/backend/`
- `dist/grms_bundle/frontend/web/`
- `dist/grms_bundle/launcher/`
- `dist/grms_bundle_linux/backend/`
- `dist/grms_bundle_linux/frontend/web/`
- `dist/grms_bundle_linux/launcher/`

## Build commands

### Windows

Run from repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/grms/build-grms-bundle.ps1 -Configuration release
```

Optional debug build:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/grms/build-grms-bundle.ps1 -Configuration debug
```

Optional fixed frontend API base URL override:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/grms/build-grms-bundle.ps1 -Configuration release -FrontendApiBaseUrl http://10.11.10.91:8082
```

### Linux

Run from repository root:

```bash
chmod +x tools/grms/linux/build-grms-bundle-linux.sh
./tools/grms/linux/build-grms-bundle-linux.sh --configuration release
```

Optional debug build:

```bash
./tools/grms/linux/build-grms-bundle-linux.sh --configuration debug
```

Optional fixed frontend API base URL override:

```bash
./tools/grms/linux/build-grms-bundle-linux.sh --configuration release --frontend-api-base-url http://10.11.10.91:8082
```

Optional Raspberry Pi 64-bit build:

```bash
./tools/grms/linux/build-grms-bundle-linux.sh --configuration release --goarch arm64
```

Optional Raspberry Pi 32-bit ARMv7 build:

```bash
./tools/grms/linux/build-grms-bundle-linux.sh --configuration release --goarch arm --goarm 7
```

## Run bundled app

### Windows

```powershell
cd dist/grms_bundle
.\launcher\grms_launcher.exe
```

### Linux

```bash
cd dist/grms_bundle_linux
./start-grms.sh
```

For ARM builds, use the matching output directory instead:

- `dist/grms_bundle_linux_arm64`
- `dist/grms_bundle_linux_armv7`

Launcher behavior:

- Starts backend from `backend/testcomm_go.exe`
- Sets:
  - `TESTCOMM_WEB_ROOT=<bundle>/frontend/web`
  - `TESTCOMM_CONFIG_DIR=<bundle>/backend/config`
  - `TESTCOMM_DB_PATH=<bundle>/backend/testcomm.db`
  - `TESTCOMM_PORT` (default `8082`)
  - `TESTCOMM_KILL_PREVIOUS=1` when unset
- Honors `GRMS_OPEN_BROWSER=0` to skip opening a local browser window
- Waits for `http://127.0.0.1:<port>/health`
- Opens default browser at `http://127.0.0.1:<port>/`

## Quick smoke test

### Windows

After launch:

```powershell
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:8082/health
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:8082/
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:8082/dashboard
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:8082/testcomm/rooms/Demo%20101
```

Expected: all return HTTP 200.

### Linux

```bash
chmod +x tools/grms/linux/smoke-test-linux.sh
./tools/grms/linux/smoke-test-linux.sh http://127.0.0.1:8082
```

Expected: all checks return HTTP 200.

## Notes

- Build script runs Go and Flutter builds in parallel via PowerShell background jobs.
- Linux script runs Go and Flutter builds in parallel via shell background jobs.
- Linux script can cross-compile Go binaries for `amd64`, `arm64`, or `arm` (`GOARM=6|7`). The Flutter web build is architecture-independent.
- Flutter may print wasm dry-run warnings; bundle build still succeeds as long as exit code is `0`.
- Static hosting is SPA-aware: unknown non-API routes fall back to `index.html`.
- Default bundle build uses same-origin API routing in deployed mode: frontend calls the host it is opened from (for example `127.0.0.1` or a LAN IP).
