# NotchTune — marketing site

The landing page for NotchTune. A single static page: liquid-glass UI demos
that mirror the real app, an interactive "Tune the glass" playground, a
comparison section, and a download CTA that pulls the latest release version
live from the GitHub API.

No build step, no dependencies. Just `index.html`, `styles.css`, `app.js`, and
`assets/`.

## Run locally

```bash
cd website
python3 -m http.server 8745
# open http://localhost:8745
```

## Deploy on Vercel

This site lives in a subfolder of the app repo, so point Vercel at it:

1. Import the `dw2lam/NotchTune` repo into Vercel.
2. **Settings → General → Root Directory** → set to `website`.
3. **Framework Preset**: `Other` (static — no build command, no install).
4. Deploy. `vercel.json` handles clean URLs and long-cache headers for assets.

Production tracks `main`; pushes to other branches get preview URLs.

## Notes

- The download button reads the latest release from
  `https://api.github.com/repos/dw2lam/NotchTune/releases/latest` and falls back
  to a baked-in version if the API is unreachable.
- The notch UI panels are faithful CSS recreations of the real app surfaces
  (agents list, music player, approvals, the Agents/Music tabs, usage pills),
  not screenshots — so they scale crisply and stay in sync with the brand.
