import React, { useState, useEffect, useRef } from 'react';
import AppDemo, { NavItem } from './AppDemo';

const NATIVE_W = 860;
const NATIVE_H = 500;
const CHROMELESS_W = 860;
const CHROMELESS_H = 400;

// ─── Colors (shared with AppDemo) ─────────────────────────────────────────────
const VC = {
  accent:       '#78C7F5',
  accentDim:    'rgba(120,199,245,0.22)',
  recordActive: '#FAA3B8',
  cardBg:       'rgba(41,48,64,0.92)',
  insetBg:      'rgba(48,56,74,0.90)',
  textPrimary:  'rgba(249,249,247,0.92)',
  textSecondary:'rgba(149,158,177,1)',
  windowBg:     '#13151c',
  timeline: [
    'rgba(138,209,247,0.94)',
    'rgba(156,235,201,0.94)',
    'rgba(250,191,171,0.94)',
    'rgba(204,186,250,0.94)',
    'rgba(247,224,153,0.94)',
  ],
  timelineUnassigned: 'rgba(77,87,110,0.92)',
};

// ─── Tour section definitions ─────────────────────────────────────────────────
interface TourSection {
  nav: NavItem;
  label: string;
  headline: string;
  description: string;
  bullets: string[];
  visual?: 'demo' | 'wiki';
}

const SECTIONS: TourSection[] = [
  {
    nav: 'Activity',
    label: 'Capture',
    headline: 'Press play.\nDo your work.',
    description:
      'TaskTrace silently records your active application, keystrokes, and microphone. When you stop, on-device AI generates a summary of each session. No manual timers. No browser extensions.',
    bullets: [
      'Screen, keystrokes, and microphone captured in real time',
      'On-device AI summarizes what you did in each app',
      'All data stays on your Mac — nothing leaves your laptop',
      'Review, tag, or delete any session afterward',
    ],
  },
  {
    nav: 'Analytics',
    label: 'Analyze',
    headline: 'See where\nyour time goes.',
    description:
      'A year of tracked time at a glance. A GitHub-style heatmap reveals your rhythms. Filter by tag to see exactly how time splits across projects.',
    bullets: [
      '52-week heatmap shows tracked time for every day',
      '14-day bar chart breaks down time by tag',
      'Filter by tag to isolate a project or client',
      'Tracked and tagged percentages at a glance',
    ],
  },
  {
    nav: 'Calendar',
    label: 'History',
    headline: 'Every day.\nAlways available.',
    description:
      'When you need to reconstruct a day for a client, timesheet, or your own memory, TaskTrace shows the whole timeline in one place. You can jump to any day, see where time went, and recover the actual shape of the work instead of guessing from fragments.',
    bullets: [
      'Rebuild a day quickly when you forgot to track time in the moment',
      'See distinct work blocks so context switching and deep-focus stretches are obvious',
      'Open the underlying sessions when you need the details behind a block',
      'Review past work even when you are offline or away from the original tools',
    ],
  },
  {
    nav: 'Search',
    label: 'Automated Personal Wiki',
    headline: 'A second brain\nwithout writing notes.',
    description:
      'Most people want better knowledge management, but they do not want the extra job of constantly maintaining it. TaskTrace captures what you do, pulls out what matters, and turns it into project memory you can come back to later.',
    bullets: [
      'Capture useful knowledge while you work instead of stopping to document it',
      'Keep project context searchable and readable when you return days or weeks later',
      'Build a personal wiki automatically from real work instead of manual note-taking',
    ],
    visual: 'wiki',
  },
  {
    nav: 'Search',
    label: 'Search',
    headline: 'Build your graph.\nGive agents context.',
    description:
      'TaskTrace turns your activities, screenshots, notes, and summaries into a personal knowledge graph. Agents can search it for durable context, and the same graph continuously updates your Obsidian archive while a resizable text pane keeps the underlying evidence visible.',
    bullets: [
      'Personal knowledge graph accumulates from activities, overviews, screenshots, and extracted entities',
      'Graph retrieval gives agents the surrounding context instead of a single isolated hit',
      'Community notes export into Obsidian automatically and stay up to date as the graph changes',
      'Resizable evidence pane keeps summaries, OCR, transcripts, and source context readable beside the graph',
    ],
  },
  {
    nav: 'Agents',
    label: 'Agents',
    headline: 'Skills and context\nfor agents.',
    description:
      'TaskTrace gives agents current work context, reusable skills, and direct MCP tools for reading activity, creating todos, and pushing notifications when something needs attention.',
    bullets: [
      'Generated skills turn repeated workflows into reusable procedures',
      'MCP resources expose current activity, todos, screenshots, and graph search',
      'Agents can create todos and goals through TaskTrace tools',
      'Agent messages can surface as macOS notifications',
    ],
  },
  {
    nav: 'MCP',
    label: 'Agent API',
    headline: 'Context for\nyour AI tools.',
    description:
      'A local MCP server exposes your work history to Claude, Cursor, and other AI tools. Your agents know what you\'re working on — without you telling them.',
    bullets: [
      'Claude and Cursor read your live context on demand',
      'No more re-explaining your project at the start of every chat',
      'Configurable feeds with granularity controls',
      'Bearer token authentication for secure access',
    ],
  },
];

// ─── Small-screen hero visuals ──────────────────────────────────────────────

function VisualCard({
  children,
  padding = '32px 24px',
}: {
  children: React.ReactNode;
  padding?: React.CSSProperties['padding'];
}) {
  return (
    <div style={{
      background: VC.cardBg,
      borderRadius: 20,
      border: '1px solid rgba(255,255,255,0.08)',
      boxShadow: '0 16px 48px rgba(0,0,0,0.35), 0 0 0 1px rgba(255,255,255,0.04)',
      padding,
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      overflow: 'hidden',
      position: 'relative',
    }}>
      {children}
    </div>
  );
}

function BulletPlayIcon() {
  return (
    <span style={styles.bulletIconWrap} aria-hidden="true">
      <svg viewBox="0 0 14 14" width="14" height="14" fill="none">
        <path
          d="M4 2.8L10.4 7 4 11.2V2.8Z"
          fill="#5bbef0"
          opacity="0.92"
        />
      </svg>
    </span>
  );
}

// 1 — Activity: big glowing play button with waves that fade to nothing
function PlayButtonVisual() {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      padding: '48px 0',
      position: 'relative',
    }}>
      <style>{`
        @keyframes playWave {
          0%   { transform: translate(-50%,-50%) scale(1);   opacity: 0.3; }
          40%  { opacity: 0; }
          100% { transform: translate(-50%,-50%) scale(2.8); opacity: 0; }
        }
        @keyframes playGlow {
          0%, 100% { filter: drop-shadow(0 0 24px rgba(120,199,245,0.45)); }
          50%      { filter: drop-shadow(0 0 48px rgba(120,199,245,0.7)); }
        }
      `}</style>

      {/* Expanding waves — absolutely positioned, fade to transparent */}
      {[0, 1, 2, 3].map(i => (
        <div key={i} style={{
          position: 'absolute',
          top: '50%', left: '50%',
          width: 140, height: 140,
          borderRadius: '50%',
          border: `1.5px solid ${VC.accent}`,
          animation: `playWave 3s ease-out ${i * 0.75}s infinite`,
          opacity: 0,
          pointerEvents: 'none',
        }} />
      ))}

      {/* Button circle */}
      <div style={{
        position: 'relative', zIndex: 1,
        width: 140, height: 140,
        borderRadius: '50%',
        background: VC.accentDim,
        border: `1.5px solid rgba(255,255,255,0.2)`,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        animation: 'playGlow 3s ease-in-out infinite',
        boxShadow: '0 0 60px rgba(120,199,245,0.2)',
      }}>
        <svg width="56" height="56" viewBox="0 0 24 24" fill={VC.accent} stroke="none">
          <polygon points="7,3 21,12 7,21" />
        </svg>
      </div>
    </div>
  );
}

// 2 — Overview: horizontal timeline
function TimelineVisual() {
  const blocks = [
    { label: 'Xcode',    pct: 35, color: VC.timeline[0], tag: 'Work' },
    { label: 'Terminal',  pct: 25, color: VC.timeline[1], tag: 'Work' },
    { label: 'Safari',   pct: 22, color: VC.timeline[2], tag: null },
    { label: 'Slack',    pct: 18, color: VC.timeline[3], tag: 'Work' },
  ];

  return (
    <VisualCard>
      <div style={{ width: '100%', display: 'flex', flexDirection: 'column', gap: 16 }}>
        {/* Time ruler */}
        <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 11, color: VC.textSecondary, fontWeight: 500 }}>
          <span>9:00 AM</span><span>10:00</span><span>11:00</span><span>12:00 PM</span>
        </div>
        {/* Segmented bar */}
        <div style={{ display: 'flex', gap: 3, height: 36, borderRadius: 10, overflow: 'hidden' }}>
          {blocks.map((b, i) => (
            <div key={i} style={{
              flex: b.pct,
              background: b.color,
              borderRadius: i === 0 ? '10px 0 0 10px' : i === blocks.length - 1 ? '0 10px 10px 0' : 0,
              transition: 'flex 0.5s ease',
            }} />
          ))}
        </div>
        {/* Legend */}
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 14, marginTop: 4 }}>
          {blocks.map((b, i) => (
            <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 7 }}>
              <span style={{ width: 10, height: 10, borderRadius: 3, background: b.color, display: 'inline-block', flexShrink: 0 }} />
              <span style={{ fontSize: 12, color: VC.textPrimary, fontWeight: 500 }}>{b.label}</span>
              <span style={{ fontSize: 11, color: VC.textSecondary }}>{b.pct} min</span>
            </div>
          ))}
        </div>
      </div>
    </VisualCard>
  );
}

// 4 — Calendar: mini month grid
function CalendarVisual() {
  const days = Array.from({ length: 31 }, (_, i) => i + 1);
  const startDow = 0; // March 2026 starts Sunday
  const cells: (number | null)[] = [
    ...Array.from({ length: startDow }, () => null),
    ...days,
  ];
  while (cells.length % 7 !== 0) cells.push(null);
  const selectedDay = 18;
  const availableRange = [5, 18];

  return (
    <VisualCard>
      <div style={{ width: '100%', maxWidth: 280 }}>
        <div style={{ textAlign: 'center', fontSize: 14, fontWeight: 600, color: VC.textPrimary, marginBottom: 12 }}>
          March 2026
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gap: 2, textAlign: 'center' }}>
          {['S','M','T','W','T','F','S'].map((d, i) => (
            <div key={i} style={{ fontSize: 10, fontWeight: 600, color: VC.textSecondary, padding: '4px 0', letterSpacing: '0.05em' }}>{d}</div>
          ))}
          {cells.map((day, idx) => {
            const selected = day === selectedDay;
            const available = day !== null && day >= availableRange[0] && day <= availableRange[1];
            return (
              <div key={idx} style={{
                fontSize: 12,
                fontWeight: selected ? 700 : 400,
                color: day === null ? 'transparent' : available ? VC.textPrimary : 'rgba(149,158,177,0.3)',
                padding: '5px 0',
                borderRadius: 8,
                background: selected ? VC.accent : 'transparent',
                ...(selected && { color: '#13151c' }),
                position: 'relative',
              }}>
                {day ?? ''}
                {available && !selected && (
                  <span style={{
                    position: 'absolute', bottom: 2, left: '50%', transform: 'translateX(-50%)',
                    width: 3, height: 3, borderRadius: '50%',
                    background: VC.timeline[day! % VC.timeline.length],
                  }} />
                )}
              </div>
            );
          })}
        </div>
      </div>
    </VisualCard>
  );
}

// 3 — Analytics: bar chart
function BarChartVisual() {
  const bars = [
    { label: 'Mon', work: 3.2, research: 1.1 },
    { label: 'Tue', work: 4.5, research: 0.8 },
    { label: 'Wed', work: 2.8, research: 2.0 },
    { label: 'Thu', work: 5.1, research: 0.5 },
    { label: 'Fri', work: 3.9, research: 1.4 },
    { label: 'Sat', work: 1.2, research: 3.1 },
    { label: 'Sun', work: 0.6, research: 1.8 },
  ];
  const maxH = Math.max(...bars.map(b => b.work + b.research));
  const chartH = 120;

  return (
    <VisualCard>
      <div style={{ width: '100%', display: 'flex', flexDirection: 'column', gap: 14 }}>
        {/* Legend */}
        <div style={{ display: 'flex', gap: 16, justifyContent: 'flex-end' }}>
          {[
            { label: 'Work', color: VC.timeline[0] },
            { label: 'Research', color: VC.timeline[1] },
          ].map(l => (
            <div key={l.label} style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
              <span style={{ width: 8, height: 8, borderRadius: 2, background: l.color, display: 'inline-block' }} />
              <span style={{ fontSize: 11, color: VC.textSecondary }}>{l.label}</span>
            </div>
          ))}
        </div>

        {/* Chart */}
        <div style={{ position: 'relative' }}>
          {/* Grid lines */}
          {[0.25, 0.5, 0.75, 1].map(f => (
            <div key={f} style={{
              position: 'absolute', left: 0, right: 0,
              top: (1 - f) * chartH,
              height: 1,
              background: 'rgba(255,255,255,0.06)',
            }} />
          ))}

          <div style={{ display: 'flex', gap: 6, alignItems: 'flex-end', height: chartH }}>
            {bars.map((b, i) => {
              const wH = (b.work / maxH) * chartH;
              const rH = (b.research / maxH) * chartH;
              return (
                <div key={i} style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
                  <div style={{
                    width: '100%', maxWidth: 28,
                    borderRadius: '6px 6px 2px 2px',
                    overflow: 'hidden',
                    display: 'flex', flexDirection: 'column',
                  }}>
                    <div style={{ height: rH, background: VC.timeline[1], transition: 'height 0.4s ease' }} />
                    <div style={{ height: wH, background: VC.timeline[0], transition: 'height 0.4s ease' }} />
                  </div>
                </div>
              );
            })}
          </div>
        </div>

        {/* Day labels */}
        <div style={{ display: 'flex', gap: 6 }}>
          {bars.map((b, i) => (
            <div key={i} style={{ flex: 1, textAlign: 'center', fontSize: 10, color: VC.textSecondary, fontWeight: 500 }}>
              {b.label}
            </div>
          ))}
        </div>
      </div>
    </VisualCard>
  );
}

// 5 — Search: standalone knowledge graph
function KnowledgeGraphVisual() {
  const nodes = [
    { id: 'o1', kind: 'overview',    label: 'Pipeline',    x: 150, y: 112, r: 17, glow: 0.9 },
    { id: 'a1', kind: 'activity',    label: 'Xcode',       x: 82,  y: 58,  r: 11, glow: 0.6 },
    { id: 'a2', kind: 'activity',    label: 'Terminal',    x: 226, y: 70,  r: 11, glow: 0.35 },
    { id: 's1', kind: 'screenshot',  label: '',            x: 36,  y: 28,  r: 7,  glow: 0.4 },
    { id: 's2', kind: 'screenshot',  label: '',            x: 100, y: 22,  r: 7,  glow: 0.0 },
    { id: 's3', kind: 'screenshot',  label: '',            x: 262, y: 34,  r: 7,  glow: 0.0 },
    { id: 's4', kind: 'screenshot',  label: '',            x: 294, y: 72,  r: 7,  glow: 0.2 },
    { id: 'o2', kind: 'overview',    label: 'Knowledge',   x: 308, y: 150, r: 17, glow: 0.7 },
    { id: 'a3', kind: 'activity',    label: 'Safari',      x: 258, y: 214, r: 11, glow: 0.5 },
    { id: 's5', kind: 'screenshot',  label: '',            x: 220, y: 248, r: 7,  glow: 0.0 },
    { id: 's6', kind: 'screenshot',  label: '',            x: 290, y: 262, r: 7,  glow: 0.1 },
    { id: 'a4', kind: 'activity',    label: 'Claims',      x: 360, y: 204, r: 11, glow: 0.2 },
    { id: 's7', kind: 'screenshot',  label: '',            x: 394, y: 246, r: 7,  glow: 0.0 },
  ];

  const links = [
    ['o1','a1'], ['o1','a2'],
    ['a1','s1'], ['a1','s2'],
    ['a2','s3'], ['a2','s4'],
    ['o2','a3'], ['o2','a4'],
    ['a3','s5'], ['a3','s6'],
    ['a4','s7'],
  ];

  const colors: Record<string, string> = {
    overview:   '#7fc2f0',
    activity:   '#8bdac8',
    screenshot: '#f6d28f',
    edge:       'rgba(255,255,255,0.14)',
    nodeStroke: 'rgba(17,24,39,0.95)',
  };

  const nodeMap = Object.fromEntries(nodes.map(n => [n.id, n]));

  return (
    <VisualCard padding={0}>
      <div style={{ width: '100%' }}>
        <style>{`
          @keyframes graphNodeFloat {
            0%, 100% { transform: translateY(0px) scale(1); }
            50% { transform: translateY(-8px) scale(1.02); }
          }
        `}</style>

        <div style={{
          minHeight: 280,
          borderRadius: 20,
          overflow: 'hidden',
          border: '1px solid rgba(255,255,255,0.08)',
          background: 'radial-gradient(circle at 22% 18%, rgba(127,194,240,0.14), transparent 34%), radial-gradient(circle at 78% 82%, rgba(139,218,200,0.12), transparent 30%), rgba(19,21,28,0.72)',
        }}>
          <svg viewBox="0 0 420 280" width="100%" style={{ display: 'block', minHeight: 260 }}>
            <defs>
              <filter id="graph-glow" x="-80%" y="-80%" width="260%" height="260%">
                <feGaussianBlur stdDeviation="8" result="blur" />
                <feMerge><feMergeNode in="blur" /><feMergeNode in="SourceGraphic" /></feMerge>
              </filter>
            </defs>

            {links.map(([from, to]) => {
              const a = nodeMap[from], b = nodeMap[to];
              return <line key={`${from}-${to}`} x1={a.x} y1={a.y} x2={b.x} y2={b.y} stroke={colors.edge} strokeWidth="1.4" />;
            })}

            {nodes.map((n, idx) => {
              const fill = colors[n.kind];
              return (
                <g
                  key={n.id}
                  style={{
                    animation: `graphNodeFloat ${4.8 + (idx % 4) * 0.8}s ease-in-out ${idx * 0.18}s infinite`,
                    transformOrigin: `${n.x}px ${n.y}px`,
                  }}
                >
                  {n.glow > 0 && (
                    <circle cx={n.x} cy={n.y} r={n.r + 10 + n.glow * 16} fill={fill} opacity={0.1 + n.glow * 0.25} filter="url(#graph-glow)" />
                  )}
                  <circle cx={n.x} cy={n.y} r={n.r} fill={fill} stroke={colors.nodeStroke} strokeWidth="1.2" />
                  {n.label && (
                    <text x={n.x} y={n.y - n.r - 7} textAnchor="middle" fontSize="11" fontWeight="600" fill="rgba(249,249,247,0.85)" fontFamily="Inter, SF Pro Text, sans-serif">
                      {n.label}
                    </text>
                  )}
                </g>
              );
            })}
          </svg>
        </div>
      </div>
    </VisualCard>
  );
}

function LargeWikiVisual() {
  const sourceCards = [
    { label: 'Screenshots', tone: VC.timeline[0] },
    { label: 'Work sessions', tone: VC.timeline[1] },
    { label: 'Research', tone: VC.timeline[2] },
    { label: 'Decisions', tone: VC.timeline[3] },
  ];
  const wikiRows = [
    { label: 'Progress', width: '82%' },
    { label: 'Key ideas', width: '68%' },
    { label: 'Next up', width: '74%' },
  ];

  return (
    <VisualCard padding="20px">
      <div style={{ width: '100%', display: 'grid', gridTemplateColumns: '170px 54px minmax(0, 1fr)', gap: 18, alignItems: 'center' }}>
        <style>{`
          @keyframes wikiPulse {
            0%, 100% { opacity: 0.45; transform: scaleX(1); }
            50% { opacity: 0.9; transform: scaleX(1.04); }
          }
          @keyframes wikiFloat {
            0%, 100% { transform: translateY(0px); }
            50% { transform: translateY(-6px); }
          }
        `}</style>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
          {sourceCards.map((card, index) => (
            <div
              key={card.label}
              style={{
                padding: '12px 14px',
                borderRadius: 16,
                background: 'rgba(255,255,255,0.04)',
                border: '1px solid rgba(255,255,255,0.07)',
                display: 'flex',
                alignItems: 'center',
                gap: 10,
                animation: `wikiFloat ${4.2 + index * 0.4}s ease-in-out ${index * 0.18}s infinite`,
              }}
            >
              <span
                style={{
                  width: 10,
                  height: 10,
                  borderRadius: 3,
                  background: card.tone,
                  boxShadow: `0 0 14px ${card.tone}`,
                  flexShrink: 0,
                }}
              />
              <span style={{ fontSize: 12.5, fontWeight: 700, color: VC.textPrimary, letterSpacing: '0.01em' }}>
                {card.label}
              </span>
            </div>
          ))}
        </div>

        <div
          style={{
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            gap: 10,
          }}
        >
          {Array.from({ length: 3 }, (_, index) => (
            <div>
              <div
                key={index}
                style={{
                  width: 54,
                  height: 2,
                  borderRadius: 999,
                  background: `linear-gradient(90deg, rgba(120,199,245,0.08), rgba(120,199,245,0.9), rgba(120,199,245,0.08))`,
                  animation: `wikiPulse 2.6s ease-in-out ${index * 0.35}s infinite`,
                }}
              />
            </div>
          ))}
        </div>

        <div
          style={{
            borderRadius: 22,
            background: 'linear-gradient(180deg, rgba(18,22,31,0.98), rgba(25,29,40,0.92))',
            border: '1px solid rgba(255,255,255,0.08)',
            padding: '18px 18px 16px',
            boxShadow: 'inset 0 1px 0 rgba(255,255,255,0.04)',
          }}
        >
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 12, marginBottom: 16 }}>
            <div>
              <div style={{ fontSize: 11, textTransform: 'uppercase', letterSpacing: '0.08em', color: VC.accent, fontWeight: 700, marginBottom: 6 }}>
                Personal wiki
              </div>
              <div style={{ fontSize: 26, lineHeight: 1.04, color: VC.textPrimary, fontWeight: 760, letterSpacing: '-0.04em' }}>
                Product launch
              </div>
            </div>
            <div style={{ fontSize: 11, color: VC.textSecondary, padding: '7px 10px', borderRadius: 999, background: 'rgba(120,199,245,0.12)', border: '1px solid rgba(120,199,245,0.16)' }}>
              always current
            </div>
          </div>

          <div style={{ display: 'grid', gap: 11 }}>
            {wikiRows.map((row, index) => (
              <div
                key={row.label}
                style={{
                  padding: '13px 14px',
                  borderRadius: 14,
                  background: 'rgba(255,255,255,0.04)',
                  border: '1px solid rgba(255,255,255,0.06)',
                }}
              >
                <div style={{ fontSize: 12, fontWeight: 700, color: VC.accent, letterSpacing: '0.04em', textTransform: 'uppercase', marginBottom: 8 }}>
                  {row.label}
                </div>
                <div style={{ display: 'grid', gap: 7 }}>
                  <div style={{ width: row.width, height: 7, borderRadius: 999, background: 'rgba(249,249,247,0.76)' }} />
                  <div style={{ width: `${62 - index * 6}%`, height: 7, borderRadius: 999, background: 'rgba(149,158,177,0.52)' }} />
                  <div style={{ width: `${44 + index * 9}%`, height: 7, borderRadius: 999, background: 'rgba(149,158,177,0.32)' }} />
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </VisualCard>
  );
}

function SmallWikiVisual() {
  const sourceDots = [
    { label: 'Shots', x: '14%', y: '18%', color: VC.timeline[0] },
    { label: 'Audio', x: '74%', y: '20%', color: VC.timeline[1] },
    { label: 'Tasks', x: '20%', y: '54%', color: VC.timeline[2] },
    { label: 'Ideas', x: '78%', y: '56%', color: VC.timeline[3] },
  ];

  return (
    <VisualCard padding="18px 16px 20px">
      <div style={{ width: '100%', position: 'relative', minHeight: 300 }}>
        <style>{`
          @keyframes wikiOrb {
            0%, 100% { transform: translateY(0px) scale(1); }
            50% { transform: translateY(-6px) scale(1.03); }
          }
          @keyframes wikiBeam {
            0%, 100% { opacity: 0.28; }
            50% { opacity: 0.82; }
          }
        `}</style>

        <div
          style={{
            position: 'absolute',
            inset: '10px 10px 92px',
            borderRadius: 24,
            background: 'radial-gradient(circle at 50% 28%, rgba(120,199,245,0.18), transparent 35%), rgba(255,255,255,0.02)',
            border: '1px solid rgba(255,255,255,0.05)',
          }}
        />

        {sourceDots.map((dot, index) => (
          <div
            key={dot.label}
            style={{
              position: 'absolute',
              left: dot.x,
              top: dot.y,
              transform: 'translate(-50%, -50%)',
              display: 'flex',
              flexDirection: 'column',
              alignItems: 'center',
              gap: 8,
              animation: `wikiOrb ${4 + index * 0.4}s ease-in-out ${index * 0.2}s infinite`,
            }}
          >
            <div
              style={{
                width: 18,
                height: 18,
                borderRadius: 6,
                background: dot.color,
                boxShadow: `0 0 18px ${dot.color}`,
              }}
            />
            <div style={{ fontSize: 10.5, fontWeight: 700, letterSpacing: '0.05em', textTransform: 'uppercase', color: 'rgba(249,249,247,0.72)' }}>
              {dot.label}
            </div>
          </div>
        ))}

        {[
          { left: '22%', top: '27%', width: 92, rotate: 18 },
          { left: '60%', top: '28%', width: 86, rotate: -20 },
          { left: '28%', top: '60%', width: 76, rotate: -10 },
          { left: '58%', top: '61%', width: 84, rotate: 11 },
        ].map((beam, index) => (
          <div
            key={index}
            style={{
              position: 'absolute',
              left: beam.left,
              top: beam.top,
              width: beam.width,
              height: 2,
              borderRadius: 999,
              transform: `rotate(${beam.rotate}deg)`,
              transformOrigin: 'left center',
              background: 'linear-gradient(90deg, rgba(120,199,245,0.02), rgba(120,199,245,0.8), rgba(120,199,245,0.02))',
              animation: `wikiBeam 2.3s ease-in-out ${index * 0.3}s infinite`,
            }}
          />
        ))}

        <div
          style={{
            position: 'absolute',
            left: '50%',
            bottom: 0,
            transform: 'translateX(-50%)',
            width: '78%',
            maxWidth: 290,
            borderRadius: 22,
            background: 'linear-gradient(180deg, rgba(18,22,31,0.98), rgba(25,29,40,0.94))',
            border: '1px solid rgba(255,255,255,0.08)',
            padding: '16px 15px 15px',
            boxShadow: '0 18px 46px rgba(0,0,0,0.34)',
          }}
        >
          <div style={{ fontSize: 10.5, textTransform: 'uppercase', letterSpacing: '0.08em', color: VC.accent, fontWeight: 700, marginBottom: 8 }}>
            Second brain
          </div>
          <div style={{ fontSize: 22, lineHeight: 1.04, color: VC.textPrimary, fontWeight: 760, letterSpacing: '-0.04em', marginBottom: 12 }}>
            Project wiki
          </div>
          <div style={{ display: 'grid', gap: 9 }}>
            {['Progress', 'Decisions', 'Next up'].map((label, index) => (
              <div
                key={label}
                style={{
                  padding: '10px 11px',
                  borderRadius: 13,
                  background: 'rgba(255,255,255,0.04)',
                  border: '1px solid rgba(255,255,255,0.06)',
                }}
              >
                <div style={{ fontSize: 11, fontWeight: 700, color: VC.accent, letterSpacing: '0.04em', textTransform: 'uppercase', marginBottom: 7 }}>
                  {label}
                </div>
                <div style={{ display: 'grid', gap: 6 }}>
                  <div style={{ width: `${78 - index * 8}%`, height: 6, borderRadius: 999, background: 'rgba(249,249,247,0.74)' }} />
                  <div style={{ width: `${56 + index * 4}%`, height: 6, borderRadius: 999, background: 'rgba(149,158,177,0.42)' }} />
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </VisualCard>
  );
}

// 6 — Agents: skills and MCP tools
function AgentsVisual() {
  const events = [
    { label: 'Generated Skills', icon: '⚡' },
    { label: 'MCP Context',      icon: '📋' },
    { label: 'Push Message',     icon: '🏷' },
  ];

  return (
    <VisualCard>
      <style>{`
        @keyframes agentParticle {
          0%   { left: 0%;  opacity: 0; }
          10%  { opacity: 1; }
          90%  { opacity: 1; }
          100% { left: 100%; opacity: 0; }
        }
      `}</style>
      <div style={{ width: '100%', display: 'flex', alignItems: 'center', gap: 20 }}>
        {/* Event nodes */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: 12, flexShrink: 0 }}>
          {events.map((ev, i) => (
            <div key={i} style={{
              display: 'flex', alignItems: 'center', gap: 8,
              background: VC.insetBg,
              border: '1px solid rgba(255,255,255,0.08)',
              borderRadius: 10, padding: '8px 12px',
            }}>
              <span style={{ fontSize: 16 }}>{ev.icon}</span>
              <span style={{ fontSize: 11, fontWeight: 600, color: VC.textPrimary, whiteSpace: 'nowrap' }}>{ev.label}</span>
            </div>
          ))}
        </div>

        {/* Animated connection lines */}
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 12, minWidth: 40 }}>
          {events.map((_, i) => (
            <div key={i} style={{
              height: 34, position: 'relative', display: 'flex', alignItems: 'center',
            }}>
              <div style={{
                width: '100%', height: 2,
                background: 'linear-gradient(90deg, rgba(120,199,245,0.3), rgba(120,199,245,0.06))',
                borderRadius: 1,
              }} />
              {/* Traveling particle */}
              <div style={{
                position: 'absolute', top: '50%', transform: 'translateY(-50%)',
                width: 6, height: 6, borderRadius: '50%',
                background: VC.timeline[i],
                boxShadow: `0 0 8px ${VC.timeline[i]}`,
                animation: `agentParticle 2s ease-in-out ${i * 0.6}s infinite`,
              }} />
            </div>
          ))}
        </div>

        {/* AI hub */}
        <div style={{
          width: 56, height: 56, borderRadius: 14, flexShrink: 0,
          background: VC.accentDim,
          border: '1.5px solid rgba(255,255,255,0.15)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          boxShadow: `0 0 24px rgba(120,199,245,0.2)`,
        }}>
          <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke={VC.accent} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
            <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
            <circle cx="9" cy="10" r="1" fill={VC.accent} stroke="none" />
            <circle cx="12" cy="10" r="1" fill={VC.accent} stroke="none" />
            <circle cx="15" cy="10" r="1" fill={VC.accent} stroke="none" />
          </svg>
        </div>
      </div>
    </VisualCard>
  );
}

// 7 — MCP: plug + socket graphic
function McpVisual() {
  return (
    <VisualCard>
      <div style={{ display: 'flex', alignItems: 'center', gap: 20 }}>
        {/* Plug icon */}
        <div style={{
          width: 52, height: 52, borderRadius: 14,
          background: VC.insetBg, border: '1px solid rgba(255,255,255,0.08)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>
          <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke={VC.timeline[3]} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M12 2v6" /><path d="M6 8h12" />
            <path d="M8 8v4a4 4 0 0 0 8 0V8" />
            <path d="M12 16v6" />
          </svg>
        </div>

        {/* Animated dashes */}
        <div style={{ flex: 1, height: 2, minWidth: 30, background: 'repeating-linear-gradient(90deg, rgba(204,186,250,0.5) 0 6px, transparent 6px 12px)', borderRadius: 1 }} />

        {/* Tool logos */}
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          {['Claude', 'Cursor', 'VS Code'].map((tool, i) => (
            <div key={i} style={{
              display: 'flex', alignItems: 'center', gap: 8,
              background: VC.insetBg, border: '1px solid rgba(255,255,255,0.08)',
              borderRadius: 10, padding: '7px 14px',
            }}>
              <span style={{ width: 8, height: 8, borderRadius: '50%', background: VC.timeline[i], display: 'inline-block' }} />
              <span style={{ fontSize: 12, fontWeight: 600, color: VC.textPrimary }}>{tool}</span>
            </div>
          ))}
        </div>
      </div>
    </VisualCard>
  );
}

// Map nav → small-screen visual
function SmallVisual({ section }: { section: TourSection }) {
  if (section.visual === 'wiki') {
    return <SmallWikiVisual />;
  }

  switch (section.nav) {
    case 'Activity':  return <PlayButtonVisual />;
    case 'Overview':  return <TimelineVisual />;
    case 'Analytics': return <BarChartVisual />;
    case 'Calendar':  return <CalendarVisual />;
    case 'Search':    return <KnowledgeGraphVisual />;
    case 'Agents':    return <AgentsVisual />;
    case 'MCP':       return <McpVisual />;
    default:          return <ScaledChromelessDemo nav={section.nav} />;
  }
}

function LargeVisual({ section }: { section: TourSection }) {
  if (section.visual === 'wiki') {
    return <LargeWikiVisual />;
  }

  return <ScaledDemo nav={section.nav} />;
}

// ─── Scaled AppDemo wrapper ──────────────────────────────────────────────────
// Renders the demo at its native 860×500 and uses transform:scale() to fit
// the available width. The outer div's height is set to the scaled height so
// surrounding layout flows correctly.
function ScaledDemo({ nav }: { nav: NavItem }) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [scale, setScale] = useState(1);

  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    const update = () => {
      const w = el.clientWidth;
      setScale(Math.min(1, w / NATIVE_W));
    };
    update();
    const ro = new ResizeObserver(update);
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  return (
    <div
      ref={containerRef}
      style={{ width: '100%', height: NATIVE_H * scale, overflow: 'hidden' }}
    >
      <div
        style={{
          width: NATIVE_W,
          transformOrigin: 'top left',
          transform: `scale(${scale})`,
        }}
      >
        <AppDemo controlledNav={nav} hideExplainer />
      </div>
    </div>
  );
}

// ─── Scaled chromeless wrapper for small screens ────────────────────────────
function ScaledChromelessDemo({ nav }: { nav: NavItem }) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [scale, setScale] = useState(1);

  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    const update = () => {
      const w = el.clientWidth;
      setScale(Math.min(1, w / CHROMELESS_W));
    };
    update();
    const ro = new ResizeObserver(update);
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  return (
    <div
      ref={containerRef}
      style={{ width: '100%', height: CHROMELESS_H * scale, overflow: 'hidden' }}
    >
      <div
        style={{
          width: CHROMELESS_W,
          height: CHROMELESS_H,
          transformOrigin: 'top left',
          transform: `scale(${scale})`,
        }}
      >
        <AppDemo controlledNav={nav} hideExplainer chromeless />
      </div>
    </div>
  );
}

// ─── Component ────────────────────────────────────────────────────────────────
export default function FeatureTour() {
  const [activeIdx, setActiveIdx] = useState(0);
  const [visibleSet, setVisibleSet] = useState<Set<number>>(new Set());
  const sectionRefs = useRef<(HTMLDivElement | null)[]>([]);
  const [isSmall, setIsSmall] = useState(false);

  // Detect which text section is in the viewport centre band (desktop sticky mode)
  useEffect(() => {
    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          const idx = sectionRefs.current.indexOf(entry.target as HTMLDivElement);
          if (idx === -1) return;
          if (entry.isIntersecting) {
            setActiveIdx(idx);
            setVisibleSet((prev) => {
              if (prev.has(idx)) return prev;
              const next = new Set(prev);
              next.add(idx);
              return next;
            });
          }
        });
      },
      { rootMargin: '-35% 0px -35% 0px' },
    );

    sectionRefs.current.forEach((el) => el && observer.observe(el));
    return () => observer.disconnect();
  }, []);

  // Track breakpoint
  useEffect(() => {
    const update = () => setIsSmall(window.innerWidth < 1100);
    update();
    window.addEventListener('resize', update);
    return () => window.removeEventListener('resize', update);
  }, []);

  // ── Small-screen layout: stacked demo + text per section ──
  if (isSmall) {
    return (
      <section id="features" style={styles.section}>
        <style>{`
          @media (max-width: 640px) {
            .tour-headline { font-size: clamp(28px, 7vw, 44px) !important; }
          }
        `}</style>
        <div style={styles.smallContainer}>
          {SECTIONS.map((section, i) => (
            <SmallSection key={i} section={section} index={i} total={SECTIONS.length} />
          ))}
        </div>
      </section>
    );
  }

  // ── Large-screen layout: sticky demo + scrolling text ──
  return (
    <section id="features" style={styles.section}>
      <div style={styles.grid}>
        {/* Text column */}
        <div style={styles.textColumn}>
          {SECTIONS.map((section, i) => {
            const isVisible = visibleSet.has(i);
            return (
              <div
                key={i}
                ref={(el) => { sectionRefs.current[i] = el; }}
                style={{
                  ...styles.textSection,
                  opacity: isVisible ? 1 : 0,
                  transform: isVisible ? 'translateY(0)' : 'translateY(40px)',
                  transition: 'opacity 0.7s ease, transform 0.7s ease',
                }}
              >
                <span style={styles.label}>{section.label}</span>
                <h2 className="tour-headline" style={styles.headline}>
                  {section.headline}
                </h2>
                <p style={styles.description}>{section.description}</p>
                <ul style={styles.bulletList}>
                  {section.bullets.map((bullet, j) => (
                    <li key={j} style={styles.bullet}>
                      <BulletPlayIcon />
                      <span style={styles.bulletText}>{bullet}</span>
                    </li>
                  ))}
                </ul>
              </div>
            );
          })}
        </div>

        {/* Demo column — sticky, vertically centred once scrolling */}
        <div style={styles.demoColumn}>
          {/* Spacer pushes the demo down to align with the first text section's
              vertical centre. The text sections are 80vh with justify:center,
              so the content sits roughly at 50vh from the section top. We use
              a similar offset here so the demo starts beside the first section. */}
          <div style={styles.demoSpacer} />
          <div style={styles.stickyDemo}>
            <LargeVisual section={SECTIONS[activeIdx]} />
          </div>
        </div>
      </div>
    </section>
  );
}

// ─── Small-screen section with its own AppDemo instance ──────────────────────
function SmallSection({
  section,
  index,
  total,
}: {
  section: TourSection;
  index: number;
  total: number;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          setVisible(true);
          observer.disconnect();
        }
      },
      { threshold: 0.1 },
    );
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  return (
    <div
      ref={ref}
      style={{
        ...styles.smallSection,
        opacity: visible ? 1 : 0,
        transform: visible ? 'translateY(0)' : 'translateY(40px)',
        transition: 'opacity 0.7s ease, transform 0.7s ease',
      }}
    >
      {/* Visual above text */}
      <div style={styles.smallDemoWrap}>
        <SmallVisual section={section} />
      </div>

      {/* Text below */}
      <span style={styles.label}>{section.label}</span>
      <h2 className="tour-headline" style={styles.headline}>
        {section.headline}
      </h2>
      <p style={styles.description}>{section.description}</p>
      <ul style={styles.bulletList}>
        {section.bullets.map((bullet, j) => (
          <li key={j} style={styles.bullet}>
            <BulletPlayIcon />
            <span style={styles.bulletText}>{bullet}</span>
          </li>
        ))}
      </ul>

      {/* Step dots */}
      <div style={styles.stepIndicator}>
        {Array.from({ length: total }, (_, j) => (
          <span
            key={j}
            style={{
              ...styles.stepDot,
              background: j === index ? '#5bbef0' : 'rgba(255,255,255,0.12)',
            }}
          />
        ))}
      </div>
    </div>
  );
}

// ─── Styles ───────────────────────────────────────────────────────────────────
const styles: Record<string, React.CSSProperties> = {
  section: {
    position: 'relative',
    background: 'transparent',
    padding: '0 24px 96px',
    zIndex: 1,
  },

  // ── Large-screen grid ──
  grid: {
    maxWidth: 1360,
    margin: '0 auto',
    display: 'grid',
    gridTemplateColumns: '380px 1fr',
    gap: 64,
  },
  textColumn: {
    display: 'flex',
    flexDirection: 'column' as const,
  },
  textSection: {
    minHeight: '80vh',
    display: 'flex',
    flexDirection: 'column' as const,
    justifyContent: 'center',
    padding: '72px 0',
  },
  demoColumn: {
    position: 'relative' as const,
  },
  demoSpacer: {
    /* Match the first text section: it's minHeight 80vh with justify:center,
       so its content sits roughly at 40vh from the top. A 20vh spacer
       positions the demo's top edge so it starts aligned with the first
       section's content block. */
    height: '20vh',
  },
  stickyDemo: {
    position: 'sticky' as const,
    top: '20vh',
  },

  // ── Small-screen stacked ──
  smallContainer: {
    maxWidth: 860,
    margin: '0 auto',
    display: 'flex',
    flexDirection: 'column' as const,
    gap: 80,
  },
  smallSection: {
    display: 'flex',
    flexDirection: 'column' as const,
  },
  smallDemoWrap: {
    width: '100%',
    marginBottom: 40,
  },

  // ── Shared text styles ──
  label: {
    display: 'inline-block',
    fontSize: 12,
    fontWeight: 600,
    letterSpacing: '0.08em',
    textTransform: 'uppercase' as const,
    color: '#5bbef0',
    marginBottom: 16,
  },
  headline: {
    fontSize: 'clamp(32px, 5vw, 54px)',
    fontWeight: 800,
    color: '#f9f9f7',
    lineHeight: 1.08,
    letterSpacing: '-0.04em',
    marginBottom: 20,
    whiteSpace: 'pre-line' as const,
  },
  description: {
    fontSize: 17,
    color: 'rgba(249,249,247,0.6)',
    lineHeight: 1.7,
    marginBottom: 28,
    maxWidth: 540,
  },
  bulletList: {
    listStyle: 'none',
    display: 'flex',
    flexDirection: 'column' as const,
    gap: 12,
    padding: 0,
    margin: 0,
  },
  bullet: {
    display: 'flex',
    alignItems: 'flex-start',
    gap: 12,
  },
  bulletIconWrap: {
    width: 14,
    height: 14,
    flexShrink: 0,
    marginTop: 5,
    display: 'inline-flex',
    alignItems: 'center',
    justifyContent: 'center',
    filter: 'drop-shadow(0 0 8px rgba(91,190,240,0.22))',
  },
  bulletText: {
    fontSize: 15,
    color: 'rgba(249,249,247,0.5)',
    lineHeight: 1.6,
  },
  stepIndicator: {
    display: 'flex',
    gap: 6,
    marginTop: 32,
  },
  stepDot: {
    width: 6,
    height: 6,
    borderRadius: '50%',
    display: 'inline-block',
    transition: 'background 0.3s ease',
  },
};
