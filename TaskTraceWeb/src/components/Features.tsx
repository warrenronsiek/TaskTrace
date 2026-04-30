import React, { useEffect, useRef, useState } from 'react';
import { PlayIcon } from './Icons';

interface Feature {
  icon: React.ReactNode;
  title: string;
  description: string;
}

const features: Feature[] = [
  {
    icon: <PlayIcon size={22} color="#5bbef0" />,
    title: 'Passive capture',
    description:
      'Press play, do your work, press stop. TaskTrace silently records your active application, keystrokes, and microphone in the background. No manual input required.',
  },
  {
    icon: <AiIcon />,
    title: 'AI summaries',
    description:
      'When you stop recording, an AI pipeline automatically describes screenshots, transcribes audio, summarizes each activity, and groups everything into meaningful daily overviews.',
  },
  {
    icon: <TagIcon />,
    title: 'Tag-based organization',
    description:
      'Create tags for clients, projects, or billing categories. AI suggests the right tag for each activity. Filter analytics and overviews by tag for instant reports.',
  },
  {
    icon: <AnalyticsIcon />,
    title: 'Time analytics',
    description:
      'A GitHub-style heatmap shows your tracked time over the last year. A 14-day bar chart breaks down how time splits across tags. See patterns you never noticed before.',
  },
  {
    icon: <CalendarIcon />,
    title: 'Full history',
    description:
      'Browse any past day with the calendar. Every session is stored locally in SQLite. Your entire work history is always available, offline, in seconds.',
  },
  {
    icon: <McpIcon />,
    title: 'Agent-ready context API',
    description:
      'A local MCP server exposes your work history to AI agents in real time. Claude, Cursor, and other tools can query what you\'re doing and act on it. No prompt writing required.',
  },
];

export default function Features() {
  return (
    <section id="features" style={styles.section}>
      <style>{`
        @media (max-width: 640px) {
          .features-grid { grid-template-columns: 1fr !important; }
        }
        .glass-card:hover {
          background: rgba(255, 255, 255, 0.055) !important;
          border-color: rgba(255, 255, 255, 0.12) !important;
          box-shadow: inset 0 1px 0 rgba(255,255,255,0.08), 0 4px 20px rgba(0,0,0,0.25) !important;
        }
      `}</style>
      <div style={styles.container}>
        <span style={styles.label}>Features</span>
        <h2 style={styles.heading}>Capture your workflow.<br />Make it useful.</h2>
        <p style={styles.subheading}>
          For developers, consultants, and anyone who wants AI to understand their work, not just respond to it.
        </p>

        <div className="features-grid" style={styles.grid}>
          {features.map((f, i) => (
            <FeatureCard key={i} feature={f} index={i} />
          ))}
        </div>
      </div>
    </section>
  );
}

function FeatureCard({ feature, index }: { feature: Feature; index: number }) {
  const ref = useRef<HTMLDivElement>(null);
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const observer = new IntersectionObserver(
      ([entry]) => { if (entry.isIntersecting) { setVisible(true); observer.disconnect(); } },
      { threshold: 0.15 }
    );
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  return (
    <div
      ref={ref}
      className={`glass-card${visible ? ' feature-card-visible' : ''}`}
      style={{
        ...styles.card,
        opacity: visible ? undefined : 0,
        animationDelay: visible ? `${index * 80}ms` : undefined,
      }}
    >
      <div style={styles.iconWrap}>{feature.icon}</div>
      <h3 style={styles.cardTitle}>{feature.title}</h3>
      <p style={styles.cardDesc}>{feature.description}</p>
    </div>
  );
}

/* ===== Icons ===== */

function RecordIcon() {
  return (
    <svg width="22" height="22" viewBox="0 0 22 22" fill="none">
      <circle cx="11" cy="11" r="6" fill="currentColor" opacity="0.9" />
      <circle cx="11" cy="11" r="10" stroke="currentColor" strokeWidth="1.5" opacity="0.3" />
    </svg>
  );
}

function AiIcon() {
  return (
    <svg width="22" height="22" viewBox="0 0 22 22" fill="none">
      <path d="M4 11h14M11 4v14" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
      <circle cx="11" cy="11" r="3" fill="currentColor" />
      <circle cx="4" cy="11" r="1.5" fill="currentColor" opacity="0.5" />
      <circle cx="18" cy="11" r="1.5" fill="currentColor" opacity="0.5" />
      <circle cx="11" cy="4" r="1.5" fill="currentColor" opacity="0.5" />
      <circle cx="11" cy="18" r="1.5" fill="currentColor" opacity="0.5" />
    </svg>
  );
}

function TagIcon() {
  return (
    <svg width="22" height="22" viewBox="0 0 22 22" fill="none">
      <path
        d="M3 3h8l8 8-8 8-8-8V3z"
        stroke="currentColor"
        strokeWidth="1.8"
        strokeLinejoin="round"
      />
      <circle cx="7.5" cy="7.5" r="1.5" fill="currentColor" />
    </svg>
  );
}

function AnalyticsIcon() {
  return (
    <svg width="22" height="22" viewBox="0 0 22 22" fill="none">
      <rect x="3" y="14" width="4" height="5" rx="1" fill="currentColor" opacity="0.5" />
      <rect x="9" y="9" width="4" height="10" rx="1" fill="currentColor" opacity="0.75" />
      <rect x="15" y="5" width="4" height="14" rx="1" fill="currentColor" />
    </svg>
  );
}

function CalendarIcon() {
  return (
    <svg width="22" height="22" viewBox="0 0 22 22" fill="none">
      <rect x="3" y="5" width="16" height="14" rx="2" stroke="currentColor" strokeWidth="1.8" />
      <path d="M3 9h16" stroke="currentColor" strokeWidth="1.5" />
      <path d="M7 3v4M15 3v4" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />
      <circle cx="11" cy="14" r="1.5" fill="currentColor" />
    </svg>
  );
}

function McpIcon() {
  return (
    <svg width="22" height="22" viewBox="0 0 22 22" fill="none">
      <path
        d="M4 11a7 7 0 1 1 14 0 7 7 0 0 1-14 0z"
        stroke="currentColor"
        strokeWidth="1.8"
      />
      <path d="M11 11l-3-3M11 11l3-3M11 11v4" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" />
    </svg>
  );
}

const styles: Record<string, React.CSSProperties> = {
  section: {
    position: 'relative',
    background: 'transparent',
    padding: '96px 24px',
    zIndex: 1,
  },
  container: {
    maxWidth: 1100,
    margin: '0 auto',
    textAlign: 'center',
  },
  label: {
    display: 'inline-block',
    fontSize: 12,
    fontWeight: 600,
    letterSpacing: '0.08em',
    textTransform: 'uppercase',
    color: '#5bbef0',
    marginBottom: 12,
  },
  heading: {
    fontSize: 'clamp(28px, 4vw, 44px)',
    fontWeight: 800,
    letterSpacing: '-0.03em',
    color: 'var(--text-primary)',
    lineHeight: 1.12,
    marginBottom: 16,
  },
  subheading: {
    fontSize: 17,
    color: 'var(--text-secondary)',
    marginBottom: 64,
    maxWidth: 520,
    margin: '0 auto 64px',
    lineHeight: 1.6,
  },
  grid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(auto-fit, minmax(300px, 1fr))',
    gap: 20,
    textAlign: 'left',
  },
  card: {
    background: 'rgba(255, 255, 255, 0.03)',
    borderRadius: 16,
    padding: '28px 28px 32px',
    border: '1px solid rgba(255, 255, 255, 0.07)',
    backdropFilter: 'blur(12px) saturate(130%)',
    WebkitBackdropFilter: 'blur(12px) saturate(130%)',
    boxShadow: 'inset 0 1px 0 rgba(255, 255, 255, 0.05), 0 2px 12px rgba(0, 0, 0, 0.2)',
    transition: 'background 0.25s ease, border-color 0.25s ease, box-shadow 0.25s ease',
  },
  iconWrap: {
    width: 44,
    height: 44,
    background: 'rgba(91, 190, 240, 0.08)',
    border: '1px solid rgba(91, 190, 240, 0.12)',
    borderRadius: 12,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    color: '#5bbef0',
    marginBottom: 18,
  },
  cardTitle: {
    fontSize: 17,
    fontWeight: 700,
    color: 'var(--text-primary)',
    marginBottom: 10,
    letterSpacing: '-0.02em',
  },
  cardDesc: {
    fontSize: 14.5,
    color: 'var(--text-secondary)',
    lineHeight: 1.65,
  },
};
