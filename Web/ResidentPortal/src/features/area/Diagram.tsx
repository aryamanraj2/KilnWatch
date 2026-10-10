import { useEffect, useRef, useState } from 'react';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import { ring } from '../../data/geo';
import type { Page, Point, Search } from '../../data/model';
import { useLocale } from '../../i18n';
import { config } from '../../data/client';

const latLng = (p: Point): L.LatLngTuple => [p[1], p[0]];

export default function Diagram({ query, page, selected, onSelect, onPoint, compact = false }: {
  query: Search; page: Page | null; selected: string | null;
  onSelect: (id: string) => void; onPoint?: (p: Point) => void; compact?: boolean;
}) {
  const { t, number } = useLocale();
  const container = useRef<HTMLDivElement>(null), map = useRef<L.Map | null>(null);
  const layers = useRef<L.LayerGroup | null>(null);
  const callbacks = useRef({ onSelect, onPoint });
  const [tileError, setTileError] = useState(false);
  const unavailable = config.scenario === 'map-error' || Math.abs(query.center[1]) > 85;
  useEffect(() => { callbacks.current = { onSelect, onPoint }; }, [onSelect, onPoint]);

  useEffect(() => {
    if (!container.current || unavailable) return;
    const m = L.map(container.current, { zoomControl: false, scrollWheelZoom: false, zoomAnimation: false, fadeAnimation: false, markerZoomAnimation: false });
    map.current = m;
    m.attributionControl.setPrefix(false);
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19, attribution: '© <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener">OpenStreetMap</a> contributors',
      // Send only the site origin, never a record path or resident query.
      referrerPolicy: 'origin', keepBuffer: 1,
    }).on('tileerror', () => setTileError(true)).addTo(m);
    L.control.scale({ imperial: false, position: 'bottomleft' }).addTo(m);
    layers.current = L.layerGroup().addTo(m);
    m.on('click', (event: L.LeafletMouseEvent) => callbacks.current.onPoint?.([event.latlng.wrap().lng, event.latlng.lat]));
    const resize = new ResizeObserver(() => m.invalidateSize({ animate: false }));
    resize.observe(container.current);
    return () => { resize.disconnect(); m.remove(); map.current = null; layers.current = null; };
  }, [unavailable]);

  useEffect(() => {
    const m = map.current;
    if (!m) return;
    m.fitBounds(L.latLngBounds(ring(query.center, query.radius_m).map(latLng)), { padding: [40, 40], animate: false });
  }, [query, unavailable]);

  useEffect(() => {
    const group = layers.current;
    if (!group) return;
    const focusedPin = container.current?.contains(document.activeElement) ? document.activeElement?.getAttribute('aria-label') : null;
    group.clearLayers();
    if (!compact) L.polygon(ring(query.center, query.radius_m).map(latLng), { color: '#a84b25', weight: 1.5, dashArray: '6 6', fillOpacity: 0.035, interactive: false }).addTo(group);
    if (!compact) L.circleMarker(latLng(query.center), { radius: 5, color: '#fff', weight: 2, fillColor: '#1a1a1a', fillOpacity: 1, interactive: false }).addTo(group);
    (page?.items ?? []).forEach(({ kiln }, i) => {
      const active = selected === kiln.id;
      if (kiln.footprint) L.polygon(kiln.footprint.map(latLng), { color: '#a84b25', weight: 1, fillOpacity: 0.2, interactive: false }).addTo(group);
      const button = document.createElement('button');
      button.type = 'button'; button.className = `map-pin ${active ? 'selected' : ''} status-pin-${kiln.status}`;
      button.setAttribute('aria-label', `${i + 1} · ${kiln.id}`); button.setAttribute('aria-pressed', String(active));
      const label = document.createElement('span'); label.textContent = String(i + 1); button.append(label);
      L.DomEvent.disableClickPropagation(button);
      button.addEventListener('click', () => callbacks.current.onSelect(kiln.id));
      const marker = L.marker(latLng(kiln.centroid), { icon: L.divIcon({ html: button, className: 'kiln-marker', iconSize: [44, 44], iconAnchor: [22, 22] }), keyboard: false, zIndexOffset: active ? 1000 : 0 }).addTo(group);
      const tooltip = document.createElement('span'); tooltip.textContent = kiln.id;
      marker.bindTooltip(tooltip, { direction: 'top', offset: [0, -20] });
      if (focusedPin === button.getAttribute('aria-label')) button.focus({ preventScroll: true });
    });
  }, [query, page, selected, compact, unavailable]);

  if (unavailable) return <div className="diagram-error"><h3>{t('Map unavailable', 'मानचित्र उपलब्ध नहीं')}</h3><p>{t('Use the list and coordinate fields. All records and draft actions remain available.', 'सूची और निर्देशांक का उपयोग करें। सभी रिकॉर्ड और मसौदा विकल्प उपलब्ध हैं।')}</p></div>;
  return <div className={`diagram ${compact ? 'compact-map' : ''}`}>
    <div className="map-title"><span>{t('Street map', 'सड़क मानचित्र')} <span className="map-mode">{config.mode === 'fixture' ? t('Demo locations', 'नमूना स्थान') : t('Public records', 'सार्वजनिक रिकॉर्ड')}</span></span><span className="mono">N ↑</span></div>
    <div className="basemap-wrap">
      <div ref={container} className="basemap" role="group" aria-label={t('Interactive area map. Select a numbered record. Drag to pan; use zoom buttons to explore.', 'क्षेत्र का मानचित्र। क्रमांकित रिकॉर्ड चुनें। खींचकर देखें और बटनों से ज़ूम करें।')} />
      <div className="map-controls" role="group" aria-label={t('Map controls', 'मानचित्र नियंत्रण')}>
        <button onClick={() => map.current?.zoomIn()} aria-label={t('Zoom in', 'ज़ूम बढ़ाएँ')}>+</button>
        <button onClick={() => map.current?.zoomOut()} aria-label={t('Zoom out', 'ज़ूम घटाएँ')}>−</button>
        <button onClick={() => map.current?.fitBounds(L.latLngBounds(ring(query.center, query.radius_m).map(latLng)), { padding: [40, 40], animate: false })} aria-label={t('Reset map to search area', 'खोज क्षेत्र पर मानचित्र लौटाएँ')}>⌾</button>
      </div>
    </div>
    {tileError && <p className="map-help map-warning">{t('Some map tiles could not load. Pins and the record list are still available.', 'कुछ मानचित्र टाइलें लोड नहीं हुईं। पिन और रिकॉर्ड सूची उपलब्ध हैं।')}</p>}
    {!compact && <div className="map-caption"><span><i className="legend-ring" />{number(query.radius_m / 1000, 1)} {t('km search radius', 'किमी खोज दायरा')}</span><span>{t('Select a pin to view evidence', 'साक्ष्य के लिए पिन चुनें')}</span></div>}
    {!compact && <p className="map-help">{t('Drag to explore. Click an empty point to choose another search centre.', 'खींचकर देखें। दूसरा खोज केंद्र चुनने के लिए खाली स्थान पर क्लिक करें।')}</p>}
  </div>;
}
