# Adding a new webinar's assets

Notes for posting assets from a session you ran.

1. Create a folder named `webinars/YYYY-MM-topic-slug/`.
2. Drop in whatever the session used: slides, sample code, scripts. Keep individual files under GitHub's 100 MB limit. Leave the recording out of the repo and link to wherever it's hosted instead.
3. Add a page for the session at `docs/mkdocs/docs/webinars/YYYY-MM-topic-slug.md` so it shows up on the docs site. Keep it short: a title, a one-line note on when it happened, and links to the release download and the recording. For example:

    ```markdown
    # <Webinar title>

    Held <Month year>.

    - [Download everything (zip)](https://github.com/KongHQ-CX/cs-webinars/releases/download/YYYY-MM-topic-slug/YYYY-MM-topic-slug.zip)
    - [Recording](<link>)
    ```

4. Open a PR.

Merging to `main` does the rest: a workflow zips `webinars/YYYY-MM-topic-slug/` and publishes it as a GitHub Release tagged `YYYY-MM-topic-slug`, and the docs site rebuilds and redeploys. See [docs/github-actions.md](github-actions.md) for what each workflow does and where to check if one fails.
