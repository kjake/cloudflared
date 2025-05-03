#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <cloudflared executable location>"
  exit 1
}

stop_service() {
  echo "→ Stopping cloudflared service…"
  if command -v systemctl &>/dev/null; then
    systemctl stop cloudflared || true
  elif command -v service &>/dev/null; then
    service cloudflared stop || true
  elif command -v rcctl &>/dev/null; then
    rcctl stop cloudflared || true
  elif [ -x "/etc/rc.d/cloudflared" ]; then
    /etc/rc.d/cloudflared stop || true
  else
    echo "Warning: couldn't stop cloudflared (no known service manager)" >&2
  fi
}

start_service() {
  echo "→ Starting cloudflared service…"
  if command -v systemctl &>/dev/null; then
    systemctl start cloudflared || true
  elif command -v service &>/dev/null; then
    service cloudflared start || true
  elif command -v rcctl &>/dev/null; then
    rcctl start cloudflared || true
  elif [ -x "/etc/rc.d/cloudflared" ]; then
    /etc/rc.d/cloudflared start || true
  else
    echo "Warning: couldn't start cloudflared (no known service manager)" >&2
  fi
}

if [[ $# -ne 1 || $1 == -h || $1 == --help ]]; then
  usage
fi

DEST="$1"

# Temporary file cleanup
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

# Detect OS and major version
OS="$(uname -s)"
case "$OS" in
  FreeBSD)
    RAW_VER="$(uname -r)"
    MAJOR="${RAW_VER%%.*}"
    TARGET_OS="freebsd${MAJOR}"
    ;;
  NetBSD)
    RAW_VER="$(uname -r)"
    MAJOR="${RAW_VER%%.*}"
    TARGET_OS="netbsd${MAJOR}"
    ;;
  OpenBSD)
    RAW_VER="$(uname -r)"
    MAJOR="${RAW_VER%%.*}"
    TARGET_OS="openbsd${MAJOR}"
    ;;
  *)
    echo "Error: Unsupported OS: $OS" >&2
    exit 1
    ;;
esac

# Detect architecture
ARCH_RAW="$(uname -m)"
case "$ARCH_RAW" in
  x86_64|amd64) TARGET_ARCH="amd64" ;;
  aarch64|arm64) TARGET_ARCH="arm64" ;;
  *)
    echo "Error: Unsupported architecture: $ARCH_RAW" >&2
    exit 1
    ;;
esac

FILENAME="cloudflared-${TARGET_OS}-${TARGET_ARCH}"
echo "→ Detected target: $FILENAME"

# Pull the download URL from GitHub API
API_URL="https://api.github.com/repos/kjake/cloudflared/releases/latest"
DOWNLOAD_URL="$(curl -sSL "$API_URL" \
  | grep '"browser_download_url"' \
  | grep "$FILENAME" \
  | head -n1 \
  | cut -d '"' -f4)"

if [ -z "$DOWNLOAD_URL" ]; then
  echo "Error: could not find download for $FILENAME" >&2
  exit 1
fi

echo "→ Downloading $DOWNLOAD_URL …"
curl -sSL "$DOWNLOAD_URL" -o "$TMP"
chmod +x "$TMP"


stop_service
echo "→ Installing new binary to $DEST"
mv -f "$TMP" "$DEST"
chmod +x "$DEST"
start_service

echo "Success: cloudflared has been updated to the latest release."
exit 0