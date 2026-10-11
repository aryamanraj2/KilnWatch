import { Link, useNavigate, useParams, useSearchParams } from 'react-router-dom';
import { lazy, Suspense, useState } from 'react';
import { client, config } from '../../data/client';
import { assessed, safeSource, type Kiln, type RuleCheck } from '../../data/model';
import { CHECK_STATUS, flags, UNKNOWN_CHECK, UNKNOWN_VERIFICATION, VERIFICATION } from '../../data/live';
import { useApp } from '../../app/state';
import { useLocale } from '../../i18n';
import { Arrow, ErrorState, Loading, Status, usePhone, useResource } from '../../components/shared';
import { Evidence } from '../evidence/Evidence';
import { describe, missingFacts } from '../complaint/draft';
const Diagram = lazy(() => import('../area/Diagram'));

export function KilnPage() {
  const { id = '' } = useParams(); const { t, local, number, date, language } = useLocale();
  const resource = useResource(signal => client.detail(id, signal), id); const s = useApp(); const navigate = useNavigate();
  const [explanation, setExplanation] = useState<'explain' | 'missing' | null>(null); const phone = usePhone();
  if (resource.error) return <div className="page narrow"><ErrorState error={resource.error} retry={resource.retry} /></div>;
  if (!resource.value) return <div className="page"><Loading /></div>;
  const k = resource.value, selected = s.basket.some(item => item.id === k.id), sample = config.mode === 'fixture';
  return <div className="page detail-page"><Link className="back-link" to="/area">← {t('Back to area', 'क्षेत्र पर वापस जाएँ')}</Link>
    <div className="record-heading"><div><p className="eyebrow">{t('A record to understand', 'समझने के लिए एक रिकॉर्ड')}</p><h1>{local(k.name)}</h1>{local(k.name) !== k.id && <p className="mono record-code">{k.id}</p>}<Status kiln={k} /></div><div className="observation"><p className="eyebrow">{t('Latest observation', 'नवीनतम अवलोकन')}</p><strong>{date(k.last_seen)}</strong><p className="help">{sample ? t('Sample date · fictional site', 'नमूना तिथि · काल्पनिक स्थल') : t('Observation, not construction date', 'अवलोकन, निर्माण की तिथि नहीं')}</p></div></div>
    <Glance kiln={k} sample={sample} />
    {k.human_reviewed && sample && <p className="notice">{t('Fictitious human-reviewed example. No real inspection is represented.', 'मानव-समीक्षित स्थिति का काल्पनिक उदाहरण। यह वास्तविक निरीक्षण नहीं है।')}</p>}
    <div className="detail-grid"><div><Evidence key={id} kiln={k} /><section className="record-section"><div className="section-heading"><h2>{t('What the rules tell us', 'नियम क्या बताते हैं')}</h2><span className="small muted">{t('Measurements, with context', 'संदर्भ सहित माप')}</span></div>{k.checks ? <Checks kiln={k} /> : k.assessments.map(a => <article className="rule-card" key={a.rule_id}><Link className="citation mono" to={`/rules/${a.rule_id}`}>{a.rule_id} <Arrow /></Link>{assessed(a) ? <><div className="rule-measure"><strong className="mono">{number(a.measured_distance_m!)} {t('m', 'मी')}</strong><span>{sample ? t('sample distance · reference threshold', 'नमूना दूरी · संदर्भ सीमा') : t('measured distance · supplied threshold', 'मापी गई दूरी · दी गई सीमा')} <b className="mono">{number(a.threshold_m!)} {t('m', 'मी')}</b></span></div><div className={`distance-bar${a.measured_distance_m! < a.threshold_m! ? '' : ' neutral'}`} aria-hidden="true"><span style={{ width: `${Math.min(100, a.measured_distance_m! / a.threshold_m! * 100)}%` }} /><i /></div><p className="help">{sample ? t('Sample assessment only. Applicability and measurement require site verification.', 'केवल नमूना आकलन। लागू नियम और माप की स्थल पर पुष्टि आवश्यक है।') : t('Published assessment. Confirm site conditions with an authorised inspector.', 'प्रकाशित आकलन। अधिकृत निरीक्षक से स्थल की स्थिति की पुष्टि कराएँ।')}</p><a href={safeSource(a.source_url)} rel="noreferrer" target="_blank">{t('Read the cited source', 'दिए गए स्रोत को पढ़ें')} <Arrow /></a></> : <><h3>{t('Not assessed', 'आकलन नहीं हुआ')}</h3><p>{t('The applicable rule or measurement has not been established. This is not a compliance finding.', 'लागू नियम या माप स्थापित नहीं किया गया है। यह अनुपालन का निष्कर्ष नहीं है।')}</p></>}</article>)}</section></div>
      <aside className="detail-aside"><section className="card location-card"><p className="eyebrow">{t('Site location', 'स्थल का स्थान')}</p><Suspense fallback={<Loading />}><Diagram compact query={{ center: k.centroid, radius_m: 800 }} page={{ items: [{ kiln: k, distance_m: 0 }], next_cursor: null, complete: true, revision: k.revision, coverage: 'unknown', updated_at: k.last_seen, distance_basis: 'centroid' }} selected={k.id} onSelect={() => {}} /></Suspense><p className="help">{sample ? t('Fictional site on a real street map.', 'वास्तविक नक्शे पर काल्पनिक स्थल।') : t('Published site coordinates.', 'प्रकाशित स्थल निर्देशांक।')}</p></section><details className="card prediction-card" open={!phone}><summary className="eyebrow" onClick={e => { if (!phone) e.preventDefault(); }}>{t('Model prediction', 'मॉडल का अनुमान')}</summary><h2>{['FCBK', 'CFCBK', 'Zigzag'].includes(k.prediction.type) ? k.prediction.type : t('Type unknown', 'प्रकार अज्ञात')}</h2><p>{sample ? t('Confirm on site', 'स्थल पर पुष्टि करें') : t('Unverified · confirm on site', 'अपुष्ट · स्थल पर पुष्टि करें')}</p><p className="help">{sample ? t('A model score does not verify technology, fuel, or operation.', 'मॉडल का स्कोर तकनीक, ईंधन या संचालन की पुष्टि नहीं करता।') : t('The score is a detector score for shape matching, not an accuracy. It does not verify type, technology, fuel or operation.', 'यह स्कोर आकार मिलान का डिटेक्टर स्कोर है, सटीकता नहीं। इससे प्रकार, तकनीक, ईंधन या संचालन की पुष्टि नहीं होती।')}</p><dl><div><dt>{sample ? t('Model score', 'मॉडल स्कोर') : t('Detector score', 'डिटेक्टर स्कोर')}</dt><dd className="mono">{k.prediction.score === null ? '—' : number(k.prediction.score, 2)}</dd></div><div><dt>{t('Latitude', 'अक्षांश')}</dt><dd className="mono">{k.centroid[1].toFixed(5)}</dd></div><div><dt>{t('Longitude', 'देशांतर')}</dt><dd className="mono">{k.centroid[0].toFixed(5)}</dd></div></dl></details>
      <section className="card"><p className="eyebrow">{t('Population context', 'जनसंख्या का संदर्भ')}</p>{k.exposure ? <><h2>{number(k.exposure.people)} <small>{t('people', 'लोग')}</small></h2><p>{t('within', 'दायरे में')} {number(k.exposure.radius_m)} {t('m', 'मी')}{!sample && ` ${t('of the kiln edge · modelled residents', 'भट्ठे के किनारे से · मॉडल आधारित निवासी')}`}</p><p className="help">{local(k.exposure.source)}{k.exposure.estimated_at && ` · ${date(k.exposure.estimated_at)}`}</p></> : <><h2 className="small-heading">{sample ? t('Exposure estimate not available', 'जनसंख्या प्रभाव का अनुमान उपलब्ध नहीं') : t('Exposure not assessed', 'जनसंख्या प्रभाव का आकलन नहीं हुआ')}</h2><p className="help">{t('Missing data does not mean zero people are nearby.', 'जानकारी न होने का अर्थ यह नहीं कि आसपास कोई नहीं रहता।')}</p></>}</section>
      <section className="card explanation"><p className="eyebrow">{t('Make sense of this record', 'इस रिकॉर्ड को समझें')}</p><h2>{t('What can I ask?', 'मैं क्या पूछ सकता हूँ?')}</h2><p className="help">{sample ? t('Template-based explanations from this record. No live assistant.', 'इस रिकॉर्ड पर आधारित तय प्रारूप के स्पष्टीकरण। लाइव सहायक नहीं।') : t('Template-based explanations from this record, or ask the public assistant.', 'इस रिकॉर्ड पर आधारित तय प्रारूप के स्पष्टीकरण, या सार्वजनिक सहायक से पूछें।')}</p><div className="explain-actions"><button className="secondary" onClick={() => setExplanation('explain')}>{t('Explain this record', 'इस रिकॉर्ड को समझाएँ')} <span aria-hidden="true">→</span></button><button className="secondary" onClick={() => setExplanation('missing')}>{t('What is missing?', 'क्या जानकारी बाकी है?')} <span aria-hidden="true">→</span></button>{!sample && <Link className="button secondary" to={`/ask?kiln=${encodeURIComponent(k.id)}`}>{t('Ask about this kiln', 'इस भट्ठे के बारे में पूछें')} <Arrow /></Link>}</div>{explanation && <div className="explanation-answer" role="status"><span className="sample-tag">{sample ? t('Sample explanation', 'नमूना स्पष्टीकरण') : t('Record explanation', 'रिकॉर्ड का स्पष्टीकरण')}</span>{explanation === 'explain' ? <p>{describe(k, language, sample)}</p> : <ul>{missingFacts(k, language).map(f => <li key={f}>{f}</li>)}</ul>}<Link className="citation mono" to={`/kilns/${k.id}`}>{k.id}</Link></div>}</section>
      <section className="draft-callout"><h2>{t('Turn questions into a request.', 'सवालों को अनुरोध में बदलें।')}</h2><p>{t('Add this record to an editable draft asking for an inspection.', 'इस रिकॉर्ड को निरीक्षण का अनुरोध करने वाले संपादन योग्य मसौदे में जोड़ें।')}</p><button className={selected ? 'secondary full' : 'primary full'} disabled={!selected && s.basket.length >= 10} onClick={() => s.changeBasket(k)}>{selected ? t('Remove from draft', 'मसौदे से हटाएँ') : t('Add to inspection draft', 'निरीक्षण मसौदे में जोड़ें')}</button>{!selected && s.basket.length >= 10 && <p>{t('A draft can include up to 10 records.', 'मसौदे में अधिकतम 10 रिकॉर्ड हो सकते हैं।')}</p>}<button className="text-button" onClick={() => { if (selected || s.changeBasket(k)) navigate('/complaint'); }}>{t('Prepare an inspection request', 'निरीक्षण का अनुरोध तैयार करें')} <Arrow /></button></section></aside>
    </div>
    <div className="action-bar"><Link className="button secondary" to={`/ask?kiln=${encodeURIComponent(k.id)}`}>{t('Ask about this kiln', 'इस भट्ठे के बारे में पूछें')}</Link><button className="primary" disabled={!selected && s.basket.length >= 10} onClick={() => s.changeBasket(k)}>{selected ? t('Remove from draft', 'मसौदे से हटाएँ') : t('Add to draft', 'मसौदे में जोड़ें')}</button></div>
  </div>;
}

// Phones only (CSS): restates lines the page already shows, no new claims or numbers.
function Glance({ kiln: k, sample }: { kiln: Kiln; sample: boolean }) {
  const { t, number, date } = useLocale();
  const m = (n: number) => `${number(n)}\u00a0${t('m', 'मी')}`;
  let rule;
  if (k.checks) {
    const f = flags(k)[0];
    rule = f && f.measured_distance_m !== null && f.threshold_m !== null
      ? <><span className="mono">{f.rule_id}</span> <strong className="mono">{m(f.measured_distance_m)}</strong> · {t('rule', 'नियम')} <span className="mono">{m(f.threshold_m)}</span><small>{t(...(CHECK_STATUS[f.status] ?? UNKNOWN_CHECK))} · {t(...((f.verification && VERIFICATION[f.verification]) || UNKNOWN_VERIFICATION))}</small></>
      : f ? <>{t(...(CHECK_STATUS[f.status] ?? UNKNOWN_CHECK))}</> : <>{t('No siting flag from mapped data.', 'मानचित्र डेटा से कोई स्थान संबंधी संकेत नहीं मिला।')}</>;
  } else {
    const a = k.assessments.find(assessed);
    rule = a ? <><span className="mono">{a.rule_id}</span> <strong className="mono">{m(a.measured_distance_m!)}</strong> · {t('rule', 'नियम')} <span className="mono">{m(a.threshold_m!)}</span><small>{sample ? t('sample distance · reference threshold', 'नमूना दूरी · संदर्भ सीमा') : t('measured distance · supplied threshold', 'मापी गई दूरी · दी गई सीमा')}</small></> : <>{t('Not assessed', 'आकलन नहीं हुआ')}</>;
  }
  const people = k.exposure ? <><strong className="mono">{number(k.exposure.people)}</strong> {t('people', 'लोग')} · {sample ? `${t('within', 'दायरे में')} ${m(k.exposure.radius_m)}` : t('within 800 m of the kiln edge', 'भट्ठे के किनारे से 800 मीटर के भीतर')}</> : sample ? t('Exposure estimate not available', 'जनसंख्या प्रभाव का अनुमान उपलब्ध नहीं') : t('Exposure not assessed', 'जनसंख्या प्रभाव का आकलन नहीं हुआ');
  // New labels need native Hindi review.
  return <section className="card glance" aria-label={t('At a glance', 'एक नज़र में')}><p className="eyebrow">{t('At a glance', 'एक नज़र में')}</p><dl>
    <div><dt>{t('Rule', 'नियम')}</dt><dd>{rule}</dd></div>
    <div><dt>{t('People', 'लोग')}</dt><dd>{people}</dd></div>
    <div><dt>{t('Latest observation', 'नवीनतम अवलोकन')}</dt><dd>{date(k.last_seen)}</dd></div>
  </dl></section>;
}

function Checks({ kiln }: { kiln: Kiln }) {
  const { t, number } = useLocale(); const phone = usePhone();
  const checks = kiln.checks ?? [];
  const note = kiln.rules_assessment === 'partially_evaluated' ? t('Some rules could not be checked from map data. Check on site.', 'कुछ नियम मानचित्र डेटा से जाँचे नहीं जा सके। स्थल पर जाँच करें।')
    : kiln.rules_assessment === 'not_evaluated' ? t('Rules not evaluated. No usable assessment is available.', 'नियमों का मूल्यांकन नहीं हुआ। उपयोगी आकलन उपलब्ध नहीं है।')
    : kiln.rules_assessment === 'evaluated' && checks.length ? null : t('Rule assessment unavailable. Check on site.', 'नियमों का आकलन उपलब्ध नहीं। स्थल पर जाँच करें।');
  return <>
    {note && <p className="help">{note}</p>}
    {checks.length > 0 && !flags(kiln).length && <p className="notice">{t('No siting flag from mapped data. This does not mean the site passed: map data is incomplete and the site still needs inspection.', 'मानचित्र डेटा से कोई स्थान संबंधी संकेत नहीं मिला। इसका अर्थ यह नहीं कि स्थल नियमों पर खरा है: मानचित्र डेटा अधूरा है और स्थल का निरीक्षण अभी आवश्यक है।')}</p>}
    {(phone ? flags(kiln) : checks).map(c => card(c))}
    {phone && checks.length > flags(kiln).length && <details className="other-checks"><summary>{t('Other rule checks', 'अन्य नियम जाँच')} · {number(checks.length - flags(kiln).length)}</summary>{checks.filter(c => c.status !== 'within_threshold').map(c => card(c))}</details>}
  </>;
  function card(c: RuleCheck) {
      const bar = c.measured_distance_m !== null && c.threshold_m && (c.status === 'within_threshold' || c.status === 'beyond_threshold');
      return <article className="rule-card" key={c.rule_id}>
        <Link className="citation mono" to={`/rules/${c.rule_id}?kiln=${encodeURIComponent(kiln.id)}`}>{c.rule_id} <Arrow /></Link>
        <h3>{c.check}</h3>
        <p><strong>{t(...(CHECK_STATUS[c.status] ?? UNKNOWN_CHECK))}</strong></p>
        {c.threshold_m !== null && c.status !== 'not_evaluated' && c.status !== 'not_applicable' && <div className="rule-measure"><strong className="mono">{c.measured_distance_m === null ? '—' : `${number(c.measured_distance_m)} ${t('m', 'मी')}`}</strong><span>{t('nearest mapped feature, from the kiln edge · threshold', 'भट्ठे के किनारे से निकटतम मानचित्रित स्थान · सीमा')} <b className="mono">{number(c.threshold_m)} {t('m', 'मी')}</b></span></div>}
        {bar && <div className={`distance-bar${c.status === 'within_threshold' ? '' : ' neutral'}`} aria-hidden="true"><span style={{ width: `${Math.min(100, c.measured_distance_m! / c.threshold_m! * 100)}%` }} /><i /></div>}
        {c.measured_distance_m === null && c.threshold_m !== null && (c.status === 'beyond_threshold' || c.status === 'inconclusive') && <p className="help">{t('No mapped feature was found within the search distance.', 'खोज की दूरी के भीतर कोई मानचित्रित स्थान नहीं मिला।')}</p>}
        <p className="help">{t(...((c.verification && VERIFICATION[c.verification]) || UNKNOWN_VERIFICATION))} · {c.source}</p>
      </article>;
  }
}

function LiveRulePage({ id }: { id: string }) {
  const [params] = useSearchParams(); const kilnId = params.get('kiln') ?? ''; const { t, number } = useLocale();
  const r = useResource(signal => kilnId ? client.detail(kilnId, signal) : Promise.resolve(null), `${id}:${kilnId}`);
  const back = <Link className="back-link" to={kilnId ? `/kilns/${encodeURIComponent(kilnId)}` : '/area'}>← {kilnId ? t('Back to the record', 'रिकॉर्ड पर वापस जाएँ') : t('Check an area', 'क्षेत्र की जाँच')}</Link>;
  if (r.error) return <div className="page narrow"><ErrorState error={r.error} retry={r.retry} /></div>;
  if (kilnId && !r.value) return <div className="page"><Loading /></div>;
  const c = r.value?.checks?.find(x => x.rule_id === id);
  if (!c) return <article className="page narrow prose">{back}<p className="eyebrow">{t('Rule reference', 'नियम का संदर्भ')}</p><p className="citation mono">{id}</p><h1>{t('Rule details come from a kiln record', 'नियम का विवरण भट्ठे के रिकॉर्ड से आता है')}</h1><p className="lead">{t('The public registry publishes each rule check with a kiln record. Open a record and follow its rule ID to see the threshold, measured distance and source.', 'सार्वजनिक रजिस्ट्री हर नियम की जाँच भट्ठे के रिकॉर्ड के साथ प्रकाशित करती है। सीमा, मापी गई दूरी और स्रोत देखने के लिए कोई रिकॉर्ड खोलें और उसके नियम ID पर जाएँ।')}</p></article>;
  const verification = t(...((c.verification && VERIFICATION[c.verification]) || UNKNOWN_VERIFICATION));
  return <article className="page narrow prose">{back}<p className="eyebrow">{t('Rule check from a kiln record', 'भट्ठे के रिकॉर्ड से नियम की जाँच')}</p><p className="citation mono">{c.rule_id}</p><h1>{c.check}</h1><p className="mono record-code">{kilnId}</p>
    <dl><div><dt>{t('Result', 'परिणाम')}</dt><dd>{t(...(CHECK_STATUS[c.status] ?? UNKNOWN_CHECK))}</dd></div><div><dt>{t('Threshold', 'सीमा')}</dt><dd>{c.threshold_m === null ? t('No distance threshold applied', 'कोई दूरी सीमा लागू नहीं') : `${number(c.threshold_m)} ${t('m', 'मी')}`}</dd></div><div><dt>{t('Measured distance', 'मापी गई दूरी')}</dt><dd>{c.measured_distance_m === null ? t('None measured', 'माप नहीं') : `${number(c.measured_distance_m)} ${t('m from the kiln edge to the nearest mapped feature', 'मी, भट्ठे के किनारे से निकटतम मानचित्रित स्थान तक')}`}</dd></div><div><dt>{t('Threshold source', 'सीमा का स्रोत')}</dt><dd>{c.source}</dd></div><div><dt>{t('Verification', 'पुष्टि')}</dt><dd>{verification}</dd></div></dl>
    <section className="notice"><h2>{t('Before drawing a conclusion', 'निष्कर्ष से पहले')}</h2><p>{t('A rule check is a siting signal from mapped data, pending inspection. An authority must establish the rules that apply to a site.', 'नियम की जाँच मानचित्र डेटा से मिला स्थान संबंधी संकेत है, जिसका निरीक्षण लंबित है। स्थल पर लागू नियम संबंधित प्राधिकरण को स्थापित करने हैं।')}</p></section></article>;
}

export function RulePage() {
  const { id = '' } = useParams();
  return config.mode === 'live' ? <LiveRulePage id={id} /> : <FixtureRulePage id={id} />;
}
function FixtureRulePage({ id }: { id: string }) {
  const { t, local } = useLocale();
  const r = useResource(signal => client.rule(id, signal), id);
  if (r.error) return <div className="page narrow"><ErrorState error={r.error} retry={r.retry} /></div>;
  if (!r.value) return <div className="page"><Loading /></div>;
  const rule = r.value;
  return <article className="page narrow prose"><Link className="back-link" to="/area">← {t('Check an area', 'क्षेत्र की जाँच')}</Link><p className="eyebrow">{t('Rule reference', 'नियम का संदर्भ')}</p><p className="citation mono">{rule.id}</p><h1>{local(rule.name)}</h1><p className="lead">{local(rule.explanation)}</p><dl><div><dt>{t('Jurisdiction', 'अधिकार क्षेत्र')}</dt><dd>{local(rule.jurisdiction)}</dd></div><div><dt>{t('Reference date', 'संदर्भ तिथि')}</dt><dd>{rule.effective_date ?? t('Not supplied', 'नहीं दिया गया')}</dd></div><div><dt>{t('Threshold for this portal', 'इस पोर्टल के लिए सीमा')}</dt><dd>{rule.threshold_m === null ? t('Not established', 'स्थापित नहीं') : `${rule.threshold_m} m · ${config.mode === 'fixture' ? t('sample reference only', 'केवल नमूना संदर्भ') : t('reference only', 'केवल संदर्भ')}`}</dd></div></dl><section className="notice"><h2>{t('Before drawing a conclusion', 'निष्कर्ष से पहले')}</h2><p>{local(rule.limitation)}</p></section><h2>{t('Source', 'स्रोत')}</h2><p>{rule.source_title}</p>{safeSource(rule.source_url) ? <a href={safeSource(rule.source_url)} target="_blank" rel="noreferrer">{t('Open official notification (PDF)', 'आधिकारिक अधिसूचना खोलें (PDF)')} <Arrow /></a> : <p>{t('An approved source link is not available.', 'स्वीकृत स्रोत लिंक उपलब्ध नहीं है।')}</p>}<p className="help">{t('An authority must establish the current rules applicable to a site. A rule reference is not an inspection finding.', 'स्थल पर लागू वर्तमान नियम संबंधित प्राधिकरण को स्थापित करने हैं। नियम का संदर्भ निरीक्षण का निष्कर्ष नहीं है।')}</p></article>;
}
