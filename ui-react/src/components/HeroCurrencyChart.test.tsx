import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';

import { HeroCurrencyChart } from './HeroCurrencyChart';

describe('HeroCurrencyChart', () => {
  it('shows empty-state text when there is no price history', () => {
    render(
      <HeroCurrencyChart
        title="USD / UAH"
        data={[]}
        formatter={(value) => `₴${value.toFixed(2)}`}
      />,
    );

    expect(screen.getByText('USD / UAH')).toBeInTheDocument();
    expect(screen.getByText('No points yet')).toBeInTheDocument();
    expect(screen.getByText('Waiting for price history.')).toBeInTheDocument();
  });
});
