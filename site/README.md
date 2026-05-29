# Open Island — landing site

Pixel-retro, single-page marketing site for Open Island. Astro static output,
bilingual (English + 简体中文), dark base + CRT amber accent. The centerpiece is
a self-playing "notch island" demo (`src/components/NotchMockup.astro`) — an
original re-implementation of the morphing-island technique: a resizing `#island`
div state machine, canvas pixel sprites, a fake cursor, a `setTimeout` storyboard,
and `IntersectionObserver` playback gating, with a `prefers-reduced-motion`
static fallback.

## Develop

```bash
cd site
npm install
npm run dev        # http://localhost:4321
```

## Build

```bash
npm run build      # → site/dist/ (static)
npm run preview    # serve the build locally
```

## Deploy (X-Pages)

The build is plain static files. Set `SITE_BASE` to the sub-path X-Pages serves
from so asset URLs resolve, then build and ship `dist/`:

```bash
SITE_BASE=/your-xpages-path/ npm run build
# then deploy site/dist/ via the xpages-deploy workflow
```

All internal asset URLs are built from `import.meta.env.BASE_URL`, so setting
`SITE_BASE` at build time is enough — no per-file edits needed.

## Structure

```
src/
  layouts/BaseLayout.astro   head, fonts, JSON-LD, language init + persistence
  pages/index.astro          composes all sections
  components/
    T.astro                  bilingual <span lang> helper (CSS toggles which shows)
    Nav, Hero, NotchMockup, Features, Support, WhyOpen, FAQ, Footer, LangToggle
  styles/global.css          design tokens + shared classes
```

Content (agent/terminal lists, features, FAQ) mirrors the repo `README.md` and
`docs/product.md` — keep them in sync at release time.
