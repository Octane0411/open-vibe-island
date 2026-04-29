// v7 — The pill IS the panel. Session + notification = different contents inside the same shape.
const { useState: useS, useEffect: useE, useRef: useR } = React;

// ---------- Data ----------
const SESSIONS = [
  { id: 's1', agent: 'claude', state: 'waiting', project: 'open-island', branch: 'refactor/claude-kernel-pid-monitor', msg: '开始执行吧，先补测试再提 PR', you: '<task-notification>', terminal: 'Ghostty', age: '2h', detail: { tool: 'Edit', target: 'Sources/OpenIslandCore/Sessions/SessionState.swift L124-156' } },
  { id: 's2', agent: 'claude', state: 'waiting', project: 'open-island', branch: 'fix/external-island-width', msg: '有用户反馈外接屏宽度计算有问题', you: '提个 PR', terminal: 'Ghostty', age: '4h', detail: { tool: 'Bash', target: 'git diff --stat' } },
  { id: 's3', agent: 'codex',  state: 'running', project: 'open-island', branch: 'main', msg: '分析 session reducer 的测试覆盖率', you: 'run tests', terminal: 'Terminal', age: '3m', detail: { tool: 'Bash', target: 'swift test --filter SessionStateTests' } },
  { id: 's4', agent: 'claude', state: 'idle', project: 'open-island', branch: 'main', msg: '', you: '', terminal: 'Ghostty', age: '<1m' },
  { id: 's5', agent: 'claude', state: 'idle', project: 'open-island', branch: 'main', msg: '', you: '', terminal: 'Ghostty', age: '<1m' },
  { id: 's6', agent: 'codex',  state: 'idle', project: 'open-island', branch: 'main', msg: '', you: '', terminal: 'cmux', age: '<1m' },
  { id: 's7', agent: 'claude', state: 'done', project: 'dotfiles', branch: 'main', msg: 'Commit pushed · 3 files changed', you: 'commit all and push', terminal: 'Kaku', age: '12m' },
  { id: 's8', agent: 'codex',  state: 'idle', project: 'open-island', branch: 'main', msg: '', you: '', terminal: 'WezTerm', age: '<1m' },
];
const pickSessions = (n) => SESSIONS.slice(0, n);

// ---------- Icons ----------
const IconSound = () => (<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5" fill="currentColor" stroke="none"/><path d="M15.54 8.46a5 5 0 0 1 0 7.07"/><path d="M19.07 4.93a10 10 0 0 1 0 14.14"/></svg>);
const IconGear = () => (<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09a1.65 1.65 0 0 0-1-1.51 1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09a1.65 1.65 0 0 0 1.51-1 1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg>);

// ---------- Unified bars glyph (from v6) ----------
function BarsGlyph({ mode = 'idle' }) {
  const ink = '#f1ead9';
  if (mode === 'running') return (
    <svg width="24" height="24" viewBox="0 0 24 24"><g fill={ink}>
      <rect x="5.25" width="2.5" rx="1.25"><animate attributeName="height" values="4;12;4" dur="0.9s" repeatCount="indefinite"/><animate attributeName="y" values="10;6;10" dur="0.9s" repeatCount="indefinite"/></rect>
      <rect x="10.75" width="2.5" rx="1.25"><animate attributeName="height" values="6;14;6" dur="0.9s" begin="0.15s" repeatCount="indefinite"/><animate attributeName="y" values="9;5;9" dur="0.9s" begin="0.15s" repeatCount="indefinite"/></rect>
      <rect x="16.25" width="2.5" rx="1.25"><animate attributeName="height" values="4;10;4" dur="0.9s" begin="0.3s" repeatCount="indefinite"/><animate attributeName="y" values="10;7;10" dur="0.9s" begin="0.3s" repeatCount="indefinite"/></rect>
    </g></svg>
  );
  if (mode === 'waiting') return (
    <svg width="24" height="24" viewBox="0 0 24 24"><g fill={ink}>
      <rect x="5.25" y="7" width="2.5" height="10" rx="1.25"><animate attributeName="fill-opacity" values="0.55;1;0.55" dur="1.8s" repeatCount="indefinite"/></rect>
      <rect x="16.25" y="7" width="2.5" height="10" rx="1.25"><animate attributeName="fill-opacity" values="1;0.55;1" dur="1.8s" repeatCount="indefinite"/></rect>
    </g></svg>
  );
  if (mode === 'done') return (<svg width="24" height="24" viewBox="0 0 24 24"><path d="M 6 12 L 10.5 16.5 L 18 9" fill="none" stroke={ink} strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"/></svg>);
  return (
    <svg width="24" height="24" viewBox="0 0 24 24"><g fill={ink}>
      <rect x="5.25" y="10.5" width="2.5" height="3" rx="1.25" fillOpacity="0.7"/>
      <rect x="10.75" y="9.5" width="2.5" height="5" rx="1.25"><animate attributeName="fill-opacity" values="0.7;1;0.7" dur="2.8s" repeatCount="indefinite"/></rect>
      <rect x="16.25" y="10.5" width="2.5" height="3" rx="1.25" fillOpacity="0.7"/>
    </g></svg>
  );
}

// ---------- Notch-row (top 32px of pill, stays when expanded) ----------
function NotchRow({ state, label, right, macbook, width }) {
  if (macbook) {
    return (
      <div className="oi-notch-row" style={{ width }}>
        <div style={{ display:'flex', alignItems:'center' }}>
          <div className="glyph"><BarsGlyph mode={state}/></div>
        </div>
        <div className="phys-gap" />
        <div className="right">{right}</div>
      </div>
    );
  }
  return (
    <div className="oi-notch-row" style={{ width }}>
      <div style={{ display:'flex', alignItems:'center' }}>
        <div className="glyph"><BarsGlyph mode={state}/></div>
        {label && <span className="label">{label}</span>}
      </div>
      <div className="spacer" />
      {right && <div className="right">{right}</div>}
    </div>
  );
}

// ---------- Usage strip ----------
function UsageStrip() {
  return (
    <div className="oi-usage">
      <span className="lbl claude">Claude</span>
      <span className="u hot">5h <b>13%</b></span>
      <span className="u">7d <b>12%</b></span>
      <span className="sep">│</span>
      <span className="lbl codex">Codex</span>
      <span className="u ok">5h <b>1%</b></span>
      <span className="u ok">7d <b>5%</b></span>
      <span className="spacer" />
      <button className="icon-btn" title="Sound"><IconSound/></button>
      <button className="icon-btn" title="Settings"><IconGear/></button>
    </div>
  );
}

// ---------- Session row ----------
function Row({ s, expanded, onToggle, density, variant }) {
  const compact = density === 'compact';
  return (
    <>
      <div className={`oi-row ${compact?'compact':''}`} onClick={onToggle}>
        <span className={`state-dot ${s.state}`}/>
        <div className="oi-main">
          <div className="title">
            <span className="proj">{s.project}</span>
            {s.branch && s.branch !== 'main' && <span className="branch"> ({s.branch})</span>}
            {s.msg && !compact && <><span className="sep">·</span><span className="msg">{s.msg}</span></>}
          </div>
          {!compact && s.you && <div className="sub"><span className="you">You:</span> {s.you}</div>}
        </div>
        <div className="side">
          {variant !== 'grouped' && <span className={`oi-badge ${s.agent}`}>{s.agent === 'claude' ? 'CC' : 'CX'}</span>}
          <span className="oi-badge">{s.terminal}</span>
          <span className="oi-age">{s.age}</span>
        </div>
      </div>
      {expanded && s.detail && (
        <div className="oi-detail">
          <div className="k">Last tool call</div>
          <div>{s.detail.tool} → {s.detail.target}</div>
          <div className="k">Session</div>
          <div style={{fontFamily:'JetBrains Mono, monospace', fontSize:11}}>{s.id}-019a…c27f · {s.terminal}</div>
          <div className="acts">
            <button className="act primary">Jump to terminal ↗</button>
            <button className="act">Open transcript</button>
          </div>
        </div>
      )}
    </>
  );
}

// ---------- Pill content variants (the pill GROWS around these) ----------

// Shared: notch-only (collapsed)
function ContentNotchOnly({ state, label, right, macbook }) {
  return <NotchRow state={state} label={label} right={right} macbook={macbook}/>;
}

// Session list — default
function ContentSessions({ sessions, expandedId, onToggle, density, macbook, variant='default', state, label, right }) {
  return (
    <>
      <NotchRow state={state} label={label} right={right} macbook={macbook}/>
      <UsageStrip/>
      {sessions.length === 0 ? (
        <div className="oi-empty">
          <svg width="44" height="44" viewBox="0 0 44 44" fill="none"><path d="M 6 4 H 38 V 16 A 8 8 0 0 1 30 24 H 14 A 8 8 0 0 1 6 16 Z" fill="none" stroke="rgba(241,234,217,0.2)" strokeWidth="1.5" strokeDasharray="3 3"/></svg>
          <div className="t">No active sessions</div>
          <div className="h">Open a terminal and start <code>claude</code> or <code>codex</code> — sessions auto-appear here.</div>
        </div>
      ) : variant === 'grouped' ? (
        <GroupedRows sessions={sessions} expandedId={expandedId} onToggle={onToggle} density={density}/>
      ) : variant === 'timeline' ? (
        <TimelineRows sessions={sessions} expandedId={expandedId} onToggle={onToggle} density={density}/>
      ) : (
        <div className="oi-list">
          {sessions.map(s => <Row key={s.id} s={s} expanded={expandedId===s.id} onToggle={()=>onToggle(s.id)} density={density} variant="default"/>)}
        </div>
      )}
    </>
  );
}

function GroupedRows({ sessions, expandedId, onToggle, density }) {
  const groups = [
    { k:'claude', label:'Claude Code', list: sessions.filter(s=>s.agent==='claude') },
    { k:'codex',  label:'Codex',       list: sessions.filter(s=>s.agent==='codex')  },
  ].filter(g => g.list.length);
  return (
    <div className="oi-list">
      {groups.map(g => (
        <div key={g.k}>
          <div style={{ padding:'10px 16px 4px', fontFamily:'JetBrains Mono, monospace', fontSize:10.5, textTransform:'uppercase', letterSpacing:'0.14em', color: g.k==='claude'?'#e7a762':'#8cb7ff', display:'flex', alignItems:'center', gap:8, borderTop:'1px solid rgba(255,255,255,0.04)' }}>
            <span>{g.label}</span>
            <span style={{ background:'rgba(255,255,255,0.06)', color:'rgba(241,234,217,0.7)', padding:'1px 7px', borderRadius:999, fontSize:10 }}>{g.list.length}</span>
          </div>
          {g.list.map(s => <Row key={s.id} s={s} expanded={expandedId===s.id} onToggle={()=>onToggle(s.id)} density={density} variant="grouped"/>)}
        </div>
      ))}
    </div>
  );
}

function TimelineRows({ sessions, expandedId, onToggle, density }) {
  return (
    <div className="oi-list">
      {sessions.map(s => (
        <div key={s.id} className="oi-row" style={{ gridTemplateColumns:'44px 1fr auto', gap:10, padding:'10px 16px 10px 0', position:'relative' }} onClick={()=>onToggle(s.id)}>
          <div style={{ fontFamily:'JetBrains Mono, monospace', fontSize:10.5, color:'rgba(241,234,217,0.45)', textAlign:'right', padding:'0 10px 0 0', borderRight:'1px solid rgba(255,255,255,0.1)', position:'relative', alignSelf:'stretch', display:'flex', alignItems:'center', justifyContent:'flex-end' }}>
            {s.age}
            <span style={{ position:'absolute', right:-4.5, top:'50%', width:8, height:8, borderRadius:'50%', background: s.state==='running'?'#6ea7ff':s.state==='waiting'?'#e7a762':s.state==='done'?'#6fb982':'rgba(241,234,217,0.35)', transform:'translateY(-50%)', boxShadow:'0 0 0 3px #0a0a0e' }}/>
          </div>
          <div className="oi-main" style={{ paddingLeft: 4 }}>
            <div className="title"><span className="proj">{s.project}</span>{s.branch && s.branch!=='main' && <span className="branch"> ({s.branch})</span>}{s.msg && <><span className="sep">·</span><span className="msg">{s.msg}</span></>}</div>
            {s.you && <div className="sub"><span className="you">You:</span> {s.you}</div>}
          </div>
          <div className="side" style={{ paddingRight: 16 }}>
            <span className={`oi-badge ${s.agent}`}>{s.agent === 'claude' ? 'CC' : 'CX'}</span>
            <span className="oi-badge">{s.terminal}</span>
          </div>
        </div>
      ))}
    </div>
  );
}

// Notification content — the PILL is the notification (Dynamic-Island style)
function ContentNotif({ kind, macbook, onClose }) {
  const bodyMap = {
    two: {
      state: 'waiting', label: 'Permission', right: 'Claude',
      title: 'Run shell command?',
      code: '$ git push origin refactor/claude-kernel-pid-monitor',
      sub: 'open-island · Ghostty',
      acts: [{k:'deny', l:'Deny', cls:'danger'}, {k:'ok', l:'Allow', cls:'primary'}],
      hint: <><kbd>↵</kbd> allow · <kbd>esc</kbd> deny</>,
    },
    three: {
      state: 'waiting', label: 'Permission', right: 'Codex',
      title: 'Edit SessionState.swift?',
      code: 'Sources/OpenIslandCore/Sessions/SessionState.swift\n+ 23 lines  − 8 lines  · L124–L156',
      sub: 'open-island · fix/external-island-width',
      acts: [{k:'deny', l:'Deny'}, {k:'once', l:'Allow once'}, {k:'always', l:'Always allow', cls:'primary'}],
      hint: <><kbd>1</kbd> deny · <kbd>2</kbd> once · <kbd>3</kbd> always</>,
    },
    jump: {
      state: 'waiting', label: 'Waiting', right: 'Gemini',
      title: 'Agent waiting on you',
      code: '> Should I use pnpm or npm?\n  1) pnpm\n  2) npm\n  3) Cancel',
      sub: 'my-webapp · WezTerm · pane 3',
      acts: [{k:'x', l:'Dismiss'}, {k:'jmp', l:'Jump to terminal ↗', cls:'primary'}],
    },
    done: {
      state: 'done', label: 'Done', right: 'Claude',
      title: 'Commit pushed to origin/main',
      code: '3 files changed, 47 insertions(+), 12 deletions(−)\n  M  Sources/OpenIslandCore/Sessions/SessionState.swift\n  M  Tests/OpenIslandCoreTests/SessionStateTests.swift\n  A  docs/hooks.md',
      sub: 'open-island · refactor/claude-kernel-pid-monitor',
      acts: [{k:'diff', l:'Open diff'}, {k:'jmp', l:'Jump back ↗', cls:'primary'}],
    },
  };
  const c = bodyMap[kind];
  if (!c) return null;
  return (
    <>
      <NotchRow state={c.state} label={c.label} right={c.right} macbook={macbook}/>
      <div className="oi-notif-body">
        <div className="title">{c.title}</div>
        <div className="sub">{c.sub}</div>
        <div className="code">{c.code}</div>
        <div className={`acts ${c.acts.length>2?'wrap':''}`}>
          {c.acts.map(a => <button key={a.k} className={`btn ${a.cls||''}`} onClick={()=>a.k==='x' && onClose?.()}>{a.l}</button>)}
        </div>
        {c.hint && <div className="hint">{c.hint}</div>}
      </div>
    </>
  );
}

// ---------- THE PILL — unified shape that morphs ----------
function Pill({ mode, state, label, right, macbook, width, height, children, onClick }) {
  return (
    <div className={`oi-pill ${macbook?'macbook':''}`} data-mode={mode}
         style={{ width, height }} onClick={onClick}>
      {/* physical notch (MacBook only) — pure black, sits on top of pill */}
      {macbook && (
        <div style={{ position:'absolute', top:0, left:'50%', transform:'translateX(-50%)', width:180, height:32, pointerEvents:'none' }}>
          <svg width="180" height="32" viewBox="0 0 180 32"><path d={`M 0 0 H 180 V 16 A 16 16 0 0 1 164 32 H 16 A 16 16 0 0 1 0 16 Z`} fill="#000"/></svg>
        </div>
      )}
      {children}
    </div>
  );
}

// ---------- Stages ----------
function MenuBar({ wallpaper = 'plum', children, tall = 720, appName='Xcode' }) {
  const bg = {
    plum: 'linear-gradient(135deg, #3c2344, #5f2e58 60%, #a8517a)',
    slate: 'linear-gradient(135deg, #1e2530, #3a4a5c)',
    forest: 'linear-gradient(135deg, #1b2e22, #3a5a3f)',
    sand: 'linear-gradient(135deg, #c8a576, #e8d4a0 60%, #f1ead9)',
  }[wallpaper];
  return (
    <div className="v7-stage" data-wall={wallpaper} style={{ background:bg, minHeight: tall }}>
      <div className="menubar">
        <b></b>
        <span className="m" style={{fontWeight:600}}>{appName}</span>
        <span className="m">File  Edit  View</span>
        <span className="spacer"/>
        <span className="time">Apr 20  14:22</span>
      </div>
      <div style={{ padding:'60px 40px', color:'rgba(255,255,255,0.4)', fontFamily:'JetBrains Mono, monospace', fontSize:12 }}>
        <div style={{ opacity:0.3 }}>// 点上面的 notch 开合 · 通知从同一个 pill 里长出来</div>
      </div>
      {children}
    </div>
  );
}

// ---------- Live interactive stage ----------
function LiveStage({ wallpaper, sessionCount, density, variant, macbook }) {
  const [mode, setMode] = useS('notch'); // notch | panel | notif
  const [notif, setNotif] = useS(null); // two | three | jump | done
  const [expandedId, setExpandedId] = useS('s1');
  const sessions = pickSessions(sessionCount);

  const waiting = sessions.filter(s=>s.state==='waiting').length;
  const running = sessions.filter(s=>s.state==='running').length;
  const notchState = waiting>0?'waiting':running>0?'running':'idle';
  const notchLabel = (mode==='notch' && !macbook) ? (waiting?`${waiting} waiting`:running?`${running} running`:null) : null;
  const notchRight = mode==='notch' ? (sessions.length?`×${sessions.length}`:null) : null;

  // Pill dimensions per mode
  const notchW = macbook ? 280 : (notchLabel ? 210 : (notchRight ? 140 : 100));
  const notchH = 32;
  const panelW = macbook ? 540 : 520;
  const panelH = 'auto';
  const notifW = macbook ? 480 : (notif==='three'?460:440);
  const notifH = 'auto';

  let width, height;
  if (mode === 'notch') { width = notchW; height = notchH; }
  else if (mode === 'notif') { width = notifW; height = undefined; }
  else { width = panelW; height = undefined; }

  const togglePanel = () => {
    if (mode === 'panel') setMode('notch');
    else { setNotif(null); setMode('panel'); }
  };
  const fire = (k) => { setNotif(k); setMode('notif'); };

  return (
    <div className="v7-live">
      <MenuBar wallpaper={wallpaper} tall={720}>
        <Pill mode={mode} macbook={macbook} width={width} height={height} onClick={mode==='notch' ? togglePanel : undefined}>
          {mode === 'notch' && (
            <ContentNotchOnly state={notchState} label={notchLabel} right={notchRight} macbook={macbook}/>
          )}
          {mode === 'panel' && (
            <div onClick={(e)=>e.stopPropagation()}>
              <div onClick={()=>setMode('notch')} style={{ cursor:'pointer' }}>
                <NotchRow state={notchState} label={null} right={<span style={{opacity:0.5}}>close ⌃</span>} macbook={macbook}/>
              </div>
              <UsageStrip/>
              {sessions.length === 0 ? (
                <div className="oi-empty">
                  <svg width="44" height="44" viewBox="0 0 44 44" fill="none"><path d="M 6 4 H 38 V 16 A 8 8 0 0 1 30 24 H 14 A 8 8 0 0 1 6 16 Z" fill="none" stroke="rgba(241,234,217,0.2)" strokeWidth="1.5" strokeDasharray="3 3"/></svg>
                  <div className="t">No active sessions</div>
                  <div className="h">Open a terminal and start <code>claude</code> or <code>codex</code>.</div>
                </div>
              ) : variant === 'grouped' ? (
                <GroupedRows sessions={sessions} expandedId={expandedId} onToggle={(id)=>setExpandedId(x=>x===id?null:id)} density={density}/>
              ) : variant === 'timeline' ? (
                <TimelineRows sessions={sessions} expandedId={expandedId} onToggle={(id)=>setExpandedId(x=>x===id?null:id)} density={density}/>
              ) : (
                <div className="oi-list">{sessions.map(s => <Row key={s.id} s={s} expanded={expandedId===s.id} onToggle={()=>setExpandedId(x=>x===s.id?null:s.id)} density={density}/>)}</div>
              )}
            </div>
          )}
          {mode === 'notif' && (
            <div onClick={(e)=>e.stopPropagation()}>
              <ContentNotif kind={notif} macbook={macbook} onClose={()=>setMode('notch')}/>
            </div>
          )}
        </Pill>
      </MenuBar>

      {/* Triggers */}
      <div className="v7-triggers">
        <div className="t-hd">pill mode</div>
        <button className={mode==='notch'?'on':''} onClick={()=>{ setNotif(null); setMode('notch'); }}>◦ notch</button>
        <button className={mode==='panel'?'on':''} onClick={()=>{ setNotif(null); setMode('panel'); }}>▼ session panel</button>
        <div className="t-hd" style={{ marginTop: 8 }}>fire notif</div>
        <button className={mode==='notif'&&notif==='two'?'on':''} onClick={()=>fire('two')}>permission 2-way</button>
        <button className={mode==='notif'&&notif==='three'?'on':''} onClick={()=>fire('three')}>permission 3-way</button>
        <button className={mode==='notif'&&notif==='jump'?'on':''} onClick={()=>fire('jump')}>jump back</button>
        <button className={mode==='notif'&&notif==='done'?'on':''} onClick={()=>fire('done')}>task done</button>
      </div>
    </div>
  );
}

// ---------- Static preview: show a pill in a given mode in a mini stage ----------
function MiniPreview({ wallpaper='plum', children, width, macbook }) {
  const bg = {
    plum: 'linear-gradient(135deg, #3c2344, #5f2e58 60%, #a8517a)',
    slate: 'linear-gradient(135deg, #1e2530, #3a4a5c)',
    forest: 'linear-gradient(135deg, #1b2e22, #3a5a3f)',
    sand: 'linear-gradient(135deg, #c8a576, #e8d4a0 60%, #f1ead9)',
  }[wallpaper];
  return (
    <div className="mini-stage" data-wall={wallpaper} style={{ background:bg }}>
      <div className={`oi-pill ${macbook?'macbook':''}`} data-mode="panel" style={{ width }}>
        {macbook && (
          <div style={{ position:'absolute', top:0, left:'50%', transform:'translateX(-50%)', width:180, height:32, pointerEvents:'none' }}>
            <svg width="180" height="32" viewBox="0 0 180 32"><path d={`M 0 0 H 180 V 16 A 16 16 0 0 1 164 32 H 16 A 16 16 0 0 1 0 16 Z`} fill="#000"/></svg>
          </div>
        )}
        {children}
      </div>
    </div>
  );
}

// ---------- Root ----------
function V7App() {
  const [wallpaper, setWall] = useS('plum');
  const [sessionCount, setSC] = useS(6);
  const [density, setDen] = useS('comfortable');
  const [variant, setVar] = useS('default');
  const [macbook, setMB] = useS(false);

  useE(() => {
    const h = (e) => {
      const p = document.getElementById('tweaks-v7');
      if (!p) return;
      if (e.data?.type === '__activate_edit_mode') p.style.display = 'block';
      if (e.data?.type === '__deactivate_edit_mode') p.style.display = 'none';
    };
    window.addEventListener('message', h);
    window.parent.postMessage({ type: '__edit_mode_available' }, '*');
    return () => window.removeEventListener('message', h);
  }, []);

  const sessions = pickSessions(sessionCount);

  return (
    <div className="app v3">
      <header className="topbar">
        <div className="brand"><span className="dot-v3"/><span>Open Island · v7 — pill as panel</span></div>
        <span className="meta mono">// 所有模块都是 notch 的延伸</span>
        <div className="spacer"/>
      </header>

      <main className="main main-v3">
        <section className="section" data-screen-label="00 Frame">
          <div className="section-head"><h2>Frame</h2><span className="tag mono">// v6 → v7</span><div className="line"/></div>
          <div className="assumption" style={{ display:'grid', gap:10 }}>
            <div>🪩 <b>核心:一个 pill</b>。notch / session 列表 / 通知都是<b>同一块形状</b>在长大 / 变形。顶边永远贴屏幕,不是 float 面板,没有内圆角。</div>
            <div>🧬 <b>形状基因来自 v6</b>:平顶 + 圆底。小的时候是 notch(flat-top + 16R bottom),大的时候是大 pill(flat-top + 22R bottom)。永远不变的是那条平直的顶边。</div>
            <div>💡 <b>通知就是 pill 里装了不同的内容</b>。像 Dynamic Island 展开显示来电 — 不是从 pill 下面再弹出一个 card,而是 pill 本体变高、装进通知。</div>
            <div>🖥️ <b>MacBook 物理刘海</b>:纯黑 notch 叠在 pill 顶部。Pill 比刘海宽,左右内容贴在刘海两侧。</div>
          </div>
        </section>

        <section className="section" data-screen-label="01 Live stage">
          <div className="section-head"><h2>01 · Live stage</h2><span className="tag mono">// 点 notch / 按钮,看 pill 变形</span><div className="line"/></div>
          <LiveStage wallpaper={wallpaper} sessionCount={sessionCount} density={density} variant={variant} macbook={macbook}/>
        </section>

        <section className="section" data-screen-label="02 Variations">
          <div className="section-head"><h2>02 · Session list · 3 变体</h2><span className="tag mono">// 都是同一只 pill,内容排布不同</span><div className="line"/></div>
          <div className="v7-grid three">
            <div className="v7-card">
              <div className="label"><span className="num">V1</span><span className="name">Default</span></div>
              <MiniPreview wallpaper={wallpaper} width={480} macbook={false}>
                <ContentSessions sessions={sessions} expandedId={null} onToggle={()=>{}} density={density} variant="default" state="waiting" label={null} right="×6"/>
              </MiniPreview>
              <div className="hint">一眼看全 · 点状态 + CC/CX + 终端徽章 + 年龄 · 展开看工具调用详情</div>
            </div>
            <div className="v7-card">
              <div className="label"><span className="num">V2</span><span className="name">Timeline</span></div>
              <MiniPreview wallpaper={wallpaper} width={480} macbook={false}>
                <ContentSessions sessions={sessions} expandedId={null} onToggle={()=>{}} density={density} variant="timeline" state="waiting" label={null} right="×6"/>
              </MiniPreview>
              <div className="hint">时间轴 · 左列 age + 状态珠子 · 看得到活动分布</div>
            </div>
            <div className="v7-card">
              <div className="label"><span className="num">V3</span><span className="name">Agent-grouped</span></div>
              <MiniPreview wallpaper={wallpaper} width={480} macbook={false}>
                <ContentSessions sessions={sessions} expandedId={null} onToggle={()=>{}} density={density} variant="grouped" state="waiting" label={null} right="×6"/>
              </MiniPreview>
              <div className="hint">Claude / Codex 分组 · 并行多 agent 更清晰</div>
            </div>
          </div>
        </section>

        <section className="section" data-screen-label="03 Notifications">
          <div className="section-head"><h2>03 · Notifications</h2><span className="tag mono">// pill 本体变成通知</span><div className="line"/></div>
          <div className="assumption" style={{ marginBottom: 18 }}>
            这些通知就像 Dynamic Island 的来电 / 计时器一样自然 — pill 本体变高、换上通知内容,没有额外的 card 也没有 drop shadow 单独堆出来。权限请求有三种 UI,因为不同 agent 表现不同。
          </div>
          <div className="v7-grid two">
            {[
              { k:'two', n:'N1', name:'Permission · 2-way', hint:'Claude Code 常见 — Allow / Deny。键盘 ↵ / esc 响应。', w:420 },
              { k:'three', n:'N2', name:'Permission · 3-way', hint:'破坏性操作 — Deny / Once / Always。键盘 1/2/3 响应。', w:460 },
              { k:'jump', n:'N3', name:'Jump back', hint:'Agent 在终端里 prompt,panel 响应不了 — 跳回精确 TTY / pane。', w:440 },
              { k:'done', n:'N4', name:'Task complete', hint:'Diff summary + Open diff / Jump back。2s 后自动收回 notch。', w:440 },
            ].map(c => (
              <div key={c.k} className="v7-card">
                <div className="label"><span className="num">{c.n}</span><span className="name">{c.name}</span></div>
                <MiniPreview wallpaper={wallpaper} width={c.w} macbook={false}>
                  <ContentNotif kind={c.k} macbook={false} onClose={()=>{}}/>
                </MiniPreview>
                <div className="hint">{c.hint}</div>
              </div>
            ))}
          </div>
        </section>

        <section className="section" data-screen-label="04 Empty / MacBook">
          <div className="section-head"><h2>04 · Empty 与 MacBook 物理刘海</h2><span className="tag mono">// 边界情况</span><div className="line"/></div>
          <div className="v7-grid two">
            <div className="v7-card">
              <div className="label"><span className="num">E1</span><span className="name">Zero sessions</span></div>
              <MiniPreview wallpaper={wallpaper} width={460} macbook={false}>
                <ContentSessions sessions={[]} expandedId={null} onToggle={()=>{}} density={density} variant="default" state="idle" label={null} right={null}/>
              </MiniPreview>
              <div className="hint">从未启动 claude/codex · 引导性空态。</div>
            </div>
            <div className="v7-card">
              <div className="label"><span className="num">M1</span><span className="name">MacBook — pill 包住物理刘海</span></div>
              <MiniPreview wallpaper={wallpaper} width={540} macbook={true}>
                <ContentSessions sessions={sessions.slice(0,4)} expandedId={null} onToggle={()=>{}} density={density} variant="default" state="waiting" label={null} right="×4"/>
              </MiniPreview>
              <div className="hint">纯黑 notch 叠在 pill 顶部。Pill 比刘海宽,内容在下方完整展示。左右 glyph / right-slot 贴在刘海两侧。</div>
            </div>
          </div>
        </section>
      </main>

      <aside className="tweaks" id="tweaks-v7">
        <h3>Tweaks</h3>
        <div className="grp"><div className="grp-title">Variant</div>
          <div className="btn-group">
            <button className={variant==='default'?'on':''} onClick={()=>setVar('default')}>V1 default</button>
            <button className={variant==='timeline'?'on':''} onClick={()=>setVar('timeline')}>V2 timeline</button>
            <button className={variant==='grouped'?'on':''} onClick={()=>setVar('grouped')}>V3 grouped</button>
          </div></div>
        <div className="grp"><div className="grp-title">Wallpaper</div>
          <div className="btn-group">{['plum','slate','forest','sand'].map(w => <button key={w} className={wallpaper===w?'on':''} onClick={()=>setWall(w)}>{w}</button>)}</div></div>
        <div className="grp"><div className="grp-title">Sessions</div>
          <div className="btn-group">{[0,1,3,6,8].map(n => <button key={n} className={sessionCount===n?'on':''} onClick={()=>setSC(n)}>{n}</button>)}</div></div>
        <div className="grp"><div className="grp-title">Density</div>
          <div className="btn-group"><button className={density==='comfortable'?'on':''} onClick={()=>setDen('comfortable')}>comfortable</button><button className={density==='compact'?'on':''} onClick={()=>setDen('compact')}>compact</button></div></div>
        <div className="grp"><div className="grp-title">Device (live stage)</div>
          <div className="btn-group"><button className={!macbook?'on':''} onClick={()=>setMB(false)}>external</button><button className={macbook?'on':''} onClick={()=>setMB(true)}>MacBook notch</button></div></div>
        <div className="grp"><div className="grp-title">Note</div>
          <div className="hint" style={{ lineHeight:1.55 }}>Pill = 唯一形状。<br/>Notch / session / 通知 = 同一 pill 的不同状态。<br/>顶边永远平直贴屏幕。</div>
        </div>
      </aside>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<V7App/>);
