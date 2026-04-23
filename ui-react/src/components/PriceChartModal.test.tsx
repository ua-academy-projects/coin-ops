import { render, screen } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';

import { PriceChartModal } from './PriceChartModal';

describe('PriceChartModal', () => {
  it('shows loading text when chart data is empty', () => {
    render(
      <PriceChartModal
        coin="bitcoin"
        data={[]}
        onClose={vi.fn()}
      />,
    );

    expect(screen.getByText('Bitcoin (BTC) — Price History')).toBeInTheDocument();
    expect(screen.getByText('Loading chart data…')).toBeInTheDocument();
  });
});
