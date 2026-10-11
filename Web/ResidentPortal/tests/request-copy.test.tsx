import { fireEvent, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { LocaleProvider } from '../src/i18n';
import { client, config } from '../src/data/client';
import { kilns } from '../src/data/fixtures';
import { rememberRequest, zeroRequests } from '../src/data/requests';
import { InspectionRequest } from '../src/features/requests/InspectionRequest';

afterEach(() => { vi.restoreAllMocks(); localStorage.clear(); });

describe('English request counts', () => {
  for (const [count, noun, residents] of [[1, 'request', 'resident has'], [12, 'requests', 'residents have']] as const) {
    const aggregate = { ...zeroRequests(), count, last_request_on: '2026-10-11' };
    const summary = `${count} ${residents} asked for an inspection of this kiln.`;
    it(`uses the correct count ${count} wording after sending`, async () => {
      const kiln = { ...kilns[0], id: `copy-added-${count}`, resident_requests: aggregate };
      vi.spyOn(client, 'request').mockResolvedValue({ kiln_id: kiln.id, created: true, resident_requests: aggregate });
      render(<LocaleProvider><InspectionRequest kiln={kiln} open onOpen={() => {}} /></LocaleProvider>);
      expect(screen.getByText(`${count} inspection ${noun} · not verified`)).toBeVisible();
      fireEvent.click(screen.getByLabelText('Smoke or ash'));
      fireEvent.click(screen.getByRole('button', { name: 'Send request' }));
      expect(await screen.findByText(`Your request was added. ${summary}`)).toBeVisible();
    });
    it(`uses the correct count ${count} wording when revisiting`, () => {
      const kiln = { ...kilns[0], id: `copy-revisit-${count}`, resident_requests: aggregate };
      rememberRequest(config.mode, kiln.id, aggregate);
      render(<LocaleProvider><InspectionRequest kiln={kiln} open={false} onOpen={() => {}} /></LocaleProvider>);
      expect(screen.getByText(`${count} inspection ${noun} · not verified`)).toBeVisible();
      expect(screen.getByText(summary)).toBeVisible();
    });
  }
});
