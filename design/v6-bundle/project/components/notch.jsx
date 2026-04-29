// Notch overlay — full animated timeline
// States: idle -> running -> notify (permission) -> done -> collapse
// Direction A (liquid), B (pixel), C (terminal) render differently

const { useEffect, useState, useRef } = window.React ? window.React : React;

function NotchOverlay({ direction = 'A', state = 'idle', agent = 'claude', speed = 1, theme = 'default' }) {
  // Compute notch dims per state
  const dims = {
    idle:     { w: 180, h: 32,  r: 18 },
    running:  { w: 260, h: 32,  r: 18 },
    notify:   { w: 460, h: 112, r: 26 },
    error:    { w: 320, h: 64,  r: 22 },
    done:     { w: 240, h: 32,  r: 18 },
    expanded: { w: 520, h: 180, r: 28 },
  }[state] || { w: 180, h: 32, r: 18 };

  const color = AGENT_COLORS[agent] || '#8b5cf6';
  const transition = `all ${420/speed}ms cubic-bezier(.25, 1.4, .3, 1)`;

  return (
    <div style={{
      position: 'absolute', top: 0, left: '50%',
      transform: 'translateX(-50%)',
      background: '#000',
      width: dims.w, height: dims.h,
      borderRadius: `0 0 ${dims.r}px ${dims.r}px`,
      transition,
      overflow: 'hidden',
      zIndex: 5,
      boxShadow: direction === 'A' ? `0 4px 24px rgba(0,0,0,0.5), inset 0 -1px 0 ${color}33` : 'none',
    }}>
      <NotchContent direction={direction} state={state} agent={agent} color={color} speed={speed} />
    </div>
  );
}

function NotchContent({ direction, state, agent, color, speed }) {
  // Decide layout
  if (state === 'idle') return <NotchIdle direction={direction} color={color} speed={speed} />;
  if (state === 'running') return <NotchRunning direction={direction} color={color} agent={agent} speed={speed} />;
  if (state === 'notify') return <NotchNotify direction={direction} color={color} agent={agent} speed={speed} />;
  if (state === 'error') return <NotchError direction={direction} speed={speed} />;
  if (state === 'done') return <NotchDone direction={direction} color={color} speed={speed} />;
  if (state === 'expanded') return <NotchExpanded direction={direction} color={color} agent={agent} speed={speed} />;
  return null;
}

// ----- Idle: minimal dot -----
function NotchIdle({ direction, color, speed }) {
  if (direction === 'B') {
    return (
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '100%', gap: 4 }}>
        <div style={{ width: 4, height: 4, background: '#39ff88' }} />
        <div style={{ width: 4, height: 4, background: '#39ff88', animation: 'blink 0.8s steps(2) infinite' }} />
        <div style={{ width: 4, height: 4, background: '#39ff88' }} />
      </div>
    );
  }
  if (direction === 'C') {
    return (
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '100%', color: '#d97742', fontFamily: "'JetBrains Mono', monospace", fontSize: 11, letterSpacing: '0.15em' }}>
        <span>~ idle ~</span>
      </div>
    );
  }
  return (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '100%', gap: 8 }}>
      <div style={{
        width: 8, height: 8, borderRadius: '50%',
        background: `radial-gradient(circle at 30% 30%, #fff, #aaa)`,
        opacity: 0.7,
        animation: `breathe ${2.4/speed}s ease-in-out infinite`,
      }} />
    </div>
  );
}

// ----- Running: agent icon + thinking dots / progress -----
function NotchRunning({ direction, color, agent, speed }) {
  if (direction === 'B') {
    return (
      <div style={{ display: 'flex', alignItems: 'center', height: '100%', padding: '0 10px', gap: 8, color: '#39ff88', fontFamily: "'VT323', monospace" }}>
        <div style={{ width: 10, height: 10, background: color, animation: `blink ${0.5/speed}s steps(2) infinite`, border: '1px solid rgba(255,255,255,0.2)' }} />
        <div style={{ fontSize: 16, letterSpacing: 1, lineHeight: 1 }}>{agent.toUpperCase()}</div>
        <div style={{ marginLeft: 'auto', display: 'flex', gap: 2 }}>
          {[0,1,2,3,4].map(i => (
            <div key={i} style={{ width: 4, height: 10, background: '#39ff88', opacity: 0.15 + (i/5)*0.85, animation: `blink ${0.4/speed}s steps(2) infinite`, animationDelay: `${i*0.08}s` }} />
          ))}
        </div>
      </div>
    );
  }
  if (direction === 'C') {
    return (
      <div style={{ display: 'flex', alignItems: 'center', height: '100%', padding: '0 12px', gap: 10, color: '#f4efe6', fontFamily: "'JetBrains Mono', monospace", fontSize: 11 }}>
        <span style={{ color: '#d97742' }}>{'>'}</span>
        <span>{agent}</span>
        <span style={{ color: '#8a7f6d' }}>running</span>
        <span style={{ marginLeft: 'auto', display: 'inline-flex', gap: 2 }}>
          {[0,1,2].map(i => <span key={i} style={{ animation: `blink ${1/speed}s steps(2) infinite`, animationDelay: `${i*0.15}s` }}>·</span>)}
        </span>
      </div>
    );
  }
  // A: Liquid
  return (
    <div style={{ display: 'flex', alignItems: 'center', height: '100%', padding: '0 10px', gap: 10 }}>
      <AgentIcon name={agent} size={22} direction="A" />
      <div style={{ display: 'flex', gap: 3 }}>
        {[0,1,2].map(i => (
          <div key={i} style={{
            width: 5, height: 5, borderRadius: '50%',
            background: color,
            animation: `breathe ${0.9/speed}s ease-in-out infinite`,
            animationDelay: `${i*0.15}s`,
            boxShadow: `0 0 6px ${color}`,
          }} />
        ))}
      </div>
      <div style={{ marginLeft: 'auto', fontFamily: "'JetBrains Mono', monospace", fontSize: 10, color: 'rgba(255,255,255,0.55)' }}>
        3.2k tok
      </div>
    </div>
  );
}

// ----- Notify: permission request expanded -----
function NotchNotify({ direction, color, agent, speed }) {
  if (direction === 'B') {
    return (
      <div style={{ padding: '14px 16px', color: '#39ff88', fontFamily: "'VT323', monospace" }}>
        <div style={{ fontSize: 12, color: '#ffbf3c', marginBottom: 6, letterSpacing: 2 }}>▶ PERMISSION REQUEST</div>
        <div style={{ fontSize: 18, color: '#fff', lineHeight: 1.2, marginBottom: 10 }}>
          {agent.toUpperCase()} wants to <span style={{ color: '#ff5bd1' }}>write_file</span>
          <br /><span style={{ fontSize: 14, color: '#39ff88' }}>./src/App.swift</span>
        </div>
        <div style={{ display: 'flex', gap: 8 }}>
          <button style={{ flex: 1, background: '#39ff88', color: '#08120c', border: 0, padding: '6px 0', fontFamily: 'inherit', fontSize: 14, letterSpacing: 2 }}>[ALLOW]</button>
          <button style={{ flex: 1, background: 'transparent', color: '#ff5bd1', border: '1px solid #ff5bd1', padding: '6px 0', fontFamily: 'inherit', fontSize: 14, letterSpacing: 2 }}>[DENY]</button>
        </div>
      </div>
    );
  }
  if (direction === 'C') {
    return (
      <div style={{ padding: '12px 14px', color: '#f4efe6', fontFamily: "'JetBrains Mono', monospace", fontSize: 11, lineHeight: 1.5 }}>
        <div style={{ color: '#d97742', marginBottom: 2 }}>┌─ permission ─────────────────┐</div>
        <div>│ <b>{agent}</b> → write_file <span style={{ color: '#8a7f6d' }}>./App.swift</span></div>
        <div style={{ color: '#8a7f6d' }}>│ proceed? y/N</div>
        <div style={{ display: 'flex', gap: 8, marginTop: 6 }}>
          <span style={{ border: '1px solid #f4efe6', padding: '2px 10px' }}>Y allow</span>
          <span style={{ border: '1px solid #8a7f6d', padding: '2px 10px', color: '#8a7f6d' }}>N deny</span>
        </div>
      </div>
    );
  }
  // A: liquid
  return (
    <div style={{ display: 'flex', alignItems: 'center', height: '100%', padding: '14px 18px', gap: 14 }}>
      <AgentIcon name={agent} size={56} direction="A" />
      <div style={{ flex: 1, color: '#fff' }}>
        <div style={{ fontSize: 10, letterSpacing: '0.15em', color: color, textTransform: 'uppercase', marginBottom: 3 }}>permission</div>
        <div style={{ fontSize: 14, lineHeight: 1.3 }}>
          <span style={{ fontWeight: 600 }}>{agent}</span> wants to <span style={{ color }}>write</span>
        </div>
        <div style={{ fontFamily: "'JetBrains Mono', monospace", fontSize: 11, color: 'rgba(255,255,255,0.6)', marginTop: 2 }}>./src/App.swift</div>
      </div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
        <button style={{
          background: color, color: '#fff', border: 0, borderRadius: 8,
          padding: '6px 14px', fontSize: 12, fontWeight: 600, cursor: 'pointer',
          boxShadow: `0 0 0 1px rgba(255,255,255,0.15) inset`,
        }}>Allow</button>
        <button style={{
          background: 'rgba(255,255,255,0.08)', color: '#fff', border: '1px solid rgba(255,255,255,0.12)', borderRadius: 8,
          padding: '6px 14px', fontSize: 12, cursor: 'pointer',
        }}>Deny</button>
      </div>
    </div>
  );
}

// ----- Error -----
function NotchError({ direction, speed }) {
  const msg = 'session bridge disconnected';
  if (direction === 'B') {
    return (
      <div style={{ height: '100%', display: 'flex', alignItems: 'center', padding: '0 12px', gap: 10, color: '#ff5bd1', fontFamily: "'VT323', monospace", animation: `drift ${0.2/speed}s infinite` }}>
        <div style={{ fontSize: 18 }}>✕</div>
        <div style={{ fontSize: 14, lineHeight: 1.1 }}>ERROR<br /><span style={{ color: '#fff', fontSize: 12 }}>{msg}</span></div>
      </div>
    );
  }
  if (direction === 'C') {
    return (
      <div style={{ height: '100%', display: 'flex', alignItems: 'center', padding: '0 14px', gap: 10, color: '#ff5bd1', fontFamily: "'JetBrains Mono', monospace", fontSize: 11 }}>
        <span>[!]</span>
        <div><div>err: {msg}</div><div style={{ color: '#8a7f6d' }}>press r to retry</div></div>
      </div>
    );
  }
  return (
    <div style={{ height: '100%', display: 'flex', alignItems: 'center', padding: '0 16px', gap: 12 }}>
      <div style={{
        width: 28, height: 28, borderRadius: '50%',
        background: 'radial-gradient(circle at 30% 30%, #ff8fa8, #ef4444)',
        boxShadow: '0 0 20px #ef444477',
        animation: `breathe ${0.9/speed}s ease-in-out infinite`,
      }} />
      <div style={{ color: '#fff' }}>
        <div style={{ fontSize: 12, fontWeight: 600 }}>Bridge disconnected</div>
        <div style={{ fontSize: 11, color: 'rgba(255,255,255,0.55)' }}>Tap to retry</div>
      </div>
    </div>
  );
}

// ----- Done -----
function NotchDone({ direction, color, speed }) {
  if (direction === 'B') {
    return (
      <div style={{ height: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, color: '#39ff88', fontFamily: "'VT323', monospace", fontSize: 16, letterSpacing: 2 }}>
        ✓ DONE
      </div>
    );
  }
  if (direction === 'C') {
    return (
      <div style={{ height: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6, color: '#d97742', fontFamily: "'JetBrains Mono', monospace", fontSize: 11 }}>
        <span>◆</span><span>complete</span><span style={{ color: '#8a7f6d' }}>(4.2s)</span>
      </div>
    );
  }
  return (
    <div style={{ height: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8 }}>
      <div style={{
        width: 18, height: 18, borderRadius: '50%',
        background: `linear-gradient(135deg, ${color}, ${color}aa)`,
        display: 'grid', placeItems: 'center', color: '#fff',
        animation: `pop ${0.4/speed}s cubic-bezier(.25,1.6,.4,1)`,
      }}>
        <svg width="10" height="10" viewBox="0 0 10 10"><path d="M2 5 L4 7 L8 3" stroke="#fff" strokeWidth="1.6" fill="none" strokeLinecap="round" /></svg>
      </div>
      <span style={{ color: '#fff', fontSize: 12 }}>Complete</span>
    </div>
  );
}

// ----- Expanded: full control center preview -----
function NotchExpanded({ direction, color, agent, speed }) {
  if (direction === 'B') {
    return (
      <div style={{ padding: 14, color: '#39ff88', fontFamily: "'VT323', monospace", height: '100%' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', color: '#ffbf3c', fontSize: 12, letterSpacing: 2, marginBottom: 8 }}>
          <span>▶ SESSIONS · 3</span><span>USAGE 62%</span>
        </div>
        {['claude','codex','ghostty'].map((a, i) => (
          <div key={a} style={{ display:'flex', alignItems:'center', gap:10, fontSize: 16, padding: '3px 0', borderBottom: i < 2 ? '1px dashed #1a2f1a' : 'none' }}>
            <span style={{ color: AGENT_COLORS[a] }}>█</span>
            <span style={{ color: '#fff' }}>{a}</span>
            <span style={{ color: '#39ff88', marginLeft: 'auto' }}>{['idle','busy','wait'][i]}</span>
          </div>
        ))}
      </div>
    );
  }
  if (direction === 'C') {
    return (
      <div style={{ padding: 12, color: '#f4efe6', fontFamily: "'JetBrains Mono', monospace", fontSize: 11, lineHeight: 1.5 }}>
        <div style={{ color: '#d97742' }}>~/open-island $ sessions</div>
        <div style={{ color: '#8a7f6d' }}>──────────────────────────────</div>
        <div>● <b>claude-code</b>   <span style={{ color: '#8a7f6d' }}>running · 3.2k tok</span></div>
        <div>○ codex         <span style={{ color: '#8a7f6d' }}>idle</span></div>
        <div>◎ ghostty       <span style={{ color: '#ffbf3c' }}>waiting · permission</span></div>
        <div style={{ color: '#8a7f6d', marginTop: 4 }}>[↵ open] [tab cycle] [q quit]</div>
      </div>
    );
  }
  return (
    <div style={{ padding: 14, height: '100%', color: '#fff' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 10 }}>
        <div style={{ fontSize: 11, letterSpacing: '0.15em', color: 'rgba(255,255,255,0.55)', textTransform: 'uppercase' }}>Sessions</div>
        <div style={{ fontFamily: "'JetBrains Mono', monospace", fontSize: 10, color: 'rgba(255,255,255,0.55)' }}>5h · 62%</div>
      </div>
      {[
        { a: 'claude',  s: 'running', t: '3.2k tok' },
        { a: 'codex',   s: 'idle',    t: '—' },
        { a: 'ghostty', s: 'waiting', t: 'permission' },
      ].map((row, i) => (
        <div key={row.a} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '6px 4px', borderTop: i ? '1px solid rgba(255,255,255,0.06)' : 'none' }}>
          <AgentIcon name={row.a} size={26} direction="A" />
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: 12, fontWeight: 500 }}>{row.a}</div>
            <div style={{ fontSize: 10, color: 'rgba(255,255,255,0.5)', fontFamily: "'JetBrains Mono', monospace" }}>{row.t}</div>
          </div>
          <StatusIcon state={row.s} direction="A" size={16} />
        </div>
      ))}
    </div>
  );
}

Object.assign(window, { NotchOverlay });
