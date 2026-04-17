#!/usr/bin/env bash

set -euo pipefail

CONFIGURATION="release"
FRONTEND_API_BASE_URL=""
GOARCH_TARGET="amd64"
GOARM_TARGET=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --configuration)
      CONFIGURATION="${2:-}"
      shift 2
      ;;
    --frontend-api-base-url)
      FRONTEND_API_BASE_URL="${2:-}"
      shift 2
      ;;
    --goarch)
      GOARCH_TARGET="${2:-}"
      shift 2
      ;;
    --goarm)
      GOARM_TARGET="${2:-}"
      shift 2
      ;;
    *)
      echo "[grms-bundle-linux] Unknown argument: $1" >&2
      echo "Usage: $0 [--configuration release|debug] [--frontend-api-base-url <url>] [--goarch amd64|arm64|arm] [--goarm <6|7>]" >&2
      exit 1
      ;;
  esac
done

if [[ "$CONFIGURATION" != "release" && "$CONFIGURATION" != "debug" ]]; then
  echo "[grms-bundle-linux] --configuration must be 'release' or 'debug'" >&2
  exit 1
fi

if [[ "$GOARCH_TARGET" != "amd64" && "$GOARCH_TARGET" != "arm64" && "$GOARCH_TARGET" != "arm" ]]; then
  echo "[grms-bundle-linux] --goarch must be one of: amd64, arm64, arm" >&2
  exit 1
fi

if [[ "$GOARCH_TARGET" == "arm" ]]; then
  if [[ -z "$GOARM_TARGET" ]]; then
    GOARM_TARGET="7"
  fi
  if [[ "$GOARM_TARGET" != "6" && "$GOARM_TARGET" != "7" ]]; then
    echo "[grms-bundle-linux] --goarm must be 6 or 7 when --goarch arm is used" >&2
    exit 1
  fi
elif [[ -n "$GOARM_TARGET" ]]; then
  echo "[grms-bundle-linux] --goarm can only be used together with --goarch arm" >&2
  exit 1
fi

log() {
  echo "[grms-bundle-linux] $*"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[grms-bundle-linux] Required command '$1' not found in PATH." >&2
    exit 1
  fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

FLUTTER_APP_PATH="$REPO_ROOT/tools/grms/flutter_grems_app"
TESTCOMM_PATH="$REPO_ROOT/tools/grms/testcomm_go"
LAUNCHER_PATH="$REPO_ROOT/tools/grms/grms_launcher"
TESTCOMM_CONFIG_PATH="$TESTCOMM_PATH/config"

DIST_DIR_NAME="grms_bundle_linux"
if [[ "$GOARCH_TARGET" == "arm64" ]]; then
  DIST_DIR_NAME="grms_bundle_linux_arm64"
elif [[ "$GOARCH_TARGET" == "arm" ]]; then
  DIST_DIR_NAME="grms_bundle_linux_armv${GOARM_TARGET}"
fi

DIST_PATH="$REPO_ROOT/dist/$DIST_DIR_NAME"
BACKEND_OUT_DIR="$DIST_PATH/backend"
FRONTEND_OUT_DIR="$DIST_PATH/frontend/web"
LAUNCHER_OUT_DIR="$DIST_PATH/launcher"

BACKEND_BIN_PATH="$BACKEND_OUT_DIR/testcomm_go"
LAUNCHER_BIN_PATH="$LAUNCHER_OUT_DIR/grms_launcher"
GO_BUILD_ENV=(GOOS=linux GOARCH="$GOARCH_TARGET")
if [[ "$GOARCH_TARGET" == "arm" ]]; then
  GO_BUILD_ENV+=(GOARM="$GOARM_TARGET")
fi

log "Repository root: $REPO_ROOT"
log "Checking prerequisites..."
require_cmd go
require_cmd flutter

[[ -d "$FLUTTER_APP_PATH" ]] || { echo "Flutter app path missing: $FLUTTER_APP_PATH" >&2; exit 1; }
[[ -d "$TESTCOMM_PATH" ]] || { echo "TestComm path missing: $TESTCOMM_PATH" >&2; exit 1; }
[[ -d "$LAUNCHER_PATH" ]] || { echo "Launcher path missing: $LAUNCHER_PATH" >&2; exit 1; }
[[ -d "$TESTCOMM_CONFIG_PATH" ]] || { echo "TestComm config path missing: $TESTCOMM_CONFIG_PATH" >&2; exit 1; }

log "Target Go platform: linux/$GOARCH_TARGET${GOARM_TARGET:+ (GOARM=$GOARM_TARGET)}"
log "Bundle output directory: $DIST_PATH"

log "Preparing output directories..."
mkdir -p "$BACKEND_OUT_DIR" "$FRONTEND_OUT_DIR" "$LAUNCHER_OUT_DIR"
rm -rf "$BACKEND_OUT_DIR"/* "$FRONTEND_OUT_DIR"/* "$LAUNCHER_OUT_DIR"/*

log "Starting parallel build jobs (Go backend + Flutter web)..."
(
  cd "$TESTCOMM_PATH"
  env "${GO_BUILD_ENV[@]}" go build -o "$BACKEND_BIN_PATH" .
) &
GO_JOB_PID=$!

(
  cd "$FLUTTER_APP_PATH"
  flutter pub get

  BUILD_ARGS=(build web --base-href / --dart-define=GREMS_DEPLOYMENT_MODE=deployed)
  if [[ "$CONFIGURATION" == "release" ]]; then
    BUILD_ARGS+=(--release)
  fi
  if [[ -n "$FRONTEND_API_BASE_URL" ]]; then
    BUILD_ARGS+=("--dart-define=TESTCOMM_BASE_URL=$FRONTEND_API_BASE_URL")
  fi

  flutter "${BUILD_ARGS[@]}"
) &
FLUTTER_JOB_PID=$!

wait "$GO_JOB_PID"
wait "$FLUTTER_JOB_PID"

log "Copying backend config into bundle..."
mkdir -p "$BACKEND_OUT_DIR/config"
cp -a "$TESTCOMM_CONFIG_PATH"/. "$BACKEND_OUT_DIR/config/"

log "Copying Flutter web output into bundle..."
cp -a "$FLUTTER_APP_PATH/build/web"/. "$FRONTEND_OUT_DIR/"

log "Building Linux launcher binary..."
(
  cd "$LAUNCHER_PATH"
  env "${GO_BUILD_ENV[@]}" go build -o "$LAUNCHER_BIN_PATH" .
)
chmod +x "$BACKEND_BIN_PATH" "$LAUNCHER_BIN_PATH"

log "Writing launcher helper script..."
cat > "$DIST_PATH/start-grms.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/launcher/grms_launcher"
EOF
chmod +x "$DIST_PATH/start-grms.sh"

log "GRMS Linux bundle built successfully."
log "Bundle location: $DIST_PATH"
log "To run:"
echo "  cd \"$DIST_PATH\" && ./start-grms.sh"
