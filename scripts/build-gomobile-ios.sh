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
#       - no `go get`,
#       - no edits to third_party/olcrtc/go.mod,
#       - no edits to third_party/olcrtc/go.sum,
#       - no wrapper module, no go.work (those are fallbacks for a
#         later step if this one fails).
#   * It does NOT package an IPA.
#
# `gomobile bind` requires the build to happen *inside* a Go module
# whose dependency graph satisfies `golang.org/x/mobile`. The upstream
# core module already owns `./mobile` and is the only Go module in
# this repo, so we run `gomobile bind` from `third_party/olcrtc` and
# write the output back into the iOS tree via a relative `-o` path.
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
CORE_DIR="third_party/olcrtc"
CORE_GO_MOD="${CORE_DIR}/go.mod"
MOBILE_PKG_DIR="${CORE_DIR}/mobile"
OUT_DIR="ios/OlcRTCClient/Frameworks"
OUT_FRAMEWORK_ABS="${REPO_ROOT}/${OUT_DIR}/OlcRTCMobile.xcframework"
# Relative path from inside ${CORE_DIR} back to the absolute output path.
# Used by gomobile bind so the framework lands in the iOS tree even
# though we run bind from inside the upstream module.
OUT_FRAMEWORK_FROM_CORE="../../${OUT_DIR}/OlcRTCMobile.xcframework"

if [ ! -f "${CORE_GO_MOD}" ]; then
  echo "ERROR: ${CORE_GO_MOD} not found." >&2
  echo "       The Go core submodule appears to be missing or unpopulated." >&2
  echo "       Run: git submodule update --init --recursive" >&2
  exit 1
fi
echo "==> Found upstream Go module: ${CORE_GO_MOD}"

if [ ! -d "${MOBILE_PKG_DIR}" ]; then
  echo "ERROR: ${MOBILE_PKG_DIR} not found." >&2
  echo "       Expected the gomobile-friendly package at ./mobile in the upstream module." >&2
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
# These `go install` invocations resolve via GOPROXY and do NOT modify
# any local go.mod (they run with the build cache, not the project module).
if ! command -v gomobile >/dev/null 2>&1; then
  echo "==> go install golang.org/x/mobile/cmd/gomobile@latest"
  go install golang.org/x/mobile/cmd/gomobile@latest
fi

if ! command -v gobind >/dev/null 2>&1; then
  echo "==> go install golang.org/x/mobile/cmd/gobind@latest"
  go install golang.org/x/mobile/cmd/gobind@latest
fi

echo "==> gomobile version (post-install)"
gomobile version || true

# --- gomobile init ----------------------------------------------------------
echo "==> gomobile init"
gomobile init

# --- Prepare output dir, scrub stale framework ------------------------------
mkdir -p "${REPO_ROOT}/${OUT_DIR}"

if [ -e "${OUT_FRAMEWORK_ABS}" ]; then
  echo "==> Removing stale ${OUT_FRAMEWORK_ABS}"
  rm -rf "${OUT_FRAMEWORK_ABS}"
fi

# --- Enter the upstream Go module so gomobile sees a go.mod -----------------
cd "${REPO_ROOT}/${CORE_DIR}"

echo "==> Now running from upstream module:"
echo "==> pwd"
pwd
echo "==> go env GOMOD"
go env GOMOD
echo "==> go list -m golang.org/x/mobile (diagnostic; may fail if not in graph)"
go list -m golang.org/x/mobile || true
echo "==> go test -count=1 ./mobile (sanity check before bind)"
go test -count=1 ./mobile

# --- Build the xcframework --------------------------------------------------
echo "==> gomobile bind -v -target=ios -o ${OUT_FRAMEWORK_FROM_CORE} ./mobile"
gomobile bind -v \
  -target=ios \
  -o "${OUT_FRAMEWORK_FROM_CORE}" \
  ./mobile

# --- Back to repo root for output inspection --------------------------------
cd "${REPO_ROOT}"

if [ ! -d "${OUT_FRAMEWORK_ABS}" ]; then
  echo "ERROR: gomobile bind did not produce ${OUT_FRAMEWORK_ABS}" >&2
  exit 1
fi

echo "==> Directory tree of ${OUT_FRAMEWORK_ABS}"
if command -v tree >/dev/null 2>&1; then
  tree -a "${OUT_FRAMEWORK_ABS}"
else
  # Portable fallback: find with depth + sort.
  find "${OUT_FRAMEWORK_ABS}" -print | sort
fi

echo "==> Generated headers (*.h) inside ${OUT_FRAMEWORK_ABS}"
find "${OUT_FRAMEWORK_ABS}" -name '*.h' -print | sort || true

echo "==> Generated Swift module interfaces (*.swiftinterface) inside ${OUT_FRAMEWORK_ABS}"
SWIFTINTERFACES="$(find "${OUT_FRAMEWORK_ABS}" -name '*.swiftinterface' -print | sort || true)"
if [ -n "${SWIFTINTERFACES}" ]; then
  echo "${SWIFTINTERFACES}"
else
  echo "(none — gomobile bind currently produces Objective-C headers, not Swift module interfaces)"
fi

echo "==> Done. ${OUT_FRAMEWORK_ABS} is gitignored; do not commit it."
