/* NotchTune landing — live version, reveals, dynamic island demo */
(function () {
  "use strict";

  const REPO = "dw2lam/NotchTune";

  /* ---------- live latest-release version ---------- */
  function applyVersion(tag, htmlUrl) {
    const v = String(tag || "").replace(/^v/i, "");
    if (!v) return;
    document.querySelectorAll("[data-latest-version]").forEach((el) => (el.textContent = v));
    document.querySelectorAll("[data-download-label]").forEach((el) => (el.textContent = "Download v" + v + " for macOS"));
    document.querySelectorAll("[data-release-meta]").forEach((el) => (el.textContent = "Latest release · v" + v));
    if (htmlUrl) {
      document.querySelectorAll("[data-download-latest]").forEach((el) => (el.href = htmlUrl));
    }
  }

  fetch("https://api.github.com/repos/" + REPO + "/releases/latest", {
    headers: { Accept: "application/vnd.github+json" },
  })
    .then((r) => (r.ok ? r.json() : Promise.reject(r.status)))
    .then((data) => {
      // Prefer the .dmg asset URL if present, else the release page.
      const dmg = (data.assets || []).find((a) => /\.dmg$/i.test(a.name));
      applyVersion(data.tag_name, dmg ? dmg.browser_download_url : data.html_url);
    })
    .catch(() => {/* keep static fallback (0.1.2) */});

  /* ---------- scroll reveal ---------- */
  const io = new IntersectionObserver(
    (entries) => {
      entries.forEach((e) => {
        if (e.isIntersecting) {
          e.target.classList.add("in");
          io.unobserve(e.target);
        }
      });
    },
    { threshold: 0.12, rootMargin: "0px 0px -8% 0px" }
  );
  document.querySelectorAll(".reveal").forEach((el) => io.observe(el));

  /* ---------- nav elevate on scroll ---------- */
  const nav = document.getElementById("nav");
  const onScroll = () => nav && nav.classList.toggle("scrolled", window.scrollY > 12);
  window.addEventListener("scroll", onScroll, { passive: true });
  onScroll();

  /* ---------- real pixel island buddies ---------- */
  // 9x9 idle frames lifted verbatim from the app (UnifiedBars.swift). 1 = cream pixel.
  const SPRITES = {
    dino: [
      [0,0,0,0,1,1,1,1,1],[0,0,0,0,1,0,1,1,1],[0,0,0,0,1,1,1,1,1],
      [0,0,1,1,1,1,1,0,0],[0,1,1,1,1,1,1,1,0],[1,1,1,1,1,1,1,0,0],
      [1,0,1,1,1,1,1,0,0],[0,0,0,1,0,1,0,0,0],[0,0,0,1,0,0,0,0,0]],
    ghost: [
      [0,0,1,1,1,1,1,0,0],[0,1,1,1,1,1,1,1,0],[0,1,0,1,1,0,1,1,0],
      [0,1,1,1,1,1,1,1,0],[0,1,1,1,1,1,1,1,0],[0,1,1,1,1,1,1,1,0],
      [0,1,1,1,1,1,1,1,0],[0,1,1,1,1,1,1,1,0],[0,1,0,1,0,1,0,1,0]],
    crab: [
      [1,0,1,0,0,0,1,0,1],[0,1,0,0,0,0,0,1,0],[0,0,1,1,1,1,1,0,0],
      [1,1,1,1,1,1,1,1,1],[1,0,1,1,1,1,1,0,1],[0,0,1,1,1,1,1,0,0],
      [0,1,0,1,0,1,0,1,0],[1,0,0,0,0,0,0,0,1],[0,0,0,0,0,0,0,0,0]],
    duck: [
      [0,0,0,0,1,1,1,0,0],[0,0,0,0,1,0,1,1,1],[0,0,0,0,1,1,1,0,0],
      [0,0,0,0,0,1,1,0,0],[0,1,1,1,1,1,1,0,0],[1,1,0,1,1,1,1,0,0],
      [1,1,1,1,1,1,1,0,0],[0,0,1,0,1,0,0,0,0],[0,0,1,1,0,1,1,0,0]],
    claude: [
      [0,0,0,0,0,0,0,0,0],[0,0,0,0,0,0,0,0,0],[0,1,1,1,1,1,1,1,0],
      [0,1,0,1,1,1,0,1,0],[1,1,1,1,1,1,1,1,1],[0,1,1,1,1,1,1,1,0],
      [0,1,0,1,0,1,0,1,0],[0,1,0,1,0,1,0,1,0],[0,1,0,1,0,1,0,1,0]],
  };
  document.querySelectorAll(".sprite[data-char]").forEach((el) => {
    const grid = SPRITES[el.dataset.char];
    if (!grid) return;
    let rects = "";
    grid.forEach((row, y) =>
      row.forEach((v, x) => { if (v) rects += '<rect x="' + x + '" y="' + y + '" width="1" height="1"/>'; })
    );
    el.innerHTML =
      '<svg viewBox="0 0 9 9" shape-rendering="crispEdges" fill="#f1ead9" xmlns="http://www.w3.org/2000/svg">' +
      rects + "</svg>";
  });

  /* ---------- liquid glass lab (mirrors the app's real glass settings) ---------- */
  const island = document.getElementById("labIsland");
  if (island) {
    // Real model from LiquidGlassSettings: enable, material (clear/frosted),
    // tint color, tint strength. Default: enabled, clear, black tint @ 22%.
    const state = { enabled: true, material: "clear", tint: [0, 0, 0], strength: 22 };
    const enable = document.getElementById("ctl-enable");
    const strength = document.getElementById("ctl-strength");
    const matNote = document.querySelector("[data-mat-note]");
    const strengthOut = document.querySelector('[data-val="strength"]');
    const MAT_NOTE = {
      clear: "Transparent, light-bending glass — the most “liquid” look.",
      frosted: "Frosted, more opaque glass with stronger contrast.",
    };

    function render() {
      const [r, g, b] = state.tint;
      const a = state.strength / 100;
      if (!state.enabled) {
        // solid-black fallback (no Liquid Glass)
        island.style.background = "#050507";
        island.style.backdropFilter = island.style.webkitBackdropFilter = "none";
        island.style.borderColor = "rgba(255,255,255,.06)";
        island.style.color = "#fff";
      } else {
        const frost = state.material === "frosted" ? 0.17 : 0.04;
        const blur = state.material === "frosted" ? 30 : 18;
        island.style.background =
          "linear-gradient(155deg,rgba(255,255,255,.16),transparent 38%)," +
          "rgba(" + r + "," + g + "," + b + "," + a.toFixed(2) + ")," +
          "rgba(255,255,255," + frost + ")";
        island.style.backdropFilter = island.style.webkitBackdropFilter =
          "blur(" + blur + "px) saturate(150%)";
        island.style.borderColor = "rgba(255,255,255,.16)";
        const lum = 0.299 * r + 0.587 * g + 0.114 * b;
        island.style.color = a > 0.5 && lum > 150 ? "#10131c" : "#fff";
      }
      strengthOut.textContent = state.strength + "%";
      matNote.textContent = MAT_NOTE[state.material];
      const dis = !state.enabled;
      document.querySelectorAll(".lab-group").forEach((gp) => gp.classList.toggle("is-disabled", dis));
    }

    enable.addEventListener("change", () => { state.enabled = enable.checked; render(); });
    strength.addEventListener("input", () => { state.strength = +strength.value; render(); });
    document.querySelectorAll("[data-mat]").forEach((btn) =>
      btn.addEventListener("click", () => {
        if (!state.enabled) return;
        state.material = btn.dataset.mat;
        document.querySelectorAll("[data-mat]").forEach((b) => b.classList.toggle("is-on", b === btn));
        render();
      }));
    document.querySelectorAll(".swatch").forEach((btn) =>
      btn.addEventListener("click", () => {
        if (!state.enabled) return;
        state.tint = btn.dataset.tint.split(",").map(Number);
        document.querySelectorAll(".swatch").forEach((b) => b.classList.toggle("is-on", b === btn));
        render();
      }));
    render();
  }

  /* ---------- dynamic island switch demo ---------- */
  const demo = document.querySelector("[data-island-demo]");
  if (demo && !window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
    const states = demo.querySelectorAll("[data-state]");
    const labels = document.querySelectorAll("[data-demo-label]");
    const order = ["music", "agents", "approve", "music"];
    let i = 0;
    const show = (name) => {
      states.forEach((s) => s.classList.toggle("active", s.dataset.state === name));
      labels.forEach((l) => l.classList.toggle("active", l.dataset.demoLabel === name));
    };
    show(order[0]);
    let running = true;
    const tick = () => {
      if (!running) return;
      i = (i + 1) % order.length;
      show(order[i]);
    };
    let timer = setInterval(tick, 2600);
    // pause when offscreen
    const vis = new IntersectionObserver((es) => {
      es.forEach((e) => {
        running = e.isIntersecting;
      });
    }, { threshold: 0.3 });
    vis.observe(demo);
  }
})();
