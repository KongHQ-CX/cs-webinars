# Adding a new webinar's assets

Notes for posting assets from a session you ran.

1. Create a folder named `webinars/YYYY-MM-topic-slug/`. Base the slug on the session's registration page title (kebab-case, trimmed if it's long), so it matches what attendees already saw when they signed up.
2. Drop in whatever the session used: slides, sample code, scripts. Keep individual files under GitHub's 100 MB limit. Leave the recording out of the repo and link to wherever it's hosted instead.
3. Check for secrets before you commit anything. Sample code, demo scripts, `.env` files, decK configs, and curl examples are the most common place these slip in: API keys, tokens, passwords, personal access tokens, webhook URLs with a token baked into the query string, private keys and certs.
   - If a value is a placeholder an attendee is meant to replace with their own — the normal case for `.env.example` files, curl headers, and config samples — use `__REPLACE_ME__` for it. It's the one placeholder value confirmed not to trip the secret scan across `.env`, curl headers, YAML, JSON, and Python. Say what the real value needs to be in a comment above the line, not in the placeholder itself. Details and why other placeholders (`demo-secret-key-123`, `set-me-before-running`) still get flagged are in [docs/overriding-a-safe-secret-scan.md](overriding-a-safe-secret-scan.md).
   - If a value has to be real-looking for a lab to actually run — a throwaway self-signed cert, a token that needs the right shape — that's a different case. Confirm it's genuinely safe (grants access to nothing real, attendees regenerate or replace it, costs nothing if a stranger copies it), then allowlist it per the same doc. Don't merge past a failure you haven't allowlisted; a repo admin can override the check, but the finding just comes back red on the next push.
   - Run the same scan CI runs before you push: `gitleaks detect --source . --redact --no-banner`. `no leaks found` and exit `0` means you're clear. This catches more than the CI run does if you've committed and later removed a secret in the same branch — CI scans the same commit history you're about to push, so a secret is still a finding even after a later commit deletes it.
   - If something you commit turns out to be a live credential, removing it from the file isn't enough — it's still in git history. Rotate it, then follow the "rewrite history" note in [docs/overriding-a-safe-secret-scan.md](overriding-a-safe-secret-scan.md).
4. Add a page for the session at `docs/zola/content/webinars/YYYY-MM-topic-slug.md` so it shows up on the docs site. Give it TOML front matter with the session's title and date (use the first of the month, matching the folder's month granularity), then write one or two sentences as the body, reused from the registration page instead of new copy. Add a `recording_url` under `[extra]` if you have one; it renders as a "Watch" button next to the download on the card (point it at the on-demand registration page if that's where the recording lives). Tag the session via `tags` under `[extra]`; those drive the filter chips on the webinars page. Tags are one pool that mixes Kong products (`Konnect`, `Gateway`, `Mesh`, `AI Gateway`, `Insomnia`) with themes (`Security`, `Observability`, `Migration`, `Getting Started`), so a security-focused Konnect session is `["Konnect", "Security"]`. Use the names from the `tags` list in `docs/zola/config.toml` so the chips stay consistent, and add a new tag there first if you need one that doesn't exist yet. The site builds the download link itself from the filename, so there's no placeholder to fill in. For example:

    ```
    +++
    title = "<Webinar title>"
    date = YYYY-MM-01
    [extra]
    tags = ["Konnect", "Security"]
    recording_url = "<link>"
    +++
    <One or two sentences from the registration page describing what the session covered.>
    ```

5. Open a PR against `main`. Forking is enabled on this repo, and that's the preferred way in regardless of whether you already have collaborator access — it keeps push access scoped to your own copy instead of the shared repo:

    ```bash
    gh repo fork KongHQ-CX/cs-webinars --clone
    cd cs-webinars
    git checkout -b webinars/topic-slug
    # add your files, commit
    git push -u origin webinars/topic-slug
    gh pr create --repo KongHQ-CX/cs-webinars --base main
    ```

    Without the `gh` CLI: click "Fork" on the repo's GitHub page, clone your fork, branch, push to your fork, then open the PR from your fork's branch against `KongHQ-CX/cs-webinars:main`.

    `main` is protected by a repo ruleset: it needs one approving review before merge, and blocks force-pushes to and deletion of `main` itself. Pushing follow-up commits to your PR branch doesn't dismiss an existing approval, so address review feedback with new commits instead of rewriting history. Merge, squash, and rebase are all allowed once it's approved. Two checks run automatically on the PR — `gitleaks` (the secret scan from step 3) and CodeQL; see [docs/github-actions.md](github-actions.md) for what each does and where to check logs if one fails.

Merging to `main` does the rest: a workflow zips `webinars/YYYY-MM-topic-slug/` and publishes it as a GitHub Release tagged `YYYY-MM-topic-slug`, and the docs site rebuilds and redeploys automatically. See [docs/github-actions.md](github-actions.md) for what each workflow does and where to check if one fails.
