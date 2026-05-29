// @ts-check
import { defineConfig } from 'astro/config';

// Static output — the whole site is prerendered to plain HTML/CSS/JS and
// deployed to X-Pages. `base` is configurable via SITE_BASE so the build can
// be served from a sub-path (X-Pages assigns one) without 404-ing on assets.
// Internal asset URLs are built with import.meta.env.BASE_URL, so setting
// SITE_BASE at build time is all that's needed.
const base = process.env.SITE_BASE || '/';
const site = process.env.SITE_URL || 'https://openisland.app';

export default defineConfig({
  output: 'static',
  site,
  base,
  trailingSlash: 'ignore',
  build: {
    assets: '_assets',
  },
});
