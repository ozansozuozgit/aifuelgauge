/* global React, ReactDOM, Icon, Popover, Settings, BrandMark */
const { useState: useStateA } = React;

function TrafficLights() {
  const c = ['#ff5f57', '#febc2e', '#28c840'];
  return (
    <div style={{ display: 'flex', gap: 8 }}>
      {c.map((col, i) => <span key={i} style={{ width: 12, height: 12, borderRadius: 999, background: col }} />)}
    </div>
  );
}

function MenuBarMock({ onToggle, open }) {
  return (
    <div style={{
      width: '100%', height: 30, borderRadius: '10px 10px 0 0',
      background: 'var(--material)', backdropFilter: 'blur(20px)',
      borderBottom: '1px solid var(--border)',
      display: 'flex', alignItems: 'center', justifyContent: 'flex-end',
      gap: 16, padding: '0 12px',
    }}>
      <span style={{ fontSize: 12, color: 'var(--text-3)', fontWeight: 500 }}>􀙥</span>
      <span style={{ fontSize: 12, color: 'var(--text-3)', fontWeight: 500 }}>􀊪</span>
      <button onClick={onToggle} title="Toggle popover"
        style={{
          display: 'inline-flex', alignItems: 'center', gap: 6, padding: '3px 9px', borderRadius: 6,
          border: 'none', background: open ? 'var(--accent-soft)' : 'transparent',
          fontFamily: 'var(--font-mono)', fontSize: 12.5, fontWeight: 600, color: 'var(--text)',
        }}>
        <BrandMark size={15} />
        <span style={{ color: 'var(--critical)' }}>19%</span>
        <span style={{ color: 'var(--text-2)' }}>47m</span>
      </button>
      <span style={{ fontSize: 11.5, color: 'var(--text-3)', fontWeight: 500, fontFamily: 'var(--font-mono)' }}>9:41</span>
    </div>
  );
}

function Frame({ label, sublabel, children, w }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 12, width: w }}>
      <div>
        <div style={{ fontSize: 13, fontWeight: 700, color: 'var(--text)', letterSpacing: 0.1 }}>{label}</div>
        <div style={{ fontSize: 12, color: 'var(--text-3)', marginTop: 1 }}>{sublabel}</div>
      </div>
      {children}
    </div>
  );
}

function App() {
  const [theme, setTheme] = useStateA('light');
  const [popOpen, setPopOpen] = useStateA(true);
  const [heroMode, setHeroMode] = useStateA('featured');

  React.useEffect(() => { document.documentElement.setAttribute('data-theme', theme); }, [theme]);

  return (
    <div style={{ minHeight: '100vh', background: 'var(--bg-canvas)',
      backgroundImage: 'radial-gradient(circle at 50% 0%, var(--bg-canvas) 0%, var(--bg-canvas-2) 100%)' }}>
      {/* presentation bar */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '20px 24px',
        maxWidth: 1360, margin: '0 auto' }}>
        <BrandMark size={26} />
        <div>
          <div style={{ fontSize: 17, fontWeight: 750, letterSpacing: -0.2 }}>AI Fuel Gauge — UI/UX Redesign</div>
          <div style={{ fontSize: 12.5, color: 'var(--text-2)' }}>Refined-native direction · menu-bar popover + restructured settings</div>
        </div>
        <div style={{ marginLeft: 'auto', display: 'flex', alignItems: 'center', gap: 12 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <span style={{ fontSize: 12, fontWeight: 600, color: 'var(--text-2)' }}>Hero</span>
            <div style={{ display: 'inline-flex', padding: 2, gap: 2, borderRadius: 9, background: 'var(--track)' }}>
              {[{ v: 'featured', l: 'Featured' }, { v: 'trio', l: 'Top 3' }].map((o) => (
                <button key={o.v} onClick={() => setHeroMode(o.v)}
                  style={{ border: 'none', borderRadius: 7, padding: '5px 12px', fontSize: 12.5, fontWeight: 600,
                    background: heroMode === o.v ? 'var(--surface-raised)' : 'transparent',
                    color: heroMode === o.v ? 'var(--text)' : 'var(--text-2)',
                    boxShadow: heroMode === o.v ? '0 1px 2px rgba(0,0,0,0.12)' : 'none' }}>{o.l}</button>
              ))}
            </div>
          </div>
          <button onClick={() => setTheme(theme === 'light' ? 'dark' : 'light')}
            style={{ display: 'inline-flex', alignItems: 'center', gap: 7, padding: '8px 14px',
              borderRadius: 10, border: '1px solid var(--border)', background: 'var(--surface-raised)', color: 'var(--text)',
              fontSize: 13, fontWeight: 600, boxShadow: '0 1px 2px rgba(0,0,0,0.05)' }}>
            <Icon name={theme === 'light' ? 'moon' : 'sun'} size={16} />
            {theme === 'light' ? 'Dark' : 'Light'}
          </button>
        </div>
      </div>

      <div style={{ display: 'flex', gap: 40, padding: '14px 24px 80px', maxWidth: 1360, margin: '0 auto',
        alignItems: 'flex-start', flexWrap: 'wrap', justifyContent: 'center' }}>
        {/* popover */}
        <Frame label="Menu-bar popover" sublabel="Click the gauge in the menu bar to toggle" w={480}>
          <div style={{ position: 'relative' }}>
            <MenuBarMock onToggle={() => setPopOpen(!popOpen)} open={popOpen} />
            <div style={{ height: 14 }} />
            {popOpen ? (
              <div style={{ position: 'relative' }}>
                <div style={{ position: 'absolute', top: -7, right: 64, width: 14, height: 14, background: 'var(--surface)',
                  borderLeft: '1px solid var(--border-strong)', borderTop: '1px solid var(--border-strong)',
                  transform: 'rotate(45deg)', borderRadius: 2, zIndex: 2 }} />
                <Popover heroMode={heroMode} onSettings={() => { document.getElementById('settings-anchor')?.scrollIntoView({ behavior: 'smooth', block: 'center' }); }} />
              </div>
            ) : (
              <div style={{ padding: '40px 20px', textAlign: 'center', color: 'var(--text-3)', fontSize: 13,
                border: '1px dashed var(--border-strong)', borderRadius: 14 }}>
                Popover closed — click the gauge above to open it.
              </div>
            )}
          </div>
        </Frame>

        {/* settings */}
        <Frame label="Settings window" sublabel="Sidebar navigation replaces the 12-panel scroll" w={760}>
          <div id="settings-anchor" style={{
            width: 760, height: 600, borderRadius: 12, overflow: 'hidden',
            border: '1px solid var(--border-strong)', boxShadow: 'var(--shadow-win)', background: 'var(--surface)',
            display: 'flex', flexDirection: 'column',
          }}>
            <div style={{ height: 38, display: 'flex', alignItems: 'center', gap: 12, padding: '0 14px',
              background: 'var(--material)', borderBottom: '1px solid var(--border)', flexShrink: 0 }}>
              <TrafficLights />
              <span style={{ fontSize: 13, fontWeight: 600, color: 'var(--text-2)', margin: '0 auto', paddingRight: 52 }}>Settings</span>
            </div>
            <div style={{ flex: 1, minHeight: 0 }}><Settings /></div>
          </div>
        </Frame>
      </div>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<App />);
