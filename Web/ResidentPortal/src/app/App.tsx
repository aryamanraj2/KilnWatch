import { useEffect, useRef } from 'react';
import { Link, NavLink, Route, Routes, useLocation } from 'react-router-dom';
import { useLocale } from '../i18n';
import { useApp } from './state';
import { config } from '../data/client';
import { AreaPage } from '../features/area/AreaPage';
import { KilnPage, RulePage } from '../features/records/RecordPages';
import { ComplaintPage } from '../features/complaint/ComplaintPage';
import { InfoPage } from '../features/InfoPage';
import { AskPage } from '../features/ask/AskPage';
import { usePhone } from '../components/shared';

export function App() {
  const { language, setLanguage, t, theme, setTheme } = useLocale();
  const { basket } = useApp();
  const location = useLocation();
  const phone = usePhone(); const menu = useRef<HTMLDetailsElement>(null);
  const close = () => { if (menu.current) menu.current.open = false; };
  const tab = location.pathname.startsWith('/ask') ? 'ask' : location.pathname.startsWith('/complaint') ? 'draft' : ['/', '/area'].includes(location.pathname) || /^\/(kilns|rules)\//.test(location.pathname) ? 'area' : null;
  useEffect(() => {
    document.title = `${t('Resident portal', 'निवासी पोर्टल')} · KilnWatch`;
    document.querySelector<HTMLElement>('#main')?.focus({ preventScroll: true });
    window.scrollTo({ top: 0, behavior: 'instant' });
  }, [location.pathname, language, t]);
  return <>
    <a className="skip-link" href="#main">{t('Skip to content', 'मुख्य सामग्री पर जाएँ')}</a>
    <header className="site-header">
      <Link className="brand" to="/" aria-label={t('KilnWatch home', 'KilnWatch मुख्य पृष्ठ')}><img src="/mark.svg" alt="" width="36" height="36" /><span>KilnWatch<small>{t('Resident portal', 'निवासी पोर्टल')}</small></span></Link>
      <nav aria-label={t('Main navigation', 'मुख्य नेविगेशन')}><NavLink to="/area" className={({ isActive }) => isActive || location.pathname === "/" ? "active" : ""}>{t('Check an area', 'क्षेत्र की जाँच')}</NavLink>{config.mode === 'live' && <NavLink to="/ask">{t('Ask', 'पूछें')}</NavLink>}<NavLink to="/complaint">{t('Inspection draft', 'निरीक्षण मसौदा')}{basket.length > 0 && <span className="count">{basket.length}</span>}</NavLink></nav>
      {phone ? <details className="prefs-menu" ref={menu}><summary><span className="sr-only">{t('Language and appearance', 'भाषा और रंग रूप')}: </span><span aria-hidden="true">Aa</span> {language === 'hi' ? 'हिन्दी' : 'EN'}</summary><div className="prefs-panel"><div className="language" role="group" aria-label="Language / भाषा"><button lang="en" aria-pressed={language === 'en'} onClick={() => { setLanguage('en'); close(); }}>EN</button><button lang="hi" aria-pressed={language === 'hi'} onClick={() => { setLanguage('hi'); close(); }}>हिन्दी</button></div><label className="theme-label"><span className="sr-only">{t('Appearance', 'रंग रूप')}</span><select aria-label={t('Appearance', 'रंग रूप')} value={theme} onChange={e => setTheme(e.target.value)}><option value="system">{t('System', 'सिस्टम')}</option><option value="light">{t('Light', 'हल्का')}</option><option value="dark">{t('Dark', 'गहरा')}</option></select></label></div></details> : <div className="preferences"><div className="language" role="group" aria-label="Language / भाषा"><button lang="en" aria-pressed={language === 'en'} onClick={() => setLanguage('en')}>EN</button><button lang="hi" aria-pressed={language === 'hi'} onClick={() => setLanguage('hi')}>हिन्दी</button></div><label className="theme-label"><span className="sr-only">{t('Appearance', 'रंग रूप')}</span><select aria-label={t('Appearance', 'रंग रूप')} value={theme} onChange={e => setTheme(e.target.value)}><option value="system">{t('System', 'सिस्टम')}</option><option value="light">{t('Light', 'हल्का')}</option><option value="dark">{t('Dark', 'गहरा')}</option></select></label></div>}
    </header>
    <div className="sample-strip"><span className="strip-full"><span className="sample-tag">{config.mode === 'fixture' ? t('Sample data', 'नमूना डेटा') : t('Public service', 'सार्वजनिक सेवा')}</span><span>{config.mode === 'fixture' ? t('Explore with fictional records. Nothing here is a finding about a real site.', 'काल्पनिक रिकॉर्ड के साथ देखें। यहाँ कोई जानकारी वास्तविक स्थल का निष्कर्ष नहीं है।') : t('Only approved public records can be displayed.', 'केवल स्वीकृत सार्वजनिक रिकॉर्ड दिखाए जा सकते हैं।')}</span></span><span className="strip-short">{config.mode === 'fixture' ? t('Sample data · fictional records', 'नमूना डेटा · काल्पनिक रिकॉर्ड') : t('Public service · approved records only', 'सार्वजनिक सेवा · केवल स्वीकृत रिकॉर्ड')}</span></div>
    <main id="main" tabIndex={-1}><Routes><Route path="/" element={<AreaPage />} /><Route path="/area" element={<AreaPage />} /><Route path="/kilns/:id" element={<KilnPage />} /><Route path="/rules/:id" element={<RulePage />} /><Route path="/complaint" element={<ComplaintPage />} /><Route path="/ask" element={<AskPage />} /><Route path="/about" element={<InfoPage kind="about" />} /><Route path="/privacy" element={<InfoPage kind="privacy" />} /><Route path="*" element={<div className="page narrow"><p className="eyebrow">404</p><h1>{t('This page is not here', 'यह पृष्ठ यहाँ नहीं है')}</h1><Link className="button primary" to="/">{t('Check an area', 'क्षेत्र की जाँच करें')}</Link></div>} /></Routes></main>
    <footer><span>KilnWatch <span className="footer-dot">·</span> {t('Evidence first. Inspection next.', 'पहले साक्ष्य। फिर निरीक्षण।')}</span><nav aria-label={t('Information', 'जानकारी')}><Link to="/about">{t('About & sources', 'परिचय और स्रोत')}</Link><Link to="/privacy">{t('Privacy', 'गोपनीयता')}</Link></nav></footer>
    <nav className="tab-bar" aria-label={t('Tabs', 'टैब')}>
      <Link to="/area" aria-current={tab === 'area' ? 'page' : undefined}><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 21s-6.5-5.6-6.5-11a6.5 6.5 0 0 1 13 0c0 5.4-6.5 11-6.5 11z" /><circle cx="12" cy="10" r="2.3" /></svg><span>{t('Area', 'क्षेत्र')}</span></Link>
      <Link to="/ask" aria-current={tab === 'ask' ? 'page' : undefined}><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4.5 5.5h15v10h-8l-4.5 3.5v-3.5h-2.5z" /></svg><span>{t('Ask', 'पूछें')}</span></Link>
      <Link to="/complaint" aria-current={tab === 'draft' ? 'page' : undefined}><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6.5 3.5h7l4 4v13h-11z" /><path d="M13.5 3.5v4h4M9 12h6M9 15.5h6" /></svg><span>{t('Draft', 'मसौदा')}{basket.length > 0 && <span className="count">{basket.length}</span>}</span></Link>
    </nav>
  </>;
}
