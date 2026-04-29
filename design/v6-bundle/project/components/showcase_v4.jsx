// v4 showcase — Pill variations + Horizon notch strengtheners.
const { useState: useState_v4 } = React;

function V4Showcase() {
  const [tone, setTone] = useState_v4('paper');

  const pills = [
    { id: 'p1', name: 'P1 · Seam',     sub: '中线细缝。像被轻轻划开 — "open" 的暗示,克制到不露痕迹。',          Mark: P1_Seam,     App: AppIcon_P1 },
    { id: 'p2', name: 'P2 · Dot',      sub: '左端一个反白小圆。读作"光标 / 信号源",也像 Dynamic Island 的相机孔。', Mark: P2_Dot,      App: AppIcon_P2 },
    { id: 'p3', name: 'P3 · Tick',     sub: '左侧一个 checkmark — 完成 / agent 跑完了。',                     Mark: P3_Tick,     App: AppIcon_P3 },
    { id: 'p4', name: 'P4 · Chevron',  sub: '左侧 chevron — "run / forward / prompt"。Linear 味道。',          Mark: P4_Chevron,  App: AppIcon_P4 },
    { id: 'p5', name: 'P5 · Ring',     sub: '只是一个药丸轮廓。读作"环礁 / 岛"。',                              Mark: P5_Ring,     App: AppIcon_P5 },
    { id: 'p6', name: 'P6 · Split',    sub: '左实右空 — 状态二象性。静态但有张力。',                           Mark: P6_Split,    App: AppIcon_P6 },
    { id: 'p7', name: 'P7 · Bite',     sub: '底边咬出一个小 notch。药丸本身就是 notch 的拓扑。',                Mark: P7_Bite,     App: AppIcon_P7 },
    { id: 'p8', name: 'P8 · Under',    sub: '药丸 + 下方短下划线。terminal prompt 的极简引用,对称居中。',      Mark: P8_Under,    App: AppIcon_P8 },
  ];

  const horizons = [
    { id: 'h1', name: 'H1 · Notch-out',   sub: '上层药丸底部咬出一个 notch → 直接把 notch 画出来。',               Mark: H1_NotchOut,   App: AppIcon_H1 },
    { id: 'h2', name: 'H2 · Drop-pill',   sub: '上层 pill 垂下一条连接杆到下方小岛 pill。读作"notch 展开"。',      Mark: H2_DropPill,   App: AppIcon_H2 },
    { id: 'h3', name: 'H3 · Pill-in-pill',sub: '药丸轮廓里嵌一个实心小药丸。远近两个 notch,或 notch+icon。',       Mark: H3_PillInPill, App: AppIcon_H3 },
  ];

  React.useEffect(() => {
    const handler = (e) => {
      const panel = document.getElementById('tweaks-v4');
      if (!panel) return;
      if (e.data?.type === '__activate_edit_mode') panel.style.display = 'block';
      if (e.data?.type === '__deactivate_edit_mode') panel.style.display = 'none';
    };
    window.addEventListener('message', handler);
    window.parent.postMessage({ type: '__edit_mode_available' }, '*');
    return () => window.removeEventListener('message', handler);
  }, []);

  const Section = ({ title, tag, items, tone }) => (
    <section className="section">
      <div className="section-head">
        <h2>{title}</h2>
        <span className="tag mono">{tag}</span>
        <div className="line" />
      </div>

      {/* Marks row */}
      <div className="mark-grid">
        {items.map(v => (
          <div key={v.id} className="mark-card">
            <div className="mark-plate" data-tone={tone}>
              <v.Mark size={160} tone={tone} />
            </div>
            <div className="mark-meta">
              <div className="mark-name">{v.name}</div>
              <div className="mark-sub">{v.sub}</div>
            </div>
          </div>
        ))}
      </div>

      {/* App icon row */}
      <div className="app-strip">
        {items.map(v => (
          <div key={v.id} className="app-cell">
            <v.App size={160} tone={tone} />
            <div className="app-label">{v.name.split(' · ')[0]}</div>
          </div>
        ))}
      </div>

      {/* Dock row */}
      <div className="dock-block">
        {items.map(v => (
          <div key={v.id} className="dock-row">
            <div className="dock-name">{v.name.split(' · ')[0]} · {v.name.split(' · ')[1]}</div>
            <div className="dock-sizes">
              {[16, 32, 64, 128].map(sz => (
                <div key={sz} className="dock-wrap">
                  <v.App size={sz} tone={tone} />
                  <span className="mono dock-lbl">{sz}</span>
                </div>
              ))}
            </div>
          </div>
        ))}
      </div>
    </section>
  );

  return (
    <div className="app v3">
      <header className="topbar">
        <div className="brand"><span className="dot-v3" /><span>Open Island · Logo v4</span></div>
        <span className="meta mono">// pill focus · static only · notch-obvious horizons</span>
        <div className="spacer" />
        <span className="chip">tone: {tone}</span>
        <span className="chip">8 pills · 3 horizons</span>
      </header>

      <main className="main main-v3">
        <section className="section">
          <div className="section-head">
            <h2>Feedback from v3 → v4</h2>
            <span className="tag mono">// plan</span>
            <div className="line" />
          </div>
          <div className="assumption" style={{ display: 'grid', gap: 10 }}>
            <div>✅ <b>Pill (M1)</b> 保留核心 — 现在做 <b>8 个克制修饰</b>,每个只加一个元素,保持 pill 的气质。</div>
            <div>✅ <b>Horizon (M3)</b> 保留,但 3 个新变体<b>把 notch 语义明确画出来</b>(底部咬口 / 垂下岛 / pill-in-pill)。</div>
            <div>❌ Drop(圆球在底部)在 app icon 里形成正圆球,确实在 macOS 圆角矩里会显得"飘"和奇怪 — 砍掉。</div>
            <div>❌ Inner Notch / Cursor / O+I — 砍掉。</div>
            <div>🔒 App icon 一律<b>静态</b>。动态只留给 notch 本身。</div>
          </div>
        </section>

        <Section title="01 · Pill modifications" tag="// P1–P8" items={pills} tone={tone} />
        <Section title="02 · Horizon — notch made obvious" tag="// H1–H3" items={horizons} tone={tone} />
      </main>

      <aside className="tweaks" id="tweaks-v4">
        <h3>Tweaks</h3>
        <div className="grp">
          <div className="grp-title">Tone</div>
          <div className="btn-group">
            <button className={tone === 'paper' ? 'on' : ''} onClick={() => setTone('paper')}>paper</button>
            <button className={tone === 'ink' ? 'on' : ''} onClick={() => setTone('ink')}>ink</button>
            <button className={tone === 'bw' ? 'on' : ''} onClick={() => setTone('bw')}>bw</button>
          </div>
          <div className="hint">paper = 暖米纸 · ink = 墨底 · bw = 纯白</div>
        </div>
        <div className="grp">
          <div className="grp-title">How to respond</div>
          <div className="hint" style={{ lineHeight: 1.55 }}>
            给分就行(比如"P2 85, P7 90"),或直接说"P7 + 把咬口做圆一点"、"H2 把下方药丸换成 P2"这种。我会合体或微调。
          </div>
        </div>
      </aside>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<V4Showcase />);
