#!/usr/bin/env bash
set -euo pipefail

# verify-deepseek-key.sh
# Verifies that the built app contains the DEEPSEEK_API_KEY inside the generated Info.plist.
# Works for Debug/Release; supports simulator or device builds. Defaults to Debug + iPhone simulator.

usage() {
  cat <<'USAGE'
Usage:
  scripts/verify-deepseek-key.sh [--scheme WhipTip] [--configuration Debug|Release] [--sdk iphonesimulator|iphoneos] [--destination "platform=iOS Simulator,name=iPhone 15"]

Examples:
  scripts/verify-deepseek-key.sh
  scripts/verify-deepseek-key.sh --configuration Release --sdk iphonesimulator
  scripts/verify-deepseek-key.sh --sdk iphoneos --configuration Release
USAGE
}

SCHEME="WhipTip"
CONFIGURATION="Debug"
SDK="iphonesimulator"
# Leave DESTINATION empty by default; xcodebuild will pick a reasonable default simulator
DESTINATION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scheme)
      SCHEME="$2"; shift 2;;
    --configuration)
      CONFIGURATION="$2"; shift 2;;
    --sdk)
      SDK="$2"; shift 2;;
    --destination)
      DESTINATION="$2"; shift 2;;
    -h|--help)
      usage; exit 0;;
    *)
      echo "Unknown argument: $1" >&2; usage; exit 1;;
  esac
done

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
PROJ="$ROOT_DIR/WhipTip.xcodeproj"

# Build to a derived data location so we can locate the built app
DERIVED_DATA=$(mktemp -d)

# Choose pretty printer if available
if command -v xcpretty >/dev/null 2>&1; then
  PIPE_CMD=(xcpretty)
else
  PIPE_CMD=(cat)
fi

# If no destination provided and building for simulator, pick the first available simulator by UDID
if [[ -z "$DESTINATION" && "$SDK" == "iphonesimulator" ]]; then
  # Query available destinations and select the first concrete iOS Simulator (not placeholder)
  DEST_JSON=$(xcodebuild -project "$PROJ" -scheme "$SCHEME" -showdestinations 2>/dev/null || true)
  # Extract a UDID-like token (UUID format) for iOS Simulator
  DEST_UDID=$(printf "%s" "$DEST_JSON" | awk -F'id:' '/platform:iOS Simulator/ && $2 ~ /[A-F0-9-]{36}/ { gsub(/[ ,}]/, "", $2); print $2; exit }')
  if [[ -n "$DEST_UDID" ]]; then
    DESTINATION="id=$DEST_UDID"
  else
    # Fallback to generic platform if parsing fails
    DESTINATION="generic/platform=iOS Simulator"
  fi
fi

# Build arguments
XCB_ARGS=(
  -project "$PROJ"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -sdk "$SDK"
  -derivedDataPath "$DERIVED_DATA"
  build
)

# Add destination (now resolved or user-provided) when available
if [[ -n "$DESTINATION" ]]; then
  XCB_ARGS+=( -destination "$DESTINATION" )
fi

set -x
# Run build and avoid exiting if pretty-printer fails; we already selected a fallback
(
  set +o pipefail
  xcodebuild "${XCB_ARGS[@]}" | "${PIPE_CMD[@]}"
)
set +x

# Locate the built .app deterministically first, fallback to find
APP_PATH=""
if [[ "$SDK" == "iphonesimulator" ]]; then
  CANDIDATE="$DERIVED_DATA/Build/Products/${CONFIGURATION}-iphonesimulator/WhipTip.app"
else
  CANDIDATE="$DERIVED_DATA/Build/Products/${CONFIGURATION}-iphoneos/WhipTip.app"
fi

if [[ -d "$CANDIDATE" ]]; then
  APP_PATH="$CANDIDATE"
else
  APP_PATH=$(find "$DERIVED_DATA/Build/Products" -type d -name "WhipTip.app" | head -n 1 || true)
fi

if [[ -z "$APP_PATH" ]]; then
  echo "ERROR: Could not locate built app in $DERIVED_DATA" >&2
  exit 1
fi

INFO_PLIST="$APP_PATH/Info.plist"
if [[ ! -f "$INFO_PLIST" ]]; then
  echo "ERROR: Info.plist not found at $INFO_PLIST" >&2
  exit 1
fi

# Read key. On macOS, use /usr/libexec/PlistBuddy or defaults as fallback.
VALUE=""
if command -v /usr/libexec/PlistBuddy >/dev/null 2>&1; then
  set +e
  VALUE=$(/usr/libexec/PlistBuddy -c "Print :DEEPSEEK_API_KEY" "$INFO_PLIST" 2>/dev/null)
  STATUS=$?
  set -e
  if [[ $STATUS -ne 0 ]]; then
    echo "ERROR: Key DEEPSEEK_API_KEY not found in Info.plist" >&2
    exit 1
  fi
else
  VALUE=$(defaults read "$APP_PATH/Info" DEEPSEEK_API_KEY 2>/dev/null || true)
  if [[ -z "$VALUE" ]]; then
    echo "ERROR: Key DEEPSEEK_API_KEY not found in Info.plist" >&2
    exit 1
  fi
fi

MASKED="${VALUE:0:4}********${VALUE: -4}"
echo "SUCCESS: DEEPSEEK_API_KEY is present in Info.plist => $MASKED"

echo "Note: Runtime still prefers UserDefaults override if present."
