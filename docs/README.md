# Notra landing page

This is a dependency-free, static GitHub Pages site for Notra. Open `index.html` directly for a quick preview, or serve the folder locally so relative paths behave like GitHub Pages:

```sh
python3 -m http.server 8000 --directory docs
```

Then visit `http://localhost:8000`.

## Publishing with GitHub Pages

1. Commit and push the `docs/` folder.
2. In the repository, open **Settings → Pages**.
3. Select **Deploy from a branch**, choose the branch, and select `/ (root)` if publishing from a dedicated site branch, or configure the repository workflow to publish this folder.

All links and assets are relative, so the site works from a repository subpath such as `https://USERNAME.github.io/REPOSITORY/`.

## Site assets and theme

Product screenshots live in `assets/screenshots/`; the promo video and poster live in `assets/video/`; official GitHub marks and the Notra logo live in `assets/icons/`.

The theme follows `prefers-color-scheme` on first load. The header button lets visitors choose light or dark mode, and that choice is saved in `localStorage` under `notra-theme`.
