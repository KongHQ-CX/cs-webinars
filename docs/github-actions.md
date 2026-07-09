# What the GitHub Actions do

Three workflows run on every merge to `main`.

## Deploy docs (`.github/workflows/docs.yml`)

Triggers on any push to `main` that touches `docs/**`. It downloads a pinned, checksum-verified [Zola](https://www.getzola.org/) binary, runs `zola check` to catch broken links or config errors, builds the site with `zola build`, and deploys the result to GitHub Pages. The site itself computes each webinar's download link straight from its content filename (the same slug used for the release tag and the zip name), so there's no placeholder-substitution step in this workflow at all.

## Release webinar assets (`.github/workflows/release-webinar.yml`)

Triggers on any push to `main` that touches `webinars/**`. Diffs the push to find which folders under `webinars/` changed, then for each one:

1. Zips the folder into `<slug>.zip`.
2. Publishes (or updates, if the tag already exists) a GitHub Release tagged with the folder's slug, with the zip attached.

If a session's folder gets edited later, merging that change re-zips and re-publishes the same release, so the download link in the docs page never has to change.

## Secret scan (`.github/workflows/secret-scan.yml`)

Runs on every PR into `main` and every push to `main`. It downloads a pinned version of [gitleaks](https://github.com/gitleaks/gitleaks), verifies the download against a known checksum, and scans the full commit history for anything that looks like a credential. This is a backstop, not the primary defense: check your own files for secrets before you commit, per [docs/adding-webinar-assets.md](adding-webinar-assets.md).

Gitleaks reads its config from [`.gitleaks.toml`](../.gitleaks.toml) at the repo root, which extends the default ruleset with a short allowlist of values we have confirmed are safe to publish (a lab's throwaway self-signed cert, for example). When the scan flags something you know is safe, add a scoped allowlist entry there rather than merging past the failure. The process is written up in [docs/overriding-a-safe-secret-scan.md](overriding-a-safe-secret-scan.md).

## Where to check if something breaks

All three workflows show up under the repo's Actions tab. A failed docs or release run means the site or a release didn't publish; check the job logs there first. A failed secret scan means it found something that looks like a credential. Don't merge until you've confirmed what it flagged and either removed it (rewriting history if it already landed in a commit) or, if it's genuinely safe to publish, allowlisted it per [docs/overriding-a-safe-secret-scan.md](overriding-a-safe-secret-scan.md).

PRs from forks are a special case: GitHub holds their workflow runs in an `action_required` state until a maintainer approves them from the Actions tab, so a fork PR with no visible checks usually just means nobody's approved the run yet, not that the workflows didn't apply.
