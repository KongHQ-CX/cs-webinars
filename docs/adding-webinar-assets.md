# Adding a new webinar's assets

Notes for posting assets from a session you ran.

1. Create a folder named `webinars/YYYY-MM-topic-slug/`. Base the slug on the session's registration page title (kebab-case, trimmed if it's long), so it matches what attendees already saw when they signed up.
2. Drop in whatever the session used: slides, sample code, scripts. Keep individual files under GitHub's 100 MB limit. Leave the recording out of the repo and link to wherever it's hosted instead.
3. Add a page for the session at `docs/mkdocs/docs/webinars/YYYY-MM-topic-slug.md` so it shows up on the docs site. Reuse the registration page's title and description instead of writing new copy. Leave `{{ RELEASE_ZIP }}` exactly as written. The docs workflow fills it in with the release download link automatically when the site rebuilds. For example:

    ```markdown
    # <Webinar title>

    Held <Month year>.

    <One or two sentences from the registration page describing what the session covered.>

    - [Download everything (zip)]({{ RELEASE_ZIP }})
    - [Recording](<link>)
    ```

4. Open a PR.

Merging to `main` does the rest: a workflow zips `webinars/YYYY-MM-topic-slug/` and publishes it as a GitHub Release tagged `YYYY-MM-topic-slug`, and the docs site rebuilds, filling in the `{{ RELEASE_ZIP }}` placeholder and redeploying. See [docs/github-actions.md](github-actions.md) for what each workflow does and where to check if one fails.
