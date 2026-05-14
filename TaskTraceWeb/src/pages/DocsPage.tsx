import React, { useEffect, useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { useUseCasePath } from '../useCase';

const GITHUB_REPO = 'https://github.com/warrenronsiek/TaskTrace/tree/master/TaskTraceMCPPlugin';

const sections = [
  { id: 'overview', label: 'Overview' },
  { id: 'resources', label: 'Resources' },
  { id: 'tools', label: 'Tools' },
  { id: 'skills', label: 'Plugin Skills' },
  { id: 'installation', label: 'Installation' },
  { id: 'configuration', label: 'Configuration' },
];

export default function DocsPage() {
  const [activeId, setActiveId] = useState('overview');
  const observerRef = useRef<IntersectionObserver | null>(null);
  const homePath = useUseCasePath('/');

  useEffect(() => {
    document.title = 'TaskTrace | MCP Server Docs';
    document.querySelector('meta[name="description"]')?.setAttribute('content', 'Documentation for the local TaskTrace MCP server, including resources, activity search, graph search, installation, and configuration.');
    document.querySelector('meta[property="og:title"]')?.setAttribute('content', 'TaskTrace | MCP Server Docs');
    document.querySelector('meta[property="og:description"]')?.setAttribute('content', 'Documentation for the local TaskTrace MCP server, including resources, activity search, graph search, installation, and configuration.');
    document.querySelector('meta[property="og:url"]')?.setAttribute('content', 'https://tasktrace.com/docs');
    document.querySelector('meta[name="twitter:title"]')?.setAttribute('content', 'TaskTrace | MCP Server Docs');
    document.querySelector('meta[name="twitter:description"]')?.setAttribute('content', 'Documentation for the local TaskTrace MCP server, including resources, activity search, graph search, installation, and configuration.');
    document.querySelector('meta[name="twitter:url"]')?.setAttribute('content', 'https://tasktrace.com/docs');
    document.querySelector('link[rel="canonical"]')?.setAttribute('href', 'https://tasktrace.com/docs');
  }, []);

  useEffect(() => {
    const headings = sections.map(s => document.getElementById(s.id)).filter(Boolean) as HTMLElement[];

    observerRef.current = new IntersectionObserver(
      entries => {
        const visible = entries.filter(e => e.isIntersecting);
        if (visible.length > 0) {
          setActiveId(visible[0].target.id);
        }
      },
      { rootMargin: '-20% 0px -70% 0px', threshold: 0 }
    );

    headings.forEach(el => observerRef.current!.observe(el));
    return () => observerRef.current?.disconnect();
  }, []);

  const scrollTo = (id: string) => {
    document.getElementById(id)?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  };

  return (
    <div style={styles.page}>
      <header style={styles.header}>
        <div style={styles.headerInner}>
          <Link to={homePath} style={styles.logo}>
            <img src="/tasktrace-logo.svg" alt="TaskTrace logo" width={22} height={22} />
            TaskTrace
          </Link>
          <span style={styles.headerLabel}>Docs</span>
        </div>
      </header>

      <div style={styles.layout}>
        <nav style={styles.sidebar}>
          <p style={styles.sidebarGroup}>MCP Server</p>
          {sections.map(s => (
            <button
              key={s.id}
              style={{
                ...styles.navItem,
                ...(activeId === s.id ? styles.navItemActive : {}),
              }}
              onClick={() => scrollTo(s.id)}
            >
              {s.label}
            </button>
          ))}
          <div style={styles.sidebarDivider} />
          <a href={GITHUB_REPO} target="_blank" rel="noopener noreferrer" style={styles.githubLink}>
            <GitHubIcon />
            GitHub repo
          </a>
        </nav>

        <main style={styles.content}>
          {/* Overview */}
          <section style={styles.section}>
            <h1 id="overview" style={styles.h1}>MCP Server</h1>
            <p style={styles.lead}>
              TaskTrace exposes a local{' '}
              <a href="https://modelcontextprotocol.io" target="_blank" rel="noopener noreferrer" style={styles.link}>
                Model Context Protocol
              </a>{' '}
              (MCP) server that lets AI coding assistants — Claude Code, Cursor, OpenClaw, and any
              MCP-compatible client — read your work history directly from the desktop app and run
              ranked retrieval over both recorded activity and your persisted knowledge graph.
            </p>
            <p style={styles.body}>
              The server runs entirely on your machine. No data leaves your device. Enable or disable
              it at any time in the TaskTrace app under <strong>Preferences &rarr; MCP</strong>.
            </p>
            <p style={styles.body}>
              The plugin package is open source and available on{' '}
              <a href={GITHUB_REPO} target="_blank" rel="noopener noreferrer" style={styles.link}>
                GitHub
              </a>.
            </p>
          </section>

          {/* Resources */}
          <section style={styles.section}>
            <h2 id="resources" style={styles.h2}>Resources</h2>
            <p style={styles.body}>
              TaskTrace exposes MCP resources that agents can read. Use the{' '}
              <code style={styles.code}>resources/list</code> MCP method to discover which resources
              and screenshot templates are currently enabled.
            </p>

            <ResourceCard
              uri="tasktrace://overviews/active-day"
              description="JSON document containing the current TaskTrace overview titles, summaries, and durations for the active day. Enabled by default."
            />
            <ResourceCard
              uri="tasktrace://activities/high-level"
              description="JSON document containing recent completed activities with top-level summaries only. This feed lags behind capture because activities only appear here after summarization finishes. Enabled by default."
            />
            <ResourceCard
              uri="tasktrace://activities/detailed"
              description="JSON document containing the eager recent-activity feed, including incomplete activities, keystrokes, transcript text, summary when available, and screenshot metadata (description and OCR) when present. Screenshot bytes are fetched separately via the screenshot URI template. Disabled by default — enable in Settings."
            />
            <ResourceCard
              uri="tasktrace://activity/{activityId}/screenshot/{screenshotId}"
              description="Binary WebP screenshot bytes for a specific screenshot. URIs for each screenshot are embedded in the detailed activity feed. Only available when the detailed activity resource is enabled."
              isTemplate
            />

            <p style={{ ...styles.body, marginTop: 16 }}>
              Start with <code style={styles.code}>tasktrace://overviews/active-day</code> for a
              quick summary, use <code style={styles.code}>tasktrace://activities/high-level</code>{' '}
              for a summarized activity list, and reach for{' '}
              <code style={styles.code}>tasktrace://activities/detailed</code> when you need
              keystrokes, OCR, transcripts, or screenshots.
            </p>
          </section>

          {/* Tools */}
          <section style={styles.section}>
            <h2 id="tools" style={styles.h2}>Tools</h2>
            <p style={styles.body}>
              TaskTrace exposes two native retrieval tools: <code style={styles.code}>tasktrace_search</code>{' '}
              for activity history and <code style={styles.code}>tasktrace_graph_search</code> for
              the currently selected knowledge directory.
            </p>
            <ToolCard
              name="tasktrace_search"
              params={[
                { name: 'query', type: 'string', description: 'Natural-language query to search over overviews, activity summaries, and screenshot descriptions.' },
                { name: 'limit', type: 'number', description: 'Optional maximum number of overview result trees to return. Defaults to 10 and is clamped to 50.' },
              ]}
              description="Exposes activity search over TaskTrace data and returns ranked relevant descriptions of matching overviews, activities, and screenshots without generating a natural-language summary."
            />
            <ToolCard
              name="tasktrace_graph_search"
              params={[
                { name: 'query', type: 'string', description: 'Natural-language question or graph lookup query over persisted knowledge communities, concepts, claims, and relationships.' },
                { name: 'limit', type: 'number', description: 'Optional maximum number of reranked graph hits to keep. Defaults to 3 and is clamped to 10.' },
              ]}
              description="Exposes graph search over persisted knowledge communities, concepts, claims, and relationships for the knowledge directory currently selected in TaskTrace. It returns ranked graph evidence without generating a summary."
            />
            <p style={styles.body}>
              <code style={styles.code}>tasktrace_search</code> returns JSON containing the
              submitted query, resolved limit, ranked results, and per-node reranking scores. Each
              ranked result contains a score and the full overview tree, including matched
              activities and screenshots.
            </p>
            <CodeBlock code={`{
  "name": "tasktrace_search",
  "arguments": {
    "query": "invoice reconciliation",
    "limit": 5
  }
}`} />
            <p style={styles.body}>
              <code style={styles.code}>tasktrace_graph_search</code> returns structured graph
              evidence for the currently selected knowledge directory in the desktop app. Clients do
              not pass a directory identifier; TaskTrace uses the active selection.
            </p>
            <CodeBlock code={`{
  "name": "tasktrace_graph_search",
  "arguments": {
    "query": "what do we know about billing retries?",
    "limit": 3
  }
}`} />
            <p style={styles.body}>
              Standard MCP clients call resources through <code style={styles.code}>resources/list</code>{' '}
              and <code style={styles.code}>resources/read</code>, then call{' '}
              <code style={styles.code}>tasktrace_search</code> for historical activity retrieval or{' '}
              <code style={styles.code}>tasktrace_graph_search</code> for knowledge-graph retrieval
              instead of browsing the feeds directly.
            </p>
            <p style={styles.body}>
              If you install the OpenClaw plugin, OpenClaw exposes both native retrieval tools and
              resource-backed wrapper tools for listing and reading TaskTrace feeds from its tool
              catalog.
            </p>
          </section>

          {/* Skills */}
          <section style={styles.section}>
            <h2 id="skills" style={styles.h2}>Plugin Skills</h2>
            <p style={styles.body}>
              The Claude Code plugin bundles three skills that teach Claude when to use TaskTrace
              instead of treating the MCP server as an anonymous tool list.
            </p>
            <ToolCard
              name="tasktrace-context"
              params={[]}
              description="Auto-triggers on questions about your own work history, current activity, or picking up an in-progress task. It routes today's questions to resources and historical questions to tasktrace_search."
            />
            <ToolCard
              name="tasktrace-knowledge"
              params={[]}
              description="Auto-triggers on questions about what you know, have read, or have in your notes. It routes those questions to tasktrace_graph_search."
            />
            <ToolCard
              name="tasktrace-setup"
              params={[]}
              description="Run /tasktrace-mcp:setup in Claude Code to check the local install, confirm TaskTrace.app is available, verify the MCP server, and walk through missing permissions or plugin setup."
            />
          </section>

          {/* Installation */}
          <section style={styles.section}>
            <h2 id="installation" style={styles.h2}>Installation</h2>

            <p style={styles.body}>
              Install TaskTrace from the signed DMG by dragging <code style={styles.codeInline}>TaskTrace.app</code>{' '}
              into <code style={styles.codeInline}>/Applications</code> before registering the MCP
              server. The command examples below assume the default installed binary path at{' '}
              <code style={styles.codeInline}>/Applications/TaskTrace.app/Contents/MacOS/TaskTrace</code>.
              If you keep the app somewhere else, replace that path in the examples.
            </p>

            <h3 style={styles.h3}>Claude Code</h3>
            <p style={styles.body}>
              Clone the repo, then add the in-repo plugin directory as a local Claude Code marketplace:
            </p>
            <CodeBlock code={`git clone https://github.com/warrenronsiek/TaskTrace.git
cd TaskTrace/TaskTraceMCPPlugin`} />
            <p style={styles.body}>
              Inside Claude Code, install the plugin from that local marketplace:
            </p>
            <CodeBlock code={`/plugin marketplace add .
/plugin install tasktrace-mcp@tasktrace-mcp
/reload-plugins
/mcp`} />
            <p style={styles.body}>
              You should
              see <code style={styles.codeInline}>tasktrace</code> listed. If setup fails, run{' '}
              <code style={styles.codeInline}>/tasktrace-mcp:setup</code> for a local install check.
            </p>
            <p style={styles.body}>
              Or register the MCP server directly without the plugin:
            </p>
            <CodeBlock code={`claude mcp add --transport stdio --scope user tasktrace -- \\
  /Applications/TaskTrace.app/Contents/MacOS/TaskTrace --mcp-stdio`} />

            <h3 style={styles.h3}>Codex</h3>
            <p style={styles.body}>
              Stage and install from the plugin directory in a TaskTrace checkout, then restart Codex and
              install <code style={styles.codeInline}>tasktrace-mcp</code> from the local marketplace:
            </p>
            <CodeBlock code={`git clone https://github.com/warrenronsiek/TaskTrace.git
cd TaskTrace/TaskTraceMCPPlugin
npm install
npm run install:codex-local`} />

            <h3 style={styles.h3}>OpenClaw</h3>
            <p style={styles.body}>
              Clone TaskTrace locally, install the native TaskTrace MCP plugin from the in-repo
              plugin directory, register
              the TaskTrace stdio MCP server, clear stale upgrade-era allowlists, restart
              the gateway, then inspect the MCP registration:
            </p>
            <CodeBlock code={`git clone https://github.com/warrenronsiek/TaskTrace.git
cd TaskTrace/TaskTraceMCPPlugin
openclaw plugins install .
openclaw mcp set tasktrace '{"command":"/Applications/TaskTrace.app/Contents/MacOS/TaskTrace","args":["--mcp-stdio"]}'
openclaw config unset tools.allow
openclaw gateway restart
openclaw plugins inspect tasktrace-mcp`} />
            <p style={styles.body}>
              OpenClaw can call TaskTrace tools over MCP, including{' '}
              <code style={styles.codeInline}>tasktrace_push_message</code> for sending a macOS
              notification through the running TaskTrace app.
            </p>

            <h3 style={styles.h3}>Generic <code style={styles.codeInline}>.mcp.json</code></h3>
            <p style={styles.body}>
              Any MCP-compatible client that supports project-scoped server config files can use the
              standard <code style={styles.codeInline}>mcpServers</code> format:
            </p>
            <CodeBlock code={`{
  "mcpServers": {
    "tasktrace": {
      "command": "/Applications/TaskTrace.app/Contents/MacOS/TaskTrace",
      "args": ["--mcp-stdio"]
    }
  }
}`} />
            <p style={styles.body}>
              Save this as <code style={styles.codeInline}>.mcp.json</code> in your project root, or
              copy it from the{' '}
              <a href={GITHUB_REPO} target="_blank" rel="noopener noreferrer" style={styles.link}>
                in-repo plugin directory
              </a>.
            </p>
          </section>

          {/* Configuration */}
          <section style={{ ...styles.section, paddingBottom: 120 }}>
            <h2 id="configuration" style={styles.h2}>Configuration</h2>
            <p style={styles.body}>
              The plugin's reusable MCP config lives in <code style={styles.codeInline}>.mcp.json</code>.
              For Claude Code and generic MCP clients, the only required launch contract is the
              TaskTrace binary plus <code style={styles.codeInline}>--mcp-stdio</code>.
            </p>
            <CodeBlock code={`{
  "mcpServers": {
    "tasktrace": {
      "command": "/Applications/TaskTrace.app/Contents/MacOS/TaskTrace",
      "args": ["--mcp-stdio"]
    }
  }
}`} />
            <p style={styles.body}>
              OpenClaw exposes these resource-backed tools on top of the registered TaskTrace MCP
              server: <code style={styles.codeInline}>tasktrace_list_resources</code>,{' '}
              <code style={styles.codeInline}>tasktrace_list_resource_templates</code>,{' '}
              <code style={styles.codeInline}>tasktrace_get_active_day_overviews</code>,{' '}
              <code style={styles.codeInline}>tasktrace_get_high_level_activities</code>,{' '}
              <code style={styles.codeInline}>tasktrace_get_detailed_activities</code>, and{' '}
              <code style={styles.codeInline}>tasktrace_read_resource</code>, plus write tools like{' '}
              <code style={styles.codeInline}>tasktrace_add_todo</code>,{' '}
              <code style={styles.codeInline}>tasktrace_add_goal</code>, and{' '}
              <code style={styles.codeInline}>tasktrace_push_message</code>.
            </p>
          </section>
        </main>
      </div>
    </div>
  );
}

function ResourceCard({ uri, description, isTemplate }: { uri: string; description: string; isTemplate?: boolean }) {
  return (
    <div style={cardStyles.card}>
      <div style={cardStyles.uriRow}>
        <code style={cardStyles.uri}>{uri}</code>
        {isTemplate && <span style={cardStyles.badge}>template</span>}
      </div>
      <p style={cardStyles.desc}>{description}</p>
    </div>
  );
}

function ToolCard({ name, params, description }: {
  name: string;
  params: { name: string; type: string; description: string }[];
  description: string;
}) {
  return (
    <div style={cardStyles.card}>
      <code style={cardStyles.toolName}>{name}</code>
      <p style={cardStyles.desc}>{description}</p>
      {params.length > 0 && (
        <div style={cardStyles.params}>
          {params.map(p => (
            <div key={p.name} style={cardStyles.param}>
              <span style={cardStyles.paramName}>{p.name}</span>
              <span style={cardStyles.paramType}>{p.type}</span>
              <span style={cardStyles.paramDesc}>{p.description}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function CodeBlock({ code }: { code: string }) {
  return (
    <pre style={codeBlockStyles.pre}>
      <code style={codeBlockStyles.code}>{code}</code>
    </pre>
  );
}

function GitHubIcon() {
  return (
    <svg width={14} height={14} viewBox="0 0 24 24" fill="currentColor" style={{ flexShrink: 0 }}>
      <path d="M12 2C6.477 2 2 6.484 2 12.017c0 4.425 2.865 8.18 6.839 9.504.5.092.682-.217.682-.483 0-.237-.008-.868-.013-1.703-2.782.605-3.369-1.343-3.369-1.343-.454-1.158-1.11-1.466-1.11-1.466-.908-.62.069-.608.069-.608 1.003.07 1.531 1.032 1.531 1.032.892 1.53 2.341 1.088 2.91.832.092-.647.35-1.088.636-1.338-2.22-.253-4.555-1.113-4.555-4.951 0-1.093.39-1.988 1.029-2.688-.103-.253-.446-1.272.098-2.65 0 0 .84-.27 2.75 1.026A9.564 9.564 0 0 1 12 6.844a9.59 9.59 0 0 1 2.504.337c1.909-1.296 2.747-1.027 2.747-1.027.546 1.379.202 2.398.1 2.651.64.7 1.028 1.595 1.028 2.688 0 3.848-2.339 4.695-4.566 4.943.359.309.678.92.678 1.855 0 1.338-.012 2.419-.012 2.747 0 .268.18.58.688.482A10.02 10.02 0 0 0 22 12.017C22 6.484 17.522 2 12 2z" />
    </svg>
  );
}

// ─── Styles ───────────────────────────────────────────────────────────────────

const styles: Record<string, React.CSSProperties> = {
  page: {
    minHeight: '100vh',
    background: '#0b0d11',
    color: '#f9f9f7',
    fontFamily: 'var(--font)',
  },
  header: {
    borderBottom: '1px solid rgba(255,255,255,0.08)',
    height: 60,
    display: 'flex',
    alignItems: 'center',
    position: 'sticky',
    top: 0,
    background: '#0b0d11',
    zIndex: 50,
  },
  headerInner: {
    maxWidth: 1200,
    margin: '0 auto',
    padding: '0 24px',
    width: '100%',
    display: 'flex',
    alignItems: 'center',
    gap: 12,
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
  headerLabel: {
    fontSize: 13,
    color: 'rgba(249,249,247,0.35)',
    paddingLeft: 12,
    borderLeft: '1px solid rgba(255,255,255,0.14)',
  },
  layout: {
    maxWidth: 1200,
    margin: '0 auto',
    padding: '0 24px',
    display: 'flex',
    gap: 64,
    alignItems: 'flex-start',
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
  sidebarGroup: {
    fontSize: 11,
    fontWeight: 600,
    letterSpacing: '0.08em',
    textTransform: 'uppercase',
    color: 'rgba(249,249,247,0.4)',
    marginBottom: 8,
    marginTop: 4,
  },
  navItem: {
    display: 'block',
    width: '100%',
    textAlign: 'left',
    padding: '6px 10px',
    fontSize: 14,
    fontWeight: 400,
    color: 'rgba(249,249,247,0.5)',
    background: 'transparent',
    border: 'none',
    borderRadius: 6,
    cursor: 'pointer',
    transition: 'color 0.15s ease, background 0.15s ease',
  },
  navItemActive: {
    color: '#f9f9f7',
    fontWeight: 500,
    background: 'rgba(255,255,255,0.08)',
  },
  sidebarDivider: {
    height: 1,
    background: 'rgba(255,255,255,0.08)',
    margin: '12px 0',
  },
  githubLink: {
    display: 'inline-flex',
    alignItems: 'center',
    gap: 6,
    fontSize: 13,
    color: 'rgba(249,249,247,0.5)',
    textDecoration: 'none',
    padding: '6px 10px',
    borderRadius: 6,
    transition: 'color 0.15s ease',
  },
  content: {
    flex: 1,
    minWidth: 0,
    paddingTop: 40,
  },
  section: {
    marginBottom: 56,
  },
  h1: {
    fontSize: 36,
    fontWeight: 800,
    letterSpacing: '-0.04em',
    color: '#f9f9f7',
    marginBottom: 16,
    scrollMarginTop: 80,
  },
  h2: {
    fontSize: 24,
    fontWeight: 700,
    letterSpacing: '-0.03em',
    color: '#f9f9f7',
    marginBottom: 16,
    marginTop: 0,
    scrollMarginTop: 80,
  },
  h3: {
    fontSize: 15,
    fontWeight: 600,
    color: '#f9f9f7',
    marginTop: 28,
    marginBottom: 10,
  },
  lead: {
    fontSize: 17,
    color: 'rgba(249,249,247,0.82)',
    lineHeight: 1.7,
    marginBottom: 14,
  },
  body: {
    fontSize: 15,
    color: 'rgba(249,249,247,0.65)',
    lineHeight: 1.75,
    marginBottom: 14,
  },
  link: {
    color: '#5bbef0',
    textDecoration: 'underline',
  },
  code: {
    fontFamily: 'ui-monospace, "SF Mono", Menlo, monospace',
    fontSize: 13,
    background: 'rgba(255,255,255,0.08)',
    padding: '1px 5px',
    borderRadius: 4,
    color: '#f9f9f7',
  },
  codeInline: {
    fontFamily: 'ui-monospace, "SF Mono", Menlo, monospace',
    fontSize: 13,
    background: 'rgba(255,255,255,0.08)',
    padding: '1px 5px',
    borderRadius: 4,
    color: '#f9f9f7',
  },
};

const cardStyles: Record<string, React.CSSProperties> = {
  card: {
    border: '1px solid rgba(255,255,255,0.08)',
    borderRadius: 10,
    padding: '16px 20px',
    marginBottom: 12,
    background: '#111318',
  },
  uriRow: {
    display: 'flex',
    alignItems: 'center',
    gap: 10,
    marginBottom: 8,
  },
  uri: {
    fontFamily: 'ui-monospace, "SF Mono", Menlo, monospace',
    fontSize: 13,
    color: '#5bbef0',
    fontWeight: 600,
  },
  badge: {
    fontSize: 11,
    fontWeight: 600,
    letterSpacing: '0.04em',
    textTransform: 'uppercase',
    color: 'rgba(249,249,247,0.4)',
    background: 'rgba(255,255,255,0.08)',
    padding: '2px 7px',
    borderRadius: 20,
  },
  toolName: {
    display: 'block',
    fontFamily: 'ui-monospace, "SF Mono", Menlo, monospace',
    fontSize: 14,
    color: '#f9f9f7',
    fontWeight: 700,
    marginBottom: 8,
  },
  desc: {
    fontSize: 14,
    color: 'rgba(249,249,247,0.65)',
    lineHeight: 1.65,
    margin: 0,
  },
  params: {
    marginTop: 12,
    borderTop: '1px solid rgba(255,255,255,0.08)',
    paddingTop: 12,
    display: 'flex',
    flexDirection: 'column',
    gap: 8,
  },
  param: {
    display: 'flex',
    flexWrap: 'wrap',
    gap: 8,
    alignItems: 'baseline',
  },
  paramName: {
    fontFamily: 'ui-monospace, "SF Mono", Menlo, monospace',
    fontSize: 13,
    color: '#f9f9f7',
    fontWeight: 600,
  },
  paramType: {
    fontSize: 12,
    color: 'rgba(249,249,247,0.4)',
    background: 'rgba(255,255,255,0.08)',
    padding: '1px 6px',
    borderRadius: 4,
  },
  paramDesc: {
    fontSize: 13,
    color: 'rgba(249,249,247,0.5)',
    flex: '1 1 100%',
  },
};

const codeBlockStyles: Record<string, React.CSSProperties> = {
  pre: {
    background: '#080a0e',
    borderRadius: 10,
    padding: '16px 20px',
    overflowX: 'auto',
    marginBottom: 16,
  },
  code: {
    fontFamily: 'ui-monospace, "SF Mono", Menlo, monospace',
    fontSize: 13,
    color: '#e5e7eb',
    lineHeight: 1.7,
    whiteSpace: 'pre',
  },
};
