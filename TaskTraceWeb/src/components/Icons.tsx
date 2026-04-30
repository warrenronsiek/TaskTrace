import React from 'react';

/**
 * Shared play/stop icons used across the site.
 * Play = positive / proactive / go.
 * Stop = negative / reactive / blocked.
 */

interface IconProps {
  size?: number;
  color?: string;
  style?: React.CSSProperties;
}

export function PlayIcon({ size = 16, color = 'currentColor', style }: IconProps) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 16 16"
      fill={color}
      style={{ flexShrink: 0, display: 'inline-block', ...style }}
    >
      <path d="M4.5 2.5a1 1 0 0 1 1.5-.87l8 4.62a1 1 0 0 1 0 1.74l-8 4.62A1 1 0 0 1 4.5 11.74V2.5z" />
    </svg>
  );
}

export function StopIcon({ size = 16, color = 'currentColor', style }: IconProps) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 16 16"
      fill={color}
      style={{ flexShrink: 0, display: 'inline-block', ...style }}
    >
      <rect x="2.5" y="2.5" width="11" height="11" rx="1.5" />
    </svg>
  );
}

export function GitHubIcon({ size = 16, color = 'currentColor', style }: IconProps) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill={color}
      style={{ flexShrink: 0, display: 'inline-block', ...style }}
      aria-hidden="true"
    >
      <path d="M12 .5C5.65.5.5 5.65.5 12c0 5.1 3.29 9.4 7.86 10.93.58.1.79-.25.79-.56v-2.15c-3.2.7-3.87-1.36-3.87-1.36-.52-1.34-1.28-1.69-1.28-1.69-1.05-.72.08-.7.08-.7 1.16.08 1.77 1.19 1.77 1.19 1.03 1.76 2.7 1.25 3.36.96.1-.75.4-1.25.73-1.54-2.55-.29-5.24-1.28-5.24-5.7 0-1.26.45-2.29 1.19-3.1-.12-.29-.52-1.47.11-3.06 0 0 .97-.31 3.18 1.18a11.1 11.1 0 0 1 5.8 0c2.2-1.49 3.17-1.18 3.17-1.18.63 1.59.23 2.77.11 3.06.74.81 1.19 1.84 1.19 3.1 0 4.43-2.69 5.4-5.26 5.69.42.36.78 1.07.78 2.16v3.14c0 .31.21.67.8.56A11.51 11.51 0 0 0 23.5 12C23.5 5.65 18.35.5 12 .5Z" />
    </svg>
  );
}
