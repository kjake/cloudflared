#!/usr/bin/env bash
#
# Regression tests for ../update-cloudflared.sh.
#
#   ./tests/update-cloudflared.test.sh
#
# No network and no root: the GitHub release is faked as a JSON file whose
# asset URLs are file:// paths, and `uname` is shadowed on PATH so the NetBSD
# code path runs on any host. Everything lives under a temp directory.
#
# The fake release JSON mirrors the real API's shape — pretty-printed, one
# field per line, "digest" listed before "browser_download_url" inside each
# asset object — because that is what the script's parser relies on.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${1:-$HERE/../update-cloudflared.sh}"
ASSET="cloudflared-netbsd10-amd64"
WRONG_DIGEST="0000000000000000000000000000000000000000000000000000000000000000"

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

pass=0
fail=0

ok()  { echo "PASS: $1"; pass=$((pass + 1)); }
bad() { echo "FAIL: $1"; fail=$((fail + 1)); }

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

# fixture <name> <api: ok|wrong|none> <sha256 asset: ok|none> <binary: intact|corrupt>
# Builds a self-contained release plus a copy of the script pointed at it, and
# echoes the case directory.
fixture() {
  local name="$1" api="$2" sum="$3" binary="$4" dir="$TMPROOT/$1" hash api_field
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
  hash="$(digest "$dir/assets/$ASSET")"

  [ "$sum" = ok ] && printf '%s  %s\n' "$hash" "$ASSET" > "$dir/assets/$ASSET.sha256"

  # Corrupt after the digests are taken from the pristine binary: that is
  # exactly the broken-download case, a payload no published digest matches.
  [ "$binary" = corrupt ] && printf 'truncated garbage\n' > "$dir/assets/$ASSET"

  case "$api" in
    ok)    api_field="\"sha256:$hash\"" ;;
    wrong) api_field="\"sha256:$WRONG_DIGEST\"" ;;
    none)  api_field="null" ;;
  esac

  {
    echo '{'
    echo '  "assets": ['
    echo '    {'
    echo "      \"name\": \"$ASSET\","
    echo "      \"digest\": $api_field,"
    echo "      \"browser_download_url\": \"file://$dir/assets/$ASSET\""
    if [ "$sum" = ok ]; then
      echo '    },'
      echo '    {'
      echo "      \"name\": \"$ASSET.sha256\","
      echo '      "digest": null,'
      echo "      \"browser_download_url\": \"file://$dir/assets/$ASSET.sha256\""
    fi
    echo '    }'
    echo '  ]'
    echo '}'
  } > "$dir/release.json"

  sed "s#^API_URL=.*#API_URL=\"file://$dir/release.json\"#" "$SCRIPT" > "$dir/script.sh"
  chmod +x "$dir/script.sh"

  printf '%s\n' "$dir"
}

run() { PATH="$1/bin:$PATH" "$1/script.sh" "$1/dest/cloudflared" 2>&1; }

# --- both digest sources present and correct ---------------------------------
dir="$(fixture both ok ok intact)"
out="$(run "$dir")"; status=$?
[ $status -eq 0 ] && ok "both sources: exits 0" || bad "both sources: exit $status: $out"
printf '%s' "$out" | grep -q "verified against GitHub's published asset digest" \
  && ok "both sources: checks the API digest" || bad "both sources: skipped the API digest"
printf '%s' "$out" | grep -q "verified against $ASSET.sha256" \
  && ok "both sources: checks the .sha256 asset" || bad "both sources: skipped the .sha256 asset"
[ -x "$dir/dest/cloudflared" ] && ok "both sources: binary installed" \
                               || bad "both sources: binary not installed"

# --- API digest alone is enough (covers releases with no .sha256 asset) ------
dir="$(fixture apionly ok none intact)"
out="$(run "$dir")"; status=$?
[ $status -eq 0 ] && [ -x "$dir/dest/cloudflared" ] \
  && ok "API digest only: installs with no .sha256 asset" \
  || bad "API digest only: exit $status: $out"

# --- a corrupted download must not reach the destination ---------------------
dir="$(fixture corrupt ok ok corrupt)"
out="$(run "$dir")"; status=$?
[ $status -ne 0 ] && ok "corrupt download: exits non-zero" || bad "corrupt download: exited 0"
printf '%s' "$out" | grep -q "checksum mismatch" && ok "corrupt download: explains why" \
                                                 || bad "corrupt download: unclear error: $out"
[ -e "$dir/dest/cloudflared" ] && bad "corrupt download: corrupt binary was installed" \
                               || ok "corrupt download: destination untouched"
[ -z "$(ls -A "$dir/dest")" ] && ok "corrupt download: staging dir cleaned up" \
                              || bad "corrupt download: left $(ls -A "$dir/dest")"

# --- sources disagreeing means the upload was damaged, so refuse -------------
dir="$(fixture disagree wrong ok intact)"
out="$(run "$dir")"; status=$?
[ $status -ne 0 ] && [ ! -e "$dir/dest/cloudflared" ] \
  && ok "sources disagree: refuses even though .sha256 matches" \
  || bad "sources disagree: exit $status: $out"

# --- a release with no digest at all is refused unless overridden ------------
dir="$(fixture nodigest none none intact)"
out="$(run "$dir")"; status=$?
[ $status -ne 0 ] && ok "no digest published: refuses to install" \
                  || bad "no digest published: installed anyway"

dir="$(fixture nodigest-override none none intact)"
out="$(PATH="$dir/bin:$PATH" CLOUDFLARED_SKIP_CHECKSUM=1 "$dir/script.sh" "$dir/dest/cloudflared" 2>&1)"
status=$?
[ $status -eq 0 ] && [ -x "$dir/dest/cloudflared" ] \
  && ok "CLOUDFLARED_SKIP_CHECKSUM=1: installs unverified" \
  || bad "CLOUDFLARED_SKIP_CHECKSUM=1: exit $status: $out"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
