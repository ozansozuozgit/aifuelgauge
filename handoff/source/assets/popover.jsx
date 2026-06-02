/* global React, Icon, LANES, RESETS, SESSIONS, SERVERS, ROUTES, STATE_VAR, STATE_LABEL, ArcGauge, Meter, TrustChip, Sparkline */
const { useState } = React;

// Brand mark — a small gauge glyph (arc + needle)
function BrandMark({ size = 22 }) {
  const s = size, c = s / 2, r = s / 2 - 2.2;
  return (
    <svg width={s} height={s} viewBox={`0 0 ${s} ${s}`} style={{ display: 'block' }}>
      <g transform={`rotate(110 ${c} ${c})`}>
        <circle cx={c} cy={c} r={r} fill="none" stroke="var(--accent)" strokeWidth="2.1"
          strokeLinecap="round" strokeDasharray={`${2 * Math.PI * r * 0.74} ${2 * Math.PI * r}`} />
      </g>
      <line x1={c} y1={c} x2={c + r * 0.62} y2={c - r * 0.42} stroke="var(--accent)" strokeWidth="2.1" strokeLinecap="round" />
      <circle cx={c} cy={c} r="1.9" fill="var(--accent)" />
    </svg>
  );
}

function StatePill({ state, label }) {
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 6,
      fontSize: 11.5, fontWeight: 600, color: 'var(--text-2)',
      padding: '4px 10px 4px 8px', borderRadius: 999,
      background: `color-mix(in oklch, ${STATE_VAR[state]} 13%, transparent)`,
      border: `1px solid color-mix(in oklch, ${STATE_VAR[state]} 26%, transparent)`,
    }}>
      <span style={{ width: 7, height: 7, borderRadius: 999, background: STATE_VAR[state],
        boxShadow: `0 0 0 3px color-mix(in oklch, ${STATE_VAR[state]} 22%, transparent)` }} />
      {label}
    </span>
  );
}

// ---------- Hero: featured lane + focus chooser ----------
const PROVIDER_KEYS = [
  { key: 'auto', label: 'Auto' },
  { key: 'Claude Code', label: 'Claude' },
  { key: 'Codex', label: 'Codex' },
  { key: 'Cursor', label: 'Cursor' },
  { key: 'OpenRouter', label: 'OpenRouter' },
  { key: 'OpenAI', label: 'OpenAI' },
];

function representativeLane(lanes, provider) {
  const ls = lanes.filter((l) => l.provider === provider && l.percent != null);
  if (!ls.length) return lanes.find((l) => l.provider === provider) || null;
  return ls.sort((a, b) => b.percent - a.percent)[0];
}

function FocusPill({ focus, setFocus }) {
  const [open, setOpen] = useState(false);
  const lbl = PROVIDER_KEYS.find((p) => p.key === focus)?.label || 'Auto';
  return (
    <div style={{ position: 'relative' }}>
      <button onClick={() => setOpen(!open)}
        style={{ display: 'inline-flex', alignItems: 'center', gap: 5, padding: '4px 8px 4px 7px',
          borderRadius: 8, border: '1px solid var(--border)', background: 'var(--surface-raised)',
          fontSize: 11.5, fontWeight: 600, color: 'var(--text-2)' }}>
        <Icon name={focus === 'auto' ? 'bolt' : 'pin'} size={12} stroke={2}
          style={{ color: focus === 'auto' ? 'var(--accent)' : 'var(--text-2)' }} />
        {lbl}
        <Icon name="chevDown" size={13} style={{ color: 'var(--text-3)' }} />
      </button>
      {open && (
        <>
          <div onClick={() => setOpen(false)} style={{ position: 'fixed', inset: 0, zIndex: 20 }} />
          <div style={{ position: 'absolute', top: 'calc(100% + 5px)', right: 0, zIndex: 21, minWidth: 156,
            background: 'var(--surface-raised)', border: '1px solid var(--border-strong)',
            borderRadius: 10, boxShadow: 'var(--shadow-pop)', padding: 5 }}>
            <div style={{ fontSize: 9.5, fontWeight: 700, letterSpacing: 0.4, color: 'var(--text-3)', textTransform: 'uppercase', padding: '5px 8px 4px' }}>Feature in hero</div>
            {PROVIDER_KEYS.map((p) => (
              <button key={p.key} onClick={() => { setFocus(p.key); setOpen(false); }}
                style={{ display: 'flex', alignItems: 'center', gap: 8, width: '100%', padding: '6px 8px', borderRadius: 7,
                  border: 'none', textAlign: 'left', fontSize: 12.5, fontWeight: focus === p.key ? 600 : 500,
                  background: focus === p.key ? 'var(--accent-soft)' : 'transparent', color: focus === p.key ? 'var(--accent)' : 'var(--text)' }}
                onMouseEnter={(e) => { if (focus !== p.key) e.currentTarget.style.background = 'var(--surface-hover)'; }}
                onMouseLeave={(e) => { if (focus !== p.key) e.currentTarget.style.background = 'transparent'; }}>
                <Icon name={p.key === 'auto' ? 'bolt' : 'pin'} size={13} stroke={2} style={{ opacity: p.key === 'auto' ? 1 : 0.7 }} />
                {p.label === 'Auto' ? 'Auto · tightest lane' : p.label}
                {focus === p.key && <Icon name="check" size={13} stroke={2.2} style={{ marginLeft: 'auto' }} />}
              </button>
            ))}
          </div>
        </>
      )}
    </div>
  );
}

function HeroCard({ lane, recommend, focus, setFocus }) {
  const auto = focus === 'auto';
  return (
    <div style={{
      display: 'flex', gap: 16, alignItems: 'center',
      padding: 16, borderRadius: 'var(--radius-lg)',
      background: 'var(--surface-raised)',
      border: '1px solid var(--border)',
      boxShadow: '0 1px 2px rgba(0,0,0,0.04)',
    }}>
      <div style={{ position: 'relative', flexShrink: 0 }}>
        <ArcGauge percent={lane.percent} state={lane.state} size={132} stroke={12}>
          <div style={{ fontFamily: 'var(--font-mono)', fontSize: 30, fontWeight: 600, color: STATE_VAR[lane.state], lineHeight: 1 }}>
            {Math.round((lane.percent ?? 0) * 100)}<span style={{ fontSize: 15 }}>%</span>
          </div>
          <div style={{ fontSize: 10.5, fontWeight: 600, color: 'var(--text-3)', marginTop: 3, letterSpacing: 0.2 }}>USED</div>
        </ArcGauge>
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 4 }}>
          <span style={{ fontSize: 10.5, fontWeight: 700, letterSpacing: 0.6, color: 'var(--text-3)', textTransform: 'uppercase' }}>
            {auto ? 'Tightest lane' : 'Watching'}
          </span>
          <div style={{ marginLeft: 'auto' }}><FocusPill focus={focus} setFocus={setFocus} /></div>
        </div>
        <div style={{ fontSize: 18, fontWeight: 650, letterSpacing: -0.2 }}>{lane.provider}</div>
        <div style={{ fontSize: 12.5, color: 'var(--text-2)', marginTop: 1 }}>{lane.window} · {lane.plan}</div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 7, marginTop: 11,
          padding: '7px 10px', borderRadius: 9,
          background: 'color-mix(in oklch, var(--safe) 11%, transparent)',
          border: '1px solid color-mix(in oklch, var(--safe) 22%, transparent)' }}>
          <Icon name="bolt" size={14} stroke={2} style={{ color: 'var(--safe)', flexShrink: 0 }} />
          <span style={{ fontSize: 12, fontWeight: 550, color: 'var(--text)', lineHeight: 1.3 }}>
            {recommend}
          </span>
        </div>
        {lane.resetIn && (
          <div style={{ display: 'flex', alignItems: 'center', gap: 5, marginTop: 9, color: 'var(--text-2)', fontSize: 11.5 }}>
            <Icon name="clock" size={13} stroke={1.9} />
            Resets in <strong style={{ color: STATE_VAR[lane.state], fontFamily: 'var(--font-mono)', fontWeight: 600 }}>{lane.resetIn}</strong>
          </div>
        )}
      </div>
    </div>
  );
}

// ---------- Top-3 hero (egalitarian multi-gauge) ----------
function TrioHero({ lanes, onPick }) {
  const top = [...lanes].filter((l) => l.percent != null).sort((a, b) => b.percent - a.percent).slice(0, 3);
  return (
    <div style={{ display: 'flex', gap: 8, padding: 12, borderRadius: 'var(--radius-lg)',
      background: 'var(--surface-raised)', border: '1px solid var(--border)', boxShadow: '0 1px 2px rgba(0,0,0,0.04)' }}>
      {top.map((lane) => (
        <button key={lane.id} onClick={() => onPick && onPick(lane.provider)}
          style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6,
            padding: '10px 6px', borderRadius: 'var(--radius)', border: 'none', background: 'transparent',
            transition: 'background .15s' }}
          onMouseEnter={(e) => { e.currentTarget.style.background = 'var(--surface-hover)'; }}
          onMouseLeave={(e) => { e.currentTarget.style.background = 'transparent'; }}>
          <ArcGauge percent={lane.percent} state={lane.state} size={86} stroke={8}>
            <div style={{ fontFamily: 'var(--font-mono)', fontSize: 19, fontWeight: 600, color: STATE_VAR[lane.state], lineHeight: 1 }}>
              {Math.round(lane.percent * 100)}<span style={{ fontSize: 11 }}>%</span>
            </div>
          </ArcGauge>
          <div style={{ textAlign: 'center' }}>
            <div style={{ fontSize: 12.5, fontWeight: 650 }}>{lane.provider}</div>
            <div style={{ fontSize: 10.5, color: 'var(--text-3)' }}>{lane.window}</div>
            {lane.resetIn && (
              <div style={{ display: 'inline-flex', alignItems: 'center', gap: 3, marginTop: 3, fontSize: 10.5,
                fontFamily: 'var(--font-mono)', fontWeight: 600, color: STATE_VAR[lane.state] }}>
                <Icon name="clock" size={10} /> {lane.resetIn}
              </div>
            )}
          </div>
        </button>
      ))}
    </div>
  );
}

// ---------- Lane row ----------
function LaneRow({ lane, showDetails, dragMode, onPin, isFocused }) {
  const [copied, setCopied] = useState(false);
  const doCopy = () => { setCopied(true); setTimeout(() => setCopied(false), 1100); };
  return (
    <div style={{
      display: 'flex', flexDirection: 'column', gap: showDetails ? 9 : 7,
      padding: '11px 12px', borderRadius: 'var(--radius)',
      transition: 'background .15s',
    }}
      onMouseEnter={(e) => { e.currentTarget.style.background = 'var(--surface-hover)'; }}
      onMouseLeave={(e) => { e.currentTarget.style.background = 'transparent'; }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
        {dragMode && <Icon name="grip" size={15} style={{ color: 'var(--text-3)', cursor: 'grab', flexShrink: 0 }} />}
        <span style={{ width: 8, height: 8, borderRadius: 999, background: STATE_VAR[lane.state], flexShrink: 0,
          boxShadow: `0 0 0 3px color-mix(in oklch, ${STATE_VAR[lane.state]} 18%, transparent)` }} />
        <div style={{ minWidth: 0, flex: 1 }}>
          <div style={{ display: 'flex', alignItems: 'baseline', gap: 7 }}>
            <span style={{ fontSize: 13, fontWeight: 600, whiteSpace: 'nowrap' }}>{lane.provider}</span>
            <span style={{ fontSize: 11.5, color: 'var(--text-3)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{lane.window}</span>
          </div>
        </div>
        <span style={{ fontFamily: 'var(--font-mono)', fontSize: 13, fontWeight: 600,
          color: lane.state === 'unknown' ? 'var(--text-2)' : 'var(--text)', whiteSpace: 'nowrap' }}>{lane.used}</span>
        {onPin && (
          <button className="row-act" onClick={() => onPin(lane.provider)} title={isFocused ? 'Featured in hero' : 'Feature in hero'} style={iconBtn}>
            <Icon name="pin" size={14} stroke={2} style={{ color: isFocused ? 'var(--accent)' : 'var(--text-3)' }} />
          </button>
        )}
        <button className="row-act" onClick={doCopy} title="Copy lane receipt"
          style={iconBtn}>
          <Icon name={copied ? 'check' : 'copy'} size={14} style={{ color: copied ? 'var(--safe)' : 'var(--text-3)' }} />
        </button>
        <button className="row-act" title="Open provider dashboard" style={iconBtn}>
          <Icon name="external" size={14} style={{ color: 'var(--text-3)' }} />
        </button>
      </div>

      <div style={{ display: 'flex', alignItems: 'center', gap: 10, paddingLeft: dragMode ? 33 : 18 }}>
        {lane.percent != null
          ? <Meter percent={lane.percent} state={lane.state} />
          : <div style={{ flex: 1, height: 6, borderRadius: 6, background: 'var(--track)',
              backgroundImage: 'repeating-linear-gradient(45deg, transparent, transparent 4px, color-mix(in oklch, var(--unknown) 30%, transparent) 4px, color-mix(in oklch, var(--unknown) 30%, transparent) 8px)' }} />}
        <span style={{ fontSize: 11, fontWeight: 600, color: STATE_VAR[lane.state], minWidth: 78, textAlign: 'right' }}>{lane.meterLabel}</span>
      </div>

      {showDetails && (
        <div style={{ paddingLeft: dragMode ? 33 : 18, display: 'flex', flexDirection: 'column', gap: 8 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            {lane.trend.length >= 2 && <Sparkline data={lane.trend} state={lane.state} width={120} height={22} />}
            <TrustChip confidence={lane.confidence} />
            {lane.resetIn && (
              <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4, fontSize: 11, color: 'var(--text-2)' }}>
                <Icon name="clock" size={12} /> {lane.resetIn}
              </span>
            )}
          </div>
          {lane.pace && (
            <div style={{ display: 'flex', gap: 6, alignItems: 'flex-start' }}>
              <Icon name={lane.pace.includes('warning') ? 'warn' : 'check'} size={13} stroke={2}
                style={{ color: lane.pace.includes('warning') ? 'var(--caution)' : STATE_VAR[lane.state], marginTop: 1, flexShrink: 0 }} />
              <span style={{ fontSize: 11.5, color: 'var(--text-2)', lineHeight: 1.35 }}>{lane.pace}</span>
            </div>
          )}
          <div style={{ display: 'flex', gap: 6, alignItems: 'flex-start' }}>
            <Icon name="info" size={13} style={{ color: 'var(--text-3)', marginTop: 1, flexShrink: 0 }} />
            <span style={{ fontSize: 11.5, color: 'var(--text-3)', lineHeight: 1.35 }}>{lane.explanation}</span>
          </div>
        </div>
      )}
    </div>
  );
}

const iconBtn = {
  display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
  width: 26, height: 26, borderRadius: 7, border: 'none', background: 'transparent',
  flexShrink: 0,
};

function Segmented({ options, value, onChange }) {
  return (
    <div style={{ display: 'inline-flex', padding: 2, gap: 2, borderRadius: 8, background: 'var(--track)' }}>
      {options.map((o) => (
        <button key={o.value} onClick={() => onChange(o.value)}
          style={{
            border: 'none', borderRadius: 6, padding: '3px 11px', fontSize: 11.5, fontWeight: 600,
            background: value === o.value ? 'var(--surface-raised)' : 'transparent',
            color: value === o.value ? 'var(--text)' : 'var(--text-2)',
            boxShadow: value === o.value ? '0 1px 2px rgba(0,0,0,0.12)' : 'none',
            transition: 'all .15s',
          }}>{o.label}</button>
      ))}
    </div>
  );
}

// ---------- Reset timeline ----------
function ResetStrip({ items }) {
  return (
    <div style={{ display: 'flex', gap: 8 }}>
      {items.map((it, i) => (
        <div key={it.id} style={{
          flex: 1, padding: '8px 11px', borderRadius: 'var(--radius)',
          background: 'var(--surface-raised)', border: '1px solid var(--border)',
        }}>
          <div style={{ fontSize: 9, fontWeight: 700, letterSpacing: 0.5, color: 'var(--text-3)', textTransform: 'uppercase' }}>
            {i === 0 ? 'Next reset' : 'Reset'}
          </div>
          <div style={{ fontFamily: 'var(--font-mono)', fontSize: 16, fontWeight: 600, color: STATE_VAR[it.state], marginTop: 2 }}>{it.value}</div>
          <div style={{ fontSize: 11, fontWeight: 550, color: 'var(--text-2)', marginTop: 1 }}>{it.label}</div>
        </div>
      ))}
    </div>
  );
}

// ---------- Workbench ----------
function Workbench() {
  const [open, setOpen] = useState(false);
  return (
    <div style={{ borderRadius: 'var(--radius)', background: 'var(--surface-sunken)', border: '1px solid var(--border)', overflow: 'hidden' }}>
      <button onClick={() => setOpen(!open)} style={{
        display: 'flex', alignItems: 'center', gap: 8, width: '100%', padding: '10px 12px',
        border: 'none', background: 'transparent', color: 'var(--text)',
      }}>
        <Icon name="terminal" size={14} style={{ color: 'var(--text-2)' }} />
        <span style={{ fontSize: 12, fontWeight: 650 }}>Workbench</span>
        <span style={{ fontSize: 11, color: 'var(--text-3)' }}>{SESSIONS.length} sessions · {SERVERS.length} servers · {ROUTES.length} routes</span>
        <span style={{ marginLeft: 'auto' }}><Icon name={open ? 'chevUp' : 'chevDown'} size={15} style={{ color: 'var(--text-3)' }} /></span>
      </button>
      {open && (
        <div style={{ padding: '2px 12px 12px', display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 14, animation: 'fadeIn .2s' }}>
          <div style={{ gridColumn: '1 / -1', height: 1, background: 'var(--divider)' }} />
          <WBGroup title="Sessions">
            {SESSIONS.map((s) => (
              <div key={s.id} style={{ display: 'flex', alignItems: 'center', gap: 7, padding: '4px 0' }}>
                <span style={{ fontSize: 9, fontWeight: 700, color: 'var(--text-2)', width: 26, height: 17, borderRadius: 5,
                  display: 'inline-flex', alignItems: 'center', justifyContent: 'center', background: 'var(--track)' }}>{s.provider}</span>
                <div style={{ minWidth: 0 }}>
                  <div style={{ fontSize: 11.5, fontWeight: 600, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{s.project}</div>
                  <div style={{ fontSize: 10, color: 'var(--text-3)' }}>
                    <span style={{ color: s.status === 'active' ? 'var(--safe)' : 'var(--text-3)' }}>{s.status}</span> · {s.detail}
                  </div>
                </div>
              </div>
            ))}
          </WBGroup>
          <WBGroup title="Dev servers">
            {SERVERS.map((s) => (
              <div key={s.id} style={{ display: 'flex', alignItems: 'center', gap: 7, padding: '4px 0' }}>
                <span style={{ fontFamily: 'var(--font-mono)', fontSize: 11.5, fontWeight: 600, color: 'var(--accent)' }}>:{s.port}</span>
                <span style={{ fontSize: 11, color: 'var(--text-2)', flex: 1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{s.command}</span>
                <button style={iconBtn} title="Open"><Icon name="external" size={13} style={{ color: 'var(--text-3)' }} /></button>
                <button style={iconBtn} title="Stop"><Icon name="stop" size={12} style={{ color: 'var(--text-3)' }} /></button>
              </div>
            ))}
            <div style={{ marginTop: 6 }}>
              <div style={{ fontSize: 9, fontWeight: 700, letterSpacing: 0.5, color: 'var(--text-3)', textTransform: 'uppercase', marginBottom: 5 }}>Routes</div>
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: 5 }}>
                {ROUTES.map((r) => (
                  <span key={r} style={{ fontSize: 10.5, fontWeight: 550, color: 'var(--text-2)', padding: '3px 8px', borderRadius: 6, background: 'var(--track)' }}>{r}</span>
                ))}
              </div>
            </div>
          </WBGroup>
        </div>
      )}
    </div>
  );
}
function WBGroup({ title, children }) {
  return (
    <div>
      <div style={{ fontSize: 9, fontWeight: 700, letterSpacing: 0.5, color: 'var(--text-3)', textTransform: 'uppercase', marginBottom: 4 }}>{title}</div>
      {children}
    </div>
  );
}

// ---------- Action bar ----------
function ActionBar({ onSettings, onRefresh, refreshing }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
      <button onClick={onRefresh} style={primaryBtn}>
        <Icon name="refresh" size={14} stroke={2} style={{ animation: refreshing ? 'spin 1s linear infinite' : 'none' }} />
        Refresh
      </button>
      <button onClick={onSettings} style={ghostBtn}>
        <Icon name="settings" size={14} /> Settings
      </button>
      <button style={ghostBtn}>
        <Icon name="chart" size={14} /> History
      </button>
      <div style={{ marginLeft: 'auto', display: 'flex', gap: 4 }}>
        <button style={iconBtn} title="Copy status"><Icon name="copy" size={15} style={{ color: 'var(--text-2)' }} /></button>
        <button style={iconBtn} title="Diagnostics report"><Icon name="info" size={15} style={{ color: 'var(--text-2)' }} /></button>
        <button style={iconBtn} title="Quit"><Icon name="power" size={15} style={{ color: 'var(--text-2)' }} /></button>
      </div>
    </div>
  );
}
const primaryBtn = {
  display: 'inline-flex', alignItems: 'center', gap: 6, padding: '7px 13px',
  borderRadius: 9, border: 'none', background: 'var(--accent)', color: '#fff',
  fontSize: 12.5, fontWeight: 600,
};
const ghostBtn = {
  display: 'inline-flex', alignItems: 'center', gap: 6, padding: '7px 12px',
  borderRadius: 9, border: '1px solid var(--border)', background: 'var(--surface-raised)',
  color: 'var(--text)', fontSize: 12.5, fontWeight: 600,
};

// ---------- Popover ----------
function Popover({ onSettings, heroMode = 'featured' }) {
  const [filter, setFilter] = useState('usable');
  const [details, setDetails] = useState(false);
  const [drag, setDrag] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [focus, setFocus] = useState('auto');

  const sorted = [...LANES].sort((a, b) => (b.percent ?? -1) - (a.percent ?? -1));
  const autoLane = LANES.find((l) => l.id === 'claude-5h') || sorted[0];
  const featured = focus === 'auto' ? autoLane : (representativeLane(LANES, focus) || autoLane);
  const recommend = focus === 'auto'
    ? 'Switch to Codex — most room right now (58% left).'
    : `${featured.percent >= 0.85 ? 'Tight — consider another lane.' : featured.percent >= 0.6 ? 'Usable, but watch the pace.' : 'Comfortable headroom for now.'}`;
  const usable = sorted.filter((l) => l.state !== 'exhausted' && l.percent != null);
  const rows = filter === 'usable' ? usable : sorted;

  const refresh = () => { setRefreshing(true); setTimeout(() => setRefreshing(false), 900); };
  const headState = focus === 'auto' ? autoLane.state : featured.state;

  return (
    <div style={{
      width: 480, background: 'var(--surface)', borderRadius: 'var(--radius-xl)',
      border: '1px solid var(--border-strong)', boxShadow: 'var(--shadow-pop)', overflow: 'hidden',
      display: 'flex', flexDirection: 'column',
    }}>
      {/* header */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '15px 16px 13px' }}>
        <BrandMark size={24} />
        <div style={{ lineHeight: 1.15 }}>
          <div style={{ fontSize: 14.5, fontWeight: 700, letterSpacing: -0.1 }}>AI Fuel Gauge</div>
          <div style={{ fontSize: 11, color: 'var(--text-3)' }}>6 lanes live · updated 2m ago</div>
        </div>
        <div style={{ marginLeft: 'auto' }}><StatePill state={headState} label={STATE_LABEL[headState]} /></div>
      </div>

      <div style={{ padding: '0 16px', display: 'flex', flexDirection: 'column', gap: 13 }}>
        {heroMode === 'trio'
          ? <TrioHero lanes={LANES} onPick={() => {}} />
          : <HeroCard lane={featured} recommend={recommend} focus={focus} setFocus={setFocus} />}
      </div>

      {/* lane toolbar */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '15px 16px 8px' }}>
        <span style={{ fontSize: 11, fontWeight: 700, letterSpacing: 0.4, color: 'var(--text-3)', textTransform: 'uppercase' }}>Lanes</span>
        <Segmented value={filter} onChange={setFilter}
          options={[{ value: 'usable', label: 'Usable' }, { value: 'all', label: 'All' }]} />
        <span style={{ fontSize: 11, fontWeight: 600, color: 'var(--text-3)', fontFamily: 'var(--font-mono)' }}>{rows.length}</span>
        <div style={{ marginLeft: 'auto', display: 'flex', gap: 4 }}>
          <button onClick={() => setDrag(!drag)} title="Reorder"
            style={{ ...iconBtn, background: drag ? 'var(--accent-soft)' : 'transparent', color: drag ? 'var(--accent)' : 'var(--text-2)' }}>
            <Icon name="sliders" size={15} />
          </button>
          <button onClick={() => setDetails(!details)} title="Toggle details"
            style={{ ...iconBtn, background: details ? 'var(--accent-soft)' : 'transparent', color: details ? 'var(--accent)' : 'var(--text-2)' }}>
            <Icon name="chart" size={15} />
          </button>
        </div>
      </div>

      {/* lanes */}
      <div className="scroll-thin" style={{ padding: '0 8px', maxHeight: 250, overflowY: 'auto', margin: '0 8px',
        background: 'var(--surface-sunken)', borderRadius: 'var(--radius)', border: '1px solid var(--border)' }}>
        {rows.map((lane, i) => (
          <React.Fragment key={lane.id}>
            <LaneRow lane={lane} showDetails={details} dragMode={drag}
              onPin={(p) => setFocus(focus === p ? 'auto' : p)}
              isFocused={focus !== 'auto' && lane.provider === focus} />
            {i < rows.length - 1 && <div style={{ height: 1, background: 'var(--divider)', margin: '0 12px' }} />}
          </React.Fragment>
        ))}
      </div>

      <div style={{ padding: '13px 16px 0' }}><ResetStrip items={RESETS} /></div>
      <div style={{ padding: '12px 16px 0' }}><Workbench /></div>

      {/* footer */}
      <div style={{ marginTop: 14, padding: '12px 16px 14px', borderTop: '1px solid var(--divider)', background: 'var(--material)' }}>
        <div style={{ fontSize: 10.5, color: 'var(--text-3)', marginBottom: 10, display: 'flex', alignItems: 'center', gap: 6 }}>
          <Icon name="seal" size={12} style={{ color: 'var(--safe)' }} />
          6 exact · 1 estimated · 1 no limit — all data local
        </div>
        <ActionBar onSettings={onSettings} onRefresh={refresh} refreshing={refreshing} />
      </div>
    </div>
  );
}

window.Popover = Popover;
window.BrandMark = BrandMark;
window.Segmented = Segmented;
window.iconBtn = iconBtn;
window.ghostBtn = ghostBtn;
window.primaryBtn = primaryBtn;
