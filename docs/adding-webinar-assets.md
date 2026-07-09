# Adding a new webinar's assets

Notes for posting assets from a session you ran.

1. Create a folder named `YYYY-MM-topic-slug` at the root of the repo.
2. Drop in whatever the session used: slides, sample code, scripts, a link to the recording.
3. Add a page for the session at `docs/mkdocs/docs/webinars/YYYY-MM-topic-slug.md` so it shows up on the docs site. Keep it short: a title, a one-line note on when it happened, and links to the assets folder and the recording. For example:

    ```markdown
    # <Webinar title>

    Held <Month year>.

    - [Session assets](https://github.com/KongHQ-CX/cs-webinars/tree/main/YYYY-MM-topic-slug)
    - [Recording](<link>)
    ```

4. Open a PR.

Merging to `main` publishes the docs site automatically, so there's nothing else to do.
