# cloudflared Fork

This repository maintains a fork of `cloudflare/cloudflared`, staged for automated upstream updates while preserving our custom CI workflows.

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

   ```bash
   git clone https://github.com/<your-org>/cloudflared.git
   cd cloudflared
   ```

2. **Verify `customizations` is default**

   ```bash
   git branch --show-current  # should output: customizations
   ```

3. **Update README**
   Simply edit this file and push to `customizations`:

   ```bash
   git checkout customizations
   git add README.md
   git commit -m "docs: update README"
   git push origin customizations
   ```

## Automated Upstream Sync

We use a GitHub Actions workflow (`.github/workflows/update-cloudflared.yml`) that runs on a schedule or via manual dispatch. On each run:

1. Fetch the latest upstream release tag from `cloudflare/cloudflared`.
2. Create a new branch `release-<tag>` off of `customizations`.
3. Merge upstream tag into `release-<tag>`, preserving upstream diffs.
4. Apply our `customizations` overlay.
5. Push `release-<tag>` to GitHub and open a PR for manual review.

Conflicts (if any) are surfaced in the PR for one-time resolution.

## Manual Release Workflow (optional)

If you prefer to run sync locally:

```bash
# 1) Fetch new tag
git fetch https://github.com/cloudflare/cloudflared.git tag vX.Y.Z --depth=1

# 2) Create release branch
git checkout -b release-vX.Y.Z customizations

# 3) Merge upstream
git merge FETCH_HEAD --allow-unrelated-histories -m "chore: merge upstream vX.Y.Z"

# 4) Apply overlay
git merge customizations -s recursive -X ours --no-ff -m "chore: apply custom overlay"

# 5) Push and PR
git push -u origin release-vX.Y.Z
```

## Contributing

1. Open issues or PRs against **`customizations`** for any improvements to workflows, docs, or configs.
2. Upstream bugs/features should still be filed against [cloudflare/cloudflared](https://github.com/cloudflare/cloudflared).
