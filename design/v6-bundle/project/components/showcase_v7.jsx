// v7 showcase — logos derived from rest states I & M.
const { useState: useState_v7 } = React;

function V7Showcase() {
  const [tone, setTone] = useState_v7('paper');

  const pulseLogos = [
    { id: 'beacon',   Mark: Logo_Beacon,   App: window.AppIcon_Beacon,   name: 'L1 · Beacon',   sub: '长横线 + 左侧定位点。I 方案凝固为"信号已就位"。' },
  ];
  const breatheLogos = [
    { id: 'bardot',   Mark: Logo_BarDot,   App: window.AppIcon_BarDot,   name: 'L6 · Bar + Dot',sub: 'M 的粗杠 + I 的定位点 — 两个灵感合体。' },
  ];

  React.useEffect(() => {
    const handler = (e) => {
      const panel = document.getElementById('tweaks-v7');
      if (!panel) return;
      if (e.data?.type === '__activate_edit_mode') panel.style.display = 'block';
      if (e.data?.type === '__deactivate_edit_mode') panel.style.display = 'none';
    };
    window.addEventListener('message', handler);
    window.parent.postMessage({ type: '__edit_mode_available' }, '*');
    return () => window.removeEventListener('message', handler);
  }, []);

  const Row = ({ title, tag, items }) => (
    <section className="section">
      <div className="section-head">
        <h2>{title}</h2>
        <span className="tag mono">{tag}</span>
        <div className="line" />
      </div>
      <div className="logo-grid">
        {items.map(v => (
          <div key={v.id} className="logo-card">
            <div className="logo-plate" data-tone={tone}><v.Mark size={180} tone={tone} /></div>
            <div className="logo-meta"><div className="logo-name">{v.name}</div><div className="logo-sub">{v.sub}</div></div>
          </div>
        ))}
      </div>
      <div className="app-grid-v6" style={{ gridTemplateColumns: `repeat(${items.length}, 1fr)`, marginTop: 16 }}>
        {items.map(v => (
          <div key={v.id} className="app-cell-v6">
            <v.App size={150} tone={tone} />
            <div className="app-label">{v.name.split(' · ')[0]}</div>
          </div>
        ))}
      </div>
      <div style={{ marginTop: 16 }}>
        {items.map(v => (
          <div key={v.id} className="dock-row">
            <div className="dock-name">{v.name.split(' · ')[0]} · {v.name.split(' · ')[1]}</div>
            <div className="dock-sizes">
              {[16,32,64,128].map(sz => (
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
        <div className="brand"><span className="dot-v3" /><span>Open Island · Logo v7 — from I & M</span></div>
        <span className="meta mono">// pulse-line + breathing-bar DNA</span>
        <div className="spacer" />
        <span className="chip">tone: {tone}</span>
      </header>

      <main className="main main-v3">
        <section className="section">
          <div className="section-head">
            <h2>Thesis</h2>
            <span className="tag mono">// v7</span>
            <div className="line" />
          </div>
          <div className="assumption" style={{ display: 'grid', gap: 10 }}>
            <div>Rest state 保留 <b>I · Pulse line</b>(长线 + 游走亮点)和 <b>M · Breathing bar</b>(呼吸粗杠)作为品牌动效。</div>
            <div>Logo 是这些动效的 <b>静止快照</b>。核心元素:notch 形轮廓 · 内部横线 / 横杠 / 点 — 无字符、无符号、无装饰。</div>
            <div>6 个横版 mark + 2 个专为 app icon 做的高比例 mark + 一套 top-anchored 变体。</div>
          </div>
        </section>

        <Row title="01 · L1 · Beacon" tag="// line + dot" items={pulseLogos} />
        <Row title="02 · L6 · Bar + Dot" tag="// bar + dot" items={breatheLogos} />

        <section className="section">
          <div className="section-head">
            <h2>03 · Head-to-head — larger</h2>
            <span className="tag mono">// compare</span>
            <div className="line" />
          </div>
          <div className="logo-grid">
            <div className="logo-card">
              <div className="logo-plate" data-tone={tone} style={{ padding: '80px 30px' }}><Logo_Beacon size={260} tone={tone} /></div>
              <div className="logo-meta"><div className="logo-name">L1 · Beacon</div><div className="logo-sub">细线贯穿 + 一枚定位点。更"通讯 / 信号 / 地图标记"。</div></div>
            </div>
            <div className="logo-card">
              <div className="logo-plate" data-tone={tone} style={{ padding: '80px 30px' }}><Logo_BarDot size={260} tone={tone} /></div>
              <div className="logo-meta"><div className="logo-name">L6 · Bar + Dot</div><div className="logo-sub">粗杠 + 尾点。更"物体感 / 存在感",质量更重。</div></div>
            </div>
          </div>
        </section>

        <section className="section">
          <div className="section-head">
            <h2>04 · Wordmark lockup</h2>
            <span className="tag mono">// horizontal</span>
            <div className="line" />
          </div>
          <div className="logo-plate" data-tone={tone} style={{ padding: '60px 40px' }}>
            <Logo_WordLockup size={460} tone={tone} mark="beacon" />
          </div>
          <div className="logo-plate" data-tone={tone} style={{ padding: '60px 40px', marginTop: 14 }}>
            <Logo_WordLockup size={460} tone={tone} mark="bardot" />
          </div>
        </section>
      </main>

      <aside className="tweaks" id="tweaks-v7">
        <h3>Tweaks</h3>
        <div className="grp">
          <div className="grp-title">Tone</div>
          <div className="btn-group">
            <button className={tone==='paper'?'on':''} onClick={()=>setTone('paper')}>paper</button>
            <button className={tone==='ink'?'on':''} onClick={()=>setTone('ink')}>ink</button>
            <button className={tone==='bw'?'on':''} onClick={()=>setTone('bw')}>bw</button>
          </div>
        </div>
        <div className="grp">
          <div className="grp-title">Decide</div>
          <div className="hint" style={{ lineHeight: 1.55 }}>
            给分或说"L1 + L8 app icon",我收敛到一组。也可以混搭(e.g. "Beacon 当 logo,Top-anchored bar 当 app icon")。
          </div>
        </div>
      </aside>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<V7Showcase />);
