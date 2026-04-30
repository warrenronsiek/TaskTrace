import React from 'react';
import { PlayIcon, StopIcon } from './Icons';

const steps = [
  {
    number: '01',
    title: 'Press record',
    description:
      'Click the play button in TaskTrace. The app runs in the background, capturing your active application, keystrokes, screenshots every minute, and microphone audio. All stored locally on your Mac.',
    icon: 'play' as const,
  },
  {
    number: '02',
    title: 'AI processes your session',
    description:
      'When you stop, the AI pipeline kicks in automatically. It describes screenshots with computer vision, transcribes audio, writes a summary for each activity, suggests tags, and groups everything into high-level overviews.',
    icon: 'stop' as const,
  },
  {
    number: '03',
    title: 'Review, tag, and report',
    description:
      'Browse your day in the Activity view. Adjust tags, fix durations, and read AI-generated overviews. Your analytics update instantly. Query your history from any AI tool via the built-in MCP server.',
    icon: 'play' as const,
  },
];

export default function HowItWorks() {
  return (
    <section id="how-it-works" style={styles.section}>
      <div style={styles.container}>
        <div style={styles.header}>
          <span style={styles.label}>How it works</span>
          <h2 style={styles.heading}>Three steps to a<br />complete work record</h2>
          <p style={styles.subheading}>
            No setup, no manual entry. TaskTrace handles the capture so you can focus on doing the work.
          </p>
        </div>

        <div style={styles.steps}>
          {steps.map((step, i) => (
            <React.Fragment key={i}>
              <Step step={step} />
              {i < steps.length - 1 && <div style={styles.connector} />}
            </React.Fragment>
          ))}
        </div>
      </div>
    </section>
  );
}

function Step({ step }: { step: typeof steps[0] }) {
  return (
    <div style={styles.step}>
      <div style={styles.stepNumber}>
        {step.icon === 'play'
          ? <PlayIcon size={18} color="#5bbef0" />
          : <StopIcon size={16} color="#5bbef0" />}
      </div>
      <div style={styles.stepContent}>
        <h3 style={styles.stepTitle}>{step.title}</h3>
        <p style={styles.stepDesc}>{step.description}</p>
      </div>
    </div>
  );
}

const styles: Record<string, React.CSSProperties> = {
  section: {
    background: '#f3f3f0',
    padding: '96px 24px',
  },
  container: {
    maxWidth: 900,
    margin: '0 auto',
  },
  header: {
    textAlign: 'center',
    marginBottom: 64,
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
    fontSize: 'clamp(28px, 4vw, 44px)',
    fontWeight: 800,
    letterSpacing: '-0.03em',
    color: '#0b0d11',
    lineHeight: 1.12,
    marginBottom: 16,
  },
  subheading: {
    fontSize: 17,
    color: '#6b7280',
    lineHeight: 1.6,
    maxWidth: 460,
    margin: '0 auto',
  },
  steps: {
    display: 'flex',
    flexDirection: 'column',
    gap: 0,
  },
  step: {
    display: 'flex',
    gap: 28,
    alignItems: 'flex-start',
    padding: '32px 36px',
    background: '#ffffff',
    borderRadius: 16,
    border: '1px solid rgba(0,0,0,0.06)',
  },
  connector: {
    width: 2,
    height: 24,
    background: 'linear-gradient(to bottom, rgba(91,190,240,0.3), rgba(91,190,240,0.1))',
    margin: '0 0 0 53px',
  },
  stepNumber: {
    flexShrink: 0,
    width: 44,
    height: 44,
    borderRadius: '50%',
    background: 'rgba(91,190,240,0.1)',
    border: '1.5px solid rgba(91,190,240,0.25)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    fontSize: 13,
    fontWeight: 700,
    color: '#5bbef0',
    fontVariantNumeric: 'tabular-nums',
    letterSpacing: '0.02em',
  },
  stepContent: {
    flex: 1,
    paddingTop: 2,
  },
  stepTitle: {
    fontSize: 19,
    fontWeight: 700,
    color: '#0b0d11',
    letterSpacing: '-0.02em',
    marginBottom: 10,
  },
  stepDesc: {
    fontSize: 15,
    color: '#6b7280',
    lineHeight: 1.65,
  },
};
