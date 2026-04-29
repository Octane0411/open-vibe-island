// Agent & Terminal icon set — 3 directions
// Each icon takes { size, direction, theme, animated }
// direction: 'A' (liquid), 'B' (pixel), 'C' (terminal)

const AGENT_COLORS = {
  claude:  '#8b5cf6',
  codex:   '#10b981',
  ghostty: '#f97316',
  termapp: '#9ca3af',
  cmux:    '#06b6d4',
  kaku:    '#f43f5e',
  wezterm: '#3b82f6',
  opencode:'#eab308',
  gemini:  '#c084fc',
};

// ---- Base shapes per direction ----
function IconFrame({ children, color, direction, size = 48 }) {
  if (direction === 'A') {
    // Liquid — soft squircle, gradient-tinted glass
    return (
      <div style={{
        width: size, height: size, borderRadius: size * 0.28,
        background: `linear-gradient(145deg, ${color}, ${shade(color, -18)})`,
        display: 'grid', placeItems: 'center', color: '#fff',
        boxShadow: `inset 0 1px 0 rgba(255,255,255,0.35), inset 0 -8px 12px ${shade(color, -30)}55, 0 4px 12px ${color}44`,
        position: 'relative', overflow: 'hidden',
      }}>
        <div style={{
          position: 'absolute', inset: 0,
          background: 'radial-gradient(60% 40% at 30% 20%, rgba(255,255,255,0.55), transparent 60%)',
          pointerEvents: 'none',
        }} />
        <div style={{ position: 'relative', zIndex: 1 }}>{children}</div>
      </div>
    );
  }
  if (direction === 'B') {
    // Pixel — hard-edge square, scan-line bg
    return (
      <div style={{
        width: size, height: size,
        background: '#08120c',
        border: `2px solid ${color}`,
        boxShadow: `inset 0 0 0 2px #08120c, 0 0 0 0 ${color}`,
        display: 'grid', placeItems: 'center',
        color, fontFamily: "'VT323', 'JetBrains Mono', monospace",
        imageRendering: 'pixelated', position: 'relative',
      }}>
        <div style={{
          position: 'absolute', inset: 0, pointerEvents: 'none',
          background: 'repeating-linear-gradient(0deg, rgba(255,255,255,0.05) 0 1px, transparent 1px 3px)',
        }} />
        <div style={{ position: 'relative', zIndex: 1 }}>{children}</div>
      </div>
    );
  }
  // C: Terminal / ASCII
  return (
    <div style={{
      width: size, height: size,
      background: 'transparent',
      border: `1px solid ${color}66`,
      display: 'grid', placeItems: 'center',
      color, fontFamily: "'JetBrains Mono', monospace",
      position: 'relative',
    }}>
      <div style={{
        position: 'absolute', top: 3, left: 5, fontSize: size * 0.12,
        color: `${color}88`, fontFamily: "'JetBrains Mono', monospace"
      }}>┐</div>
      <div style={{ position: 'relative' }}>{children}</div>
    </div>
  );
}

function shade(hex, amt) {
  // quick shade
  const n = hex.replace('#','');
  const r = parseInt(n.slice(0,2),16), g = parseInt(n.slice(2,4),16), b = parseInt(n.slice(4,6),16);
  const adj = (v) => Math.max(0, Math.min(255, v + amt));
  return '#' + [adj(r), adj(g), adj(b)].map(v => v.toString(16).padStart(2,'0')).join('');
}

// ---- Per-agent glyphs ----
function Glyph({ name, size, direction, color }) {
  const gs = size * 0.52;
  // Each agent gets an abstract geometric glyph — NOT copying any real logos
  const glyphs = {
    claude: (
      // Three radiating arcs
      <svg width={gs} height={gs} viewBox="0 0 24 24" fill="none">
        <path d="M12 3 L12 21 M5 7 L19 17 M5 17 L19 7" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" />
      </svg>
    ),
    codex: (
      // Chevron stack
      <svg width={gs} height={gs} viewBox="0 0 24 24" fill="none">
        <path d="M5 8 L12 14 L19 8 M5 14 L12 20 L19 14" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" />
      </svg>
    ),
    opencode: (
      <svg width={gs} height={gs} viewBox="0 0 24 24" fill="none">
        <circle cx="12" cy="12" r="7" stroke="currentColor" strokeWidth="2.5" />
        <path d="M8 12 L16 12" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" />
      </svg>
    ),
    gemini: (
      <svg width={gs} height={gs} viewBox="0 0 24 24" fill="none">
        <path d="M12 3 L14 10 L21 12 L14 14 L12 21 L10 14 L3 12 L10 10 Z" stroke="currentColor" strokeWidth="2" fill="currentColor" fillOpacity="0.25" strokeLinejoin="round" />
      </svg>
    ),
    termapp: (
      <svg width={gs} height={gs} viewBox="0 0 24 24" fill="none">
        <path d="M5 7 L10 12 L5 17" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" />
        <path d="M12 18 L19 18" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" />
      </svg>
    ),
    ghostty: (
      // Rounded dome + 3 fangs
      <svg width={gs} height={gs} viewBox="0 0 24 24" fill="none">
        <path d="M5 10 a7 7 0 0 1 14 0 V20 L16 18 L13 20 L10 18 L7 20 Z" stroke="currentColor" strokeWidth="2" fill="currentColor" fillOpacity="0.15" strokeLinejoin="round" />
        <circle cx="10" cy="11" r="1.3" fill="currentColor" />
        <circle cx="15" cy="11" r="1.3" fill="currentColor" />
      </svg>
    ),
    cmux: (
      // Split panes
      <svg width={gs} height={gs} viewBox="0 0 24 24" fill="none">
        <rect x="4" y="5" width="7" height="14" stroke="currentColor" strokeWidth="2" rx="1" />
        <rect x="13" y="5" width="7" height="6"  stroke="currentColor" strokeWidth="2" rx="1" />
        <rect x="13" y="13" width="7" height="6" stroke="currentColor" strokeWidth="2" rx="1" />
      </svg>
    ),
    kaku: (
      // Brush stroke tilde
      <svg width={gs} height={gs} viewBox="0 0 24 24" fill="none">
        <path d="M4 14 Q8 8 12 14 T20 14" stroke="currentColor" strokeWidth="3" strokeLinecap="round" />
      </svg>
    ),
    wezterm: (
      // W + horizon line
      <svg width={gs} height={gs} viewBox="0 0 24 24" fill="none">
        <path d="M4 7 L8 17 L12 10 L16 17 L20 7" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" />
      </svg>
    ),
  };
  return glyphs[name] || <span>?</span>;
}

function AgentIcon({ name, size = 48, direction = 'A' }) {
  const color = AGENT_COLORS[name] || '#888';
  // In direction B (pixel) we use high-contrast; C we use line
  return (
    <IconFrame color={color} direction={direction} size={size}>
      <div style={{ color: direction === 'A' ? '#fff' : color, display: 'grid', placeItems: 'center' }}>
        <Glyph name={name} size={size} direction={direction} color={color} />
      </div>
    </IconFrame>
  );
}

// Status icons (idle, running, waiting-permission, error, done)
function StatusIcon({ state, direction = 'A', size = 32 }) {
  const color = {
    idle: '#9a9aa8', running: '#10b981', waiting: '#f59e0b',
    error: '#ef4444', done: '#06b6d4',
  }[state] || '#9a9aa8';

  if (direction === 'B') {
    return (
      <div style={{
        width: size, height: size, position: 'relative',
        display: 'grid', placeItems: 'center',
      }}>
        <div style={{
          width: size * 0.5, height: size * 0.5,
          background: color,
          clipPath: state === 'error'
            ? 'polygon(50% 0, 100% 100%, 0 100%)'
            : state === 'waiting' ? 'polygon(50% 0,100% 50%,50% 100%,0 50%)'
            : 'none',
          imageRendering: 'pixelated',
          animation: state === 'running' ? 'blink 0.6s steps(2) infinite' : 'none',
        }} />
      </div>
    );
  }
  if (direction === 'C') {
    const ch = { idle:'○', running:'◉', waiting:'◎', error:'✕', done:'◆' }[state];
    return <span style={{ color, fontFamily: "'JetBrains Mono', monospace", fontSize: size * 0.7, display: 'inline-block', width: size, height: size, lineHeight: `${size}px`, textAlign: 'center' }}>{ch}</span>;
  }
  // A: soft dot
  return (
    <div style={{
      width: size, height: size, display: 'grid', placeItems: 'center', position: 'relative',
    }}>
      <div style={{
        width: size * 0.45, height: size * 0.45, borderRadius: '50%',
        background: `radial-gradient(circle at 30% 30%, ${shade(color, 40)}, ${color})`,
        boxShadow: `0 0 ${size*0.3}px ${color}77`,
        animation: state === 'running' ? 'breathe 1.4s ease-in-out infinite' : 'none',
      }} />
      {state === 'waiting' && (
        <div style={{
          position: 'absolute', inset: size*0.15,
          borderRadius: '50%', border: `2px solid ${color}`,
          animation: 'pulse-ring 1.4s ease-out infinite',
        }} />
      )}
    </div>
  );
}

Object.assign(window, { AgentIcon, StatusIcon, AGENT_COLORS });
