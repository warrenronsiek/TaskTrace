import React from 'react';
import { PlayIcon, StopIcon } from './Icons';

const before = [
  'You explain your situation every time you open a chat',
  'Context is lost between sessions',
  'AI reacts to prompts. It never anticipates.',
  'Work is fragmented across tools and memory',
];

const after = [
  'Agents see your workflow as it happens',
  'Agents query your full session history on demand',
  'Proactive help, not just reactive responses',
  'Your system understands what you\'re doing',
];

export default function AgentContext() {
  return (
    <section id="agents" style={styles.section}>
      <style>{`
        @media (max-width: 640px) {
          .agent-comparison { grid-template-columns: 1fr !important; }
          .agent-divider { display: none; }
        }
      `}</style>
      <div style={styles.container}>

        {/* Header */}
        <div style={styles.header}>
          <span style={styles.label}>For AI agents</span>
          <h2 style={styles.heading}>The missing layer<br />between you and AI</h2>
          <p style={styles.subheading}>
            Agents don't need instructions. They need context.
          </p>
        </div>

        {/* Body copy */}
        <p style={styles.body}>
          TaskTrace passively observes your activity across applications, documents, keystrokes, and
          conversations, then converts it into structured context. That context is continuously
          summarized and exposed to your local AI agents via an MCP server. Instead of explaining
          what you're working on, your tools can now see it. Move from reactive prompts to
          proactive assistance.
        </p>

        {/* Before / After */}
        <div className="agent-comparison" style={styles.comparison}>
          <ComparisonColumn
            label="Reactive"
            items={before}
            variant="before"
          />
          <div className="agent-divider" style={styles.divider} />
          <ComparisonColumn
            label="Proactive"
            items={after}
            variant="after"
          />
        </div>

      </div>
    </section>
  );
}

function ComparisonColumn({
  label,
  items,
  variant,
}: {
  label: string;
  items: string[];
  variant: 'before' | 'after';
}) {
  const isBefore = variant === 'before';
  return (
    <div style={styles.column}>
      <div style={{ ...styles.columnLabel, ...(isBefore ? styles.columnLabelBefore : styles.columnLabelAfter) }}>
        {label}
      </div>
      <ul style={styles.list}>
        {items.map((item, i) => (
          <li key={i} style={styles.listItem}>
            <span style={{ ...styles.bullet, ...(isBefore ? styles.bulletBefore : styles.bulletAfter) }}>
              {isBefore
                ? <StopIcon size={14} color="rgba(255,68,102,0.5)" />
                : <PlayIcon size={14} color="#5bbef0" />}
            </span>
            <span style={{ ...styles.itemText, ...(isBefore ? styles.itemTextBefore : {}) }}>
              {item}
            </span>
          </li>
        ))}
      </ul>
    </div>
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
    maxWidth: 900,
    margin: '0 auto',
  },
  header: {
    textAlign: 'center',
    marginBottom: 32,
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
    fontSize: 'clamp(28px, 4vw, 48px)',
    fontWeight: 800,
    letterSpacing: '-0.04em',
    color: '#f9f9f7',
    lineHeight: 1.1,
    marginBottom: 16,
  },
  subheading: {
    fontSize: 20,
    color: 'rgba(249,249,247,0.55)',
    fontStyle: 'italic',
    fontWeight: 400,
  },
  body: {
    fontSize: 17,
    color: 'rgba(249,249,247,0.6)',
    lineHeight: 1.75,
    maxWidth: 720,
    margin: '0 auto 56px',
    textAlign: 'center',
  },
  comparison: {
    display: 'grid',
    gridTemplateColumns: '1fr auto 1fr',
    gap: 0,
    background: 'rgba(255,255,255,0.03)',
    backdropFilter: 'blur(16px) saturate(130%)',
    WebkitBackdropFilter: 'blur(16px) saturate(130%)',
    border: '1px solid rgba(255,255,255,0.07)',
    borderRadius: 20,
    overflow: 'hidden',
    marginBottom: 40,
    boxShadow: 'inset 0 1px 0 rgba(255,255,255,0.05), 0 4px 24px rgba(0,0,0,0.25)',
  },
  divider: {
    width: 1,
    background: 'rgba(255,255,255,0.07)',
  },
  column: {
    padding: '36px 40px',
  },
  columnLabel: {
    fontSize: 12,
    fontWeight: 700,
    letterSpacing: '0.09em',
    textTransform: 'uppercase',
    marginBottom: 24,
    display: 'inline-block',
    padding: '4px 12px',
    borderRadius: 50,
  },
  columnLabelBefore: {
    color: 'rgba(255,68,102,0.6)',
    background: 'rgba(255,68,102,0.08)',
  },
  columnLabelAfter: {
    color: '#5bbef0',
    background: 'rgba(91,190,240,0.1)',
  },
  list: {
    listStyle: 'none',
    display: 'flex',
    flexDirection: 'column',
    gap: 16,
  },
  listItem: {
    display: 'flex',
    alignItems: 'flex-start',
    gap: 12,
  },
  bullet: {
    flexShrink: 0,
    fontSize: 13,
    fontWeight: 700,
    marginTop: 1,
  },
  bulletBefore: {
    color: 'rgba(249,249,247,0.2)',
  },
  bulletAfter: {
    color: '#5bbef0',
  },
  itemText: {
    fontSize: 15,
    color: 'rgba(249,249,247,0.75)',
    lineHeight: 1.5,
  },
  itemTextBefore: {
    color: 'rgba(249,249,247,0.35)',
    textDecoration: 'line-through',
    textDecorationColor: 'rgba(249,249,247,0.15)',
  },
  callout: {
    textAlign: 'center',
    padding: '28px 32px',
    background: 'rgba(91,190,240,0.05)',
    border: '1px solid rgba(91,190,240,0.12)',
    borderRadius: 14,
  },
  calloutText: {
    fontSize: 17,
    color: 'rgba(249,249,247,0.6)',
    lineHeight: 1.6,
  },
  calloutEmphasis: {
    color: '#f9f9f7',
    fontWeight: 600,
  },
};
