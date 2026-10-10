import { useEffect, useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { useApp, type DraftFields } from '../../app/state';
import { config } from '../../data/client';
import { useLocale } from '../../i18n';
import { Arrow, Status } from '../../components/shared';
import { exportText, makeDraft } from './draft';

export function ComplaintPage() {
  const s = useApp(); const { t, local, language } = useLocale(); const [message, setMessage] = useState(''); const editor = useRef<HTMLTextAreaElement>(null);
  const sample = config.mode === 'fixture';
  useEffect(() => { if (!s.draft) s.setDraftLanguage(language); }, [language]);
  function discardOK() { return !s.draft || window.confirm(t('Replace the current draft? Your edits will be lost.', 'मौजूदा मसौदा बदलें? आपके संपादन हट जाएँगे।')); }
  function field<K extends keyof DraftFields>(key: K, value: DraftFields[K]) { if (!discardOK()) return; s.setDraft(''); s.setFields(f => ({ ...f, [key]: value })); setMessage(''); }
  function generate() {
    if (!discardOK()) return;
    s.setDraft(makeDraft(s.basket, s.fields, s.draftLanguage, s.query?.center ?? null, window.location.origin, sample)); setMessage(t('Draft prepared. Review and edit before exporting.', 'मसौदा तैयार है। निर्यात से पहले पढ़ें और संपादित करें।'));
    requestAnimationFrame(() => editor.current?.focus());
  }
  function download() {
    const url = URL.createObjectURL(new Blob([exportText(s.draft, s.draftLanguage, sample)], { type: 'text/plain;charset=utf-8' }));
    const a = document.createElement('a'); a.href = url; a.download = `kilnwatch-${sample ? 'sample-' : ''}draft-${s.draftLanguage}.txt`; document.body.append(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(url), 1000);
    setMessage(t('Draft downloaded. Nothing has been submitted.', 'मसौदा डाउनलोड हुआ। कुछ भी जमा नहीं किया गया है।'));
  }
  async function copy() {
    try { await navigator.clipboard.writeText(exportText(s.draft, s.draftLanguage, sample)); setMessage(t('Draft copied. Nothing has been submitted.', 'मसौदा कॉपी हुआ। कुछ भी जमा नहीं किया गया है।')); }
    catch { editor.current?.focus(); editor.current?.select(); setMessage(t('Clipboard access is unavailable. Use Download text or select and copy the print preview text.', 'क्लिपबोर्ड उपलब्ध नहीं है। पाठ डाउनलोड करें या प्रिंट पूर्वावलोकन का पाठ चुनकर कॉपी करें।')); }
  }
  return <div className="page complaint-page"><div className="no-print"><Link className="back-link" to="/area">← {t('Back to area', 'क्षेत्र पर वापस जाएँ')}</Link><div className="intro"><div><p className="eyebrow">{t('Prepare, review, then export', 'तैयार करें, जाँचें, फिर निर्यात करें')}</p><h1>{t('Ask for an inspection.', 'निरीक्षण का अनुरोध करें।')}</h1></div><p>{t('A careful request starts with what is known—and what still needs checking. This is your editable draft; nothing is sent from here.', 'एक सावधान अनुरोध में ज्ञात बातें और बाकी जाँच स्पष्ट होती हैं। यह आपका संपादन योग्य मसौदा है; यहाँ से कुछ भेजा नहीं जाता।')}</p></div></div>
    {!s.basket.length ? <div className="empty card"><h2>{t('Choose a record to begin', 'शुरू करने के लिए रिकॉर्ड चुनें')}</h2><p>{t('Open a candidate and add it to your inspection draft. You can include up to 10 records.', 'किसी रिकॉर्ड को खोलें और निरीक्षण मसौदे में जोड़ें। अधिकतम 10 रिकॉर्ड शामिल कर सकते हैं।')}</p><Link className="button primary" to="/area">{t('Explore an area', 'क्षेत्र देखें')} <Arrow /></Link></div> : <>
      <div className="composer-grid no-print"><aside><section className="card"><p className="eyebrow">{t('Included records', 'शामिल रिकॉर्ड')}</p><h2>{s.basket.length} {t('selected', 'चुने गए')}</h2><ul className="basket-list">{s.basket.map(k => <li key={k.id}><Link className="mono" to={`/kilns/${k.id}`}>{k.id}</Link><p>{local(k.name)}</p><Status kiln={k} /><button className="text-button" aria-label={`${t('Remove', 'हटाएँ')} ${k.id}`} onClick={() => s.changeBasket(k)}>{t('Remove', 'हटाएँ')}</button></li>)}</ul><Link to="/area">{t('Add another record', 'और रिकॉर्ड जोड़ें')} <Arrow /></Link></section>
      <section className="card"><h2>{t('Your details', 'आपकी जानकारी')}</h2><p className="help">{t('Optional. Included only in the draft you choose to export.', 'वैकल्पिक। केवल आपके निर्यात किए गए मसौदे में शामिल होगी।')}</p><label htmlFor="resident-name">{t('Name (optional)', 'नाम (वैकल्पिक)')}</label><input id="resident-name" autoComplete="off" maxLength={120} value={s.fields.name} onChange={e => field('name', e.target.value)} /><label htmlFor="resident-contact">{t('Contact (optional)', 'संपर्क (वैकल्पिक)')}</label><input id="resident-contact" autoComplete="off" maxLength={180} value={s.fields.contact} onChange={e => field('contact', e.target.value)} /><label htmlFor="resident-observations">{t('Your own observations', 'आपके अपने अवलोकन')}</label><textarea id="resident-observations" rows={4} maxLength={4000} value={s.fields.observations} onChange={e => field('observations', e.target.value)} placeholder={t('What did you notice, and when?', 'आपने क्या देखा और कब?')} /><p className="help">{t('These are kept separate from satellite evidence.', 'इन्हें उपग्रह साक्ष्य से अलग रखा जाता है।')}</p>
      <label className="checkbox-label"><input type="checkbox" checked={s.fields.includeLocation} disabled={!s.query} onChange={e => field('includeLocation', e.target.checked)} /><span>{t('Include my exact search location in the draft', 'मसौदे में मेरी खोज का सटीक स्थान शामिल करें')}</span></label>{s.fields.includeLocation && s.query && <p className="mono small">{s.query.center[1].toFixed(5)}, {s.query.center[0].toFixed(5)}</p>}{!s.query && <p className="help">{t('Choose an area first to include a location. It is never required.', 'स्थान शामिल करने के लिए पहले क्षेत्र चुनें। यह आवश्यक नहीं है।')}</p>}</section></aside>
      <section className="editor-panel"><div className="editor-toolbar"><div><p className="eyebrow">{t('Inspection request', 'निरीक्षण अनुरोध')}</p><h2>{t('Make it your own', 'अपनी बात जोड़ें')}</h2></div><label htmlFor="draft-language">{t('Draft language', 'मसौदे की भाषा')}<select id="draft-language" value={s.draftLanguage} onChange={e => { if (discardOK()) { s.setDraft(''); s.setDraftLanguage(e.target.value === 'hi' ? 'hi' : 'en'); } }}><option value="en">English</option><option value="hi">हिन्दी</option></select></label></div>
      <div className="notice"><p>{t('Recipient not verified. Confirm the responsible authority and filing route yourself before using a real request. This portal does not submit complaints.', 'प्राप्तकर्ता सत्यापित नहीं है। वास्तविक अनुरोध से पहले संबंधित प्राधिकरण और जमा करने की प्रक्रिया की पुष्टि करें। यह पोर्टल शिकायत जमा नहीं करता।')}</p></div>
      <button className="primary" onClick={generate}>{s.draft ? t('Regenerate draft', 'मसौदा फिर बनाएँ') : t('Create editable draft', 'संपादन योग्य मसौदा बनाएँ')} <span aria-hidden="true">→</span></button>
      <label htmlFor="draft-editor">{t('Edit your inspection request', 'अपना निरीक्षण अनुरोध संपादित करें')}</label><textarea ref={editor} id="draft-editor" className="draft-editor" lang={s.draftLanguage} rows={22} maxLength={60000} value={s.draft} onChange={e => { s.setDraft(e.target.value); setMessage(''); }} placeholder={t('Create a draft, then edit the text here.', 'मसौदा बनाएँ, फिर यहाँ संपादन करें।')} />
      <p className="help">{t('Kept in this tab’s memory. Refreshing or closing the tab loses the draft. Changing details or records asks before clearing your text.', 'केवल इस टैब की मेमोरी में रहता है। रीफ़्रेश या बंद करने पर मसौदा खो जाएगा। जानकारी या रिकॉर्ड बदलने पर पाठ हटाने से पहले पूछा जाएगा।')}</p>
      <div className="export-actions"><button className="primary" disabled={!s.draft.trim()} onClick={download}>{t('Download text', 'पाठ डाउनलोड करें')} <span aria-hidden="true">↓</span></button><button className="secondary" disabled={!s.draft.trim()} onClick={copy}>{t('Copy draft', 'मसौदा कॉपी करें')}</button><button className="secondary" disabled={!s.draft.trim()} onClick={() => window.print()}>{t('Print / Save PDF', 'प्रिंट / PDF सहेजें')}</button></div>
      <p className="feedback" role="status">{message}</p>{s.draft && <details className="print-preview"><summary>{t('Review export text', 'निर्यात होने वाला पाठ देखें')}</summary><pre lang={s.draftLanguage}>{exportText(s.draft, s.draftLanguage, sample)}</pre></details>}
      <p className="help">{t('Evidence appears as links/references. No image files are attached.', 'साक्ष्य लिंक और संदर्भ के रूप में हैं। चित्र फ़ाइलें संलग्न नहीं हैं।')}{sample && ' ' + t('The sample-data notice is added to every export.', 'हर नमूना निर्यात में नमूना डेटा की सूचना रहती है।')}</p></section></div>
      <article id="print-document" lang={s.draftLanguage}><div className="print-brand">KilnWatch · {s.draftLanguage === 'hi' ? 'निरीक्षण अनुरोध' : 'Inspection request'}</div><div className="print-body">{exportText(s.draft, s.draftLanguage, sample)}</div></article>
    </>}
  </div>;
}
