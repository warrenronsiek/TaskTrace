export interface ComparisonCompetitor {
  name: string;
  positioning: string;
  strengths: string;
  gap: string;
}

export interface ComparisonSection {
  title: string;
  body: string;
}

export interface ComparisonFaq {
  question: string;
  answer: string;
}

export interface ComparisonPageContent {
  slug: string;
  badge: string;
  title: [string, string];
  description: string;
  verdict: string;
  competitors: ComparisonCompetitor[];
  landscapeNote?: string;
  taskTraceAdvantages: ComparisonSection[];
  honestLimits: string[];
  idealFor: string[];
  avoidIf: string[];
  faqs: ComparisonFaq[];
}

export const comparisonPages: ComparisonPageContent[] = [
  {
    slug: 'passive-time-tracking',
    badge: 'Comparison · passive time tracking',
    title: ['Passive Time Tracking', 'Without Guesswork'],
    description:
      'Compare TaskTrace against passive time tracking tools like RescueTime and Toggl Track if you want a clearer record of where your workday actually went.',
    verdict:
      'Choose TaskTrace here if app-level logging is not enough and you want your day turned into understandable work history, summaries, and billable reconstruction.',
    competitors: [
      {
        name: 'RescueTime',
        positioning: 'Background tracking for apps, sites, and productivity scoring.',
        strengths: 'Excellent passive logging, mature categorization, easy reporting.',
        gap: 'It usually tells you where time went at the app level, not what the work actually was.',
      },
      {
        name: 'Toggl Track',
        positioning: 'Widely adopted time tracker for projects, clients, and reports.',
        strengths: 'Clean timer UX, strong team reporting, easy invoicing workflows.',
        gap: 'It still depends on you remembering to start and stop the clock or fill in the blank later.',
      },
    ],
    taskTraceAdvantages: [
      {
        title: 'Passive capture becomes usable evidence',
        body: 'TaskTrace records screenshots, keystrokes, meetings, and app context so a later summary can explain the session instead of only timestamping it.',
      },
      {
        title: 'You can reconstruct billables after the fact',
        body: 'The product is stronger when a user forgot to track time but still needs an accurate timeline for a client, project, or internal review.',
      },
      {
        title: 'The timeline is semantic, not only temporal',
        body: 'The AI layer is supposed to turn raw capture into named activities, summaries, and taggable work units.',
      },
    ],
    honestLimits: [
      'If all someone wants is a simple timer or lightweight productivity score, TaskTrace is heavier than they need.',
      'The value here depends on trusting full work capture, which narrows the audience.',
      'For teams already standardized on classic time entry workflows, incumbent tools are easier to deploy.',
    ],
    idealFor: [
      'Independent professionals who repeatedly forget timers but still need accurate client reporting.',
      'People who want a true answer to "what did I do all day?" instead of a category pie chart.',
    ],
    avoidIf: [
      'You want the lightest possible tracker with minimal permissions.',
      'You only need start-stop timers and do not care about summaries or evidence.',
    ],
    faqs: [
      {
        question: 'Why not just use RescueTime?',
        answer:
          'RescueTime is better if app-level background analytics are enough. TaskTrace is for the case where the app name is not enough and you need the work session explained.',
      },
      {
        question: 'Why not just use Toggl?',
        answer:
          'Toggl wins when disciplined manual timers are acceptable. TaskTrace is trying to remove the discipline requirement altogether.',
      },
      {
        question: 'Is this a replacement for time tracking software?',
        answer:
          'Sometimes. More often it is the layer that produces the raw history a user can later turn into clean time tracking output.',
      },
    ],
  },
  {
    slug: 'proof-of-work',
    badge: 'Comparison · proof of work and monitoring',
    title: ['Proof Of Work', 'Without Corporate Surveillance'],
    description:
      'Compare TaskTrace against proof-of-work and employee monitoring tools like Time Doctor and Hubstaff. Same inputs, different philosophy.',
    verdict:
      'TaskTrace fits best when you want an evidence trail you control for reporting, accountability, or billing, without turning your workday into a company surveillance feed.',
    competitors: [
      {
        name: 'Time Doctor',
        positioning: 'Employer-facing activity tracking with screenshots and attendance style oversight.',
        strengths: 'Strong monitoring controls, mature reporting, familiar enterprise framing.',
        gap: 'The product narrative is managerial compliance, not personal memory or self-optimization.',
      },
      {
        name: 'Hubstaff',
        positioning: 'Workforce tracking with screenshots, GPS, scheduling, and payroll hooks.',
        strengths: 'Good fit for distributed teams that want one operations stack.',
        gap: 'It drifts toward fleet management and workforce administration instead of understanding knowledge work.',
      },
    ],
    taskTraceAdvantages: [
      {
        title: 'The captured record belongs to the user',
        body: 'TaskTrace can use screenshots and activity as proof, but the narrative is personal accountability and reporting, not bossware.',
      },
      {
        title: 'It can explain the work, not just police it',
        body: 'If the output becomes summaries, timelines, and semantic activity units, the captured data has value beyond compliance.',
      },
      {
        title: 'Local-first storage changes the trust model',
        body: 'Keeping sensitive work history on-device is a real differentiator against cloud monitoring suites.',
      },
    ],
    honestLimits: [
      'If a company explicitly wants centralized admin controls, payroll, and workforce management, incumbent tools still fit better.',
    ],
    idealFor: [
      'Contractors and employees who need to prove what happened during a day of work.',
      'People who want an evidence trail they control for billing, review cycles, or dispute resolution.',
    ],
    avoidIf: [
      'You are shopping for a team surveillance suite.',
      'You need payroll, scheduling, GPS tracking, or employer admin tooling.',
    ],
    faqs: [
      {
        question: 'How is this different from employee monitoring software?',
        answer:
          'The raw inputs may look similar, but the owner and purpose are different. The intended user is the worker who wants context, memory, and reporting they control.',
      },
      {
        question: 'Could a company still use it?',
        answer:
          'Possibly, but the strongest fit is still the individual user who wants local ownership of the captured record.',
      },
      {
        question: 'Why does local-first matter in this category?',
        answer:
          'Because the data is extremely sensitive. Storage architecture is part of the product promise, not a backend implementation detail.',
      },
    ],
  },
  {
    slug: 'ai-billables-reporting',
    badge: 'Comparison · AI summaries, billables, and reporting',
    title: ['AI Summaries And Billables', 'From Real Work History'],
    description:
      'Compare TaskTrace against tools like Timely and Harvest if your main goal is turning real work into faster, cleaner reports and billables.',
    verdict:
      'TaskTrace is strongest here when the hard part is not invoicing itself, but remembering and explaining what happened during the workday.',
    competitors: [
      {
        name: 'Timely',
        positioning: 'Automatic memory-based time capture and structured reporting.',
        strengths: 'Strong auto-tracking story and polished reporting workflows.',
        gap: 'It is still mostly about structuring time entries rather than deeply interpreting what the work meant.',
      },
      {
        name: 'Harvest',
        positioning: 'Classic agency timesheets, invoicing, and reporting.',
        strengths: 'Mature invoicing and team reporting, easy to understand, operationally dependable.',
        gap: 'Harvest shines after time is entered. It does not create a rich narrative of the day from raw context.',
      },
    ],
    taskTraceAdvantages: [
      {
        title: 'Summaries can become invoice-ready explanations',
        body: 'A consultant can move from captured work history to a client-readable account of what was done instead of just submitting hours.',
      },
      {
        title: 'Tagging can happen after the fact',
        body: 'Because the history exists, people can retroactively classify work by client or project without reconstructing the day from memory.',
      },
      {
        title: 'The same capture layer powers both reporting and recall',
        body: 'One recording system can answer billing, status updates, and personal retrospectives instead of forcing separate workflows.',
      },
    ],
    honestLimits: [
      'If the user already has disciplined billing ops and only needs a standard invoicing tool, Harvest may be enough.',
      'Some teams need accounting integrations more than they need deeper semantic context.',
    ],
    idealFor: [
      'Consultants, agencies, and freelancers who need to explain and bill work accurately.',
      'Anyone who wants reports generated from captured activity instead of manual memory.',
    ],
    avoidIf: [
      'You mainly need invoicing features and not activity capture.',
      'You want a simple timesheet system with established finance integrations.',
    ],
    faqs: [
      {
        question: 'Is this better than Harvest for invoicing?',
        answer:
          'Not necessarily. Harvest is stronger as a classic invoicing product. TaskTrace is stronger earlier in the chain when the problem is reconstructing the work in the first place.',
      },
      {
        question: 'What makes this different from Timely?',
        answer:
          'The differentiator is depth of capture. Timely organizes time well. TaskTrace is trying to explain the work session with enough context to produce better summaries.',
      },
      {
        question: 'Who gets the most value here?',
        answer:
          'People whose billing quality depends on memory and who routinely lose information between doing the work and documenting the work.',
      },
    ],
  },
  {
    slug: 'personal-analytics',
    badge: 'Comparison · personal analytics and productivity insight',
    title: ['Personal Analytics', 'Beyond Focus Coaching'],
    description:
      'Compare TaskTrace against productivity insight tools like Rize and DeskTime. This category is closer to the self-optimization story, but most products still stay shallow.',
    verdict:
      'TaskTrace makes more sense here if you want analysis grounded in real work sessions instead of just focus scores, reminders, and productivity labels.',
    competitors: [
      {
        name: 'Rize',
        positioning: 'Automatic tracking plus AI-style focus coaching and break suggestions.',
        strengths: 'Clean habit feedback, clear personal improvement loops, approachable UX.',
        gap: 'It does not preserve a very rich memory of the work itself.',
      },
      {
        name: 'DeskTime',
        positioning: 'Productivity tracking with app classifications and analytics.',
        strengths: 'Good dashboards, simple reporting, easy way to categorize productive versus unproductive time.',
        gap: 'A productivity score is a lossy summary. It usually cannot explain the substance of the day.',
      },
    ],
    taskTraceAdvantages: [
      {
        title: 'The analysis can anchor on actual sessions',
        body: 'Patterns, interruptions, and client mix can be inferred from concrete work history instead of from coarse app categories.',
      },
      {
        title: 'Self-optimization can stay tied to output',
        body: 'A user can review what kinds of work led to progress, context switching, or burnout because the underlying timeline is interpretable.',
      },
      {
        title: 'The same system supports reflection and execution',
        body: 'TaskTrace can be both the archive of what happened and the analytics layer over it.',
      },
    ],
    honestLimits: [
      'If someone only wants lightweight nudges and break reminders, a simpler focus tool may feel better.',
      'Users who dislike full capture will prefer shallower coaching products.',
    ],
    idealFor: [
      'People trying to understand what kinds of work consume time and create progress.',
      'Users who want productivity insight tied to real outputs and project context.',
    ],
    avoidIf: [
      'You only want habit nudges, pomodoro support, or break reminders.',
      'You do not want screenshots or detailed history involved in the analysis.',
    ],
    faqs: [
      {
        question: 'Is this a focus coach?',
        answer:
          'Not really. It can support focus analysis, but the stronger story is work memory plus analytics, not coaching by itself.',
      },
      {
        question: 'How is this different from DeskTime?',
        answer:
          'DeskTime is good at turning activity into categorized productivity dashboards. TaskTrace is better positioned if the user wants to inspect what the work actually was.',
      },
      {
        question: 'Why does full capture matter here?',
        answer:
          'Because shallow inputs usually produce shallow advice. Richer context makes the analytics more defensible and more useful.',
      },
    ],
  },
  {
    slug: 'llm-context-memory',
    badge: 'Comparison · LLM context and memory',
    title: ['LLM Memory', 'Built Around Active Work'],
    description:
      'TaskTrace records work context for summaries, recall, and AI assistance on your Mac. Older products like Rewind and Limitless helped define this space, but they are no longer active standalone options in the same way.',
    verdict:
      'Choose TaskTrace here if you want memory that is tied to active work and turns into something usable, like timelines, summaries, analytics, and agent context.',
    landscapeNote:
      'Rewind and Limitless were important reference points for this category, but Limitless was acquired by Meta in December 2025 and the company says the Rewind app is sunsetting. That leaves more room for a work-focused, local-first product.',
    competitors: [],
    taskTraceAdvantages: [
      {
        title: 'The output is more than search',
        body: 'TaskTrace can produce timelines, summaries, analytics, tags, and reportable work units rather than just retrieval results.',
      },
      {
        title: 'The product is centered on work, not general life capture',
        body: 'Work memory is easier to justify than total life memory because the ROI is clearer: billing, recall, accountability, and optimization.',
      },
      {
        title: 'Local-first storage matches the sensitivity of the data',
        body: 'Memory products trigger privacy concerns quickly. On-device storage is not sufficient by itself, but it does make the pitch stronger.',
      },
    ],
    honestLimits: [
      'If TaskTrace does not feel clearly more structured than retrieval-first products, the distinction will be lost.',
      'The category is powerful but also easy to make sound scary or excessive.',
    ],
    idealFor: [
      'People who want AI to understand work context continuously instead of only through prompts.',
      'Users who need both recall and operational outputs like summaries, billing, or analytics.',
    ],
    avoidIf: [
      'You only want general-purpose memory search across your whole life.',
      'You prefer a cloud-first assistant that follows you across many devices and modalities.',
    ],
    faqs: [
      {
        question: 'Is this basically Rewind?',
        answer:
          'It overlaps, but the sharper story is structured work context. Rewind is retrieval-first. TaskTrace should feel closer to an operating log for work.',
      },
      {
        question: 'What makes this more useful than a memory search tool?',
        answer:
          'The difference is whether the captured context turns into something structured and actionable, like summaries, timelines, tags, and reports, instead of only searchable recall.',
      },
      {
        question: 'Why focus on work memory instead of life memory?',
        answer:
          'Because the value is easier to justify. Work memory has immediate uses for billing, reporting, recall, and AI context.',
      },
    ],
  },
  {
    slug: 'local-first-lifelogging',
    badge: 'Comparison · local-first lifelogging',
    title: ['Local-First Lifelogging', 'With More Ambition'],
    description:
      'Compare TaskTrace against local-first activity logging tools like ActivityWatch and ManicTime. Philosophically aligned, but usually much less ambitious.',
    verdict:
      'TaskTrace is most compelling here if you already like the local-first philosophy but want more than raw logs and dashboards.',
    competitors: [
      {
        name: 'ActivityWatch',
        positioning: 'Open, privacy-first, local activity tracking.',
        strengths: 'Strong local-first philosophy, lightweight adoption, credible privacy posture.',
        gap: 'It mostly logs and visualizes. The interpretation layer is limited compared with the TaskTrace thesis.',
      },
      {
        name: 'ManicTime',
        positioning: 'Automatic local activity tracking and offline history.',
        strengths: 'Solid passive logging, dependable offline story, practical desktop utility.',
        gap: 'It records history well but does not push deeply into semantic AI summaries or agent context.',
      },
    ],
    taskTraceAdvantages: [
      {
        title: 'The local-first story survives richer capture',
        body: 'TaskTrace can keep the privacy philosophy while still recording screenshots, transcripts, and session context that older tools usually avoid.',
      },
      {
        title: 'AI turns logs into something closer to memory',
        body: 'A local activity log becomes materially more useful when it can answer what happened, why it mattered, and how it should be grouped.',
      },
      {
        title: 'The same archive can power agents',
        body: 'This is where the product can exceed traditional local trackers: it can become context infrastructure for AI tools running on the same machine.',
      },
    ],
    honestLimits: [
      'Users who care most about simplicity and open-ended logging may prefer the leaner incumbents.',
      'Richer capture means higher trust requirements and a bigger permission surface.',
      'The AI value has to be real or the product will just look like a heavier local tracker.',
    ],
    idealFor: [
      'People who already like the local-first ethos but want more than dashboards and raw logs.',
      'Users who want their local archive to support summaries, search, analytics, and agent workflows.',
    ],
    avoidIf: [
      'You want the simplest possible local tracker with minimal scope.',
      'You prefer open-source-style utilities over a more opinionated product.',
    ],
    faqs: [
      {
        question: 'Why not just use ActivityWatch?',
        answer:
          'ActivityWatch is great if the goal is private logging and visualization. TaskTrace aims at a richer interpretation layer on top of similar local-first instincts.',
      },
      {
        question: 'Is local-first enough to win?',
        answer:
          'No. It is table stakes for this category. The real question is whether the product does meaningfully more with the local archive.',
      },
      {
        question: 'Why does the local-first angle matter so much?',
        answer:
          'Because the captured data is sensitive. Local ownership is part of the value proposition, not just a backend detail.',
      },
    ],
  },
  {
    slug: 'team-analytics',
    badge: 'Comparison · team analytics and organizational intelligence',
    title: ['Team Analytics', 'Only If You Go Multi-User'],
    description:
      'Compare TaskTrace against team analytics and workforce reporting tools like TimeCamp and Connecteam if you are thinking beyond individual tracking.',
    verdict:
      'TaskTrace is not the best choice here if you need a full team operations suite today. It is more relevant if you want an individual-first product that could grow into shared team intelligence later.',
    competitors: [
      {
        name: 'TimeCamp',
        positioning: 'Team productivity, billing, and time reporting software.',
        strengths: 'Good organization-level reporting and familiar time management workflows.',
        gap: 'The system usually aggregates time rather than deeply understanding the underlying work.',
      },
      {
        name: 'Connecteam',
        positioning: 'Operations software for scheduling, payroll, and workforce coordination.',
        strengths: 'Strong operational tooling for deskless or distributed teams.',
        gap: 'It is not really a knowledge-work memory or AI context product.',
      },
    ],
    taskTraceAdvantages: [
      {
        title: 'Individual capture can become an organizational dataset later',
        body: 'If enough users opt in, a team layer could inherit much richer source data than standard time tracking tools ever receive.',
      },
      {
        title: 'Knowledge-work analytics could be more granular',
        body: 'Instead of aggregated time only, the system could reason about work modes, handoffs, and project flow.',
      },
      {
        title: 'The product can enter from the bottom up',
        body: 'Starting with an individual tool creates a different adoption path than top-down enterprise procurement.',
      },
    ],
    honestLimits: [
      'TaskTrace is not primarily a team admin suite today.',
      'Enterprise buyers usually expect permissions, controls, integrations, and reporting depth that are outside the initial product story.',
    ],
    idealFor: [
      'Teams that may eventually want bottom-up work intelligence built from individual capture.',
      'Organizations exploring a more user-controlled alternative to classic workforce reporting.',
    ],
    avoidIf: [
      'You are currently evaluating workforce operations software.',
      'You need scheduling, payroll, or centralized team administration right now.',
    ],
    faqs: [
      {
        question: 'Should TaskTrace lead with team analytics today?',
        answer:
          'Probably not. Today the product is a better fit for individual users than for centralized team administration.',
      },
      {
        question: 'Why include this page at all?',
        answer:
          'Because some buyers will still search here, and it helps define what the product is not yet while outlining the future direction honestly.',
      },
      {
        question: 'What would make this category viable later?',
        answer:
          'A clear opt-in multi-user model, strong permission controls, and proof that richer capture creates better org-level insight than standard timesheets.',
      },
    ],
  },
];

export const comparisonSlugs = comparisonPages.map(page => page.slug);
