/* global React */
// ============================================================
// Demo data + shared visual primitives for the popover & settings
// ============================================================

const STATE_VAR = {
  safe: 'var(--safe)', caution: 'var(--caution)',
  critical: 'var(--critical)', exhausted: 'var(--exhausted)', unknown: 'var(--unknown)',
};
const STATE_LABEL = {
  safe: 'Plenty', caution: 'Getting tight', critical: 'Almost out',
  exhausted: 'Exhausted', unknown: 'Estimate',
};

// Lanes ordered by realism — mirrors the app's provider mix.
const LANES = [
  { id: 'claude-5h', provider: 'Claude Code', plan: 'Max 5×', window: '5h window',
    percent: 0.81, used: '81%', left: '19% left', state: 'critical', confidence: 'exact',
    resetIn: '47m', meterLabel: '19% left', dash: '#claude',
    pace: 'Pace warning — recent burn likely hits the cap before reset.',
    explanation: 'Exact 5h quota captured from the Claude Code statusline.',
    trend: [0.32,0.40,0.51,0.58,0.66,0.74,0.81] },
  { id: 'cursor-incl', provider: 'Cursor', plan: 'Pro', window: 'Included usage',
    percent: 0.90, used: '90%', left: '10% left', state: 'critical', confidence: 'exact',
    resetIn: '6d', meterLabel: '10% left',
    pace: 'On track to exhaust included requests this cycle.',
    explanation: 'Live current-period usage from your local Cursor session.',
    trend: [0.55,0.62,0.68,0.74,0.80,0.86,0.90] },
  { id: 'openrouter-key', provider: 'OpenRouter', plan: 'Main key', window: 'Key usage',
    percent: 0.76, used: '$76', left: '$24 left', state: 'caution', confidence: 'exact',
    resetIn: '1h', meterLabel: '$24 of $100',
    pace: 'Steady — comfortable until the next credit reset.',
    explanation: 'Official key-usage endpoint with a saved API key.',
    trend: [0.40,0.48,0.55,0.60,0.66,0.71,0.76] },
  { id: 'codex-5h', provider: 'Codex', plan: 'Plus', window: '5h window',
    percent: 0.42, used: '42%', left: '58% left', state: 'safe', confidence: 'exact',
    resetIn: '2h 10m', meterLabel: '58% left',
    pace: 'Plenty of headroom for the next task.',
    explanation: 'Exact quota from your local Codex account token.',
    trend: [0.10,0.18,0.24,0.30,0.34,0.39,0.42] },
  { id: 'codex-weekly', provider: 'Codex', plan: 'Plus', window: 'Weekly',
    percent: 0.68, used: '68%', left: '32% left', state: 'caution', confidence: 'exact',
    resetIn: '3d', meterLabel: '32% left',
    pace: 'Slightly ahead of an even weekly pace.',
    explanation: 'Exact weekly quota window from the Codex account.',
    trend: [0.20,0.30,0.40,0.48,0.55,0.62,0.68] },
  { id: 'openai-cost', provider: 'OpenAI', plan: 'Budget', window: 'Month-to-date',
    percent: 0.35, used: '$42', left: '$78 left', state: 'safe', confidence: 'exact',
    resetIn: '11d', meterLabel: '$42 of $120 budget',
    pace: 'Spend tracking under your monthly budget.',
    explanation: 'Organization costs from the OpenAI admin key, framed by your budget.',
    trend: [0.05,0.10,0.16,0.22,0.27,0.31,0.35] },
  { id: 'claude-weekly', provider: 'Claude Code', plan: 'Max 5×', window: 'Weekly',
    percent: 0.55, used: '55%', left: '45% left', state: 'caution', confidence: 'exact',
    resetIn: '4d', meterLabel: '45% left',
    pace: 'Even pace across the week so far.',
    explanation: 'Exact weekly quota captured from the Claude Code statusline.',
    trend: [0.18,0.26,0.34,0.41,0.47,0.51,0.55] },
  { id: 'opencode', provider: 'OpenCode', plan: 'Local', window: 'Token volume',
    percent: null, used: '2.4M tok', left: 'no limit', state: 'unknown', confidence: 'estimated',
    resetIn: null, meterLabel: 'estimated from local logs',
    pace: null,
    explanation: 'Local SQLite token aggregation. No official quota to compare against.',
    trend: [] },
];

const RESETS = [
  { id: 'r1', label: 'Claude 5h', value: '47m', state: 'critical' },
  { id: 'r2', label: 'OpenRouter', value: '1h', state: 'caution' },
  { id: 'r3', label: 'Codex 5h', value: '2h 10m', state: 'safe' },
];

const SESSIONS = [
  { id: 's1', provider: 'CC', project: 'fuel-gauge-app', status: 'active', detail: '2m ago · 14 turns' },
  { id: 's2', provider: 'CX', project: 'api-gateway', status: 'idle', detail: '38m ago' },
  { id: 's3', provider: 'CC', project: 'docs-site', status: 'idle', detail: '2h ago' },
];
const SERVERS = [
  { id: 'sv1', port: 3000, command: 'next dev' },
  { id: 'sv2', port: 5173, command: 'vite' },
];
const ROUTES = ['Skills', 'Plugins', 'Config', 'Logs', 'App state', 'Sessions'];

// ---------- Arc gauge ----------
function clamp01(n){ return Math.max(0, Math.min(1, n)); }

function ArcGauge({ percent, state, size = 150, stroke = 12, children }) {
  const cx = size / 2, r = (size / 2) - stroke - 3;
  const C = 2 * Math.PI * r;
  const arcFrac = 0.72;            // 259° sweep
  const arcLen = C * arcFrac;
  const valLen = arcLen * clamp01(percent ?? 0);
  const gapDeg = (1 - arcFrac) * 360;
  const rot = 90 + gapDeg / 2;     // center the gap at the bottom
  const col = STATE_VAR[state];
  return (
    <div style={{ position: 'relative', width: size, height: size }}>
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} style={{ display: 'block' }}>
        <g transform={`rotate(${rot} ${cx} ${cx})`}>
          <circle cx={cx} cy={cx} r={r} fill="none" stroke="var(--track)"
            strokeWidth={stroke} strokeLinecap="round"
            strokeDasharray={`${arcLen} ${C}`} />
          {percent != null && (
            <circle cx={cx} cy={cx} r={r} fill="none" stroke={col}
              strokeWidth={stroke} strokeLinecap="round"
              strokeDasharray={`${valLen} ${C}`}
              style={{ transition: 'stroke-dasharray .7s cubic-bezier(.2,.8,.2,1), stroke .3s' }} />
          )}
        </g>
      </svg>
      <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center',
        justifyContent: 'center', flexDirection: 'column' }}>{children}</div>
    </div>
  );
}

// ---------- Linear meter ----------
function Meter({ percent, state, height = 6 }) {
  return (
    <div style={{ height, borderRadius: height, background: 'var(--track)', overflow: 'hidden', flex: 1 }}>
      <div style={{
        height: '100%', width: `${clamp01(percent ?? 0) * 100}%`,
        background: STATE_VAR[state], borderRadius: height,
        transition: 'width .6s cubic-bezier(.2,.8,.2,1)',
      }} />
    </div>
  );
}

// ---------- Trust chip ----------
function TrustChip({ confidence }) {
  const exact = confidence === 'exact';
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 3,
      fontSize: 10, fontWeight: 600, letterSpacing: 0.2,
      padding: '2px 6px 2px 5px', borderRadius: 5,
      color: exact ? 'var(--safe)' : 'var(--text-3)',
      background: exact ? 'color-mix(in oklch, var(--safe) 14%, transparent)' : 'var(--track)',
    }}>
      <Icon name={exact ? 'seal' : 'info2'} size={11} stroke={2} />
      {exact ? 'Exact' : 'Estimate'}
    </span>
  );
}

// ---------- Sparkline ----------
function Sparkline({ data, state, width = 100, height = 24 }) {
  if (!data || data.length < 2) return null;
  const max = 1, min = 0;
  const pts = data.map((v, i) => {
    const x = (i / (data.length - 1)) * width;
    const y = height - ((v - min) / (max - min)) * height;
    return [x, y];
  });
  const d = pts.map((p, i) => (i === 0 ? `M${p[0]},${p[1]}` : `L${p[0]},${p[1]}`)).join(' ');
  const area = `${d} L${width},${height} L0,${height} Z`;
  const col = STATE_VAR[state];
  return (
    <svg width={width} height={height} viewBox={`0 0 ${width} ${height}`} style={{ display: 'block', overflow: 'visible' }}>
      <path d={area} fill={col} opacity="0.10" />
      <path d={d} fill="none" stroke={col} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
      <circle cx={pts[pts.length - 1][0]} cy={pts[pts.length - 1][1]} r="2.4" fill={col} />
    </svg>
  );
}

Object.assign(window, {
  LANES, RESETS, SESSIONS, SERVERS, ROUTES, STATE_VAR, STATE_LABEL,
  ArcGauge, Meter, TrustChip, Sparkline, clamp01,
});
