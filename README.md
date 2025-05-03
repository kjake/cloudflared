# cloudflared for *BSD

This repository maintains a fork of `cloudflare/cloudflared` with minimal customizations in order to build for most *BSD systems.  
The supported automated builds are attached to the Releases area.

The current supported build targets are:
* FreeBSD 14 (amd64)
* OpenBSD 7 (amd64)
* NetBSD 10 (amd64)

Builds happen on virtual machines and are not cross-compiled in Linux:
```yaml
cloudflared-freebsd14-amd64: ELF 64-bit LSB executable, x86-64, version 1 (FreeBSD), statically linked, for FreeBSD 12.3, FreeBSD-style, Go BuildID=whtbnhgLy_4DNlvoQVLN/sdPbSLy5tutf2R4FBg0D/tkLU1W0BkczEJ-UfmxXi/-wnnwpjpQM5JSMNpsu8B, with debug_info, not stripped

cloudflared-openbsd7-amd64: ELF 64-bit LSB executable, x86-64, version 1 (OpenBSD), dynamically linked, interpreter /usr/libexec/ld.so, for OpenBSD, Go BuildID=sKt-KKXK70xaz3xIjpcG/DI00O_ESV89p0mlN2FHW/CxKapph2Ks5I7Pe4q00b/xlodVQBnz_4GDBLMx3C-, with debug_info, not stripped

cloudflared-netbsd10-amd64: ELF 64-bit LSB executable, x86-64, version 1 (NetBSD), statically linked, for NetBSD 7.0, BuildID[sha1]=ee1a86cd4d2281c56b0c2e124f8337716aa22844, with debug_info, not stripped
```

---

## Branching Model

* **`customizations` (default)**

  * Contains *only* our fork-specific changes (CI config, workflows, branding, etc.).
  * Users and automation never push directly to this branch—it serves as the persistent overlay.

* **`release-<tag>`**

  * Created automatically (or manually) for each new upstream release tag (e.g. `release-2025.4.2`).
  * Merges the upstream tag, then applies `customizations` on top.
  * Open a PR from this branch into `customizations` to review upstream changes + overlay.

## Getting Started

1. **Clone your fork**

   ```sh
   git clone https://github.com/<your-org>/cloudflared.git
   cd cloudflared
   ```

2. **Verify `customizations` is default**

   ```sh
   git branch --show-current  # should output: customizations
   ```

3. **Update README**
   Simply edit this file and push to `customizations`:

   ```sh
   git checkout customizations
   git add README.md
   git commit -m "docs: update README"
   git push origin customizations
   ```

## Contributing

1. Open issues or PRs against **`customizations`** for any improvements to workflows, docs, or configs.
2. Upstream bugs/features should still be filed against [cloudflare/cloudflared](https://github.com/cloudflare/cloudflared).
