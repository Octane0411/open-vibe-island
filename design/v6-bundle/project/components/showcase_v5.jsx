// v5 — Show 7 candidate symbols, each paired with its Notch behavior, Logo, and App Icon.
// Principle: whatever the logo's left-cap symbol is, it is ALSO the notch's idle state.

const { useState: useState_v5 } = React;

function V5Showcase() {
  const [tone, setTone] = useState_v5('paper');

  const symbols = [
    {
      key: 'chevron',
      name: 'S1 · Chevron',
      logic: 'chevron = "prompt / forward / run"。Idle 时是 `›`,running 加右侧 spinner,done → check。最像 terminal prompt。',
      feel: 'Linear / Warp 气质。最"开发者"。',
    },
    {
      key: 'dot',
      name: 'S2 · Dot',
      logic: 'dot = "signal / cursor / camera"。Idle 是一枚静默小圆,running 时呼吸,done 时短暂变实心对勾。最像 Dynamic Island 原生语言。',
      feel: '最 Apple 原生。安静、有呼吸。',
    },
    {
      key: 'tick',
      name: 'S3 · Tick',
      logic: 'idle 什么都不画(只一枚空药丸);事件来了用 dot / bars;done 才出现 tick。tick 是"终态符号",不做 resting state。',
      feel: '最克制。空 pill 本身就是品牌,事件才填满。',
    },
    {
      key: 'bracket',
      name: 'S4 · Bracket ⟨⟩',
      logic: '⟨ ⟩ 夹起内容 = "we wrap your agent output"。Idle 是一对方括号,running 时内部流动,done tick。',
      feel: '代码 / 引用的语义,很 dev。',
    },
    {
      key: 'prompt',
      name: 'S5 · $ Prompt',
      logic: '直接是 shell 提示符。Idle = `$`,running = `$` + spinner,done = `$` + tick。',
      feel: '最直白的 terminal 符号,但风险是"太像终端不像品牌"。',
    },
    {
      key: 'bars',
      name: 'S6 · Bars',
      logic: '三根高低柱 = "activity / output"。Idle 时静止,running 时起伏。最"有在干活"的感觉,但 idle 较"空心"。',
      feel: '有活力,但不像 terminal。',
    },
    {
      key: 'triangle',
      name: 'S7 · Triangle ▶',
      logic: '播放/执行三角。Idle 是 ▶,running 时右边动,done 是 ✓。很清晰但略通用。',
      feel: '"Run" 按钮的延伸,功能感强。',
    },
  ];

  React.useEffect(() => {
    const handler = (e) => {
      const panel = document.getElementById('tweaks-v5');
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
        <div className="brand"><span className="dot-v3" /><span>Open Island · Logo v5 — symbol system</span></div>
        <span className="meta mono">// logo.left = notch.idle</span>
        <div className="spacer" />
        <span className="chip">7 symbols</span>
      </header>

      <main className="main main-v3">
        <section className="section">
          <div className="section-head">
            <h2>The thesis</h2>
            <span className="tag mono">// rationale</span>
            <div className="line" />
          </div>
          <div className="assumption" style={{ display: 'grid', gap: 10 }}>
            <div>
              你指出的是对的。<b>Logo 的左侧符号</b>不能凭好看决定,必须是 <b>notch UI 的 idle state</b> — 这样品牌和产品是同一个符号系统。
            </div>
            <div>
              下面 7 个候选符号,每个都给你看完整链路:<b>(1) 左:notch 在 5 个状态里的样子</b> → <b>(2) 中:纯 logo</b> → <b>(3) 右:app icon</b>。
              关注点应该是:"running / done / notify 时,这个符号系列撑不撑得住?"
            </div>
            <div style={{ color: '#9a9aa8', fontSize: 12 }}>
              5 个 notch 状态:idle(静置)· running(跑)· busy(多 agent)· notify(有事)· done(完成)。所有状态里 <code>done</code> 都 fallback 到 tick — 这是系统级"完成"符号。
            </div>
          </div>
        </section>

        {symbols.map(s => (
          <section key={s.key} className="section sym-section">
            <div className="section-head">
              <h2>{s.name}</h2>
              <span className="tag mono">// {s.key}</span>
              <div className="line" />
            </div>

            <div className="sym-row">
              {/* LEFT: Notch states */}
              <div className="sym-col sym-col-notch">
                <div className="col-hd">Notch states</div>
                <NotchStateRow symbolKey={s.key} />
              </div>

              {/* MID: Logo */}
              <div className="sym-col sym-col-logo">
                <div className="col-hd">Logo mark</div>
                <div className="logo-plate" data-tone={tone}>
                  <LogoWithSymbol symbolKey={s.key} size={160} tone={tone} />
                </div>
              </div>

              {/* RIGHT: App icon */}
              <div className="sym-col sym-col-app">
                <div className="col-hd">App icon</div>
                <AppIconWithSymbol symbolKey={s.key} size={160} tone={tone} />
              </div>
            </div>

            <div className="sym-notes">
              <div className="sym-logic"><span className="k">Logic · </span>{s.logic}</div>
              <div className="sym-feel"><span className="k">Feel · </span>{s.feel}</div>
            </div>

            {/* In-wild: real menu bar */}
            <div className="wild">
              <div className="col-hd" style={{ marginBottom: 10 }}>In the wild</div>
              <div style={{ display: 'flex', gap: 14, flexWrap: 'wrap' }}>
                <MenuBarMock wallpaper="plum" width={380}>
                  <NotchBar symbolKey={s.key} width={90} height={28} />
                </MenuBarMock>
                <MenuBarMock wallpaper="slate" width={380}>
                  <NotchBar symbolKey={s.key} width={170} height={28} label="Claude · editing" running />
                </MenuBarMock>
              </div>
            </div>
          </section>
        ))}
      </main>

      <aside className="tweaks" id="tweaks-v5">
        <h3>Tweaks</h3>
        <div className="grp">
          <div className="grp-title">Logo / App icon tone</div>
          <div className="btn-group">
            <button className={tone === 'paper' ? 'on' : ''} onClick={() => setTone('paper')}>paper</button>
            <button className={tone === 'ink' ? 'on' : ''} onClick={() => setTone('ink')}>ink</button>
            <button className={tone === 'bw' ? 'on' : ''} onClick={() => setTone('bw')}>bw</button>
          </div>
          <div className="hint">Notch 本身固定深色(菜单栏里只有深色才对)。</div>
        </div>
        <div className="grp">
          <div className="grp-title">How to respond</div>
          <div className="hint" style={{ lineHeight: 1.55 }}>
            告诉我:<br />1) 留哪个/哪几个符号<br />2) 对 notch 状态系统有什么调整(加状态、删状态、改逻辑)<br /><br />下一步我会把 1–2 个获胜符号做成完整规格(含动画时间线、边角 / 内边距 / 尺寸规范)。
          </div>
        </div>
      </aside>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<V5Showcase />);
