import { useRef, useState, type FormEvent } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { client, config } from '../../data/client';
import { AskError, KILN_ID, type AskAnswer } from '../../data/live';
import { useLocale } from '../../i18n';
import { Arrow } from '../../components/shared';
import { useApp } from '../../app/state';

// Resident assistant (concept Agent 3): the same public POST /ask the iOS app uses.
export function AskPage() {
  const { t, language } = useLocale();
  const { query, form } = useApp();
  const questionField = useRef<HTMLTextAreaElement>(null);
  const [params] = useSearchParams(); const raw = params.get('kiln'); const kilnId = raw && KILN_ID.test(raw) ? raw : null;
  const [question, setQuestion] = useState(''), [pending, setPending] = useState(false);
  const [answer, setAnswer] = useState<AskAnswer | null>(null), [error, setError] = useState<AskError | null>(null);
  const busy = useRef(false);
  const live = config.mode === 'live', length = question.trim().length;
  async function submit(e?: FormEvent) {
    e?.preventDefault();
    if (busy.current || !live) return; // One request at a time; never retried automatically.
    if (!length || length > 500) { setError(new AskError('invalid', false)); return; }
    busy.current = true; setPending(true); setError(null); setAnswer(null);
    try { setAnswer(await client.ask(question, kilnId, undefined, query?.center)); }
    catch (err) { setError(err instanceof AskError ? err : new AskError('network', true)); }
    finally { busy.current = false; setPending(false); }
  }
  const messages: Record<string, [string, string]> = {
    invalid: ['Enter a question of 1 to 500 characters. Your draft is still here.', '1 से 500 अक्षरों का प्रश्न लिखें। आपका मसौदा सुरक्षित है।'],
    cap: ['Ask has reached today’s limit. It resets at 05:30 IST (00:00 UTC).', 'आज के प्रश्नों की सीमा पूरी हो गई है। यह 05:30 IST (00:00 UTC) पर फिर शुरू होगी।'],
    busy: ['Too many questions, wait a moment and try again.', 'बहुत अधिक प्रश्न आए हैं, थोड़ा रुककर फिर कोशिश करें।'],
    unavailable: ['The assistant is unavailable right now.', 'सहायक अभी उपलब्ध नहीं है।'],
    model: ['The assistant could not reach its model. Your question is kept; try again shortly.', 'सहायक अपने मॉडल तक नहीं पहुँच सका। आपका प्रश्न सुरक्षित है; थोड़ी देर में फिर कोशिश करें।'],
    registry: ['The assistant could not read the public kiln records. Your question is kept; try again shortly.', 'सहायक सार्वजनिक भट्ठा रिकॉर्ड नहीं पढ़ सका। आपका प्रश्न सुरक्षित है; थोड़ी देर में फिर कोशिश करें।'],
    timeout: ['The answer took too long. Your question is kept. Try again when you are ready.', 'उत्तर में बहुत समय लगा। आपका प्रश्न सुरक्षित है। तैयार होने पर फिर कोशिश करें।'],
    network: ['The question could not be sent. Check your connection.', 'प्रश्न भेजा नहीं जा सका। अपना कनेक्शन जाँचें।'],
    malformed: ['The answer could not be read safely.', 'उत्तर को सुरक्षित रूप से नहीं पढ़ा जा सका।'],
    configuration: ['Ask needs the public service. It is not available with sample data.', 'प्रश्न पूछने के लिए सार्वजनिक सेवा चाहिए। यह नमूना डेटा के साथ उपलब्ध नहीं है।'],
  };
  const citations = answer?.citations.filter(id => KILN_ID.test(id)) ?? [];
  return <div className="page narrow ask-page">
    <h1>{t('Ask KilnWatch', 'KilnWatch से पूछें')}</h1>
    {kilnId && <p>{t('Asking about', 'इसके बारे में पूछ रहे हैं')} <Link className="citation mono" to={`/kilns/${kilnId}`}>{kilnId}</Link></p>}
    {live && query && <p className="help">{t('Using your confirmed search centre', 'आपकी पुष्टि की गई खोज के केंद्र का उपयोग')} · <span className="mono">{form.label || `${query.center[1].toFixed(5)}, ${query.center[0].toFixed(5)}`}</span></p>}
    {!live && <p className="notice">{t(...messages.configuration)}</p>}
    {/* Needs native review. */}
    {language === 'hi' && <p className="notice" lang="hi">उत्तर केवल अंग्रेज़ी में मिलते हैं। आप प्रश्न हिन्दी या अंग्रेज़ी में लिख सकते हैं।</p>}
    <form className="card ask-form" onSubmit={submit} noValidate>
      <label htmlFor="ask-question">{t('Your question', 'आपका प्रश्न')}</label>
      <textarea ref={questionField} id="ask-question" rows={3} value={question} disabled={!live} onChange={e => setQuestion(e.target.value)} aria-describedby="ask-count ask-line" placeholder={kilnId ? 'What should I check at this kiln?' : 'How many kilns are flagged in Hapur?'} />
      {live && !question && <div className="place-options"><button type="button" onClick={() => { setQuestion(kilnId ? 'What should I check at this kiln?' : 'How many kilns are flagged in Hapur?'); questionField.current?.focus(); }}>{t('Use this example question', 'इस उदाहरण प्रश्न का उपयोग करें')}</button></div>}
      <p className="help" id="ask-count"><span className="mono">{length}/500</span></p>
      <button className="primary" type="submit" disabled={!live || pending}>{pending ? t('Asking…', 'पूछ रहे हैं…') : t('Ask', 'पूछें')}</button>
      <p className="help" id="ask-line">{t('Answers cite public registry records. The assistant never records verdicts.', 'उत्तर सार्वजनिक रजिस्ट्री के रिकॉर्ड का हवाला देते हैं। सहायक कभी निर्णय दर्ज नहीं करता।')}</p>
    </form>
    {pending && <div className="loading" role="status"><span className="loading-mark" />{t('Looking up public records…', 'सार्वजनिक रिकॉर्ड देख रहे हैं…')}</div>}
    {error && <div className="notice error" role="alert"><strong>{t('Unable to answer', 'उत्तर नहीं मिल सका')}</strong><p>{t(...(messages[error.kind] ?? messages.unavailable))}</p>{error.retryable && error.kind !== 'invalid' && <button className="secondary" disabled={pending} onClick={() => void submit()}>{t('Try again', 'फिर कोशिश करें')}</button>}</div>}
    {answer && <section className="card ask-answer" aria-live="polite">
      {answer.steps.length > 0 && <details className="fact-details ask-trace"><summary>{t('Registry steps', 'रजिस्ट्री के चरण')} · {answer.steps.length}</summary><ol className="ask-steps">{answer.steps.map((s, i) => <li key={i}>{s.label}{s.summary ? ` · ${s.summary}` : ''}{!s.ok && ` · ${t('invalid tool input', 'अमान्य इनपुट')}`}</li>)}</ol></details>}
      {answer.fallback && <p className="notice">{t('The assistant could not produce a reliable answer. The records it looked up are listed below.', 'सहायक भरोसेमंद उत्तर नहीं दे सका। उसने जो रिकॉर्ड देखे, वे नीचे दिए गए हैं।')}</p>}
      <p className="ask-text" lang="en">{answer.answer}</p>
      {citations.length > 0 && <><h2 className="small-heading">{t('Cited records', 'उद्धृत रिकॉर्ड')}</h2><ul className="ask-citations">{citations.map(id => <li key={id}><Link className="citation mono" to={`/kilns/${id}`}>{id} <Arrow /></Link></li>)}</ul></>}
    </section>}
    {answer && <p className="help ask-disclaimer" lang="en">{answer.disclaimer}</p>}
  </div>;
}
