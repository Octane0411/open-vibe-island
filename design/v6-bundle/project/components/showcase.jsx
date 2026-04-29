// Main showcase app
const { useState, useEffect, useRef } = React;

function Showcase() {
  // Preset: 'A' (all liquid), 'B' (all pixel), 'C' (all ascii), 'hybrid' (liquid notch + ascii icons — user-picked combo)
  const [preset, setPreset] = useState('hybrid');
  const [agent, setAgent] = useState('claude');
  const [speed, setSpeed] = useState(1);
  const [state, setState] = useState('running');
  const [darkPreview, setDarkPreview] = useState(true);

  // Per-section direction override — applied when preset === 'hybrid' (or user manually overrides)
  // logo / appIcon / agentIcon / status / notch
  const hybridMap = { logo: 'A', appIcon: 'A', agentIcon: 'C', status: 'C', notch: 'A' };
  const uniformMap = (k) => ({ logo: k, appIcon: k, agentIcon: k, status: k, notch: k });
  const dirMap = preset === 'hybrid' ? hybridMap : uniformMap(preset);
  // 'direction' retained as a loose alias — represents the preset at the top level for chips
  const direction = preset;

  // Timeline auto-cycle
  const [autoCycle, setAutoCycle] = useState(true);
  useEffect(() => {
    if (!autoCycle) return;
    const seq = ['idle', 'running', 'notify', 'done', 'idle', 'running', 'error', 'expanded', 'idle'];
    let i = 0;
    const tick = () => {
      setState(seq[i % seq.length]);
      i++;
    };
    tick();
    const id = setInterval(tick, 2600 / speed);
    return () => clearInterval(id);
  }, [autoCycle, speed]);

  // Edit-mode protocol
  useEffect(() => {
    const handler = (e) => {
      if (e.data?.type === '__activate_edit_mode') document.getElementById('tweaks-panel').style.display = 'block';
      if (e.data?.type === '__deactivate_edit_mode') document.getElementById('tweaks-panel').style.display = 'none';
    };
    window.addEventListener('message', handler);
    window.parent.postMessage({ type: '__edit_mode_available' }, '*');
    return () => window.removeEventListener('message', handler);
  }, []);

  const dirLabel = { A: 'Liquid Glass', B: 'Pixel · 8-bit', C: 'Terminal · ASCII', hybrid: 'Hybrid · Liquid notch + ASCII icons' }[preset];
  const dirTag   = { A: '/liquid', B: '/pixel', C: '/terminal', hybrid: '/hybrid' }[preset];

  return (
    <div className="app">
      {/* Topbar */}
      <header className="topbar">
        <div className="brand">
          <span className="dot" />
          <span>Open Island — Brand Redesign</span>
        </div>
        <span className="meta mono">v0.1 · 3 directions · 20 components</span>
        <div className="spacer" />
        <span className="chip">preset: {preset} · {dirTag}</span>
        <span className="chip">state: {state}</span>
      </header>

      {/* Left nav */}
      <nav className="side">
        <h4>Explore</h4>
        {[
          ['00', 'Starting point', true],
          ['01', 'Logomarks', false],
          ['02', 'App icon', false],
          ['03', 'Agent & terminal icons', false],
          ['04', 'Status icons', false],
          ['05', 'Notch — idle → busy', false],
          ['06', 'Notch — permission', false],
          ['07', 'Notch — expanded', false],
          ['08', 'Motion timeline', false],
          ['09', 'In situ', false],
        ].map(([n, t, active]) => (
          <a key={n} href={`#s-${n}`} className={'navitem' + (active ? ' active' : '')}>
            <span className="mono" style={{ color: 'var(--ink-mute)', fontSize: 11, width: 18 }}>{n}</span>
            <span>{t}</span>
          </a>
        ))}
        <h4 style={{ marginTop: 24 }}>About</h4>
        <div style={{ padding: '4px 10px', fontSize: 12, color: 'var(--ink-mute)', lineHeight: 1.5 }}>
          Open-source macOS companion for AI coding agents. Lives in the notch.
        </div>
      </nav>

      {/* Main */}
      <main className="main">
        {/* 00 — Starting point */}
        <section className="section" id="s-00">
          <div className="section-head">
            <h2>Starting point</h2>
            <span className="tag mono">// assumptions</span>
            <div className="line" />
          </div>
          <div className="assumption">
            Open Island is a <b>control surface</b>, not an app you stare at. The identity lives in the notch — tiny by default, expands on demand. <b>After review you picked a hybrid</b>: Liquid Glass for the notch & motion (native, expressive), ASCII for the icons & status (legible, developer-native, rich at 16px). That combo is now the default — other presets remain for comparison.
            <div className="grid-4" style={{ marginTop: 14 }}>
              <DirCard k="hybrid" name="Hybrid ★" sub="Liquid notch + ASCII icons. The picked combo." active={preset === 'hybrid'} onClick={() => setPreset('hybrid')} />
              <DirCard k="A" name="Liquid Glass" sub="All liquid. Apple-native, expressive." active={preset === 'A'} onClick={() => setPreset('A')} />
              <DirCard k="B" name="Pixel · 8-bit" sub="All pixel. CRT, step timing." active={preset === 'B'} onClick={() => setPreset('B')} />
              <DirCard k="C" name="Terminal · ASCII" sub="All ASCII. Ink on paper." active={preset === 'C'} onClick={() => setPreset('C')} />
            </div>
            <div style={{ marginTop: 12, padding: 10, background: '#0d0d13', border: '1px solid var(--line)', borderRadius: 8, fontSize: 12, color: 'var(--ink-soft)', fontFamily: "'JetBrains Mono', monospace" }}>
              <div style={{ color: 'var(--ink-mute)', marginBottom: 4 }}>// hybrid map</div>
              <div>logo       <span style={{ color: '#fff' }}>→ A liquid</span></div>
              <div>app icon   <span style={{ color: '#fff' }}>→ A liquid</span></div>
              <div>notch      <span style={{ color: '#fff' }}>→ A liquid</span> <span style={{ color: 'var(--ink-mute)' }}>(motion, permission, expanded)</span></div>
              <div>agent icon <span style={{ color: '#fff' }}>→ C ascii</span> <span style={{ color: 'var(--ink-mute)' }}>(reads at 16px, feels developer-native)</span></div>
              <div>status     <span style={{ color: '#fff' }}>→ C ascii</span> <span style={{ color: 'var(--ink-mute)' }}>(○ ◉ ◎ ✕ ◆)</span></div>
            </div>
          </div>
        </section>

        {/* 01 — Logomarks */}
        <section className="section" id="s-01">
          <div className="section-head">
            <h2>01 · Logomarks</h2>
            <span className="tag mono">// 3 directions, animated</span>
            <div className="line" />
          </div>
          <div className="grid-3">
            <LogoCard k="A" active={dirMap.logo === 'A'}>
              <LogoLiquid size={180} animated theme="violet" />
            </LogoCard>
            <LogoCard k="B" active={dirMap.logo === 'B'}>
              <LogoPixel size={180} animated theme="green" />
            </LogoCard>
            <LogoCard k="C" active={dirMap.logo === 'C'}>
              <LogoTerminal size={180} animated theme="paper" />
            </LogoCard>
          </div>
        </section>

        {/* 02 — App icon @ multi-size */}
        <section className="section" id="s-02">
          <div className="section-head">
            <h2>02 · App icon — Dock / Finder sizes</h2>
            <span className="tag mono">// direction {direction}</span>
            <div className="line" />
          </div>
          <div className="card">
            <div className="hdr">
              <div className="lt"><span className="dot-x" style={{ background:'#ff5f56' }} /><span className="dot-x" style={{ background:'#ffbd2e' }} /><span className="dot-x" style={{ background:'#27c93f' }} /><span style={{ marginLeft: 10 }}>Finder · Applications</span></div>
              <span>{dirMap.appIcon === 'A' ? 'liquid.icns' : dirMap.appIcon === 'B' ? 'pixel.icns' : 'terminal.icns'}</span>
            </div>
            <div className="icon-plate" style={{ minHeight: 240 }}>
              <BigIcon direction={dirMap.appIcon} size={200} />
            </div>
            <div className="icon-sizes">
              {[512, 256, 128, 64, 32, 16].map(sz => (
                <div className="wrap" key={sz}>
                  <BigIcon direction={dirMap.appIcon} size={sz <= 64 ? sz : 64 * (sz/256)*2} />
                  <span className="lbl">{sz}px</span>
                </div>
              ))}
            </div>
          </div>
        </section>

        {/* 03 — Agent & terminal icons */}
        <section className="section" id="s-03">
          <div className="section-head">
            <h2>03 · Agent & terminal icons</h2>
            <span className="tag mono">// multi-color, per agent</span>
            <div className="line" />
          </div>
          <div className="card">
            <div className="hdr">
              <span>// 9 agents & terminals · direction {dirMap.agentIcon}</span>
              <span>48px / 24px</span>
            </div>
            <div style={{ padding: 18 }}>
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(9, 1fr)', gap: 14 }}>
                {['claude','codex','opencode','gemini','termapp','ghostty','cmux','kaku','wezterm'].map(a => (
                  <div key={a} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8 }}>
                    <AgentIcon name={a} size={56} direction={dirMap.agentIcon} />
                    <div style={{ fontSize: 11, color: 'var(--ink-soft)' }}>{a}</div>
                  </div>
                ))}
              </div>
              <div style={{ height: 1, background: 'var(--line)', margin: '18px 0' }} />
              {/* Small size */}
              <div style={{ display: 'flex', alignItems: 'center', gap: 18, flexWrap: 'wrap' }}>
                <span className="mono" style={{ fontSize: 10, color: 'var(--ink-mute)', letterSpacing: '0.15em', textTransform: 'uppercase' }}>Menubar size</span>
                {['claude','codex','opencode','gemini','termapp','ghostty','cmux','kaku','wezterm'].map(a => (
                  <AgentIcon key={a} name={a} size={20} direction={dirMap.agentIcon} />
                ))}
              </div>
            </div>
          </div>
        </section>

        {/* 04 — Status icons */}
        <section className="section" id="s-04">
          <div className="section-head">
            <h2>04 · Status</h2>
            <span className="tag mono">// idle · running · waiting · error · done</span>
            <div className="line" />
          </div>
          <div className="card">
            <div className="hdr"><span>// state glyphs</span><span>animated</span></div>
            <div style={{ padding: 22, display: 'flex', gap: 36, justifyContent: 'space-around', alignItems: 'center' }}>
              {['idle','running','waiting','error','done'].map(st => (
                <div key={st} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8 }}>
                  <StatusIcon state={st} direction={dirMap.status} size={40} />
                  <span className="mono" style={{ fontSize: 11, color: 'var(--ink-soft)' }}>{st}</span>
                </div>
              ))}
            </div>
          </div>
        </section>

        {/* 05 — Notch idle → busy */}
        <section className="section" id="s-05">
          <div className="section-head">
            <h2>05 · Notch — idle → busy</h2>
            <span className="tag mono">// morph</span>
            <div className="line" />
          </div>
          <div className="grid-2">
            <NotchScene label="Idle" state="idle" direction={dirMap.notch} agent={agent} speed={speed} dark={darkPreview} />
            <NotchScene label="Running" state="running" direction={dirMap.notch} agent={agent} speed={speed} dark={darkPreview} />
          </div>
        </section>

        {/* 06 — Notch notify / error */}
        <section className="section" id="s-06">
          <div className="section-head">
            <h2>06 · Notch — permission & error</h2>
            <span className="tag mono">// expanded</span>
            <div className="line" />
          </div>
          <div className="grid-2">
            <NotchScene label="Permission request" state="notify" direction={dirMap.notch} agent={agent} speed={speed} dark={darkPreview} tall />
            <NotchScene label="Error / Done" state={state === 'done' || state === 'error' ? state : 'error'} direction={dirMap.notch} agent={agent} speed={speed} dark={darkPreview} />
          </div>
        </section>

        {/* 07 — Expanded control center in notch */}
        <section className="section" id="s-07">
          <div className="section-head">
            <h2>07 · Notch — expanded sessions</h2>
            <span className="tag mono">// full detail</span>
            <div className="line" />
          </div>
          <NotchScene label="Expanded" state="expanded" direction={dirMap.notch} agent={agent} speed={speed} dark={darkPreview} veryTall />
        </section>

        {/* 08 — Motion timeline */}
        <section className="section" id="s-08">
          <div className="section-head">
            <h2>08 · Motion timeline</h2>
            <span className="tag mono">// live · {autoCycle ? 'auto' : 'manual'}</span>
            <div className="line" />
          </div>
          <div className="card">
            <div className="hdr">
              <div className="lt">
                <span className="dot-x" style={{ background:'#ff5f56' }} />
                <span className="dot-x" style={{ background:'#ffbd2e' }} />
                <span className="dot-x" style={{ background:'#27c93f' }} />
                <span style={{ marginLeft: 10 }}>~/motion.timeline</span>
              </div>
              <span>state: {state}</span>
            </div>
            <div style={{ background: '#000', minHeight: 240, position: 'relative' }}>
              <MacMenuBar dark />
              <NotchOverlay direction={dirMap.notch} state={state} agent={agent} speed={speed} />
              <div style={{ position: 'absolute', bottom: 16, left: 16, right: 16, display: 'flex', justifyContent: 'space-between', alignItems: 'center', color: 'rgba(255,255,255,0.5)', fontFamily: "'JetBrains Mono', monospace", fontSize: 10 }}>
                <span>auto-cycle every {Math.round(2600/speed)}ms</span>
                <div style={{ display: 'flex', gap: 8 }}>
                  {['idle','running','notify','error','done','expanded'].map(s => (
                    <button key={s} onClick={() => { setAutoCycle(false); setState(s); }}
                      style={{ background: s === state ? 'rgba(255,255,255,0.15)' : 'transparent', color: s === state ? '#fff' : 'rgba(255,255,255,0.55)', border: '1px solid rgba(255,255,255,0.15)', padding: '3px 8px', borderRadius: 4, fontFamily: 'inherit', fontSize: 10, cursor: 'pointer' }}>
                      {s}
                    </button>
                  ))}
                  <button onClick={() => setAutoCycle(a => !a)} style={{ background: autoCycle ? '#fff' : 'transparent', color: autoCycle ? '#000' : 'rgba(255,255,255,0.55)', border: '1px solid rgba(255,255,255,0.15)', padding: '3px 8px', borderRadius: 4, fontFamily: 'inherit', fontSize: 10, cursor: 'pointer' }}>{autoCycle ? '■ stop' : '▶ auto'}</button>
                </div>
              </div>
            </div>
          </div>
        </section>

        {/* 09 — In situ: macOS top bar with apps & notch */}
        <section className="section" id="s-09">
          <div className="section-head">
            <h2>09 · In situ — menubar & notch</h2>
            <span className="tag mono">// screenshot-fidelity</span>
            <div className="line" />
          </div>
          <InSitu dirMap={dirMap} state={state} agent={agent} speed={speed} />
        </section>
      </main>

      {/* Right tweaks */}
      <aside className="tweaks" id="tweaks-panel">
        <h3>Tweaks</h3>

        <div className="grp">
          <div className="grp-title">Preset</div>
          <div className="btn-group" style={{ flexWrap: 'wrap' }}>
            <button className={preset === 'hybrid' ? 'on' : ''} onClick={() => setPreset('hybrid')}>★ hybrid</button>
            {['A','B','C'].map(k => (
              <button key={k} className={preset === k ? 'on' : ''} onClick={() => setPreset(k)}>{k} · {k === 'A' ? 'liquid' : k === 'B' ? 'pixel' : 'ascii'}</button>
            ))}
          </div>
          <div style={{ marginTop: 8, fontSize: 10, color: 'var(--ink-mute)', fontFamily: "'JetBrains Mono', monospace", lineHeight: 1.5 }}>
            {preset === 'hybrid' ? 'notch→liquid  icons→ascii  status→ascii' : `all sections → ${preset === 'A' ? 'liquid' : preset === 'B' ? 'pixel' : 'ascii'}`}
          </div>
        </div>

        <div className="grp">
          <div className="grp-title">Agent</div>
          <div className="btn-group" style={{ flexWrap: 'wrap' }}>
            {['claude','codex','ghostty','cmux','kaku','wezterm'].map(a => (
              <button key={a} className={agent === a ? 'on' : ''} onClick={() => setAgent(a)}>
                <span style={{ display: 'inline-block', width: 8, height: 8, background: AGENT_COLORS[a], borderRadius: 2, marginRight: 6, verticalAlign: 'middle' }} />
                {a}
              </button>
            ))}
          </div>
        </div>

        <div className="grp">
          <div className="grp-title">Notch state</div>
          <div className="btn-group" style={{ flexWrap: 'wrap' }}>
            {['idle','running','notify','error','done','expanded'].map(s => (
              <button key={s} className={state === s && !autoCycle ? 'on' : ''} onClick={() => { setAutoCycle(false); setState(s); }}>{s}</button>
            ))}
            <button className={autoCycle ? 'on' : ''} onClick={() => setAutoCycle(a => !a)}>{autoCycle ? '◉ auto' : '○ auto'}</button>
          </div>
        </div>

        <div className="grp">
          <div className="grp-title">Speed · {speed.toFixed(2)}×</div>
          <input type="range" min="0.25" max="3" step="0.05" value={speed} onChange={e => setSpeed(parseFloat(e.target.value))} style={{ width: '100%' }} />
          <div className="btn-group" style={{ marginTop: 6 }}>
            {[0.5, 1, 1.5, 2].map(s => (
              <button key={s} className={Math.abs(speed-s) < 0.01 ? 'on' : ''} onClick={() => setSpeed(s)}>{s}×</button>
            ))}
          </div>
        </div>

        <div className="grp">
          <div className="grp-title">Background preview</div>
          <div className="btn-group">
            <button className={darkPreview ? 'on' : ''} onClick={() => setDarkPreview(true)}>dark</button>
            <button className={!darkPreview ? 'on' : ''} onClick={() => setDarkPreview(false)}>light</button>
          </div>
        </div>

        <div className="grp">
          <div className="grp-title">Notes</div>
          <div style={{ fontSize: 11, color: 'var(--ink-mute)', lineHeight: 1.55 }}>
            Every element on the page reacts to these controls. The motion timeline auto-cycles through all 6 states. Open the <span className="kbd">Tweaks</span> toggle in the top bar to hide this panel.
          </div>
        </div>
      </aside>
    </div>
  );
}

// ---- Helpers ----
function DirCard({ k, name, sub, active, onClick }) {
  return (
    <div onClick={onClick} style={{
      background: active ? '#1e1e28' : '#15151d',
      border: `1px solid ${active ? '#3a3a4a' : 'var(--line)'}`,
      borderRadius: 10, padding: 14, cursor: 'pointer',
      transition: 'all 160ms',
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 6 }}>
        <span className="mono" style={{ fontSize: 10, color: 'var(--ink-mute)' }}>DIR {k}</span>
        <div style={{ fontSize: 14, fontWeight: 500 }}>{name}</div>
        {active && <span className="mono" style={{ marginLeft: 'auto', fontSize: 10, color: 'var(--A-3)' }}>● active</span>}
      </div>
      <div style={{ fontSize: 12, color: 'var(--ink-mute)', lineHeight: 1.45 }}>{sub}</div>
    </div>
  );
}

function LogoCard({ k, active, children }) {
  return (
    <div className="card">
      <div className="hdr">
        <span>dir {k}</span>
        {active && <span style={{ color: 'var(--A-3)' }}>● active</span>}
      </div>
      <div style={{ display: 'grid', placeItems: 'center', padding: 30, background: '#0d0d13' }}>
        {children}
      </div>
    </div>
  );
}

function BigIcon({ direction, size }) {
  if (direction === 'A') return <LogoLiquid size={size} animated theme="violet" />;
  if (direction === 'B') return <LogoPixel size={size} animated theme="green" />;
  return <LogoTerminal size={size} animated theme="paper" />;
}

function MacMenuBar({ dark }) {
  return (
    <div style={{
      height: 28, background: dark ? 'rgba(0,0,0,0.55)' : 'rgba(255,255,255,0.85)',
      color: dark ? 'rgba(255,255,255,0.75)' : '#000',
      fontFamily: '-apple-system, system-ui, sans-serif', fontSize: 11,
      display: 'flex', alignItems: 'center', padding: '0 12px', gap: 14,
      borderBottom: `1px solid ${dark ? 'rgba(255,255,255,0.05)' : 'rgba(0,0,0,0.08)'}`,
    }}>
      <span style={{ fontSize: 13 }}>&#63743;</span>
      <span style={{ fontWeight: 600 }}>Xcode</span>
      <span style={{ opacity: 0.7 }}>File</span>
      <span style={{ opacity: 0.7 }}>Edit</span>
      <span style={{ opacity: 0.7 }}>View</span>
      <span style={{ opacity: 0.7 }}>Find</span>
      <span style={{ flex: 1 }} />
      <span style={{ opacity: 0.7 }}>100%</span>
      <span style={{ opacity: 0.7 }}>Tue 3:42</span>
    </div>
  );
}

function NotchScene({ label, state, direction, agent, speed, dark = true, tall, veryTall }) {
  return (
    <div className="card">
      <div className="hdr">
        <span>{label}</span>
        <span className="mono">{state}</span>
      </div>
      <div style={{
        background: dark ? '#000' : '#f2f2f6',
        position: 'relative',
        minHeight: veryTall ? 300 : tall ? 240 : 180,
      }}>
        <MacMenuBar dark={dark} />
        <NotchOverlay direction={direction} state={state} agent={agent} speed={speed} />
      </div>
    </div>
  );
}

function InSitu({ dirMap, state, agent, speed }) {
  return (
    <div className="card">
      <div className="hdr">
        <div className="lt">
          <span className="dot-x" style={{ background: '#ff5f56' }} />
          <span className="dot-x" style={{ background: '#ffbd2e' }} />
          <span className="dot-x" style={{ background: '#27c93f' }} />
          <span style={{ marginLeft: 10 }}>~ Desktop</span>
        </div>
        <span>1440 × 900</span>
      </div>
      <div style={{
        position: 'relative',
        background: 'linear-gradient(160deg, #2d1b4e 0%, #0f1b33 50%, #062133 100%)',
        minHeight: 420,
        overflow: 'hidden',
      }}>
        <MacMenuBar dark />
        <NotchOverlay direction={dirMap.notch} state={state} agent={agent} speed={speed} />
        {/* Fake window */}
        <div style={{
          position: 'absolute', top: 80, left: 40, right: 40, bottom: 70,
          background: 'rgba(20,20,28,0.92)',
          backdropFilter: 'blur(20px)',
          border: '1px solid rgba(255,255,255,0.08)',
          borderRadius: 12,
          boxShadow: '0 20px 60px rgba(0,0,0,0.4)',
          display: 'flex', flexDirection: 'column',
          fontFamily: "'JetBrains Mono', monospace",
          color: '#ededf2', fontSize: 12,
        }}>
          <div style={{ padding: '8px 12px', borderBottom: '1px solid rgba(255,255,255,0.06)', display: 'flex', gap: 8, alignItems: 'center' }}>
            <span className="dot-x" style={{ background: '#ff5f56' }} />
            <span className="dot-x" style={{ background: '#ffbd2e' }} />
            <span className="dot-x" style={{ background: '#27c93f' }} />
            <span style={{ marginLeft: 10, fontSize: 11, color: 'rgba(255,255,255,0.55)' }}>ghostty · zsh</span>
          </div>
          <div style={{ padding: 16, lineHeight: 1.55 }}>
            <div style={{ color: '#6ee7b7' }}>~/open-island git:(main) $ <span style={{ color: '#fff' }}>claude code "refactor NotchPresenter"</span></div>
            <div style={{ color: 'rgba(255,255,255,0.55)' }}>● Reading NotchPresenter.swift...</div>
            <div style={{ color: 'rgba(255,255,255,0.55)' }}>● Analyzing state machine...</div>
            <div style={{ color: '#fbbf24' }}>? permission: write_file ./NotchPresenter.swift</div>
            <div style={{ color: 'rgba(255,255,255,0.35)' }}>  → see notch for decision</div>
            <div style={{ marginTop: 8, color: '#fff' }}>▍</div>
          </div>
          <div style={{ flex: 1 }} />
          <div style={{ padding: '6px 12px', borderTop: '1px solid rgba(255,255,255,0.06)', fontSize: 10, color: 'rgba(255,255,255,0.5)', display: 'flex', gap: 12 }}>
            <span>↑ 3.2k tok</span>
            <span>claude-sonnet</span>
            <span style={{ marginLeft: 'auto' }}>bridge · connected</span>
          </div>
        </div>
      </div>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<Showcase />);
