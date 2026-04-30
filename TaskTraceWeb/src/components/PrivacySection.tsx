import React from 'react';
import { PlayIcon } from './Icons';

function LockIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
      <rect x="3" y="11" width="18" height="11" rx="2" />
      <path d="M7 11V7a5 5 0 0 1 10 0v4" />
    </svg>
  );
}

function EyeOffIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
      <path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94" />
      <path d="M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19" />
      <line x1="1" y1="1" x2="23" y2="23" />
    </svg>
  );
}

function CpuIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
      <rect x="4" y="4" width="16" height="16" rx="2" />
      <rect x="9" y="9" width="6" height="6" />
      <line x1="9" y1="1" x2="9" y2="4" /><line x1="15" y1="1" x2="15" y2="4" />
      <line x1="9" y1="20" x2="9" y2="23" /><line x1="15" y1="20" x2="15" y2="23" />
      <line x1="20" y1="9" x2="23" y2="9" /><line x1="20" y1="15" x2="23" y2="15" />
      <line x1="1" y1="9" x2="4" y2="9" /><line x1="1" y1="15" x2="4" y2="15" />
    </svg>
  );
}

const points = [
  {
    icon: <PlayIcon size={20} color="#5bbef0" />,
    title: 'All data stays on your Mac',
    body: 'TaskTrace records screenshots, keystrokes, transcripts, and summaries. All of it is stored in a local database on your device. Nothing is uploaded to our servers. (We don\'t even have servers.)',
  },
  {
    icon: <PlayIcon size={20} color="#5bbef0" />,
    title: 'No app telemetry',
    body: 'The TaskTrace app does not collect usage events, crash reports, advertising identifiers, or behavioral analytics. It does not phone home to TaskTrace servers.',
  },
  {
    icon: <PlayIcon size={20} color="#5bbef0" />,
    title: 'AI runs locally',
    body: 'Summarization and tagging use on-device AI models. Your work content never leaves your machine to reach a third-party AI API.',
  },
];

export default function PrivacySection() {
  return (
    <section id="privacy" style={styles.section}>
      <div style={styles.container}>
        <div style={styles.left}>
          <span style={styles.label}>Privacy-first</span>
          <h2 style={styles.heading}>Your work history<br />belongs to you</h2>
          <p style={styles.body}>
            TaskTrace captures sensitive data by design: code, emails, and documents. We built it from the
            ground up so that data never leaves your machine.
          </p>
        </div>
        <div style={styles.right}>
          {points.map((p, i) => (
            <div key={i} style={styles.point}>
              <span style={styles.pointIcon}>{p.icon}</span>
              <div>
                <h4 style={styles.pointTitle}>{p.title}</h4>
                <p style={styles.pointBody}>{p.body}</p>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
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
    display: 'flex',
    flexWrap: 'wrap',
    gap: '64px',
    alignItems: 'flex-start',
  },
  left: {
    flex: '1 1 300px',
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
    marginBottom: 20,
  },
  body: {
    fontSize: 16,
    color: 'var(--text-secondary)',
    lineHeight: 1.65,
  },
  right: {
    flex: '1 1 300px',
    display: 'flex',
    flexDirection: 'column',
    gap: 28,
  },
  point: {
    display: 'flex',
    gap: 18,
    alignItems: 'flex-start',
    padding: '20px 22px',
    background: 'rgba(255, 255, 255, 0.025)',
    border: '1px solid rgba(255, 255, 255, 0.06)',
    borderRadius: 14,
    backdropFilter: 'blur(8px)',
    WebkitBackdropFilter: 'blur(8px)',
    boxShadow: 'inset 0 1px 0 rgba(255, 255, 255, 0.04)',
  },
  pointIcon: {
    flexShrink: 0,
    marginTop: 2,
    color: '#5bbef0',
    display: 'flex',
  },
  pointTitle: {
    fontSize: 16,
    fontWeight: 600,
    color: 'var(--text-primary)',
    marginBottom: 6,
    letterSpacing: '-0.01em',
  },
  pointBody: {
    fontSize: 14.5,
    color: 'var(--text-secondary)',
    lineHeight: 1.6,
  },
};
