import React, { useEffect } from 'react';
import Navbar from '../components/Navbar';
import Hero from '../components/Hero';
import FeatureTour from '../components/FeatureTour';
import AgentContext from '../components/AgentContext';
import IntegrationsSection from '../components/IntegrationsSection';
import PrivacySection from '../components/PrivacySection';
import Team from '../components/Team';
import Footer from '../components/Footer';
import { useVariant } from '../useCase';

export default function LandingPage() {
  const variant = useVariant();

  useEffect(() => {
    document.title = variant.title;
    document.querySelector('meta[name="description"]')?.setAttribute('content', variant.description);
    document.querySelector('meta[property="og:title"]')?.setAttribute('content', variant.title);
    document.querySelector('meta[property="og:description"]')?.setAttribute('content', variant.description);
    document.querySelector('meta[property="og:url"]')?.setAttribute('content', 'https://www.tasktrace.com/');
    document.querySelector('meta[name="twitter:title"]')?.setAttribute('content', variant.title);
    document.querySelector('meta[name="twitter:description"]')?.setAttribute('content', variant.description);
    document.querySelector('meta[name="twitter:url"]')?.setAttribute('content', 'https://www.tasktrace.com/');
    document.querySelector('link[rel="canonical"]')?.setAttribute('href', 'https://www.tasktrace.com/');
  }, [variant.description, variant.title]);

  return (
    <div style={styles.pageWrap}>
      {/* Ambient background orbs */}
      <div style={styles.orbContainer} aria-hidden="true">
        <div style={styles.orb1} />
        <div style={styles.orb2} />
        <div style={styles.orb3} />
        <div style={styles.orb4} />
      </div>

      <Navbar />
      <main style={{ position: 'relative', zIndex: 1 }}>
        <Hero />
        <FeatureTour />
        <div style={styles.sectionDivider} />
        <IntegrationsSection />
        <div style={styles.sectionDivider} />
        <AgentContext />
        <div style={styles.sectionDivider} />
        <PrivacySection />
        <div style={styles.sectionDivider} />
        <Team />
      </main>
      <Footer />
    </div>
  );
}

const styles: Record<string, React.CSSProperties> = {
  pageWrap: {
    position: 'relative',
    minHeight: '100vh',
    overflowX: 'clip',  /* clip horizontal overflow without breaking position:sticky */
  },
  orbContainer: {
    position: 'fixed',
    inset: 0,
    pointerEvents: 'none',
    zIndex: 0,
    overflow: 'hidden',
  },
  orb1: {
    position: 'absolute',
    top: '-10%',
    left: '15%',
    width: 700,
    height: 700,
    borderRadius: '50%',
    background: 'radial-gradient(circle, rgba(91,190,240,0.08) 0%, transparent 70%)',
    filter: 'blur(60px)',
    animation: 'orbFloat 25s ease-in-out infinite',
  },
  orb2: {
    position: 'absolute',
    top: '30%',
    right: '-5%',
    width: 600,
    height: 600,
    borderRadius: '50%',
    background: 'radial-gradient(circle, rgba(168,120,245,0.06) 0%, transparent 70%)',
    filter: 'blur(80px)',
    animation: 'orbFloatAlt 30s ease-in-out infinite',
  },
  orb3: {
    position: 'absolute',
    bottom: '15%',
    left: '-8%',
    width: 550,
    height: 550,
    borderRadius: '50%',
    background: 'radial-gradient(circle, rgba(91,190,240,0.05) 0%, transparent 70%)',
    filter: 'blur(70px)',
    animation: 'orbFloat 35s ease-in-out infinite',
    animationDelay: '-10s',
  },
  sectionDivider: {
    width: '100%',
    maxWidth: 1100,
    margin: '0 auto',
    height: 1,
    background: 'linear-gradient(90deg, transparent, rgba(255,255,255,0.06) 30%, rgba(255,255,255,0.06) 70%, transparent)',
  },
  orb4: {
    position: 'absolute',
    bottom: '40%',
    right: '20%',
    width: 400,
    height: 400,
    borderRadius: '50%',
    background: 'radial-gradient(circle, rgba(250,163,184,0.04) 0%, transparent 70%)',
    filter: 'blur(60px)',
    animation: 'orbFloatAlt 28s ease-in-out infinite',
    animationDelay: '-5s',
  },
};
