# Adding a new webinar's assets

Notes for posting assets from a session you ran.

1. Create a folder named `webinars/YYYY-MM-topic-slug/`.
2. Drop in whatever the session used: slides, sample code, scripts. Keep individual files under GitHub's 100 MB limit. Leave the recording out of the repo and link to wherever it's hosted instead.
3. Add a page for the session at `docs/mkdocs/docs/webinars/YYYY-MM-topic-slug.md` so it shows up on the docs site. List each file as a direct download link using its `raw.githubusercontent.com` URL instead of linking to the GitHub folder view. That's what makes the file download when someone clicks it, rather than opening GitHub's UI. For example:

    ```markdown
    # <Webinar title>

    Held <Month year>.

    ## Downloads

    - [Slides (PDF)](https://raw.githubusercontent.com/KongHQ-CX/cs-webinars/main/webinars/YYYY-MM-topic-slug/slides.pdf)
    - [Sample code (zip)](https://raw.githubusercontent.com/KongHQ-CX/cs-webinars/main/webinars/YYYY-MM-topic-slug/demo-code.zip)

    ## More

    - [Full folder on GitHub](https://github.com/KongHQ-CX/cs-webinars/tree/main/webinars/YYYY-MM-topic-slug)
    - [Recording](<link>)
    ```

4. Open a PR.

Merging to `main` publishes the docs site automatically, so there's nothing else to do.
