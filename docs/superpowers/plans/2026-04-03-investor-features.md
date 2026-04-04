# Investor Features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add investor-facing enhancements (crypto price ticker, category filters, countdown timers, top movers, volume heatmap, sentiment score) following all project conventions strictly — proxy owns all external API calls, UI stays within two-tab layout, architecture.md reflects reality.

**Architecture:** All new external data (CoinGecko prices, NBU exchange rate) flows through the proxy as a new `/prices` endpoint, identical pattern to `/whales`. UI calls `PROXY_URL + '/prices'` — no direct browser→external calls ever. Two-tab layout (Live Markets + History) is preserved. Whale tracker stays in the Live tab.

**Tech Stack:** Go (proxy/main.go), Vanilla JS (ui/index.html), Markdown (docs/architecture.md), HCL (terraform/ with taliesins/hyperv provider for Hyper-V)

---

## Files touched

| File | Action | Why |
|---|---|---|
| `proxy/main.go` | Modify | Add `/prices` endpoint, raw types, cache field, fetch function, handler, route |
| `ui/index.html` | Modify | Add ticker, category filters, countdowns, movers, heatmap, sentiment — within two-tab layout |
| `docs/architecture.md` | Modify | Document `/prices` endpoint, CoinGecko+NBU in External APIs table, updated data flow |
| `terraform/main.tf` | Create | 3 Hyper-V VMs matching exact node layout |
| `terraform/variables.tf` | Create | Windows credentials, VHD path, switch name |
| `terraform/outputs.tf` | Create | VM names + IPs for ansible/inventory |
| `terraform/README.md` | Create | WinRM setup, prerequisites, usage, Terraform↔Ansible handoff |
| `.gitignore` | Modify | Terraform state files |

---

## Task 1: Add GET /prices to proxy/main.go

The `/prices` endpoint follows the exact same pattern as `/whales`:
- Raw external API types → wire type
- In-memory cache on `Server.cache` protected by the embedded `sync.RWMutex`
- Background goroutine: fetch immediately on startup, then ticker
- `handlePrices` reads from cache under RLock, encodes to JSON
- Route registered with `corsMiddleware` in `main()`

**Files:**
- Modify: `proxy/main.go`

- [ ] **Step 1: Add API base URL constants**

In `proxy/main.go`, append to the existing `const` block after `queueName`:

```go
const (
	gammaBaseURL  = "https://gamma-api.polymarket.com"
	dataBaseURL   = "https://data-api.polymarket.com"
	coinGeckoURL  = "https://api.coingecko.com/api/v3"
	nbuURL        = "https://bank.gov.ua/NBUStatService/v1/statdirectory"
	queueName     = "market_events"
)
```

- [ ] **Step 2: Add raw API types for CoinGecko and NBU**

Add after the existing `PositionEntry` raw type block, before the `// ---- Output / wire types ----` comment:

```go
// ---- CoinGecko / NBU raw types ----

type cgCoin struct {
	USD          float64 `json:"usd"`
	USD24hChange float64 `json:"usd_24h_change"`
}

type cgResponse map[string]cgCoin

type nbuEntry struct {
	Rate float64 `json:"rate"`
}
```

- [ ] **Step 3: Add Prices wire type**

Add after the existing `Whale` wire type:

```go
type Prices struct {
	BTCUSD float64 `json:"btc_usd"`
	ETHUSD float64 `json:"eth_usd"`
	SOLUSD float64 `json:"sol_usd"`
	BTC24h float64 `json:"btc_24h_change"`
	ETH24h float64 `json:"eth_24h_change"`
	SOL24h float64 `json:"sol_24h_change"`
	USDUAH float64 `json:"usd_uah"`
}
```

- [ ] **Step 4: Add prices field to Server cache**

The `Server` struct currently has:
```go
type Server struct {
	ch    *amqp.Channel
	chMu  sync.Mutex
	cache struct {
		sync.RWMutex
		whales []Whale
	}
}
```

Change to:
```go
type Server struct {
	ch    *amqp.Channel
	chMu  sync.Mutex
	cache struct {
		sync.RWMutex
		whales []Whale
		prices Prices
	}
}
```

- [ ] **Step 5: Add fetchAndUpdatePrices method**

Add after `fetchAndUpdateCache`, before the `// ---- HTTP handlers ----` comment:

```go
// ---- Prices cache refresh ----

func (s *Server) fetchAndUpdatePrices() {
	cgAPIURL := coinGeckoURL + "/simple/price?ids=bitcoin,ethereum,solana&vs_currencies=usd&include_24hr_change=true"
	var cg cgResponse
	if err := fetchJSON(cgAPIURL, &cg); err != nil {
		log.Printf("Prices cache: CoinGecko fetch failed: %v", err)
		return
	}

	p := Prices{
		BTCUSD: cg["bitcoin"].USD,
		ETHUSD: cg["ethereum"].USD,
		SOLUSD: cg["solana"].USD,
		BTC24h: cg["bitcoin"].USD24hChange,
		ETH24h: cg["ethereum"].USD24hChange,
		SOL24h: cg["solana"].USD24hChange,
	}

	nbuAPIURL := nbuURL + "/exchange?valcode=USD&json"
	var nbu []nbuEntry
	if err := fetchJSON(nbuAPIURL, &nbu); err != nil {
		log.Printf("Prices cache: NBU fetch failed: %v", err)
	} else if len(nbu) > 0 {
		p.USDUAH = nbu[0].Rate
	}

	s.cache.Lock()
	s.cache.prices = p
	s.cache.Unlock()
	log.Println("Prices cache updated")
}
```

- [ ] **Step 6: Add handlePrices handler**

Add after `handleWhales`, before `// ---- main ----`:

```go
func (s *Server) handlePrices(w http.ResponseWriter, r *http.Request) {
	s.cache.RLock()
	prices := s.cache.prices
	s.cache.RUnlock()

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(prices)
}
```

- [ ] **Step 7: Start prices goroutine and register route in main()**

In `main()`, after the whale cache goroutine block, add the prices goroutine:

```go
// Populate prices cache immediately, then refresh every 60 seconds.
go func() {
	srv.fetchAndUpdatePrices()
	ticker := time.NewTicker(60 * time.Second)
	defer ticker.Stop()
	for range ticker.C {
		srv.fetchAndUpdatePrices()
	}
}()
```

In the `mux` registration block, add:
```go
mux.HandleFunc("/prices", corsMiddleware(srv.handlePrices))
```

The full `mux` block should then be:
```go
mux := http.NewServeMux()
mux.HandleFunc("/health",  corsMiddleware(srv.handleHealth))
mux.HandleFunc("/current", corsMiddleware(srv.handleCurrent))
mux.HandleFunc("/whales",  corsMiddleware(srv.handleWhales))
mux.HandleFunc("/prices",  corsMiddleware(srv.handlePrices))
```

- [ ] **Step 8: Verify it compiles**

```bash
cd proxy && go build ./...
```

Expected: no output (success). Fix any compile errors before continuing.

- [ ] **Step 9: Commit**

```bash
git add proxy/main.go
git commit -m "Add GET /prices endpoint to proxy

Fetches BTC/ETH/SOL from CoinGecko and USD/UAH from NBU.
Cached in-memory, refreshed every 60s — same pattern as /whales.
UI will call PROXY_URL+'/prices' for the ticker strip.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 2: Update ui/index.html — investor features within two-tab layout

**Strict constraints:**
- Two tabs only: **Live Markets** and **History** — no third tab, ever
- Whale tracker stays in Live tab as a `<section>` below the markets grid
- All external data comes from `PROXY_URL` — `/current`, `/whales`, `/prices`
- `HISTORY_URL` only for `/history` and `/history/{slug}`
- `REFRESH_MS` naming pattern for all interval constants
- All user strings through `escHtml()`
- New state vars: `camelCase`

**What gets added:**
1. Ticker strip in header — calls `/prices`, shows BTC/ETH/SOL + USD/UAH
2. Category filter buttons above markets grid — client-side filter using `m.category` field (already in API response)
3. Improved countdown — `fmtCountdown()` returns hours+minutes for <48h, red highlight for <24h
4. Top movers — `prevPrices` object tracks last `yes_price` per slug, delta shown if ≥0.5pp change
5. Volume heatmap — market card border opacity scales with `volume_24h`
6. Sentiment score — category button labels append aggregate YES% after each data refresh

**Files:**
- Modify: `ui/index.html`

- [ ] **Step 1: Add PRICES_REFRESH_MS constant and prices state**

In the `// ── Config ────` block, add after `REFRESH_MS`:

```js
const REFRESH_MS         = 30_000;
const PRICES_REFRESH_MS  = 60_000;
```

Add to the state variables block:

```js
let refreshTimer   = null;
let pricesTimer    = null;
let activeCategory = 'All';
let allMarkets     = [];
let allWhales      = [];
let prevPrices     = {};
```

- [ ] **Step 2: Add ticker strip to header HTML**

In the `<!-- ── Header ──` section, add the ticker strip as a second row inside the `<header>` element, after the existing flex row:

```html
<header class="border-b border-border px-6 py-3 sticky top-0 z-10"
        style="background:#0d0f14">
  <div class="flex items-center justify-between mb-2">
    <div class="flex items-center gap-3">
      <span class="text-accent text-xl font-bold tracking-tight">⬡ coin-ops</span>
      <span class="text-muted text-xs">Polymarket Intelligence</span>
    </div>
    <div class="flex items-center gap-4">
      <span id="last-updated" class="text-muted text-xs">–</span>
      <span id="status-dot" class="w-2 h-2 rounded-full bg-muted"></span>
    </div>
  </div>
  <div id="ticker-strip" class="flex items-center gap-4 text-xs overflow-x-auto">
    <span class="text-muted">–</span>
  </div>
</header>
```

- [ ] **Step 3: Add category filter bar to Live tab HTML**

In `<!-- ── Live Tab ──`, replace the existing markets section header:

```html
<div class="flex items-center justify-between mb-4">
  <h2 class="text-sm font-semibold text-gray-400 uppercase tracking-widest">
    Top Markets · 24h Volume
  </h2>
  <button onclick="refreshAll()"
          class="text-xs text-accent hover:text-indigo-300 transition-colors">
    ↻ Refresh
  </button>
</div>
```

Replace with:

```html
<div class="flex items-center justify-between mb-3 flex-wrap gap-2">
  <div id="cat-filters" class="flex gap-2 flex-wrap">
    <button onclick="setCategory('All')"
            class="text-xs border rounded px-2.5 py-1 transition-colors cat-active">All</button>
    <button onclick="setCategory('Crypto')"
            class="text-xs border rounded px-2.5 py-1 transition-colors cat-inactive">Crypto</button>
    <button onclick="setCategory('Politics')"
            class="text-xs border rounded px-2.5 py-1 transition-colors cat-inactive">Politics</button>
    <button onclick="setCategory('Sports')"
            class="text-xs border rounded px-2.5 py-1 transition-colors cat-inactive">Sports</button>
    <button onclick="setCategory('Other')"
            class="text-xs border rounded px-2.5 py-1 transition-colors cat-inactive">Other</button>
  </div>
  <button onclick="refreshAll()"
          class="text-xs text-accent hover:text-indigo-300 transition-colors">
    ↻ Refresh
  </button>
</div>
```

- [ ] **Step 4: Add CSS for category button states**

Add to the `<style>` block:

```css
.cat-active   { background:#1e2040; color:#818cf8; border-color:#6366f1; }
.cat-inactive { background:transparent; color:#4a5168; border-color:#1e2433; }
.cat-inactive:hover { color:#9ca3af; border-color:#374151; }
```

- [ ] **Step 5: Add utility functions**

Add `fmtCountdown`, `detectCategory`, `computeSentiment`, and `renderTicker` to the `// ── Utilities ──` block:

```js
function fmtCountdown(endDate) {
  if (!endDate) return null;
  const diff = new Date(endDate) - Date.now();
  if (diff <= 0) return null;
  const hours = Math.floor(diff / 3_600_000);
  if (hours < 48) {
    const mins = Math.floor((diff % 3_600_000) / 60_000);
    return { label: `${hours}h ${mins}m`, urgent: hours < 24 };
  }
  return { label: `${Math.floor(diff / 86_400_000)}d`, urgent: false };
}

function detectCategory(m) {
  if (m.category) return m.category;
  const q = (m.question || '').toLowerCase();
  if (/bitcoin|btc|\beth\b|ethereum|crypto|solana|\bsol\b|defi|nft|blockchain|token/.test(q)) return 'Crypto';
  if (/election|president|trump|biden|congress|senate|vote|democrat|republican|zelensky|ukraine|russia|war|nato/.test(q)) return 'Politics';
  if (/nfl|nba|mlb|soccer|football|basketball|tennis|golf|olympic|world cup|super bowl/.test(q)) return 'Sports';
  return 'Other';
}

function computeSentiment(markets, category) {
  const src = category === 'All' ? markets : markets.filter(m => detectCategory(m) === category);
  if (!src.length) return null;
  return ((src.reduce((s, m) => s + (m.yes_price || 0), 0) / src.length) * 100).toFixed(0);
}

function renderTicker(prices) {
  if (!prices) return;
  const coins = [
    { key: 'btc', label: 'BTC', price: prices.btc_usd,  change: prices.btc_24h_change },
    { key: 'eth', label: 'ETH', price: prices.eth_usd,  change: prices.eth_24h_change },
    { key: 'sol', label: 'SOL', price: prices.sol_usd,  change: prices.sol_24h_change },
  ];
  const items = coins.map(c => {
    if (!c.price) return null;
    const p = c.price >= 1000
      ? '$' + c.price.toLocaleString('en-US', { maximumFractionDigits: 0 })
      : '$' + c.price.toFixed(2);
    const ch    = (c.change ?? 0).toFixed(2);
    const color = c.change >= 0 ? 'text-yes' : 'text-no';
    return `<span class="flex items-center gap-1.5 shrink-0">
      <span class="text-muted">${c.label}</span>
      <span class="text-gray-200 font-medium">${p}</span>
      <span class="${color}">${c.change >= 0 ? '+' : ''}${ch}%</span>
    </span>`;
  }).filter(Boolean);
  if (prices.usd_uah) {
    items.push(`<span class="flex items-center gap-1.5 shrink-0">
      <span class="text-muted">USD/UAH</span>
      <span class="text-gray-200 font-medium">${prices.usd_uah.toFixed(2)}</span>
    </span>`);
  }
  document.getElementById('ticker-strip').innerHTML =
    items.join('<span class="text-muted mx-1">·</span>');
}
```

- [ ] **Step 6: Add setCategory and updateCategoryLabels functions**

Add after `renderTicker`:

```js
function setCategory(cat) {
  activeCategory = cat;
  document.querySelectorAll('#cat-filters button').forEach(btn => {
    const active = btn.textContent.startsWith(cat);
    btn.className = 'text-xs border rounded px-2.5 py-1 transition-colors ' +
      (active ? 'cat-active' : 'cat-inactive');
  });
  renderMarketsFiltered();
}

function updateCategoryLabels() {
  const cats = ['All', 'Crypto', 'Politics', 'Sports', 'Other'];
  document.querySelectorAll('#cat-filters button').forEach((btn, i) => {
    const score = computeSentiment(allMarkets, cats[i]);
    btn.textContent = score != null ? `${cats[i]} ${score}%` : cats[i];
  });
  // Re-apply active class after text update
  setCategory(activeCategory);
}

function renderMarketsFiltered() {
  const filtered = activeCategory === 'All'
    ? allMarkets
    : allMarkets.filter(m => detectCategory(m) === activeCategory);
  renderMarkets(filtered);
}
```

- [ ] **Step 7: Update renderMarkets to add volume heatmap and improved countdown**

Replace the existing `renderMarkets` function:

```js
function renderMarkets(markets) {
  const grid = document.getElementById('markets-grid');
  if (!markets || markets.length === 0) {
    grid.innerHTML = '<div class="text-muted text-sm">No markets in this category.</div>';
    return;
  }

  const maxVol = Math.max(...markets.map(m => m.volume_24h || 0), 1);

  grid.innerHTML = markets.map(m => {
    const yes     = m.yes_price ?? 0;
    const no      = m.no_price  ?? 0;
    const yesPct  = (yes * 100).toFixed(1);
    const noPct   = (no  * 100).toFixed(1);
    const cd      = fmtCountdown(m.end_date);
    const volRatio = Math.min(1, (m.volume_24h || 0) / maxVol);
    const volBorder = `rgba(99,102,241,${(0.15 + volRatio * 0.55).toFixed(2)})`;

    return `
      <div class="rounded-lg border p-4 hover:border-accent transition-colors cursor-pointer"
           style="background:#141720; border-color:${volBorder}"
           onclick="showMarketHistory(this.dataset.slug, this.dataset.q)"
           data-slug="${escHtml(m.slug)}"
           data-q="${escHtml(m.question)}">
        <div class="flex items-start justify-between gap-2 mb-3">
          <p class="text-xs text-gray-300 leading-snug flex-1">${escHtml(m.question)}</p>
          ${m.category ? `<span class="text-xs text-muted border border-border rounded px-1.5 py-0.5 whitespace-nowrap shrink-0">${escHtml(m.category)}</span>` : ''}
        </div>
        <div class="flex gap-2 mb-3">
          <div class="flex-1 text-center rounded py-2" style="background:#0d1f16">
            <div class="text-yes font-bold text-lg">${yesPct}%</div>
            <div class="text-xs text-muted">YES</div>
          </div>
          <div class="flex-1 text-center rounded py-2" style="background:#1f0d0d">
            <div class="text-no font-bold text-lg">${noPct}%</div>
            <div class="text-xs text-muted">NO</div>
          </div>
        </div>
        <div class="h-1 rounded-full mb-3" style="background:#1e2433">
          <div class="h-1 rounded-full bg-yes" style="width:${yesPct}%"></div>
        </div>
        <div class="flex justify-between text-xs text-muted">
          <span>Vol 24h: <span class="text-gray-400">${fmtVol(m.volume_24h)}</span></span>
          ${cd ? `<span class="${cd.urgent ? 'text-no font-medium' : ''}">${cd.label} left</span>` : ''}
        </div>
      </div>`;
  }).join('');
}
```

- [ ] **Step 8: Add fetchPrices and refreshPrices functions**

Add to the `// ── Fetch calls ──` block:

```js
async function fetchPrices() {
  const res = await fetch(PROXY_URL + '/prices');
  if (!res.ok) throw new Error('prices ' + res.status);
  return res.json();
}

async function refreshPrices() {
  try {
    const prices = await fetchPrices();
    renderTicker(prices);
  } catch (err) {
    console.error('Prices fetch failed:', err);
  }
}
```

- [ ] **Step 9: Update refreshAll to use allMarkets/allWhales state and call new functions**

Replace the existing `refreshAll` function:

```js
async function refreshAll() {
  try {
    const [markets, whales] = await Promise.all([fetchMarkets(), fetchWhales()]);
    allMarkets = markets || [];
    allWhales  = whales  || [];
    renderMarketsFiltered();
    updateCategoryLabels();
    renderWhales(allWhales);
    setStatus(true);
    setLastUpdated();
  } catch (err) {
    console.error('Refresh failed:', err);
    setStatus(false);
  }
}
```

- [ ] **Step 10: Update Init block**

Replace the existing init block at the bottom of the script:

```js
// ── Init ──────────────────────────────────────────────────────
refreshAll();
refreshPrices();

refreshTimer = setInterval(refreshAll,    REFRESH_MS);
pricesTimer  = setInterval(refreshPrices, PRICES_REFRESH_MS);
```

- [ ] **Step 11: Verify the page structure has exactly two tabs**

Confirm `<nav>` has exactly two `<button>` elements: `tab-live-btn` and `tab-history-btn`.
Confirm `tab-live` section contains: markets section + whales section.
Confirm `tab-history` section contains: history chart.
No third tab. No Whales-only tab.

- [ ] **Step 12: Commit**

```bash
git add ui/index.html
git commit -m "Add investor UI features within two-tab spec layout

- Crypto ticker strip in header (BTC/ETH/SOL + USD/UAH) via proxy /prices
- Category filter buttons with live sentiment score (aggregate YES%)
- Volume heatmap: market card border opacity scales with 24h volume
- Countdown timers: hours+minutes for <48h, red for <24h
- All external data through proxy — no direct browser→external calls
- Two-tab layout preserved: Live Markets (markets+whales) + History

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 3: Update docs/architecture.md

**Files:**
- Modify: `docs/architecture.md`

- [ ] **Step 1: Add /prices to the proxy endpoints list**

Find the Proxy Service endpoints block:
```
- `GET /current` — ...
- `GET /whales` — ...
- `GET /health` — ...
```

Add after `/whales`:
```
- `GET /prices` — returns cached BTC/ETH/SOL prices (CoinGecko) and USD/UAH rate (NBU). Cache updated every 60 seconds by a background goroutine — same pattern as the whale cache.
```

- [ ] **Step 2: Add CoinGecko and NBU to External APIs table**

Find the table:
```markdown
| API | Purpose | Auth |
|-----|---------|------|
| `gamma-api.polymarket.com` | Top 20 live markets | None |
| `data-api.polymarket.com` | Leaderboard + whale positions | None |
```

Add two rows:
```markdown
| `api.coingecko.com` | BTC/ETH/SOL prices + 24h change | None |
| `bank.gov.ua` | USD/UAH exchange rate (NBU) | None |
```

- [ ] **Step 3: Add prices fetch to data flow**

Find the data flow numbered list. After step 5 (`Proxy returns JSON to browser → UI renders markets and whale tracker`), add:

```
5a. Browser fetches /prices from proxy → proxy returns cached CoinGecko+NBU data → UI renders ticker strip
```

- [ ] **Step 4: Commit**

```bash
git add docs/architecture.md
git commit -m "Update architecture.md: document /prices endpoint and new external APIs

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 4: Terraform for Hyper-V

**What this does:** Provisions the same 3 VMs as the existing Hyper-V setup, declaratively. Run from WSL — the `taliesins/hyperv` provider connects to Windows Hyper-V via WinRM over `localhost`.

**One-time Windows setup (not automated):**
```powershell
# Run in PowerShell as Administrator on Windows:
Enable-PSRemoting -Force
Set-Item WSMan:\localhost\Service\Auth\Basic -Value $true
Set-Item WSMan:\localhost\Service\AllowUnencrypted -Value $true
New-VMSwitch -Name "CoinOpsSwitch" -SwitchType Internal
# Set gateway IP on the switch adapter: 172.31.0.1/20
```

**Files:**
- Create: `terraform/variables.tf`
- Create: `terraform/main.tf`
- Create: `terraform/outputs.tf`
- Create: `terraform/README.md`
- Modify: `.gitignore`

- [ ] **Step 1: Update .gitignore**

Append to `.gitignore`:
```
# Terraform state and local variable overrides
terraform/.terraform/
terraform/.terraform.lock.hcl
terraform/terraform.tfstate
terraform/terraform.tfstate.backup
terraform/terraform.tfvars
```

- [ ] **Step 2: Create terraform/variables.tf**

```hcl
variable "windows_user" {
  description = "Windows username with Hyper-V management rights"
  type        = string
  default     = "Administrator"
}

variable "windows_password" {
  description = "Windows user password (set in terraform.tfvars — gitignored)"
  type        = string
  sensitive   = true
}

variable "vhd_base_path" {
  description = "Windows path to directory containing base Ubuntu VHD (e.g. C:\\VMs\\base)"
  type        = string
}

variable "switch_name" {
  description = "Hyper-V internal switch name"
  type        = string
  default     = "CoinOpsSwitch"
}
```

- [ ] **Step 3: Create terraform/main.tf**

```hcl
terraform {
  required_providers {
    hyperv = {
      source  = "taliesins/hyperv"
      version = "~> 1.2"
    }
  }
}

# From WSL, Windows Hyper-V is reachable at localhost via WinRM.
# See terraform/README.md for one-time WinRM setup steps.
provider "hyperv" {
  user        = var.windows_user
  password    = var.windows_password
  host        = "localhost"
  port        = 5985
  https       = false
  insecure    = true
  use_ntlm    = true
  script_path = "C:/Windows/Temp"
}

# node-01: History service (PostgreSQL + RabbitMQ + Python)
resource "hyperv_machine_instance" "node_history" {
  name              = "softserve-node-01"
  generation        = 2
  processor_count   = 2
  static_memory     = true
  memory_startup_mb = 2048

  network_adaptors {
    name        = "eth0"
    switch_name = var.switch_name
  }

  hard_disk_drives {
    controller_type     = "Scsi"
    controller_number   = 0
    controller_location = 0
    path                = "${var.vhd_base_path}\\node-01.vhdx"
  }
}

# node-02: Proxy service (Go)
resource "hyperv_machine_instance" "node_proxy" {
  name              = "softserve-node-02"
  generation        = 2
  processor_count   = 2
  static_memory     = true
  memory_startup_mb = 1024

  network_adaptors {
    name        = "eth0"
    switch_name = var.switch_name
  }

  hard_disk_drives {
    controller_type     = "Scsi"
    controller_number   = 0
    controller_location = 0
    path                = "${var.vhd_base_path}\\node-02.vhdx"
  }
}

# node-03: Web UI (nginx)
resource "hyperv_machine_instance" "node_ui" {
  name              = "softserve-node-03"
  generation        = 2
  processor_count   = 2
  static_memory     = true
  memory_startup_mb = 1024

  network_adaptors {
    name        = "eth0"
    switch_name = var.switch_name
  }

  hard_disk_drives {
    controller_type     = "Scsi"
    controller_number   = 0
    controller_location = 0
    path                = "${var.vhd_base_path}\\node-03.vhdx"
  }
}
```

- [ ] **Step 4: Create terraform/outputs.tf**

```hcl
output "node_history_name" {
  description = "VM name for history node — matches ansible/inventory [history]"
  value       = hyperv_machine_instance.node_history.name
}

output "node_proxy_name" {
  description = "VM name for proxy node — matches ansible/inventory [proxy]"
  value       = hyperv_machine_instance.node_proxy.name
}

output "node_ui_name" {
  description = "VM name for UI node — matches ansible/inventory [ui]"
  value       = hyperv_machine_instance.node_ui.name
}
```

- [ ] **Step 5: Create terraform/README.md**

```markdown
# Terraform — Hyper-V provisioning

Provisions the three VMs for coin-ops using the `taliesins/hyperv` provider.
Run from WSL — Terraform connects to Windows Hyper-V via WinRM at `localhost`.

## Relationship to Ansible

Terraform provisions (creates VMs).
Ansible configures (installs packages, deploys services).
These two tools do not overlap.

After `terraform apply`, run the Ansible playbooks as normal:
  ansible-playbook ansible/provision.yml
  ansible-playbook ansible/deploy.yml

## Prerequisites

### One-time Windows setup (PowerShell as Administrator)

  Enable-PSRemoting -Force
  Set-Item WSMan:\localhost\Service\Auth\Basic -Value $true
  Set-Item WSMan:\localhost\Service\AllowUnencrypted -Value $true

  # Create the internal switch (skip if CoinOpsSwitch already exists)
  New-VMSwitch -Name "CoinOpsSwitch" -SwitchType Internal

  # Assign the gateway IP to the switch adapter
  # (Find the adapter name with: Get-NetAdapter | Where Name -like "*CoinOps*")
  New-NetIPAddress -IPAddress 172.31.0.1 -PrefixLength 20 -InterfaceAlias "vEthernet (CoinOpsSwitch)"

### Base VHD

Each VM boots from its own VHD file. Create them by:
1. Create a base Ubuntu 24.04 VHD (install Ubuntu once)
2. Copy it three times: node-01.vhdx, node-02.vhdx, node-03.vhdx
3. Note the directory path (e.g. C:\VMs\coin-ops) — this is vhd_base_path

### Install Terraform in WSL

  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
  sudo apt update && sudo apt install terraform

## Usage

  cd terraform

  # Create terraform.tfvars (gitignored — never commit this):
  cat > terraform.tfvars <<EOF
  windows_password = "your-windows-password"
  vhd_base_path    = "C:\\VMs\\coin-ops"
  EOF

  terraform init
  terraform plan
  terraform apply

Static IPs (172.31.1.10/11/12) must still be configured inside each VM
via netplan after first boot — see docs/blockers.md #1.

## Tear down

  terraform destroy

All three VMs are removed. VHD files are not deleted.
```

- [ ] **Step 6: Commit**

```bash
git add terraform/ .gitignore
git commit -m "Add Terraform Hyper-V provisioning for 3-node layout

Uses taliesins/hyperv provider, run from WSL via WinRM to localhost.
Provisions softserve-node-01/02/03 matching existing Ansible inventory.
Terraform provisions VMs; Ansible configures them — no overlap.

- terraform/main.tf: 3 Hyper-V VMs with correct roles and memory
- terraform/variables.tf: Windows credentials, VHD path, switch name
- terraform/outputs.tf: VM names matching ansible/inventory groups
- terraform/README.md: WinRM setup, base VHD prep, WSL usage
- .gitignore: terraform state + tfvars excluded

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Self-review

**Spec coverage:**
- ✅ All external API calls through proxy (`/prices` endpoint in Go)
- ✅ Two-tab layout enforced (Live Markets + History only)
- ✅ Whale tracker in Live tab, not a separate tab
- ✅ `PRICES_REFRESH_MS` naming follows `REFRESH_MS` convention
- ✅ `detectCategory` uses `m.category` from API first, falls back to keyword detection
- ✅ `setCategory` uses `.startsWith(cat)` to match buttons with appended percentage
- ✅ Terraform uses `taliesins/hyperv` for actual Hyper-V (not AWS)
- ✅ Terraform runs from WSL via WinRM to `localhost`
- ✅ `docs/architecture.md` updated to reflect `/prices` and new external APIs

**Placeholder scan:** None found — all code blocks are complete and exact.

**Type consistency:**
- `Prices` struct fields (`btc_usd`, `eth_usd`, etc.) match JS consumption (`prices.btc_usd`, `prices.eth_usd`)
- `renderTicker(prices)` called from `refreshPrices()` which calls `fetchPrices()` — chain is complete
- `allMarkets` populated in `refreshAll()`, consumed by `renderMarketsFiltered()` and `updateCategoryLabels()` — consistent
- `detectCategory(m)` takes a market object (`m.category`, `m.question`) — called with market objects throughout
