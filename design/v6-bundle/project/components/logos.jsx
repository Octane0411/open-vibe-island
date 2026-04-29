// Logomarks — 3 directions
// A: Liquid Glass (SVG gradient squircle with flowing blob)
// B: Pixel 8-bit (grid-based glyph)
// C: Terminal / ASCII (monospace composition)

const { useEffect, useRef, useState } = React;

// ---------- Direction A: Liquid Glass ----------
function LogoLiquid({ size = 128, animated = true, theme = 'violet' }) {
  const id = React.useId();
  const palette = {
    violet: ['#5b2cf5', '#ff2d87', '#22d3ee'],
    ocean:  ['#0ea5e9', '#22d3ee', '#a78bfa'],
    sunset: ['#ff4d6d', '#ffba08', '#ff8e3c'],
    mono:   ['#2a2a36', '#4a4a58', '#8a8a98'],
  }[theme] || ['#5b2cf5', '#ff2d87', '#22d3ee'];

  return (
    <svg width={size} height={size} viewBox="0 0 128 128" style={{ display: 'block' }}>
      <defs>
        <linearGradient id={`${id}-base`} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0%" stopColor={palette[0]} />
          <stop offset="55%" stopColor={palette[1]} />
          <stop offset="100%" stopColor={palette[2]} />
        </linearGradient>
        <radialGradient id={`${id}-sheen`} cx="0.3" cy="0.2" r="0.9">
          <stop offset="0%" stopColor="rgba(255,255,255,0.55)" />
          <stop offset="40%" stopColor="rgba(255,255,255,0.08)" />
          <stop offset="100%" stopColor="rgba(255,255,255,0)" />
        </radialGradient>
        <clipPath id={`${id}-clip`}>
          <rect x="6" y="6" width="116" height="116" rx="28" ry="28" />
        </clipPath>
        <filter id={`${id}-blur`}>
          <feGaussianBlur stdDeviation="6" />
        </filter>
      </defs>

      {/* Squircle background */}
      <rect x="6" y="6" width="116" height="116" rx="28" ry="28" fill={`url(#${id}-base)`} />

      {/* Flowing blob */}
      <g clipPath={`url(#${id}-clip)`}>
        <g style={animated ? { animation: 'flow 9s ease-in-out infinite', transformOrigin: '64px 64px' } : {}}>
          <ellipse cx="40" cy="40" rx="48" ry="36" fill={palette[2]} opacity="0.55" filter={`url(#${id}-blur)`} />
          <ellipse cx="90" cy="90" rx="40" ry="52" fill={palette[0]} opacity="0.45" filter={`url(#${id}-blur)`} />
        </g>
        {/* The island — a horizon pill */}
        <g transform="translate(64 72)">
          <rect x="-30" y="-7" width="60" height="14" rx="7" fill="rgba(255,255,255,0.96)" />
          <rect x="-30" y="-7" width="60" height="14" rx="7" fill={`url(#${id}-sheen)`} opacity="0.8" />
        </g>
        {/* Glass sheen top */}
        <rect x="6" y="6" width="116" height="116" rx="28" ry="28" fill={`url(#${id}-sheen)`} opacity="0.9" />
      </g>

      {/* Edge highlight */}
      <rect x="6.5" y="6.5" width="115" height="115" rx="27.5" ry="27.5" fill="none" stroke="rgba(255,255,255,0.25)" strokeWidth="1" />
    </svg>
  );
}

// ---------- Direction B: Pixel 8-bit ----------
function LogoPixel({ size = 128, animated = true, theme = 'green' }) {
  // 16x16 grid — an island silhouette with a prompt
  // 0 = empty, 1 = ink, 2 = highlight, 3 = accent
  const grid = [
    "................",
    "................",
    ".....111........",
    "....12211.......",
    "...1122211......",
    "..112222211..33.",
    ".1122222221.333.",
    "1112222222111333",
    "1111111111111111",
    ".1..............",
    "................",
    "................",
    "......33........",
    "......33........",
    "................",
    "................",
  ];
  const paletteMap = {
    green:  { 1: '#147a3a', 2: '#39ff88', 3: '#ffbf3c', bg: '#08120c' },
    amber:  { 1: '#7a4a14', 2: '#ffbf3c', 3: '#ff5bd1', bg: '#120e08' },
    pink:   { 1: '#7a1451', 2: '#ff5bd1', 3: '#39ff88', bg: '#120814' },
    mono:   { 1: '#2a2a36', 2: '#ededf2', 3: '#9a9aa8', bg: '#0a0a0f' },
  };
  const p = paletteMap[theme] || paletteMap.green;
  const cell = size / 16;

  return (
    <div style={{ width: size, height: size, position: 'relative', background: p.bg, imageRendering: 'pixelated', overflow: 'hidden' }}>
      <svg width={size} height={size} viewBox="0 0 16 16" shapeRendering="crispEdges">
        {grid.map((row, y) =>
          row.split('').map((ch, x) => {
            if (ch === '.') return null;
            const color = p[ch];
            const isBlink = animated && ch === '3' && y >= 12;
            return (
              <rect
                key={`${x}-${y}`}
                x={x}
                y={y}
                width={1}
                height={1}
                fill={color}
                style={isBlink ? { animation: 'blink 1s steps(2) infinite' } : undefined}
              />
            );
          })
        )}
      </svg>
      {/* Scanline overlay */}
      {animated && (
        <div style={{
          position: 'absolute', inset: 0, pointerEvents: 'none',
          background: 'repeating-linear-gradient(0deg, rgba(255,255,255,0.04) 0, rgba(255,255,255,0.04) 1px, transparent 1px, transparent 3px)',
        }} />
      )}
    </div>
  );
}

// ---------- Direction C: Terminal / ASCII ----------
function LogoTerminal({ size = 128, animated = true, theme = 'paper' }) {
  const palettes = {
    paper: { bg: '#f4efe6', ink: '#18140e', accent: '#d97742', soft: '#8a7f6d' },
    ink:   { bg: '#0e0d0a', ink: '#f4efe6', accent: '#d97742', soft: '#6a6158' },
    amber: { bg: '#120c00', ink: '#ffbf3c', accent: '#ff5bd1', soft: '#8a6e1c' },
  };
  const p = palettes[theme] || palettes.paper;
  const fs = size * 0.095;

  return (
    <div style={{
      width: size, height: size, background: p.bg, color: p.ink,
      fontFamily: "'JetBrains Mono', monospace",
      display: 'grid', placeItems: 'center', position: 'relative',
      border: `1px solid ${p.ink}22`,
    }}>
      <div style={{ textAlign: 'left', lineHeight: 1.05, fontSize: fs, letterSpacing: '-0.02em' }}>
        <div style={{ color: p.soft, fontSize: fs * 0.65, marginBottom: fs * 0.3 }}>~/open-island</div>
        <div>
          <span style={{ color: p.accent }}>{'>'}</span> <span style={{ fontWeight: 700 }}>O</span>
          <span style={{ opacity: 0.4 }}>pen</span>
        </div>
        <div style={{ marginLeft: fs * 0.9 }}>
          <span style={{ fontWeight: 700 }}>I</span>
          <span style={{ opacity: 0.4 }}>sland</span>
          <span style={{ background: p.ink, color: p.bg, display: 'inline-block', width: fs * 0.5, height: fs * 0.95, marginLeft: 2, verticalAlign: 'text-bottom', animation: animated ? 'blink 1s steps(2) infinite' : 'none' }} />
        </div>
      </div>
      {/* Corner tick */}
      <div style={{ position: 'absolute', top: 6, right: 8, fontFamily: "'JetBrains Mono', monospace", fontSize: size * 0.055, color: p.soft }}>◐</div>
    </div>
  );
}

// Export
Object.assign(window, { LogoLiquid, LogoPixel, LogoTerminal });
