import { Link } from 'react-router-dom';
import { useEffect, useState, type ReactNode } from 'react';
import { DataError, type Kiln } from '../data/model';
import { useLocale } from '../i18n';

export function Arrow() { return <span aria-hidden="true">↗</span>; }
export function Status({ kiln }: { kiln: Kiln }) {
  const { t } = useLocale();
  const values: Record<string, [string, string, string]> = {
    flagged: ['⚑', 'Flagged by satellite · pending inspection', 'उपग्रह से चिह्नित · निरीक्षण लंबित'],
    confirmed: ['!', 'Confirmed violation', 'पुष्ट उल्लंघन'], compliant: ['✓', 'Compliant', 'नियमों के अनुरूप'],
    not_a_kiln: ['⊘', 'Not a kiln', 'भट्ठा नहीं'], closed: ['Ⅱ', 'Closed or not firing', 'बंद या चालू नहीं'],
  };
  const status = kiln.status === 'flagged' || kiln.human_reviewed ? kiln.status : 'unknown';
  const value = values[status] ?? ['?', 'Status not available', 'स्थिति उपलब्ध नहीं'];
  return <span className={`status status-${values[status] ? status : 'unknown'}`}><span aria-hidden="true">{value[0]}</span><span>{t(value[1], value[2])}</span></span>;
}
export function ErrorState({ error, retry }: { error: DataError; retry?: () => void }) {
  const { t } = useLocale();
  const descriptions: Record<string, [string, string]> = {
    configuration: ['Public service is not configured. The local sample experience is available only in explicit sample mode.', 'सार्वजनिक सेवा कॉन्फ़िगर नहीं है। स्थानीय नमूने केवल नमूना मोड में उपलब्ध हैं।'],
    malformed: ['This response could not be read safely. Please retry.', 'इस उत्तर को सुरक्षित रूप से नहीं पढ़ा जा सका। फिर कोशिश करें।'],
    not_found: ['This public record is not available. It may not be published.', 'यह सार्वजनिक रिकॉर्ड उपलब्ध नहीं है। हो सकता है यह प्रकाशित न हो।'],
    throttled: ['The service is busy. Wait a moment before retrying.', 'सेवा व्यस्त है। फिर कोशिश करने से पहले थोड़ा रुकें।'],
    pagination: ['Results changed while loading. Search again for a consistent set.', 'लोड होते समय परिणाम बदल गए। एक समान सूची के लिए फिर खोजें।'],
    timeout: ['The request took too long. Your input is still here.', 'अनुरोध में अधिक समय लगा। आपकी दर्ज जानकारी सुरक्षित है।'],
    unavailable: ['The service is unavailable. Your input is still here; try again.', 'सेवा उपलब्ध नहीं है। आपकी दर्ज जानकारी सुरक्षित है; फिर कोशिश करें।'],
  };
  const message = descriptions[error.code] ?? descriptions.unavailable;
  return <div className="notice error" role="alert"><strong>{t('Unable to load', 'लोड नहीं हो सका')}</strong><p>{t(...message)}</p>{retry && <button className="secondary" onClick={retry}>{t('Try again', 'फिर कोशिश करें')}</button>}<Link to="/">{t('Check another area', 'दूसरे क्षेत्र की जाँच करें')} <Arrow /></Link></div>;
}
export function Loading() { const { t } = useLocale(); return <div className="loading" role="status"><span className="loading-mark" />{t('Loading records…', 'रिकॉर्ड लोड हो रहे हैं…')}</div>; }
export function Empty({ children }: { children: ReactNode }) { return <div className="empty">{children}</div>; }
export function useResource<T>(load: (signal: AbortSignal) => Promise<T>, key: string) {
  const [value, setValue] = useState<T | null>(null), [error, setError] = useState<DataError | null>(null), [attempt, setAttempt] = useState(0);
  useEffect(() => {
    const controller = new AbortController(); setValue(null); setError(null);
    load(controller.signal).then(v => { if (!controller.signal.aborted) setValue(v); }).catch(e => { if (!controller.signal.aborted) setError(e instanceof DataError ? e : new DataError('unavailable')); });
    return () => controller.abort();
    // Callers provide an immutable resource key; callbacks close over that key only.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key, attempt]);
  return { value, error, retry: () => setAttempt(x => x + 1) };
}
