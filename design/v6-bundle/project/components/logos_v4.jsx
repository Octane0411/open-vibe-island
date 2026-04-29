// Logos v4 — focus on Pill modifications + Horizon notch-ification.
// All static (icons should never animate). Pure black/white + warm paper.
// Goal: keep pill-level restraint, but add just enough to be distinctly "Open Island".

// ---------- Shared container ----------
function Squircle_v4({ size = 200, tone = 'paper', children, pad = 0 }) {
  const bg = tone === 'paper' ? '#f1ead9' : tone === 'ink' ? '#0d0d0f' : tone === 'bw' ? '#ffffff' : '#f1ead9';
  const ring = tone === 'ink' ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)';
  const r = size * 0.225;
  return (
    <div style={{
      width: size, height: size, background: bg, borderRadius: r,
      display: 'grid', placeItems: 'center', position: 'relative',
      boxShadow: `inset 0 0 0 1px ${ring}, 0 ${size*0.015}px ${size*0.06}px rgba(0,0,0,0.2)`,
      overflow: 'hidden',
    }}>
      {children}
    </div>
  );
}

const inkOf = (tone) => tone === 'ink' ? '#f1ead9' : '#0d0d0f';

// ============================================================
// PILL VARIANTS — all static, each adds ONE small modification
// ============================================================

// P1 · Pill with seam — a hairline split down the middle, suggests "opens"
function P1_Seam({ size = 140, tone = 'paper' }) {
  const ink = inkOf(tone);
  return (
    <svg width={size} height={size * 0.44} viewBox="0 0 140 62">
      <rect x="2" y="2" width="136" height="58" rx="29" fill={ink} />
      <rect x="69" y="16" width="2" height="30" rx="1" fill={tone === 'ink' ? '#0d0d0f' : '#f1ead9'} opacity="0.9" />
    </svg>
  );
}

// P2 · Pill with an inset dot — the "cursor" / "signal"
function P2_Dot({ size = 140, tone = 'paper' }) {
  const ink = inkOf(tone);
  const knockout = tone === 'ink' ? '#0d0d0f' : '#f1ead9';
  return (
    <svg width={size} height={size * 0.44} viewBox="0 0 140 62">
      <rect x="2" y="2" width="136" height="58" rx="29" fill={ink} />
      <circle cx="30" cy="31" r="7" fill={knockout} />
    </svg>
  );
}

// P3 · Pill with a tick — left cap carries a small tick mark (Linear-ish)
function P3_Tick({ size = 140, tone = 'paper' }) {
  const ink = inkOf(tone);
  const knockout = tone === 'ink' ? '#0d0d0f' : '#f1ead9';
  return (
    <svg width={size} height={size * 0.44} viewBox="0 0 140 62">
      <rect x="2" y="2" width="136" height="58" rx="29" fill={ink} />
      <path d="M22 31 L30 39 L44 23" stroke={knockout} strokeWidth="4.5" strokeLinecap="round" strokeLinejoin="round" fill="none" />
    </svg>
  );
}

// P4 · Pill with chevron — subtle "open/forward" glyph inside
function P4_Chevron({ size = 140, tone = 'paper' }) {
  const ink = inkOf(tone);
  const knockout = tone === 'ink' ? '#0d0d0f' : '#f1ead9';
  return (
    <svg width={size} height={size * 0.44} viewBox="0 0 140 62">
      <rect x="2" y="2" width="136" height="58" rx="29" fill={ink} />
      <path d="M26 22 L38 31 L26 40" stroke={knockout} strokeWidth="4.5" strokeLinecap="round" strokeLinejoin="round" fill="none" />
    </svg>
  );
}

// P5 · Open pill — ring (outline) rather than solid. Reads as "island" atoll.
function P5_Ring({ size = 140, tone = 'paper' }) {
  const ink = inkOf(tone);
  return (
    <svg width={size} height={size * 0.44} viewBox="0 0 140 62">
      <rect x="4" y="4" width="132" height="54" rx="27" fill="none" stroke={ink} strokeWidth="6" />
    </svg>
  );
}

// P6 · Split pill — half solid, half outline. Minimal but distinctive.
function P6_Split({ size = 140, tone = 'paper' }) {
  const ink = inkOf(tone);
  return (
    <svg width={size} height={size * 0.44} viewBox="0 0 140 62">
      <defs>
        <clipPath id="p6-left"><rect x="0" y="0" width="70" height="62" /></clipPath>
        <clipPath id="p6-right"><rect x="70" y="0" width="70" height="62" /></clipPath>
      </defs>
      <g clipPath="url(#p6-left)">
        <rect x="2" y="2" width="136" height="58" rx="29" fill={ink} />
      </g>
      <g clipPath="url(#p6-right)">
        <rect x="4" y="4" width="132" height="54" rx="27" fill="none" stroke={ink} strokeWidth="6" />
      </g>
    </svg>
  );
}

// P7 · Pill with indent — a tiny rectangular bite on the bottom edge (static notch reference)
function P7_Bite({ size = 140, tone = 'paper' }) {
  const ink = inkOf(tone);
  return (
    <svg width={size} height={size * 0.44} viewBox="0 0 140 62">
      <path d={`
        M 31 2
        H 109
        A 29 29 0 0 1 109 60
        H 82
        Q 82 52 74 52
        L 66 52
        Q 58 52 58 60
        H 31
        A 29 29 0 0 1 31 2
        Z
      `} fill={ink} />
    </svg>
  );
}

// P8 · Pill + underscore — terminal reference, but subtle; just a short bar under the pill
function P8_Under({ size = 140, tone = 'paper' }) {
  const ink = inkOf(tone);
  return (
    <svg width={size} height={size * 0.58} viewBox="0 0 140 82">
      <rect x="2" y="2" width="136" height="58" rx="29" fill={ink} />
      <rect x="58" y="72" width="24" height="6" rx="3" fill={ink} />
    </svg>
  );
}

// ============================================================
// HORIZON VARIANTS — stacked pills, but make notch more obvious
// ============================================================

// H1 · Horizon with a notch carved out of the top pill's underside
function H1_NotchOut({ size = 140, tone = 'paper' }) {
  const ink = inkOf(tone);
  return (
    <svg width={size} height={size * 0.7} viewBox="0 0 140 98">
      {/* Top pill with a small notch at the bottom-center */}
      <path d={`
        M 22 8
        H 118
        A 22 22 0 0 1 118 52
        H 84
        Q 84 44 76 44
        L 64 44
        Q 56 44 56 52
        H 22
        A 22 22 0 0 1 22 8
        Z
      `} fill={ink} />
      {/* Lower bar (ground) */}
      <rect x="42" y="68" width="56" height="14" rx="7" fill={ink} opacity="0.35" />
    </svg>
  );
}

// H2 · Horizon with a cursor bar descending from the top pill (like a dropdown notch)
function H2_DropPill({ size = 140, tone = 'paper' }) {
  const ink = inkOf(tone);
  return (
    <svg width={size} height={size * 0.72} viewBox="0 0 140 100">
      {/* Top pill */}
      <rect x="18" y="10" width="104" height="30" rx="15" fill={ink} />
      {/* Vertical stem connecting down */}
      <rect x="66" y="40" width="8" height="22" rx="4" fill={ink} />
      {/* Bottom small pill — the "island" */}
      <rect x="46" y="62" width="48" height="22" rx="11" fill={ink} />
    </svg>
  );
}

// H3 · Pill-within-pill — small pill centered inside a larger pill outline
function H3_PillInPill({ size = 140, tone = 'paper' }) {
  const ink = inkOf(tone);
  return (
    <svg width={size} height={size * 0.45} viewBox="0 0 140 64">
      <rect x="3" y="3" width="134" height="58" rx="29" fill="none" stroke={ink} strokeWidth="5" />
      <rect x="52" y="22" width="36" height="20" rx="10" fill={ink} />
    </svg>
  );
}

// ============================================================
// App icon wrappers
// ============================================================
function wrapIcon(Mark, aspect) {
  return function AppIcon({ size = 200, tone = 'paper' }) {
    // For wide pills, constrain by width; for taller horizons, constrain by height
    const markSize = size * (aspect === 'tall' ? 0.7 : 0.72);
    return <Squircle_v4 size={size} tone={tone}><Mark size={markSize} tone={tone} /></Squircle_v4>;
  };
}

const AppIcon_P1 = wrapIcon(P1_Seam);
const AppIcon_P2 = wrapIcon(P2_Dot);
const AppIcon_P3 = wrapIcon(P3_Tick);
const AppIcon_P4 = wrapIcon(P4_Chevron);
const AppIcon_P5 = wrapIcon(P5_Ring);
const AppIcon_P6 = wrapIcon(P6_Split);
const AppIcon_P7 = wrapIcon(P7_Bite);
const AppIcon_P8 = wrapIcon(P8_Under, 'tall');
const AppIcon_H1 = wrapIcon(H1_NotchOut, 'tall');
const AppIcon_H2 = wrapIcon(H2_DropPill, 'tall');
const AppIcon_H3 = wrapIcon(H3_PillInPill);

Object.assign(window, {
  Squircle_v4,
  P1_Seam, P2_Dot, P3_Tick, P4_Chevron, P5_Ring, P6_Split, P7_Bite, P8_Under,
  H1_NotchOut, H2_DropPill, H3_PillInPill,
  AppIcon_P1, AppIcon_P2, AppIcon_P3, AppIcon_P4, AppIcon_P5, AppIcon_P6, AppIcon_P7, AppIcon_P8,
  AppIcon_H1, AppIcon_H2, AppIcon_H3,
});
