# UI React

## Install

Enter the frontend directory and install dependencies:

```bash
cd /Users/arturvolinec/Projects/internship/coin-ops/ui-react
npm install
```

## Run The App

Start the local development server:

```bash
npm run dev
```

Then open the URL printed in the terminal. In this project it is usually:

```text
http://localhost:3000/
```

## Run Tests

Start test watch mode:

```bash
npm test
```

Run the full test suite one time:

```bash
npm run test:run
```

You can also use:

```bash
npm test -- --run
```

That does the same kind of one-time run, but through the `npm test` command.
That performs the same one-time run through the `npm test` command.

## What Tests Exist

There are 3 small groups of tests:

- Unit tests
  These cover helper functions such as formatting, labels, and filtering.

- Component tests
  These cover isolated UI pieces such as cards and modals with simple props.

- App-level tests
  These cover the main `App` component with mocked API responses, so no real backend is required.

## Where Tests Live

Main places to look:

- `src/lib/*.test.ts`
  Helper tests

- `src/components/*.test.tsx`
  Component tests

- `src/App.test.tsx`
  App-level tests

- `src/test/setup.ts`
  Shared test setup

- `src/test/mockFetch.ts`
  Shared fetch mocking helper

## How API Mocking Works

The tests do not call the real backend.

Instead, they replace `fetch(...)` with mocked responses inside the test environment.

Example flow:

- app asks for `/api/current`
- test returns mocked market data
- app asks for `/api/prices`
- test returns mocked price data

This keeps the tests:

- fast
- local
- independent from VMs, Docker, and backend services

## How To Debug A Failing Test

If a test fails:

1. Run the tests again:

```bash
npm run test:run
```

2. Read the first real error message.
   Start with the first relevant error message before reading the full stack output.

3. Check which file failed.
   Example:

```text
src/components/PriceSummaryCard.test.tsx
```

4. Compare:
   what the test expected
   and what the rendered output actually contains

5. If the failure is about UI text, verify the rendered output before changing application code.

## Useful Extra Commands

Run the TypeScript check:

```bash
npm run lint
```

Build the frontend:

```bash
npm run build
```

These are useful verification steps before committing.
