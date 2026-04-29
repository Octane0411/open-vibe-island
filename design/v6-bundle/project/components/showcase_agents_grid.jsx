// v6 — Agents right-slot redesign: preview page.
// Compares 4 square-matrix variants against the current "tinted dot" baseline.

const { useState: useState_ag, useEffect: useEffect_ag } = React;

const V6_INK = '#f1ead9';
const V6_PAPER = '#0d0d0f';

// Inlined copy of UnifiedBars from notch_v6_locked.jsx so this page is
// self-contained and does not depend on loading the full v6 notch bundle.
function UnifiedBars({ mode = 'running' }) {
  const cols = [
    { x: 5.25, idleH: 3, runCycle: [4, 12, 4], runDelay: 0, waitH: 10 },
    { x: 10.75, idleH: 5, runCycle: [6, 14, 6], runDelay: 0.15, waitH: 0 },
    { x: 16.25, idleH: 3, runCycle: [4, 10, 4], runDelay: 0.3, waitH: 10 },
  ];
  const BAR_W = 2.5;
  const CENTER = 12;
  return (
    <g fill={V6_INK}>
      {cols.map((c, i) => {
        if (mode === 'running') {
          const [lo, hi, lo2] = c.runCycle;
          return (
            <rect key={i} x={c.x} width={BAR_W} rx={BAR_W / 2}
              y={CENTER - lo / 2} height={lo}>
              <animate attributeName="height" values={`${lo};${hi};${lo2}`} dur="0.9s" begin={`${c.runDelay}s`} repeatCount="indefinite" />
              <animate attributeName="y" values={`${CENTER - lo / 2};${CENTER - hi / 2};${CENTER - lo2 / 2}`} dur="0.9s" begin={`${c.runDelay}s`} repeatCount="indefinite" />
            </rect>
          );
        }
        const isWaiting = mode === 'waiting';
        const h = isWaiting ? c.waitH : c.idleH;
        const y = CENTER - h / 2;
        const opacity = isWaiting && c.waitH === 0 ? 0 : 1;
        return <rect key={i} x={c.x} width={BAR_W} rx={BAR_W / 2} y={y} height={h} opacity={opacity} />;
      })}
    </g>
  );
}

// v6 brand palette (mirrors AgentTool.brandColorHex in OpenIslandCore).
const AGENT_PALETTE = [
  { name: 'Claude', color: '#d97742' },
  { name: 'Codex', color: '#4aa3df' },
  { name: 'Cursor', color: '#7a5cff' },
  { name: 'Gemini', color: '#42e86b' },
  { name: 'OpenCode', color: '#ffb547' },
  { name: 'Qoder', color: '#ff6b9f' },
  { name: 'Qwen', color: '#c084fc' },
  { name: 'Factory', color: '#6e9fff' },
];

// Scenario: pick n sessions from the palette and assign states by a pattern.
function buildScenario(n, pattern) {
  // pattern: 'all-running' | 'mixed' | 'one-waiting' | 'all-waiting'
  return AGENT_PALETTE.slice(0, n).map((a, i) => {
    let state = 'running';
    if (pattern === 'mixed') {
      // Alternating running/idle, with one waiting if n >= 3
      state = i % 2 === 0 ? 'running' : 'idle';
      if (n >= 3 && i === 2) state = 'waiting';
    } else if (pattern === 'one-waiting') {
      state = i === Math.min(1, n - 1) ? 'waiting' : 'running';
    } else if (pattern === 'all-waiting') {
      state = 'waiting';
    }
    return { color: a.color, state, name: a.name };
  });
}

// --- Baseline (current implementation) for side-by-side comparison ----------
function AgentsBaselineDots({ sessions }) {
  // Mirrors the current V6RightSlotView.agents: row of 7pt filled circles.
  // Ignores state (the current implementation only knows about "active" sessions).
  const W = sessions.length * 7 + Math.max(0, sessions.length - 1) * 4;
  return (
    <svg width={W} height={7} viewBox={`0 0 ${W} 7`} style={{ overflow: 'visible' }}>
      {sessions.map((s, i) => (
        <circle key={i} cx={3.5 + i * 11} cy={3.5} r={3.5} fill={s.color} />
      ))}
    </svg>
  );
}

// --- MacBook pill: outer width fixed, content pinned to the notch's edges ---
// Mirrors NotchV6 macbook mode from notch_v6_locked.jsx but self-contained.
function MacbookPreviewPill({ mode = 'running', right, rightW, height = 32, physicalNotchWidth = 180 }) {
  const r = height / 2;
  const halfReserve = 44;
  const outer = halfReserve + physicalNotchWidth + halfReserve;
  const padL = r, padR = r;
  const glyphW = 24;
  const glyphX = padL;
  const rightX = outer - padR - rightW;

  return (
    <div style={{ width: outer, height, position: 'relative' }}>
      <svg width={outer} height={height} viewBox={`0 0 ${outer} ${height}`}
        style={{ display: 'block', position: 'absolute', inset: 0 }} preserveAspectRatio="none">
        <path d={`M 0 0 H ${outer} V ${height - r} A ${r} ${r} 0 0 1 ${outer - r} ${height} H ${r} A ${r} ${r} 0 0 1 0 ${height - r} Z`} fill={V6_PAPER} />
      </svg>
      <div style={{ position: 'absolute', top: (height - 24) / 2, left: glyphX, width: glyphW, height: 24 }}>
        <svg width={glyphW} height={24} viewBox={`0 0 ${glyphW} 24`} style={{ overflow: 'visible' }}>
          <UnifiedBars mode={mode} />
        </svg>
      </div>
      {right && (
        <div style={{
          position: 'absolute', top: (height - 24) / 2, left: rightX,
          width: rightW, height: 24,
          display: 'flex', alignItems: 'center', justifyContent: 'flex-start',
        }}>{right}</div>
      )}
    </div>
  );
}

// --- A minimal notch pill that accepts arbitrary JSX for its right slot ----
function PreviewPill({ mode = 'running', label = 'Claude · editing', right, rightW, height = 32, minWidth = 70 }) {
  const r = height / 2;
  const glyphW = 24;
  const labelW = label ? label.length * 6.8 + 10 : 0;
  const rightFullW = right ? rightW + 14 : 0;
  const padL = r, padR = r;
  const intrinsicW = padL + glyphW + labelW + rightFullW + padR;
  const pillW = Math.max(minWidth, intrinsicW);

  const glyphX = padL;
  const labelX = glyphX + glyphW + 6;
  const rightX = pillW - padR - rightW;

  return (
    <div style={{ width: pillW, height, position: 'relative' }}>
      <svg width={pillW} height={height} viewBox={`0 0 ${pillW} ${height}`} style={{ display: 'block', position: 'absolute', inset: 0 }}>
        <path d={`M 0 0 H ${pillW} V ${height - r} A ${r} ${r} 0 0 1 ${pillW - r} ${height} H ${r} A ${r} ${r} 0 0 1 0 ${height - r} Z`} fill={V6_PAPER} />
      </svg>
      <div style={{ position: 'absolute', top: (height - 24) / 2, left: glyphX, width: glyphW, height: 24 }}>
        <svg width={glyphW} height={24} viewBox={`0 0 ${glyphW} 24`} style={{ overflow: 'visible' }}>
          <UnifiedBars mode={mode} />
        </svg>
      </div>
      {label && (
        <div style={{
          position: 'absolute', top: 0, left: labelX, height,
          display: 'flex', alignItems: 'center',
          color: V6_INK, fontFamily: "'JetBrains Mono', monospace",
          fontSize: 11.5, fontWeight: 500, whiteSpace: 'nowrap',
        }}>{label}</div>
      )}
      {right && (
        <div style={{
          position: 'absolute', top: (height - 24) / 2, left: rightX,
          width: rightW, height: 24,
          display: 'flex', alignItems: 'center', justifyContent: 'flex-start',
        }}>{right}</div>
      )}
    </div>
  );
}

// --- Page sections -----------------------------------------------------------

const VARIANTS = [
  {
    id: 'v1', title: 'V1 · Dense Grid',
    summary: '8×8 square tiles, radius 1.5, gap 2. Running = solid color · Idle = same color at 22% alpha · Waiting = solid + 1px cream outline + opacity pulse.',
    note: '最直白的"方块网格"。每个 agent 一个可辨认色块,状态通过亮度 + 外框切换。信息密度中等,tile 大到不会看作 LED 或圆点。',
  },
  {
    id: 'v2', title: 'V2 · Tight Grid',
    summary: '5×5 square tiles, radius 1, gap 1.5. Waiting adds a scaling halo stroke in the same color (pulse 1.4s).',
    note: '紧凑版本,适合常态 6-8 个会话。Waiting 的光环放大-淡出,让需关注的那块"呼吸"出格,但不靠白色环。',
  },
  {
    id: 'v3', title: 'V3 · Framed Matrix',
    summary: 'Persistent 2×4 skeleton of hairline frames. Running = filled · Idle = color stroke only · Waiting = filled + outer color glow pulse. Empty slots keep showing a dim frame.',
    note: '始终显示矩阵骨架,单个 agent 也能看出"一个槽位被占"。骨架让它一眼像 UI 控件,不像指示灯。状态三档语义最清晰。',
  },
  {
    id: 'v4', title: 'V4 · Pixel Panel',
    summary: '4×4 micro-cells with a subtle outer panel frame. Running = color · Idle = color at 28% · Waiting = blink (0.9s). Total footprint ≈ 23×12pt.',
    note: '最彻底脱离"圆点"语言,像 MacBook 键盘上的 Caps Lock 指示或 Touch Bar 微缩阵列。适合极窄的 notch 预算。代价:小面板辨识度依赖位置记忆。',
  },
];

const STATE_CYCLE = ['all-running', 'mixed', 'one-waiting', 'all-waiting'];
const STATE_LABELS = {
  'all-running': 'All running',
  'mixed': 'Mixed (idle + 1 waiting)',
  'one-waiting': 'One waiting',
  'all-waiting': 'All waiting',
};

function VariantPanel({ variant, sharedLayout }) {
  const Grid = GRID_COMPONENTS[variant.id];
  const [count, setCount] = useState_ag(5);
  const [pattern, setPattern] = useState_ag('mixed');
  const [localLayout, setLocalLayout] = useState_ag(sharedLayout);
  useEffect_ag(() => { setLocalLayout(sharedLayout); }, [sharedLayout]);

  const sessions = buildScenario(count, pattern);
  const rightW = rightWidthFor(variant.id, sessions, localLayout);

  return (
    <section className="variant-panel">
      <header className="variant-head">
        <div className="variant-title">{variant.title}</div>
        <div className="variant-sub">{variant.summary}</div>
      </header>

      {/* Matrix preview at 8× scale so rules are readable */}
      <div className="variant-stage">
        <div className="stage-label">Matrix · 8× zoom</div>
        <div className="stage-plate">
          <Grid sessions={sessions} layout={localLayout} displayScale={8} />
        </div>
      </div>

      {/* Integration: inside a real v6 pill (external layout) */}
      <div className="variant-stage">
        <div className="stage-label">In context · external pill · 1×</div>
        <div className="stage-plate plate-island">
          <PreviewPill
            mode={sessions.some(s => s.state === 'waiting') ? 'waiting' : 'running'}
            label={count === 1 ? `${sessions[0].name} · editing` : `Running ${sessions.filter(s => s.state === 'running').length}`}
            right={<Grid sessions={sessions} layout={localLayout} />}
            rightW={rightW}
          />
        </div>
      </div>

      {/* Atlas — every n from 1 to 10 so the rhythm is legible */}
      <div className="variant-stage">
        <div className="stage-label">Atlas · n = 1 … 10 · layout = {localLayout}</div>
        <div className="count-strip count-strip-10">
          {[1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map(n => (
            <div key={n} className="count-cell">
              <div className="count-svg-wrap">
                <Grid sessions={buildScenario(n, pattern)} layout={localLayout} displayScale={3.5} />
              </div>
              <div className="count-lbl">n={n}</div>
            </div>
          ))}
        </div>
      </div>

      <div className="variant-controls">
        <div className="ctrl-row">
          <span className="ctrl-lbl">count</span>
          {[1, 2, 3, 4, 5, 6, 7, 8, 10].map(n => (
            <button key={n} className={count === n ? 'on' : ''} onClick={() => setCount(n)}>{n}</button>
          ))}
        </div>
        <div className="ctrl-row">
          <span className="ctrl-lbl">state</span>
          {STATE_CYCLE.map(p => (
            <button key={p} className={pattern === p ? 'on' : ''} onClick={() => setPattern(p)}>{STATE_LABELS[p]}</button>
          ))}
        </div>
        <div className="ctrl-row">
          <span className="ctrl-lbl">layout</span>
          {['balanced', 'wrap'].map(l => (
            <button key={l} className={localLayout === l ? 'on' : ''} onClick={() => setLocalLayout(l)}>{l}</button>
          ))}
        </div>
      </div>

      <div className="variant-note">{variant.note}</div>
    </section>
  );
}

function BaselineSection() {
  const [count, setCount] = useState_ag(4);
  const sessions = buildScenario(count, 'all-running');
  const rightW = count * 7 + Math.max(0, count - 1) * 4;
  return (
    <section className="variant-panel variant-baseline">
      <header className="variant-head">
        <div className="variant-title">V0 · Current implementation (baseline)</div>
        <div className="variant-sub">Row of 7pt filled circles. Problem: Gemini green (<code>#42e86b</code>) and Claude orange (<code>#d97742</code>) read as macOS camera / mic privacy indicators in the same screen region.</div>
      </header>
      <div className="variant-stage">
        <div className="stage-label">Matrix · 8× zoom</div>
        <div className="stage-plate">
          <div style={{ transform: 'scale(8)', transformOrigin: 'center', padding: '24px 48px' }}>
            <AgentsBaselineDots sessions={sessions} />
          </div>
        </div>
      </div>
      <div className="variant-stage">
        <div className="stage-label">In context · external pill · 1×</div>
        <div className="stage-plate plate-island">
          <PreviewPill mode="running" label={`Running ${count}`} right={<AgentsBaselineDots sessions={sessions} />} rightW={rightW} />
        </div>
      </div>
      <div className="variant-controls">
        <div className="ctrl-row">
          <span className="ctrl-lbl">count</span>
          {[1, 2, 3, 4, 5, 6].map(n => (
            <button key={n} className={count === n ? 'on' : ''} onClick={() => setCount(n)}>{n}</button>
          ))}
        </div>
      </div>
    </section>
  );
}

function SideBySide({ sharedLayout }) {
  const [count, setCount] = useState_ag(5);
  const [pattern, setPattern] = useState_ag('mixed');
  const [localLayout, setLocalLayout] = useState_ag(sharedLayout);
  useEffect_ag(() => { setLocalLayout(sharedLayout); }, [sharedLayout]);
  const sessions = buildScenario(count, pattern);
  return (
    <section className="sbs-section">
      <header className="variant-head">
        <div className="variant-title">Side-by-side · same sessions in all 4 variants</div>
        <div className="variant-sub">同一组 session 数据在四个方案下的对比(1× 真实尺寸)。state 统一控制。</div>
      </header>

      <div className="sbs-grid">
        {/* Baseline */}
        <div className="sbs-cell sbs-cell-baseline">
          <div className="sbs-lbl">V0 · baseline dots</div>
          <div className="sbs-plate">
            <PreviewPill mode="running" label={`Running ${count}`}
              right={<AgentsBaselineDots sessions={sessions} />}
              rightW={count * 7 + Math.max(0, count - 1) * 4} />
          </div>
        </div>
        {VARIANTS.map(v => {
          const Grid = GRID_COMPONENTS[v.id];
          return (
            <div key={v.id} className="sbs-cell">
              <div className="sbs-lbl">{v.title}</div>
              <div className="sbs-plate">
                <PreviewPill
                  mode={sessions.some(s => s.state === 'waiting') ? 'waiting' : 'running'}
                  label={`Running ${sessions.filter(s => s.state === 'running').length}`}
                  right={<Grid sessions={sessions} layout={localLayout} />}
                  rightW={rightWidthFor(v.id, sessions, localLayout)} />
              </div>
            </div>
          );
        })}
      </div>

      <div className="variant-controls">
        <div className="ctrl-row">
          <span className="ctrl-lbl">count</span>
          {[1, 2, 3, 4, 5, 6, 7, 8, 10].map(n => (
            <button key={n} className={count === n ? 'on' : ''} onClick={() => setCount(n)}>{n}</button>
          ))}
        </div>
        <div className="ctrl-row">
          <span className="ctrl-lbl">state</span>
          {STATE_CYCLE.map(p => (
            <button key={p} className={pattern === p ? 'on' : ''} onClick={() => setPattern(p)}>{STATE_LABELS[p]}</button>
          ))}
        </div>
        <div className="ctrl-row">
          <span className="ctrl-lbl">layout</span>
          {['balanced', 'wrap'].map(l => (
            <button key={l} className={localLayout === l ? 'on' : ''} onClick={() => setLocalLayout(l)}>{l}</button>
          ))}
        </div>
      </div>
    </section>
  );
}

// --- Same-agent canonical scenario: 1..N Claude sessions, all the same color.
// Users typically pick one primary agent (e.g. Claude Code) and open 1–8 of it.
// So the right-slot will almost always be a uniform orange field — the per-cell
// *state* (running / idle / waiting) becomes the whole story.
function SameAgentScenario() {
  const CLAUDE = '#d97742';
  const [count, setCount] = useState_ag(1);
  const [phase, setPhase] = useState_ag(0);  // drives auto-cycling states
  const [auto, setAuto] = useState_ag(true);

  // Phase cycle, uses count when choosing which cell to highlight:
  // 0 = all running · 1 = one waiting · 2 = one idle (dim) · 3 = mixed (idle + waiting)
  const PHASES = ['all-running', 'one-waiting', 'one-idle', 'mixed'];
  const phaseKey = PHASES[phase % PHASES.length];

  useEffect_ag(() => {
    if (!auto) return;
    const t = setInterval(() => setPhase(p => (p + 1) % PHASES.length), 1800);
    return () => clearInterval(t);
  }, [auto]);

  // Build Claude-only sessions with the requested state pattern.
  const sessions = React.useMemo(() => {
    const arr = Array.from({ length: count }, () => ({ color: CLAUDE, state: 'running', name: 'Claude' }));
    const waitIdx = Math.min(count - 1, count >= 3 ? 2 : 0);
    const idleIdx = Math.max(0, count - 1);
    if (phaseKey === 'one-waiting' && count >= 1) arr[waitIdx].state = 'waiting';
    if (phaseKey === 'one-idle' && count >= 1) arr[idleIdx].state = 'idle';
    if (phaseKey === 'mixed') {
      // Alternate idle, one waiting near the middle.
      for (let i = 0; i < count; i++) {
        if (i % 3 === 1) arr[i].state = 'idle';
      }
      if (count >= 2) arr[Math.min(count - 1, Math.floor(count / 2))].state = 'waiting';
    }
    return arr;
  }, [count, phaseKey]);

  const hasWaiting = sessions.some(s => s.state === 'waiting');
  const runningCount = sessions.filter(s => s.state === 'running').length;
  const pillMode = hasWaiting ? 'waiting' : (runningCount > 0 ? 'running' : 'idle');
  const label = (() => {
    if (pillMode === 'idle') return null;
    if (hasWaiting) return count === 1 ? 'Permission needed' : `${runningCount} running · 1 waiting`;
    return count === 1 ? 'Claude · editing' : `Claude × ${count} · running`;
  })();
  const rightW = rightWidthFor('v1', sessions, 'balanced');

  const frameW = 460;
  const frameH = 44;
  const physicalNotchW = 180;

  const gridRight = <AgentsGridV1 sessions={sessions} layout="balanced" waitingStyle="breath" />;

  const noteFor = {
    'all-running': `• 全部 ${count} 个 Claude 会话都在跑 — 所有方块实心橙色,布局 = ${JSON.stringify(balancedRows(count))}。`,
    'one-waiting': `• 有一个会话需要你回应 — 对应那格 opacity 0.35↔1 呼吸,其他保持实色。左侧 UnifiedBars 切到 pause。`,
    'one-idle': `• 有一个会话闲置(或刚 done) — 对应那格变成 22% alpha 的暗色,其他保持实色。`,
    'mixed': '• 混合:部分 running (实色) + 部分 idle (暗) + 一个 waiting (呼吸)。复杂但仍只有 "橙 / 暗橙 / 呼吸橙" 三档。',
  }[phaseKey];

  return (
    <div className="variant-panel single-agent-panel">
      <header className="variant-head">
        <div className="variant-title">V1a · Single-brand, 1–8 sessions</div>
        <div className="variant-sub">典型用户只用一种 agent(如 Claude Code),会同时开 1-8 个会话 — 全部同色。右槽只剩"橙/暗橙/呼吸橙"三档,由 balanced 布局塑造出形状。</div>
      </header>

      <div className="scenario-row">
        {/* External display */}
        <div className="scenario-stage">
          <div className="stage-label">External display · pill 宽度随内容流动</div>
          <div style={{
            width: frameW, height: frameH, borderRadius: 8,
            background: 'linear-gradient(180deg, #2a2a30, #1f1f24)',
            position: 'relative', overflow: 'hidden',
            border: '1px solid rgba(255,255,255,0.06)',
          }}>
            <div style={{
              position: 'absolute', top: 0, left: '50%', transform: 'translateX(-50%)',
              transition: 'width 0.45s cubic-bezier(.4,0,.2,1)',
            }}>
              <PreviewPill mode={pillMode} label={label} right={gridRight} rightW={rightW} />
            </div>
          </div>
        </div>

        {/* MacBook notched */}
        <div className="scenario-stage">
          <div className="stage-label">MacBook · pill 外宽锁定,包住物理刘海</div>
          <div style={{
            width: frameW, height: frameH, borderRadius: 8,
            background: 'linear-gradient(180deg, #2a2a30, #1f1f24)',
            position: 'relative', overflow: 'hidden',
            border: '1px solid rgba(255,255,255,0.06)',
          }}>
            <svg width={physicalNotchW} height={32} viewBox={`0 0 ${physicalNotchW} 32`}
              style={{ position: 'absolute', top: 0, left: '50%', transform: 'translateX(-50%)', pointerEvents: 'none', zIndex: 1 }}>
              <path d={`M 0 0 H ${physicalNotchW} V 16 A 16 16 0 0 1 ${physicalNotchW - 16} 32 H 16 A 16 16 0 0 1 0 16 Z`} fill="#000" />
            </svg>
            <div style={{ position: 'absolute', top: 0, left: '50%', transform: 'translateX(-50%)', zIndex: 2 }}>
              <MacbookPreviewPill mode={pillMode} right={gridRight} rightW={rightW} physicalNotchWidth={physicalNotchW} />
            </div>
          </div>
        </div>
      </div>

      <div className="scenario-note">{noteFor}</div>

      <div className="variant-controls">
        <div className="ctrl-row">
          <span className="ctrl-lbl">count</span>
          {[1, 2, 3, 4, 5, 6, 7, 8].map(n => (
            <button key={n} className={count === n ? 'on' : ''} onClick={() => setCount(n)}>{n}</button>
          ))}
        </div>
        <div className="ctrl-row">
          <span className="ctrl-lbl">phase</span>
          {PHASES.map((p, i) => (
            <button key={p} className={phaseKey === p ? 'on' : ''} onClick={() => { setAuto(false); setPhase(i); }}>{p}</button>
          ))}
          <button className={auto ? 'on' : ''} onClick={() => setAuto(a => !a)}>{auto ? 'auto ✓' : 'auto'}</button>
        </div>
      </div>
    </div>
  );
}

const V1_WAITING_VARIANTS = [
  { id: 'breath', title: 'V1a · Breath', note: '最简。仅 opacity 0.35 ↔ 1 呼吸。没有任何额外装饰,靠亮度节奏提示。' },
  { id: 'halo',   title: 'V1b · Soft Halo', note: '同色高斯模糊光晕淡入淡出,无硬边框。像色块在"发光"。对邻居影响最小。' },
  { id: 'scale',  title: 'V1c · Scale Pulse', note: '方块本身 0.82 ↔ 1.05 缩放 + 亮度脉冲。生命感最强,但要注意别让其他格子被"顶移"。' },
  { id: 'tick',   title: 'V1d · Center Tick', note: '格子中央一个反色(cream)小圆点脉冲。语义最明确——"这个在等你回应"。' },
  { id: 'edge',   title: 'V1e · Top Edge', note: '格子顶部一条 cream highlight bar 脉冲。类似 iOS 的系统徽标 / "未读"提示。' },
  { id: 'outline', title: 'V0 · White Outline (legacy)', note: '当前方案。白色 1px 外描边 — 太显眼,和整体极简语言冲突。保留作对照。' },
];

function V1WaitingVariantsPanel() {
  const [count, setCount] = useState_ag(5);
  const sessions = buildScenario(count, 'one-waiting');
  return (
    <div className="variant-panel">
      <header className="variant-head">
        <div className="variant-title">V1 · Waiting 处理候选</div>
        <div className="variant-sub">基于 V1 Dense Grid(8×8 方块),5 种 waiting 表达方式比较。running / idle 完全相同,只有 waiting 那格渲染不同。</div>
      </header>

      <div className="variant-stage">
        <div className="stage-label">Matrix · 8× zoom</div>
        <div className="v1wait-grid">
          {V1_WAITING_VARIANTS.map(v => (
            <div key={v.id} className="v1wait-cell">
              <div className="v1wait-plate">
                <AgentsGridV1 sessions={sessions} layout="balanced" displayScale={8} waitingStyle={v.id} />
              </div>
              <div className="v1wait-title">{v.title}</div>
              <div className="v1wait-note">{v.note}</div>
            </div>
          ))}
        </div>
      </div>

      <div className="variant-stage">
        <div className="stage-label">In context · external pill · 1× · n = {count}</div>
        <div className="v1wait-plate-row">
          {V1_WAITING_VARIANTS.map(v => (
            <div key={v.id} className="v1wait-incontext">
              <div className="v1wait-ic-lbl">{v.title.replace(/^V[0-9a-z]+ · /, '')}</div>
              <div className="sbs-plate">
                <PreviewPill mode="waiting" label={`${sessions.filter(s => s.state === 'running').length} running · 1 waiting`}
                  right={<AgentsGridV1 sessions={sessions} layout="balanced" waitingStyle={v.id} />}
                  rightW={rightWidthFor('v1', sessions, 'balanced')} />
              </div>
            </div>
          ))}
        </div>
      </div>

      <div className="variant-controls">
        <div className="ctrl-row">
          <span className="ctrl-lbl">count</span>
          {[1, 2, 3, 4, 5, 6, 7, 8, 10].map(n => (
            <button key={n} className={count === n ? 'on' : ''} onClick={() => setCount(n)}>{n}</button>
          ))}
        </div>
      </div>
    </div>
  );
}

function LayoutAtlas() {
  // Show the balanced layout's shape for every n from 1..10 using V1 geometry
  // at a readable display scale.
  const mkSess = (n) => AGENT_PALETTE.slice(0, n).map(a => ({ color: a.color, state: 'running' }));
  const labelFor = (n) => {
    if (n <= 9) return JSON.stringify(balancedRows(n));
    return `[4,4] · +${n - 7}`;
  };
  return (
    <div className="atlas-grid">
      {[1,2,3,4,5,6,7,8,9,10].map(n => (
        <div key={n} className="atlas-cell">
          <div className="atlas-svg-wrap">
            <AgentsGridV1 sessions={mkSess(n)} layout="balanced" displayScale={6} />
          </div>
          <div className="atlas-lbl">
            <span className="atlas-n">n={n}</span>
            <span className="atlas-rows">{labelFor(n)}</span>
          </div>
        </div>
      ))}
    </div>
  );
}

function AgentsGridShowcase() {
  const [sharedLayout, setSharedLayout] = useState_ag('balanced');
  return (
    <div className="app v3 ag-app">
      <header className="topbar">
        <div className="brand"><span className="dot-v3" /><span>Open Island · v6 — agents grid redesign</span></div>
        <span className="meta mono">// right-slot square-matrix exploration</span>
        <div className="spacer" />
        <div className="ctrl-row" style={{ gap: 4 }}>
          <span className="ctrl-lbl" style={{ minWidth: 0 }}>global layout</span>
          {['balanced', 'wrap'].map(l => (
            <button key={l} className={sharedLayout === l ? 'on' : ''} onClick={() => setSharedLayout(l)}>{l}</button>
          ))}
        </div>
      </header>

      <main className="main main-v3 ag-main">
        <section className="section">
          <div className="section-head">
            <h2>Why redesign</h2>
            <span className="tag mono">// problem framing</span>
            <div className="line" />
          </div>
          <div className="assumption" style={{ display: 'grid', gap: 8 }}>
            <div>❌ 当前 agents 插槽是一排 <b>7pt 彩色实心圆</b>(<code>Circle().fill(color)</code>)。</div>
            <div>❌ 品牌色 <b>Gemini <code>#42e86b</code> ≈ macOS 摄像头指示绿</b>,<b>Claude <code>#d97742</code> ≈ 麦克风指示橙</b>,同时 pill 又长在 notch 区域。用户第一反应会是"谁在偷开我的摄像头 / 麦克风?"。</div>
            <div>✅ 目标:改成 <b>方形矩阵</b>(每行 2-4 格),格子数 = session 数,色保留品牌识别,但形态完全离开"圆点"语言。三种状态:<b>running</b>(亮) / <b>idle</b>(暗) / <b>waiting</b>(需关注)。</div>
          </div>
        </section>

        <section className="section">
          <div className="section-head">
            <h2>01 · Baseline — 当前方案</h2>
            <div className="line" />
          </div>
          <BaselineSection />
        </section>

        <section className="section">
          <div className="section-head">
            <h2>02 · Locked — V1a · 同品牌多会话典型场景</h2>
            <span className="tag mono">// the 80% case</span>
            <div className="line" />
          </div>
          <div className="assumption" style={{ marginBottom: 14 }}>
            典型用户只用一种 agent(比如只用 Claude Code),但会同时开 <b>1-8</b> 个会话。右槽全部同色 — 信息靠每格的<b>状态</b>(running 实色 / idle 暗色 / waiting 呼吸)和 balanced 布局塑造的<b>形状</b>来传递。<br />切 count 看不同数量,切 phase 或等 auto 看不同状态组合。
          </div>
          <SameAgentScenario />
        </section>

        <section className="section">
          <div className="section-head">
            <h2>03 · Balanced-layout atlas</h2>
            <span className="tag mono">// row sizes per n</span>
            <div className="line" />
          </div>
          <div className="assumption" style={{ marginBottom: 14 }}>
            用户建议:与其"4 列自动换行",不如对 n = 1..9 <b>查表</b>(每行居中对齐):<br />
            <code>1→[1]</code> · <code>2→[2]</code> · <code>3→[3]</code> · <code>4→[2,2]</code> · <code>5→[3,2]</code> · <code>6→[3,3]</code> · <code>7→[4,3]</code> · <code>8→[4,4]</code> · <code>9→[3,3,3]</code> · <code>10+→[4,4] 末位 +N</code>。<br />
            每一档矩阵形状都被专门调过,1-8 恒定 2 行,9 时 cell 略小以塞进 3 行,10+ 折叠成 overflow。整体"色块"的轮廓始终是对称的。
          </div>
          <LayoutAtlas />
        </section>

        <section className="section">
          <div className="section-head">
            <h2>04 · V1 waiting 处理候选</h2>
            <span className="tag mono">// locked on V1 Dense Grid</span>
            <div className="line" />
          </div>
          <div className="assumption" style={{ marginBottom: 14 }}>
            视觉语言已锁定为 <b>V1 Dense Grid</b>(8×8 方块)。下面比较 5 种 <b>waiting</b> 表达方式 — 都<b>不使用</b>白色硬描边。
          </div>
          <V1WaitingVariantsPanel />
        </section>

        <section className="section">
          <div className="section-head">
            <h2>05 · Other visual-language variants (legacy)</h2>
            <span className="tag mono">// V2 / V3 / V4 for reference only</span>
            <div className="line" />
          </div>
          <div className="variants-list">
            {VARIANTS.map(v => <VariantPanel key={v.id} variant={v} sharedLayout={sharedLayout} />)}
          </div>
        </section>

        <section className="section">
          <div className="section-head">
            <h2>06 · Side-by-side (all visual languages)</h2>
            <div className="line" />
          </div>
          <SideBySide sharedLayout={sharedLayout} />
        </section>

        <section className="section">
          <div className="section-head">
            <h2>07 · Decision checklist</h2>
            <div className="line" />
          </div>
          <div className="assumption" style={{ display: 'grid', gap: 6 }}>
            <div>• <b>layout:</b> balanced(查表) vs wrap(4 列自动换行)。balanced 让每个 n 都"完美居中",wrap 保持"矩阵轮廓恒定"。</div>
            <div>• 哪个视觉语言在 <b>1 个 session</b> 时仍然有存在感?(V3 的骨架最强,V4 的像素最弱)</div>
            <div>• 哪个视觉语言在 <b>6-8 个 session</b> 时最好读?(V2 密度最高 / V3 骨架辅助)</div>
            <div>• waiting 的醒目程度要不要更强?(V1 白色描边最刺眼,V3 外发光最"系统"感,V4 闪烁最直接)</div>
            <div>• pill 宽度预算:balanced 下宽度会随 n 变化(1 格时最窄);wrap 下宽度恒定。</div>
          </div>
        </section>
      </main>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<AgentsGridShowcase />);
