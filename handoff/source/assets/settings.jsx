/* global React, Icon, Segmented, ghostBtn, primaryBtn, STATE_VAR */
const { useState: useStateS } = React;

// ---------- form primitives ----------
function Switch({ on, onChange }) {
  return (
    <button onClick={() => onChange(!on)} role="switch" aria-checked={on}
      style={{
        width: 38, height: 23, borderRadius: 999, border: 'none', padding: 2, flexShrink: 0,
        background: on ? 'var(--accent)' : 'var(--track)',
        transition: 'background .2s', position: 'relative', cursor: 'pointer',
      }}>
      <span style={{
        display: 'block', width: 19, height: 19, borderRadius: 999, background: '#fff',
        boxShadow: '0 1px 3px rgba(0,0,0,0.3)',
        transform: on ? 'translateX(15px)' : 'translateX(0)', transition: 'transform .2s cubic-bezier(.3,1.4,.5,1)',
      }} />
    </button>
  );
}

function Row({ title, desc, children, icon }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 13, padding: '13px 15px' }}>
      {icon && (
        <span style={{ width: 30, height: 30, borderRadius: 8, background: 'var(--surface-sunken)',
          display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0, color: 'var(--text-2)' }}>
          <Icon name={icon} size={16} />
        </span>
      )}
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 13, fontWeight: 600 }}>{title}</div>
        {desc && <div style={{ fontSize: 11.5, color: 'var(--text-3)', marginTop: 2, lineHeight: 1.4 }}>{desc}</div>}
      </div>
      <div style={{ flexShrink: 0 }}>{children}</div>
    </div>
  );
}

function Group({ title, children }) {
  return (
    <div style={{ marginBottom: 22 }}>
      {title && <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 0.5, color: 'var(--text-3)', textTransform: 'uppercase', margin: '0 4px 8px' }}>{title}</div>}
      <div style={{ background: 'var(--surface-raised)', border: '1px solid var(--border)', borderRadius: 'var(--radius-lg)', overflow: 'hidden' }}>
        {React.Children.toArray(children).filter(Boolean).map((c, i, arr) => (
          <React.Fragment key={i}>
            {c}
            {i < arr.length - 1 && <div style={{ height: 1, background: 'var(--divider)', marginLeft: 15 }} />}
          </React.Fragment>
        ))}
      </div>
    </div>
  );
}

function TextField({ value, onChange, placeholder, mono, width }) {
  return (
    <input value={value} onChange={(e) => onChange(e.target.value)} placeholder={placeholder}
      style={{
        width: width || 150, padding: '6px 10px', borderRadius: 8,
        border: '1px solid var(--field-border)', background: 'var(--field)', color: 'var(--text)',
        fontSize: 12.5, fontFamily: mono ? 'var(--font-mono)' : 'inherit', outline: 'none',
      }}
      onFocus={(e) => { e.target.style.borderColor = 'var(--accent)'; e.target.style.boxShadow = '0 0 0 3px var(--accent-soft)'; }}
      onBlur={(e) => { e.target.style.borderColor = 'var(--field-border)'; e.target.style.boxShadow = 'none'; }} />
  );
}

function MiniBtn({ children, onClick, variant }) {
  const base = { display: 'inline-flex', alignItems: 'center', gap: 5, padding: '5px 11px', borderRadius: 7, fontSize: 12, fontWeight: 600, border: '1px solid var(--border)', background: 'var(--surface-raised)', color: 'var(--text)', whiteSpace: 'nowrap' };
  if (variant === 'primary') Object.assign(base, { background: 'var(--accent)', color: '#fff', border: 'none' });
  if (variant === 'danger') Object.assign(base, { color: 'var(--critical)', border: '1px solid color-mix(in oklch, var(--critical) 30%, transparent)' });
  return <button onClick={onClick} style={base}>{children}</button>;
}

function StatusLine({ children, tone }) {
  const col = tone === 'ok' ? 'var(--safe)' : tone === 'err' ? 'var(--critical)' : 'var(--text-3)';
  return (
    <div style={{ display: 'flex', gap: 6, alignItems: 'flex-start', padding: '10px 15px 13px', fontSize: 11.5, color: col, lineHeight: 1.4 }}>
      <Icon name={tone === 'ok' ? 'check' : tone === 'err' ? 'warn' : 'info2'} size={13} stroke={2} style={{ marginTop: 1, flexShrink: 0 }} />
      <span>{children}</span>
    </div>
  );
}

// ---------- key field block ----------
function KeyField({ label, placeholder, hint, saved }) {
  const [val, setVal] = useStateS(saved ? '••••••••••••••••••••' : '');
  const [state, setState] = useStateS(saved ? { msg: 'Stored in macOS Keychain. Tested OK.', tone: 'ok' } : { msg: 'Stored only in macOS Keychain. Never synced or logged.', tone: 'info' });
  const [testing, setTesting] = useStateS(false);
  const test = () => { setTesting(true); setState({ msg: 'Testing key…', tone: 'info' }); setTimeout(() => { setTesting(false); setState({ msg: 'Key works. Live polling enabled and saved to Keychain.', tone: 'ok' }); setVal('••••••••••••••••••••'); }, 1100); };
  return (
    <div style={{ background: 'var(--surface-raised)', border: '1px solid var(--border)', borderRadius: 'var(--radius-lg)', overflow: 'hidden', marginBottom: 14 }}>
      <div style={{ padding: '13px 15px 0', display: 'flex', alignItems: 'center', gap: 8 }}>
        <span style={{ width: 30, height: 30, borderRadius: 8, background: 'var(--surface-sunken)', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', color: 'var(--text-2)' }}>
          <Icon name="key" size={16} />
        </span>
        <div>
          <div style={{ fontSize: 13, fontWeight: 600 }}>{label}</div>
          <div style={{ fontSize: 11.5, color: 'var(--text-3)' }}>{hint}</div>
        </div>
        {saved && <span style={{ marginLeft: 'auto', fontSize: 10.5, fontWeight: 600, color: 'var(--safe)', display: 'inline-flex', alignItems: 'center', gap: 4 }}><Icon name="seal" size={12} /> Connected</span>}
      </div>
      <div style={{ padding: '11px 15px', display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap' }}>
        <input type="password" value={val} onChange={(e) => setVal(e.target.value)} placeholder={placeholder}
          style={{ flex: 1, minWidth: 180, padding: '7px 11px', borderRadius: 8, border: '1px solid var(--field-border)', background: 'var(--field)', color: 'var(--text)', fontSize: 12.5, fontFamily: 'var(--font-mono)', outline: 'none' }}
          onFocus={(e) => { e.target.style.borderColor = 'var(--accent)'; e.target.style.boxShadow = '0 0 0 3px var(--accent-soft)'; }}
          onBlur={(e) => { e.target.style.borderColor = 'var(--field-border)'; e.target.style.boxShadow = 'none'; }} />
        <MiniBtn onClick={test}>{testing ? 'Testing…' : 'Test'}</MiniBtn>
        <MiniBtn onClick={test} variant="primary">Paste, test & save</MiniBtn>
        {saved && <MiniBtn variant="danger"><Icon name="trash" size={13} /></MiniBtn>}
      </div>
      <div style={{ borderTop: '1px solid var(--divider)' }}><StatusLine tone={state.tone}>{state.msg}</StatusLine></div>
    </div>
  );
}

// ============================================================
//  SECTIONS
// ============================================================
function SectionHeader({ title, desc }) {
  return (
    <div style={{ marginBottom: 20 }}>
      <h2 style={{ margin: 0, fontSize: 21, fontWeight: 700, letterSpacing: -0.3 }}>{title}</h2>
      <p style={{ margin: '5px 0 0', fontSize: 13, color: 'var(--text-2)', lineHeight: 1.45, maxWidth: 460 }}>{desc}</p>
    </div>
  );
}

function GeneralSection() {
  const [refresh, setRefresh] = useStateS(180);
  const [login, setLogin] = useStateS(true);
  return (
    <>
      <SectionHeader title="General" desc="How often AI Fuel Gauge refreshes in the background, and whether it starts with your Mac." />
      <Group title="Auto-sync">
        <Row icon="refresh" title="Refresh cadence" desc="Background polling interval. Manual refresh always works instantly.">
          <Segmented value={refresh} onChange={setRefresh}
            options={[{ value: 60, label: '1m' }, { value: 180, label: '3m' }, { value: 300, label: '5m' }, { value: 900, label: '15m' }]} />
        </Row>
      </Group>
      <Group title="Startup">
        <Row icon="power" title="Start at login" desc="Recreate the launch agent so the gauge is always in your menu bar.">
          <Switch on={login} onChange={setLogin} />
        </Row>
      </Group>
    </>
  );
}

const PROVIDERS = [
  { key: 'codex', name: 'Codex', desc: 'Account quota + local fallback from ~/.codex.', plan: 'Plus', detected: true },
  { key: 'cursor', name: 'Cursor', desc: 'Local account state + live current-period usage.', plan: 'Pro', detected: true },
  { key: 'claude', name: 'Claude Code', desc: 'Exact 5h/weekly via statusline; token estimates otherwise.', plan: 'Max 5×', detected: true },
  { key: 'opencode', name: 'OpenCode', desc: 'Local token estimates from OpenCode SQLite.', plan: 'Local', detected: false },
  { key: 'openrouter', name: 'OpenRouter', desc: 'Official key + credit endpoints when a key is saved.', plan: '—', detected: false },
  { key: 'openai', name: 'OpenAI', desc: 'Org costs + token usage when an admin key is saved.', plan: '—', detected: false },
];

function ProvidersSection() {
  const [on, setOn] = useStateS(Object.fromEntries(PROVIDERS.map((p) => [p.key, true])));
  return (
    <>
      <SectionHeader title="Providers" desc="Turn sources on or off. Disabling one removes it from polling, alerts, history, and the exported status snapshot." />
      <Group title="Monitored sources">
        {PROVIDERS.map((p) => (
          <Row key={p.key} title={
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 8 }}>{p.name}
              {p.detected
                ? <span style={{ fontSize: 10, fontWeight: 600, color: 'var(--safe)', background: 'color-mix(in oklch, var(--safe) 14%, transparent)', padding: '1px 6px', borderRadius: 5 }}>{p.plan}</span>
                : <span style={{ fontSize: 10, fontWeight: 600, color: 'var(--text-3)', background: 'var(--track)', padding: '1px 6px', borderRadius: 5 }}>needs key</span>}
            </span>} desc={p.desc}>
            <Switch on={on[p.key]} onChange={(v) => setOn({ ...on, [p.key]: v })} />
          </Row>
        ))}
      </Group>
      <Group title="Plan label overrides">
        <Row icon="info2" title="Claude Code" desc="Auto-detected: Max 5× · a••@gmail.com. Override only if wrong.">
          <TextField value="" onChange={() => {}} placeholder="Max 5×" width={130} />
        </Row>
        <Row icon="info2" title="Cursor" desc="Detected: Pro · active. Override only if wrong.">
          <TextField value="" onChange={() => {}} placeholder="Pro" width={130} />
        </Row>
      </Group>
    </>
  );
}

function KeysSection() {
  return (
    <>
      <SectionHeader title="API keys" desc="Local-first sources stay automatic. Add keys only for providers that expose official usage metadata. Keys live in your macOS Keychain." />
      <KeyField label="OpenRouter" hint="Key usage + account credits" placeholder="sk-or-v1-…" saved />
      <KeyField label="OpenAI Admin" hint="Organization costs + token usage" placeholder="sk-admin-…" />
      <div style={{ display: 'flex', gap: 8, marginTop: 4 }}>
        <MiniBtn><Icon name="external" size={13} /> OpenRouter dashboard</MiniBtn>
        <MiniBtn><Icon name="external" size={13} /> OpenAI usage</MiniBtn>
      </div>
    </>
  );
}

function AlertsSection() {
  const [th, setTh] = useStateS({ 50: false, 75: true, 90: true, 100: true });
  const [stale, setStale] = useStateS(true);
  const profiles = ['Codex', 'Cursor', 'OpenRouter', 'Claude Code'];
  const [prof, setProf] = useStateS(Object.fromEntries(profiles.map((p) => [p, 'Global'])));
  return (
    <>
      <SectionHeader title="Alerts" desc="Notifications fire when usage crosses a threshold. Tune globally, then override per provider where alerts get noisy." />
      <Group title="Global thresholds">
        <div style={{ padding: '14px 15px', display: 'flex', gap: 8, flexWrap: 'wrap' }}>
          {[50, 75, 90, 100].map((t) => (
            <button key={t} onClick={() => setTh({ ...th, [t]: !th[t] })}
              style={{ padding: '7px 16px', borderRadius: 9, fontSize: 13, fontWeight: 600, fontFamily: 'var(--font-mono)',
                border: th[t] ? '1px solid transparent' : '1px solid var(--border)',
                background: th[t] ? 'var(--accent)' : 'var(--surface-raised)',
                color: th[t] ? '#fff' : 'var(--text-2)' }}>{t}%</button>
          ))}
        </div>
        <Row title="Stale-data warnings" desc="Warn when a lane hasn't refreshed and may be out of date.">
          <Switch on={stale} onChange={setStale} />
        </Row>
      </Group>
      <Group title="Per-provider profiles">
        {profiles.map((p) => (
          <Row key={p} title={p} desc={prof[p] === 'Global' ? 'Uses the global thresholds above.' : `Custom: ${prof[p]} alerts only.`}>
            <Segmented value={prof[p]} onChange={(v) => setProf({ ...prof, [p]: v })}
              options={[{ value: 'Global', label: 'Global' }, { value: 'Standard', label: 'Std' }, { value: 'Critical', label: 'Crit' }, { value: 'Off', label: 'Off' }]} />
          </Row>
        ))}
      </Group>
    </>
  );
}

function MenuBarSection() {
  const [mode, setMode] = useStateS('detail');
  const [focus, setFocus] = useStateS('auto');
  const previews = {
    detail: '◐ Claude 5h · 19% · 47m',
    pair: '◐ 19% · ◑ 32%',
    trend: '◐ Claude ╱╱╱',
    compact: '◐ 19%',
    minimal: '◐',
  };
  return (
    <>
      <SectionHeader title="Menu bar" desc="Control how much the menu-bar label shows, and which provider drives it." />
      <Group title="Preview">
        <div style={{ padding: '18px 15px', display: 'flex', justifyContent: 'center' }}>
          <div style={{ display: 'inline-flex', alignItems: 'center', gap: 8, padding: '5px 12px', borderRadius: 7,
            background: 'var(--surface-sunken)', border: '1px solid var(--border)', fontFamily: 'var(--font-mono)', fontSize: 13, fontWeight: 600 }}>
            <span style={{ color: 'var(--critical)' }}>{previews[mode]}</span>
          </div>
        </div>
      </Group>
      <Group title="Display density">
        <Row title="Label detail" desc="From full detail down to a single status glyph.">
          <Segmented value={mode} onChange={setMode}
            options={[{ value: 'detail', label: 'Detail' }, { value: 'pair', label: 'Pair' }, { value: 'trend', label: 'Trend' }, { value: 'compact', label: 'Compact' }, { value: 'minimal', label: 'Min' }]} />
        </Row>
        <Row title="Provider focus" desc="Auto picks the tightest useful lane. Pin one to always lead.">
          <Segmented value={focus} onChange={setFocus}
            options={[{ value: 'auto', label: 'Auto' }, { value: 'codex', label: 'Codex' }, { value: 'cursor', label: 'Cursor' }, { value: 'claude', label: 'Claude' }]} />
        </Row>
      </Group>
    </>
  );
}

function BudgetsSection() {
  return (
    <>
      <SectionHeader title="Budgets" desc="Optional monthly guardrails turn raw spend rows into comparable warning lanes. Leave blank to show spend only — never an invented limit." />
      <Group title="Monthly guardrails">
        <Row icon="dollar" title="OpenAI" desc="Turns month-to-date spend into a budget lane.">
          <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}><span style={{ color: 'var(--text-3)', fontSize: 13 }}>$</span><TextField value="120" onChange={() => {}} placeholder="USD" mono width={90} /></div>
        </Row>
        <Row icon="dollar" title="Cursor" desc="Optional spend guardrail for Cursor spend rows.">
          <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}><span style={{ color: 'var(--text-3)', fontSize: 13 }}>$</span><TextField value="" onChange={() => {}} placeholder="USD" mono width={90} /></div>
        </Row>
        <Row icon="dollar" title="OpenRouter" desc="Optional key-usage guardrail in credits.">
          <TextField value="100" onChange={() => {}} placeholder="credits" mono width={110} />
        </Row>
      </Group>
    </>
  );
}

function PrivacySection() {
  const [msg, setMsg] = useStateS({ t: 'History stores only lane IDs, timestamps, and percentages — never prompt text.', tone: 'info' });
  return (
    <>
      <SectionHeader title="Data & privacy" desc="Everything is local. Diagnostics and the status export are sanitized — no keys, tokens, or prompt text." />
      <Group title="Local files">
        <Row icon="chart" title="Usage history" desc="7-day rolling trend used for sparklines and history.">
          <div style={{ display: 'flex', gap: 6 }}><MiniBtn onClick={() => setMsg({ t: 'Revealed usage-history.json in Finder.', tone: 'ok' })}>Reveal</MiniBtn><MiniBtn variant="danger" onClick={() => setMsg({ t: 'Local usage history cleared.', tone: 'ok' })}>Clear</MiniBtn></div>
        </Row>
        <Row icon="download" title="status.json export" desc="Sanitized snapshot for WidgetKit, SketchyBar, Raycast, etc.">
          <MiniBtn onClick={() => setMsg({ t: 'Revealed status.json in Finder.', tone: 'ok' })}>Reveal</MiniBtn>
        </Row>
        <Row icon="shield" title="Diagnostics report" desc="Copy a secret-free report for bug reports.">
          <MiniBtn onClick={() => setMsg({ t: 'Copied diagnostics report (sanitized) to clipboard.', tone: 'ok' })}>Copy</MiniBtn>
        </Row>
      </Group>
      <div style={{ marginTop: -8 }}><StatusLine tone={msg.tone}>{msg.t}</StatusLine></div>
    </>
  );
}

function AboutSection() {
  const [msg, setMsg] = useStateS('You\u2019re on the latest version.');
  return (
    <>
      <SectionHeader title="About" desc="Version info and update options." />
      <Group>
        <div style={{ padding: '20px 15px', display: 'flex', alignItems: 'center', gap: 14 }}>
          <span style={{ width: 52, height: 52, borderRadius: 13, background: 'var(--surface-sunken)', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', border: '1px solid var(--border)' }}>
            <window.BrandMark size={30} />
          </span>
          <div>
            <div style={{ fontSize: 16, fontWeight: 700 }}>AI Fuel Gauge</div>
            <div style={{ fontSize: 12.5, color: 'var(--text-2)' }}>Version 0.4.0 · macOS 14+ · MIT</div>
          </div>
        </div>
      </Group>
      <Group title="Updates">
        <Row icon="download" title="Check for updates" desc={msg}>
          <MiniBtn variant="primary" onClick={() => setMsg('Checking GitHub releases…')}>Check now</MiniBtn>
        </Row>
        <Row icon="external" title="Releases & changelog" desc="Open the latest GitHub release.">
          <MiniBtn>Open</MiniBtn>
        </Row>
        <Row icon="copy" title="Homebrew update command" desc="Copy the brew upgrade command.">
          <MiniBtn>Copy</MiniBtn>
        </Row>
      </Group>
    </>
  );
}

const NAV = [
  { key: 'general', label: 'General', icon: 'settings', Comp: GeneralSection },
  { key: 'providers', label: 'Providers', icon: 'gauge', Comp: ProvidersSection },
  { key: 'keys', label: 'API Keys', icon: 'key', Comp: KeysSection },
  { key: 'alerts', label: 'Alerts', icon: 'bell', Comp: AlertsSection },
  { key: 'menubar', label: 'Menu Bar', icon: 'menubar', Comp: MenuBarSection },
  { key: 'budgets', label: 'Budgets', icon: 'dollar', Comp: BudgetsSection },
  { key: 'privacy', label: 'Data & Privacy', icon: 'shield', Comp: PrivacySection },
  { key: 'about', label: 'About', icon: 'info', Comp: AboutSection },
];

function Settings() {
  const [active, setActive] = useStateS('providers');
  const Active = NAV.find((n) => n.key === active).Comp;
  return (
    <div style={{ display: 'flex', height: '100%', background: 'var(--surface)' }}>
      {/* sidebar */}
      <div style={{ width: 208, flexShrink: 0, background: 'var(--surface-sunken)', borderRight: '1px solid var(--border)',
        display: 'flex', flexDirection: 'column', padding: '14px 10px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '4px 8px 14px' }}>
          <window.BrandMark size={22} />
          <span style={{ fontSize: 13.5, fontWeight: 700 }}>AI Fuel Gauge</span>
        </div>
        <nav style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
          {NAV.map((n) => (
            <button key={n.key} onClick={() => setActive(n.key)}
              style={{
                display: 'flex', alignItems: 'center', gap: 10, padding: '8px 10px', borderRadius: 8,
                border: 'none', textAlign: 'left', fontSize: 13, fontWeight: active === n.key ? 600 : 500,
                background: active === n.key ? 'var(--accent)' : 'transparent',
                color: active === n.key ? '#fff' : 'var(--text-2)', transition: 'background .12s',
              }}
              onMouseEnter={(e) => { if (active !== n.key) e.currentTarget.style.background = 'var(--surface-hover)'; }}
              onMouseLeave={(e) => { if (active !== n.key) e.currentTarget.style.background = 'transparent'; }}>
              <Icon name={n.icon} size={16} stroke={active === n.key ? 2 : 1.7} />
              {n.label}
            </button>
          ))}
        </nav>
        <div style={{ marginTop: 'auto', padding: '10px 8px 2px', fontSize: 10.5, color: 'var(--text-3)', display: 'flex', alignItems: 'center', gap: 5 }}>
          <Icon name="shield" size={12} style={{ color: 'var(--safe)' }} /> Local-first · v0.4.0
        </div>
      </div>
      {/* content */}
      <div className="scroll-thin" style={{ flex: 1, overflowY: 'auto', padding: '26px 28px 40px' }}>
        <div style={{ maxWidth: 560 }}><Active /></div>
      </div>
    </div>
  );
}

window.Settings = Settings;
