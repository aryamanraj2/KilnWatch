import { point, type Point, type Search } from './model';
const R = 6371008.8;
const radians = (n: number) => n * Math.PI / 180;
export function distance(a: Point, b: Point): number {
  const dLat = radians(b[1] - a[1]), dLon = radians(b[0] - a[0]);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(radians(a[1])) * Math.cos(radians(b[1])) * Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.asin(Math.sqrt(Math.min(1, h)));
}
export function destination(p: Point, metres: number, bearing: number): Point {
  const d = metres / R, b = radians(bearing), lat = radians(p[1]), lon = radians(p[0]);
  const lat2 = Math.asin(Math.sin(lat) * Math.cos(d) + Math.cos(lat) * Math.sin(d) * Math.cos(b));
  const lon2 = lon + Math.atan2(Math.sin(b) * Math.sin(d) * Math.cos(lat), Math.cos(d) - Math.sin(lat) * Math.sin(lat2));
  return [((lon2 * 180 / Math.PI + 540) % 360) - 180, lat2 * 180 / Math.PI];
}
export function ring(center: Point, radius: number): Point[] {
  return Array.from({ length: 65 }, (_, i) => destination(center, radius, i * 360 / 64));
}
export function validateSearch(s: Search): boolean {
  return point.safeParse(s.center).success && [800, 1000, 2000, 5000].includes(s.radius_m);
}
export function parseCoordinate(value: string): number {
  const normalized = value.replace(/[०-९]/g, c => String(c.charCodeAt(0) - 0x0966)).trim();
  return /^[-+]?\d+(\.\d+)?$/.test(normalized) ? Number(normalized) : NaN;
}
