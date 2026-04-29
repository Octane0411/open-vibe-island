// v6 — Notch as live system, Logo extracted from notch grammar.
const { useState: useState_v6, useEffect: useEffect_v6 } = React;

function TransitionDemo({ idleVariant, waitingVariant }) {
  const [mode, setMode] = useState_v6('idle');
  const [auto, setAuto] = useState_v6(true);
  const order = ['idle', 'running', 'waiting', 'done', 'idle'];
  useEffect_v6(() => {
    if (!auto) return;
    let i = 0;
    const id = setInterval(() => { i = (i + 1) % order.length; setMode(order[i]); }, 2000);
    return () => clearInterval(id);
  }, [auto]);

  const label = { idle: null, running: 'Claude · editing', waiting: 'Permission needed', done: 'Commit pushed' }[mode];
  const right = mode === 'running' ? { type: 'agents', agents: [{ color: '#d97742' }] }
              : mode === 'waiting' ? { type: 'time', txt: '2m' } : null;

  const stageStyle = {
    background: '#1a1a1e', borderRadius: 12, padding: '20px 18px 16px',
    border: '1px solid rgba(255,255,255,0.05)',
    display: 'grid', gap: 14, justifyItems: 'center',
  };
  const captionStyle = { color: '#8b8b92', fontSize: 10.5, letterSpacing: 0.8, textTransform: 'uppercase', fontFamily: 'JetBrains Mono, monospace' };
  const noteStyle = { color: '#6b6b72', fontSize: 11, maxWidth: 300, textAlign: 'center', lineHeight: 1.5 };

  const frameW = 420;
  const frameH = 44;
  const physicalNotchW = 180;

  // Center-anchored wrapper so width grows both ways from center
  const centerWrapStyle = {
    position: 'absolute', top: 0, left: '50%', transform: 'translateX(-50%)',
    transition: 'width 0.45s cubic-bezier(.4,0,.2,1)',
  };

  return (
    <div style={{ display: 'grid', gap: 16 }}>
      <div style={{ display: 'grid', gap: 14, gridTemplateColumns: '1fr 1fr' }}>
        {/* EXTERNAL — pill width grows with content, center-anchored (Dynamic-Island-style) */}
        <div style={stageStyle}>
          <div style={captionStyle}>◦ External display · width = fluid (content-driven)</div>
          <div style={{
            width: frameW, height: frameH, borderRadius: 8,
            background: 'linear-gradient(180deg, #2a2a30, #1f1f24)',
            position: 'relative', overflow: 'hidden',
            border: '1px solid rgba(255,255,255,0.06)',
          }}>
            <div style={centerWrapStyle}>
              <NotchV6 state={mode} label={label} right={right}
                minWidth={70} height={32} />
            </div>
          </div>
          <div style={noteStyle}>Pill 宽度随内容变化 — idle 缩到最小,有 label/right-slot 时向两侧对称展开,黑色边缘平滑过渡。</div>
        </div>

        {/* NOTCHED — same component, minWidth large enough to wrap the physical cutout */}
        <div style={stageStyle}>
          <div style={captionStyle}>◈ MacBook · pill width = 460px (locked · 包住刘海)</div>
          <div style={{
            width: frameW, height: frameH, borderRadius: 8,
            background: 'linear-gradient(180deg, #2a2a30, #1f1f24)',
            position: 'relative', overflow: 'hidden',
            border: '1px solid rgba(255,255,255,0.06)',
          }}>
            {/* Hardware physical notch — real cutout, always present */}
            <svg width={physicalNotchW} height={32} viewBox={`0 0 ${physicalNotchW} 32`}
              style={{ position: 'absolute', top: 0, left: '50%', transform: 'translateX(-50%)', pointerEvents:'none', zIndex: 1 }}>
              <path d={`M 0 0 H ${physicalNotchW} V 16 A 16 16 0 0 1 ${physicalNotchW - 16} 32 H 16 A 16 16 0 0 1 0 16 Z`} fill="#000" />
            </svg>
            <div style={{ ...centerWrapStyle, zIndex: 2 }}>
              <NotchV6 state={mode} label={label} right={right}
                notchWidth={physicalNotchW} height={32} />
            </div>
          </div>
          <div style={noteStyle}>类 Dynamic Island:左右内容贴在物理刘海两侧 · 中间信息由刘海本身承载 · 状态切换时左右不动。</div>
        </div>
      </div>

      <div className="controls mono" style={{ justifyContent: 'center' }}>
        <span style={{ color: '#d97742', marginRight: 6 }}>state:</span>
        {['idle', 'running', 'waiting', 'done'].map(s => (
          <button key={s} className={mode === s ? 'on' : ''} onClick={() => { setAuto(false); setMode(s); }}>{s}</button>
        ))}
        <button className={auto ? 'on' : ''} onClick={() => setAuto(a => !a)}>{auto ? 'auto ✓' : 'auto'}</button>
      </div>
    </div>
  );
}

function V6Showcase() {
  const [tone, setTone] = useState_v6('paper');
  // Locked combo: idle = pause-bars (unified), waiting = pause (unified)
  const idleVariant = 'pause-bars';
  const waitingVariant = 'pause';

  useEffect_v6(() => {
    const handler = (e) => {
      const panel = document.getElementById('tweaks-v6');
      if (!panel) return;
      if (e.data?.type === '__activate_edit_mode') panel.style.display = 'block';
      if (e.data?.type === '__deactivate_edit_mode') panel.style.display = 'none';
    };
    window.addEventListener('message', handler);
    window.parent.postMessage({ type: '__edit_mode_available' }, '*');
    return () => window.removeEventListener('message', handler);
  }, []);

  return (
    <div className="app v3">
      <header className="topbar">
        <div className="brand"><span className="dot-v3" /><span>Open Island · v6 — dynamic notch, extracted logo</span></div>
        <span className="meta mono">// notch = live · logo = signature</span>
        <div className="spacer" />
      </header>

      <main className="main main-v3">
        <section className="section">
          <div className="section-head">
            <h2>Reframe</h2>
            <span className="tag mono">// v5 → v6</span>
            <div className="line" />
          </div>
          <div className="assumption" style={{ display: 'grid', gap: 10 }}>
            <div>✅ <b>Notch 永远是动态的</b>。左 = 当前状态(idle/running/waiting/done),中 = label(session / agent / 消息),右 = 附加信息(session count / agent dots / time-left)。</div>
            <div>✅ <b>Logo 不是 pill+符号</b>,而是直接使用 <b>notch 的形态本身</b>(平顶 + 圆底)作为品牌签名。这样 logo 和 notch 是同一个物体。</div>
            <div>❌ 不再做左侧"固定符号"的 logo。那是 v5 的错误方向。</div>
            <div>❌ <b>不设 error 状态</b>。出错通过 done 的变体 + 展开态来表达。</div>
          </div>
        </section>

        {/* Section 1 — Notch states gallery */}
        <section className="section">
          <div className="section-head">
            <h2>01 · Notch state gallery</h2>
            <span className="tag mono">// 6 states × right-slot variants</span>
            <div className="line" />
          </div>

          <div className="state-grid">
            {[
              { state: 'idle', label: null, right: null, note: 'Rest — Unified bars (3 柱,中柱柔呼吸)' },
              { state: 'running', label: 'Claude · editing', right: { type: 'agents', agents: [{color:'#d97742'}] }, note: 'Running — Unified bars · wave。统一的"进行中"状态。' },
              { state: 'running', label: null, right: { type: 'count', n: 3 }, note: 'Multi-agent compact — wave + count badge。' },
              { state: 'running', label: 'Running 3', right: { type: 'agents', agents: [{color:'#d97742'},{color:'#4aa3df'},{color:'#7a5cff'}] }, note: 'Multi-agent labelled — wave + "Running 3" + agent color stack。' },
              { state: 'spinner', label: 'Building', right: { type: 'time', txt: '1m 24s' }, note: '(可选) Spinner — 留给长时 build / deploy 场景。' },
              { state: 'waiting', label: 'Permission needed', right: { type: 'time', txt: '2m' }, note: 'Waiting — Unified bars · pause(与 running 同源几何)。' },
              { state: 'done', label: 'Commit pushed', right: null, note: 'Tick draws in, holds 2s, notch collapses back to idle。' },
            ].map((cfg, i) => (
              <div key={i} className="state-card">
                <div className="state-stage">
                  <NotchV6 state={cfg.state} label={cfg.label} right={cfg.right}
                    width={cfg.label ? (cfg.right ? 260 : 210) : (cfg.right ? 110 : 70)}
                    height={32} idleVariant={idleVariant} waitingVariant={waitingVariant} />
                </div>
                <div className="state-note">{cfg.note}</div>
              </div>
            ))}
          </div>

          {/* Rest-state comparison — removed. Locked to Unified bars. */}

          {/* State-transition showcase — THE main thing: idle/running/waiting share geometry so they morph smoothly */}
          <div className="section-head" style={{ marginTop: 28 }}>
            <h3 style={{ margin: 0, fontSize: 15 }}>Unified-bars · 状态双向过渡演示</h3>
            <span className="tag mono">// 外接屏:fluid · MacBook:locked 包住刘海</span>
            <div className="line" />
          </div>
          <div className="assumption" style={{ marginBottom: 14 }}>
            <b>外接屏 vs MacBook</b>:<b>外接屏</b>的 pill 宽度随内容流动(idle 最小,有 label/right-slot 时对称展开 — 真正的 Dynamic Island 行为);<b>MacBook</b> 的 pill 外宽固定(必须始终包住中间的物理刘海),左右内容贴刘海两侧,状态切换时左右锚点不动。
          </div>
          <TransitionDemo idleVariant="pause-bars" waitingVariant="pause" />

          {/* Waiting-state备选 — removed. Locked to Pause (unified). */}
        </section>

        {/* Section 3 — Final logo (locked) */}
        <section className="section">
          <div className="section-head">
            <h2>02 · Logo — final</h2>
            <span className="tag mono">// L6 · Bar + Dot · locked</span>
            <div className="line" />
          </div>
          <div className="assumption" style={{ marginBottom: 18 }}>
            <b>L6 · Bar + Dot</b> 已定稿。粗杠 + 尾点:粗杠来自 notch 的 <i>Breathing bar</i>(M),尾点来自 <i>Pulse line</i>(I)的扫描亮点停在终点。Logo 和 notch 的 idle 动效共用同一套几何语言。
          </div>

          <div className="logo-grid" style={{ gridTemplateColumns: '1fr 1fr' }}>
            <div className="logo-card">
              <div className="logo-plate" data-tone={tone} style={{ padding: '70px 30px' }}><Logo_BarDot size={280} tone={tone} /></div>
              <div className="logo-meta"><div className="logo-name">Primary mark</div><div className="logo-sub">主 logo — 平顶圆底 notch 形状 + 反白粗杠 + 反白尾点。</div></div>
            </div>
            <div className="logo-card">
              <div className="logo-plate" data-tone={tone === 'paper' ? 'ink' : 'paper'} style={{ padding: '70px 30px' }}><Logo_BarDot size={280} tone={tone === 'paper' ? 'ink' : 'paper'} /></div>
              <div className="logo-meta"><div className="logo-name">Inverse</div><div className="logo-sub">反色版本 — 深底应用场景。</div></div>
            </div>
          </div>

          <div className="section-head" style={{ marginTop: 32 }}>
            <h3 style={{ margin: 0, fontSize: 16 }}>Wordmark lockup</h3>
            <div className="line" />
          </div>
          <div className="logo-plate" data-tone={tone} style={{ padding: '56px 36px' }}>
            <Logo_WordLockup size={460} tone={tone} mark="bardot" />
          </div>
        </section>

        {/* Section 4 — App icons */}
        <section className="section">
          <div className="section-head">
            <h2>03 · App icon</h2>
            <span className="tag mono">// dock sizes</span>
            <div className="line" />
          </div>
          <div className="app-grid-v6" style={{ gridTemplateColumns: 'repeat(3, 1fr)' }}>
            <div className="app-cell-v6"><AppIcon_BarDot size={150} tone={tone} /><div className="app-label">Bar + Dot</div></div>
            <div className="app-cell-v6"><AppIcon_BarDot size={150} tone={tone === 'paper' ? 'ink' : 'paper'} /><div className="app-label">Inverse</div></div>
            <div className="app-cell-v6"><AppIcon_BarDot size={150} tone="bw" /><div className="app-label">B/W</div></div>
          </div>

          <div className="section-head" style={{ marginTop: 24 }}>
            <h3 style={{ margin: 0, fontSize: 16 }}>Dock sizes</h3>
            <div className="line" />
          </div>
          <div className="dock-row">
            <div className="dock-name">Bar + Dot</div>
            <div className="dock-sizes">
              {[16,32,64,128].map(sz => (
                <div key={sz} className="dock-wrap">
                  <AppIcon_BarDot size={sz} tone={tone} />
                  <span className="mono dock-lbl">{sz}</span>
                </div>
              ))}
            </div>
          </div>
        </section>
      </main>

      <aside className="tweaks" id="tweaks-v6">
        <h3>Tweaks</h3>
        <div className="grp">
          <div className="grp-title">Logo / App icon tone</div>
          <div className="btn-group">
            <button className={tone==='paper'?'on':''} onClick={()=>setTone('paper')}>paper</button>
            <button className={tone==='ink'?'on':''} onClick={()=>setTone('ink')}>ink</button>
            <button className={tone==='bw'?'on':''} onClick={()=>setTone('bw')}>bw</button>
          </div>
        </div>
        <div className="grp">
          <div className="grp-title">Status</div>
          <div className="hint" style={{ lineHeight: 1.55 }}>
            ✅ Logo = <b>L6 · Bar + Dot</b><br />
            ✅ Idle / Running / Waiting = <b>Unified bars</b><br /><br />
            ⏳ 下一步:迭代 done / label / right-slot。
          </div>
        </div>
      </aside>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<V6Showcase />);
