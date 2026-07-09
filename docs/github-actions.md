# What the GitHub Actions do

Two workflows run on every merge to `main`.

## Deploy docs (`.github/workflows/docs.yml`)

Triggers on any push to `main` that touches `docs/**`. Before building, it scans every file in `docs/mkdocs/docs/webinars/` and replaces any `{{ RELEASE_ZIP }}` placeholder with that page's release download URL, computed from the page's own filename (the same slug used for the release tag and the zip name). Then it installs mkdocs and the plugins pinned in `docs/mkdocs/requirements.txt`, builds the site with `mkdocs build --strict`, and deploys the result to GitHub Pages.

## Release webinar assets (`.github/workflows/release-webinar.yml`)

Triggers on any push to `main` that touches `webinars/**`. Diffs the push to find which folders under `webinars/` changed, then for each one:

1. Zips the folder into `<slug>.zip`.
2. Publishes (or updates, if the tag already exists) a GitHub Release tagged with the folder's slug, with the zip attached.

If a session's folder gets edited later, merging that change re-zips and re-publishes the same release, so the download link in the docs page never has to change.

## Where to check if something breaks

Both workflows show up under the repo's Actions tab. A failed run means the docs site or a release didn't publish. Check the job logs there first.
