import React, { useEffect } from 'react';
import { Link } from 'react-router-dom';
import { useUseCasePath } from '../useCase';

export default function PrivacyPage() {
  const homePath = useUseCasePath('/');

  useEffect(() => {
    document.title = 'TaskTrace | Privacy Policy';
    document.querySelector('meta[name="description"]')?.setAttribute('content', 'Read how TaskTrace stores recordings locally on your Mac and keeps your work history private. The TaskTrace app does not collect telemetry.');
    document.querySelector('meta[property="og:title"]')?.setAttribute('content', 'TaskTrace | Privacy Policy');
    document.querySelector('meta[property="og:description"]')?.setAttribute('content', 'Read how TaskTrace stores recordings locally on your Mac and keeps your work history private. The TaskTrace app does not collect telemetry.');
    document.querySelector('meta[property="og:url"]')?.setAttribute('content', 'https://www.tasktrace.com/privacy');
    document.querySelector('meta[name="twitter:title"]')?.setAttribute('content', 'TaskTrace | Privacy Policy');
    document.querySelector('meta[name="twitter:description"]')?.setAttribute('content', 'Read how TaskTrace stores recordings locally on your Mac and keeps your work history private. The TaskTrace app does not collect telemetry.');
    document.querySelector('meta[name="twitter:url"]')?.setAttribute('content', 'https://www.tasktrace.com/privacy');
    document.querySelector('link[rel="canonical"]')?.setAttribute('href', 'https://www.tasktrace.com/privacy');
  }, []);

  return (
    <>
      <header style={styles.header}>
        <div style={styles.headerInner}>
          <Link to={homePath} style={styles.logo}>
            <img src="/tasktrace-logo.svg" alt="TaskTrace logo" width={22} height={22} />
            TaskTrace
          </Link>
        </div>
      </header>
      <main style={styles.main}>
        <article style={styles.article}>
          <h1 style={styles.h1}>Privacy Policy</h1>
          <p style={styles.lastUpdated}>Last updated: March 2026</p>

          <Section title="Overview">
            TaskTrace is a macOS application that records your screen activity and keystrokes to help
            you understand and report on how you spend your working time. We take your privacy seriously.
            This policy explains what data we collect, how we use it, and what stays on your device.
          </Section>

          <Section title="Data stored on your device">
            All recordings made by TaskTrace are stored exclusively on your Mac in a local SQLite
            database. This includes:
            <ul style={styles.list}>
              <li>Screenshots taken during recording sessions</li>
              <li>Keystroke logs from your active applications</li>
              <li>Microphone transcripts</li>
              <li>AI-generated activity summaries and overviews</li>
              <li>Tags and session metadata</li>
            </ul>
            None of this data is transmitted to TaskTrace servers or any third-party service.
          </Section>

          <Section title="App telemetry">
            The TaskTrace macOS app does not collect product telemetry, usage analytics, crash
            reports, advertising identifiers, or behavioral event tracking. The app does not phone
            home to TaskTrace servers. This website may use standard marketing analytics and
            conversion measurement, but that website activity is separate from your local app
            recordings.
          </Section>

          <Section title="AI processing">
            TaskTrace uses on-device AI models (via Apple's MLX framework) to summarize activities
            and generate overviews. Your work content is processed entirely on your Mac and is never
            sent to a remote AI service or API.
          </Section>

          <Section title="MCP server">
            TaskTrace runs a local MCP (Model Context Protocol) server on your machine that allows
            AI assistants you have installed (such as Claude Desktop or Cursor) to query your work
            history. This communication is entirely local. It does not involve TaskTrace's servers.
            You can disable the MCP server in Settings at any time.
          </Section>

          <Section title="Data retention and deletion">
            Your data is yours. You can delete individual sessions or your entire history at any
            time from within the app. Uninstalling TaskTrace removes the app, but your database file
            remains in your Application Support folder. You can delete it manually to remove all data.
          </Section>

          <Section title="Changes to this policy">
            We may update this policy as the app evolves. Significant changes will be noted in the
            app's release notes. Continued use of the app after changes constitutes acceptance of
            the updated policy.
          </Section>

          <Section title="Contact">
            Questions about this policy? Reach us at{' '}
            <a href="mailto:privacy@tasktrace.com" style={styles.emailLink}>
              privacy@tasktrace.com
            </a>.
            {' '}I'd also love to hear feature requests.
          </Section>
        </article>
      </main>
    </>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section style={sectionStyles.section}>
      <h2 style={sectionStyles.h2}>{title}</h2>
      <div style={sectionStyles.content}>{children}</div>
    </section>
  );
}

const sectionStyles: Record<string, React.CSSProperties> = {
  section: {
    marginBottom: 40,
  },
  h2: {
    fontSize: 20,
    fontWeight: 700,
    color: 'var(--text-primary)',
    letterSpacing: '-0.02em',
    marginBottom: 12,
  },
  content: {
    fontSize: 15.5,
    color: 'var(--text-secondary)',
    lineHeight: 1.7,
  },
};

const styles: Record<string, React.CSSProperties> = {
  header: {
    borderBottom: '1px solid rgba(255,255,255,0.06)',
    height: 60,
    display: 'flex',
    alignItems: 'center',
    background: 'var(--bg-primary)',
  },
  headerInner: {
    maxWidth: 1100,
    margin: '0 auto',
    padding: '0 24px',
    width: '100%',
  },
  logo: {
    fontSize: 17,
    fontWeight: 700,
    color: '#f9f9f7',
    letterSpacing: '-0.02em',
    textDecoration: 'none',
    display: 'inline-flex',
    alignItems: 'center',
    gap: 7,
  },
  main: {
    padding: '64px 24px 120px',
  },
  article: {
    maxWidth: 680,
    margin: '0 auto',
  },
  h1: {
    fontSize: 38,
    fontWeight: 800,
    color: 'var(--text-primary)',
    letterSpacing: '-0.04em',
    marginBottom: 8,
  },
  lastUpdated: {
    fontSize: 13,
    color: 'var(--text-muted)',
    marginBottom: 48,
  },
  list: {
    paddingLeft: 20,
    marginTop: 10,
    marginBottom: 10,
    lineHeight: 1.8,
  },
  emailLink: {
    color: '#5bbef0',
    textDecoration: 'underline',
  },
};
