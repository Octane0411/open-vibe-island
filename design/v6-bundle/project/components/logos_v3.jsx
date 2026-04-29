// Logomarks — v3. Direction locked: 药丸/notch 形 + 极简几何。
// Palette: pure black/white + warm paper. Max 1-2 elements. macOS-native app icon container.
// Each mark has: PillWord(size) → just the mark; AppIcon(size) → inside rounded squircle.
// References (feel, not copy): Warp fluid type, Ghostty minimal geo, Linear sharp geo, Figma mono.

const { useId: useId_v3 } = React;

// Shared app-icon container — macOS squircle, paper or ink.
function Squircle({ size = 200, tone = 'paper', children, inset = 0 }) {
  const bg = tone === 'paper' ? '#f1ead9' : tone === 'ink' ? '#0d0d0f' : '#ffffff';
  const ring = tone === 'paper' ? 'rgba(0,0,0,0.06)' : tone === 'ink' ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.05)';
  const r = size * 0.225;
  return (
    <div style={{
      width: size, height: size, background: bg, borderRadius: r,
      display: 'grid', placeItems: 'center', position: 'relative',
      boxShadow: `inset 0 0 0 1px ${ring}, 0 ${size*0.015}px ${size*0.06}px rgba(0,0,0,0.2)`,
      overflow: 'hidden',
    }}>
      <div style={{ width: size - inset*2, height: size - inset*2, display: 'grid', placeItems: 'center' }}>
        {children}
      </div>
    </div>
  );
}

// ---------- M1. Pure pill ----------
// One ink pill, centered. That's it. Ghostty/Figma-level restraint.
function Mark_Pill({ size = 128, tone = 'paper' }) {
  const ink = tone === 'ink' ? '#f1ead9' : '#0d0d0f';
  return (
    <svg width={size} height={size * 0.45} viewBox="0 0 128 58">
      <rect x="2" y="2" width="124" height="54" rx="27" fill={ink} />
    </svg>
  );
}
function AppIcon_Pill({ size = 200, tone = 'paper' }) {
  return <Squircle size={size} tone={tone}><Mark_Pill size={size * 0.62} tone={tone} /></Squircle>;
}

// ---------- M2. Pill + drop ----------
// Pill with a single droplet below — reads as "notch" + "island signal".
function Mark_Drop({ size = 128, tone = 'paper', animated = true }) {
  const id = useId_v3();
  const ink = tone === 'ink' ? '#f1ead9' : '#0d0d0f';
  return (
    <svg width={size} height={size} viewBox="0 0 128 128">
      <rect x="24" y="28" width="80" height="28" rx="14" fill={ink} />
      <circle cx="64" cy="92" r="9" fill={ink}
        style={animated ? { animation: 'm3drop 2.6s cubic-bezier(.55,.05,.2,1) infinite', transformOrigin: '64px 92px' } : {}} />
      {animated && <style>{`@keyframes m3drop {
        0%,100% { transform: translateY(-14px) scale(0.8); opacity: 0; }
        25% { transform: translateY(0) scale(1); opacity: 1; }
        60% { transform: translateY(0) scale(1); opacity: 1; }
        80% { transform: translateY(6px) scale(0.9); opacity: 0.6; }
      }`}</style>}
    </svg>
  );
}
function AppIcon_Drop({ size = 200, tone = 'paper', animated = true }) {
  return <Squircle size={size} tone={tone}><Mark_Drop size={size * 0.68} tone={tone} animated={animated} /></Squircle>;
}

// ---------- M3. Stacked pills (mountain/island) ----------
// Two pills stacked like horizon layers. A skyline from afar, a notch from up close.
function Mark_Horizon({ size = 128, tone = 'paper' }) {
  const ink = tone === 'ink' ? '#f1ead9' : '#0d0d0f';
  return (
    <svg width={size} height={size} viewBox="0 0 128 128">
      <rect x="16" y="48" width="96" height="18" rx="9" fill={ink} />
      <rect x="36" y="72" width="56" height="12" rx="6" fill={ink} opacity="0.35" />
    </svg>
  );
}
function AppIcon_Horizon({ size = 200, tone = 'paper' }) {
  return <Squircle size={size} tone={tone}><Mark_Horizon size={size * 0.72} tone={tone} /></Squircle>;
}

// ---------- M4. Pill with inner notch ----------
// A pill that literally cuts a notch into its bottom edge. Meta: the notch eating itself.
function Mark_InnerNotch({ size = 128, tone = 'paper' }) {
  const ink = tone === 'ink' ? '#f1ead9' : '#0d0d0f';
  // Pill with small rectangle + rounded corners subtracted from the bottom
  return (
    <svg width={size} height={size * 0.5} viewBox="0 0 128 64">
      <path d={`
        M 32 4
        H 96
        A 28 28 0 0 1 96 60
        H 76
        Q 76 50 68 50
        L 60 50
        Q 52 50 52 60
        H 32
        A 28 28 0 0 1 32 4
        Z
      `} fill={ink} />
    </svg>
  );
}
function AppIcon_InnerNotch({ size = 200, tone = 'paper' }) {
  return <Squircle size={size} tone={tone}><Mark_InnerNotch size={size * 0.72} tone={tone} /></Squircle>;
}

// ---------- M5. Pill with vertical bar (cursor) ----------
// A pill with a single ink stroke rising through it — notch meets terminal cursor.
function Mark_Cursor({ size = 128, tone = 'paper', animated = true }) {
  const ink = tone === 'ink' ? '#f1ead9' : '#0d0d0f';
  return (
    <svg width={size} height={size * 0.65} viewBox="0 0 128 84">
      <rect x="8" y="30" width="112" height="24" rx="12" fill={ink} />
      <rect x="60" y="6" width="8" height="72" rx="1" fill={ink}
        style={animated ? { animation: 'm5blink 1.1s steps(2) infinite' } : {}} />
      {animated && <style>{`@keyframes m5blink { 50% { opacity: 0.15; } }`}</style>}
    </svg>
  );
}
function AppIcon_Cursor({ size = 200, tone = 'paper', animated = true }) {
  return <Squircle size={size} tone={tone}><Mark_Cursor size={size * 0.72} tone={tone} animated={animated} /></Squircle>;
}

// ---------- M6. Two pills forming O + I ligature ----------
// A horizontal pill (O-hole reading) + a vertical pill (I). Monogram without literal letters.
function Mark_OI({ size = 128, tone = 'paper' }) {
  const ink = tone === 'ink' ? '#f1ead9' : '#0d0d0f';
  return (
    <svg width={size} height={size * 0.55} viewBox="0 0 128 70">
      {/* O: open pill (ring) */}
      <path d="M38 12 A 23 23 0 1 0 38 58 A 23 23 0 1 0 38 12 Z M38 24 A 11 11 0 1 1 38 46 A 11 11 0 1 1 38 24 Z" fill={ink} fillRule="evenodd" />
      {/* I: vertical pill */}
      <rect x="84" y="12" width="20" height="46" rx="10" fill={ink} />
    </svg>
  );
}
function AppIcon_OI({ size = 200, tone = 'paper' }) {
  return <Squircle size={size} tone={tone}><Mark_OI size={size * 0.75} tone={tone} /></Squircle>;
}

Object.assign(window, {
  Squircle,
  Mark_Pill, AppIcon_Pill,
  Mark_Drop, AppIcon_Drop,
  Mark_Horizon, AppIcon_Horizon,
  Mark_InnerNotch, AppIcon_InnerNotch,
  Mark_Cursor, AppIcon_Cursor,
  Mark_OI, AppIcon_OI,
});
