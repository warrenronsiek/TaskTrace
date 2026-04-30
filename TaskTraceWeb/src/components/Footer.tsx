import React from 'react';
import { Link } from 'react-router-dom';
import DownloadLink from './DownloadLink';
import { GitHubIcon } from './Icons';
import { useUseCasePath, useVariant } from '../useCase';
import { TASKTRACE_GITHUB_REPO_URL } from '../vars';

export default function Footer() {
  const homePath = useUseCasePath('/');
  const privacyPath = useUseCasePath('/privacy');
  const termsPath = useUseCasePath('/terms');
  const licensePath = useUseCasePath('/license');
  const variant = useVariant();

  return (
    <footer style={styles.footer}>
      <div style={styles.container}>
        <div style={styles.top}>
          <div style={styles.brand}>
            <Link to={homePath} style={styles.logo}>
              TaskTrace
            </Link>
            <p style={styles.tagline}>AI-powered work tracking for macOS</p>
            <p style={styles.openSource}>
              Open source and local-first. Inspect the code before you run it.
            </p>
          </div>
          <div style={styles.links}>
            <div style={styles.linkGroup}>
              <span style={styles.groupTitle}>Product</span>
              <a
                href={TASKTRACE_GITHUB_REPO_URL}
                target="_blank"
                rel="noopener noreferrer"
                style={styles.linkIcon}
                onMouseEnter={e => (e.currentTarget.style.color = '#f9f9f7')}
                onMouseLeave={e => (e.currentTarget.style.color = 'rgba(249,249,247,0.5)')}
              >
                <GitHubIcon size={15} />
                GitHub
              </a>
              <DownloadLink
                style={styles.link}
                onMouseEnter={e => (e.currentTarget.style.color = '#f9f9f7')}
                onMouseLeave={e => (e.currentTarget.style.color = 'rgba(249,249,247,0.5)')}
              >
                {variant.navCta}
              </DownloadLink>
            </div>
            <div style={styles.linkGroup}>
              <span style={styles.groupTitle}>Company</span>
              <span
                style={{ ...styles.link, cursor: 'pointer' }}
                onClick={() => document.getElementById('team')?.scrollIntoView({ behavior: 'smooth' })}
                onMouseEnter={e => (e.currentTarget.style.color = '#f9f9f7')}
                onMouseLeave={e => (e.currentTarget.style.color = 'rgba(249,249,247,0.5)')}
              >
                Team
              </span>
            </div>
            <div style={styles.linkGroup}>
              <span style={styles.groupTitle}>Legal</span>
              <Link
                to={privacyPath}
                style={styles.link}
                onMouseEnter={e => (e.currentTarget.style.color = '#f9f9f7')}
                onMouseLeave={e => (e.currentTarget.style.color = 'rgba(249,249,247,0.5)')}
              >
                Privacy Policy
              </Link>
              <Link
                to={termsPath}
                style={styles.link}
                onMouseEnter={e => (e.currentTarget.style.color = '#f9f9f7')}
                onMouseLeave={e => (e.currentTarget.style.color = 'rgba(249,249,247,0.5)')}
              >
                Terms of Service
              </Link>
              <Link
                to={licensePath}
                style={styles.link}
                onMouseEnter={e => (e.currentTarget.style.color = '#f9f9f7')}
                onMouseLeave={e => (e.currentTarget.style.color = 'rgba(249,249,247,0.5)')}
              >
                License
              </Link>
            </div>
          </div>
        </div>
        <div style={styles.bottom}>
          <span style={styles.copy}>© {new Date().getFullYear()} TaskTrace. All rights reserved.</span>
        </div>
      </div>
    </footer>
  );
}

const styles: Record<string, React.CSSProperties> = {
  footer: {
    position: 'relative',
    background: 'rgba(7, 9, 14, 0.6)',
    backdropFilter: 'blur(16px)',
    WebkitBackdropFilter: 'blur(16px)',
    borderTop: '1px solid rgba(255,255,255,0.06)',
    padding: '56px 24px 40px',
    zIndex: 1,
  },
  container: {
    maxWidth: 1100,
    margin: '0 auto',
  },
  top: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    gap: 48,
    marginBottom: 48,
    flexWrap: 'wrap',
  },
  brand: {
    flex: '1 1 200px',
  },
  logo: {
    fontSize: 17,
    fontWeight: 700,
    color: '#f9f9f7',
    letterSpacing: '-0.02em',
    display: 'block',
    marginBottom: 8,
  },
  tagline: {
    fontSize: 14,
    color: 'rgba(249,249,247,0.4)',
    lineHeight: 1.5,
    marginBottom: 8,
  },
  openSource: {
    fontSize: 13,
    color: 'rgba(249,249,247,0.32)',
    lineHeight: 1.5,
    maxWidth: 260,
  },
  links: {
    display: 'flex',
    gap: 56,
    flexWrap: 'wrap',
  },
  linkGroup: {
    display: 'flex',
    flexDirection: 'column',
    gap: 10,
  },
  groupTitle: {
    fontSize: 12,
    fontWeight: 600,
    letterSpacing: '0.07em',
    textTransform: 'uppercase',
    color: 'rgba(249,249,247,0.25)',
    marginBottom: 2,
  },
  link: {
    fontSize: 14,
    color: 'rgba(249,249,247,0.5)',
    transition: 'color 0.15s ease',
    display: 'block',
    textDecoration: 'none',
  },
  linkIcon: {
    fontSize: 14,
    color: 'rgba(249,249,247,0.5)',
    transition: 'color 0.15s ease',
    display: 'inline-flex',
    alignItems: 'center',
    gap: 7,
    textDecoration: 'none',
  },
  bottom: {
    borderTop: '1px solid rgba(255,255,255,0.06)',
    paddingTop: 24,
  },
  copy: {
    fontSize: 13,
    color: 'rgba(249,249,247,0.25)',
  },
};
