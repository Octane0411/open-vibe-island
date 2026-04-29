// v5 — Symbol system shared between Notch UI and Logo.
// Logic: notch displays state symbols (running/waiting/done/error/prompt).
// The logo = the pill + the brand's "resting" symbol. The app icon IS a notch in idle state.
// 7 candidate idle symbols → 7 paired (notch, logo, app icon) explorations.

// ---------- Shared ink ----------
const inkOfv5 = (tone) => tone === 'ink' ? '#f1ead9' : '#0d0d0f';
const invOfv5 = (tone) => tone === 'ink' ? '#0d0d0f' : '#f1ead9';

// ---------- The Symbol primitives ----------
// All drawn as "ink-on-knockout" glyphs, sized to live inside a pill's left cap
// Each is delivered as a function (cx, cy, scale, color) => <svg elements>

const Sym = {
  chevron: (cx, cy, s, c) => (
    <path d={`M ${cx-3.2*s} ${cy-5*s} L ${cx+3*s} ${cy} L ${cx-3.2*s} ${cy+5*s}`}
      stroke={c} strokeWidth={2.2*s} strokeLinecap="round" strokeLinejoin="round" fill="none" />
  ),
  dot: (cx, cy, s, c) => (
    <circle cx={cx} cy={cy} r={3.8*s} fill={c} />
  ),
  tick: (cx, cy, s, c) => (
    <path d={`M ${cx-5*s} ${cy} L ${cx-1*s} ${cy+4.2*s} L ${cx+5.5*s} ${cy-4.5*s}`}
      stroke={c} strokeWidth={2.4*s} strokeLinecap="round" strokeLinejoin="round" fill="none" />
  ),
  bars: (cx, cy, s, c) => (
    <g>
      <rect x={cx-5*s} y={cy-5*s} width={2*s} height={10*s} rx={s} fill={c} />
      <rect x={cx-1*s} y={cy-3*s} width={2*s} height={6*s}  rx={s} fill={c} />
      <rect x={cx+3*s} y={cy-6*s} width={2*s} height={12*s} rx={s} fill={c} />
    </g>
  ),
  bracket: (cx, cy, s, c) => (
    <g fill="none" stroke={c} strokeWidth={2*s} strokeLinecap="round" strokeLinejoin="round">
      <path d={`M ${cx-2*s} ${cy-5*s} L ${cx-6*s} ${cy} L ${cx-2*s} ${cy+5*s}`} />
      <path d={`M ${cx+2*s} ${cy-5*s} L ${cx+6*s} ${cy} L ${cx+2*s} ${cy+5*s}`} />
    </g>
  ),
  prompt: (cx, cy, s, c) => (
    // $ glyph stylised
    <g fill="none" stroke={c} strokeWidth={2.1*s} strokeLinecap="round">
      <path d={`M ${cx+4*s} ${cy-4*s} Q ${cx-4*s} ${cy-5*s} ${cx-4*s} ${cy-1*s} Q ${cx-4*s} ${cy+2*s} ${cx+4*s} ${cy+2*s} Q ${cx+4*s} ${cy+5*s} ${cx-4*s} ${cy+5*s}`} />
      <line x1={cx} y1={cy-7*s} x2={cx} y2={cy+7*s} />
    </g>
  ),
  triangle: (cx, cy, s, c) => (
    <path d={`M ${cx-4*s} ${cy-5*s} L ${cx+5*s} ${cy} L ${cx-4*s} ${cy+5*s} Z`} fill={c} />
  ),
};

// ---------- Notch component ----------
// Rendered inside a simulated menu bar. Notch is a rounded-bottom pill attached to the top.
function NotchBar({ symbolKey = 'dot', tone = 'ink', running = false, label = null, width = 180, height = 30, sRight = null }) {
  // Notch is always dark (it sits on dark menu bar)
  const bg = '#0d0d0f';
  const ink = '#f1ead9';
  const r = height / 2;
  const symScale = height / 30;

  return (
    <div style={{ position: 'relative', width, height }}>
      {/* pill */}
      <svg width={width} height={height} viewBox={`0 0 ${width} ${height}`} style={{ display: 'block' }}>
        <defs>
          <clipPath id="notchClip"><rect x="0" y="-2" width={width} height={height+2} rx={r} ry={r} /></clipPath>
        </defs>
        {/* Straight top, rounded bottom corners (dynamic-island style) */}
        <path d={`
          M 0 0
          H ${width}
          V ${height - r}
          A ${r} ${r} 0 0 1 ${width - r} ${height}
          H ${r}
          A ${r} ${r} 0 0 1 0 ${height - r}
          Z
        `} fill={bg} />
        {/* Left symbol */}
        {Sym[symbolKey] && Sym[symbolKey](22, height/2, symScale, ink)}
        {/* Label */}
        {label && (
          <text x={42} y={height/2} dy="0.34em" fill={ink}
            fontFamily="'JetBrains Mono', monospace" fontSize={11*symScale} fontWeight="500">{label}</text>
        )}
        {/* Right symbol (e.g. spinner, count, right-status) */}
        {sRight && Sym[sRight] && Sym[sRight](width-22, height/2, symScale, ink)}
        {/* Running: subtle dot pulse at right */}
        {running && (
          <circle cx={width-18} cy={height/2} r={3*symScale} fill={ink}>
            <animate attributeName="opacity" values="0.3;1;0.3" dur="1.2s" repeatCount="indefinite" />
          </circle>
        )}
      </svg>
    </div>
  );
}

function MenuBarMock({ children, wallpaper = 'plum', width = 520 }) {
  const bg = {
    plum: 'linear-gradient(135deg, #3c2344, #5f2e58 60%, #a8517a)',
    slate: 'linear-gradient(135deg, #1e2530, #3a4a5c)',
    forest: 'linear-gradient(135deg, #1b2e22, #3a5a3f)',
  }[wallpaper];
  return (
    <div style={{ width, borderRadius: 12, overflow: 'hidden', background: bg, border: '1px solid rgba(255,255,255,0.06)' }}>
      <div style={{ position: 'relative', height: 30, background: 'rgba(0,0,0,0.35)', backdropFilter: 'blur(8px)', display: 'flex', alignItems: 'center', padding: '0 10px' }}>
        <span style={{ fontSize: 12, color: '#f1ead9', fontWeight: 600 }}></span>
        <span style={{ fontSize: 12, color: '#f1ead9', marginLeft: 10 }}>Finder</span>
        <span style={{ fontSize: 12, color: '#f1ead9', marginLeft: 10, opacity: 0.8 }}>File Edit View</span>
        <span style={{ flex: 1 }} />
        <span style={{ fontSize: 11, color: '#f1ead9', opacity: 0.7, fontFamily: 'JetBrains Mono, monospace' }}>14:22</span>
        {/* Notch is centered, attached to top */}
        <div style={{ position: 'absolute', top: 0, left: '50%', transform: 'translateX(-50%)' }}>
          {children}
        </div>
      </div>
      <div style={{ height: 110 }} />
    </div>
  );
}

// ---------- Logo mark using a symbol ----------
function LogoWithSymbol({ symbolKey, size = 140, tone = 'paper' }) {
  const ink = inkOfv5(tone);
  const inv = invOfv5(tone);
  // Pill 140x62, symbol lives at left cap
  const w = 140, h = 62;
  const scale = 1.4;
  return (
    <svg width={size} height={size * h/w} viewBox={`0 0 ${w} ${h}`}>
      <rect x="2" y="2" width={w-4} height={h-4} rx={(h-4)/2} fill={ink} />
      {Sym[symbolKey] && Sym[symbolKey](28, h/2, scale, inv)}
    </svg>
  );
}

// ---------- App Icon ----------
function AppIconWithSymbol({ symbolKey, size = 200, tone = 'paper' }) {
  const bg = tone === 'paper' ? '#f1ead9' : tone === 'ink' ? '#0d0d0f' : '#fff';
  const ring = tone === 'ink' ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)';
  const r = size * 0.225;
  return (
    <div style={{
      width: size, height: size, background: bg, borderRadius: r,
      display: 'grid', placeItems: 'center',
      boxShadow: `inset 0 0 0 1px ${ring}, 0 ${size*0.015}px ${size*0.06}px rgba(0,0,0,0.2)`,
      overflow: 'hidden',
    }}>
      <LogoWithSymbol symbolKey={symbolKey} size={size * 0.72} tone={tone} />
    </div>
  );
}

// ---------- Notch state gallery for one symbol ----------
// Shows how the symbol evolves across states: idle / running / notify / done / expanded
function NotchStateRow({ symbolKey }) {
  // idle = only left symbol, minimal
  // running = left symbol + spinner dot at right
  // busy = left symbol + "3 bars" on right
  // notify = left symbol + label
  // done = switches to tick
  // expanded = wider with more text
  return (
    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(5, 1fr)', gap: 10 }}>
      <NotchCell label="idle">
        <NotchBar symbolKey={symbolKey} width={70} height={22} />
      </NotchCell>
      <NotchCell label="running">
        <NotchBar symbolKey={symbolKey} width={100} height={22} running />
      </NotchCell>
      <NotchCell label="busy">
        <NotchBar symbolKey={symbolKey} width={110} height={22} sRight="bars" />
      </NotchCell>
      <NotchCell label="notify">
        <NotchBar symbolKey={symbolKey} width={180} height={22} label="Ready to edit" />
      </NotchCell>
      <NotchCell label="done">
        <NotchBar symbolKey="tick" width={70} height={22} />
      </NotchCell>
    </div>
  );
}

function NotchCell({ label, children }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6 }}>
      <div style={{ background: '#2b1f3a', padding: '0px 0 0', borderRadius: 10, width: '100%', display: 'flex', justifyContent: 'center', minHeight: 40, alignItems: 'flex-start' }}>
        {children}
      </div>
      <span style={{ fontFamily: 'JetBrains Mono, monospace', fontSize: 10, color: '#5a5a68' }}>{label}</span>
    </div>
  );
}

Object.assign(window, { Sym, NotchBar, MenuBarMock, LogoWithSymbol, AppIconWithSymbol, NotchStateRow });
