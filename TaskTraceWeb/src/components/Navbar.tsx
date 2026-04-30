import React, { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import DownloadLink from './DownloadLink';
import { GitHubIcon } from './Icons';
import { useUseCasePath, useVariant } from '../useCase';
import { TASKTRACE_GITHUB_REPO_URL } from '../vars';

const styles: Record<string, React.CSSProperties> = {
  nav: {
    position: 'fixed',
    top: 0,
    left: 0,
    right: 0,
    zIndex: 100,
    height: 60,
    display: 'flex',
    alignItems: 'center',
    transition: 'background 0.3s ease, backdrop-filter 0.3s ease, border-color 0.3s ease',
  },
  navScrolled: {
    background: 'rgba(11, 13, 17, 0.72)',
    backdropFilter: 'blur(20px) saturate(150%)',
    WebkitBackdropFilter: 'blur(20px) saturate(150%)',
    borderBottom: '1px solid rgba(255,255,255,0.06)',
    boxShadow: 'inset 0 1px 0 rgba(255,255,255,0.04), 0 4px 24px rgba(0,0,0,0.3)',
  },
  navTransparent: {
    background: 'transparent',
    borderBottom: '1px solid transparent',
  },
  inner: {
    width: '100%',
    maxWidth: 1100,
    margin: '0 auto',
    padding: '0 24px',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  logo: {
    fontSize: 17,
    fontWeight: 700,
    color: '#f9f9f7',
    letterSpacing: '-0.02em',
    display: 'inline-flex',
    alignItems: 'center',
    gap: 8,
  },
  links: {
    display: 'flex',
    alignItems: 'center',
    gap: 32,
  },
  link: {
    fontSize: 14,
    fontWeight: 500,
    color: 'rgba(249,249,247,0.7)',
    transition: 'color 0.15s ease',
    cursor: 'pointer',
  },
  iconLink: {
    color: 'rgba(249,249,247,0.68)',
    transition: 'color 0.15s ease',
    display: 'inline-flex',
    alignItems: 'center',
    justifyContent: 'center',
    width: 32,
    height: 32,
  },
  downloadBtn: {
    padding: '8px 18px',
    background: '#5bbef0',
    color: '#0b0d11',
    fontSize: 13,
    fontWeight: 600,
    borderRadius: 50,
    transition: 'opacity 0.2s ease',
    display: 'inline-flex',
    alignItems: 'center',
    gap: 6,
  },
};

export default function Navbar() {
  const [scrolled, setScrolled] = useState(false);
  const variant = useVariant();
  const homePath = useUseCasePath('/');
  const docsPath = useUseCasePath('/docs');
  const comparisonPath = '/compare';

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 20);
    window.addEventListener('scroll', onScroll, { passive: true });
    return () => window.removeEventListener('scroll', onScroll);
  }, []);

  const scrollTo = (id: string) => {
    document.getElementById(id)?.scrollIntoView({ behavior: 'smooth' });
  };

  return (
    <nav style={{ ...styles.nav, ...(scrolled ? styles.navScrolled : styles.navTransparent) }}>
      <style>{`
        @media (max-width: 600px) {
          .nav-text-links { display: none; }
        }
      `}</style>
      <div style={styles.inner}>
        <Link to={homePath} style={styles.logo}>
          <img src="/tasktrace-logo.svg" alt="TaskTrace logo" width={26} height={26} />
          TaskTrace
        </Link>
        <div style={styles.links}>
          <Link
            className="nav-text-links"
            to={comparisonPath}
            style={styles.link}
            onMouseEnter={e => ((e.currentTarget as HTMLAnchorElement).style.color = '#f9f9f7')}
            onMouseLeave={e => ((e.currentTarget as HTMLAnchorElement).style.color = 'rgba(249,249,247,0.7)')}
          >
            Comparisons
          </Link>
          <Link
            className="nav-text-links"
            to={docsPath}
            style={styles.link}
            onMouseEnter={e => ((e.currentTarget as HTMLAnchorElement).style.color = '#f9f9f7')}
            onMouseLeave={e => ((e.currentTarget as HTMLAnchorElement).style.color = 'rgba(249,249,247,0.7)')}
          >
            Docs
          </Link>
          <span
            className="nav-text-links"
            style={styles.link}
            onClick={() => scrollTo('features')}
            onMouseEnter={e => (e.currentTarget.style.color = '#f9f9f7')}
            onMouseLeave={e => (e.currentTarget.style.color = 'rgba(249,249,247,0.7)')}
          >
            Features
          </span>
          <span
            className="nav-text-links"
            style={styles.link}
            onClick={() => scrollTo('team')}
            onMouseEnter={e => (e.currentTarget.style.color = '#f9f9f7')}
            onMouseLeave={e => (e.currentTarget.style.color = 'rgba(249,249,247,0.7)')}
          >
            Team
          </span>
          <a
            href={TASKTRACE_GITHUB_REPO_URL}
            target="_blank"
            rel="noopener noreferrer"
            aria-label="TaskTrace on GitHub"
            title="TaskTrace on GitHub"
            style={styles.iconLink}
            onMouseEnter={e => ((e.currentTarget as HTMLAnchorElement).style.color = '#f9f9f7')}
            onMouseLeave={e => ((e.currentTarget as HTMLAnchorElement).style.color = 'rgba(249,249,247,0.68)')}
          >
            <GitHubIcon size={19} />
          </a>
          <DownloadLink
            style={styles.downloadBtn}
            onMouseEnter={e => ((e.currentTarget as HTMLAnchorElement).style.opacity = '0.85')}
            onMouseLeave={e => ((e.currentTarget as HTMLAnchorElement).style.opacity = '1')}
          >
            {variant.navCta}
          </DownloadLink>
        </div>
      </div>
    </nav>
  );
}
