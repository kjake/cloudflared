# cloudflared for *BSD

This is a fork of [cloudflare/cloudflared](https://github.com/cloudflare/cloudflared) that ships official binaries for FreeBSD, NetBSD, and OpenBSD. Cloudflare doesn't publish *BSD builds; this fork adds a thin overlay of BSD-portability shims and a CI pipeline that builds inside real BSD VMs (not cross-compiled from Linux). The binary is functionally identical to upstream — same tunnels, WARP routing, SSH proxy, diagnostic, and ingress code paths. Every deviation from upstream is captured in [`patches/`](patches/). As of 2026.9.0 the only one is a build-file portability fix (teaching the `Makefile` that NetBSD exists); there are no behavioral deviations, upstream having adopted this fork's QUIC error-preservation tweak (see issue #10).

Upstream is polled every 12 hours; a new upstream release produces a matching release here, usually within a few hours of upstream's announcement.

## Supported targets

| OS      | Version | Architecture | Asset                         |
| ------- | ------- | ------------ | ----------------------------- |
| FreeBSD | 14.4    | amd64        | `cloudflared-freebsd14-amd64` |
| FreeBSD | 15.1    | amd64        | `cloudflared-freebsd15-amd64` |
| OpenBSD | 7.9     | amd64        | `cloudflared-openbsd7-amd64`  |
| NetBSD  | 10.1    | amd64        | `cloudflared-netbsd10-amd64`  |
| NetBSD  | 11.0    | amd64        | `cloudflared-netbsd11-amd64`  |

See [Build provenance](#build-provenance) at the bottom for binary metadata.

## Install or update

The same script handles first install and subsequent updates — it detects your OS, pulls the matching latest-release binary from this repo, and replaces the target path. If a `cloudflared` service is running, it'll be stopped and restarted around the swap.

```sh
curl -fsSL https://raw.githubusercontent.com/kjake/cloudflared/customizations/update-cloudflared.sh \
  -o update-cloudflared.sh
chmod +x update-cloudflared.sh
./update-cloudflared.sh /usr/local/bin/cloudflared
```

Before anything is installed, the script verifies the download against two digests: the SHA-256 GitHub computes for every release asset at upload time and returns in its API, and a `<asset>.sha256` that CI publishes next to each binary. Any mismatch — or a binary that won't run `--version` — and the destination is left untouched. The swap itself is an atomic same-filesystem rename, so an interrupted update can't leave a half-written binary in place.

GitHub's digests go back to the 2025.6.1 release here, so nothing needs to have been published with a `.sha256` for verification to work. Only releases older than that have nothing to check against; `CLOUDFLARED_SKIP_CHECKSUM=1` covers that case. Trust in the digests themselves still derives from `raw.githubusercontent.com` plus the public CI pipeline in [`.github/workflows/`](.github/workflows/) — the script is ~250 lines, so skim it before running.

## Service setup

Once the binary is in place, wire it into your init system and configure a tunnel. Service-install specifics vary by OS — check `cloudflared service --help` or hand-roll an rc.d script. For day-to-day operation:

```sh
# FreeBSD / OpenBSD (sysrc-style enable, then start)
service cloudflared start
service cloudflared restart
service cloudflared stop
```

On OPNsense, the configured tunnel mode lives in `/etc/rc.conf` via `sysrc cloudflared_mode='...'` — see the QUIC tuning section below for an example.

## QUIC stability tuning

If logs intermittently show:

- `failed to accept QUIC stream: timeout: no recent network activity`
- `failed to accept QUIC stream: Application error 0x0 (remote)`

you can improve stability by increasing UDP socket buffers and (if that's not enough) disabling QUIC path-MTU discovery.

**Runtime:**

```sh
sysctl kern.ipc.maxsockbuf=16777216
sysctl net.inet.udp.recvspace=8388608
```

**Persist (FreeBSD / NetBSD)** — append to `/etc/sysctl.conf`:

```conf
kern.ipc.maxsockbuf=16777216
net.inet.udp.recvspace=8388608
```

**Persist (OPNsense)** — System → Settings → Tunables, add the same two `kern.ipc.maxsockbuf` and `net.inet.udp.recvspace` values.

**Disable PMTU discovery** for cloudflared if QUIC still misbehaves:

```sh
sysrc cloudflared_mode='tunnel --no-autoupdate --quic-disable-pmtu-discovery run'
service cloudflared restart
```

`--quic-disable-pmtu-discovery` must appear before `run`. Occasional `Application error 0x0 (remote)` can still occur after tuning and does not by itself prove packet corruption.

## How upstream tracking works

Two branches matter:

- **`customizations`** (default) — the persistent thin overlay. Contains the build workflows, BSD-portability shims for `diagnostic/` and `ingress/`, [`patches/`](patches/), the install script, and this README. Nothing else. Note the `Makefile` is *not* here: it is inherited from upstream unmodified, with the one BSD delta applied from [`patches/`](patches/).
- **`release-<tag>`** (auto-generated) — created on every new upstream release by [`.github/workflows/update-cloudflared.yml`](.github/workflows/update-cloudflared.yml). Starts from upstream's tag, overlays the customizations files, applies `patches/*.patch`, and force-pushes. These branches are throwaway build artifacts — don't open PRs against them.

To contribute, open issues or PRs against `customizations`. Upstream bugs and feature requests should still go to [cloudflare/cloudflared](https://github.com/cloudflare/cloudflared); upstream does accept patches from time to time, and a patch that lands there is removed from [`patches/`](patches/).

## Build provenance

Binaries are built inside real BSD VMs in CI (`vmactions/freebsd-vm@v1`, `netbsd-vm@v1`, `openbsd-vm@v1`), not cross-compiled from Linux. Resulting `file` output:

```text
cloudflared-freebsd14-amd64: ELF 64-bit LSB executable, x86-64, version 1 (FreeBSD), statically linked, for FreeBSD 12.3, FreeBSD-style, Go BuildID=…, with debug_info, not stripped

cloudflared-openbsd7-amd64:  ELF 64-bit LSB executable, x86-64, version 1 (OpenBSD), dynamically linked, interpreter /usr/libexec/ld.so, for OpenBSD, Go BuildID=…, with debug_info, not stripped

cloudflared-netbsd10-amd64:  ELF 64-bit LSB executable, x86-64, version 1 (NetBSD), statically linked, for NetBSD 7.0, BuildID[sha1]=…, with debug_info, not stripped
```

Two things worth knowing:

- **OpenBSD dynamically links** by policy — the OS doesn't ship a static libc, and Go follows suit.
- **"for FreeBSD 12.3" / "for NetBSD 7.0"** are Go's runtime baseline (minimum kernel version the binary will run on), set by the Go linker as a fixed ELF note — not derived from the build host. Inspect it with `readelf -n <binary> | grep -A2 FreeBSD`. The build host versions are listed in [Supported targets](#supported-targets).
