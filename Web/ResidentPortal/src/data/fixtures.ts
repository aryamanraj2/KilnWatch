import { kilnSchema, text, type Kiln, type Rule, type Point } from './model';
import { destination } from './geo';
export const CENTER: Point = [77.68, 28.73];
export const UPDATED = '2026-10-01T06:00:00Z';
export const SOURCE = 'https://mpcb.gov.in/sites/default/files/standing_orders/Environmental%20Standards%20for%20Brick%20Kilns%20vide%20notification.pdf';
export const places = [
  { label: text('Pilkhuwa · sample area', 'पिलखुवा · नमूना क्षेत्र'), aliases: 'pilkhuwa hapur पिलखुवा हापुड़ sample नमूना', center: CENTER },
  { label: text('Sample east · no records', 'पूर्व नमूना क्षेत्र · कोई रिकॉर्ड नहीं'), aliases: 'east empty पूर्व खाली', center: destination(CENTER, 3500, 90) },
];
export const rules: Rule[] = [
  { id: 'C-ORCH-800', name: text('Distance from fruit orchards', 'फलों के बागों से दूरी'), jurisdiction: text('Central reference · sample assessment only', 'केंद्रीय संदर्भ · केवल नमूना आकलन'), threshold_m: 800,
    explanation: text('The 2022 notification gives an 800 m siting distance from fruit orchards. State boards may set stricter criteria.', '2022 की अधिसूचना में फलों के बागों से 800 मीटर की दूरी दी गई है। राज्य बोर्ड अधिक कड़े मानदंड तय कर सकते हैं।'),
    limitation: text('The sample measurement demonstrates a comparison only. Local applicability and the nearest orchard require inspection; this is not a finding about a real site.', 'नमूना माप केवल तुलना दिखाता है। स्थानीय नियमों और निकटतम बाग की जाँच आवश्यक है; यह किसी वास्तविक स्थल का निष्कर्ष नहीं है।'), source_url: SOURCE, source_title: 'MoEF&CC · G.S.R. 143(E), note 6 · 22 February 2022', effective_date: '2022-02-22', applicability: 'sample_assessment' },
  { id: 'C-HAB-800', name: text('Distance from homes', 'आवासों से दूरी'), jurisdiction: text('Uttar Pradesh · applicability unresolved', 'उत्तर प्रदेश · लागू मानदंड की पुष्टि बाकी'), threshold_m: null,
    explanation: text('A search circle around you is not a kiln-to-habitation assessment. The UP threshold has not been confirmed for this portal.', 'आपके आसपास का खोज दायरा भट्ठे से आवास की दूरी का आकलन नहीं है। इस पोर्टल के लिए उत्तर प्रदेश के मानदंड की पुष्टि नहीं हुई है।'),
    limitation: text('Repository references disagree on 800 m and 1,000 m. No threshold or conclusion is applied here. Ask the authority to establish the applicable rule and measured distance.', 'परियोजना संदर्भों में 800 और 1,000 मीटर का अंतर है। यहाँ कोई सीमा या निष्कर्ष लागू नहीं किया गया है। संबंधित प्राधिकरण से लागू नियम और माप की जाँच का अनुरोध करें।'), source_url: SOURCE, source_title: 'MoEF&CC · G.S.R. 143(E), note 6 · central reference only', effective_date: '2022-02-22', applicability: 'reference_only' },
  { id: 'C-TECH-10K', name: text('Kiln technology', 'भट्ठे की तकनीक'), jurisdiction: text('Central reference · site verification required', 'केंद्रीय संदर्भ · स्थल पर पुष्टि आवश्यक'), threshold_m: null,
    explanation: text('Satellite shape can suggest a kiln type. It cannot verify fuel, technology, or whether the kiln is operating.', 'उपग्रह में दिखाई देने वाला आकार भट्ठे के प्रकार का संकेत दे सकता है। इससे ईंधन, तकनीक या संचालन की पुष्टि नहीं होती।'),
    limitation: text('No technology assessment has been performed. Model scores are not independent proof of type or compliance.', 'तकनीक का आकलन नहीं किया गया है। मॉडल का स्कोर प्रकार या अनुपालन का स्वतंत्र प्रमाण नहीं है।'), source_url: SOURCE, source_title: 'MoEF&CC · G.S.R. 143(E), notes 1–2', effective_date: '2022-02-22', applicability: 'reference_only' },
];
const before = { url: '/samples/before.svg', acquired_at: '2023-12-05T05:40:00Z', source: text('KilnWatch synthetic scene · not satellite imagery', 'KilnWatch काल्पनिक दृश्य · उपग्रह चित्र नहीं'), resolution_m: null, width: 256 as const, height: 256 as const, outline_px: null };
const after = { ...before, url: '/samples/after.svg', acquired_at: '2026-10-01T05:40:00Z', outline_px: [[94, 109], [151, 87], [176, 142], [117, 168]] as Point[] };
export const kilns: Kiln[] = Array.from({ length: 7 }, (_, i) => {
  const centroid = destination(CENTER, [290, 450, 590, 720, 850, 940, 1420][i], [35, 130, 230, 285, 80, 190, 335][i]);
  return kilnSchema.parse({
    id: `SAMPLE-KW-00${i + 1}`, name: [text('Orchard edge', 'बाग के किनारे'), text('Eastern fields', 'पूर्वी खेत'), text('South field', 'दक्षिणी खेत'), text('Western plot', 'पश्चिमी भूखंड'), text('Canal-side plot', 'नहर के पास'), text('Southern plot', 'दक्षिणी भूखंड'), text('Northern field', 'उत्तरी खेत')][i],
    centroid, footprint: [...[45, 135, 225, 315, 45].map(b => destination(centroid, 48, b))],
    status: ['flagged', 'flagged', 'flagged', 'unclassified', 'compliant', 'closed', 'flagged'][i], human_reviewed: i === 4 || i === 5,
    last_seen: UPDATED, revision: 'sample-1', prediction: { type: i === 3 ? 'unclassified' : i === 1 ? 'Zigzag' : 'FCBK', score: i === 3 ? null : 0.82, verified: false },
    evidence: { before: i === 0 || i >= 4 ? before : null, after: i !== 3 ? after : null },
    assessments: [
      ...([0, 4, 6].includes(i) ? [{ rule_id: 'C-ORCH-800', state: 'assessed', measured_distance_m: [520, 0, 0, 0, 1120, 0, 640][i], threshold_m: 800, source_url: SOURCE }] : []),
      { rule_id: 'C-HAB-800', state: 'not_evaluated', measured_distance_m: null, threshold_m: null, source_url: null },
      { rule_id: 'C-TECH-10K', state: 'not_evaluated', measured_distance_m: null, threshold_m: null, source_url: null },
    ],
    exposure: [0, 1, 4, 6].includes(i) ? { people: [1240, 860, 0, 0, 420, 0, 1780][i], radius_m: 800, source: text('Synthetic population example · not a measured health impact', 'काल्पनिक जनसंख्या उदाहरण · स्वास्थ्य प्रभाव का माप नहीं'), estimated_at: UPDATED } : null,
  });
});
