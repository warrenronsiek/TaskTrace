import React from 'react';
import DownloadLink from './DownloadLink';
import { GitHubIcon } from './Icons';
import { useVariant } from '../useCase';
import { TASKTRACE_GITHUB_REPO_URL } from '../vars';

export default function Hero() {
  const v = useVariant();

  return (
    <section style={styles.section}>
      {/* Ambient glow */}
      <div style={styles.glow} />

      <div style={styles.container}>
        <div style={styles.badge}>
          <span style={styles.badgeDot} />
          {v.badge}
        </div>

        <h1 style={styles.headline}>
          {v.headline[0]}
          <br />
          {v.headline[1]}
        </h1>

        <p style={styles.subheadline}>{v.subheadline}</p>

        <div style={styles.ctas}>
          <DownloadLink style={styles.primaryBtn}>
            <AppleIcon />
            {v.cta}
          </DownloadLink>
          <a
            href={TASKTRACE_GITHUB_REPO_URL}
            target="_blank"
            rel="noopener noreferrer"
            style={styles.secondaryBtn}
          >
            <GitHubIcon size={18} />
            View source
          </a>
        </div>
        <p style={styles.openSourceCopy}>
          TaskTrace is open source, so you can inspect the recorder, local AI pipeline, and
          release infrastructure before installing it.
        </p>
      </div>

    </section>
  );
}

function AppleIcon() {
  return (
    <svg
      width="30"
      height="30"
      viewBox="0 -2 16 18"
      fill="currentColor"
      style={{ display: 'block', flexShrink: 0, marginBottom: '-6px', marginLeft: '-5px' }}
    >
      <path d="M11.182 1C10.196 1 9.395 1.574 8.91 1.574c-.506 0-1.29-.547-2.16-.547C5.11 1.027 3.47 2.25 3.47 4.7c0 1.536.596 3.163 1.355 4.218.66.918 1.236 1.65 2.07 1.65.82 0 1.183-.538 2.2-.538 1.034 0 1.344.527 2.24.527.87 0 1.465-.793 2.012-1.59.617-.903.873-1.788.884-1.835-.032-.011-1.702-.69-1.702-2.587 0-1.638 1.294-2.398 1.352-2.44C12.852 1.44 11.9 1 11.182 1zM10.432 0c.384-.47.66-1.108.66-1.75 0-.09-.008-.18-.023-.258-.63.025-1.388.43-1.84.96-.34.392-.666 1.014-.666 1.662 0 .097.016.192.023.22.04.007.104.014.168.014.565 0 1.275-.385 1.678-.848z" />
    </svg>
  );
}

const styles: Record<string, React.CSSProperties> = {
  section: {
    position: 'relative',
    background: 'transparent',
    minHeight: '100vh',
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    padding: '120px 24px 60px',
    overflow: 'hidden',
    zIndex: 1,
  },
  glow: {
    position: 'absolute',
    top: '10%',
    left: '50%',
    transform: 'translateX(-50%)',
    width: 1000,
    height: 600,
    background:
      'radial-gradient(ellipse at center, rgba(91,190,240,0.1) 0%, rgba(91,190,240,0.03) 40%, transparent 70%)',
    pointerEvents: 'none',
  },
  container: {
    position: 'relative',
    maxWidth: 760,
    textAlign: 'center',
    zIndex: 1,
  },
  badge: {
    display: 'inline-flex',
    alignItems: 'center',
    gap: 7,
    fontSize: 12,
    fontWeight: 500,
    color: 'rgba(249,249,247,0.6)',
    background: 'rgba(255,255,255,0.05)',
    backdropFilter: 'blur(12px) saturate(140%)',
    WebkitBackdropFilter: 'blur(12px) saturate(140%)',
    border: '1px solid rgba(255,255,255,0.1)',
    borderRadius: 50,
    padding: '5px 14px',
    marginBottom: 28,
    letterSpacing: '0.01em',
    boxShadow: 'inset 0 1px 0 rgba(255,255,255,0.06)',
  },
  badgeDot: {
    width: 6,
    height: 6,
    borderRadius: '50%',
    background: '#5bbef0',
    display: 'inline-block',
  },
  headline: {
    fontSize: 'clamp(42px, 7vw, 72px)',
    fontWeight: 800,
    color: '#f9f9f7',
    lineHeight: 1.08,
    letterSpacing: '-0.04em',
    marginBottom: 24,
  },
  subheadline: {
    fontSize: 18,
    color: 'rgba(249,249,247,0.6)',
    lineHeight: 1.65,
    maxWidth: 580,
    margin: '0 auto 36px',
    fontWeight: 400,
  },
  ctas: {
    display: 'flex',
    justifyContent: 'center',
    gap: 14,
    flexWrap: 'wrap',
  },
  primaryBtn: {
    display: 'inline-flex',
    alignItems: 'center',
    gap: 8,
    padding: '14px 28px',
    background: '#5bbef0',
    color: '#0b0d11',
    fontSize: 15,
    fontWeight: 700,
    borderRadius: 50,
    transition: 'opacity 0.2s ease, transform 0.15s ease',
    textDecoration: 'none',
  },
  secondaryBtn: {
    display: 'inline-flex',
    alignItems: 'center',
    gap: 8,
    padding: '14px 24px',
    background: 'rgba(255,255,255,0.055)',
    color: '#f9f9f7',
    fontSize: 15,
    fontWeight: 650,
    borderRadius: 50,
    border: '1px solid rgba(255,255,255,0.12)',
    transition: 'border-color 0.2s ease, background 0.2s ease',
    textDecoration: 'none',
  },
  openSourceCopy: {
    fontSize: 13,
    color: 'rgba(249,249,247,0.46)',
    lineHeight: 1.6,
    maxWidth: 520,
    margin: '18px auto 0',
  },
};
