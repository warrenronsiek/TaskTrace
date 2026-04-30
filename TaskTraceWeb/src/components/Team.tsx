import React from 'react';

const members = [
  {
    name: 'Warren Ronsiek',
    role: 'Engineering',
    bio: 'Software developer with 10 years of experience in data and AI. Has built data products in consumer finance, health data security, and advertising.',
  },
];

export default function Team() {
  return (
    <section id="team" style={styles.section}>
      <div style={styles.container}>
        <div style={styles.header}>
          <span style={styles.label}>Team</span>
          <h2 style={styles.heading}>Built by people who want to know<br />what they accomplished this week</h2>
        </div>
        <div style={styles.grid}>
          {members.map((m, i) => (
            <MemberCard key={i} member={m} />
          ))}
        </div>
      </div>
    </section>
  );
}

function MemberCard({ member }: { member: typeof members[0] }) {
  return (
    <div style={styles.card}>
      <img src="/warren_headshot.jpeg" alt={member.name} style={styles.avatar} />
      <div>
        <div style={styles.name}>{member.name}</div>
        <div style={styles.role}>{member.role}</div>
        <p style={styles.bio}>{member.bio}</p>
        <div style={styles.socialLinks}>
          <SocialLink href="https://github.com/warrenronsiek" label="GitHub">
            <GitHubIcon />
          </SocialLink>
          <SocialLink href="https://linkedin.com/in/warrenronsiek" label="LinkedIn">
            <LinkedInIcon />
          </SocialLink>
          <SocialLink href="https://x.com/warrenronsiek" label="X">
            <XIcon />
          </SocialLink>
        </div>
      </div>
    </div>
  );
}

function SocialLink({ href, label, children }: { href: string; label: string; children: React.ReactNode }) {
  return (
    <a
      href={href}
      target="_blank"
      rel="noopener noreferrer"
      aria-label={label}
      style={styles.socialLink}
      onMouseEnter={e => (e.currentTarget.style.color = '#f9f9f7')}
      onMouseLeave={e => (e.currentTarget.style.color = 'rgba(249,249,247,0.35)')}
    >
      {children}
    </a>
  );
}

function GitHubIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor">
      <path d="M12 2C6.477 2 2 6.484 2 12.017c0 4.425 2.865 8.18 6.839 9.504.5.092.682-.217.682-.483 0-.237-.008-.868-.013-1.703-2.782.605-3.369-1.343-3.369-1.343-.454-1.158-1.11-1.466-1.11-1.466-.908-.62.069-.608.069-.608 1.003.07 1.531 1.032 1.531 1.032.892 1.53 2.341 1.088 2.91.832.092-.647.35-1.088.636-1.338-2.22-.253-4.555-1.113-4.555-4.951 0-1.093.39-1.988 1.029-2.688-.103-.253-.446-1.272.098-2.65 0 0 .84-.27 2.75 1.026A9.564 9.564 0 0 1 12 6.844a9.59 9.59 0 0 1 2.504.337c1.909-1.296 2.747-1.027 2.747-1.027.546 1.379.202 2.398.1 2.651.64.7 1.028 1.595 1.028 2.688 0 3.848-2.339 4.695-4.566 4.943.359.309.678.92.678 1.855 0 1.338-.012 2.419-.012 2.747 0 .268.18.58.688.482A10.02 10.02 0 0 0 22 12.017C22 6.484 17.522 2 12 2z" />
    </svg>
  );
}

function LinkedInIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor">
      <path d="M20.447 20.452h-3.554v-5.569c0-1.328-.027-3.037-1.852-3.037-1.853 0-2.136 1.445-2.136 2.939v5.667H9.351V9h3.414v1.561h.046c.477-.9 1.637-1.85 3.37-1.85 3.601 0 4.267 2.37 4.267 5.455v6.286zM5.337 7.433a2.062 2.062 0 0 1-2.063-2.065 2.064 2.064 0 1 1 2.063 2.065zm1.782 13.019H3.555V9h3.564v11.452zM22.225 0H1.771C.792 0 0 .774 0 1.729v20.542C0 23.227.792 24 1.771 24h20.451C23.2 24 24 23.227 24 22.271V1.729C24 .774 23.2 0 22.222 0h.003z" />
    </svg>
  );
}

function XIcon() {
  return (
    <svg width="17" height="17" viewBox="0 0 24 24" fill="currentColor">
      <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z" />
    </svg>
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
    maxWidth: 1100,
    margin: '0 auto',
  },
  header: {
    textAlign: 'center',
    marginBottom: 56,
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
    fontSize: 'clamp(28px, 4vw, 42px)',
    fontWeight: 800,
    letterSpacing: '-0.03em',
    color: 'var(--text-primary)',
    lineHeight: 1.14,
  },
  grid: {
    display: 'flex',
    justifyContent: 'center',
  },
  card: {
    display: 'flex',
    gap: 22,
    padding: '32px',
    background: 'rgba(255, 255, 255, 0.03)',
    borderRadius: 16,
    border: '1px solid rgba(255, 255, 255, 0.07)',
    backdropFilter: 'blur(12px) saturate(130%)',
    WebkitBackdropFilter: 'blur(12px) saturate(130%)',
    boxShadow: 'inset 0 1px 0 rgba(255, 255, 255, 0.05), 0 2px 12px rgba(0, 0, 0, 0.2)',
    alignItems: 'flex-start',
    maxWidth: 480,
    width: '100%',
  },
  avatar: {
    flexShrink: 0,
    width: 72,
    height: 72,
    borderRadius: '50%',
    objectFit: 'cover',
    border: '1.5px solid rgba(91,190,240,0.25)',
    boxShadow: '0 0 20px rgba(91, 190, 240, 0.1)',
  },
  name: {
    fontSize: 17,
    fontWeight: 700,
    color: 'var(--text-primary)',
    marginBottom: 3,
    letterSpacing: '-0.02em',
  },
  role: {
    fontSize: 12,
    fontWeight: 600,
    color: '#5bbef0',
    textTransform: 'uppercase',
    letterSpacing: '0.07em',
    marginBottom: 10,
  },
  bio: {
    fontSize: 14.5,
    color: 'var(--text-secondary)',
    lineHeight: 1.65,
    marginBottom: 14,
  },
  socialLinks: {
    display: 'flex',
    gap: 14,
  },
  socialLink: {
    color: 'var(--text-muted)',
    transition: 'color 0.15s ease',
    display: 'flex',
    alignItems: 'center',
  },
};
