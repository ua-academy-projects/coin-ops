import { render, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';

import { PriceSummaryCard } from './PriceSummaryCard';

describe('PriceSummaryCard', () => {
  it('shows fallback text when price, change, and history are missing', () => {
    render(
      <PriceSummaryCard
        title="Bitcoin"
        symbol="BTC"
        data={[]}
        accentClassName="from-orange-500/20 via-amber-400/10 to-transparent"
        onClick={vi.fn()}
      />,
    );

    expect(screen.getByText('Bitcoin')).toBeInTheDocument();
    expect(screen.getByText('--')).toBeInTheDocument();
    expect(screen.getByText('No change data')).toBeInTheDocument();
    expect(screen.getByText('Waiting for price history.')).toBeInTheDocument();
  });
});
