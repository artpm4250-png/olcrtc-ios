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

# Prepare a reports directory that mirrors what we print to stdout. Both the
# directory and `OUT_FRAMEWORK_ABS` are uploaded as CI artifacts by the
# Gomobile iOS Bind workflow; they let the next step (Swift integration)
# read the real generated symbols instead of guessing.
REPORT_DIR="${REPO_ROOT}/build/reports/gomobile"
rm -rf "${REPORT_DIR}"
mkdir -p "${REPORT_DIR}"

FILES_TXT="${REPORT_DIR}/files.txt"
HEADERS_TXT="${REPORT_DIR}/headers.txt"
MODULEMAPS_TXT="${REPORT_DIR}/modulemaps.txt"
SWIFTINTERFACES_TXT="${REPORT_DIR}/swiftinterfaces.txt"
SUMMARY_MD="${REPORT_DIR}/summary.md"

HEADER_HEAD_LINES=240
SWIFTINTERFACE_HEAD_LINES=240

# ---- files.txt (full directory listing, depth-capped at 5) -----------------
echo "==> Writing ${FILES_TXT}"
find "${OUT_FRAMEWORK_ABS}" -maxdepth 5 -type f | sort > "${FILES_TXT}"

echo "==> Directory tree of ${OUT_FRAMEWORK_ABS} (echoed to stdout)"
cat "${FILES_TXT}"

# Helper: emit "==> path\n<first N lines>\n" for each file in $@ to the given
# report file AND to stdout.
emit_files_into() {
  local report_path="$1"; shift
  local head_lines="$1"; shift
  : > "${report_path}"
  if [ "$#" -eq 0 ]; then
    echo "(none found)" | tee -a "${report_path}"
    return 0
  fi
  for f in "$@"; do
    {
      echo "==> ${f}"
      head -n "${head_lines}" "${f}" || true
      echo
    } | tee -a "${report_path}"
  done
}

# ---- headers.txt (all .h files, first 240 lines each) ----------------------
HEADER_FILES=()
while IFS= read -r path; do
  [ -n "${path}" ] && HEADER_FILES+=("${path}")
done < <(find "${OUT_FRAMEWORK_ABS}" -name '*.h' -type f | sort)

echo "==> Generated headers (*.h) inside ${OUT_FRAMEWORK_ABS}"
printf '%s\n' "${HEADER_FILES[@]}"

echo "==> Writing ${HEADERS_TXT} (first ${HEADER_HEAD_LINES} lines per header)"
emit_files_into "${HEADERS_TXT}" "${HEADER_HEAD_LINES}" "${HEADER_FILES[@]}"

# ---- modulemaps.txt (all module.modulemap files, full contents) ------------
MODULEMAP_FILES=()
while IFS= read -r path; do
  [ -n "${path}" ] && MODULEMAP_FILES+=("${path}")
done < <(find "${OUT_FRAMEWORK_ABS}" -name 'module.modulemap' -type f | sort)

echo "==> Module maps inside ${OUT_FRAMEWORK_ABS}"
printf '%s\n' "${MODULEMAP_FILES[@]}"

echo "==> Writing ${MODULEMAPS_TXT} (full contents)"
: > "${MODULEMAPS_TXT}"
if [ "${#MODULEMAP_FILES[@]}" -eq 0 ]; then
  echo "(none found)" | tee -a "${MODULEMAPS_TXT}"
else
  for f in "${MODULEMAP_FILES[@]}"; do
    {
      echo "==> ${f}"
      cat "${f}"
      echo
    } | tee -a "${MODULEMAPS_TXT}"
  done
fi

# ---- swiftinterfaces.txt (all *.swiftinterface, first 240 lines each) ------
SWIFTINTERFACE_FILES=()
while IFS= read -r path; do
  [ -n "${path}" ] && SWIFTINTERFACE_FILES+=("${path}")
done < <(find "${OUT_FRAMEWORK_ABS}" -name '*.swiftinterface' -type f | sort)

echo "==> Generated Swift module interfaces (*.swiftinterface) inside ${OUT_FRAMEWORK_ABS}"
if [ "${#SWIFTINTERFACE_FILES[@]}" -eq 0 ]; then
  echo "(none — gomobile bind currently produces Objective-C headers, not Swift module interfaces)"
else
  printf '%s\n' "${SWIFTINTERFACE_FILES[@]}"
fi

echo "==> Writing ${SWIFTINTERFACES_TXT} (first ${SWIFTINTERFACE_HEAD_LINES} lines per file)"
emit_files_into "${SWIFTINTERFACES_TXT}" "${SWIFTINTERFACE_HEAD_LINES}" "${SWIFTINTERFACE_FILES[@]}"

# ---- summary.md (high-level findings, parsed mechanically) -----------------
# Best-effort: pick the *first* discovered xcframework slice (e.g. ios-arm64),
# extract framework name + module name + a list of declared @interface /
# function names from the public header. This is intentionally conservative —
# the authoritative source is docs/ai/GOMOBILE_BINDINGS.md, which is updated
# from these reports after a green CI run.
FIRST_FRAMEWORK_DIR="$(find "${OUT_FRAMEWORK_ABS}" -mindepth 2 -maxdepth 2 -name '*.framework' -type d | sort | head -n 1 || true)"
FRAMEWORK_NAME=""
PRIMARY_HEADER=""
PRIMARY_MODULEMAP=""
INTERFACE_LINES=""
FUNCTION_LINES=""
if [ -n "${FIRST_FRAMEWORK_DIR}" ]; then
  FRAMEWORK_NAME="$(basename "${FIRST_FRAMEWORK_DIR}" .framework)"
  PRIMARY_HEADER="$(find "${FIRST_FRAMEWORK_DIR}/Headers" -name '*.h' -type f 2>/dev/null | sort | head -n 1 || true)"
  PRIMARY_MODULEMAP="$(find "${FIRST_FRAMEWORK_DIR}/Modules" -name 'module.modulemap' -type f 2>/dev/null | sort | head -n 1 || true)"
  if [ -n "${PRIMARY_HEADER}" ]; then
    INTERFACE_LINES="$(grep -E '^@interface ' "${PRIMARY_HEADER}" || true)"
    FUNCTION_LINES="$(grep -E '^(FOUNDATION_EXPORT|extern) ' "${PRIMARY_HEADER}" || true)"
  fi
fi

{
  echo "# gomobile bind — generated artifacts summary"
  echo
  echo "Written by \`scripts/build-gomobile-ios.sh\` after a successful"
  echo "\`gomobile bind -target=ios\`. This file is **mechanical** — the"
  echo "curated mapping lives in \`docs/ai/GOMOBILE_BINDINGS.md\`, which is"
  echo "updated by hand from these reports."
  echo
  echo "## xcframework"
  echo
  echo "- path: \`${OUT_FRAMEWORK_ABS#${REPO_ROOT}/}\`"
  echo "- first framework slice: \`${FIRST_FRAMEWORK_DIR#${REPO_ROOT}/}\`"
  echo "- framework name: \`${FRAMEWORK_NAME}\`"
  echo "- primary header: \`${PRIMARY_HEADER#${REPO_ROOT}/}\`"
  echo "- module map: \`${PRIMARY_MODULEMAP#${REPO_ROOT}/}\`"
  echo
  echo "## @interface declarations (primary header)"
  echo
  if [ -n "${INTERFACE_LINES}" ]; then
    echo '```objc'
    echo "${INTERFACE_LINES}"
    echo '```'
  else
    echo "_(none discovered by grep on the primary header)_"
  fi
  echo
  echo "## FOUNDATION_EXPORT / extern declarations (primary header)"
  echo
  if [ -n "${FUNCTION_LINES}" ]; then
    echo '```objc'
    echo "${FUNCTION_LINES}"
    echo '```'
  else
    echo "_(none discovered by grep on the primary header)_"
  fi
  echo
  echo "## Companion reports"
  echo
  echo "- \`files.txt\` — full file listing inside the xcframework."
  echo "- \`headers.txt\` — first ${HEADER_HEAD_LINES} lines of every \`*.h\`."
  echo "- \`modulemaps.txt\` — full contents of every \`module.modulemap\`."
  echo "- \`swiftinterfaces.txt\` — first ${SWIFTINTERFACE_HEAD_LINES} lines of every \`*.swiftinterface\` (empty if gomobile only emitted Obj-C)."
} > "${SUMMARY_MD}"

echo "==> Wrote ${SUMMARY_MD}"
echo "----- begin ${SUMMARY_MD} -----"
cat "${SUMMARY_MD}"
echo "----- end ${SUMMARY_MD} -----"

echo "==> Done. ${OUT_FRAMEWORK_ABS} and ${REPORT_DIR} are gitignored; do not commit them."
