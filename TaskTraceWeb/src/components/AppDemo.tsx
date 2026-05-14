import React, { useState, useRef, useLayoutEffect, useEffect } from 'react';

// ─── AppColors.swift dark-mode values ─────────────────────────────────────────
const C = {
  accent:         '#78C7F5',                     // recordIdle (0.47,0.78,0.96)
  accentDim:      'rgba(120,199,245,0.22)',
  accentBorder:   'rgba(255,255,255,0.38)',
  recordActive:   '#FAA3B8',                     // recordActive (0.98,0.64,0.72)
  recordActiveDim:'rgba(250,163,184,0.22)',
  cardBg:         'rgba(41,48,64,0.92)',          // cardBackground
  insetBg:        'rgba(48,56,74,0.90)',          // insetBackground
  chipBg:         'rgba(59,69,92,0.95)',          // chipBackground
  textPrimary:    'rgba(249,249,247,0.92)',
  textSecondary:  'rgba(149,158,177,1)',
  windowBg:       '#13151c',
  sidebarBg:      '#16181f',
  titleBarBg:     '#1c1f28',
  tagWork:        '#85D1FA',                     // darkPalette[0]
  tagResearch:    '#99EBC7',                     // darkPalette[1]
  // timelineColor darkPalette (overviewID % 5)
  timeline: [
    'rgba(138,209,247,0.94)',   // 0 – blue
    'rgba(156,235,201,0.94)',   // 1 – green
    'rgba(250,191,171,0.94)',   // 2 – salmon
    'rgba(204,186,250,0.94)',   // 3 – lavender
    'rgba(247,224,153,0.94)',   // 4 – yellow
  ],
  timelineUnassigned: 'rgba(77,87,110,0.92)',    // timelineUnassigned dark
};

// ─── Nav metadata (matches ContentView AppPage) ────────────────────────────────
export type NavItem = 'Activity' | 'Calendar' | 'Analytics' | 'Overview' | 'Search' | 'Tags' | 'Agents' | 'Settings' | 'MCP';
const NAV_ITEMS: { label: NavItem; icon: React.ReactNode }[] = [
  { label: 'Activity',  icon: <StopwatchIcon /> },
  { label: 'Calendar',  icon: <CalendarIcon /> },
  { label: 'Analytics', icon: <ChartIcon /> },
  { label: 'Overview',  icon: <DocIcon /> },
  { label: 'Search',    icon: <SearchNavIcon /> },
  { label: 'Tags',      icon: <TagIcon /> },
  { label: 'Settings',  icon: <GearIcon /> },
  { label: 'Agents',    icon: <AgentsNavIcon /> },
  { label: 'MCP',       icon: <McpNavIcon /> },
];

// ─── SF-Symbol-inspired SVG icons ─────────────────────────────────────────────
function StopwatchIcon() {
  return (
    <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="12" cy="13" r="8" />
      <polyline points="12 9 12 13 14.5 15.5" />
      <line x1="9.5" y1="2" x2="14.5" y2="2" />
      <line x1="12" y1="2" x2="12" y2="5" />
    </svg>
  );
}
function CalendarIcon() {
  return (
    <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <rect x="3" y="4" width="18" height="18" rx="3" />
      <line x1="16" y1="2" x2="16" y2="6" />
      <line x1="8" y1="2" x2="8" y2="6" />
      <line x1="3" y1="10" x2="21" y2="10" />
    </svg>
  );
}
function ChartIcon() {
  return (
    <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <line x1="18" y1="20" x2="18" y2="10" />
      <line x1="12" y1="20" x2="12" y2="4" />
      <line x1="6" y1="20" x2="6" y2="14" />
      <line x1="2" y1="20" x2="22" y2="20" />
    </svg>
  );
}
function DocIcon() {
  return (
    <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
      <polyline points="14 2 14 8 20 8" />
      <line x1="8" y1="13" x2="16" y2="13" />
      <line x1="8" y1="17" x2="13" y2="17" />
    </svg>
  );
}
function TagIcon() {
  return (
    <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M20.59 13.41l-7.17 7.17a2 2 0 0 1-2.83 0L2 12V2h10l8.59 8.59a2 2 0 0 1 0 2.82z" />
      <line x1="7" y1="7" x2="7.01" y2="7" />
    </svg>
  );
}
function GearIcon() {
  return (
    <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="12" cy="12" r="3" />
      <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z" />
    </svg>
  );
}
function SearchNavIcon() {
  return (
    <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="11" cy="11" r="8" />
      <line x1="21" y1="21" x2="16.65" y2="16.65" />
    </svg>
  );
}
function McpNavIcon() {
  return (
    <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <rect x="2" y="3" width="20" height="7" rx="2" />
      <rect x="2" y="14" width="20" height="7" rx="2" />
      <circle cx="18.5" cy="6.5" r="1.2" fill="currentColor" stroke="none" />
      <circle cx="18.5" cy="17.5" r="1.2" fill="currentColor" stroke="none" />
    </svg>
  );
}
function AgentsNavIcon() {
  return (
    <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M16 21v-2a4 4 0 0 0-4-4H7a4 4 0 0 0-4 4v2" />
      <circle cx="9.5" cy="7" r="3" />
      <path d="M22 21v-2a4 4 0 0 0-3-3.87" />
      <path d="M16 3.13a4 4 0 0 1 0 7.75" />
    </svg>
  );
}

// ─── Activity data ─────────────────────────────────────────────────────────────
const ACTIVITIES = [
  {
    app: 'Xcode', bundle: 'com.apple.dt.Xcode',
    start: '9:14 AM', end: '10:02 AM', duration: '48 min', tag: 'Work',
    summary: 'Implemented ActivityActor finalization pipeline. Added screenshot OCR and AI summarization steps. Fixed actor isolation warning in OverviewStore.',
    keystrokes: 'func finalize() async throws {\n  await processScreenshots()\n  let s = try await ai.summarize()\n  await store.save(s)\n}',
    mic: 'Discussed the async pipeline design with the team. Agreed on actor isolation pattern.',
  },
  {
    app: 'Terminal', bundle: 'com.apple.Terminal',
    start: '10:02 AM', end: '10:47 AM', duration: '45 min', tag: 'Work',
    summary: 'Ran unit tests for OverviewStore and AnalyticsStore. Fixed flaky CalendarStore test by adding async wait for actor state propagation.',
    keystrokes: 'swift test --filter OverviewStoreTests\nswift test --filter AnalyticsStoreTests\n# all tests passed',
    mic: '',
  },
  {
    app: 'Safari', bundle: 'com.apple.Safari',
    start: '10:47 AM', end: '11:30 AM', duration: '43 min', tag: null,
    summary: 'Researched Apple MLX framework performance on M-series silicon. Evaluated transformer throughput and compared against alternatives for on-device inference.',
    keystrokes: '',
    mic: 'Talked through MLX benchmarks. M3 hits ~60 tok/s on the 3B model.',
  },
];

const OVERVIEWS = [
  {
    title: 'ActivityActor Pipeline Implementation',
    summary: 'Built and tested the finalization pipeline for ActivityActor, covering screenshot OCR, AI summarization, and tag assignment. Fixed actor isolation issues in OverviewStore.',
    duration: '1 hr 33 min', sources: [1, 2], tag: 'Work',
  },
  {
    title: 'ML Research: MLX Benchmarks',
    summary: 'Reviewed Apple MLX framework performance on M-series silicon. Evaluated transformer model throughput and compared inference speeds.',
    duration: '43 min', sources: [3], tag: null,
  },
];

// ─── Tags data ─────────────────────────────────────────────────────────────────
const TAGS_DATA = [
  { id: 1, name: 'Work',     description: 'Programming, meetings, and professional tasks.' },
  { id: 2, name: 'Research', description: 'Reading, learning, and exploring new topics.' },
  { id: 3, name: 'Personal', description: 'Non-work activities and personal projects.' },
];

// ─── Calendar data ─────────────────────────────────────────────────────────────
// March 2026: starts on Sunday (March 1 = Sunday)
const MARCH_2026 = Array.from({ length: 31 }, (_, i) => i + 1);
const MARCH_START_DOW = 0; // Sunday
const SELECTED_DAY = 18;
const AVAILABLE_RANGE = [5, 18]; // days 5–18 have data

// Timeline blocks for March 18 (seconds since midnight)
const TIMELINE_BLOCKS = [
  { startS: 9 * 3600 + 14 * 60, endS: 10 * 3600 + 47 * 60, overviewID: 1, title: 'ActivityActor Pipeline' },
  { startS: 10 * 3600 + 47 * 60, endS: 11 * 3600 + 30 * 60, overviewID: null, title: '' },
];

// ─── Sliding pill tab bar ──────────────────────────────────────────────────────
function PanelTabs({ panels, selected, onSelect }: {
  panels: string[];
  selected: string;
  onSelect: (p: string) => void;
}) {
  const refs = useRef<(HTMLButtonElement | null)[]>([]);
  const wrapRef = useRef<HTMLDivElement>(null);
  const [pill, setPill] = useState({ left: 0, width: 0 });

  useLayoutEffect(() => {
    const idx = panels.indexOf(selected);
    const el = refs.current[idx];
    const wrap = wrapRef.current;
    if (el && wrap) {
      const wRect = wrap.getBoundingClientRect();
      const eRect = el.getBoundingClientRect();
      setPill({ left: eRect.left - wRect.left, width: eRect.width });
    }
  }, [selected, panels]);

  return (
    <div ref={wrapRef} style={tb.wrap}>
      <div style={{ ...tb.pill, left: pill.left, width: pill.width }} />
      {panels.map((p, i) => (
        <button
          key={p}
          ref={el => { refs.current[i] = el; }}
          onClick={() => onSelect(p)}
          style={{ ...tb.btn, color: p === selected ? C.textPrimary : C.textSecondary }}
        >
          {p}
        </button>
      ))}
    </div>
  );
}

const tb: Record<string, React.CSSProperties> = {
  wrap: {
    position: 'relative',
    display: 'inline-flex',
    background: 'rgba(48,56,74,0.86)',
    borderRadius: 18,
    padding: '5px 6px',
    gap: 2,
    alignSelf: 'flex-start',
  },
  pill: {
    position: 'absolute',
    top: 5,
    height: 'calc(100% - 10px)',
    background: C.accentDim,
    border: `0.8px solid ${C.accentBorder}`,
    borderRadius: 50,
    backdropFilter: 'blur(8px)',
    pointerEvents: 'none',
    transition: 'left 0.22s cubic-bezier(0.34,1.56,0.64,1), width 0.22s cubic-bezier(0.34,1.56,0.64,1)',
  },
  btn: {
    position: 'relative',
    zIndex: 1,
    background: 'none',
    border: 'none',
    cursor: 'pointer',
    fontSize: 11,
    fontWeight: 600,
    padding: '5px 11px',
    borderRadius: 50,
    fontFamily: 'Inter, sans-serif',
    transition: 'color 0.15s ease',
    whiteSpace: 'nowrap' as const,
  },
};

// ─── Activity panel ────────────────────────────────────────────────────────────
function ActivityPanel() {
  const [panelSel, setPanelSel] = useState(['Summary', 'Summary', 'Summary']);

  function getPanels(a: typeof ACTIVITIES[0]) {
    const p = ['Summary'];
    if (a.keystrokes) p.push('Keystrokes');
    if (a.mic) p.push('Microphone');
    return p;
  }

  return (
    <div style={ap.scroll}>
      {ACTIVITIES.map((a, i) => {
        const available = getPanels(a);
        const sel = available.includes(panelSel[i]) ? panelSel[i] : 'Summary';
        return (
          <div key={i} style={ap.card}>
            <div style={ap.hdr}>
              <div>
                <div style={ap.appName}>{a.app}</div>
                <div style={ap.bundle}>{a.bundle}</div>
              </div>
              <div style={ap.meta}>
                {a.tag && <span style={ap.tagChip}>{a.tag}</span>}
                <div style={ap.times}>
                  <span style={ap.time}>{a.start}</span>
                  <span style={{ ...ap.time, color: C.textSecondary, fontSize: 10 }}>{a.end}</span>
                </div>
              </div>
            </div>
            <div style={ap.dur}>⏱ {a.duration}</div>
            <PanelTabs
              panels={available}
              selected={sel}
              onSelect={p => {
                const next = [...panelSel];
                next[i] = p;
                setPanelSel(next);
              }}
            />
            <div style={ap.panelBox}>
              <div style={ap.panelLabel}>{sel}</div>
              {sel === 'Summary'    && <p style={ap.panelText}>{a.summary}</p>}
              {sel === 'Keystrokes' && <pre style={ap.mono}>{a.keystrokes}</pre>}
              {sel === 'Microphone' && <p style={ap.panelText}>{a.mic}</p>}
            </div>
          </div>
        );
      })}
    </div>
  );
}

const ap: Record<string, React.CSSProperties> = {
  scroll:     { overflowY: 'auto', padding: '12px 14px', display: 'flex', flexDirection: 'column', gap: 10, height: '100%' },
  card:       { background: C.cardBg, borderRadius: 14, padding: 14, display: 'flex', flexDirection: 'column', gap: 9, flexShrink: 0 },
  hdr:        { display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' },
  appName:    { fontSize: 13, fontWeight: 700, color: C.textPrimary, marginBottom: 1 },
  bundle:     { fontSize: 9.5, color: C.textSecondary },
  meta:       { display: 'flex', alignItems: 'flex-start', gap: 10 },
  tagChip:    { fontSize: 9.5, fontWeight: 600, padding: '2px 8px', background: 'rgba(120,199,245,0.18)', color: C.accent, borderRadius: 50, marginTop: 2 },
  times:      { display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 1 },
  time:       { fontSize: 11, fontWeight: 500, color: C.textPrimary },
  dur:        { fontSize: 10.5, color: C.textSecondary, marginTop: -3 },
  panelBox:   { background: C.insetBg, borderRadius: 10, padding: 11 },
  panelLabel: { fontSize: 10.5, fontWeight: 700, color: C.textPrimary, marginBottom: 5, textTransform: 'uppercase' as const, letterSpacing: '0.05em' },
  panelText:  { fontSize: 11.5, color: C.textSecondary, lineHeight: 1.6, margin: 0 },
  mono:       { fontSize: 10, color: C.textSecondary, fontFamily: 'monospace', lineHeight: 1.65, margin: 0, whiteSpace: 'pre-wrap' as const },
};

// ─── Overview panel ────────────────────────────────────────────────────────────
function OverviewPanel() {
  return (
    <div style={ov.scroll}>
      {OVERVIEWS.map((o, i) => (
        <div key={i} style={ov.card}>
          <div style={ov.title}>{o.title}</div>
          <p style={ov.summary}>{o.summary}</p>
          <div style={ov.metaRow}>
            <div style={ov.metaBlock}>
              <div style={ov.metaLabel}>Duration</div>
              <div style={ov.metaValue}>{o.duration}</div>
            </div>
            <div style={ov.metaBlock}>
              <div style={ov.metaLabel}>Source Activities</div>
              <div style={{ display: 'flex', gap: 5, marginTop: 2 }}>
                {o.sources.map(n => <span key={n} style={ov.chip}>{n}</span>)}
              </div>
            </div>
            <div style={ov.metaBlock}>
              <div style={ov.metaLabel}>Tag</div>
              {o.tag
                ? <span style={{ ...ov.chip, background: 'rgba(120,199,245,0.18)', color: C.accent }}>{o.tag}</span>
                : <span style={{ ...ov.chip, color: C.textSecondary }}>None</span>
              }
            </div>
          </div>
        </div>
      ))}
    </div>
  );
}

const ov: Record<string, React.CSSProperties> = {
  scroll:    { overflowY: 'auto', padding: '12px 14px', display: 'flex', flexDirection: 'column', gap: 10, height: '100%' },
  card:      { background: C.cardBg, borderRadius: 14, padding: 14, display: 'flex', flexDirection: 'column', gap: 10, flexShrink: 0 },
  title:     { fontSize: 13, fontWeight: 700, color: C.textPrimary },
  summary:   { fontSize: 11.5, color: C.textSecondary, lineHeight: 1.6, margin: 0 },
  metaRow:   { display: 'flex', gap: 24, flexWrap: 'wrap' as const },
  metaBlock: { display: 'flex', flexDirection: 'column', gap: 5 },
  metaLabel: { fontSize: 9.5, fontWeight: 700, color: C.textSecondary, textTransform: 'uppercase' as const, letterSpacing: '0.06em' },
  metaValue: { fontSize: 12, color: C.textPrimary },
  chip:      { fontSize: 10, fontWeight: 600, padding: '3px 9px', background: C.chipBg, color: C.textPrimary, borderRadius: 50 },
};

// ─── Analytics panel ───────────────────────────────────────────────────────────
function heatVal(seed: number) {
  const r = Math.abs(Math.sin(seed * 9301 + 49297) * 233280);
  return r - Math.floor(r);
}
const HEATMAP: number[][] = Array.from({ length: 52 }, (_, w) =>
  Array.from({ length: 7 }, (_, d) => {
    if (d === 0 || d === 6) return heatVal(w * 7 + d) * 0.35;
    const v = heatVal(w * 7 + d);
    return v > 0.28 ? v : 0;
  })
);
const MONTH_LABELS: Record<number, string> = {
  0: 'Apr', 4: 'May', 9: 'Jun', 13: 'Jul', 18: 'Aug', 22: 'Sep',
  27: 'Oct', 31: 'Nov', 36: 'Dec', 40: 'Jan', 44: 'Feb', 49: 'Mar',
};
const BARS = Array.from({ length: 14 }, (_, i) => ({
  work:     Math.round(Math.abs(Math.sin(i * 127 + 43)) * 4 * 3600),
  research: Math.round(Math.abs(Math.sin(i * 311 + 17)) * 1.5 * 3600),
}));
const BAR_DATES = Array.from({ length: 14 }, (_, i) => {
  const d = new Date(2026, 2, 5 + i);
  return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
});

function AnalyticsPanel() {
  const [activeTag, setActiveTag] = useState<string | null>(null);
  const filterLabels = ['All', 'Work', 'Research'];
  const pillRefs = useRef<(HTMLButtonElement | null)[]>([]);
  const filterWrapRef = useRef<HTMLDivElement>(null);
  const [fpill, setFpill] = useState({ left: 0, width: 0 });

  useLayoutEffect(() => {
    const idx = activeTag === null ? 0 : filterLabels.indexOf(activeTag);
    const el = pillRefs.current[idx];
    const wrap = filterWrapRef.current;
    if (el && wrap) {
      const wRect = wrap.getBoundingClientRect();
      const eRect = el.getBoundingClientRect();
      setFpill({ left: eRect.left - wRect.left, width: eRect.width });
    }
  }, [activeTag]);

  const maxBar = Math.max(...BARS.map(b => b.work + b.research), 1);
  const CHART_H = 110;

  const heatColor = (v: number) => {
    if (v <= 0) return C.insetBg;
    const rgb = activeTag === 'Research' ? '153,235,199' : '133,209,250';
    return `rgba(${rgb},${(0.22 + v * 0.78).toFixed(2)})`;
  };

  return (
    <div style={an.scroll}>
      <div ref={filterWrapRef} style={an.filterWrap}>
        <div style={{ ...an.filterPill, left: fpill.left, width: fpill.width }} />
        {filterLabels.map((label, i) => {
          const isActive = label === 'All' ? activeTag === null : activeTag === label;
          return (
            <button
              key={label}
              ref={el => { pillRefs.current[i] = el; }}
              onClick={() => setActiveTag(label === 'All' ? null : label)}
              style={{ ...an.filterBtn, color: isActive ? C.textPrimary : C.textSecondary }}
            >
              {label}
            </button>
          );
        })}
      </div>

      <div style={an.statRow}>
        <div style={an.statCard}>
          <div style={an.statNum}>84.2%</div>
          <div style={an.statLabel}>Tracked</div>
        </div>
        <div style={an.statCard}>
          <div style={an.statNum}>76.5%</div>
          <div style={an.statLabel}>Tagged</div>
        </div>
      </div>

      <div style={an.card}>
        <div style={an.cardTitle}>Last 365 Days</div>
        <div style={{ display: 'flex', gap: 7, alignItems: 'flex-start' }}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 3, paddingTop: 17, flexShrink: 0 }}>
            {['S','M','T','W','T','F','S'].map((d, i) => (
              <div key={i} style={{ width: 10, height: 9, fontSize: 7.5, color: C.textSecondary, lineHeight: '9px' }}>{d}</div>
            ))}
          </div>
          <div style={{ flex: 1, overflow: 'hidden' }}>
            <div style={{ display: 'flex', gap: 3, marginBottom: 4, height: 14 }}>
              {HEATMAP.map((_, w) => (
                <div key={w} style={{ width: 9, flexShrink: 0, fontSize: 7.5, color: C.textSecondary, whiteSpace: 'nowrap' as const }}>
                  {MONTH_LABELS[w] ?? ''}
                </div>
              ))}
            </div>
            <div style={{ display: 'flex', gap: 3 }}>
              {HEATMAP.map((col, w) => (
                <div key={w} style={{ display: 'flex', flexDirection: 'column', gap: 3 }}>
                  {col.map((v, d) => (
                    <div key={d} style={{ width: 9, height: 9, borderRadius: 2, background: heatColor(v), flexShrink: 0 }} />
                  ))}
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>

      <div style={{ ...an.card, marginBottom: 14 }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 10 }}>
          <div style={an.cardTitle}>Last 14 Days</div>
          <div style={{ display: 'flex', gap: 10 }}>
            {['Work', 'Research'].map(t => (
              <div key={t} style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
                <div style={{ width: 8, height: 8, borderRadius: 2, background: t === 'Work' ? C.tagWork : C.tagResearch }} />
                <span style={{ fontSize: 10, color: C.textSecondary }}>{t}</span>
              </div>
            ))}
          </div>
        </div>

        {/* Chart area */}
        <div style={{ position: 'relative' }}>
          {/* Horizontal gridlines */}
          {[0.25, 0.5, 0.75, 1].map(f => (
            <div key={f} style={{
              position: 'absolute', left: 0, right: 0,
              top: (1 - f) * CHART_H,
              height: 1,
              background: 'rgba(255,255,255,0.06)',
              pointerEvents: 'none',
            }} />
          ))}

          {/* Bars */}
          <div style={{ display: 'flex', gap: 3, alignItems: 'flex-end', height: CHART_H }}>
            {BARS.map((b, i) => {
              const wH = (b.work / maxBar) * CHART_H;
              const rH = (b.research / maxBar) * CHART_H;
              const totalH = Math.max(wH + rH, 2);
              return (
                <div key={i} style={{
                  flex: 1, minWidth: 0,
                  height: totalH,
                  borderRadius: '3px 3px 0 0',
                  overflow: 'hidden',
                  display: 'flex',
                  flexDirection: 'column',
                  alignSelf: 'flex-end',
                }}>
                  <div style={{ height: rH, background: C.tagResearch, opacity: 0.88, flexShrink: 0 }} />
                  <div style={{ height: wH, background: C.tagWork, opacity: 0.88, flexShrink: 0 }} />
                </div>
              );
            })}
          </div>

          {/* X-axis baseline */}
          <div style={{ height: 1, background: 'rgba(255,255,255,0.14)' }} />

          {/* X-axis labels */}
          <div style={{ display: 'flex', gap: 3, marginTop: 5 }}>
            {BARS.map((_, i) => (
              <div key={i} style={{ flex: 1, minWidth: 0 }}>
                <span style={{ fontSize: 7.5, color: C.textSecondary, whiteSpace: 'nowrap' as const }}>
                  {i % 3 === 0 ? BAR_DATES[i] : ''}
                </span>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

const an: Record<string, React.CSSProperties> = {
  scroll:     { overflowY: 'auto', padding: '12px 14px', display: 'flex', flexDirection: 'column', gap: 10, height: '100%' },
  filterWrap: { position: 'relative', display: 'inline-flex', background: C.insetBg, borderRadius: 20, padding: '6px 8px', gap: 2, alignSelf: 'flex-start' },
  filterPill: { position: 'absolute', top: 6, height: 'calc(100% - 12px)', background: C.accentDim, border: `0.8px solid ${C.accentBorder}`, borderRadius: 50, pointerEvents: 'none', transition: 'left 0.22s cubic-bezier(0.34,1.56,0.64,1), width 0.22s cubic-bezier(0.34,1.56,0.64,1)' },
  filterBtn:  { position: 'relative', zIndex: 1, background: 'none', border: 'none', cursor: 'pointer', fontSize: 12, fontWeight: 600, padding: '6px 14px', borderRadius: 50, fontFamily: 'Inter, sans-serif', transition: 'color 0.15s ease' },
  statRow:    { display: 'flex', gap: 10 },
  statCard:   { flex: 1, background: C.cardBg, borderRadius: 14, padding: '12px 14px' },
  statNum:    { fontSize: 22, fontWeight: 800, color: C.textPrimary, letterSpacing: '-0.03em' },
  statLabel:  { fontSize: 10.5, fontWeight: 600, color: C.textSecondary, marginTop: 2 },
  card:       { background: C.cardBg, borderRadius: 14, padding: '12px 14px' },
  cardTitle:  { fontSize: 12, fontWeight: 700, color: C.textPrimary, marginBottom: 10 },
};

// ─── Tags panel ────────────────────────────────────────────────────────────────
function PencilIcon() {
  return (
    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7" />
      <path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z" />
    </svg>
  );
}
function TrashIcon() {
  return (
    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
      <polyline points="3 6 5 6 21 6" />
      <path d="M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6" />
      <path d="M10 11v6M14 11v6" />
      <path d="M9 6V4a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2" />
    </svg>
  );
}

function TagsPanel() {
  const [adding, setAdding] = useState(false);
  const [newName, setNewName] = useState('');
  const [newDesc, setNewDesc] = useState('');

  return (
    <div style={tg.scroll}>
      <div style={tg.centered}>

        {/* ── Action section (matches Form Section with Add/edit form) ── */}
        <div style={tg.group}>
          {adding ? (
            <div style={tg.form}>
              <input
                value={newName}
                onChange={e => setNewName(e.target.value)}
                placeholder="Tag name"
                autoFocus
                style={tg.input}
              />
              <textarea
                value={newDesc}
                onChange={e => setNewDesc(e.target.value)}
                placeholder="Description"
                rows={3}
                style={tg.textarea}
              />
              <div style={{ display: 'flex', gap: 8 }}>
                <button style={tg.btnPrimary} onClick={() => { setAdding(false); setNewName(''); setNewDesc(''); }}>
                  Add Tag
                </button>
                <button style={tg.btnGlass} onClick={() => { setAdding(false); setNewName(''); setNewDesc(''); }}>
                  Cancel
                </button>
              </div>
            </div>
          ) : (
            <button style={tg.btnPrimary} onClick={() => setAdding(true)}>
              <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round">
                <line x1="12" y1="5" x2="12" y2="19" /><line x1="5" y1="12" x2="19" y2="12" />
              </svg>
              Add New Tag
            </button>
          )}
        </div>

        {/* ── Tags section (matches Form Section("Tags")) ── */}
        <div style={tg.sectionHeader}>Tags</div>
        <div style={tg.group}>
          {TAGS_DATA.map((tag, i) => (
            <React.Fragment key={tag.id}>
              {i > 0 && <div style={tg.divider} />}
              <div style={tg.tagRow}>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={tg.tagName}>{tag.name}</div>
                  <div style={tg.tagDesc}>{tag.description}</div>
                </div>
                <div style={{ display: 'flex', gap: 7, flexShrink: 0 }}>
                  <button style={tg.btnGlass}>
                    <PencilIcon /> Edit
                  </button>
                  <button style={{ ...tg.btnGlass, color: C.recordActive, borderColor: 'rgba(250,163,184,0.22)' }}>
                    <TrashIcon /> Delete
                  </button>
                </div>
              </div>
            </React.Fragment>
          ))}
        </div>

      </div>
    </div>
  );
}

const tg: Record<string, React.CSSProperties> = {
  scroll:        { overflowY: 'auto', height: '100%', padding: '14px 16px' },
  centered:      { maxWidth: 560, margin: '0 auto', display: 'flex', flexDirection: 'column', gap: 0 },
  group: {
    background: C.cardBg,
    borderRadius: 14,
    border: '1px solid rgba(255,255,255,0.07)',
    overflow: 'hidden',
    marginBottom: 8,
    padding: '6px 14px',
  },
  form:          { display: 'flex', flexDirection: 'column', gap: 10, padding: '8px 0' },
  input: {
    background: C.insetBg,
    border: '1px solid rgba(255,255,255,0.10)',
    borderRadius: 8,
    color: C.textPrimary,
    fontSize: 12,
    padding: '8px 10px',
    outline: 'none',
    fontFamily: 'Inter, sans-serif',
  },
  textarea: {
    background: C.insetBg,
    border: '1px solid rgba(255,255,255,0.10)',
    borderRadius: 8,
    color: C.textPrimary,
    fontSize: 12,
    padding: '8px 10px',
    outline: 'none',
    fontFamily: 'Inter, sans-serif',
    resize: 'vertical' as const,
  },
  btnPrimary: {
    display: 'inline-flex',
    alignItems: 'center',
    gap: 7,
    padding: '8px 16px',
    background: C.accentDim,
    border: `0.8px solid ${C.accentBorder}`,
    borderRadius: 10,
    color: C.accent,
    fontSize: 12,
    fontWeight: 600,
    cursor: 'pointer',
    fontFamily: 'Inter, sans-serif',
    backdropFilter: 'blur(8px)',
    margin: '6px 0',
  },
  btnGlass: {
    display: 'inline-flex',
    alignItems: 'center',
    gap: 5,
    padding: '6px 12px',
    background: 'rgba(255,255,255,0.06)',
    border: '0.8px solid rgba(255,255,255,0.14)',
    borderRadius: 8,
    color: C.textPrimary,
    fontSize: 11,
    fontWeight: 500,
    cursor: 'pointer',
    fontFamily: 'Inter, sans-serif',
  },
  sectionHeader: {
    fontSize: 10.5,
    fontWeight: 700,
    color: C.textSecondary,
    textTransform: 'uppercase' as const,
    letterSpacing: '0.07em',
    padding: '10px 4px 4px',
  },
  tagRow:  { display: 'flex', alignItems: 'center', gap: 14, padding: '11px 0' },
  tagName: { fontSize: 13, fontWeight: 600, color: C.textPrimary, marginBottom: 3 },
  tagDesc: { fontSize: 11, color: C.textSecondary, lineHeight: 1.5 },
  divider: { height: 1, background: 'rgba(255,255,255,0.06)', margin: '0 -14px' },
};

// ─── Calendar panel ────────────────────────────────────────────────────────────
function CalendarPanel() {
  const scrollRef = useRef<HTMLDivElement>(null);
  const HOUR_H = 52;          // px per hour
  const TIME_LABEL_W = 36;    // px

  // Auto-scroll to show ~8am on mount
  useEffect(() => {
    if (scrollRef.current) {
      scrollRef.current.scrollTop = 8 * HOUR_H - 10;
    }
  }, []);

  // Build calendar grid cells: leading empty cells + days
  const cells: (number | null)[] = [
    ...Array.from({ length: MARCH_START_DOW }, () => null),
    ...MARCH_2026,
  ];
  // pad to full weeks
  while (cells.length % 7 !== 0) cells.push(null);

  function isAvailable(day: number | null) {
    if (!day) return false;
    return day >= AVAILABLE_RANGE[0] && day <= AVAILABLE_RANGE[1];
  }

  function timelineColor(overviewID: number | null) {
    if (overviewID === null) return C.timelineUnassigned;
    return C.timeline[overviewID % C.timeline.length];
  }

  return (
    <div style={{ display: 'flex', height: '100%', gap: 0, overflow: 'hidden' }}>
      {/* ── Mini calendar ── */}
      <div style={cal.calCol}>
        {/* Glass card */}
        <div style={cal.calCard}>
          {/* Month label */}
          <div style={cal.monthLabel}>March 2026</div>

          {/* Weekday headers */}
          <div style={cal.weekdayRow}>
            {['S','M','T','W','T','F','S'].map((d, i) => (
              <div key={i} style={cal.weekdayHdr}>{d}</div>
            ))}
          </div>

          {/* Day grid */}
          <div style={cal.dayGrid}>
            {cells.map((day, idx) => {
              const selected = day === SELECTED_DAY;
              const available = isAvailable(day);
              return (
                <div key={idx} style={cal.dayCell}>
                  {day !== null && (
                    <div style={{
                      ...cal.dayNum,
                      opacity: available ? 1 : 0.32,
                      color: selected ? C.textPrimary : available ? C.textPrimary : C.textSecondary,
                      fontWeight: selected ? 600 : 400,
                      position: 'relative',
                    }}>
                      {selected && (
                        <div style={cal.selectedCircle} />
                      )}
                      <span style={{ position: 'relative', zIndex: 1 }}>{day}</span>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </div>
      </div>

      {/* ── Divider ── */}
      <div style={{ width: 1, background: 'rgba(255,255,255,0.06)', flexShrink: 0, margin: '12px 0' }} />

      {/* ── 24-hour timeline ── */}
      <div ref={scrollRef} style={cal.timelineScroll}>
        <div style={{ position: 'relative', height: 24 * HOUR_H, minWidth: 0 }}>
          {/* Hour lines + labels */}
          {Array.from({ length: 24 }, (_, h) => (
            <div key={h} style={{ position: 'absolute', top: h * HOUR_H, left: 0, right: 0, display: 'flex', alignItems: 'flex-start' }}>
              <span style={{ width: TIME_LABEL_W, fontSize: 9.5, color: C.textSecondary, flexShrink: 0, paddingTop: 1, textAlign: 'right', paddingRight: 8 }}>
                {h === 0 ? '12 AM' : h < 12 ? `${h} AM` : h === 12 ? '12 PM' : `${h - 12} PM`}
              </span>
              <div style={{ flex: 1, height: 1, background: 'rgba(255,255,255,0.06)', marginTop: 6 }} />
            </div>
          ))}

          {/* Activity blocks */}
          {TIMELINE_BLOCKS.map((block, i) => {
            const top = (block.startS / 3600) * HOUR_H;
            const height = Math.max(((block.endS - block.startS) / 3600) * HOUR_H - 1, 4);
            return (
              <div
                key={i}
                style={{
                  position: 'absolute',
                  top,
                  left: TIME_LABEL_W + 4,
                  right: 14,
                  height,
                  background: timelineColor(block.overviewID),
                  borderRadius: 8,
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  overflow: 'hidden',
                }}
              >
                {height > 18 && (
                  <span style={{ fontSize: 10, fontWeight: 600, color: 'rgba(14,18,26,0.88)', textAlign: 'center', padding: '0 6px' }}>
                    {block.title || 'Unassigned'}
                  </span>
                )}
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}

const cal: Record<string, React.CSSProperties> = {
  calCol:       { width: 210, flexShrink: 0, padding: '14px 12px', display: 'flex', flexDirection: 'column' },
  calCard: {
    background: 'rgba(48,56,74,0.55)',
    border: '0.8px solid rgba(255,255,255,0.14)',
    borderRadius: 18,
    padding: '14px 10px',
    backdropFilter: 'blur(12px)',
    boxShadow: '0 8px 24px rgba(120,199,245,0.06)',
  },
  monthLabel:   { fontSize: 13, fontWeight: 600, color: C.textPrimary, textAlign: 'center', marginBottom: 10 },
  weekdayRow:   { display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', marginBottom: 4 },
  weekdayHdr:   { fontSize: 10, color: C.textSecondary, textAlign: 'center', fontWeight: 500, padding: '2px 0' },
  dayGrid:      { display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gap: '2px 0' },
  dayCell:      { display: 'flex', alignItems: 'center', justifyContent: 'center', height: 26 },
  dayNum: {
    width: 24, height: 24,
    display: 'flex', alignItems: 'center', justifyContent: 'center',
    fontSize: 11, borderRadius: '50%', cursor: 'default',
  },
  selectedCircle: {
    position: 'absolute',
    inset: 0,
    borderRadius: '50%',
    background: 'rgba(120,199,245,0.24)',
    border: '0.8px solid rgba(255,255,255,0.38)',
    backdropFilter: 'blur(8px)',
    boxShadow: '0 4px 12px rgba(120,199,245,0.20)',
  },
  timelineScroll: {
    flex: 1,
    overflowY: 'auto',
    overflowX: 'hidden',
    padding: '14px 0',
  },
};

// ─── Settings panel ────────────────────────────────────────────────────────────
const PERMISSIONS = [
  { title: 'Accessibility',      subtitle: 'Required for global keystroke capture.',            granted: true },
  { title: 'Screen Recording',   subtitle: 'Required for screenshot capture.',                  granted: true },
  { title: 'Microphone',         subtitle: 'Required for background audio capture.',            granted: true },
  { title: 'Speech Recognition', subtitle: 'Required for live on-device voice transcription.', granted: false },
];

function CheckCircle({ granted }: { granted: boolean }) {
  const color = granted ? '#22c55e' : '#ef4444';
  return (
    <svg width="16" height="16" viewBox="0 0 16 16" fill="none" style={{ flexShrink: 0 }}>
      <circle cx="8" cy="8" r="8" fill={color} opacity="0.15" />
      {granted
        ? <path d="M5 8l2 2 4-4" stroke={color} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
        : <path d="M5 5l6 6M11 5l-6 6" stroke={color} strokeWidth="1.6" strokeLinecap="round" />
      }
    </svg>
  );
}

function SettingsPanel() {
  return (
    <div style={st.scroll}>
      <div style={st.sectionLabel}>Permissions</div>
      <div style={st.card}>
        <p style={st.intro}>
          TaskTrace needs Accessibility, Screen Recording, Microphone, and Speech Recognition to capture keystrokes, screenshots, and live transcription.
        </p>
        {PERMISSIONS.map((p, i) => (
          <React.Fragment key={p.title}>
            {i > 0 && <div style={st.divider} />}
            <div style={st.row}>
              <CheckCircle granted={p.granted} />
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={st.permTitle}>{p.title}</div>
                <div style={st.permSub}>{p.subtitle}</div>
              </div>
              <span style={{ ...st.badge, color: p.granted ? '#22c55e' : '#ef4444', background: p.granted ? 'rgba(34,197,94,0.1)' : 'rgba(239,68,68,0.1)' }}>
                {p.granted ? 'Granted' : 'Missing'}
              </span>
            </div>
          </React.Fragment>
        ))}
      </div>
    </div>
  );
}

const st: Record<string, React.CSSProperties> = {
  scroll:      { overflowY: 'auto', padding: '12px 14px', display: 'flex', flexDirection: 'column', gap: 8, height: '100%' },
  sectionLabel:{ fontSize: 10.5, fontWeight: 700, color: C.textSecondary, textTransform: 'uppercase', letterSpacing: '0.07em', padding: '2px 4px 2px' },
  card:        { background: C.cardBg, borderRadius: 14, padding: '0 14px' },
  intro:       { fontSize: 11, color: C.textSecondary, lineHeight: 1.6, padding: '10px 0 8px', borderBottom: '1px solid rgba(255,255,255,0.06)', marginBottom: 0 },
  divider:     { height: 1, background: 'rgba(255,255,255,0.06)' },
  row:         { display: 'flex', alignItems: 'center', gap: 10, padding: '10px 0' },
  permTitle:   { fontSize: 12.5, fontWeight: 600, color: C.textPrimary, marginBottom: 2 },
  permSub:     { fontSize: 11, color: C.textSecondary, lineHeight: 1.4 },
  badge:       { fontSize: 10.5, fontWeight: 600, borderRadius: 50, padding: '2px 9px', flexShrink: 0 },
};

// ─── Search panel ─────────────────────────────────────────────────────────────
const GRAPH_COLORS = {
  overview:   '#7fc2f0',
  activity:   '#8bdac8',
  screenshot: '#f6d28f',
  edge:       'rgba(255,255,255,0.16)',
  grid:       'rgba(255,255,255,0.08)',
  nodeStroke: 'rgba(17,24,39,0.95)',
};

// Static mock graph nodes + links matching the AppDemo mock data
const GRAPH_NODES: { id: string; kind: 'overview' | 'activity' | 'screenshot'; label: string; x: number; y: number; r: number; glow: number }[] = [
  // Tree 1: ActivityActor Pipeline
  { id: 'o1', kind: 'overview',   label: 'ActivityActor Pipeline',  x: 190, y: 130, r: 14, glow: 0.9 },
  { id: 'a1', kind: 'activity',   label: 'Xcode',                   x: 120, y:  68, r: 10, glow: 0.6 },
  { id: 'a2', kind: 'activity',   label: 'Terminal',                 x: 260, y:  82, r: 10, glow: 0.3 },
  { id: 's1', kind: 'screenshot', label: '',                         x:  62, y:  36, r:  6, glow: 0.4 },
  { id: 's2', kind: 'screenshot', label: '',                         x: 100, y:  22, r:  6, glow: 0.0 },
  { id: 's3', kind: 'screenshot', label: '',                         x: 298, y:  38, r:  6, glow: 0.0 },
  { id: 's4', kind: 'screenshot', label: '',                         x: 330, y:  70, r:  6, glow: 0.2 },
  // Tree 2: MLX Benchmarks
  { id: 'o2', kind: 'overview',   label: 'MLX Benchmarks',          x: 480, y: 148, r: 14, glow: 0.7 },
  { id: 'a3', kind: 'activity',   label: 'Safari',                   x: 420, y: 218, r: 10, glow: 0.5 },
  { id: 's5', kind: 'screenshot', label: '',                         x: 370, y: 268, r:  6, glow: 0.0 },
  { id: 's6', kind: 'screenshot', label: '',                         x: 440, y: 280, r:  6, glow: 0.1 },
  { id: 'a4', kind: 'activity',   label: 'Notes',                    x: 556, y: 206, r: 10, glow: 0.2 },
  { id: 's7', kind: 'screenshot', label: '',                         x: 600, y: 256, r:  6, glow: 0.0 },
];

const GRAPH_LINKS: { from: string; to: string }[] = [
  { from: 'o1', to: 'a1' }, { from: 'o1', to: 'a2' },
  { from: 'a1', to: 's1' }, { from: 'a1', to: 's2' },
  { from: 'a2', to: 's3' }, { from: 'a2', to: 's4' },
  { from: 'o2', to: 'a3' }, { from: 'o2', to: 'a4' },
  { from: 'a3', to: 's5' }, { from: 'a3', to: 's6' },
  { from: 'a4', to: 's7' },
];

function SearchPanel() {
  const [query, setQuery] = useState('ActivityActor pipeline');
  const nodeMap = Object.fromEntries(GRAPH_NODES.map(n => [n.id, n]));

  return (
    <div style={sr.scroll}>
      {/* Search bar */}
      <div style={sr.barRow}>
        <div style={sr.barWrap}>
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke={C.textSecondary} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={{ flexShrink: 0 }}>
            <circle cx="11" cy="11" r="8" /><line x1="21" y1="21" x2="16.65" y2="16.65" />
          </svg>
          <input
            value={query}
            onChange={e => setQuery(e.target.value)}
            placeholder="Search activities, screenshots, and overviews"
            style={sr.input}
          />
        </div>
        <button style={sr.searchBtn}>
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
            <circle cx="11" cy="11" r="8" /><line x1="21" y1="21" x2="16.65" y2="16.65" />
          </svg>
        </button>
      </div>

      {/* Graph visualization mock */}
      <div style={sr.graphShell}>
        <div style={sr.graphPane}>
          <div style={sr.graphPaneBadge}>Knowledge Graph</div>
          <svg viewBox="0 0 660 320" width="100%" height="100%" style={{ display: 'block' }}>
            <defs>
              <filter id="demo-glow" x="-70%" y="-70%" width="240%" height="240%">
                <feGaussianBlur stdDeviation="7" result="blur" />
                <feMerge><feMergeNode in="blur" /><feMergeNode in="SourceGraphic" /></feMerge>
              </filter>
              <radialGradient id="bg-grad-1" cx="14%" cy="8%" r="28%">
                <stop offset="0%" stopColor="rgba(127,194,240,0.12)" />
                <stop offset="100%" stopColor="transparent" />
              </radialGradient>
              <radialGradient id="bg-grad-2" cx="82%" cy="86%" r="24%">
                <stop offset="0%" stopColor="rgba(139,218,200,0.14)" />
                <stop offset="100%" stopColor="transparent" />
              </radialGradient>
            </defs>

            <rect width="660" height="320" fill="rgba(255,255,255,0.02)" rx="12" />
            <rect width="660" height="320" fill="url(#bg-grad-1)" rx="12" />
            <rect width="660" height="320" fill="url(#bg-grad-2)" rx="12" />

            <line x1="60" y1="306" x2="620" y2="306" stroke={GRAPH_COLORS.grid} strokeWidth="1.5" />
            {['9:14 AM', '10:02 AM', '10:47 AM', '11:30 AM'].map((t, i) => {
              const x = 100 + i * 160;
              return (
                <g key={t}>
                  <line x1={x} y1={298} x2={x} y2={312} stroke={GRAPH_COLORS.grid} strokeWidth="1.2" />
                  <text x={x} y={324} textAnchor="middle" fontSize="9" fill={C.textSecondary} fontFamily="SF Pro Text, Helvetica Neue, sans-serif">{t}</text>
                </g>
              );
            })}
            <text x="620" y="296" textAnchor="end" fontSize="10" fontWeight="700" fill={GRAPH_COLORS.overview} fontFamily="SF Pro Text, Helvetica Neue, sans-serif">Time</text>

            {GRAPH_LINKS.map(({ from, to }) => {
              const a = nodeMap[from], b = nodeMap[to];
              return <line key={`${from}-${to}`} x1={a.x} y1={a.y} x2={b.x} y2={b.y} stroke={GRAPH_COLORS.edge} strokeWidth="1.4" />;
            })}

            {GRAPH_NODES.map(n => {
              const fill = GRAPH_COLORS[n.kind];
              return (
                <g key={n.id}>
                  {n.glow > 0 && (
                    <circle cx={n.x} cy={n.y} r={n.r + 8 + n.glow * 14} fill={fill} opacity={0.1 + n.glow * 0.28} filter="url(#demo-glow)" />
                  )}
                  <circle cx={n.x} cy={n.y} r={n.r} fill={fill} stroke={GRAPH_COLORS.nodeStroke} strokeWidth="1.2" />
                  {n.label && (
                    <text x={n.x} y={n.y - n.r - 6} textAnchor="middle" fontSize="9.5" fill={C.textPrimary} fontFamily="SF Pro Text, Helvetica Neue, sans-serif">{n.label}</text>
                  )}
                </g>
              );
            })}
          </svg>
        </div>
      </div>
    </div>
  );
}

const sr: Record<string, React.CSSProperties> = {
  scroll:    { overflowY: 'auto', padding: '12px 14px', display: 'flex', flexDirection: 'column', gap: 10, height: '100%' },
  barRow:    { display: 'flex', gap: 8, alignItems: 'center' },
  barWrap: {
    flex: 1,
    display: 'flex',
    alignItems: 'center',
    gap: 8,
    background: C.insetBg,
    border: '1px solid rgba(255,255,255,0.10)',
    borderRadius: 10,
    padding: '8px 10px',
  },
  input: {
    flex: 1,
    background: 'none',
    border: 'none',
    outline: 'none',
    color: C.textPrimary,
    fontSize: 12,
    fontFamily: 'Inter, sans-serif',
  },
  searchBtn: {
    width: 34,
    height: 34,
    borderRadius: 10,
    background: C.accentDim,
    border: `0.8px solid ${C.accentBorder}`,
    color: C.accent,
    cursor: 'pointer',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    flexShrink: 0,
    backdropFilter: 'blur(8px)',
  },
  graphShell: {
    flex: 1,
    minHeight: 0,
    borderRadius: 14,
    overflow: 'hidden',
    background: 'linear-gradient(180deg, rgba(255,255,255,0.02), rgba(255,255,255,0.01))',
    border: '1px solid rgba(255,255,255,0.07)',
  },
  splitRow: {
    display: 'flex',
    height: '100%',
    minHeight: 0,
  },
  graphPane: {
    flex: 1,
    minWidth: 0,
    position: 'relative',
    height: '100%',
    padding: '10px 10px 0',
  },
  graphPaneBadge: {
    position: 'absolute',
    top: 12,
    left: 12,
    padding: '4px 8px',
    borderRadius: 999,
    background: 'rgba(120,199,245,0.16)',
    border: '1px solid rgba(255,255,255,0.12)',
    color: C.accent,
    fontSize: 9.5,
    fontWeight: 700,
    letterSpacing: '0.04em',
    textTransform: 'uppercase' as const,
    zIndex: 1,
  },
};

function AgentsPanel() {
  return (
    <div style={ag.scroll}>
      <div style={ag.tabs}>
        <span style={ag.activeTab}>Skills</span>
        <span style={ag.tab}>MCP</span>
      </div>

      <div style={ag.card}>
        <div style={ag.cardHeader}>
          <span style={ag.cardTitle}>Generated Skill</span>
          <span style={ag.badge}>Ready</span>
        </div>
        <div style={ag.skillTitle}>Debug flaky Swift actor tests</div>
        <div style={ag.skillText}>
          Search recent test failures, inspect actor update streams, and add focused assertions before changing scheduling behavior.
        </div>
      </div>

      <div style={ag.card}>
        <div style={ag.cardHeader}>
          <span style={ag.cardTitle}>MCP Tool</span>
          <span style={ag.badge}>Enabled</span>
        </div>
        <div style={ag.toolName}>tasktrace_push_message</div>
        <div style={ag.skillText}>
          Agents can ask TaskTrace to show a macOS notification through the MCP tool surface.
        </div>
      </div>
    </div>
  );
}

const ag: Record<string, React.CSSProperties> = {
  scroll: { overflowY: 'auto', padding: '12px 14px', display: 'flex', flexDirection: 'column', gap: 10, height: '100%' },
  tabs: { display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap' as const },
  activeTab: { border: '1px solid rgba(255,255,255,0.12)', borderRadius: 999, padding: '8px 12px', fontSize: 11, fontWeight: 700, background: 'rgba(255,255,255,0.12)', color: C.textPrimary },
  tab: { border: '1px solid rgba(255,255,255,0.08)', borderRadius: 999, padding: '8px 12px', fontSize: 11, fontWeight: 700, color: C.textSecondary },
  card: { borderRadius: 14, padding: '14px 16px', border: '1px solid rgba(255,255,255,0.08)', background: 'rgba(255,255,255,0.06)' },
  cardHeader: { display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 10, marginBottom: 10 },
  cardTitle: { fontSize: 10, fontWeight: 800, color: C.textSecondary, textTransform: 'uppercase' as const },
  badge: { fontSize: 9, fontWeight: 700, color: '#28c840', background: 'rgba(40,200,64,0.12)', borderRadius: 999, padding: '4px 9px' },
  skillTitle: { fontSize: 13, fontWeight: 700, color: C.textPrimary, marginBottom: 6 },
  skillText: { fontSize: 11.5, color: C.textSecondary, lineHeight: 1.55 },
  toolName: { fontSize: 12, fontWeight: 700, color: C.accent, fontFamily: 'SFMono-Regular, Menlo, monospace', marginBottom: 6 },
};

// ─── MCP panel ────────────────────────────────────────────────────────────────
const MCP_URL   = 'http://127.0.0.1:32123/mcp';
const MCP_TOKEN = 'tt_9f2a4b8c1d3e6f7a';

function ToggleSwitch({ value, onChange }: { value: boolean; onChange: (v: boolean) => void }) {
  return (
    <div
      onClick={() => onChange(!value)}
      style={{
        width: 34, height: 19, borderRadius: 10,
        background: value ? C.accent : 'rgba(255,255,255,0.18)',
        position: 'relative', cursor: 'pointer',
        transition: 'background 0.2s ease', flexShrink: 0,
      }}
    >
      <div style={{
        position: 'absolute', top: 2,
        left: value ? 17 : 2, width: 15, height: 15,
        borderRadius: '50%', background: '#fff',
        boxShadow: '0 1px 4px rgba(0,0,0,0.3)',
        transition: 'left 0.2s ease',
      }} />
    </div>
  );
}

function McpConfigRow({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div style={mcp.configRow}>
      <span style={mcp.configLabel}>{label}</span>
      {children}
    </div>
  );
}

function McpResourceRow({
  title, description, uri, enabled, onToggle, warning,
}: {
  title: string; description: string; uri: string;
  enabled: boolean; onToggle: (v: boolean) => void;
  warning?: string;
}) {
  return (
    <div style={mcp.row}>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={mcp.rowTitle}>{title}</div>
        <div style={mcp.rowDesc}>{description}</div>
        <div style={mcp.rowUri}>{uri}</div>
        {warning && <div style={mcp.rowWarning}>{warning}</div>}
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 14, flexShrink: 0 }}>
        <ToggleSwitch value={enabled} onChange={onToggle} />
      </div>
    </div>
  );
}

function McpPanel() {
  const [serverEnabled,   setServerEnabled]   = useState(true);
  const [securityEnabled, setSecurityEnabled] = useState(false);
  const [overviewEnabled, setOverviewEnabled] = useState(true);
  const [highEnabled,     setHighEnabled]     = useState(true);
  const [detailedEnabled, setDetailedEnabled] = useState(false);

  return (
    <div style={mcp.scroll}>
      {/* Server config card */}
      <div style={mcp.card}>
        <p style={mcp.intro}>
          TaskTrace can keep a local MCP server available whenever the app is running.
          Use this panel to decide which feeds external AI clients can read.
        </p>
        <div style={mcp.configGrid}>
          <McpConfigRow label="Enable MCP Server">
            <ToggleSwitch value={serverEnabled} onChange={setServerEnabled} />
          </McpConfigRow>
          <div style={mcp.configDivider} />
          <McpConfigRow label="Security">
            <ToggleSwitch value={securityEnabled} onChange={setSecurityEnabled} />
          </McpConfigRow>
          <div style={mcp.configDivider} />
          <McpConfigRow label="Server URL">
            <span style={mcp.monoText}>{MCP_URL}</span>
          </McpConfigRow>
          {securityEnabled && (
            <>
              <div style={mcp.configDivider} />
              <McpConfigRow label="Bearer Token">
                <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
                  <button style={mcp.copyBtn}>Copy</button>
                  <div style={mcp.tokenBox}>{MCP_TOKEN}</div>
                </div>
              </McpConfigRow>
            </>
          )}
        </div>
      </div>

      {/* Published feeds */}
      <div style={{ opacity: serverEnabled ? 1 : 0.5, transition: 'opacity 0.2s ease' }}>
        <div style={mcp.feedsLabel}>Published Feeds</div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          <McpResourceRow
            title="Overview Feed"
            description="Publishes the active day overview titles, summaries, and durations."
            uri="tasktrace://overviews/active-day"
            enabled={overviewEnabled} onToggle={setOverviewEnabled}
          />
          <McpResourceRow
            title="High Level Activity Feed"
            description="Publishes recently completed activities with their summaries."
            uri="tasktrace://activities/high-level"
            enabled={highEnabled} onToggle={setHighEnabled}
          />
          <McpResourceRow
            title="Detailed Activity Feed"
            description="Publishes recent activities with keystrokes, transcripts, summaries, and screenshots."
            uri="tasktrace://activities/detailed"
            enabled={detailedEnabled} onToggle={setDetailedEnabled}
            warning="Warning! Enabling will introduce sensitive data to your agents!"
          />
        </div>
      </div>
    </div>
  );
}

const mcp: Record<string, React.CSSProperties> = {
  scroll:        { overflowY: 'auto', padding: '12px 14px', display: 'flex', flexDirection: 'column', gap: 10, height: '100%' },
  card:          { background: C.cardBg, borderRadius: 14, border: '1px solid rgba(255,255,255,0.07)', padding: '0 14px', overflow: 'hidden' },
  intro:         { fontSize: 11, color: C.textSecondary, lineHeight: 1.6, padding: '10px 0 8px', borderBottom: '1px solid rgba(255,255,255,0.06)', margin: 0 },
  configGrid:    { display: 'flex', flexDirection: 'column' },
  configRow:     { display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '9px 0', gap: 12, minHeight: 38 },
  configLabel:   { fontSize: 12, fontWeight: 600, color: C.textSecondary, width: 120, flexShrink: 0 },
  configDivider: { height: 1, background: 'rgba(255,255,255,0.06)' },
  monoText:      { fontFamily: 'monospace', fontSize: 11, color: C.textPrimary },
  copyBtn:       { alignSelf: 'flex-start', padding: '3px 10px', background: 'rgba(255,255,255,0.08)', border: '0.8px solid rgba(255,255,255,0.14)', borderRadius: 7, color: C.textPrimary, fontSize: 10.5, fontWeight: 500, cursor: 'pointer', fontFamily: 'Inter, sans-serif' },
  tokenBox:      { fontFamily: 'monospace', fontSize: 10, color: C.textSecondary, background: 'rgba(255,255,255,0.06)', borderRadius: 8, padding: '6px 8px', wordBreak: 'break-all' as const, maxWidth: 200 },
  feedsLabel:    { fontSize: 12, fontWeight: 700, color: C.textPrimary, marginBottom: 8 },
  row:           { background: C.cardBg, borderRadius: 14, border: '1px solid rgba(255,255,255,0.07)', padding: '12px 14px', display: 'flex', alignItems: 'center', gap: 14 },
  rowTitle:      { fontSize: 12.5, fontWeight: 700, color: C.textPrimary, marginBottom: 2 },
  rowDesc:       { fontSize: 11, color: C.textSecondary, lineHeight: 1.5, marginBottom: 4 },
  rowUri:        { fontFamily: 'monospace', fontSize: 9.5, color: C.accent, opacity: 0.85 },
  rowWarning:    { fontSize: 10, fontWeight: 600, color: '#ef4444', marginTop: 4 },
};

// ─── Explainer content per tab + record button ────────────────────────────────
export type ExplainerSource = NavItem | 'RecordButton';
export const OVERLAY: Record<ExplainerSource, { subtitle: string; bullets: string[] }> = {
  RecordButton: {
    subtitle: 'You decide when TaskTrace records. Full stop.',
    bullets: [
      'Press play to start a session. TaskTrace begins capturing immediately.',
      'Press stop and all recording ceases. Nothing runs in the background.',
      'There is no passive or always-on mode. The button is the only switch.',
      'You can review or delete any session from the Activity view at any time.',
    ],
  },
  Activity: {
    subtitle: 'Every app session you recorded, in reverse-chronological order.',
    bullets: [
      'Each card shows the app, bundle ID, time range, and duration',
      'The Summary tab shows the AI-generated description of what you did',
      'Switch to Keystrokes or Microphone tabs to see raw captured data',
      'Assign a tag to any activity to track time by project or client',
    ],
  },
  Calendar: {
    subtitle: 'Browse your full work history day by day.',
    bullets: [
      'Dates with recorded sessions appear at full opacity on the calendar',
      'Click any available date to load that day\'s timeline',
      'The 24-hour timeline on the right shows your sessions as colored blocks',
      'Each block\'s color corresponds to the overview it belongs to',
    ],
  },
  Analytics: {
    subtitle: 'See patterns in how you spend your time.',
    bullets: [
      'The heatmap shows total tracked time for every day in the last year',
      'Click a tag filter to isolate a specific project or client',
      'The bar chart breaks down the last 14 days by tag',
      'Tracked % is captured workday. Tagged % is how much of that is categorized.',
    ],
  },
  Overview: {
    subtitle: 'AI-generated summaries that group related activities together.',
    bullets: [
      'TaskTrace clusters your raw activities into named, coherent overviews',
      'Each overview has a title, summary paragraph, and estimated duration',
      'Source activity chips let you jump back to the raw recordings',
      'Assign a tag to flow time directly into analytics and billing exports',
    ],
  },
  Search: {
    subtitle: 'Find anything you\'ve done with a natural-language search.',
    bullets: [
      'Type a query and TaskTrace searches across activities, overviews, and screenshots',
      'Results appear as an interactive 3D graph — drag to rotate, click nodes for details',
      'Node glow intensity shows how closely each result matches your query',
      'Large nodes are overviews, medium are activities, and small are screenshots',
    ],
  },
  Tags: {
    subtitle: 'Custom labels that organize your time across every view.',
    bullets: [
      'Create tags for clients, projects, or billing categories',
      'AI automatically suggests the right tag for each activity after recording',
      'Tags appear across Activity, Overview, Analytics, and Calendar views',
      'Use the Edit button to rename a tag or update its description at any time',
    ],
  },
  Agents: {
    subtitle: 'Reusable skills and MCP tools that give agents TaskTrace context.',
    bullets: [
      'Generated skills capture repeatable workflows from your recent work',
      'MCP resources let agents read current activities, todos, screenshots, and graph context',
      'Agents can add todos and goals without leaving your workflow',
      'Agents can push concise macOS notifications through TaskTrace when something needs attention',
    ],
  },
  Settings: {
    subtitle: 'Configure TaskTrace to fit your workflow.',
    bullets: [
      'Toggle screen recording, keystroke capture, and microphone on or off',
      'Manage macOS permissions for accessibility and screen recording',
      'Enable or disable the local MCP server that AI agents connect to',
      'Set your data retention period and delete individual sessions',
    ],
  },
  MCP: {
    subtitle: 'Your agents know what you\'re working on — without you telling them.',
    bullets: [
      'AI tools like Claude and Cursor can read your live work context on demand',
      'Agents respond to what you\'re actually doing, not just what you typed last',
      'No more re-explaining your project, codebase, or goals at the start of every chat',
      'Proactive suggestions become possible when your tools have real situational awareness',
    ],
  },
};

// ─── Main AppDemo component ────────────────────────────────────────────────────
export interface AppDemoProps {
  /** When set, the active nav is controlled externally (scroll-driven tour). */
  controlledNav?: NavItem;
  /** Hide the explainer section below the demo window. */
  hideExplainer?: boolean;
  /** Render only the active panel content — no window chrome, sidebar, or title bar. */
  chromeless?: boolean;
}

export default function AppDemo({ controlledNav, hideExplainer, chromeless }: AppDemoProps = {}) {
  const [internalNav, setInternalNav] = useState<NavItem>('Analytics');
  const activeNav = controlledNav ?? internalNav;
  const [displaySource, setDisplaySource] = useState<ExplainerSource>('Analytics');
  const [explainerVisible, setExplainerVisible] = useState(true);
  const pendingExplainer = useRef<ExplainerSource | null>(null);
  const [isRecording, setIsRecording] = useState(true);

  function showExplainer(source: ExplainerSource) {
    if (controlledNav) return; // skip explainer in controlled mode
    pendingExplainer.current = source;
    setExplainerVisible(false);
  }

  useEffect(() => {
    if (!explainerVisible && pendingExplainer.current !== null) {
      const id = setTimeout(() => {
        setDisplaySource(pendingExplainer.current!);
        pendingExplainer.current = null;
        setExplainerVisible(true);
      }, 350);
      return () => clearTimeout(id);
    }
  }, [explainerVisible]);

  const btnColor     = isRecording ? C.recordActive    : C.accent;
  const btnDimColor  = isRecording ? C.recordActiveDim : C.accentDim;
  const btnGlow      = isRecording
    ? '0 8px 28px rgba(250,163,184,0.30), inset 0 1px 0 rgba(255,255,255,0.18)'
    : '0 8px 28px rgba(120,199,245,0.28), inset 0 1px 0 rgba(255,255,255,0.18)';

  // ── Chromeless mode: just the panel content in a minimal container ──
  if (chromeless) {
    return (
      <div style={w.chromeless}>
        {activeNav === 'Activity'  && <ActivityPanel />}
        {activeNav === 'Overview'  && <OverviewPanel />}
        {activeNav === 'Analytics' && <AnalyticsPanel />}
        {activeNav === 'Calendar'  && <CalendarPanel />}
        {activeNav === 'Search'    && <SearchPanel />}
        {activeNav === 'Tags'      && <TagsPanel />}
        {activeNav === 'Agents'    && <AgentsPanel />}
        {activeNav === 'Settings'  && <SettingsPanel />}
        {activeNav === 'MCP'       && <McpPanel />}
      </div>
    );
  }

  return (
    <>
      <style>{`
        @keyframes pulse {
          0%, 100% { opacity: 1; }
          50%       { opacity: 0.32; }
        }
        @keyframes appPulse {
          0%, 100% { box-shadow: 0 8px 28px rgba(120,199,245,0.28), inset 0 1px 0 rgba(255,255,255,0.18); }
          50%       { box-shadow: 0 8px 28px rgba(120,199,245,0.48), inset 0 1px 0 rgba(255,255,255,0.18); }
        }
      `}</style>

      <div style={w.window}>
        {/* Title bar */}
        <div style={w.titleBar}>
          <div style={w.dots}>
            <span style={{ ...w.dot, background: '#ff5f57' }} />
            <span style={{ ...w.dot, background: '#febc2e' }} />
            <span style={{ ...w.dot, background: '#28c840' }} />
          </div>
          <span style={w.windowTitle}>TaskTrace · {activeNav}</span>
          <div style={{ width: 52 }} />
        </div>

        {/* Body */}
        <div style={w.body}>
          {/* Sidebar */}
          <div style={w.sidebar}>

            {/* ── Record / Stop button (matches ContentView glassProminent circle) ── */}
            <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 7, paddingTop: 4 }}>
              <button
                onClick={() => { setIsRecording(r => !r); showExplainer('RecordButton'); }}
                style={{
                  width: 68,
                  height: 68,
                  borderRadius: '50%',
                  background: btnDimColor,
                  border: `0.8px solid ${C.accentBorder}`,
                  backdropFilter: 'blur(14px)',
                  WebkitBackdropFilter: 'blur(14px)',
                  boxShadow: btnGlow,
                  cursor: 'pointer',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  transition: 'background 0.25s ease, box-shadow 0.25s ease',
                  animation: isRecording ? 'none' : 'appPulse 2.4s ease-in-out infinite',
                  outline: 'none',
                  flexShrink: 0,
                }}
              >
                {isRecording
                  ? /* stop.fill – solid square */
                    <svg width="22" height="22" viewBox="0 0 24 24" fill={btnColor}>
                      <rect x="4" y="4" width="16" height="16" rx="2.5" />
                    </svg>
                  : /* play.fill – solid triangle */
                    <svg width="22" height="22" viewBox="0 0 24 24" fill={btnColor}>
                      <polygon points="5,3 19,12 5,21" />
                    </svg>
                }
              </button>
              <span style={{ fontSize: 11, fontWeight: 600, color: C.textPrimary }}>
                {isRecording ? 'Recording' : 'Stopped'}
              </span>
            </div>

            {/* ── Nav items (matches sidebarButton glass-pill active style) ── */}
            <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
              {NAV_ITEMS.map(({ label, icon }) => {
                const isActive = label === activeNav;
                return (
                  <div
                    key={label}
                    onClick={() => { if (!controlledNav) { setInternalNav(label); } showExplainer(label); }}
                    style={{
                      display: 'flex',
                      alignItems: 'center',
                      gap: 9,
                      padding: '9px 11px',
                      borderRadius: 12,
                      cursor: 'pointer',
                      fontSize: 12,
                      fontWeight: 600,
                      color: isActive ? C.textPrimary : C.textSecondary,
                      background: isActive ? 'rgba(48,56,74,0.82)' : 'transparent',
                      border: isActive ? '0.8px solid rgba(255,255,255,0.28)' : '0.8px solid transparent',
                      backdropFilter: isActive ? 'blur(10px)' : 'none',
                      WebkitBackdropFilter: isActive ? 'blur(10px)' : 'none',
                      boxShadow: isActive ? '0 4px 16px rgba(120,199,245,0.10)' : 'none',
                      transition: 'color 0.15s ease, background 0.15s ease, border-color 0.15s ease',
                      userSelect: 'none',
                    }}
                  >
                    <span style={{ color: isActive ? C.accent : C.textSecondary, display: 'flex', flexShrink: 0, transition: 'color 0.15s ease' }}>
                      {icon}
                    </span>
                    {label}
                  </div>
                );
              })}
            </div>
          </div>

          {/* Content */}
          <div style={w.content}>
            {activeNav === 'Activity'  && <ActivityPanel />}
            {activeNav === 'Overview'  && <OverviewPanel />}
            {activeNav === 'Analytics' && <AnalyticsPanel />}
            {activeNav === 'Calendar'  && <CalendarPanel />}
            {activeNav === 'Search'    && <SearchPanel />}
            {activeNav === 'Tags'      && <TagsPanel />}
            {activeNav === 'Agents'    && <AgentsPanel />}
            {activeNav === 'Settings'  && <SettingsPanel />}
            {activeNav === 'MCP'       && <McpPanel />}
          </div>
        </div>
      </div>

      {/* ── Per-tab / record-button explainer ── */}
      {!hideExplainer && (
        <div style={ex.wrap}>
          <div style={{ ...ex.inner, opacity: explainerVisible ? 1 : 0 }}>
            <span style={ex.label}>{displaySource === 'RecordButton' ? 'Record Button' : displaySource}</span>
            <p style={ex.subtitle}>{OVERLAY[displaySource].subtitle}</p>
            <ul style={ex.list}>
              {OVERLAY[displaySource].bullets.map((b, i) => (
                <li key={i} style={ex.item}>
                  <span style={ex.dot} />
                  <span style={ex.itemText}>{b}</span>
                </li>
              ))}
            </ul>
          </div>
        </div>
      )}
    </>
  );
}

// ─── Window chrome styles ──────────────────────────────────────────────────────
const w: Record<string, React.CSSProperties> = {
  chromeless: {
    background: C.windowBg,
    borderRadius: 14,
    overflow: 'hidden',
    border: '1px solid rgba(255,255,255,0.08)',
    boxShadow: '0 16px 48px rgba(0,0,0,0.4), 0 0 0 1px rgba(255,255,255,0.04)',
    width: '100%',
    height: 400,
    display: 'flex',
    flexDirection: 'column',
  },
  window: {
    background: C.windowBg,
    borderRadius: 14,
    overflow: 'hidden',
    border: '1px solid rgba(255,255,255,0.08)',
    boxShadow: '0 32px 80px rgba(0,0,0,0.5), 0 0 0 1px rgba(255,255,255,0.04)',
    width: 860,
    margin: '0 auto',
    height: 500,
    display: 'flex',
    flexDirection: 'column',
  },
  titleBar: {
    background: C.titleBarBg,
    padding: '10px 16px',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    borderBottom: '1px solid rgba(255,255,255,0.06)',
    flexShrink: 0,
  },
  dots:        { display: 'flex', gap: 6 },
  dot:         { width: 11, height: 11, borderRadius: '50%', display: 'inline-block' },
  windowTitle: { flex: 1, textAlign: 'center', fontSize: 12, color: 'rgba(255,255,255,0.4)', fontWeight: 500 },
  body:        { display: 'flex', flex: 1, overflow: 'hidden' },
  sidebar: {
    width: 174,
    borderRight: '1px solid rgba(255,255,255,0.06)',
    background: C.sidebarBg,
    padding: '14px 10px',
    display: 'flex',
    flexDirection: 'column',
    gap: 14,
    flexShrink: 0,
    overflowY: 'auto',
  },
  content: {
    flex: 1,
    overflow: 'hidden',
    display: 'flex',
    flexDirection: 'column',
  },
};

// ─── Below-demo explainer styles ──────────────────────────────────────────────
const ex: Record<string, React.CSSProperties> = {
  wrap: {
    maxWidth: 860,
    margin: '24px auto 0',
    width: '100%',
    padding: '0 4px',
    minHeight: 250,
  },
  inner: {
    transition: 'opacity 0.35s ease',
  },
  label: {
    display: 'inline-block',
    fontSize: 16,
    fontWeight: 700,
    letterSpacing: '0.08em',
    textTransform: 'uppercase',
    color: C.accent,
    marginBottom: 8,
  },
  subtitle: {
    fontSize: 22,
    fontWeight: 600,
    color: 'rgba(249,249,247,0.9)',
    lineHeight: 1.4,
    marginBottom: 14,
  },
  list: {
    listStyle: 'none',
    display: 'flex',
    flexDirection: 'column',
    gap: 8,
  },
  item: {
    display: 'flex',
    alignItems: 'flex-start',
    gap: 10,
  },
  dot: {
    width: 5,
    height: 5,
    borderRadius: '50%',
    background: C.accent,
    flexShrink: 0,
    marginTop: 9,
    opacity: 0.7,
    display: 'inline-block',
  },
  itemText: {
    fontSize: 19,
    color: 'rgba(149,158,177,0.9)',
    lineHeight: 1.6,
  },
};
