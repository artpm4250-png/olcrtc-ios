#!/usr/bin/env bash
#
# scripts/build-gomobile-ios.sh
#
# Build OlcRTCMobile.xcframework from the upstream Go core
# (`third_party/olcrtc/mobile`) using `gomobile bind -target=ios`.
#
# This script is intentionally isolated:
#   * It does NOT integrate the framework into the Swift Xcode project.
#   * It does NOT modify the Go core.
#   * It does NOT package an IPA.
#
# The generated `OlcRTCMobile.xcframework` is ignored by `.gitignore`
# (see ADR-0001, ADR-0008 in docs/ai/DECISIONS.md).
#
# Usage:
#   scripts/build-gomobile-ios.sh
#
# Run from anywhere; the script repositions itself to the repo root.
set -euo pipefail

# --- Locate repo root -------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

echo "==> Repo root: ${REPO_ROOT}"

# --- Inputs / outputs -------------------------------------------------------
MOBILE_PKG_DIR="third_party/olcrtc/mobile"
MOBILE_PKG_PATH="./${MOBILE_PKG_DIR}"
OUT_DIR="ios/OlcRTCClient/Frameworks"
OUT_FRAMEWORK="${OUT_DIR}/OlcRTCMobile.xcframework"

if [ ! -d "${MOBILE_PKG_DIR}" ]; then
  echo "ERROR: ${MOBILE_PKG_DIR} not found." >&2
  echo "       The Go core submodule appears to be missing." >&2
  echo "       Run: git submodule update --init --recursive" >&2
  exit 1
fi
echo "==> Found Go mobile package: ${MOBILE_PKG_DIR}"

# --- Toolchain probe --------------------------------------------------------
echo "==> go version"
go version

echo "==> xcodebuild -version"
xcodebuild -version || {
  echo "ERROR: xcodebuild not available. This script must run on macOS." >&2
  exit 1
}

# Ensure $(go env GOPATH)/bin is on PATH so freshly-installed gomobile/gobind
# are visible to subsequent commands.
GOPATH_BIN="$(go env GOPATH)/bin"
case ":${PATH}:" in
  *":${GOPATH_BIN}:"*) ;;
  *) export PATH="${GOPATH_BIN}:${PATH}" ;;
esac
echo "==> PATH includes ${GOPATH_BIN}"

echo "==> gomobile version (pre-install probe)"
if command -v gomobile >/dev/null 2>&1; then
  gomobile version || true
else
  echo "gomobile not found; will install."
fi

# --- Install gomobile + gobind if missing -----------------------------------
if ! command -v gomobile >/dev/null 2>&1; then
  echo "==> go install golang.org/x/mobile/cmd/gomobile@latest"
  go install golang.org/x/mobile/cmd/gomobile@latest
fi

if ! command -v gobind >/dev/null 2>&1; then
  echo "==> go install golang.org/x/mobile/cmd/gobind@latest"
  go install golang.org/x/mobile/cmd/gobind@latest
fi

echo "==> gomobile version (post-install)"
gomobile version

# --- gomobile init ----------------------------------------------------------
echo "==> gomobile init"
gomobile init

# --- Build the xcframework --------------------------------------------------
mkdir -p "${OUT_DIR}"

# If a previous run left a framework directory, remove it so gomobile gets a
# clean output path (it does not always overwrite a stale .xcframework cleanly).
if [ -e "${OUT_FRAMEWORK}" ]; then
  echo "==> Removing stale ${OUT_FRAMEWORK}"
  rm -rf "${OUT_FRAMEWORK}"
fi

echo "==> gomobile bind -v -target=ios -o ${OUT_FRAMEWORK} ${MOBILE_PKG_PATH}"
gomobile bind -v -target=ios -o "${OUT_FRAMEWORK}" "${MOBILE_PKG_PATH}"

# --- Inspect the output -----------------------------------------------------
if [ ! -d "${OUT_FRAMEWORK}" ]; then
  echo "ERROR: gomobile bind did not produce ${OUT_FRAMEWORK}" >&2
  exit 1
fi

echo "==> Directory tree of ${OUT_FRAMEWORK}"
if command -v tree >/dev/null 2>&1; then
  tree -a "${OUT_FRAMEWORK}"
else
  # Portable fallback: find with depth + sort.
  find "${OUT_FRAMEWORK}" -print | sort
fi

echo "==> Generated headers (*.h) inside ${OUT_FRAMEWORK}"
find "${OUT_FRAMEWORK}" -name '*.h' -print | sort || true

echo "==> Generated Swift module interfaces (*.swiftinterface) inside ${OUT_FRAMEWORK}"
SWIFTINTERFACES="$(find "${OUT_FRAMEWORK}" -name '*.swiftinterface' -print | sort || true)"
if [ -n "${SWIFTINTERFACES}" ]; then
  echo "${SWIFTINTERFACES}"
else
  echo "(none — gomobile bind currently produces Objective-C headers, not Swift module interfaces)"
fi

echo "==> Done. ${OUT_FRAMEWORK} is gitignored; do not commit it."
