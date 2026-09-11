#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <cloudflared executable location>"
  echo
  echo "Environment:"
  echo "  CLOUDFLARED_SKIP_CHECKSUM=1  install even if the release publishes no checksum"
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

# Read the first 64-hex-character token on stdin and normalise it to lowercase.
extract_sha256() {
  grep -Eo '[0-9a-fA-F]{64}' | head -n1 | tr 'A-F' 'a-f' || true
}

# Print the SHA-256 of a file, using whichever digest tool the OS ships.
# The BSDs disagree on the tool, on its flags, and on its output format
# ("hash  file", "SHA256 (file) = hash", bare hash) — and a tool can be present
# without supporting SHA-256 at all. So each candidate is tried in turn and its
# output is only accepted once a digest actually falls out of it.
sha256_of() {
  local file="$1" tool out hash

  for tool in sha256sum sha256 cksum openssl shasum; do
    command -v "$tool" &>/dev/null || continue
    case "$tool" in
      cksum)   out="$(cksum -a sha256 "$file" 2>/dev/null)" || out="" ;;
      openssl) out="$(openssl dgst -sha256 "$file" 2>/dev/null)" || out="" ;;
      shasum)  out="$(shasum -a 256 "$file" 2>/dev/null)" || out="" ;;
      *)       out="$("$tool" "$file" 2>/dev/null)" || out="" ;;
    esac

    hash="$(extract_sha256 <<<"$out")"
    if [ -n "$hash" ]; then
      printf '%s\n' "$hash"
      return 0
    fi
  done

  echo "Error: no working SHA-256 tool found (tried sha256sum, sha256, cksum, openssl, shasum)" >&2
  return 1
}

if [[ $# -ne 1 || $1 == -h || $1 == --help ]]; then
  usage
fi

DEST="$1"
DEST_DIR="$(dirname "$DEST")"

if [ ! -d "$DEST_DIR" ] || [ ! -w "$DEST_DIR" ]; then
  echo "Error: $DEST_DIR is not a writable directory (run as root?)" >&2
  exit 1
fi

# Stage the download beside the destination so the final install is a
# same-filesystem rename, which is atomic. mktemp's default /tmp is usually a
# different filesystem, making `mv` a copy that can leave a half-written binary
# in place if it is interrupted.
WORKDIR="$(mktemp -d "${DEST_DIR}/.cloudflared-update.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT
TMP="$WORKDIR/cloudflared"
SUMFILE="$WORKDIR/cloudflared.sha256"

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
CHECKSUM_NAME="${FILENAME}.sha256"
echo "→ Detected target: $FILENAME"

# Pull the asset list from the GitHub API once, then pick URLs out of it.
API_URL="https://api.github.com/repos/kjake/cloudflared/releases/latest"
RELEASE_JSON="$(curl -fsSL --retry 3 --retry-delay 2 "$API_URL")"

# Flatten the release into "<asset name> <digest or -> <url>" rows.
#
# GitHub hashes every asset as it is uploaded and returns that in the API
# response as "digest": "sha256:…", which is how a download can be verified
# even for releases published before this repo started shipping .sha256 assets.
# The API pretty-prints one field per line and lists digest before
# browser_download_url inside each asset object, so one pass can pair them up
# without jq — none of the BSDs ship it by default.
ASSET_ROWS="$(printf '%s\n' "$RELEASE_JSON" | awk '
  /"digest":/ {
    digest = "-"
    if (match($0, /sha256:[0-9a-fA-F]+/)) {
      digest = substr($0, RSTART + 7, RLENGTH - 7)
    }
    next
  }
  /"browser_download_url":/ {
    url = $0
    sub(/^[^:]*:[[:space:]]*"/, "", url)   # drop the key and the opening quote
    sub(/".*$/, "", url)                   # drop the closing quote and comma
    name = url
    sub(/.*\//, "", name)
    print name, digest, url
    digest = "-"
  }
')"

# Look assets up by exact name: a substring match on $FILENAME would also hit
# "${FILENAME}.sha256" and could hand back the checksum file as the binary.
asset_row() {
  printf '%s\n' "$ASSET_ROWS" | awk -v want="$1" '$1 == want { print; exit }'
}

BINARY_ROW="$(asset_row "$FILENAME")"
DOWNLOAD_URL="$(printf '%s\n' "$BINARY_ROW" | awk '{ print $3 }')"
API_DIGEST="$(printf '%s\n' "$BINARY_ROW" | awk '$2 != "-" { print $2 }')"
CHECKSUM_URL="$(asset_row "$CHECKSUM_NAME" | awk '{ print $3 }')"

if [ -z "$DOWNLOAD_URL" ]; then
  echo "Error: could not find download for $FILENAME" >&2
  exit 1
fi

echo "→ Downloading $DOWNLOAD_URL …"
# -f matters: without it curl writes GitHub's HTML error page to $TMP on a 404
# or 5xx and the script happily installs that as the binary.
curl -fsSL --retry 3 --retry-delay 2 "$DOWNLOAD_URL" -o "$TMP"

PUBLISHED_DIGEST=""
if [ -n "$CHECKSUM_URL" ]; then
  curl -fsSL --retry 3 --retry-delay 2 "$CHECKSUM_URL" -o "$SUMFILE"
  PUBLISHED_DIGEST="$(extract_sha256 <"$SUMFILE")"
  if [ -z "$PUBLISHED_DIGEST" ]; then
    echo "Error: $CHECKSUM_NAME contains no SHA-256 digest" >&2
    exit 1
  fi
fi

# check_digest <where it came from> <expected hash> — no-op when the source
# published nothing.
check_digest() {
  [ -n "$2" ] || return 0
  if [ "$2" != "$ACTUAL" ]; then
    echo "Error: checksum mismatch against $1 — download is corrupt or tampered with." >&2
    echo "  expected: $2" >&2
    echo "  actual:   $ACTUAL" >&2
    echo "$DEST was left untouched." >&2
    exit 1
  fi
  echo "  verified against $1"
}

if [ -z "$API_DIGEST" ] && [ -z "$PUBLISHED_DIGEST" ]; then
  if [ "${CLOUDFLARED_SKIP_CHECKSUM:-0}" = "1" ]; then
    echo "Warning: this release publishes no checksum; continuing unverified" >&2
  else
    echo "Error: this release publishes no checksum, so the download cannot be verified." >&2
    echo "Only releases from before mid-2025 predate GitHub's asset digests. Re-run" >&2
    echo "with CLOUDFLARED_SKIP_CHECKSUM=1 to install anyway." >&2
    exit 1
  fi
else
  echo "→ Verifying download…"
  ACTUAL="$(sha256_of "$TMP")"
  # Both sources are checked when both exist. The .sha256 asset is computed on
  # the build host before upload and GitHub's digest after it received the
  # bytes, so the two disagreeing means the upload itself was damaged.
  check_digest "GitHub's published asset digest" "$API_DIGEST"
  check_digest "$CHECKSUM_NAME" "$PUBLISHED_DIGEST"
  echo "  checksum OK ($ACTUAL)"
fi

chmod +x "$TMP"

# Last gate before the running service is touched: a binary that is intact but
# built for the wrong OS or architecture fails here, not after the swap.
echo "→ Smoke-testing the new binary…"
if ! VERSION_OUT="$("$TMP" --version 2>&1)"; then
  echo "Error: downloaded binary does not run:" >&2
  echo "$VERSION_OUT" >&2
  echo "$DEST was left untouched." >&2
  exit 1
fi
echo "  $(printf '%s\n' "$VERSION_OUT" | head -n1)"

stop_service
echo "→ Installing new binary to $DEST"
mv -f "$TMP" "$DEST"
chmod +x "$DEST"
start_service

echo "Success: cloudflared has been updated to the latest release."
exit 0
