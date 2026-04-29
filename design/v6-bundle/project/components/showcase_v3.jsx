// Focused logo/app-icon exploration page — v3.
// 6 directions, pure black/white + warm paper, macOS-native app icon container.
const { useState } = React;

function V3Showcase() {
  const [tone, setTone] = useState('paper');
  const [mono, setMono] = useState(false);
  const [animated, setAnimated] = useState(true);

  const variants = [
    { id: 'pill',   name: 'M1 · Pure Pill',    sub: '一枚药丸,仅此而已。最克制,离 Ghostty / Figma 最近。', Mark: Mark_Pill,       App: AppIcon_Pill,       aspect: 'wide' },
    { id: 'drop',   name: 'M2 · Pill + Drop',  sub: '药丸 + 下方水滴。静态像符号,动态像信号从 notch 里落下。', Mark: (p)=><Mark_Drop {...p} animated={animated} />,       App: (p)=><AppIcon_Drop {...p} animated={animated} /> },
    { id: 'horizon',name: 'M3 · Stacked Horizon', sub: '两层药丸堆叠 — 远看天际线,近看 notch。', Mark: Mark_Horizon,    App: AppIcon_Horizon },
    { id: 'inner',  name: 'M4 · Inner Notch',  sub: '药丸底部咬出一个小 notch。元符号:notch 吞 notch。', Mark: Mark_InnerNotch, App: AppIcon_InnerNotch, aspect: 'wide' },
    { id: 'cursor', name: 'M5 · Pill + Cursor',sub: '药丸被一条闪烁光标穿过。notch × terminal 的合体。', Mark: (p)=><Mark_Cursor {...p} animated={animated} />,     App: (p)=><AppIcon_Cursor {...p} animated={animated} /> },
    { id: 'oi',     name: 'M6 · O + I Ligature', sub: '环形 O + 竖条 I 的单色组合,既读字母又读形状。', Mark: Mark_OI,         App: AppIcon_OI },
  ];

  // Edit-mode protocol
  React.useEffect(() => {
    const handler = (e) => {
      const panel = document.getElementById('tweaks-v3');
      if (!panel) return;
      if (e.data?.type === '__activate_edit_mode') panel.style.display = 'block';
      if (e.data?.type === '__deactivate_edit_mode') panel.style.display = 'none';
    };
    window.addEventListener('message', handler);
    window.parent.postMessage({ type: '__edit_mode_available' }, '*');
    return () => window.removeEventListener('message', handler);
  }, []);

  // If monochrome override, force tone to 'bw'
  const effTone = mono ? 'bw' : tone;

  return (
    <div className="app v3">
      <header className="topbar">
        <div className="brand"><span className="dot-v3" /><span>Open Island · Logo v3</span></div>
        <span className="meta mono">// 药丸 + notch · 极简 · 纯黑白 / 暖米</span>
        <div className="spacer" />
        <span className="chip">tone: {effTone}</span>
        <span className="chip">6 marks</span>
      </header>

      <main className="main main-v3">
        {/* Intro */}
        <section className="section">
          <div className="section-head">
            <h2>Starting over — 6 marks around the pill</h2>
            <span className="tag mono">// v3</span>
            <div className="line" />
          </div>
          <div className="assumption">
            Locked direction from your answers: <b>药丸 / notch 形本身</b>,极简 1–2 元素,参考 <b>Warp / Ghostty / Linear / Figma</b>,色调 <b>纯黑白 + 暖米</b>,App icon 走 <b>macOS 原生</b> 圆角矩居中构图。这一页把所有不必要的元素全砍掉了。切换右侧 tone 可以在 paper / ink / 纯黑白 之间对比。
          </div>
        </section>

        {/* Mark grid */}
        <section className="section">
          <div className="section-head">
            <h2>01 · Marks</h2>
            <span className="tag mono">// standalone</span>
            <div className="line" />
          </div>
          <div className="mark-grid">
            {variants.map(v => (
              <div key={v.id} className="mark-card">
                <div className="mark-plate" data-tone={effTone}>
                  <v.Mark size={v.aspect === 'wide' ? 160 : 140} tone={effTone} />
                </div>
                <div className="mark-meta">
                  <div className="mark-name">{v.name}</div>
                  <div className="mark-sub">{v.sub}</div>
                </div>
              </div>
            ))}
          </div>
        </section>

        {/* App icons grid */}
        <section className="section">
          <div className="section-head">
            <h2>02 · App icons — macOS squircle</h2>
            <span className="tag mono">// in container</span>
            <div className="line" />
          </div>
          <div className="app-grid">
            {variants.map(v => (
              <div key={v.id} className="app-card">
                <v.App size={200} tone={effTone} />
                <div className="app-label">{v.name.split(' · ')[1]}</div>
              </div>
            ))}
          </div>
        </section>

        {/* Dock sizes */}
        <section className="section">
          <div className="section-head">
            <h2>03 · Dock size comparison</h2>
            <span className="tag mono">// 16 → 256</span>
            <div className="line" />
          </div>
          {variants.map(v => (
            <div key={v.id} className="dock-row">
              <div className="dock-name">{v.name.split(' · ')[1]}</div>
              <div className="dock-sizes">
                {[16, 32, 48, 64, 128, 256].map(sz => (
                  <div key={sz} className="dock-wrap">
                    <v.App size={sz} tone={effTone} />
                    <span className="mono dock-lbl">{sz}</span>
                  </div>
                ))}
              </div>
            </div>
          ))}
        </section>

        {/* Finder plate */}
        <section className="section">
          <div className="section-head">
            <h2>04 · In Finder</h2>
            <span className="tag mono">// on desktop</span>
            <div className="line" />
          </div>
          <div className="finder-plate">
            {variants.map(v => (
              <div key={v.id} className="finder-item">
                <v.App size={88} tone={effTone} />
                <div className="finder-name">Open Island<br /><span className="mono">{v.id}</span></div>
              </div>
            ))}
          </div>
        </section>
      </main>

      <aside className="tweaks" id="tweaks-v3">
        <h3>Tweaks</h3>

        <div className="grp">
          <div className="grp-title">Tone</div>
          <div className="btn-group">
            <button className={!mono && tone === 'paper' ? 'on' : ''} onClick={() => { setMono(false); setTone('paper'); }}>paper</button>
            <button className={!mono && tone === 'ink' ? 'on' : ''} onClick={() => { setMono(false); setTone('ink'); }}>ink</button>
            <button className={mono ? 'on' : ''} onClick={() => setMono(true)}>bw</button>
          </div>
          <div className="hint">paper = 暖米纸 · ink = 墨底 · bw = 纯黑白</div>
        </div>

        <div className="grp">
          <div className="grp-title">Motion</div>
          <div className="btn-group">
            <button className={animated ? 'on' : ''} onClick={() => setAnimated(true)}>on</button>
            <button className={!animated ? 'on' : ''} onClick={() => setAnimated(false)}>off</button>
          </div>
          <div className="hint">只影响 M2 · Drop 和 M5 · Cursor,其它本来就是静态。</div>
        </div>

        <div className="grp">
          <div className="grp-title">Notes</div>
          <div className="hint" style={{ lineHeight: 1.55 }}>
            想推进哪一个?直接告诉我编号(M1–M6)。也可以说"M3 但水滴改成 M2 的",我会做合体版。
          </div>
        </div>
      </aside>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<V3Showcase />);
