import React, { useEffect, useState } from 'react';
import { Link, useLocation, useParams } from 'react-router-dom';
import { comparisonPages } from '../comparisonContent';
import { PlayIcon, StopIcon } from '../components/Icons';
import DownloadLink from '../components/DownloadLink';

const competitorLinks: Record<string, string> = {
  RescueTime: 'https://www.rescuetime.com/',
  'Toggl Track': 'https://toggl.com/track/',
  'Time Doctor': 'https://www.timedoctor.com/',
  Hubstaff: 'https://hubstaff.com/',
  Timely: 'https://timelyapp.com/',
  Harvest: 'https://www.getharvest.com/',
  Rize: 'https://rize.io/',
  DeskTime: 'https://desktime.com/',
  LinkedIn: 'https://www.linkedin.com/',
  Upwork: 'https://www.upwork.com/',
  Rewind: 'https://www.rewind.ai/',
  Limitless: 'https://www.limitless.ai/',
  ActivityWatch: 'https://activitywatch.net/',
  ManicTime: 'https://www.manictime.com/',
  TimeCamp: 'https://www.timecamp.com/',
  Connecteam: 'https://connecteam.com/',
};

function getFaviconUrl(url: string) {
  return `https://www.google.com/s2/favicons?domain_url=${encodeURIComponent(url)}&sz=64`;
}

export default function ComparisonIndexPage() {
  const { comparisonSlug } = useParams();
  const location = useLocation();
  const [activeSlug, setActiveSlug] = useState(comparisonSlug ?? comparisonPages[0].slug);

  useEffect(() => {
    document.title = 'TaskTrace | Compare Use Cases';
    document.querySelector('meta[name="description"]')?.setAttribute('content', 'Compare TaskTrace across passive tracking, proof of work, billables, local-first memory, and other adjacent categories.');
    document.querySelector('meta[property="og:title"]')?.setAttribute('content', 'TaskTrace | Compare Use Cases');
    document.querySelector('meta[property="og:description"]')?.setAttribute('content', 'Compare TaskTrace across passive tracking, proof of work, billables, local-first memory, and other adjacent categories.');
    document.querySelector('meta[property="og:url"]')?.setAttribute('content', 'https://www.tasktrace.com/compare');
    document.querySelector('meta[name="twitter:title"]')?.setAttribute('content', 'TaskTrace | Compare Use Cases');
    document.querySelector('meta[name="twitter:description"]')?.setAttribute('content', 'Compare TaskTrace across passive tracking, proof of work, billables, local-first memory, and other adjacent categories.');
    document.querySelector('meta[name="twitter:url"]')?.setAttribute('content', 'https://www.tasktrace.com/compare');
    document.querySelector('link[rel="canonical"]')?.setAttribute('href', 'https://www.tasktrace.com/compare');
  }, []);

  useEffect(() => {
    const targetSlug = comparisonSlug ?? location.hash.replace('#', '');

    if (!targetSlug) {
      return;
    }

    const target = document.getElementById(targetSlug);

    if (!target) {
      return;
    }

    window.setTimeout(() => {
      target.scrollIntoView({ behavior: 'smooth', block: 'start' });
      setActiveSlug(targetSlug);
      window.history.replaceState({}, '', `/compare#${targetSlug}`);
    }, 80);
  }, [comparisonSlug, location.hash]);

  useEffect(() => {
    const sections = comparisonPages
      .map(page => document.getElementById(page.slug))
      .filter(Boolean) as HTMLElement[];

    const observer = new IntersectionObserver(
      entries => {
        const visible = entries
          .filter(entry => entry.isIntersecting)
          .sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top);

        if (visible[0]) {
          setActiveSlug(visible[0].target.id);
          window.history.replaceState({}, '', `/compare#${visible[0].target.id}`);
        }
      },
      { rootMargin: '-20% 0px -60% 0px', threshold: 0.1 }
    );

    sections.forEach(section => observer.observe(section));

    return () => observer.disconnect();
  }, []);

  const scrollToSection = (slug: string) => {
    document.getElementById(slug)?.scrollIntoView({ behavior: 'smooth', block: 'start' });
    setActiveSlug(slug);
    window.history.replaceState({}, '', `/compare#${slug}`);
  };

  return (
    <div style={styles.page}>
      <style>{`
        @media (max-width: 980px) {
          .compare-layout { grid-template-columns: 1fr !important; }
          .compare-sidebar { position: static !important; top: auto !important; }
          .compare-nav-list { display: grid !important; grid-template-columns: repeat(2, minmax(0, 1fr)); }
        }
        @media (max-width: 720px) {
          .compare-nav-list { grid-template-columns: 1fr !important; }
          .compare-hero-actions { flex-direction: column; align-items: stretch; }
          .compare-competitor-row { flex-direction: column; align-items: stretch; }
          .compare-fit-grid { grid-template-columns: 1fr !important; }
          .compare-competitor-grid { grid-template-columns: 1fr !important; }
          .compare-advantage-grid { grid-template-columns: 1fr !important; }
        }
      `}</style>
      <div style={styles.orbA} />
      <div style={styles.orbB} />
      <div style={styles.orbC} />

      <header style={styles.header}>
        <div style={styles.headerInner}>
          <Link to="/" style={styles.logo}>
            <img src="/tasktrace-logo.svg" alt="TaskTrace logo" width={24} height={24} />
            TaskTrace
          </Link>
          <div style={styles.headerLinks}>
            <Link to="/docs" style={styles.headerLink}>Docs</Link>
            <Link to="/privacy" style={styles.headerLink}>Privacy</Link>
            <DownloadLink style={styles.downloadButton}>Download</DownloadLink>
          </div>
        </div>
      </header>

      <main style={styles.main}>
        <div className="compare-layout" style={styles.layout}>
          <nav className="compare-sidebar" style={styles.sidebar}>
            <div style={styles.sidebarLabel}>Compare by use case</div>
            <div className="compare-nav-list" style={styles.sidebarList}>
              {comparisonPages.map(page => (
                <button
                  key={page.slug}
                  onClick={() => scrollToSection(page.slug)}
                  style={{
                    ...styles.sidebarButton,
                    ...(activeSlug === page.slug ? styles.sidebarButtonActive : {}),
                  }}
                >
                  <span style={styles.sidebarButtonTitle}>{page.title[0]}</span>
                  <span style={styles.sidebarButtonBody}>{page.competitors.map(competitor => competitor.name).join(' · ')}</span>
                </button>
              ))}
            </div>
          </nav>

          <div style={styles.sections}>
            {comparisonPages.map(page => (
              <section key={page.slug} id={page.slug} style={styles.sectionCard}>
                <div style={styles.sectionTop}>
                  <span style={styles.sectionBadge}>{page.badge}</span>
                  <h2 style={styles.sectionTitle}>
                    {page.title[0]}
                    <br />
                    {page.title[1]}
                  </h2>
                  <p style={styles.sectionBody}>{page.description}</p>
                </div>

                {page.competitors.length > 0 ? (
                  <div className="compare-competitor-row" style={styles.competitorLinkRow}>
                    {page.competitors.map(competitor => {
                      const url = competitorLinks[competitor.name];

                      return (
                        <div
                          key={competitor.name}
                          style={styles.competitorLinkCard}
                        >
                          <img
                            src={getFaviconUrl(url)}
                            alt={`${competitor.name} logo`}
                            width={20}
                            height={20}
                            style={styles.competitorIcon}
                          />
                          <span style={styles.competitorLinkName}>{competitor.name}</span>
                        </div>
                      );
                    })}
                  </div>
                ) : null}

                <div style={styles.summaryCard}>
                  <span style={styles.summaryLabel}>Bottom line</span>
                  <p style={styles.summaryBody}>{page.verdict}</p>
                </div>

                {page.landscapeNote ? (
                  <div style={styles.landscapeCard}>
                    <span style={styles.subsectionLabel}>Category context</span>
                    <p style={styles.landscapeBody}>{page.landscapeNote}</p>
                  </div>
                ) : null}

                {page.competitors.length > 0 ? (
                  <div className="compare-competitor-grid" style={styles.competitorGrid}>
                    {page.competitors.map(competitor => (
                      <article key={competitor.name} style={styles.competitorCard}>
                        <h3 style={styles.competitorName}>{competitor.name}</h3>
                        <p style={styles.competitorPositioning}>{competitor.positioning}</p>
                        <div style={styles.competitorPoint}>
                          <PlayIcon size={14} color="#5bbef0" style={{ marginTop: 4 }} />
                          <span>{competitor.strengths}</span>
                        </div>
                        <div style={styles.competitorPoint}>
                          <StopIcon size={14} color="rgba(255,96,128,0.8)" style={{ marginTop: 4 }} />
                          <span>{competitor.gap}</span>
                        </div>
                      </article>
                    ))}
                  </div>
                ) : null}

                <div style={styles.subsection}>
                  <span style={styles.subsectionLabel}>Why people choose TaskTrace</span>
                  <div className="compare-advantage-grid" style={styles.advantageGrid}>
                    {page.taskTraceAdvantages.map(item => (
                      <article key={item.title} style={styles.advantageCard}>
                        <div style={styles.advantageIcon}>
                          <PlayIcon size={15} color="#5bbef0" />
                        </div>
                        <h3 style={styles.advantageTitle}>{item.title}</h3>
                        <p style={styles.advantageBody}>{item.body}</p>
                      </article>
                    ))}
                  </div>
                </div>

                <div className="compare-fit-grid" style={styles.fitGrid}>
                  <div style={styles.fitCard}>
                    <span style={styles.subsectionLabel}>Best fit</span>
                    <h3 style={styles.fitTitle}>Choose TaskTrace if</h3>
                    <ul style={styles.list}>
                      {page.idealFor.map(item => (
                        <li key={item} style={styles.listItem}>
                          <PlayIcon size={14} color="#5bbef0" style={{ marginTop: 4 }} />
                          <span>{item}</span>
                        </li>
                      ))}
                    </ul>
                  </div>
                  <div style={styles.fitCard}>
                    <span style={styles.subsectionLabel}>Not a fit</span>
                    <h3 style={styles.fitTitle}>Skip it if</h3>
                    <ul style={styles.list}>
                      {page.avoidIf.map(item => (
                        <li key={item} style={styles.listItem}>
                          <StopIcon size={14} color="rgba(255,96,128,0.8)" style={{ marginTop: 4 }} />
                          <span>{item}</span>
                        </li>
                      ))}
                    </ul>
                  </div>
                </div>

                <div style={styles.subsection}>
                  <span style={styles.subsectionLabel}>Tradeoffs</span>
                  <div style={styles.tradeoffCard}>
                    <ul style={styles.list}>
                      {page.honestLimits.map(item => (
                        <li key={item} style={styles.listItem}>
                          <StopIcon size={14} color="rgba(255,96,128,0.8)" style={{ marginTop: 4 }} />
                          <span>{item}</span>
                        </li>
                      ))}
                    </ul>
                  </div>
                </div>

                <div style={styles.subsection}>
                  <span style={styles.subsectionLabel}>Common questions</span>
                  <div style={styles.faqList}>
                    {page.faqs.map(faq => (
                      <article key={faq.question} style={styles.faqCard}>
                        <h3 style={styles.faqQuestion}>{faq.question}</h3>
                        <p style={styles.faqAnswer}>{faq.answer}</p>
                      </article>
                    ))}
                  </div>
                </div>
              </section>
            ))}
          </div>
        </div>
      </main>
    </div>
  );
}

const styles: Record<string, React.CSSProperties> = {
  page: {
    position: 'relative',
    minHeight: '100vh',
    background: 'var(--bg-primary)',
    overflowX: 'clip',
  },
  orbA: {
    position: 'absolute',
    top: -120,
    left: 0,
    width: 520,
    height: 520,
    borderRadius: '50%',
    background: 'radial-gradient(circle, rgba(91,190,240,0.12) 0%, transparent 70%)',
    filter: 'blur(54px)',
    pointerEvents: 'none',
  },
  orbB: {
    position: 'absolute',
    top: 160,
    right: -120,
    width: 540,
    height: 540,
    borderRadius: '50%',
    background: 'radial-gradient(circle, rgba(250,163,184,0.07) 0%, transparent 72%)',
    filter: 'blur(56px)',
    pointerEvents: 'none',
  },
  orbC: {
    position: 'absolute',
    bottom: 120,
    left: '10%',
    width: 420,
    height: 420,
    borderRadius: '50%',
    background: 'radial-gradient(circle, rgba(168,120,245,0.08) 0%, transparent 70%)',
    filter: 'blur(48px)',
    pointerEvents: 'none',
  },
  header: {
    position: 'sticky',
    top: 0,
    zIndex: 20,
    background: 'rgba(11, 13, 17, 0.72)',
    backdropFilter: 'blur(20px) saturate(150%)',
    WebkitBackdropFilter: 'blur(20px) saturate(150%)',
    borderBottom: '1px solid rgba(255,255,255,0.06)',
  },
  headerInner: {
    maxWidth: 1180,
    margin: '0 auto',
    padding: '16px 24px',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 24,
  },
  logo: {
    display: 'inline-flex',
    alignItems: 'center',
    gap: 10,
    color: '#f9f9f7',
    fontWeight: 700,
    letterSpacing: '-0.02em',
  },
  headerLinks: {
    display: 'flex',
    alignItems: 'center',
    gap: 18,
  },
  headerLink: {
    color: 'rgba(249,249,247,0.72)',
    fontSize: 14,
  },
  downloadButton: {
    padding: '9px 18px',
    borderRadius: 999,
    background: '#5bbef0',
    color: '#0b0d11',
    fontSize: 13,
    fontWeight: 700,
  },
  main: {
    position: 'relative',
    zIndex: 1,
    maxWidth: 1180,
    margin: '0 auto',
    padding: '28px 24px 120px',
  },
  layout: {
    display: 'flex',
    gap: 64,
    alignItems: 'start',
  },
  sidebar: {
    width: 220,
    flexShrink: 0,
    position: 'sticky',
    top: 80,
    paddingTop: 40,
    paddingBottom: 40,
    display: 'flex',
    flexDirection: 'column',
    gap: 2,
  },
  sidebarLabel: {
    fontSize: 11,
    fontWeight: 600,
    letterSpacing: '0.08em',
    textTransform: 'uppercase',
    color: 'rgba(249,249,247,0.4)',
    marginBottom: 12,
    marginTop: 4,
  },
  sidebarList: {
    display: 'flex',
    flexDirection: 'column',
    gap: 2,
  },
  sidebarButton: {
    display: 'block',
    width: '100%',
    textAlign: 'left',
    padding: '8px 10px',
    fontSize: 14,
    fontWeight: 400,
    color: 'rgba(249,249,247,0.5)',
    background: 'transparent',
    border: 'none',
    borderRadius: 6,
    cursor: 'pointer',
    transition: 'color 0.15s ease, background 0.15s ease',
  },
  sidebarButtonActive: {
    color: '#f9f9f7',
    fontWeight: 500,
    background: 'rgba(255,255,255,0.08)',
  },
  sidebarButtonTitle: {
    display: 'block',
    fontSize: 14,
    lineHeight: 1.35,
  },
  sidebarButtonBody: {
    display: 'block',
    fontSize: 12,
    color: 'rgba(249,249,247,0.52)',
    lineHeight: 1.4,
    marginTop: 2,
  },
  sections: {
    display: 'flex',
    flexDirection: 'column',
    gap: 56,
    flex: 1,
    minWidth: 0,
  },
  sectionCard: {
    padding: '0 0 28px',
    scrollMarginTop: 92,
    borderBottom: '1px solid rgba(255,255,255,0.06)',
  },
  sectionTop: {
    marginBottom: 22,
  },
  sectionBadge: {
    display: 'inline-block',
    color: '#78c7f5',
    fontSize: 12,
    fontWeight: 700,
    letterSpacing: '0.08em',
    textTransform: 'uppercase',
    marginBottom: 14,
  },
  sectionTitle: {
    color: '#f9f9f7',
    fontSize: 'clamp(28px, 4vw, 46px)',
    lineHeight: 1.04,
    letterSpacing: '-0.04em',
    marginBottom: 14,
  },
  sectionBody: {
    color: 'rgba(249,249,247,0.62)',
    fontSize: 17,
    lineHeight: 1.75,
    maxWidth: 760,
  },
  competitorLinkRow: {
    display: 'flex',
    gap: 12,
    flexWrap: 'wrap',
    marginBottom: 20,
  },
  competitorLinkCard: {
    display: 'inline-flex',
    alignItems: 'center',
    gap: 10,
    padding: '10px 14px',
    borderRadius: 999,
    background: 'rgba(255,255,255,0.025)',
    border: '1px solid rgba(255,255,255,0.08)',
    color: '#f9f9f7',
  },
  competitorIcon: {
    width: 20,
    height: 20,
    borderRadius: 999,
    flexShrink: 0,
  },
  competitorLinkName: {
    fontSize: 14,
    fontWeight: 700,
  },
  competitorLinkCta: {
    fontSize: 12,
    color: 'rgba(249,249,247,0.48)',
  },
  summaryCard: {
    padding: '22px 24px',
    borderRadius: 20,
    background: 'rgba(91,190,240,0.04)',
    border: '1px solid rgba(91,190,240,0.1)',
    marginBottom: 22,
  },
  summaryLabel: {
    display: 'inline-block',
    color: '#78c7f5',
    fontSize: 12,
    fontWeight: 700,
    letterSpacing: '0.08em',
    textTransform: 'uppercase',
    marginBottom: 10,
  },
  summaryBody: {
    color: '#f9f9f7',
    fontSize: 20,
    lineHeight: 1.6,
    letterSpacing: '-0.02em',
    maxWidth: 920,
  },
  landscapeCard: {
    padding: '20px 22px',
    borderRadius: 18,
    background: 'rgba(255,255,255,0.015)',
    border: '1px solid rgba(255,255,255,0.05)',
    marginBottom: 22,
  },
  landscapeBody: {
    color: 'rgba(249,249,247,0.62)',
    fontSize: 15,
    lineHeight: 1.72,
  },
  competitorGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(2, minmax(0, 1fr))',
    gap: 16,
    marginBottom: 28,
  },
  competitorCard: {
    padding: '22px 0',
    borderRadius: 0,
    background: 'transparent',
    border: 'none',
    borderBottom: '1px solid rgba(255,255,255,0.06)',
  },
  competitorName: {
    color: '#f9f9f7',
    fontSize: 22,
    lineHeight: 1.1,
    letterSpacing: '-0.03em',
    marginBottom: 10,
  },
  competitorPositioning: {
    color: 'rgba(249,249,247,0.58)',
    fontSize: 14.5,
    lineHeight: 1.7,
    marginBottom: 14,
  },
  competitorPoint: {
    display: 'flex',
    alignItems: 'flex-start',
    gap: 9,
    color: 'rgba(249,249,247,0.72)',
    fontSize: 14.5,
    lineHeight: 1.7,
    marginBottom: 10,
  },
  subsection: {
    marginBottom: 28,
  },
  subsectionLabel: {
    display: 'inline-block',
    color: '#78c7f5',
    fontSize: 12,
    fontWeight: 700,
    letterSpacing: '0.08em',
    textTransform: 'uppercase',
    marginBottom: 12,
  },
  advantageGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(3, minmax(0, 1fr))',
    gap: 16,
  },
  advantageCard: {
    padding: '0',
    borderRadius: 0,
    background: 'transparent',
    border: 'none',
  },
  advantageIcon: {
    width: 34,
    height: 34,
    borderRadius: 10,
    background: 'rgba(91,190,240,0.09)',
    border: '1px solid rgba(91,190,240,0.14)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: 14,
  },
  advantageTitle: {
    color: '#f9f9f7',
    fontSize: 18,
    lineHeight: 1.25,
    letterSpacing: '-0.02em',
    marginBottom: 8,
  },
  advantageBody: {
    color: 'rgba(249,249,247,0.6)',
    fontSize: 14.5,
    lineHeight: 1.7,
  },
  fitGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(2, minmax(0, 1fr))',
    gap: 16,
    marginBottom: 28,
  },
  fitCard: {
    padding: '0',
    borderRadius: 0,
    background: 'transparent',
    border: 'none',
  },
  fitTitle: {
    color: '#f9f9f7',
    fontSize: 24,
    lineHeight: 1.1,
    letterSpacing: '-0.03em',
    marginBottom: 14,
  },
  tradeoffCard: {
    padding: '0',
    borderRadius: 0,
    background: 'transparent',
    border: 'none',
  },
  list: {
    listStyle: 'none',
    display: 'flex',
    flexDirection: 'column',
    gap: 12,
  },
  listItem: {
    display: 'flex',
    alignItems: 'flex-start',
    gap: 10,
    color: 'rgba(249,249,247,0.72)',
    fontSize: 14.5,
    lineHeight: 1.72,
  },
  faqList: {
    display: 'grid',
    gap: 12,
  },
  faqCard: {
    padding: '18px 0',
    borderRadius: 0,
    background: 'transparent',
    border: 'none',
    borderBottom: '1px solid rgba(255,255,255,0.06)',
  },
  faqQuestion: {
    color: '#f9f9f7',
    fontSize: 18,
    lineHeight: 1.25,
    letterSpacing: '-0.02em',
    marginBottom: 8,
  },
  faqAnswer: {
    color: 'rgba(249,249,247,0.6)',
    fontSize: 14.5,
    lineHeight: 1.7,
  },
};
