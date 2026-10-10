import { useMemo } from 'react';
import { ring } from '../../data/geo';
import type { Page, Point, Search } from '../../data/model';
import { useLocale } from '../../i18n';
import { config } from '../../data/client';

export default function Diagram({ query, page, selected, onSelect, onPoint }: { query: Search; page: Page | null; selected: string | null; onSelect: (id: string) => void; onPoint: (p: Point) => void }) {
  const { t, number } = useLocale();
  const sample = config.mode === 'fixture';
  const scale = query.radius_m * 1.4;
  const cos = Math.cos(query.center[1] * Math.PI / 180);
  const project = (p: Point): [number, number] => [320 + (((p[0] - query.center[0] + 540) % 360) - 180) * 111195 * cos / scale * 260, 260 - (p[1] - query.center[1]) * 111195 / scale * 260];
  const circle = useMemo(() => ring(query.center, query.radius_m), [query]);
  if (config.scenario === 'map-error' || Math.abs(query.center[1]) > 85) return <div className="diagram-error"><h3>{t('Map unavailable', 'मानचित्र उपलब्ध नहीं')}</h3><p>{t('Use the list and coordinate fields. All records and draft actions remain available.', 'सूची और निर्देशांक का उपयोग करें। सभी रिकॉर्ड और मसौदा विकल्प उपलब्ध हैं।')}</p></div>;
  return <div className="diagram">
    <div className="map-title"><span>{t('Illustrative map', 'सांकेतिक मानचित्र')}</span><span className="mono">N ↑</span></div>
    <div className="map-canvas" role="group" aria-label={sample ? t('Sample area diagram. Choose a numbered candidate; coordinates are an alternative to placing a point.', 'नमूना क्षेत्र का चित्र। क्रमांकित रिकॉर्ड चुनें; बिंदु लगाने के लिए निर्देशांक भी दर्ज कर सकते हैं।') : t('Area diagram of returned public records. Choose a numbered candidate; coordinates are an alternative to placing a point.', 'प्राप्त सार्वजनिक रिकॉर्ड का क्षेत्र चित्र। क्रमांकित रिकॉर्ड चुनें; बिंदु लगाने के लिए निर्देशांक भी दर्ज कर सकते हैं।')}><svg viewBox="0 0 640 520" aria-hidden="true" onClick={e => {
      if ((e.target as SVGElement).closest('[data-pin]')) return;
      const ctm = e.currentTarget.getScreenCTM(); if (!ctm) return;
      const p = new DOMPoint(e.clientX, e.clientY).matrixTransform(ctm.inverse());
      const lon = query.center[0] + (p.x - 320) * scale / (260 * 111195 * cos);
      const lat = query.center[1] - (p.y - 260) * scale / (260 * 111195);
      onPoint([((lon + 540) % 360) - 180, Math.max(-90, Math.min(90, lat))]);
    }}>
      <defs><pattern id="grid" width="40" height="40" patternUnits="userSpaceOnUse"><path d="M40 0H0V40" fill="none" stroke="currentColor" strokeWidth="0.5" /></pattern></defs>
      <rect width="640" height="520" fill="url(#grid)" className="map-grid" />
      <path d={circle.map((p, i) => `${i ? 'L' : 'M'}${project(p).join(',')}`).join(' ') + 'Z'} className="search-ring" />
      <path d="M304 260h32M320 244v32" className="crosshair" /><circle cx="320" cy="260" r="5" className="map-center" />
      <text x="320" y="291" textAnchor="middle" className="map-label">{t('Search centre', 'खोज केंद्र')}</text>
      {(page?.items ?? []).map(({ kiln }) => kiln.footprint && <path key={kiln.id} className="sample-footprint" d={kiln.footprint.map((p, i) => `${i ? 'L' : 'M'}${project(p).join(',')}`).join(' ') + 'Z'} />)}
    </svg>
      {(page?.items ?? []).map(({ kiln }, i) => {
        const [x, y] = project(kiln.centroid); const active = selected === kiln.id;
        return <button data-pin key={kiln.id} style={{ left: `${x / 640 * 100}%`, top: `${y / 520 * 100}%` }} className={`map-pin ${active ? 'selected' : ''}`} aria-pressed={active} aria-label={`${i + 1} · ${kiln.id}`} onClick={() => onSelect(kiln.id)}><span>{i + 1}</span></button>;
      })}
    </div>
    <div className="map-caption"><span><i className="legend-ring" />{number(query.radius_m / 1000, 1)} {t('km search radius', 'किमी खोज दायरा')}</span><span>{sample ? t('Sample coordinates · no basemap', 'नमूना निर्देशांक · वास्तविक नक्शा नहीं') : t('Public record coordinates · no basemap', 'सार्वजनिक रिकॉर्ड के निर्देशांक · वास्तविक नक्शा नहीं')}</span></div>
    <p className="map-help">{t('Select a pin to focus a record. Click the diagram to choose a new centre, then confirm below.', 'रिकॉर्ड देखने के लिए पिन चुनें। नया केंद्र चुनने के लिए चित्र पर क्लिक करें, फिर खोज फ़ॉर्म में पुष्टि करें।')}</p>
  </div>;
}
