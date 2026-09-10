# Surgical patches

Every `*.patch` file in this directory is applied by
[`.github/workflows/update-cloudflared.yml`](../.github/workflows/update-cloudflared.yml)
on top of a pristine checkout of the target upstream `cloudflared` release tag,
via `git apply --3way`.

Patches express *intent* rather than whole-file copies, so they survive
surrounding upstream churn. Two rules follow from that:

- If a patch no longer applies, upstream has refactored the code it touches.
  The release workflow fails loudly so the diff can be re-derived by hand
  against the new upstream state.
- If a patch is already present *verbatim* upstream, the workflow detects this
  (`git apply --reverse --check` succeeds), logs a notice, and skips it. That is
  the signal to delete the patch file; it has served its purpose. The check is
  textual, so upstream adopting the idea while rewording the surrounding code
  reads as the first case, not this one. When a patch stops applying, rule out
  upstream adoption before re-deriving anything.

## Format

Plain `git diff` output with paths relative to the repository root. Free-form
prose above the first `diff --git` line is ignored by `git apply` and is the
right place to record why the patch exists and what to do when it breaks.

## History

- `0001-preserve-quic-stream-error-causes.patch` — added `Cause` plus `Unwrap()`
  to `ControlStreamError`, `StreamListenerError`, and `DatagramManagerError` so
  `supervisor.isQuicBroken()` could see through them to the underlying
  `quic.IdleTimeoutError` / `quic.TransportError` and trigger the HTTP/2
  fallback on BSDs (issue #10). Upstream adopted the same change in **2026.9.0**,
  so the patch was removed. No behavioral deviation from upstream remains.
