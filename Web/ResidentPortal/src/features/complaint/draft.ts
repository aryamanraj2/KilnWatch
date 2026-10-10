import { assessed, safeImage, safeSource, type Kiln, type Language, type Point } from '../../data/model';
import { config } from '../../data/client';
import type { DraftFields } from '../../app/state';
export function describe(kiln: Kiln, language: Language, sample = config.mode === 'fixture'): string {
  const hi = language === 'hi';
  const prediction = ['FCBK', 'CFCBK', 'Zigzag'].includes(kiln.prediction.type) ? kiln.prediction.type : hi ? 'अज्ञात प्रकार' : 'unknown type';
  const known = kiln.assessments.filter(assessed);
  return hi
    ? `${kiln.id}: मॉडल का अनुमान ${prediction} है; स्थल पर पुष्टि आवश्यक है। ${known.length ? `${known.length} ${sample ? 'नमूना ' : ''}दूरी आकलन उपलब्ध है।` : 'दूरी नियमों का आकलन उपलब्ध नहीं है।'} ${kiln.exposure ? `${sample ? 'नमूना ' : ''}जनसंख्या अनुमान उपलब्ध है; यह स्वास्थ्य प्रभाव का माप नहीं है।` : 'जनसंख्या प्रभाव का अनुमान उपलब्ध नहीं है।'}`
    : `${kiln.id}: the model predicts ${prediction}; confirm on site. ${known.length ? `${known.length} ${sample ? 'sample ' : ''}distance assessment is available.` : 'Assessed distance rules are not available.'} ${kiln.exposure ? `A ${sample ? 'sample ' : ''}population estimate is available; it is not a measurement of health impact.` : 'Exposure estimate not available.'}`;
}
export function missingFacts(k: Kiln, lang: Language): string[] {
  const t = (en: string, hi: string) => lang === 'hi' ? hi : en;
  return [
    ...(!k.prediction.verified ? [t('Kiln type, fuel, and current operation need an on-site check.', 'भट्ठे के प्रकार, ईंधन और मौजूदा संचालन की स्थल पर जाँच आवश्यक है।')] : []),
    ...(k.assessments.some(a => !assessed(a)) ? [t('Some rules have not been assessed. The applicable threshold and measured feature must be established.', 'कुछ नियमों का आकलन नहीं हुआ है। लागू दूरी सीमा और माप का आधार स्थापित करना आवश्यक है।')] : []),
    ...(!k.exposure ? [t('Exposure estimate not available.', 'जनसंख्या प्रभाव का अनुमान उपलब्ध नहीं है।')] : []),
    ...(!k.evidence.before || !k.evidence.after ? [t('A complete evidence pair is not available.', 'साक्ष्य के दोनों चित्र उपलब्ध नहीं हैं।')] : []),
  ];
}
export function makeDraft(records: Kiln[], fields: DraftFields, language: Language, center: Point | null, origin: string, sample: boolean): string {
  const t = (en: string, hi: string) => language === 'hi' ? hi : en;
  const date = (d: string) => new Intl.DateTimeFormat(language === 'hi' ? 'hi-IN' : 'en-IN', { dateStyle: 'long', timeZone: 'Asia/Kolkata' }).format(new Date(d));
  const sections = [
    t('Request for inspection', 'निरीक्षण का अनुरोध'),
    t('To the relevant inspecting authority (recipient to be confirmed)', 'संबंधित निरीक्षण प्राधिकरण को (प्राप्तकर्ता की पुष्टि बाकी)'),
    t('Please inspect the records listed below and establish the site conditions and applicable rules. Satellite flags require inspection; they are not findings. Model predictions remain provisional.', 'कृपया नीचे दिए गए रिकॉर्ड की जाँच करके स्थल की स्थिति और लागू नियम निर्धारित करें। उपग्रह के संकेतों की जाँच आवश्यक है; वे निष्कर्ष नहीं हैं। मॉडल के अनुमान की पुष्टि बाकी है।'),
    ...records.map(k => {
      const statuses: Record<string, string> = { confirmed: t('Confirmed violation', 'पुष्ट उल्लंघन'), compliant: t('Compliant', 'नियमों के अनुरूप'), not_a_kiln: t('Not a kiln', 'भट्ठा नहीं'), closed: t('Closed or not firing', 'बंद या चालू नहीं') };
      const status = k.status === 'flagged' ? t('Flagged by satellite · pending inspection', 'उपग्रह से चिह्नित · निरीक्षण लंबित') : k.human_reviewed && statuses[k.status] ? `${sample ? t('Fictitious human-reviewed example', 'मानव-समीक्षित काल्पनिक उदाहरण') + ': ' : ''}${statuses[k.status]}` : t('Status not available', 'स्थिति उपलब्ध नहीं');
      return [k.id, status, `${t('Latest observation', 'नवीनतम अवलोकन')}: ${date(k.last_seen)}${sample ? t(' (sample date)', ' (नमूना तिथि)') : ''}`, `${t(sample ? 'Local sample record' : 'Public record', sample ? 'स्थानीय नमूना रिकॉर्ड' : 'सार्वजनिक रिकॉर्ड')}: ${origin}/kilns/${encodeURIComponent(k.id)}`, describe(k, language, sample), ...k.assessments.filter(assessed).map(a => `${sample ? t('Sample assessed distance', 'नमूना आकलित दूरी') : t('Assessed distance', 'आकलित दूरी')} · ${a.rule_id}: ${a.measured_distance_m} m / ${t('threshold', 'सीमा')} ${a.threshold_m} m. ${t('Please confirm applicability and measurement on site.', 'कृपया स्थल पर लागू नियम और माप की पुष्टि करें।')} ${safeSource(a.source_url)}`), ...missingFacts(k, language), t('Evidence references (links only; no images attached):', 'साक्ष्य संदर्भ (केवल लिंक; चित्र संलग्न नहीं हैं):'), ...(['before', 'after'] as const).flatMap(side => { const image = k.evidence[side]; const url = image && safeImage(image.url, sample, config.imageHosts); return image && url ? [`${side === 'before' ? t('Before', 'पहले') : t('After', 'बाद में')}: ${sample ? origin + url : url} · ${image.acquired_at ? date(image.acquired_at) : t('date unknown', 'तिथि अज्ञात')} · ${image.source[language]}`] : [t('Image reference unavailable.', 'चित्र का संदर्भ उपलब्ध नहीं है।')]; })].join('\n');
    }),
    fields.observations.trim() ? `${t('Resident observations (not satellite findings)', 'निवासी के अवलोकन (उपग्रह के निष्कर्ष नहीं)')}:\n${fields.observations.trim()}` : t('No personal observations supplied.', 'व्यक्तिगत अवलोकन नहीं दिए गए।'),
    ...(fields.includeLocation && center ? [`${t('Location included at my request', 'मेरे अनुरोध पर शामिल स्थान')}: ${center[1].toFixed(5)}, ${center[0].toFixed(5)}`] : []),
    ...(fields.name.trim() ? [`${t('Name', 'नाम')}: ${fields.name.trim()}`] : []),
    ...(fields.contact.trim() ? [`${t('Contact', 'संपर्क')}: ${fields.contact.trim()}`] : []),
    t('Please verify the missing information through an authorised inspection. This draft makes no claim about measured emissions, health harm, construction date, or an unverified violation.', 'कृपया अधिकृत निरीक्षण से अनुपलब्ध जानकारी की पुष्टि करें। यह मसौदा मापे गए उत्सर्जन, स्वास्थ्य हानि, निर्माण तिथि या अपुष्ट उल्लंघन का दावा नहीं करता।'),
  ];
  return sections.join('\n\n');
}
export function exportText(body: string, lang: Language, sample: boolean): string {
  return `${sample ? (lang === 'hi' ? 'नमूना डेटा · केवल प्रदर्शन के लिए · वास्तविक शिकायत नहीं\n\n' : 'SAMPLE DATA · DEMONSTRATION ONLY · NOT A REAL COMPLAINT\n\n') : ''}${body}\n\n${lang === 'hi' ? 'केवल मसौदा। किसी प्राधिकरण को भेजा नहीं गया।' : 'Draft only. Not submitted to any authority.'}\n`;
}
