import { createContext, useContext, useEffect, useRef, useState, type ReactNode } from 'react';
import { client, mergePages } from '../data/client';
import { DataError, type Kiln, type Page, type Search } from '../data/model';
import { useLocale } from '../i18n';

export type DraftFields = { name: string; contact: string; observations: string; includeLocation: boolean };
function useStore() {
  const { t } = useLocale();
  const [query, setQuery] = useState<Search | null>(null);
  const [form, setForm] = useState({ place: '', latitude: '', longitude: '', radius: 1000, label: '', accuracy: null as number | null });
  const [page, setPage] = useState<Page | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<DataError | null>(null);
  const [selected, setSelected] = useState<string | null>(null);
  const [refresh, setRefresh] = useState(0);
  const [basket, setBasket] = useState<Kiln[]>([]);
  const [draft, setDraft] = useState('');
  const [fields, setFields] = useState<DraftFields>({ name: '', contact: '', observations: '', includeLocation: false });
  const [draftLanguage, setDraftLanguage] = useState<'en' | 'hi'>('en');
  const request = useRef<AbortController | null>(null);
  const generation = useRef(0);
  const cursors = useRef(new Set<string>());
  useEffect(() => {
    if (!query) return;
    const controller = new AbortController(); request.current?.abort(); request.current = controller;
    const current = ++generation.current;
    setLoading(true); setError(null); setPage(null); cursors.current.clear();
    client.nearby(query, null, controller.signal).then(result => {
      if (current !== generation.current || controller.signal.aborted) return;
      setPage(result); setSelected(s => result.items.some(i => i.kiln.id === s) ? s : result.items[0]?.kiln.id ?? null);
      if (result.next_cursor) cursors.current.add(result.next_cursor);
    }).catch(e => { if (!controller.signal.aborted && current === generation.current) setError(e instanceof DataError ? e : new DataError('unavailable')); }).finally(() => { if (!controller.signal.aborted && current === generation.current) setLoading(false); });
    return () => controller.abort();
  }, [query, refresh]);
  useEffect(() => {
    const warn = (e: BeforeUnloadEvent) => { e.preventDefault(); e.returnValue = ''; };
    if (draft || fields.name || fields.contact || fields.observations) window.addEventListener('beforeunload', warn);
    return () => window.removeEventListener('beforeunload', warn);
  }, [draft, fields]);
  async function more() {
    if (!query || !page?.next_cursor || loading) return;
    const current = generation.current;
    const controller = new AbortController(); request.current?.abort(); request.current = controller;
    setLoading(true); setError(null);
    try {
      const next = await client.nearby(query, page.next_cursor, controller.signal);
      if (current !== generation.current || controller.signal.aborted) return;
      const merged = mergePages(page, next, cursors.current);
      if (next.next_cursor) cursors.current.add(next.next_cursor);
      setPage(merged);
    } catch (e) { if (!controller.signal.aborted && current === generation.current) setError(e instanceof DataError ? e : new DataError('unavailable')); }
    finally { if (current === generation.current && !controller.signal.aborted) setLoading(false); }
  }
  function changeBasket(kiln: Kiln) {
    if (!basket.some(k => k.id === kiln.id) && basket.length >= 10) return false;
    if (draft && !window.confirm(t('Changing the selected records clears the existing draft. Continue?', 'चुने हुए रिकॉर्ड बदलने से मौजूदा मसौदा हट जाएगा। जारी रखें?'))) return false;
    setBasket(items => items.some(k => k.id === kiln.id) ? items.filter(k => k.id !== kiln.id) : [...items, kiln]); setDraft(''); return true;
  }
  return { query, setQuery, form, setForm, page, loading, error, selected, setSelected, retry: () => setRefresh(x => x + 1), more, basket, changeBasket, draft, setDraft, fields, setFields, draftLanguage, setDraftLanguage };
}
type Store = ReturnType<typeof useStore>;
const Context = createContext<Store | null>(null);
export function StoreProvider({ children }: { children: ReactNode }) { const store = useStore(); return <Context value={store}>{children}</Context>; }
export function useApp() { const store = useContext(Context); if (!store) throw new Error('Store provider missing'); return store; }
