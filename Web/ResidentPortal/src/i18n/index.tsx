import { createContext, useContext, useEffect, useState, type ReactNode } from 'react';
import type { Language, Localized } from '../data/model';

function preference(key: string, fallback: string) { try { return localStorage.getItem(key) ?? fallback; } catch { return fallback; } }
function save(key: string, value: string) { try { localStorage.setItem(key, value); } catch { /* Preferences are optional. */ } }
type Locale = {
  language: Language; setLanguage: (l: Language) => void;
  theme: string; setTheme: (t: string) => void;
  t: (en: string, hi: string) => string; local: (value: Localized) => string;
  number: (n: number, decimals?: number) => string; date: (d: string) => string;
};
const Context = createContext<Locale | null>(null);
export function LocaleProvider({ children }: { children: ReactNode }) {
  const [language, setLanguage] = useState<Language>(() => preference('kw-language', 'en') === 'hi' ? 'hi' : 'en');
  const [theme, setTheme] = useState(() => preference('kw-theme', 'system'));
  useEffect(() => { document.documentElement.lang = language; save('kw-language', language); }, [language]);
  useEffect(() => { document.documentElement.dataset.theme = theme; save('kw-theme', theme); }, [theme]);
  const locale = language === 'hi' ? 'hi-IN' : 'en-IN';
  return <Context value={{ language, setLanguage, theme, setTheme, t: (en, hi) => language === 'hi' ? hi : en, local: value => value[language], number: (n, decimals = 0) => new Intl.NumberFormat(locale, { maximumFractionDigits: decimals }).format(n), date: d => new Intl.DateTimeFormat(locale, { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'Asia/Kolkata' }).format(new Date(d)) }}>{children}</Context>;
}
export function useLocale() { const value = useContext(Context); if (!value) throw new Error('Locale provider missing'); return value; }
