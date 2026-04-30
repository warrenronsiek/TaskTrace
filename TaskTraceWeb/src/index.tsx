import React from 'react';
import { createRoot } from 'react-dom/client';
import '@fontsource-variable/inter';
import './styles/global.css';
import App from './App';
import './index.css'
import { PostHogProvider } from '@posthog/react'
import {ENV, VITE_PUBLIC_POSTHOG_HOST, VITE_PUBLIC_POSTHOG_PROJECT_TOKEN} from "./vars";

const options = {
    api_host: VITE_PUBLIC_POSTHOG_HOST,
    defaults: '2026-01-30',
} as const

const container = document.getElementById('root');
if (!container) throw new Error('Root element not found');

const root = createRoot(container);
root.render(
  <React.StrictMode>
      {ENV === 'prod' ? (
          <PostHogProvider options={options} apiKey={VITE_PUBLIC_POSTHOG_PROJECT_TOKEN}>
              <App />
          </PostHogProvider>
      ) : (
          <App />
      )}
  </React.StrictMode>
);
