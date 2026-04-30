# TaskTraceWeb

`TaskTraceWeb` is the public website and download surface for TaskTrace.

## Development

```bash
corepack enable
pnpm install --frozen-lockfile
pnpm dev
```

## Builds

```bash
pnpm build:dev
pnpm build:prod
```

The build output is written to `dist/`.

## Important Files

- `src/App.tsx`: route table.
- `src/pages/LandingPage.tsx`: home page composition.
- `src/pages/PrivacyPage.tsx`: privacy page.
- `src/pages/TermsPage.tsx`: hosted-service terms.
- `src/pages/LicensePage.tsx`: open-source license page.
- `src/pages/DocsPage.tsx`: MCP setup docs.
- `src/components/Navbar.tsx`: top navigation and GitHub/download links.
- `src/components/Footer.tsx`: footer navigation and legal links.
- `src/vars.ts`: public website constants, including GitHub and download URLs.

Public values belong in `src/vars.ts`. Secrets and deploy credentials do not
belong in this package.

## Routing

Current top-level routes:

- `/`
- `/compare`
- `/compare/:comparisonSlug`
- `/privacy`
- `/terms`
- `/license`
- `/docs`
