import { lazy, Suspense, useEffect, useState, type FormEvent } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useApp } from '../../app/state';
import { config } from '../../data/client';
import { parseCoordinate } from '../../data/geo';
import { point, type Localized, type Point } from '../../data/model';
import { useLocale } from '../../i18n';
import { Arrow, Empty, ErrorState, Loading, Status } from '../../components/shared';
const Diagram = lazy(() => import('./Diagram'));
type Place = { label: Localized; aliases: string; center: Point };

export function AreaPage() {
  const s = useApp(); const { t, local, number, date } = useLocale(); const navigate = useNavigate();
  const [places, setPlaces] = useState<Place[]>([]), [matches, setMatches] = useState<Place[]>([]);
  const [validation, setValidation] = useState(''), [locationState, setLocationState] = useState(''), [locating, setLocating] = useState(false);
  const [view, setView] = useState<'list' | 'map'>('list');
  useEffect(() => { if (config.mode === 'fixture') void import('../../data/fixtures').then(f => setPlaces(f.places)); }, []);
  useEffect(() => {
    const timer = setTimeout(() => { const term = s.form.place.trim().toLocaleLowerCase().normalize('NFC'); setMatches(term ? places.filter(p => p.aliases.includes(term) || local(p.label).toLocaleLowerCase().includes(term)) : places); }, 160);
    return () => clearTimeout(timer);
  }, [s.form.place, places, local]);
  function choose(p: Place) { s.setForm(f => ({ ...f, place: local(p.label), label: local(p.label), latitude: p.center[1].toFixed(5), longitude: p.center[0].toFixed(5), accuracy: null })); setValidation(''); setLocationState(''); }
  function updatePoint(p: Point) { s.setForm(f => ({ ...f, place: '', label: '', latitude: p[1].toFixed(5), longitude: p[0].toFixed(5), accuracy: null })); setValidation(t('New centre selected. Confirm the coordinates to search.', 'नया केंद्र चुना गया। खोजने के लिए निर्देशांक की पुष्टि करें।')); document.getElementById('latitude')?.focus(); }
  function submit(e: FormEvent) {
    e.preventDefault(); const center: Point = [parseCoordinate(s.form.longitude), parseCoordinate(s.form.latitude)];
    if (!point.safeParse(center).success) { setValidation(t('Enter latitude −90 to 90 and longitude −180 to 180, or choose a sample place.', 'अक्षांश −90 से 90 और देशांतर −180 से 180 दर्ज करें, या नमूना स्थान चुनें।')); document.getElementById('latitude')?.focus(); return; }
    setValidation(''); s.setQuery({ center, radius_m: s.form.radius }); navigate('/area');
  }
  function locate() {
    if (!navigator.geolocation) { setLocationState(t('Location is unavailable. Enter coordinates or choose a sample place.', 'स्थान उपलब्ध नहीं है। निर्देशांक दर्ज करें या नमूना स्थान चुनें।')); return; }
    setLocating(true); setLocationState('');
    navigator.geolocation.getCurrentPosition(p => {
      s.setForm(f => ({ ...f, latitude: p.coords.latitude.toFixed(5), longitude: p.coords.longitude.toFixed(5), accuracy: p.coords.accuracy, place: '', label: '' })); setLocating(false);
      setLocationState(t('Location received. Check the accuracy and confirm your area. Sample coverage may not include this location.', 'स्थान मिला। सटीकता देखें और क्षेत्र की पुष्टि करें। नमूना कवरेज में यह स्थान शामिल न हो सकता है।'));
    }, () => { setLocating(false); setLocationState(t('Location could not be used. You can still enter coordinates or choose a sample place.', 'स्थान का उपयोग नहीं हो सका। आप निर्देशांक दर्ज कर सकते हैं या नमूना स्थान चुन सकते हैं।')); }, { enableHighAccuracy: false, timeout: 8000, maximumAge: 0 });
  }
  return <div className="page area-page">
    <section className="intro"><div><p className="eyebrow">{t('A closer look at your surroundings', 'अपने आसपास को समझें')}</p><h1>{t('Check an area.', 'क्षेत्र की जाँच करें।')}<br /><span>{t('Understand the evidence.', 'साक्ष्य को समझें।')}</span></h1></div><p>{t('Find satellite-flagged candidates, see what is known, and prepare a request for inspection. A flag is a starting point, not a finding.', 'उपग्रह से चिह्नित संभावित भट्ठे देखें, उपलब्ध जानकारी समझें और निरीक्षण का अनुरोध तैयार करें। चिह्नित होना जाँच की शुरुआत है, निष्कर्ष नहीं।')}</p></section>
    <section className="workspace">
      <aside className="search-panel">
        <form onSubmit={submit} noValidate>
          <div className="section-heading"><span className="step-number">01</span><h2>{t('Choose your area', 'अपना क्षेत्र चुनें')}</h2></div>
          <label htmlFor="place">{t('Place or address', 'स्थान या पता')}</label><div className="search-input"><span aria-hidden="true">⌕</span><input id="place" autoComplete="off" value={s.form.place} onChange={e => s.setForm(f => ({ ...f, place: e.target.value }))} placeholder={t('Try Pilkhuwa', 'पिलखुवा खोजें')} aria-describedby="place-help" /></div>
          <p className="help" id="place-help">{config.mode === 'fixture' ? t('Sample places only. This search does not geocode real addresses.', 'केवल नमूना स्थान। यह खोज वास्तविक पतों के निर्देशांक नहीं ढूँढ़ती।') : t('Address search needs an approved provider. Enter coordinates below.', 'पते की खोज के लिए स्वीकृत सेवा चाहिए। नीचे निर्देशांक दर्ज करें।')}</p>
          {config.mode === 'fixture' && <div className="place-options">{matches.map(p => <button key={p.aliases} type="button" onClick={() => choose(p)}>{local(p.label)} <span aria-hidden="true">↳</span></button>)}{!matches.length && <p className="help">{t('No sample place matches. Use coordinates below.', 'कोई नमूना स्थान नहीं मिला। नीचे निर्देशांक दर्ज करें।')}</p>}</div>}
          <button className="location-button secondary" type="button" disabled={locating} onClick={locate}><span aria-hidden="true">⌾</span>{locating ? t('Locating…', 'स्थान खोज रहे हैं…') : t('Use my location', 'मेरा स्थान उपयोग करें')}</button>
          {locationState && <p className="help" role="status">{locationState}</p>}
          <div className="separator"><span>{t('or enter coordinates', 'या निर्देशांक दर्ज करें')}</span></div>
          <div className="coordinate-fields"><div><label htmlFor="latitude">{t('Latitude', 'अक्षांश')}</label><input id="latitude" inputMode="decimal" value={s.form.latitude} onChange={e => s.setForm(f => ({ ...f, latitude: e.target.value, accuracy: null }))} placeholder="28.73000" aria-describedby={validation ? 'area-validation' : undefined} /></div><div><label htmlFor="longitude">{t('Longitude', 'देशांतर')}</label><input id="longitude" inputMode="decimal" value={s.form.longitude} onChange={e => s.setForm(f => ({ ...f, longitude: e.target.value, accuracy: null }))} placeholder="77.68000" aria-describedby={validation ? 'area-validation' : undefined} /></div></div>
          {s.form.accuracy !== null && <p className="help">{t('Location accuracy: approximately', 'स्थान की सटीकता: लगभग')} {number(s.form.accuracy)} {t('metres. Adjust coordinates if needed.', 'मीटर। आवश्यकता हो तो निर्देशांक बदलें।')}</p>}
          <fieldset><legend>{t('Search radius', 'खोज का दायरा')}</legend><div className="radius-options">{[800, 1000, 2000, 5000].map(r => <label key={r}><input type="radio" name="radius" checked={s.form.radius === r} value={r} onChange={() => s.setForm(f => ({ ...f, radius: r }))} /><span>{number(r / 1000, 1)} {t('km', 'किमी')}</span></label>)}</div></fieldset>
          <p className="help">{t('This is a search area, not a legal buffer.', 'यह खोज का क्षेत्र है, नियम की दूरी सीमा नहीं।')}</p>
          {validation && <p id="area-validation" role="alert" className="field-error">{validation}</p>}
          <button className="primary full" type="submit">{t('Confirm area & search', 'क्षेत्र की पुष्टि करके खोजें')} <span aria-hidden="true">→</span></button>
          <p className="privacy-note">{t('Your coordinates stay in this session in sample mode.', 'नमूना मोड में आपके निर्देशांक इसी सत्र में रहते हैं।')}</p>
        </form>
      </aside>
      <section className="results-workspace" aria-label={t('Nearby results', 'आसपास के परिणाम')}>
        {!s.query ? <div className="start-state"><div className="survey-illustration" aria-hidden="true"><div /><span>+</span><i /><i /></div><p className="eyebrow">{t('Start with a place', 'एक स्थान से शुरू करें')}</p><h2>{t('Every record begins with a question.', 'हर रिकॉर्ड एक सवाल की शुरुआत है।')}</h2><p>{t('Choose the Pilkhuwa sample area to explore evidence, understand the gaps, and try an inspection draft.', 'साक्ष्य देखने, जानकारी की कमी समझने और निरीक्षण मसौदा बनाने के लिए पिलखुवा का नमूना क्षेत्र चुनें।')}</p><div className="journey-steps"><span>01 {t('Find', 'खोजें')}</span><span>02 {t('Understand', 'समझें')}</span><span>03 {t('Prepare', 'तैयार करें')}</span></div></div> : <>
          <div className="results-heading"><div><p className="eyebrow">{t('Your search area', 'आपका खोज क्षेत्र')}</p><h2>{number(s.query.radius_m / 1000, 1)} {t('km around your point', 'किमी आपके बिंदु के आसपास')}</h2><p className="mono small">{s.query.center[1].toFixed(5)}, {s.query.center[0].toFixed(5)}</p></div><div className="view-switch"><button aria-pressed={view === 'list'} onClick={() => setView('list')}>{t('List', 'सूची')}</button><button aria-pressed={view === 'map'} onClick={() => setView('map')}>{t('Map', 'मानचित्र')}</button></div></div>
          <div className={`results-content view-${view}`}>
            <div className="map-pane"><Suspense fallback={<Loading />}><Diagram query={s.query} page={s.page} selected={s.selected} onSelect={id => { s.setSelected(id); }} onPoint={updatePoint} /></Suspense>{s.selected && s.page && <div className="map-selection"><span className="mono">{s.selected}</span><Link to={`/kilns/${s.selected}`}>{t('Open selected record', 'चुना रिकॉर्ड खोलें')} <Arrow /></Link></div>}</div>
            <div className="list-pane">
              <div role="status" className="results-count">{s.page && <><strong>{number(s.page.items.length)} {t('results loaded', 'परिणाम लोड हुए')}</strong><span>{s.page.complete ? t('All returned records loaded', 'लौटाए गए सभी रिकॉर्ड लोड हुए') : t('More records available', 'और रिकॉर्ड उपलब्ध हैं')}</span></>}</div>
              {s.page && <p className="dataset-note">{config.mode === 'fixture' ? t('Sample dataset', 'नमूना डेटासेट') : t('Public dataset', 'सार्वजनिक डेटासेट')} · {date(s.page.updated_at)} · {s.page.coverage === 'known' ? t('Coverage supplied', 'कवरेज दिया गया') : t('Coverage unknown', 'कवरेज अज्ञात')}{Date.now() - Date.parse(s.page.updated_at) > 30 * 86400000 && <strong> · {t('Older dataset', 'पुराना डेटासेट')}</strong>}</p>}
              {s.error && <ErrorState error={s.error} retry={s.page ? s.more : s.retry} />}
              {s.page && !s.page.items.length && <Empty><h3>{t('No published candidates returned', 'कोई प्रकाशित संभावित भट्ठा नहीं मिला')}</h3><p>{s.page.coverage === 'known' ? t('No sample records match this area. This does not establish that there are no kilns or that an area is compliant.', 'इस क्षेत्र में कोई नमूना रिकॉर्ड नहीं मिला। इसका अर्थ यह नहीं कि यहाँ भट्ठे नहीं हैं या क्षेत्र नियमों के अनुरूप है।') : t('Coverage for this area is unknown. Try a sample place; an empty result is not evidence of clean air.', 'इस क्षेत्र का कवरेज अज्ञात है। नमूना स्थान चुनें; खाली परिणाम स्वच्छ हवा का प्रमाण नहीं है।')}</p></Empty>}
              <ol className="result-list">{s.page?.items.map(({ kiln, distance_m }, i) => <li key={kiln.id} className={s.selected === kiln.id ? 'is-selected' : ''}><div className="result-top"><button className="pin-number" aria-label={`${t('Select', 'चुनें')} ${kiln.id}`} aria-pressed={s.selected === kiln.id} onClick={() => s.setSelected(kiln.id)}>{i + 1}</button><div><Link className="record-id mono" to={`/kilns/${kiln.id}`}>{kiln.id} <Arrow /></Link><h3>{local(kiln.name)}</h3></div><span className="distance mono">{number(distance_m)} {t('m', 'मी')}</span></div><Status kiln={kiln} /><div className="result-meta"><span>{date(kiln.last_seen)}</span><span>{kiln.evidence.after || kiln.evidence.before ? t('Evidence reference', 'साक्ष्य संदर्भ') : t('No imagery', 'चित्र नहीं')}</span></div><p className="help">{t('Distance to sample centroid · predicted type:', 'नमूना केंद्र तक दूरी · अनुमानित प्रकार:')} {['FCBK', 'CFCBK', 'Zigzag'].includes(kiln.prediction.type) ? kiln.prediction.type : t('unknown', 'अज्ञात')} · {t('confirm on site', 'स्थल पर पुष्टि करें')}</p></li>)}</ol>
              {s.loading && <Loading />}{s.page?.next_cursor && !s.loading && <button className="secondary full" onClick={s.more}>{t('Load more records', 'और रिकॉर्ड लोड करें')}</button>}
            </div>
          </div>
        </>}
      </section>
    </section>
    <div className="area-bottom"><p><strong>{t('A satellite flag is not a verdict.', 'उपग्रह का संकेत निर्णय नहीं है।')}</strong> {t('Only an authorised inspection can establish a finding.', 'केवल अधिकृत निरीक्षण से निष्कर्ष स्थापित हो सकता है।')}</p><Link to="/about">{t('How KilnWatch works', 'KilnWatch कैसे काम करता है')} <Arrow /></Link></div>
  </div>;
}
