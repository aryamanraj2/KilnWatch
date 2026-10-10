import { act, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { MemoryRouter } from 'react-router-dom';
import { LocaleProvider } from '../src/i18n';
import { StoreProvider, useApp } from '../src/app/state';
import { client } from '../src/data/client';
import { CENTER, kilns, UPDATED } from '../src/data/fixtures';
import type { Page } from '../src/data/model';
import { Evidence } from '../src/features/evidence/Evidence';
import { Status } from '../src/components/shared';
import { AreaPage } from '../src/features/area/AreaPage';
afterEach(() => { vi.restoreAllMocks(); localStorage.clear(); });
const page = (index: number): Page => ({ items: [{ kiln: kilns[index], distance_m: 300 }], next_cursor: null, complete: true, revision: 'sample-1', coverage: 'known', updated_at: UPDATED, distance_basis: 'centroid' });

describe('resident interactions', () => {
  it('does not show a human finding without authoritative human-review metadata', () => {
    render(<LocaleProvider><Status kiln={{ ...kilns[0], status: 'confirmed', human_reviewed: false }} /></LocaleProvider>);
    expect(screen.getByText('Status not available')).toBeVisible(); expect(screen.queryByText('Confirmed violation')).toBeNull();
  });
  it('lets a working image survive failure of the other comparison side', () => {
    render(<LocaleProvider><Evidence kiln={kilns[0]} /></LocaleProvider>);
    expect(screen.getByRole('slider')).toBeDisabled();
    fireEvent.load(screen.getByAltText('Earlier synthetic scene for this sample record'));
    fireEvent.error(screen.getByAltText('Later synthetic scene for this sample record'));
    expect(screen.queryByRole('slider')).toBeNull(); expect(screen.getByAltText('Earlier synthetic scene for this sample record')).toBeVisible(); expect(screen.getByText('This image could not be loaded.')).toBeVisible();
  });
  it('provides keyboard-independent comparison buttons once the images load', () => {
    render(<LocaleProvider><Evidence kiln={kilns[0]} /></LocaleProvider>);
    for (const image of screen.getAllByRole('img')) fireEvent.load(image);
    expect(screen.getByRole('slider')).toBeEnabled(); fireEvent.click(screen.getByText('Show before')); expect(screen.getByRole('slider')).toHaveValue('0'); fireEvent.click(screen.getByText('Show after')); expect(screen.getByRole('slider')).toHaveValue('100');
  });
  it('ignores an old response even when the transport ignores cancellation', async () => {
    let first: (p: Page) => void = () => {}, second: (p: Page) => void = () => {};
    const fetcher = vi.spyOn(client, 'nearby').mockImplementationOnce(() => new Promise(resolve => { first = resolve; })).mockImplementationOnce(() => new Promise(resolve => { second = resolve; }));
    let store: ReturnType<typeof useApp> | null = null;
    function Probe() { store = useApp(); return <span>{store.page?.items[0]?.kiln.id ?? 'none'}</span>; }
    render(<LocaleProvider><StoreProvider><Probe /></StoreProvider></LocaleProvider>);
    act(() => store!.setQuery({ center: CENTER, radius_m: 1000 })); await waitFor(() => expect(fetcher).toHaveBeenCalledTimes(1));
    act(() => store!.setQuery({ center: CENTER, radius_m: 2000 })); await waitFor(() => expect(fetcher).toHaveBeenCalledTimes(2));
    await act(async () => { second(page(1)); }); expect(screen.getByText('SAMPLE-KW-002')).toBeVisible();
    await act(async () => { first(page(0)); }); expect(screen.queryByText('SAMPLE-KW-001')).toBeNull(); expect(screen.getByText('SAMPLE-KW-002')).toBeVisible();
  });
  it('asks before clearing an edited draft when its selected records change', () => {
    let store: ReturnType<typeof useApp> | null = null;
    function Probe() { store = useApp(); return null; }
    render(<LocaleProvider><StoreProvider><Probe /></StoreProvider></LocaleProvider>);
    act(() => { store!.changeBasket(kilns[0]); store!.setDraft('Resident edit'); });
    const confirm = vi.spyOn(window, 'confirm').mockReturnValue(false);
    act(() => { store!.changeBasket(kilns[1]); }); expect(confirm).toHaveBeenCalledOnce(); expect(store!.draft).toBe('Resident edit'); expect(store!.basket).toHaveLength(1);
    confirm.mockReturnValue(true); act(() => { store!.changeBasket(kilns[1]); }); expect(store!.draft).toBe(''); expect(store!.basket).toHaveLength(2);
  });
  it('requests location only after the action, and keeps coordinate entry usable on failure', async () => {
    const getCurrentPosition = vi.fn((_success: PositionCallback, error?: PositionErrorCallback | null) => error?.({ code: 3, message: 'Timed out', PERMISSION_DENIED: 1, POSITION_UNAVAILABLE: 2, TIMEOUT: 3 }));
    vi.stubGlobal('navigator', { ...navigator, geolocation: { getCurrentPosition } });
    render(<MemoryRouter><LocaleProvider><StoreProvider><AreaPage /></StoreProvider></LocaleProvider></MemoryRouter>);
    expect(getCurrentPosition).not.toHaveBeenCalled(); fireEvent.click(screen.getByText('Use my location')); expect(getCurrentPosition).toHaveBeenCalledOnce();
    expect(screen.getByText(/Location could not be used/)).toBeVisible(); expect(screen.getByLabelText('Latitude')).toBeEnabled();
    vi.unstubAllGlobals();
  });
});
