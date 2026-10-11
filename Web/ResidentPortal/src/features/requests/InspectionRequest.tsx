import { useRef, useState, useSyncExternalStore } from 'react';
import { client, config } from '../../data/client';
import type { Kiln } from '../../data/model';
import { browserCode, concernValues, distanceValues, freshRequests, rememberRequest, RequestError, sentOn, subscribeRequests, type RequestBody } from '../../data/requests';
import { useLocale } from '../../i18n';

const concernLabels: Record<RequestBody['concerns'][number], [string, string]> = {
  smoke_or_ash: ['Smoke or ash', 'धुआँ या राख'], near_homes: ['Near homes', 'घरों के पास'], near_school_or_hospital: ['Near a school or hospital', 'स्कूल या अस्पताल के पास'], other: ['Other concern', 'अन्य चिंता'],
};
const distanceLabels: Record<RequestBody['distance_band'], [string, string]> = {
  under_1km: ['Under 1 km', '1 किमी से कम'], '1_to_5km': ['1 to 5 km', '1 से 5 किमी'], over_5km: ['Over 5 km', '5 किमी से अधिक'], not_said: ['Prefer not to say', 'बताना नहीं चाहता/चाहती'],
};
function useCount(kiln: Kiln) {
  const fresh = useSyncExternalStore(subscribeRequests, () => freshRequests(config.mode, kiln.id));
  return fresh && (!kiln.resident_requests || fresh.count >= kiln.resident_requests.count) ? fresh : kiln.resident_requests;
}
export function RequestCount({ kiln }: { kiln: Kiln }) {
  const count = useCount(kiln)?.count; const { t, number } = useLocale();
  return count ? <p className="request-count">{t(`${number(count)} inspection ${count === 1 ? 'request' : 'requests'} · not verified`, `${number(count)} निरीक्षण अनुरोध · पुष्टि नहीं हुई`)}</p> : null;
}
export function InspectionRequest({ kiln, open, onOpen }: { kiln: Kiln; open: boolean; onOpen: () => void }) {
  const { t, language, number } = useLocale();
  const [concerns, setConcerns] = useState<RequestBody['concerns']>([]);
  const [band, setBand] = useState<RequestBody['distance_band']>('not_said');
  const [busy, setBusy] = useState(false); const inFlight = useRef(false);
  const [error, setError] = useState<RequestError | null>(null);
  const [added, setAdded] = useState(false);
  const sent = useSyncExternalStore(subscribeRequests, () => sentOn(config.mode, kiln.id));
  const count = useCount(kiln)?.count;
  const residentsAsked = `${number(count ?? 0)} ${count === 1 ? 'resident has' : 'residents have'} asked for an inspection of this kiln.`;
  const sample = config.mode === 'fixture';
  const shortDate = (day: string) => new Intl.DateTimeFormat(language === 'hi' ? 'hi-IN' : 'en-IN', { day: 'numeric', month: 'short', timeZone: 'Asia/Kolkata' }).format(new Date(`${day}T12:00:00+05:30`));
  async function send() {
    if (inFlight.current || sent || !concerns.length) return;
    inFlight.current = true; setBusy(true); setError(null);
    try {
      const result = await client.request({ kiln_id: kiln.id, client_id: browserCode(config.mode), concerns, distance_band: band, lang: language });
      rememberRequest(config.mode, kiln.id, result.resident_requests); setAdded(result.created);
    } catch (e) { setError(e instanceof RequestError ? e : new RequestError('unavailable')); }
    finally { inFlight.current = false; setBusy(false); }
  }
  const limits = <p className="help">{t("Inspectors see this count in the KilnWatch inspector app. A request doesn't guarantee an inspection and doesn't change the kiln's status.", 'KilnWatch निरीक्षक ऐप में निरीक्षक यह संख्या देखते हैं। अनुरोध से निरीक्षण की गारंटी नहीं मिलती और भट्ठे की स्थिति नहीं बदलती।')}</p>;
  return <section id="resident-requests" className="card request-panel" aria-labelledby="request-heading">
    <h2 id="request-heading">{t('Resident requests', 'निवासियों के अनुरोध')}</h2>
    <RequestCount kiln={kiln} />
    {sample && <p className="sample-tag">{t('Sample request · nothing is sent', 'नमूना अनुरोध · कुछ भेजा नहीं जाता')}</p>}
    {sent ? <div role="status">
      <p className="request-confirmation">{added ? t(`Your request was added. ${residentsAsked}`, `आपका अनुरोध जोड़ा गया। ${number(count ?? 0)} निवासियों ने इस भट्ठे के निरीक्षण का अनुरोध किया है।`) : t(`You asked for an inspection on ${shortDate(sent)}`, `आपने ${shortDate(sent)} को निरीक्षण का अनुरोध किया था`)}</p>
      {!added && count !== undefined && <p>{t(residentsAsked, `${number(count)} निवासियों ने इस भट्ठे के निरीक्षण का अनुरोध किया है।`)}</p>}
      {limits}
    </div> : !open ? <><p className="help">{t('Anonymous inspection requests are a signal for KilnWatch inspectors. They are not verified.', 'अनाम निरीक्षण अनुरोध KilnWatch निरीक्षकों के लिए एक संकेत हैं। उनकी पुष्टि नहीं हुई है।')}</p><button className="primary full" onClick={onOpen}>{t('Request an inspection', 'निरीक्षण का अनुरोध करें')}</button></> : <form onSubmit={e => { e.preventDefault(); void send(); }}>
      <fieldset disabled={busy}><legend>{t('What concerns you? Choose at least one.', 'आपको किस बात की चिंता है? कम से कम एक चुनें।')}</legend>
        {concernValues.map(value => <label className="request-option" key={value}><input type="checkbox" checked={concerns.includes(value)} onChange={e => setConcerns(previous => e.target.checked ? [...previous, value] : previous.filter(c => c !== value))} />{t(...concernLabels[value])}</label>)}
      </fieldset>
      <fieldset disabled={busy}><legend>{t('Where do you live?', 'आप कहाँ रहते हैं?')}</legend>
        {distanceValues.map(value => <label className="request-option" key={value}><input type="radio" name={`request-distance-${kiln.id}`} value={value} checked={band === value} onChange={() => setBand(value)} />{t(...distanceLabels[value])}</label>)}
      </fieldset>
      <p className="help">{t('Anonymous. We store your answers and a random code from this browser, not your name, phone or location.', 'अनाम। हम आपके उत्तर और इस ब्राउज़र का एक यादृच्छिक कोड रखते हैं, आपका नाम, फ़ोन या स्थान नहीं।')}</p>
      {error && <p role="alert" className="request-error">{error.kind === 'cap' ? t("Today's request limit is reached. Try again tomorrow.", 'आज के अनुरोधों की सीमा पूरी हो गई है। कल फिर कोशिश करें।') : error.kind === 'not_found' ? t('This kiln record is no longer available.', 'इस भट्ठे का रिकॉर्ड अब उपलब्ध नहीं है।') : error.kind === 'busy' ? t('Too many requests. Your answers are kept; try again in a moment.', 'बहुत सारे अनुरोध आए हैं। आपके उत्तर सुरक्षित हैं; थोड़ी देर में फिर कोशिश करें।') : t("Couldn't send. Your answers are kept; try again.", 'भेज नहीं सके। आपके उत्तर सुरक्षित हैं; फिर कोशिश करें।')}</p>}
      <button className="primary full" disabled={!concerns.length || busy || error?.kind === 'not_found'}>{busy ? t('Sending…', 'भेज रहे हैं…') : t('Send request', 'अनुरोध भेजें')}</button>
    </form>}
  </section>;
}
