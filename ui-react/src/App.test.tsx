import { render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import App from './App';
import { mockFetch } from './test/mockFetch';

afterEach(() => {
  vi.restoreAllMocks();
});

function mockAppFetch({
  current = [],
  whales = [],
  prices = {
    btc_usd: 105000,
    eth_usd: 3200,
    btc_24h_change: 2.5,
    eth_24h_change: -1.25,
    usd_uah: 41.25,
    fetched_at: '2026-01-01T12:00:00Z',
  },
  state = {},
  currentReject,
  whalesReject,
}: {
  current?: unknown;
  whales?: unknown;
  prices?: unknown;
  state?: unknown;
  currentReject?: Error;
  whalesReject?: Error;
} = {}) {
  return mockFetch([
    { match: '/api/current', response: current, reject: currentReject },
    { match: '/api/whales', response: whales, reject: whalesReject },
    { match: '/api/prices', response: prices },
    { match: /\/api\/state\?sid=/, response: state },
    { match: '/history-api/prices/history/usd_uah?limit=72', response: [] },
    { match: '/history-api/prices/history/bitcoin?limit=72', response: [] },
    { match: '/history-api/prices/history/ethereum?limit=72', response: [] },
  ]);
}

describe('App', () => {
  it('renders the home view with mocked live data and does not use real backend URLs', async () => {
    const fetchMock = mockAppFetch({
      current: [
        {
          slug: 'btc-100k',
          question: 'Will Bitcoin hit 100k?',
          yes_price: 0.62,
          no_price: 0.38,
          volume_24h: 24000,
          category: '',
          end_date: '2026-01-01T00:00:00Z',
          fetched_at: '2026-01-01T00:00:00Z',
        },
      ],
      whales: [],
    });

    render(<App />);

    expect(await screen.findByText('Will Bitcoin hit 100k?')).toBeInTheDocument();
    expect(screen.getByText('Macro Snapshot')).toBeInTheDocument();
    expect(screen.getByPlaceholderText('Search markets, categories, or whales...')).toBeInTheDocument();
    expect(screen.getAllByText('₴41.25').length).toBeGreaterThan(0);

    expect(
      fetchMock.mock.calls.some(([input]) => String(input).includes('172.31.1.10') || String(input).includes('172.31.1.11'))
    ).toBe(false);
  });

  it('shows the empty state safely when there are no markets', async () => {
    mockAppFetch({
      current: [],
      whales: [],
    });

    render(<App />);

    expect(await screen.findByText('No markets match the current search or category filter.')).toBeInTheDocument();
  });

  it('stays usable when live market requests fail', async () => {
    mockAppFetch({
      currentReject: new Error('current failed'),
      whalesReject: new Error('whales failed'),
    });

    render(<App />);

    expect(await screen.findByText('No markets match the current search or category filter.')).toBeInTheDocument();
    expect(screen.getByText('Macro Snapshot')).toBeInTheDocument();
    expect(screen.getByPlaceholderText('Search markets, categories, or whales...')).toBeInTheDocument();
  });
});
