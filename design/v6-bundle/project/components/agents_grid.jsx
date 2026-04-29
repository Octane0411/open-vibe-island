// v6 — Agents right-slot REDESIGN
// Problem: current implementation renders a row of 7pt filled circles with brand
// colors, several of which (Gemini green, Claude orange) are uncomfortably close
// to macOS camera/mic privacy indicators — and they sit in the same screen region.
// This module explores 4 square-matrix treatments that break visually from the
// "tinted dot" vocabulary while preserving the per-agent color identity.
//
// Two orthogonal axes:
//   1. Visual language  → V1 Dense / V2 Tight / V3 Framed / V4 Pixel
//   2. Layout algorithm → 'wrap'     (4-col auto wrap)
//                       | 'balanced' (hand-tuned rows per n: 4→[2,2], 5→[3,2]...)
//
// Shared data shape:
//   sessions: [{ color: '#hex', state: 'running' | 'idle' | 'waiting' }]

const MAX_VISIBLE = 8; // 9+ → show 8 cells with last one as "+N"
const WRAP_COLS = 4;

// --- Layout algorithm --------------------------------------------------------
// Returns an array of row sizes for a given session count, tuned so every n
// feels visually centered / deliberately composed.
//   1  → [1]        2  → [2]        3  → [3]
//   4  → [2,2]      5  → [3,2]      6  → [3,3]
//   7  → [4,3]      8  → [4,4]      9  → [3,3,3]
function balancedRows(n) {
  if (n <= 0) return [];
  const table = {
    1: [1], 2: [2], 3: [3],
    4: [2, 2], 5: [3, 2], 6: [3, 3],
    7: [4, 3], 8: [4, 4], 9: [3, 3, 3],
  };
  if (table[n]) return table[n];
  // 10+ rendered as visible:8 + "+N" sharing the n=8 block
  return [4, 4];
}

function wrapRows(n, cols = WRAP_COLS) {
  const rows = [];
  let left = n;
  while (left > 0) { const take = Math.min(cols, left); rows.push(take); left -= take; }
  return rows;
}

// Plan: returns { rows, cells, overflow, maxRow } where each cell carries
// its (row, col) position and index into the source sessions array.
function planLayout(sessions, { layout, wrapCols = WRAP_COLS } = { layout: 'balanced' }) {
  const n = sessions.length;
  let visibleCount = n;
  let overflow = 0;
  if (n > 9 || (layout === 'wrap' && n > MAX_VISIBLE)) {
    // Reserve last slot for "+N" marker
    visibleCount = MAX_VISIBLE - 1;
    overflow = n - visibleCount;
  } else if (layout === 'balanced' && n > 9) {
    visibleCount = 7;
    overflow = n - 7;
  }

  const rowSizes = layout === 'balanced'
    ? (overflow > 0 ? [4, 4] : balancedRows(n))
    : wrapRows(visibleCount + (overflow > 0 ? 1 : 0), wrapCols);

  const maxRow = Math.max(...rowSizes);

  const cells = [];
  let sessionIdx = 0;
  for (let r = 0; r < rowSizes.length; r++) {
    for (let c = 0; c < rowSizes[r]; c++) {
      const isLast = (r === rowSizes.length - 1) && (c === rowSizes[r] - 1);
      if (overflow > 0 && isLast) {
        cells.push({ row: r, col: c, rowSize: rowSizes[r], kind: 'overflow' });
      } else if (sessionIdx < sessions.length) {
        cells.push({ row: r, col: c, rowSize: rowSizes[r], kind: 'cell', session: sessions[sessionIdx] });
        sessionIdx++;
      }
    }
  }

  return { rows: rowSizes, cells, overflow, maxRow };
}

// Compute x/y of a cell given geometry + layout plan.
// Each row is horizontally centered around the widest row.
function cellPosition({ row, col, rowSize, maxRow, cell, gap }) {
  const rowWidth = rowSize * cell + (rowSize - 1) * gap;
  const fullWidth = maxRow * cell + (maxRow - 1) * gap;
  const rowOffsetX = (fullWidth - rowWidth) / 2;
  const x = rowOffsetX + col * (cell + gap);
  const y = row * (cell + gap);
  return { x, y };
}

// --- Helpers ----------------------------------------------------------------
function dimColor(hex, alpha) {
  const h = hex.replace('#', '');
  const r = parseInt(h.slice(0, 2), 16);
  const g = parseInt(h.slice(2, 4), 16);
  const b = parseInt(h.slice(4, 6), 16);
  return `rgba(${r},${g},${b},${alpha})`;
}

// Geometry per variant. For n=9 (3 rows) we shrink cells a notch so the matrix
// fits the pill's internal vertical budget.
function geometryFor(variant, rowCount) {
  const base = {
    v1: { cell: 8, gap: 2, r: 1.5 },
    v2: { cell: 5, gap: 1.5, r: 1 },
    v3: { cell: 8, gap: 2, r: 1.5 },
    v4: { cell: 4, gap: 1.2, r: 0.5 },
  }[variant];
  if (rowCount >= 3) {
    // Tighten so total height stays ≤ 20pt
    return { ...base, cell: Math.max(3, base.cell - 2), gap: Math.max(1, base.gap - 0.5) };
  }
  return base;
}

// --- V1 · DENSE GRID ---------------------------------------------------------
// Base tile: 8×8 rounded square. Running = solid color · Idle = same color at
// 22% alpha. Waiting has multiple candidate treatments exposed via
// `waitingStyle`:
//   'breath'  — pure opacity pulse 0.35 ↔ 1 on the tile itself
//   'halo'    — same-color blurred halo fades around the tile (no hard edge)
//   'scale'   — tile gently scales 0.82 ↔ 1.05 with opacity pulse
//   'tick'    — cream-ink dot in the tile center pulses (indicator in-cell)
//   'edge'    — a brighter top-edge highlight bar + soft halo
//   'outline' — legacy white-cream 1px outline (for comparison only)
function AgentsGridV1({ sessions, layout = 'balanced', displayScale = 1, waitingStyle = 'breath' }) {
  const plan = planLayout(sessions, { layout });
  const { cell, gap, r } = geometryFor('v1', plan.rows.length);
  const W = plan.maxRow * cell + (plan.maxRow - 1) * gap;
  const H = plan.rows.length * cell + (plan.rows.length - 1) * gap;

  const defs = `
    @keyframes v1-breath { 0%,100% { opacity: 0.35; } 50% { opacity: 1; } }
    @keyframes v1-halo   { 0%,100% { opacity: 0; } 50% { opacity: 0.9; } }
    @keyframes v1-scale  { 0%,100% { transform: scale(0.82); opacity: 0.55; } 50% { transform: scale(1.05); opacity: 1; } }
    @keyframes v1-tick   { 0%,100% { opacity: 0.2; } 50% { opacity: 1; } }
    @keyframes v1-edge   { 0%,100% { opacity: 0.35; } 50% { opacity: 1; } }
  `;

  const renderWaiting = (s, x, y, key) => {
    const cx = x + cell / 2, cy = y + cell / 2;
    switch (waitingStyle) {
      case 'outline':
        return (
          <g key={key}>
            <rect x={x} y={y} width={cell} height={cell} rx={r} fill={s.color}
              style={{ animation: 'v1-breath 1.4s ease-in-out infinite' }} />
            <rect x={x - 0.5} y={y - 0.5} width={cell + 1} height={cell + 1} rx={r + 0.5}
              fill="none" stroke="#f1ead9" strokeOpacity="0.9" strokeWidth="1" />
          </g>
        );
      case 'halo': {
        const filterId = `v1-halo-blur-${key}`;
        return (
          <g key={key}>
            <defs>
              <filter id={filterId} x="-50%" y="-50%" width="200%" height="200%">
                <feGaussianBlur in="SourceGraphic" stdDeviation="1.6" />
              </filter>
            </defs>
            <rect x={x - 2} y={y - 2} width={cell + 4} height={cell + 4} rx={r + 2}
              fill={s.color} filter={`url(#${filterId})`}
              style={{ transformOrigin: `${cx}px ${cy}px`, animation: 'v1-halo 1.4s ease-in-out infinite' }} />
            <rect x={x} y={y} width={cell} height={cell} rx={r} fill={s.color} />
          </g>
        );
      }
      case 'scale':
        return (
          <rect key={key} x={x} y={y} width={cell} height={cell} rx={r} fill={s.color}
            style={{ transformOrigin: `${cx}px ${cy}px`, animation: 'v1-scale 1.4s ease-in-out infinite' }} />
        );
      case 'tick': {
        const dotR = Math.max(1, cell * 0.22);
        return (
          <g key={key}>
            <rect x={x} y={y} width={cell} height={cell} rx={r} fill={s.color} />
            <circle cx={cx} cy={cy} r={dotR} fill="#f1ead9"
              style={{ animation: 'v1-tick 1.1s ease-in-out infinite' }} />
          </g>
        );
      }
      case 'edge': {
        const barH = Math.max(0.8, cell * 0.18);
        return (
          <g key={key}>
            <rect x={x} y={y} width={cell} height={cell} rx={r} fill={s.color} />
            <rect x={x} y={y} width={cell} height={barH} rx={r} fill="#f1ead9" fillOpacity="0.55"
              style={{ animation: 'v1-edge 1.4s ease-in-out infinite' }} />
          </g>
        );
      }
      case 'breath':
      default:
        return (
          <rect key={key} x={x} y={y} width={cell} height={cell} rx={r} fill={s.color}
            style={{ animation: 'v1-breath 1.4s ease-in-out infinite' }} />
        );
    }
  };

  return (
    <svg width={W * displayScale} height={H * displayScale} viewBox={`0 0 ${W} ${H}`} style={{ overflow: 'visible' }}>
      <defs><style>{defs}</style></defs>
      {plan.cells.map((c, i) => {
        const { x, y } = cellPosition({ ...c, maxRow: plan.maxRow, cell, gap });
        if (c.kind === 'overflow') {
          return (
            <g key={i}>
              <rect x={x} y={y} width={cell} height={cell} rx={r} fill="#f1ead9" fillOpacity="0.14" />
              <text x={x + cell / 2} y={y + cell / 2} dy="0.36em" textAnchor="middle"
                fill="#f1ead9" fontFamily="'JetBrains Mono', monospace" fontSize={cell * 0.68} fontWeight="700">+{plan.overflow}</text>
            </g>
          );
        }
        const s = c.session;
        if (s.state === 'waiting') return renderWaiting(s, x, y, i);
        const fill = s.state === 'running' ? s.color : dimColor(s.color, 0.22);
        return <rect key={i} x={x} y={y} width={cell} height={cell} rx={r} fill={fill} />;
      })}
    </svg>
  );
}

// --- V2 · TIGHT GRID ---------------------------------------------------------
function AgentsGridV2({ sessions, layout = 'balanced', displayScale = 1 }) {
  const plan = planLayout(sessions, { layout });
  const { cell, gap, r } = geometryFor('v2', plan.rows.length);
  const W = plan.maxRow * cell + (plan.maxRow - 1) * gap;
  const H = plan.rows.length * cell + (plan.rows.length - 1) * gap;

  return (
    <svg width={W * displayScale} height={H * displayScale} viewBox={`0 0 ${W} ${H}`} style={{ overflow: 'visible' }}>
      <defs><style>{`@keyframes v2-wait-halo { 0%,100% { opacity: 0.2; transform: scale(1); } 50% { opacity: 0.85; transform: scale(1.25); } }`}</style></defs>
      {plan.cells.map((c, i) => {
        const { x, y } = cellPosition({ ...c, maxRow: plan.maxRow, cell, gap });
        const cx = x + cell / 2, cy = y + cell / 2;
        if (c.kind === 'overflow') {
          return (
            <g key={i}>
              <rect x={x} y={y} width={cell} height={cell} rx={r} fill="#f1ead9" fillOpacity="0.18" />
              <text x={cx} y={cy} dy="0.36em" textAnchor="middle"
                fill="#f1ead9" fontFamily="'JetBrains Mono', monospace" fontSize={cell * 0.7} fontWeight="700">+{plan.overflow}</text>
            </g>
          );
        }
        const s = c.session;
        if (s.state === 'waiting') {
          return (
            <g key={i}>
              <rect x={x - 2} y={y - 2} width={cell + 4} height={cell + 4} rx={r + 1}
                fill="none" stroke={s.color} strokeWidth="0.8"
                style={{ transformOrigin: `${cx}px ${cy}px`, animation: 'v2-wait-halo 1.4s ease-in-out infinite' }} />
              <rect x={x} y={y} width={cell} height={cell} rx={r} fill={s.color} />
            </g>
          );
        }
        const fill = s.state === 'running' ? s.color : dimColor(s.color, 0.2);
        return <rect key={i} x={x} y={y} width={cell} height={cell} rx={r} fill={fill} />;
      })}
    </svg>
  );
}

// --- V3 · FRAMED MATRIX ------------------------------------------------------
// When wrap layout is used we keep the 2×4 skeleton of empty slots; balanced
// layout by definition has no empty slots (rows are exactly sized), so the
// skeleton only shows around actual cells.
function AgentsGridV3({ sessions, layout = 'balanced', displayScale = 1 }) {
  const plan = planLayout(sessions, { layout });
  const { cell, gap, r } = geometryFor('v3', plan.rows.length);

  // For wrap layout, pad each row to WRAP_COLS so the 2×4 skeleton is preserved.
  const rowsPadded = layout === 'wrap'
    ? plan.rows.map(() => WRAP_COLS)
    : plan.rows;
  const maxRow = Math.max(...rowsPadded);
  const rowCount = Math.max(rowsPadded.length, layout === 'wrap' ? 2 : 1);
  const W = maxRow * cell + (maxRow - 1) * gap;
  const H = rowCount * cell + (rowCount - 1) * gap;

  // Build a lookup of placed cells to know which skeleton slots are empty.
  const placed = new Map(plan.cells.map(c => [`${c.row}-${c.col}`, c]));

  const slots = [];
  for (let rr = 0; rr < rowCount; rr++) {
    const rowW = rowsPadded[rr] ?? (layout === 'wrap' ? WRAP_COLS : 0);
    for (let cc = 0; cc < rowW; cc++) {
      slots.push({ row: rr, col: cc, rowSize: rowW, cell: placed.get(`${rr}-${cc}`) });
    }
  }

  return (
    <svg width={W * displayScale} height={H * displayScale} viewBox={`0 0 ${W} ${H}`} style={{ overflow: 'visible' }}>
      <defs><style>{`@keyframes v3-wait-glow { 0%,100% { opacity: 0.25; } 50% { opacity: 0.95; } }`}</style></defs>
      {slots.map((slot, i) => {
        const { x, y } = cellPosition({ row: slot.row, col: slot.col, rowSize: slot.rowSize, maxRow, cell, gap });
        const c = slot.cell;
        if (!c) {
          return (
            <rect key={i} x={x + 0.5} y={y + 0.5} width={cell - 1} height={cell - 1} rx={r}
              fill="none" stroke="#f1ead9" strokeOpacity="0.18" strokeWidth="0.8" />
          );
        }
        if (c.kind === 'overflow') {
          return (
            <g key={i}>
              <rect x={x + 0.5} y={y + 0.5} width={cell - 1} height={cell - 1} rx={r}
                fill="none" stroke="#f1ead9" strokeOpacity="0.35" strokeWidth="0.8" />
              <text x={x + cell / 2} y={y + cell / 2} dy="0.36em" textAnchor="middle"
                fill="#f1ead9" fontFamily="'JetBrains Mono', monospace" fontSize={cell * 0.62} fontWeight="700">+{plan.overflow}</text>
            </g>
          );
        }
        const s = c.session;
        if (s.state === 'running') {
          return <rect key={i} x={x} y={y} width={cell} height={cell} rx={r} fill={s.color} />;
        }
        if (s.state === 'idle') {
          return (
            <rect key={i} x={x + 0.5} y={y + 0.5} width={cell - 1} height={cell - 1} rx={r}
              fill="none" stroke={s.color} strokeOpacity="0.7" strokeWidth="0.9" />
          );
        }
        return (
          <g key={i}>
            <rect x={x - 1} y={y - 1} width={cell + 2} height={cell + 2} rx={r + 1}
              fill={s.color} style={{ animation: 'v3-wait-glow 1.4s ease-in-out infinite' }} />
            <rect x={x} y={y} width={cell} height={cell} rx={r} fill={s.color} />
          </g>
        );
      })}
    </svg>
  );
}

// --- V4 · PIXEL PANEL --------------------------------------------------------
// Balanced layout + tiny pixels. With balanced layout the outer panel frame
// still reads as "a panel" even for n=1.
function AgentsGridV4({ sessions, layout = 'balanced', displayScale = 1 }) {
  const plan = planLayout(sessions, { layout });
  const { cell, gap, r } = geometryFor('v4', plan.rows.length);

  const rowsPadded = layout === 'wrap' ? plan.rows.map(() => WRAP_COLS) : plan.rows;
  const maxRow = Math.max(...rowsPadded);
  const rowCount = Math.max(rowsPadded.length, layout === 'wrap' ? 2 : 1);
  const inner = {
    w: maxRow * cell + (maxRow - 1) * gap,
    h: rowCount * cell + (rowCount - 1) * gap,
  };
  const pad = 2;

  const placed = new Map(plan.cells.map(c => [`${c.row}-${c.col}`, c]));
  const slots = [];
  for (let rr = 0; rr < rowCount; rr++) {
    const rowW = rowsPadded[rr] ?? (layout === 'wrap' ? WRAP_COLS : 0);
    for (let cc = 0; cc < rowW; cc++) {
      slots.push({ row: rr, col: cc, rowSize: rowW, cell: placed.get(`${rr}-${cc}`) });
    }
  }

  return (
    <svg width={(inner.w + pad * 2) * displayScale} height={(inner.h + pad * 2) * displayScale}
      viewBox={`${-pad} ${-pad} ${inner.w + pad * 2} ${inner.h + pad * 2}`}
      style={{ overflow: 'visible' }}>
      <defs><style>{`@keyframes v4-wait-blink { 0%,100% { opacity: 0.35; } 50% { opacity: 1; } }`}</style></defs>
      <rect x={-pad + 0.5} y={-pad + 0.5} width={inner.w + pad * 2 - 1} height={inner.h + pad * 2 - 1} rx={2}
        fill="#f1ead9" fillOpacity="0.05" stroke="#f1ead9" strokeOpacity="0.15" strokeWidth="0.5" />
      {slots.map((slot, i) => {
        const { x, y } = cellPosition({ row: slot.row, col: slot.col, rowSize: slot.rowSize, maxRow, cell, gap });
        const c = slot.cell;
        if (!c) {
          return <rect key={i} x={x} y={y} width={cell} height={cell} rx={r}
            fill="#f1ead9" fillOpacity="0.08" />;
        }
        if (c.kind === 'overflow') {
          return <rect key={i} x={x} y={y} width={cell} height={cell} rx={r} fill="#f1ead9" fillOpacity="0.22" />;
        }
        const s = c.session;
        if (s.state === 'waiting') {
          return <rect key={i} x={x} y={y} width={cell} height={cell} rx={r} fill={s.color}
            style={{ animation: 'v4-wait-blink 0.9s ease-in-out infinite' }} />;
        }
        const fill = s.state === 'running' ? s.color : dimColor(s.color, 0.28);
        return <rect key={i} x={x} y={y} width={cell} height={cell} rx={r} fill={fill} />;
      })}
    </svg>
  );
}

// --- Right-slot width hint (for pill layout math) ---------------------------
// Matches what each variant actually renders:
//   balanced (all variants) → variable width = plan.maxRow cells
//   wrap V1 / V2            → variable width, same as balanced math
//   wrap V3 / V4            → fixed 4-col skeleton / panel
function rightWidthFor(variant, sessions, layout = 'balanced') {
  const plan = planLayout(sessions, { layout });
  const { cell, gap } = geometryFor(variant, plan.rows.length);
  const fixedGrid = layout === 'wrap' && (variant === 'v3' || variant === 'v4');
  const maxRow = fixedGrid ? WRAP_COLS : plan.maxRow;
  let w = maxRow * cell + (maxRow - 1) * gap;
  if (variant === 'v4') w += 4; // panel frame padding
  return w;
}

const GRID_COMPONENTS = {
  v1: AgentsGridV1,
  v2: AgentsGridV2,
  v3: AgentsGridV3,
  v4: AgentsGridV4,
};

Object.assign(window, {
  AgentsGridV1, AgentsGridV2, AgentsGridV3, AgentsGridV4,
  GRID_COMPONENTS, rightWidthFor, dimColor, balancedRows, planLayout,
});
