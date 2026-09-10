#!/usr/bin/env bash
#
# Regression tests for ../update-cloudflared.sh.
#
#   ./tests/update-cloudflared.test.sh
#
# No network and no root: the GitHub release is faked as a JSON file whose
# asset URLs are file:// paths, and `uname` is shadowed on PATH so the NetBSD
# code path runs on any host. Everything lives under a temp directory.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${1:-$HERE/../update-cloudflared.sh}"
ASSET="cloudflared-netbsd10-amd64"

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

pass=0
fail=0

ok()   { echo "PASS: $1"; pass=$((pass + 1)); }
bad()  { echo "FAIL: $1"; fail=$((fail + 1)); }

# Same tool fallback order as the script under test, so the fixtures can be
# hashed on any of the hosts these tests might run on.
digest() {
  local tool out hash
  for tool in sha256sum sha256 cksum openssl shasum; do
    command -v "$tool" &>/dev/null || continue
    case "$tool" in
      cksum)   out="$(cksum -a sha256 "$1" 2>/dev/null)" || out="" ;;
      openssl) out="$(openssl dgst -sha256 "$1" 2>/dev/null)" || out="" ;;
      shasum)  out="$(shasum -a 256 "$1" 2>/dev/null)" || out="" ;;
      *)       out="$("$tool" "$1" 2>/dev/null)" || out="" ;;
    esac
    hash="$(printf '%s\n' "$out" | grep -Eo '[0-9a-fA-F]{64}' | head -n1 || true)"
    [ -n "$hash" ] && { printf '%s\n' "$hash"; return 0; }
  done
  echo "no SHA-256 tool available to build fixtures" >&2
  return 1
}

# fixture <case-name> <good|corrupt|nosum> — builds a self-contained release
# and a copy of the script pointed at it. Echoes the case directory.
fixture() {
  local name="$1" mode="$2" dir="$TMPROOT/$1"
  mkdir -p "$dir/assets" "$dir/dest" "$dir/bin"

  cat > "$dir/bin/uname" <<'FAKE'
#!/bin/sh
case "$1" in
  -s) echo NetBSD ;;
  -r) echo 10.1 ;;
  -m) echo amd64 ;;
esac
FAKE
  chmod +x "$dir/bin/uname"

  cat > "$dir/assets/$ASSET" <<'FAKE'
#!/bin/sh
[ "$1" = "--version" ] && echo "cloudflared version 0.0.0 (test fixture)"
exit 0
FAKE
  printf '%s  %s\n' "$(digest "$dir/assets/$ASSET")" "$ASSET" > "$dir/assets/$ASSET.sha256"

  # The digest is written from the pristine binary, so corrupting it afterwards
  # is exactly the "broken download" case: a checksum that no longer matches.
  [ "$mode" = corrupt ] && printf 'truncated garbage\n' > "$dir/assets/$ASSET"
  [ "$mode" = nosum ] && rm -f "$dir/assets/$ASSET.sha256"

  {
    echo '{ "assets": ['
    echo "  { \"browser_download_url\": \"file://$dir/assets/$ASSET\" },"
    [ -f "$dir/assets/$ASSET.sha256" ] &&
      echo "  { \"browser_download_url\": \"file://$dir/assets/$ASSET.sha256\" }"
    echo '] }'
  } > "$dir/release.json"

  sed "s#^API_URL=.*#API_URL=\"file://$dir/release.json\"#" "$SCRIPT" > "$dir/script.sh"
  chmod +x "$dir/script.sh"

  printf '%s\n' "$dir"
}

# --- a good download installs ------------------------------------------------
dir="$(fixture good good)"
out="$(PATH="$dir/bin:$PATH" "$dir/script.sh" "$dir/dest/cloudflared" 2>&1)"
status=$?
[ $status -eq 0 ] && ok "valid checksum: exits 0" || bad "valid checksum: exit $status: $out"
printf '%s' "$out" | grep -q "checksum OK" && ok "valid checksum: reports verification" \
                                           || bad "valid checksum: no verification line"
[ -x "$dir/dest/cloudflared" ] && ok "valid checksum: binary installed" \
                               || bad "valid checksum: binary not installed"

# --- a corrupted download must not reach the destination ---------------------
dir="$(fixture corrupt corrupt)"
out="$(PATH="$dir/bin:$PATH" "$dir/script.sh" "$dir/dest/cloudflared" 2>&1)"
status=$?
[ $status -ne 0 ] && ok "checksum mismatch: exits non-zero" || bad "checksum mismatch: exited 0"
printf '%s' "$out" | grep -q "checksum mismatch" && ok "checksum mismatch: explains why" \
                                                 || bad "checksum mismatch: unclear error: $out"
[ -e "$dir/dest/cloudflared" ] && bad "checksum mismatch: corrupt binary was installed" \
                               || ok "checksum mismatch: destination untouched"
[ -z "$(ls -A "$dir/dest")" ] && ok "checksum mismatch: staging dir cleaned up" \
                              || bad "checksum mismatch: left $(ls -A "$dir/dest")"

# --- a release with no digest is refused unless overridden -------------------
dir="$(fixture nosum nosum)"
out="$(PATH="$dir/bin:$PATH" "$dir/script.sh" "$dir/dest/cloudflared" 2>&1)"
status=$?
[ $status -ne 0 ] && ok "no checksum published: refuses to install" \
                  || bad "no checksum published: installed anyway"

dir="$(fixture nosum-override nosum)"
out="$(PATH="$dir/bin:$PATH" CLOUDFLARED_SKIP_CHECKSUM=1 "$dir/script.sh" "$dir/dest/cloudflared" 2>&1)"
status=$?
[ $status -eq 0 ] && [ -x "$dir/dest/cloudflared" ] \
  && ok "CLOUDFLARED_SKIP_CHECKSUM=1: installs unverified" \
  || bad "CLOUDFLARED_SKIP_CHECKSUM=1: exit $status: $out"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
