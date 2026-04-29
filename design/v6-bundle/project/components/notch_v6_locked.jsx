// v6 — Notch as a dynamic info bar; Logo as a signature extracted from the notch's visual grammar.
// Left slot = live state (spinner / dot / bars / tick / error)
// Middle   = session name, agent name, or short message
// Right    = session count, or active agent avatar, or time-left

const inkOfv6 = '#f1ead9';

// ========= Left-slot: animated state glyphs =========
// Each glyph lives in a 24x24 box, centered.

function StateIdle() {
  // Locked — Unified bars rest state.
  return <UnifiedBars mode="idle" />;
}

// ========= UnifiedBars =========
// Idle / Running / Waiting all share the same 3 vertical bars — only the
// per-bar height + animation differs. This means React keeps the <rect> nodes
// identical across renders, so switching `state` triggers a smooth CSS
// transition on height/y/opacity instead of a hard swap.
function UnifiedBars({ mode = 'idle' }) {
  // Three bar columns, centered around x=12 in the 24x24 box
  const cols = [
    { x: 5.25, idleH: 3,  runCycle: [4, 12, 4], runDelay: 0,    waitH: 10 },
    { x: 10.75, idleH: 5, runCycle: [6, 14, 6], runDelay: 0.15, waitH: 0  },  // middle bar hidden in waiting
    { x: 16.25, idleH: 3, runCycle: [4, 10, 4], runDelay: 0.3,  waitH: 10 },
  ];
  const BAR_W = 2.5;
  const CENTER = 12;

  return (
    <g fill={inkOfv6}>
      {cols.map((c, i) => {
        const isWaiting = mode === 'waiting';
        const isRunning = mode === 'running';
        const isIdle = mode === 'idle';

        // In "running" we let SMIL drive height/y for a strong wave
        // In idle/waiting we set a static height/y and use CSS transition for the swap
        if (isRunning) {
          const [lo, hi, lo2] = c.runCycle;
          return (
            <rect key={i} x={c.x} width={BAR_W} rx={BAR_W/2}
              y={CENTER - lo/2} height={lo}
              style={{ transition: 'opacity 0.25s ease' }}
              opacity="1">
              <animate attributeName="height" values={`${lo};${hi};${lo2}`} dur="0.9s" begin={`${c.runDelay}s`} repeatCount="indefinite" />
              <animate attributeName="y" values={`${CENTER - lo/2};${CENTER - hi/2};${CENTER - lo2/2}`} dur="0.9s" begin={`${c.runDelay}s`} repeatCount="indefinite" />
            </rect>
          );
        }

        // idle or waiting — static rect with CSS transitions
        const h = isWaiting ? c.waitH : c.idleH;
        const y = CENTER - h/2;
        const opacity = isWaiting && c.waitH === 0 ? 0 : 1;
        // Waiting pulse on outer bars; idle gentle breathing on middle
        const pulse = isWaiting && c.waitH > 0
          ? { animation: `pause-pulse 1.8s ease-in-out ${i === 2 ? 0.9 : 0}s infinite` }
          : isIdle && i === 1
          ? { animation: 'idle-breathe 2.8s ease-in-out infinite' }
          : {};
        return (
          <rect key={i} x={c.x} width={BAR_W} rx={BAR_W/2}
            y={y} height={h} opacity={opacity}
            style={{
              transition: 'height 0.45s cubic-bezier(.4,0,.2,1), y 0.45s cubic-bezier(.4,0,.2,1), opacity 0.3s ease',
              ...pulse,
            }} />
        );
      })}
      <style>{`
        @keyframes pause-pulse {
          0%, 100% { fill-opacity: 0.55; }
          50%      { fill-opacity: 1; }
        }
        @keyframes idle-breathe {
          0%, 100% { fill-opacity: 0.7; }
          50%      { fill-opacity: 1; }
        }
      `}</style>
    </g>
  );
}

function StateRunning() { return <UnifiedBars mode="running" />; }

// Kept as an optional "spinner" variant for specific cases (e.g. long-running builds)
function StateSpinner() {
  return (
    <g>
      <circle cx="12" cy="12" r="7" fill="none" stroke={inkOfv6} strokeOpacity="0.25" strokeWidth="2" />
      <circle cx="12" cy="12" r="7" fill="none" stroke={inkOfv6} strokeWidth="2" strokeDasharray="10 34" strokeLinecap="round" style={{ transformOrigin: '12px 12px', animation: 'spinner-rot 1.1s linear infinite' }} />
      <style>{`@keyframes spinner-rot { to { transform: rotate(360deg); } }`}</style>
    </g>
  );
}

function StateThinking() {
  // Alias — now identical to Running (wave bars). Kept for API compatibility.
  return <StateRunning />;
}

function StateWaiting() {
  // Locked — Unified bars waiting (pause variant).
  return <UnifiedBars mode="waiting" />;
}

function StateDone() {
  // Tick that draws itself in once
  return (
    <path d="M 6 12 L 10.5 16.5 L 18 9" fill="none" stroke={inkOfv6} strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"
      strokeDasharray="20 20" strokeDashoffset="20">
      <animate attributeName="stroke-dashoffset" from="20" to="0" dur="0.4s" fill="freeze" />
    </path>
  );
}

function StateError() {
  // Legacy — Error state removed from the system. Kept as a no-op for safety.
  return null;
}

const STATE_MAP = {
  idle: StateIdle,
  running: StateRunning,
  thinking: StateRunning, // unified — same wave bars
  spinner: StateSpinner,  // optional alt for long builds
  waiting: StateWaiting,
  done: StateDone,
};

// ========= Right-slot: session/agent indicators =========
function SessionCount({ n }) {
  // A small badge pill with the count
  return (
    <g>
      <rect x="0" y="4" width="22" height="16" rx="8" fill={inkOfv6} fillOpacity="0.12" stroke={inkOfv6} strokeOpacity="0.3" strokeWidth="1" />
      <text x="11" y="12" dy="0.36em" textAnchor="middle" fill={inkOfv6}
        fontFamily="'JetBrains Mono', monospace" fontSize="10" fontWeight="600">×{n}</text>
    </g>
  );
}

function AgentDots({ agents }) {
  // Stack of colored pills (one per active agent)
  return (
    <g>
      {agents.map((a, i) => (
        <circle key={i} cx={4 + i * 7} cy="12" r="3" fill={a.color} />
      ))}
    </g>
  );
}

function TimeLeft({ txt }) {
  return (
    <text x="0" y="12" dy="0.36em" fill={inkOfv6} fillOpacity="0.7"
      fontFamily="'JetBrains Mono', monospace" fontSize="10.5">{txt}</text>
  );
}

// ========= The Notch component =========
// Two layout modes:
//   1. External (default): symmetric center-growth pill. Content centered. When width grows,
//      content stays centered, pill edges extend equally.
//   2. MacBook (pass `notchWidth > 0`): SINGLE pill, but content is routed AROUND a central
//      reserved gap of `notchWidth`. Left-half content (glyph + short label) is RIGHT-ANCHORED
//      to the left edge of the gap; right-half content (right-slot) is LEFT-ANCHORED to the
//      right edge of the gap. Left/right halves NEVER move — they stay pinned to the notch edges.
//      Pill is still one continuous black shape (covers the physical hardware notch), with
//      overall width = leftAnchor + notchWidth + rightAnchor + padding.
function NotchV6({
  state = 'idle',
  label = null,
  right = null,
  width,
  height = 32,
  minWidth = 70,
  notchWidth = 0, // >0 = MacBook mode; width of central physical-notch gap to route around
  idleVariant, waitingVariant, variant, physicalNotchWidth, // API-compat, ignored
}) {
  const r = height / 2;
  const LeftGlyph = STATE_MAP[state] || StateIdle;

  // --- right-slot intrinsic ---
  let rightNode = null;
  let rightW = 0;
  if (right?.type === 'count')       { rightNode = <SessionCount n={right.n} />;        rightW = 22; }
  else if (right?.type === 'agents') { rightNode = <AgentDots agents={right.agents} />; rightW = right.agents.length * 7 + 4; }
  else if (right?.type === 'time')   { rightNode = <TimeLeft txt={right.txt} />;        rightW = right.txt.length * 6.5; }

  const glyphW = 24;
  const labelW = label ? label.length * 6.8 + 10 : 0;
  const rightFullW = rightNode ? rightW + 14 : 0;
  const padL = r, padR = r;

  // ============== MACBOOK MODE — fixed outer width, content pinned to outer edges ==============
  // Overall pill width is FIXED regardless of state. Left content hugs the LEFT
  // edge of the pill; right content hugs the RIGHT edge. The middle gap = physical
  // notch width and sits exactly under the hardware cutout. Switching states does
  // NOT move the left or right halves — they stay pinned.
  // In this mode the middle label is SUPPRESSED (the physical notch would cover it
  // anyway) — only the left glyph + right-slot are shown.
  if (notchWidth > 0) {
    // Fixed half-reserve on each side — just wide enough for glyph / right-slot,
    // independent of current content so the left/right halves don't move.
    const halfReserve = 44;
    const pillOuter = halfReserve + notchWidth + halfReserve;

    // Left content: LEFT-anchored to pill's left edge (padL from edge)
    const glyphX = padL;
    // Right content: RIGHT-anchored to pill's right edge (padR from edge)
    const rightX = pillOuter - padR - rightW;

    return (
      <div style={{ width: pillOuter, height, position: 'relative' }}>
        {/* Single continuous pill background — covers entire width including where the physical notch sits underneath */}
        <svg width={pillOuter} height={height} viewBox={`0 0 ${pillOuter} ${height}`}
          style={{ display: 'block', position: 'absolute', inset: 0 }}
          preserveAspectRatio="none">
          <path d={`M 0 0 H ${pillOuter} V ${height-r} A ${r} ${r} 0 0 1 ${pillOuter-r} ${height} H ${r} A ${r} ${r} 0 0 1 0 ${height-r} Z`} fill="#0d0d0f" />
        </svg>
        {/* Content SVG overlay */}
        <svg width={pillOuter} height={height} viewBox={`0 0 ${pillOuter} ${height}`}
          style={{ display: 'block', position: 'absolute', inset: 0, pointerEvents: 'none' }}>
          {/* Left half: glyph only — LEFT-anchored to pill's left edge (label suppressed; physical notch covers the middle) */}
          <g transform={`translate(${glyphX} ${(height - 24)/2})`}>
            {(state === 'idle' || state === 'running' || state === 'waiting')
              ? <UnifiedBars mode={state} />
              : <LeftGlyph />}
          </g>
          {/* Right half: right-slot — RIGHT-anchored to pill's right edge */}
          {rightNode && (
            <g transform={`translate(${rightX} ${(height - 24)/2})`}>
              {rightNode}
            </g>
          )}
        </svg>
      </div>
    );
  }

  // ============== EXTERNAL MODE — FIXED-WIDTH pill, no drift ==============
  // The pill width NEVER changes between states. Content morphs inside via
  // opacity / translate — pill edges are rock-solid.
  //
  // Layout: glyph is LEFT-anchored at `padL`. The rest of the pill is a
  // reserved content region (label + right-slot). When there's no label/right,
  // the pill's trailing region is empty ink (still looks like a stable pill,
  // not a "wasted" space — Dynamic Island at rest has breathing room too).
  //
  // `width` prop still honored for per-state gallery cards; `minWidth` acts
  // as the locked pill width when `width` isn't given. This keeps the state
  // gallery working (each card renders a fixed-size pill) while the transition
  // demo hands a single constant `width` so the pill never drifts.

  const intrinsicW = padL + glyphW + labelW + rightFullW + padR;
  // If caller passes an explicit width, use it (locked).
  // Else use minWidth as the locked pill width (not just a floor).
  const pillW = width != null ? width : Math.max(minWidth, intrinsicW);

  // Fixed anchor positions inside the pill — these do NOT depend on state:
  const glyphX = padL;
  // Label sits immediately right of glyph, at a fixed x.
  const labelX = glyphX + glyphW + 6;
  // Right-slot hugs the pill's right edge.
  const rightX = pillW - padR - rightW;

  return (
    <div style={{
      width: pillW, height, position: 'relative',
      transition: 'width 0.45s cubic-bezier(.4,0,.2,1)',
    }}>
      {/* Background pill — width animates smoothly with content */}
      <svg width={pillW} height={height} viewBox={`0 0 ${pillW} ${height}`}
        style={{
          display: 'block', position: 'absolute', inset: 0,
          transition: 'width 0.45s cubic-bezier(.4,0,.2,1)',
        }}
        preserveAspectRatio="none">
        <path d={`M 0 0 H ${pillW} V ${height-r} A ${r} ${r} 0 0 1 ${pillW-r} ${height} H ${r} A ${r} ${r} 0 0 1 0 ${height-r} Z`} fill="#0d0d0f" />
      </svg>

      {/* Glyph — fixed left anchor */}
      <div style={{
        position: 'absolute', top: (height - 24)/2, left: glyphX,
        width: glyphW, height: 24, pointerEvents: 'none',
      }}>
        <svg width={glyphW} height={24} viewBox={`0 0 ${glyphW} 24`} style={{ overflow: 'visible' }}>
          {(state === 'idle' || state === 'running' || state === 'waiting')
            ? <UnifiedBars mode={state} />
            : <LeftGlyph />}
        </svg>
      </div>

      {/* Label — fixed left anchor (next to glyph). Fades in/out in place. */}
      <div style={{
        position: 'absolute', top: 0, left: labelX, height,
        display: 'flex', alignItems: 'center',
        color: inkOfv6, fontFamily: "'JetBrains Mono', monospace",
        fontSize: 11.5, fontWeight: 500, whiteSpace: 'nowrap',
        opacity: label ? 1 : 0,
        transform: label ? 'translateX(0)' : 'translateX(-4px)',
        transition: 'opacity 0.35s ease, transform 0.35s cubic-bezier(.4,0,.2,1)',
        pointerEvents: 'none',
      }}>
        {label || ''}
      </div>

      {/* Right-slot — hugs the (animated) right edge of the pill */}
      <div style={{
        position: 'absolute', top: (height - 24)/2, left: rightX,
        width: rightW, height: 24,
        opacity: rightNode ? 1 : 0,
        transform: rightNode ? 'translateX(0)' : 'translateX(4px)',
        transition: 'opacity 0.35s ease, left 0.45s cubic-bezier(.4,0,.2,1), transform 0.35s cubic-bezier(.4,0,.2,1)',
        pointerEvents: 'none',
      }}>
        {rightNode && (
          <svg width={rightW} height={24} viewBox={`0 0 ${rightW} 24`} style={{ overflow: 'visible' }}>
            {rightNode}
          </svg>
        )}
      </div>
    </div>
  );
}

// ========= Menu bar mock =========
// variant: 'external' (no hardware notch) | 'notched' (MacBook w/ physical notch)
function MenuBarV6({ children, wallpaper = 'plum', width = 520, appName = 'Xcode', variant = 'external', physicalNotchWidth = 170 }) {
  const bg = {
    plum:   'linear-gradient(135deg, #3c2344, #5f2e58 60%, #a8517a)',
    slate:  'linear-gradient(135deg, #1e2530, #3a4a5c)',
    forest: 'linear-gradient(135deg, #1b2e22, #3a5a3f)',
    sand:   'linear-gradient(135deg, #c8a576, #e8d4a0 60%, #f1ead9)',
  }[wallpaper];
  const notchH = 32;
  const notchR = notchH / 2;
  return (
    <div style={{ width, borderRadius: 12, overflow: 'hidden', background: bg, border: '1px solid rgba(255,255,255,0.06)' }}>
      <div style={{ position: 'relative', height: 32, background: 'rgba(0,0,0,0.28)', backdropFilter: 'blur(8px)', display: 'flex', alignItems: 'center', padding: '0 12px', color: '#f1ead9' }}>
        <span style={{ fontSize: 12, fontWeight: 700 }}></span>
        <span style={{ fontSize: 12, fontWeight: 600, marginLeft: 12 }}>{appName}</span>
        <span style={{ fontSize: 12, marginLeft: 10, opacity: 0.85 }}>File Edit View</span>
        <span style={{ flex: 1 }} />
        <span style={{ fontSize: 11, opacity: 0.75, fontFamily: 'JetBrains Mono, monospace' }}>14:22</span>

        {/* Physical hardware notch — drawn UNDER the app notch content so ears sit beside it */}
        {variant === 'notched' && (
          <svg width={physicalNotchWidth} height={notchH}
            viewBox={`0 0 ${physicalNotchWidth} ${notchH}`}
            style={{ position: 'absolute', top: 0, left: '50%', transform: 'translateX(-50%)', pointerEvents: 'none' }}>
            <path d={`M 0 0 H ${physicalNotchWidth} V ${notchH - notchR} A ${notchR} ${notchR} 0 0 1 ${physicalNotchWidth - notchR} ${notchH} H ${notchR} A ${notchR} ${notchR} 0 0 1 0 ${notchH - notchR} Z`}
              fill="#000" />
          </svg>
        )}

        <div style={{ position: 'absolute', top: 0, left: '50%', transform: 'translateX(-50%)' }}>{children}</div>
      </div>
      <div style={{ height: 140 }} />
    </div>
  );
}

// ========= Logo candidates — extracted from notch grammar =========
// The notch's DNA is: flat-top, rounded-bottom, ink fill. The logo should feel like
// "a piece of notch" — not a pill with a symbol on it.

// L1 · The Notch itself, cropped — the literal shape used as a wordmark prefix
function Logo_NotchMark({ size = 120, tone = 'paper' }) {
  const ink = tone === 'ink' ? '#f1ead9' : '#0d0d0f';
  // width:height = 2:1, flat-top, rounded-bottom
  const w = 120, h = 60;
  return (
    <svg width={size} height={size * h/w} viewBox={`0 0 ${w} ${h}`}>
      <path d={`M 0 0 H ${w} V ${h-30} A 30 30 0 0 1 ${w-30} ${h} H 30 A 30 30 0 0 1 0 ${h-30} Z`} fill={ink} />
    </svg>
  );
}

// L2 · Notch + wordmark lockup — real logo: shape + "Open Island"
function Logo_Lockup({ size = 360, tone = 'paper' }) {
  const ink = tone === 'ink' ? '#f1ead9' : '#0d0d0f';
  const w = 360, h = 90;
  return (
    <svg width={size} height={size * h/w} viewBox={`0 0 ${w} ${h}`}>
      <path d={`M 0 0 H 60 V 30 A 30 30 0 0 1 30 60 A 30 30 0 0 1 0 30 Z`} fill={ink} />
      <text x="78" y="40" fill={ink} fontFamily="'Inter', sans-serif" fontSize="28" fontWeight="700" letterSpacing="-0.02em">Open</text>
      <text x="78" y="74" fill={ink} fontFamily="'Inter', sans-serif" fontSize="28" fontWeight="400" letterSpacing="-0.02em" fillOpacity="0.6">Island</text>
    </svg>
  );
}

// L3 · Two-notch monogram — the top-half silhouette of TWO notches side by side suggests "O" "I"
function Logo_DoubleNotch({ size = 120, tone = 'paper' }) {
  const ink = tone === 'ink' ? '#f1ead9' : '#0d0d0f';
  const w = 120, h = 60;
  return (
    <svg width={size} height={size * h/w} viewBox={`0 0 ${w} ${h}`}>
      {/* Left notch (wider) */}
      <path d={`M 4 0 H 56 V 26 A 26 26 0 0 1 30 52 A 26 26 0 0 1 4 26 Z`} fill={ink} />
      {/* Right notch (narrower — reads as "I") */}
      <path d={`M 76 0 H 108 V 36 A 16 16 0 0 1 92 52 A 16 16 0 0 1 76 36 Z`} fill={ink} />
    </svg>
  );
}

// L4 · Notch with highlight slit — same pure shape, but with a single ink-of-knockout slit
// This reflects the "seam" of the notch opening / the speaker slit
function Logo_NotchSlit({ size = 120, tone = 'paper' }) {
  const ink = tone === 'ink' ? '#f1ead9' : '#0d0d0f';
  const knock = tone === 'ink' ? '#0d0d0f' : '#f1ead9';
  const w = 120, h = 60;
  return (
    <svg width={size} height={size * h/w} viewBox={`0 0 ${w} ${h}`}>
      <path d={`M 0 0 H ${w} V ${h-30} A 30 30 0 0 1 ${w-30} ${h} H 30 A 30 30 0 0 1 0 ${h-30} Z`} fill={ink} />
      <rect x={w/2 - 12} y="10" width="24" height="3" rx="1.5" fill={knock} opacity="0.85" />
    </svg>
  );
}

// L5 · Tall notch — proportion tuned so it reads as a standalone mark (less "bar", more "drop")
function Logo_TallNotch({ size = 90, tone = 'paper' }) {
  const ink = tone === 'ink' ? '#f1ead9' : '#0d0d0f';
  const w = 80, h = 100;
  return (
    <svg width={size} height={size * h/w} viewBox={`0 0 ${w} ${h}`}>
      <path d={`M 0 0 H ${w} V ${h-40} A 40 40 0 0 1 ${w-40} ${h} H 40 A 40 40 0 0 1 0 ${h-40} Z`} fill={ink} />
    </svg>
  );
}

// ========= App Icons =========
function SquircleV6({ size, tone, children }) {
  const bg = tone === 'paper' ? '#f1ead9' : tone === 'ink' ? '#0d0d0f' : '#fff';
  const ring = tone === 'ink' ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)';
  return (
    <div style={{ width: size, height: size, background: bg, borderRadius: size * 0.225,
      display: 'grid', placeItems: 'center', position: 'relative',
      boxShadow: `inset 0 0 0 1px ${ring}, 0 ${size*0.015}px ${size*0.06}px rgba(0,0,0,0.2)`,
      overflow: 'hidden' }}>
      {children}
    </div>
  );
}

function AppIcon_Notch({ size = 200, tone = 'paper', variant = 'center' }) {
  const ink = tone === 'ink' ? '#f1ead9' : '#0d0d0f';
  const S = size;
  // 'top' = notch attached to top edge (literal Dynamic Island inside an app icon)
  // 'center' = notch shape floated in the middle
  // 'tall' = tall variant centered
  if (variant === 'top') {
    return (
      <SquircleV6 size={size} tone={tone}>
        <svg width={S} height={S} viewBox={`0 0 ${S} ${S}`} style={{ display: 'block' }}>
          <path d={`M ${S*0.22} 0 H ${S*0.78} V ${S*0.3} A ${S*0.15} ${S*0.15} 0 0 1 ${S*0.63} ${S*0.45} H ${S*0.37} A ${S*0.15} ${S*0.15} 0 0 1 ${S*0.22} ${S*0.3} Z`} fill={ink} />
        </svg>
      </SquircleV6>
    );
  }
  if (variant === 'tall') {
    return (
      <SquircleV6 size={size} tone={tone}>
        <Logo_TallNotch size={size * 0.5} tone={tone} />
      </SquircleV6>
    );
  }
  return (
    <SquircleV6 size={size} tone={tone}>
      <Logo_NotchMark size={size * 0.62} tone={tone} />
    </SquircleV6>
  );
}

function AppIcon_DoubleNotch({ size = 200, tone = 'paper' }) {
  return (
    <SquircleV6 size={size} tone={tone}>
      <Logo_DoubleNotch size={size * 0.68} tone={tone} />
    </SquircleV6>
  );
}

function AppIcon_NotchSlit({ size = 200, tone = 'paper' }) {
  return (
    <SquircleV6 size={size} tone={tone}>
      <Logo_NotchSlit size={size * 0.62} tone={tone} />
    </SquircleV6>
  );
}

Object.assign(window, {
  NotchV6, MenuBarV6,
  Logo_NotchMark, Logo_Lockup, Logo_DoubleNotch, Logo_NotchSlit, Logo_TallNotch,
  AppIcon_Notch, AppIcon_DoubleNotch, AppIcon_NotchSlit,
  StateIdle, StateRunning, StateSpinner, StateWaiting, StateDone, StateError,
});
