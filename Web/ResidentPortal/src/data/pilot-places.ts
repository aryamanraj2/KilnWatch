import type { Localized, Point } from './model';

// A named entry into the published pilot, not a district-wide coverage claim or geocoder.
export type PilotPlace = { label: Localized; aliases: string; center: Point };
export const pilotPlaces: PilotPlace[] = [{
  label: { en: 'Hapur · pilot area', hi: 'हापुड़ · पायलट क्षेत्र' },
  aliases: 'hapur|hapur pilot area|hapur, uttar pradesh|hapur up|हापुड़|हापुड|हापुड़ · पायलट क्षेत्र',
  center: [77.7759, 28.7306],
}];
const normalize = (value: string) => value.trim().toLocaleLowerCase().normalize('NFC').replace(/\s+/g, ' ');
export function findPilotPlace(value: string): PilotPlace | undefined {
  const term = normalize(value);
  return pilotPlaces.find(p => [p.label.en, p.label.hi, ...p.aliases.split('|')].some(alias => normalize(alias) === term));
}
