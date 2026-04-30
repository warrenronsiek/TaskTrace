import React, { useEffect } from 'react';
import { Link } from 'react-router-dom';
import { useUseCasePath } from '../useCase';
import { TASKTRACE_GITHUB_REPO_URL } from '../vars';

export default function LicensePage() {
  const homePath = useUseCasePath('/');

  useEffect(() => {
    document.title = 'TaskTrace | Open Source License';
    document.querySelector('meta[name="description"]')?.setAttribute('content', 'TaskTrace is open source under the MIT License.');
    document.querySelector('meta[property="og:title"]')?.setAttribute('content', 'TaskTrace | Open Source License');
    document.querySelector('meta[property="og:description"]')?.setAttribute('content', 'TaskTrace is open source under the MIT License.');
    document.querySelector('meta[property="og:url"]')?.setAttribute('content', 'https://www.tasktrace.com/license');
    document.querySelector('meta[name="twitter:title"]')?.setAttribute('content', 'TaskTrace | Open Source License');
    document.querySelector('meta[name="twitter:description"]')?.setAttribute('content', 'TaskTrace is open source under the MIT License.');
    document.querySelector('meta[name="twitter:url"]')?.setAttribute('content', 'https://www.tasktrace.com/license');
    document.querySelector('link[rel="canonical"]')?.setAttribute('href', 'https://www.tasktrace.com/license');
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
          <h1 style={styles.h1}>Open Source License</h1>
          <p style={styles.lastUpdated}>TaskTrace is released under the MIT License.</p>

          <Section title="What this covers">
            The TaskTrace source code and associated documentation in the public repository are
            licensed under the MIT License. You may use, copy, modify, merge, publish, distribute,
            sublicense, and sell copies of the software under the license terms.
          </Section>

          <Section title="Repository">
            The source code and full license text are available on{' '}
            <a href={TASKTRACE_GITHUB_REPO_URL} target="_blank" rel="noopener noreferrer" style={styles.inlineLink}>
              GitHub
            </a>
            .
          </Section>

          <Section title="License text">
            <pre style={styles.licenseText}>{licenseText}</pre>
          </Section>

          <Section title="Branding">
            The MIT License covers the code. The TaskTrace name, logos, website copy, and other
            brand assets remain TaskTrace marks and are not granted by the source-code license.
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

const licenseText = `MIT License

Copyright (c) 2026 TaskTrace contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.`;

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
    maxWidth: 720,
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
  inlineLink: {
    color: '#5bbef0',
    textDecoration: 'underline',
  },
  licenseText: {
    whiteSpace: 'pre-wrap',
    overflowWrap: 'anywhere',
    background: 'rgba(255,255,255,0.04)',
    border: '1px solid rgba(255,255,255,0.08)',
    borderRadius: 8,
    padding: 18,
    color: 'rgba(249,249,247,0.76)',
    fontSize: 13,
    lineHeight: 1.6,
  },
};
