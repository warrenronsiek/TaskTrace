import { useLocation } from 'react-router-dom';

const useCases = ['agents', 'billing', 'tracking', 'consulting'] as const;

export type UseCase = (typeof useCases)[number];

export interface Variant {
  badge: string;
  headline: [string, string];
  subheadline: string;
  cta: string;
  navCta: string;
  title: string;
  description: string;
}

const defaultUseCase: UseCase = 'agents';

const VARIANTS: Record<UseCase, Variant> = {
  agents: {
    badge: 'macOS app · your data stays on device',
    headline: ['Situational Awareness...', 'for Agents'],
    subheadline:
      'TaskTrace records your screen, keystrokes, and microphone, then uses on-device AI to summarize your day. Everything runs locally on your Mac. No internet access. Your data never leaves your laptop. Local AI agents can read that context on demand.',
    cta: 'Download for macOS',
    navCta: 'Download',
    title: 'TaskTrace | Situational Awareness for AI Agents',
    description:
      'TaskTrace records your work locally on your Mac and turns it into searchable, agent-ready context with on-device AI.',
  },
  billing: {
    badge: 'macOS app · accurate timesheets, zero effort',
    headline: ['Automatic Time Tracking', 'for Client Billing'],
    subheadline:
      'Stop guessing how long things took. TaskTrace silently records your work across every app, then uses on-device AI to break your day into billable activities. Tag by client, export for invoicing. Everything stays on your Mac.',
    cta: 'Track Billable Time',
    navCta: 'Start Billing',
    title: 'TaskTrace | Automatic Time Tracking for Client Billing',
    description:
      'Passive time tracking for consultants and agencies. TaskTrace records work locally and turns it into billable activity summaries.',
  },
  tracking: {
    badge: 'macOS app · runs locally, always private',
    headline: ['Know Where', 'Your Time Goes'],
    subheadline:
      'TaskTrace runs in the background, recording what you work on and for how long. On-device AI summarizes your sessions and surfaces patterns you never noticed. No manual timers, no browser extensions, no cloud uploads.',
    cta: 'See Where Time Goes',
    navCta: 'Start Tracking',
    title: 'TaskTrace | Passive Time Tracking for macOS',
    description:
      'TaskTrace automatically records your work on macOS, summarizes it with on-device AI, and helps you see where your time actually goes.',
  },
  consulting: {
    badge: 'macOS app · built for independent professionals',
    headline: ['Track Every Minute', 'Across Every Client'],
    subheadline:
      'Consultants juggle clients, contexts, and billable hours. TaskTrace captures it all passively — screen, keystrokes, meetings — then tags and summarizes each activity with on-device AI. Generate accurate reports without lifting a finger.',
    cta: 'Capture Client Work',
    navCta: 'For Consultants',
    title: 'TaskTrace | Time Tracking for Consultants',
    description:
      'TaskTrace captures client work passively, summarizes it locally with AI, and helps consultants generate accurate time reports without manual timers.',
  },
};

function parseUseCase(value: string | null): UseCase {
  return useCases.find(useCase => useCase === value) ?? defaultUseCase;
}

function appendUseCase(path: string, useCase: UseCase): string {
  const [pathAndSearch, hash = ''] = path.split('#');
  const [pathname, search = ''] = pathAndSearch.split('?');
  const params = new URLSearchParams(search);

  params.set('use', useCase);

  return [
    pathname,
    params.size > 0 ? `?${params.toString()}` : '',
    hash.length > 0 ? `#${hash}` : '',
  ].join('');
}

export function useUseCase(): UseCase {
  const location = useLocation();
  return parseUseCase(new URLSearchParams(location.search).get('use'));
}

export function useVariant(): Variant {
  return VARIANTS[useUseCase()];
}

export function useUseCasePath(path: string): string {
  return appendUseCase(path, useUseCase());
}
