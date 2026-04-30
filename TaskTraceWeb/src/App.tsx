import React from 'react';
import { BrowserRouter, Routes, Route } from 'react-router-dom';
import LandingPage from './pages/LandingPage';
import PrivacyPage from './pages/PrivacyPage';
import DocsPage from './pages/DocsPage';
import ComparisonIndexPage from './pages/ComparisonIndexPage';
import TermsPage from './pages/TermsPage';
import LicensePage from './pages/LicensePage';

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<LandingPage />} />
        <Route path="/compare" element={<ComparisonIndexPage />} />
        <Route path="/compare/:comparisonSlug" element={<ComparisonIndexPage />} />
        <Route path="/privacy" element={<PrivacyPage />} />
        <Route path="/terms" element={<TermsPage />} />
        <Route path="/license" element={<LicensePage />} />
        <Route path="/docs" element={<DocsPage />} />
      </Routes>
    </BrowserRouter>
  );
}
