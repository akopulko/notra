# Notra landing page

This is a dependency-free, static GitHub Pages site for Notra. Open `index.html` directly for a quick preview, or serve the folder locally so relative paths behave like GitHub Pages:

```sh
python3 -m http.server 8000 --directory notra-app-landing-page
```

Then visit `http://localhost:8000`.

## Publishing with GitHub Pages

1. Commit and push the `notra-app-landing-page/` folder.
2. In the repository, open **Settings → Pages**.
3. Select **Deploy from a branch**, choose the branch, and select `/ (root)` if publishing from a dedicated site branch, or configure the repository workflow to publish this folder.

All links and assets are relative, so the site works from a repository subpath such as `https://USERNAME.github.io/REPOSITORY/`.

## Replacing placeholders

- Add `notra-macos.png`, `notra-iphone.png`, and `notra-ipad.png` to `assets/screenshots/`. The placeholder panels automatically disappear when the images load.
- Replace `IOS_APP_STORE_URL` and `MAC_APP_STORE_URL` in `index.html` with the real App Store links. They appear in the download buttons and footer.
- The logo is at `assets/icons/notra-logo.png`.

The theme follows `prefers-color-scheme` on first load. The header button lets visitors choose light or dark mode, and that choice is saved in `localStorage` under `notra-theme`.
