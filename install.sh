#!/usr/bin/env bash
# CostBurn installer
# Downloads the latest release, strips Gatekeeper quarantine,
# installs to ~/Applications, and launches.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/sanjeev-pandey23/costburn/main/install.sh | bash
#   or with --force to reinstall:
#   curl -fsSL .../install.sh | bash -s -- --force

set -euo pipefail

REPO="sanjeev-pandey23/costburn"
APP_NAME="CostBurn"
APP_BUNDLE="${APP_NAME}.app"
INSTALL_DIR="${HOME}/Applications"
FORCE=false

for arg in "$@"; do
    [[ "$arg" == "--force" ]] && FORCE=true
done

# ── colour helpers ────────────────────────────────────────────────────────────
red()   { printf '\033[0;31m%s\033[0m\n' "$*"; }
green() { printf '\033[0;32m%s\033[0m\n' "$*"; }
blue()  { printf '\033[0;34m%s\033[0m\n' "$*"; }
dim()   { printf '\033[2m%s\033[0m\n'   "$*"; }
die()   { red "Error: $*"; exit 1; }

# ── platform checks ───────────────────────────────────────────────────────────
[[ "$(uname)" == "Darwin" ]] || die "CostBurn requires macOS."

OS_MAJOR=$(sw_vers -productVersion | cut -d. -f1)
[[ "$OS_MAJOR" -ge 14 ]] \
    || die "CostBurn requires macOS 14 (Sonoma) or later. You have $(sw_vers -productVersion)."

# ── skip if already installed (unless --force) ────────────────────────────────
TARGET="${INSTALL_DIR}/${APP_BUNDLE}"
if [[ -d "$TARGET" ]] && [[ "$FORCE" == false ]]; then
    green "CostBurn is already installed at ${TARGET}."
    dim  "  Run with --force to reinstall, or just open it:"
    dim  "  open \"${TARGET}\""
    exit 0
fi

# ── fetch latest release metadata ────────────────────────────────────────────
blue "==> Fetching latest release..."
RELEASE_JSON=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest")

ZIP_URL=$(printf '%s' "$RELEASE_JSON" \
    | grep -o '"browser_download_url": *"[^"]*\.zip"' \
    | grep -v '\.sha256' \
    | head -1 \
    | cut -d'"' -f4)

SHA_URL=$(printf '%s' "$RELEASE_JSON" \
    | grep -o '"browser_download_url": *"[^"]*\.zip\.sha256"' \
    | head -1 \
    | cut -d'"' -f4)

VERSION=$(printf '%s' "$RELEASE_JSON" \
    | grep -o '"tag_name": *"[^"]*"' \
    | head -1 \
    | cut -d'"' -f4 \
    | sed 's/^mac-v//')

[[ -n "$ZIP_URL" ]] || die "Could not locate .zip asset in latest release."
[[ -n "$SHA_URL" ]] || die "Could not locate .sha256 asset in latest release."

blue "==> Downloading CostBurn ${VERSION}..."

# ── temp workspace (cleaned up on exit) ──────────────────────────────────────
TMP_DIR=$(mktemp -d /tmp/costburn-XXXXXX)
trap 'rm -rf "$TMP_DIR"' EXIT

ZIP_PATH="${TMP_DIR}/${APP_NAME}-${VERSION}.zip"
SHA_PATH="${TMP_DIR}/${APP_NAME}-${VERSION}.zip.sha256"

curl -fsSL --progress-bar "$ZIP_URL" -o "$ZIP_PATH"
curl -fsSL             "$SHA_URL" -o "$SHA_PATH"

# ── checksum verification ─────────────────────────────────────────────────────
blue "==> Verifying checksum..."
EXPECTED=$(cat "$SHA_PATH")
ACTUAL=$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')
[[ "$EXPECTED" == "$ACTUAL" ]] \
    || die "Checksum mismatch!\n  Expected: ${EXPECTED}\n  Got:      ${ACTUAL}"

# ── extract ───────────────────────────────────────────────────────────────────
blue "==> Extracting..."
STAGE_DIR="${TMP_DIR}/stage"
mkdir -p "$STAGE_DIR"
/usr/bin/unzip -q "$ZIP_PATH" -d "$STAGE_DIR"

UNPACKED_APP=$(find "$STAGE_DIR" -name "*.app" -maxdepth 2 | head -1)
[[ -n "$UNPACKED_APP" ]] || die "Could not find .app bundle in archive."

# ── strip Gatekeeper quarantine ───────────────────────────────────────────────
blue "==> Removing quarantine attribute..."
/usr/bin/xattr -dr com.apple.quarantine "$UNPACKED_APP" 2>/dev/null || true

# ── stop running instance ─────────────────────────────────────────────────────
if /usr/bin/pgrep -f "${APP_NAME}" > /dev/null 2>&1; then
    blue "==> Stopping running instance..."
    /usr/bin/pkill -f "${APP_NAME}" 2>/dev/null || true
    sleep 1
fi

# ── install ───────────────────────────────────────────────────────────────────
mkdir -p "$INSTALL_DIR"

if [[ -d "$TARGET" ]]; then
    blue "==> Replacing existing installation..."
    rm -rf "$TARGET"
fi

blue "==> Installing to ${INSTALL_DIR}..."
cp -R "$UNPACKED_APP" "$TARGET"

# ── launch ────────────────────────────────────────────────────────────────────
blue "==> Launching CostBurn..."
/usr/bin/open "$TARGET"

green ""
green "  CostBurn ${VERSION} installed to ~/Applications."
green "  Look for the \$--.-- icon in your menubar."
