// v7 logos — derived from the I (pulse-line) and M (breathing-bar) rest states.
// Core DNA: horizontal line inside a notch-shaped container.
// I = line + traveling dot. M = single bar that breathes horizontally.
// Logos translate these into STATIC marks (icons don't animate).

const inkV7 = (t) => t === 'ink' ? '#f1ead9' : '#0d0d0f';
const invV7 = (t) => t === 'ink' ? '#0d0d0f' : '#f1ead9';

// Notch shape helper
function notchPath(w, h, r) {
  return `M 0 0 H ${w} V ${h-r} A ${r} ${r} 0 0 1 ${w-r} ${h} H ${r} A ${r} ${r} 0 0 1 0 ${h-r} Z`;
}

// ------- Pulse-line derived logos (from "I") -------
// Concept: line + dot. The dot = cursor / "here I am" beacon.

// L7-1 · Beacon — notch with a line running through it + one anchor dot
function Logo_Beacon({ size = 160, tone = 'paper' }) {
  const ink = inkV7(tone), inv = invV7(tone);
  const w = 160, h = 64, r = 32;
  return (
    <svg width={size} height={size * h/w} viewBox={`0 0 ${w} ${h}`}>
      <path d={notchPath(w, h, r)} fill={ink} />
      <rect x="24" y={h/2 - 2} width={w - 48} height="4" rx="2" fill={inv} opacity="0.35" />
      <circle cx={w * 0.35} cy={h/2} r="5" fill={inv} />
    </svg>
  );
}

// L7-2 · Horizon Line — the line is the land, dot is the sun/light
function Logo_Horizon({ size = 160, tone = 'paper' }) {
  const ink = inkV7(tone), inv = invV7(tone);
  const w = 160, h = 64, r = 32;
  return (
    <svg width={size} height={size * h/w} viewBox={`0 0 ${w} ${h}`}>
      <path d={notchPath(w, h, r)} fill={ink} />
      <rect x="20" y={h/2 + 6} width={w - 40} height="3" rx="1.5" fill={inv} />
      <circle cx={w/2} cy={h/2 - 6} r="6" fill={inv} />
    </svg>
  );
}

// L7-3 · Traveler — frozen mid-travel: a dot captured at the right end of the line
function Logo_Traveler({ size = 160, tone = 'paper' }) {
  const ink = inkV7(tone), inv = invV7(tone);
  const w = 160, h = 64, r = 32;
  return (
    <svg width={size} height={size * h/w} viewBox={`0 0 ${w} ${h}`}>
      <path d={notchPath(w, h, r)} fill={ink} />
      <rect x="24" y={h/2 - 1.5} width={w - 80} height="3" rx="1.5" fill={inv} opacity="0.5" />
      <circle cx={w - 32} cy={h/2} r="5" fill={inv} />
    </svg>
  );
}

// ------- Breathing-bar derived logos (from "M") -------
// Concept: one bold bar inside the notch. Implies focus, presence, "one active thing".

// L7-4 · Core Bar — thick single bar, centered
function Logo_CoreBar({ size = 160, tone = 'paper' }) {
  const ink = inkV7(tone), inv = invV7(tone);
  const w = 160, h = 64, r = 32;
  return (
    <svg width={size} height={size * h/w} viewBox={`0 0 ${w} ${h}`}>
      <path d={notchPath(w, h, r)} fill={ink} />
      <rect x="36" y={h/2 - 4} width={w - 72} height="8" rx="4" fill={inv} />
    </svg>
  );
}

// L7-5 · Bar Stack — mid bar + two shorter satellite bars above & below
function Logo_BarStack({ size = 160, tone = 'paper' }) {
  const ink = inkV7(tone), inv = invV7(tone);
  const w = 160, h = 64, r = 32;
  return (
    <svg width={size} height={size * h/w} viewBox={`0 0 ${w} ${h}`}>
      <path d={notchPath(w, h, r)} fill={ink} />
      <rect x={w/2 - 18} y={h/2 - 14} width="36" height="3" rx="1.5" fill={inv} opacity="0.5" />
      <rect x={w/2 - 32} y={h/2 - 3} width="64" height="6" rx="3" fill={inv} />
      <rect x={w/2 - 18} y={h/2 + 11} width="36" height="3" rx="1.5" fill={inv} opacity="0.5" />
    </svg>
  );
}

// L7-6 · Bar + Trailing Dot — combines M's focus with I's anchor
function Logo_BarDot({ size = 160, tone = 'paper' }) {
  const ink = inkV7(tone), inv = invV7(tone);
  const w = 160, h = 64, r = 32;
  return (
    <svg width={size} height={size * h/w} viewBox={`0 0 ${w} ${h}`}>
      <path d={notchPath(w, h, r)} fill={ink} />
      <rect x="30" y={h/2 - 3.5} width="70" height="7" rx="3.5" fill={inv} />
      <circle cx="118" cy={h/2} r="5" fill={inv} />
    </svg>
  );
}

// ------- Square / tall variants for app icons (so it's not just a bar) -------

// L7-7 · Tall Beacon — same Beacon DNA but in tall notch proportion
function Logo_TallBeacon({ size = 120, tone = 'paper' }) {
  const ink = inkV7(tone), inv = invV7(tone);
  const w = 100, h = 120, r = 50;
  return (
    <svg width={size * w/h} height={size} viewBox={`0 0 ${w} ${h}`}>
      <path d={notchPath(w, h, r)} fill={ink} />
      <rect x="20" y={h/2 - 1.5} width={w - 40} height="3" rx="1.5" fill={inv} opacity="0.4" />
      <circle cx={w * 0.38} cy={h/2} r="6" fill={inv} />
    </svg>
  );
}

// L7-8 · Tall Core Bar — bold bar inside tall notch
function Logo_TallCoreBar({ size = 120, tone = 'paper' }) {
  const ink = inkV7(tone), inv = invV7(tone);
  const w = 100, h = 120, r = 50;
  return (
    <svg width={size * w/h} height={size} viewBox={`0 0 ${w} ${h}`}>
      <path d={notchPath(w, h, r)} fill={ink} />
      <rect x="24" y={h/2 - 5} width={w - 48} height="10" rx="5" fill={inv} />
    </svg>
  );
}

// ------- App icon wrappers -------
function SquircleV7({ size, tone, children, anchor = 'center' }) {
  const bg = tone === 'paper' ? '#f1ead9' : tone === 'ink' ? '#0d0d0f' : '#fff';
  const ring = tone === 'ink' ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)';
  const style = {
    width: size, height: size, background: bg, borderRadius: size * 0.225,
    display: 'grid', placeItems: anchor === 'top' ? 'start center' : 'center',
    paddingTop: anchor === 'top' ? 0 : 0,
    boxShadow: `inset 0 0 0 1px ${ring}, 0 ${size*0.015}px ${size*0.06}px rgba(0,0,0,0.2)`,
    overflow: 'hidden',
  };
  return <div style={style}>{children}</div>;
}

const makeApp = (Mark, scale = 0.62, anchor = 'center') =>
  function App({ size = 160, tone = 'paper' }) {
    return <SquircleV7 size={size} tone={tone} anchor={anchor}><Mark size={size * scale} tone={tone} /></SquircleV7>;
  };

// Top-anchored variant — notch literally attached to top of app icon
function AppIcon_TopAnchored({ size = 160, tone = 'paper', variant = 'beacon' }) {
  const ink = inkV7(tone), inv = invV7(tone);
  const bg = tone === 'paper' ? '#f1ead9' : tone === 'ink' ? '#0d0d0f' : '#fff';
  const ring = tone === 'ink' ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)';
  const S = size;
  // Notch proportion: 56% wide, 28% tall, attached to top
  const nw = S * 0.56, nh = S * 0.28;
  const nx = (S - nw) / 2, ny = 0;
  const nr = nh * 0.5;
  return (
    <div style={{ width: size, height: size, background: bg, borderRadius: size * 0.225, position: 'relative', overflow: 'hidden',
      boxShadow: `inset 0 0 0 1px ${ring}, 0 ${size*0.015}px ${size*0.06}px rgba(0,0,0,0.2)` }}>
      <svg width={S} height={S} viewBox={`0 0 ${S} ${S}`} style={{ display: 'block' }}>
        <path d={`M ${nx} ${ny} H ${nx+nw} V ${ny+nh-nr} A ${nr} ${nr} 0 0 1 ${nx+nw-nr} ${ny+nh} H ${nx+nr} A ${nr} ${nr} 0 0 1 ${nx} ${ny+nh-nr} Z`} fill={ink} />
        {variant === 'beacon' && (
          <>
            <rect x={nx + nw*0.18} y={ny + nh/2 - 1.2} width={nw*0.64} height="2.4" rx="1.2" fill={inv} opacity="0.35" />
            <circle cx={nx + nw*0.38} cy={ny + nh/2} r={nh*0.1} fill={inv} />
          </>
        )}
        {variant === 'bar' && (
          <rect x={nx + nw*0.2} y={ny + nh/2 - nh*0.12} width={nw*0.6} height={nh*0.24} rx={nh*0.12} fill={inv} />
        )}
      </svg>
    </div>
  );
}

// Wordmark lockup (using Beacon as the signature mark)
function Logo_WordLockup({ size = 420, tone = 'paper', mark = 'beacon' }) {
  const ink = inkV7(tone);
  const w = 420, h = 100;
  const markMap = { beacon: Logo_Beacon, corebar: Logo_CoreBar, bardot: Logo_BarDot, horizon: Logo_Horizon, traveler: Logo_Traveler, barstack: Logo_BarStack };
  const M = markMap[mark] || Logo_Beacon;
  return (
    <div style={{ display: 'inline-flex', alignItems: 'center', gap: size * 0.045 }}>
      <M size={size * 0.28} tone={tone} />
      <div style={{ fontFamily: 'Inter, sans-serif', color: ink, lineHeight: 1, letterSpacing: '-0.03em' }}>
        <div style={{ fontSize: size * 0.095, fontWeight: 700 }}>Open Island</div>
        <div style={{ fontSize: size * 0.034, fontWeight: 500, opacity: 0.55, marginTop: size * 0.012, fontFamily: 'JetBrains Mono, monospace' }}>
          agents in your menu bar
        </div>
      </div>
    </div>
  );
}

Object.assign(window, {
  Logo_Beacon, Logo_Horizon, Logo_Traveler,
  Logo_CoreBar, Logo_BarStack, Logo_BarDot,
  Logo_TallBeacon, Logo_TallCoreBar,
  AppIcon_Beacon: makeApp(Logo_Beacon, 0.72),
  AppIcon_Horizon: makeApp(Logo_Horizon, 0.72),
  AppIcon_Traveler: makeApp(Logo_Traveler, 0.72),
  AppIcon_CoreBar: makeApp(Logo_CoreBar, 0.72),
  AppIcon_BarStack: makeApp(Logo_BarStack, 0.72),
  AppIcon_BarDot: makeApp(Logo_BarDot, 0.72),
  AppIcon_TallBeacon: makeApp(Logo_TallBeacon, 0.58),
  AppIcon_TallCoreBar: makeApp(Logo_TallCoreBar, 0.58),
  AppIcon_TopAnchored,
  Logo_WordLockup,
});
