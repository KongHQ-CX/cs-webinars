# Adding a new webinar's assets

Notes for posting assets from a session you ran.

1. Create a folder named `webinars/YYYY-MM-topic-slug/`. Base the slug on the session's registration page title (kebab-case, trimmed if it's long), so it matches what attendees already saw when they signed up.
2. Drop in whatever the session used: slides, sample code, scripts. Keep individual files under GitHub's 100 MB limit. Leave the recording out of the repo and link to wherever it's hosted instead. Double-check there are no API keys, tokens, passwords, or other secrets in what you're committing. Sample code and demo scripts are the most common place these slip in. A secret scan runs on every PR as a fallback, but don't rely on it as your only check. If the scan flags something you know is safe to publish, like a throwaway self-signed cert the lab regenerates, allowlist it per [docs/overriding-a-safe-secret-scan.md](overriding-a-safe-secret-scan.md) instead of merging past the failure.
3. Add a page for the session at `docs/zola/content/webinars/YYYY-MM-topic-slug.md` so it shows up on the docs site. Give it TOML front matter with the session's title and date (use the first of the month, matching the folder's month granularity), then write one or two sentences as the body, reused from the registration page instead of new copy. Add a `recording_url` under `[extra]` if you have one; it renders as a "Watch" button next to the download on the card (point it at the on-demand registration page if that's where the recording lives). The site builds the download link itself from the filename, so there's no placeholder to fill in. For example:

    ```
    +++
    title = "<Webinar title>"
    date = YYYY-MM-01
    [extra]
    recording_url = "<link>"
    +++
    <One or two sentences from the registration page describing what the session covered.>
    ```

4. Open a PR.

Merging to `main` does the rest: a workflow zips `webinars/YYYY-MM-topic-slug/` and publishes it as a GitHub Release tagged `YYYY-MM-topic-slug`, and the docs site rebuilds and redeploys automatically. See [docs/github-actions.md](github-actions.md) for what each workflow does and where to check if one fails.
