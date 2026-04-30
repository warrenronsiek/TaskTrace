import React, { useEffect } from 'react';
import { Link } from 'react-router-dom';
import { useUseCasePath } from '../useCase';

export default function TermsPage() {
  const homePath = useUseCasePath('/');
  const privacyPath = useUseCasePath('/privacy');
  const licensePath = useUseCasePath('/license');

  useEffect(() => {
    document.title = 'TaskTrace | Terms of Service';
    document.querySelector('meta[name="description"]')?.setAttribute('content', 'Terms of Service for TaskTrace, the AI-powered work tracking app for macOS.');
    document.querySelector('meta[property="og:title"]')?.setAttribute('content', 'TaskTrace | Terms of Service');
    document.querySelector('meta[property="og:description"]')?.setAttribute('content', 'Terms of Service for TaskTrace, the AI-powered work tracking app for macOS.');
    document.querySelector('meta[property="og:url"]')?.setAttribute('content', 'https://www.tasktrace.com/terms');
    document.querySelector('meta[name="twitter:title"]')?.setAttribute('content', 'TaskTrace | Terms of Service');
    document.querySelector('meta[name="twitter:description"]')?.setAttribute('content', 'Terms of Service for TaskTrace, the AI-powered work tracking app for macOS.');
    document.querySelector('meta[name="twitter:url"]')?.setAttribute('content', 'https://www.tasktrace.com/terms');
    document.querySelector('link[rel="canonical"]')?.setAttribute('href', 'https://www.tasktrace.com/terms');
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
          <h1 style={styles.h1}>Terms of Service</h1>
          <p style={styles.lastUpdated}>Last updated: April 2026</p>

          <Section title="Acceptance of terms">
            By downloading, installing, or using TaskTrace ("the App"), you agree to be bound by
            these Terms of Service. If you do not agree, do not use the App.
          </Section>

          <Section title="Description of service">
            TaskTrace is a macOS application that records screen activity, keystrokes, and microphone
            audio to help you track and understand how you spend your working time. The App processes
            data locally on your device using on-device AI models and stores all recordings in a local
            database.
          </Section>

          <Section title="License">
            TaskTrace source code is made available under the{' '}
            <Link to={licensePath} style={styles.inlineLink}>
              MIT License
            </Link>
            . These terms cover use of the TaskTrace website, downloads, hosted documentation, and
            official distribution channels. They do not restrict the rights granted by the open-source
            license for the code itself.
          </Section>

          <Section title="Your responsibilities">
            You are responsible for ensuring that your use of the App complies with all applicable
            laws and regulations in your jurisdiction. This includes but is not limited to:
            <ul style={styles.list}>
              <li>Obtaining consent from others before recording conversations or shared screens where required by law</li>
              <li>Complying with workplace recording policies if using the App in an employment context</li>
              <li>Safeguarding access to the data stored on your device</li>
            </ul>
          </Section>

          <Section title="Privacy and data">
            Your use of the App is also governed by our{' '}
            <Link to={privacyPath} style={styles.inlineLink}>
              Privacy Policy
            </Link>
            . All recording data remains on your device. The App does not collect product
            telemetry, usage analytics, crash reports, advertising identifiers, or behavioral
            event tracking.
          </Section>

          <Section title="Intellectual property">
            The TaskTrace code is licensed under the MIT License. The TaskTrace name, logos, website
            copy, and branding remain TaskTrace marks and are not granted by the MIT License.
          </Section>

          <Section title="Disclaimer of warranties">
            The App is provided "as is" and "as available" without warranties of any kind, whether
            express or implied. We do not warrant that the App will be uninterrupted, error-free,
            or that any defects will be corrected. You use the App at your own risk.
          </Section>

          <Section title="Limitation of liability">
            To the maximum extent permitted by law, TaskTrace and its officers, directors, and
            employees shall not be liable for any indirect, incidental, special, consequential, or
            punitive damages arising out of your use of or inability to use the App.
          </Section>

          <Section title="Termination">
            We may suspend access to hosted services or official distribution channels if these terms
            are violated. The MIT License continues to govern your rights in copies of the source code
            you have already received.
          </Section>

          <Section title="Changes to these terms">
            We may update these terms as the App evolves. Significant changes will be noted in the
            App's release notes. Continued use of the App after changes constitutes acceptance of
            the updated terms.
          </Section>

          <Section title="Governing law">
            These terms are governed by and construed in accordance with the laws of the State of
            Florida, without regard to its conflict of law principles.
          </Section>

          <Section title="Contact">
            Questions about these terms? Reach us at{' '}
            <a href="mailto:warren@tasktrace.com" style={styles.inlineLink}>
              warren@tasktrace.com
            </a>.
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
  inlineLink: {
    color: '#5bbef0',
    textDecoration: 'underline',
  },
};
