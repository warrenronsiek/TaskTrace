import React from 'react';
import { Link } from 'react-router-dom';
import { useUseCasePath } from '../useCase';
import { PlayIcon } from './Icons';

const integrations = [
  {
    partner: 'openclaw',
    label: 'TaskTrace + OpenClaw',
    title: 'Persistent context for agent workflows',
    body:
      'TaskTrace exposes your recent work, summaries, and knowledge graph over MCP so OpenClaw can query what you already did before it starts guessing. Triggered workflows can react to new activity, while graph search gives longer-lived agents the surrounding context they need to stay aligned with the project.',
    points: [
      'OpenClaw reads live TaskTrace feeds and search tools from the local MCP server',
      'Graph search gives agent threads access to communities, claims, and related concepts from the currently selected knowledge directory',
      'Triggered actions let TaskTrace push important work events into persistent OpenClaw conversations',
    ],
  },
  {
    partner: 'obsidian',
    label: 'TaskTrace + Obsidian',
    title: 'Your notes stay useful without becoming another job',
    body:
      'People want a real knowledge base, but most note systems fall apart when upkeep becomes manual work. TaskTrace keeps your Obsidian archive current automatically, so your notes stay organized, searchable, and worth coming back to.',
    points: [
      'Keep project knowledge readable and current without spending time maintaining it by hand',
      'Return to old work faster because the important context is already organized in one place',
      'Avoid duplicate, stale, and half-maintained notes that make most personal knowledge systems collapse',
    ],
  },
];

export default function IntegrationsSection() {
  const docsPath = useUseCasePath('/docs');

  return (
    <section style={styles.section}>
      <style>{`
        @media (max-width: 860px) {
          .integration-grid {
            grid-template-columns: 1fr !important;
          }
        }
      `}</style>
      <div style={styles.container}>
        <div style={styles.header}>
          <span style={styles.kicker}>Integrations</span>
          <h2 style={styles.heading}>TaskTrace in the loop</h2>
          <p style={styles.subheading}>
            Capture is only the first step. The value is in how that context flows into the tools you already use.
          </p>
        </div>

        <div className="integration-grid" style={styles.grid}>
          {integrations.map(integration => (
            <article key={integration.label} style={styles.card}>
              <div style={styles.badgeRow}>
                <div style={styles.appPair}>
                  <span style={styles.appIconChip}>
                    <img src="/tasktrace-logo.svg" alt="TaskTrace" width={22} height={22} />
                  </span>
                  <span style={styles.plus}>+</span>
                  <span style={styles.appIconChip}>
                    {integration.partner === 'openclaw' ? (
                      <svg width="24" height="24" viewBox="0 0 120 120" fill="none" aria-label="OpenClaw">
                        <path d="M60 10 C30 10 15 35 15 55 C15 75 30 95 45 100 L45 110 L55 110 L55 100 C55 100 60 102 65 100 L65 110 L75 110 L75 100 C90 95 105 75 105 55 C105 35 90 10 60 10Z" fill="url(#openclaw-lobster-gradient)" />
                        <path d="M20 45 C5 40 0 50 5 60 C10 70 20 65 25 55 C28 48 25 45 20 45Z" fill="url(#openclaw-lobster-gradient)" />
                        <path d="M100 45 C115 40 120 50 115 60 C110 70 100 65 95 55 C92 48 95 45 100 45Z" fill="url(#openclaw-lobster-gradient)" />
                        <path d="M45 15 Q35 5 30 8" stroke="#ff8d6a" strokeWidth="2" strokeLinecap="round" />
                        <path d="M75 15 Q85 5 90 8" stroke="#ff8d6a" strokeWidth="2" strokeLinecap="round" />
                        <circle cx="45" cy="35" r="6" fill="#050810" />
                        <circle cx="75" cy="35" r="6" fill="#050810" />
                        <circle cx="46" cy="34" r="2" fill="#00e5cc" />
                        <circle cx="76" cy="34" r="2" fill="#00e5cc" />
                        <defs>
                          <linearGradient id="openclaw-lobster-gradient" x1="0%" y1="0%" x2="100%" y2="100%">
                            <stop offset="0%" stopColor="#ff8a5b" />
                            <stop offset="100%" stopColor="#ff5c7a" />
                          </linearGradient>
                        </defs>
                      </svg>
                    ) : (
                      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" aria-label="Obsidian">
                        <path d="M12.4 1.8 5.9 6.7 4.6 14.1 9.3 21.8 15.7 20.5 19.7 12.5 17.8 5.8 12.4 1.8Z" fill="#7C4DFF" />
                        <path d="M12.4 1.8 9.6 8.6 12 14.5 15.4 9.2 12.4 1.8Z" fill="#A88BFF" />
                        <path d="M5.9 6.7 9.6 8.6 12.4 1.8 5.9 6.7Z" fill="#5A35C9" />
                        <path d="M4.6 14.1 9.6 8.6 12 14.5 9.3 21.8 4.6 14.1Z" fill="#6B43E3" />
                        <path d="M12 14.5 15.4 9.2 19.7 12.5 15.7 20.5 12 14.5Z" fill="#8F6BFF" />
                        <path d="M15.4 9.2 17.8 5.8 19.7 12.5 15.4 9.2Z" fill="#C6B6FF" />
                      </svg>
                    )}
                  </span>
                </div>
                <span style={styles.cardLabel}>{integration.label}</span>
              </div>
              <h3 style={styles.cardTitle}>{integration.title}</h3>
              <p style={styles.cardBody}>{integration.body}</p>
              <div style={styles.pointList}>
                {integration.points.map(point => (
                  <div key={point} style={styles.pointRow}>
                    <PlayIcon size={14} color="#5bbef0" style={{ marginTop: 4 }} />
                    <span style={styles.pointText}>{point}</span>
                  </div>
                ))}
              </div>
            </article>
          ))}
        </div>

        <p style={styles.footer}>
          The MCP server docs cover the retrieval surface in detail, including activity search and graph search.
          <Link to={docsPath} style={styles.link}> Read the docs.</Link>
        </p>
      </div>
    </section>
  );
}

const styles: Record<string, React.CSSProperties> = {
  section: {
    position: 'relative',
    padding: '96px 24px',
    zIndex: 1,
  },
  container: {
    maxWidth: 1120,
    margin: '0 auto',
  },
  header: {
    textAlign: 'center',
    maxWidth: 780,
    margin: '0 auto 48px',
  },
  kicker: {
    display: 'inline-block',
    fontSize: 12,
    fontWeight: 600,
    letterSpacing: '0.08em',
    textTransform: 'uppercase',
    color: '#5bbef0',
    marginBottom: 12,
  },
  heading: {
    fontSize: 'clamp(30px, 4vw, 50px)',
    fontWeight: 800,
    letterSpacing: '-0.04em',
    color: '#f9f9f7',
    lineHeight: 1.05,
    margin: 0,
  },
  subheading: {
    fontSize: 18,
    color: 'rgba(249,249,247,0.58)',
    lineHeight: 1.7,
    marginTop: 18,
  },
  grid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(2, minmax(0, 1fr))',
    gap: 24,
  },
  card: {
    padding: '32px 30px',
    borderRadius: 24,
    background: 'linear-gradient(180deg, rgba(255,255,255,0.06), rgba(255,255,255,0.03))',
    border: '1px solid rgba(255,255,255,0.09)',
    boxShadow: '0 24px 80px rgba(0,0,0,0.26)',
    backdropFilter: 'blur(18px) saturate(130%)',
    WebkitBackdropFilter: 'blur(18px) saturate(130%)',
  },
  badgeRow: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 16,
    marginBottom: 18,
    flexWrap: 'wrap',
  },
  appPair: {
    display: 'inline-flex',
    alignItems: 'center',
    gap: 10,
  },
  appIconChip: {
    width: 42,
    height: 42,
    borderRadius: 14,
    display: 'inline-flex',
    alignItems: 'center',
    justifyContent: 'center',
    background: 'rgba(255,255,255,0.06)',
    border: '1px solid rgba(255,255,255,0.1)',
    boxShadow: 'inset 0 1px 0 rgba(255,255,255,0.06)',
    flexShrink: 0,
  },
  plus: {
    fontSize: 16,
    fontWeight: 700,
    color: 'rgba(249,249,247,0.55)',
  },
  cardLabel: {
    display: 'inline-block',
    fontSize: 12,
    fontWeight: 700,
    letterSpacing: '0.08em',
    textTransform: 'uppercase',
    color: 'rgba(120,199,245,0.9)',
    marginBottom: 16,
  },
  cardTitle: {
    fontSize: 28,
    lineHeight: 1.1,
    letterSpacing: '-0.03em',
    color: '#f9f9f7',
    margin: '0 0 14px',
  },
  cardBody: {
    fontSize: 16,
    color: 'rgba(249,249,247,0.7)',
    lineHeight: 1.75,
    margin: '0 0 24px',
  },
  pointList: {
    display: 'flex',
    flexDirection: 'column',
    gap: 14,
  },
  pointRow: {
    display: 'flex',
    alignItems: 'flex-start',
    gap: 12,
  },
  pointText: {
    fontSize: 15,
    lineHeight: 1.6,
    color: 'rgba(249,249,247,0.78)',
  },
  footer: {
    marginTop: 28,
    textAlign: 'center',
    fontSize: 15,
    lineHeight: 1.7,
    color: 'rgba(249,249,247,0.58)',
  },
  link: {
    color: '#78C7F5',
    textDecoration: 'none',
  },
};
