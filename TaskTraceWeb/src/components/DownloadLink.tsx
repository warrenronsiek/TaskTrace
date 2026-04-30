import React, { useEffect, useId, useState } from 'react';
import { macDownloadUrl } from '../vars';

type DownloadLinkProps = {
  children: React.ReactNode;
  className?: string;
  style?: React.CSSProperties;
  onMouseEnter?: React.MouseEventHandler<HTMLAnchorElement>;
  onMouseLeave?: React.MouseEventHandler<HTMLAnchorElement>;
};

export default function DownloadLink({
  children,
  className,
  style,
  onMouseEnter,
  onMouseLeave,
}: DownloadLinkProps) {
  const [isOpen, setIsOpen] = useState(false);
  const titleId = useId();
  const bodyId = useId();

  useEffect(() => {
    if (!isOpen) {
      return;
    }

    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        setIsOpen(false);
      }
    };
    document.addEventListener('keydown', onKeyDown);
    return () => document.removeEventListener('keydown', onKeyDown);
  }, [isOpen]);

  return (
    <>
      <a
        href={macDownloadUrl}
        className={className}
        style={style}
        onClick={event => {
          event.preventDefault();
          setIsOpen(true);
        }}
        onMouseEnter={onMouseEnter}
        onMouseLeave={onMouseLeave}
      >
        {children}
      </a>

      {isOpen ? (
        <div
          style={styles.backdrop}
          role="presentation"
          onMouseDown={event => {
            if (event.target === event.currentTarget) {
              setIsOpen(false);
            }
          }}
        >
          <div
            role="dialog"
            aria-modal="true"
            aria-labelledby={titleId}
            aria-describedby={bodyId}
            style={styles.dialog}
          >
            <button
              type="button"
              aria-label="Close download details"
              style={styles.closeButton}
              onClick={() => setIsOpen(false)}
            >
              x
            </button>
            <div style={styles.kicker}>Before you download</div>
            <h2 id={titleId} style={styles.title}>
              TaskTrace ships with local AI models
            </h2>
            <div id={bodyId} style={styles.body}>
              <p style={styles.paragraph}>
                The macOS DMG is large because it includes the models TaskTrace needs for local summaries,
                search, and agent context. That keeps the core AI workflow on your Mac instead of making
                you download model files after install.
              </p>
              <p style={styles.paragraph}>
                You will want a powerful Apple Silicon Mac. We recommend a MacBook Pro-class machine,
                M2 or newer, with 32 GB of memory for a smooth experience.
              </p>
            </div>
            <div style={styles.actions}>
              <button type="button" style={styles.secondaryButton} onClick={() => setIsOpen(false)}>
                Cancel
              </button>
              <a href={macDownloadUrl} style={styles.primaryButton}>
                Download DMG
              </a>
            </div>
          </div>
        </div>
      ) : null}
    </>
  );
}

const styles: Record<string, React.CSSProperties> = {
  backdrop: {
    position: 'fixed',
    inset: 0,
    zIndex: 1000,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    padding: 24,
    background: 'rgba(3, 5, 9, 0.72)',
    backdropFilter: 'blur(18px) saturate(140%)',
    WebkitBackdropFilter: 'blur(18px) saturate(140%)',
  },
  dialog: {
    position: 'relative',
    width: 'min(100%, 520px)',
    borderRadius: 8,
    border: '1px solid rgba(255,255,255,0.12)',
    background: 'rgba(12, 14, 20, 0.96)',
    boxShadow: '0 24px 80px rgba(0,0,0,0.45), inset 0 1px 0 rgba(255,255,255,0.08)',
    padding: '30px 30px 28px',
    color: '#f9f9f7',
  },
  closeButton: {
    position: 'absolute',
    top: 14,
    right: 14,
    width: 32,
    height: 32,
    borderRadius: 999,
    color: 'rgba(249,249,247,0.68)',
    background: 'rgba(255,255,255,0.06)',
    border: '1px solid rgba(255,255,255,0.08)',
    fontSize: 22,
    lineHeight: '28px',
  },
  kicker: {
    color: '#5bbef0',
    fontSize: 12,
    fontWeight: 700,
    letterSpacing: '0.08em',
    textTransform: 'uppercase',
    marginBottom: 10,
  },
  title: {
    color: '#f9f9f7',
    fontSize: 28,
    lineHeight: 1.15,
    fontWeight: 800,
    letterSpacing: 0,
    margin: '0 42px 16px 0',
  },
  body: {
    display: 'flex',
    flexDirection: 'column',
    gap: 12,
  },
  paragraph: {
    color: 'rgba(249,249,247,0.68)',
    fontSize: 15,
    lineHeight: 1.65,
    margin: 0,
  },
  actions: {
    display: 'flex',
    justifyContent: 'flex-end',
    gap: 12,
    marginTop: 26,
    flexWrap: 'wrap',
  },
  secondaryButton: {
    minHeight: 42,
    padding: '10px 18px',
    borderRadius: 999,
    border: '1px solid rgba(255,255,255,0.12)',
    color: 'rgba(249,249,247,0.78)',
    background: 'rgba(255,255,255,0.04)',
    fontSize: 14,
    fontWeight: 700,
  },
  primaryButton: {
    minHeight: 42,
    display: 'inline-flex',
    alignItems: 'center',
    justifyContent: 'center',
    padding: '10px 18px',
    borderRadius: 999,
    color: '#0b0d11',
    background: '#5bbef0',
    fontSize: 14,
    fontWeight: 800,
  },
};
