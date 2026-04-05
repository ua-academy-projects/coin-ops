/**
 * @license
 * SPDX-License-Identifier: Apache-2.0
 */

import React, { useState, useEffect, useMemo } from 'react';
import {
  TrendingUp,
  History as HistoryIcon,
  Users,
  Activity,
  Search,
  RefreshCw,
  ChevronRight,
  ArrowUpRight,
  ArrowDownRight,
  ExternalLink,
  Filter,
  BarChart3,
  LayoutGrid,
  PieChart as PieChartIcon,
  Zap,
  ShieldAlert,
  Globe
} from 'lucide-react';
import { motion, AnimatePresence } from 'motion/react';
import {
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  AreaChart,
  Area
} from 'recharts';
import { cn } from '@/src/lib/utils';
import { MarketSnapshot, Whale, HistoryPoint, Prices, PriceHistory } from './types';
import { PROXY_URL, HISTORY_URL, REFRESH_MS, PRICES_REFRESH_MS } from './config';

function getSessionId(): string {
  const name = 'coinops_sid=';
  const cookie = document.cookie.split(';').find(c => c.trim().startsWith(name));
  if (cookie) return cookie.trim().slice(name.length);
  const id = crypto.randomUUID();
  document.cookie = `coinops_sid=${id}; max-age=86400; path=/`;
  return id;
}

export default function App() {
  const [activeTab, setActiveTab] = useState<'live' | 'history' | 'whales' | 'insights'>('live');
  const [markets, setMarkets] = useState<MarketSnapshot[]>([]);
  const [whales, setWhales] = useState<Whale[]>([]);
  const [selectedMarket, setSelectedMarket] = useState<MarketSnapshot | null>(null);
  const [historyData, setHistoryData] = useState<HistoryPoint[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [prices, setPrices] = useState<Prices | null>(null);

  const loadData = async () => {
    setIsLoading(true);
    try {
      const [marketsRes, whalesRes] = await Promise.all([
        fetch(PROXY_URL + '/current'),
        fetch(PROXY_URL + '/whales'),
      ]);
      if (marketsRes.ok) setMarkets(await marketsRes.json());
      if (whalesRes.ok) setWhales(await whalesRes.json());
    } catch {
      // backend unreachable — keep existing data
    } finally {
      setIsLoading(false);
    }
  };

  const loadPrices = async () => {
    try {
      const res = await fetch(PROXY_URL + '/prices');
      if (res.ok) setPrices(await res.json());
    } catch {
      // silent fail — prices are optional
    }
  };

  const saveState = async (sid: string, tab: string) => {
    try {
      await fetch(`${PROXY_URL}/state?sid=${sid}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ active_tab: tab }),
      });
    } catch { /* silent */ }
  };

  const restoreState = async (sid: string) => {
    try {
      const res = await fetch(`${PROXY_URL}/state?sid=${sid}`);
      if (res.ok) {
        const state = await res.json();
        if (state.active_tab) setActiveTab(state.active_tab as typeof activeTab);
      }
    } catch { /* silent */ }
  };

  const handleTabSwitch = (tab: typeof activeTab) => {
    setActiveTab(tab);
    const sid = getSessionId();
    saveState(sid, tab);
  };

  useEffect(() => {
    const sid = getSessionId();
    loadData();
    loadPrices();
    restoreState(sid);
    const marketTimer = setInterval(loadData, REFRESH_MS);
    const priceTimer = setInterval(loadPrices, PRICES_REFRESH_MS);
    return () => {
      clearInterval(marketTimer);
      clearInterval(priceTimer);
    };
  }, []);

  const filteredMarkets = useMemo(() => {
    return markets.filter(m =>
      m.question.toLowerCase().includes(searchQuery.toLowerCase()) ||
      m.category.toLowerCase().includes(searchQuery.toLowerCase())
    );
  }, [markets, searchQuery]);

  const handleMarketClick = async (market: MarketSnapshot) => {
    setSelectedMarket(market);
    handleTabSwitch('history');
    try {
      const res = await fetch(`${HISTORY_URL}/history/${market.slug}?limit=500`);
      if (res.ok) setHistoryData(await res.json());
    } catch {
      setHistoryData([]);
    }
  };

  return (
    <div className="flex h-screen bg-transparent overflow-hidden relative">
      {/* Decorative Background Elements */}
      <div className="absolute top-[-10%] left-[-10%] w-[40%] h-[40%] bg-accent/20 rounded-full blur-[120px] -z-10 animate-pulse" />
      <div className="absolute bottom-[-10%] right-[-10%] w-[40%] h-[40%] bg-purple-500/10 rounded-full blur-[120px] -z-10" />
      <div className="absolute top-[30%] right-[10%] w-[20%] h-[20%] bg-blue-500/10 rounded-full blur-[100px] -z-10" />

      {/* Sidebar */}
      <aside className="w-64 border-r border-white/10 bg-black/20 backdrop-blur-3xl flex flex-col z-20">
        <div className="p-6 flex items-center gap-3">
          <div className="w-8 h-8 bg-accent rounded-lg flex items-center justify-center shadow-lg shadow-accent/40">
            <Activity className="text-white w-5 h-5" />
          </div>
          <span className="font-bold text-xl tracking-tight bg-clip-text text-transparent bg-gradient-to-r from-white to-white/60">Coin-Ops</span>
        </div>

        <nav className="flex-1 px-4 space-y-2">
          <NavItem
            icon={<TrendingUp size={20} />}
            label="Live Markets"
            active={activeTab === 'live'}
            onClick={() => handleTabSwitch('live')}
          />
          <NavItem
            icon={<Users size={20} />}
            label="Whale Tracker"
            active={activeTab === 'whales'}
            onClick={() => handleTabSwitch('whales')}
          />
          <NavItem
            icon={<LayoutGrid size={20} />}
            label="Market Insights"
            active={activeTab === 'insights'}
            onClick={() => handleTabSwitch('insights')}
          />
          <NavItem
            icon={<HistoryIcon size={20} />}
            label="History"
            active={activeTab === 'history'}
            onClick={() => handleTabSwitch('history')}
          />
        </nav>

        <div className="p-4 border-t border-white/10">
          <div className="glass rounded-xl p-4 space-y-2">
            <div className="flex items-center justify-between text-xs text-muted">
              <span>Status</span>
              <div className="flex items-center gap-1.5">
                <div className="w-1.5 h-1.5 rounded-full bg-yes animate-pulse shadow-[0_0_8px_rgba(34,197,94,0.6)]" />
                <span className="text-yes">Live</span>
              </div>
            </div>
            <p className="text-[10px] text-muted leading-relaxed">
              Connected to Polymarket Gamma API v1.2
            </p>
          </div>
        </div>
      </aside>

      {/* Main Content */}
      <main className="flex-1 flex flex-col overflow-hidden z-10">
        {/* Header */}
        <header className="h-16 border-b border-white/10 flex items-center justify-between px-8 bg-black/10 backdrop-blur-xl sticky top-0 z-10">
          <div className="flex items-center gap-4 flex-1 max-w-xl">
            <div className="relative w-full">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-muted" size={18} />
              <input
                type="text"
                placeholder="Search markets, categories, or whales..."
                className="w-full bg-white/5 border border-white/10 rounded-lg py-2 pl-10 pr-4 text-sm focus:outline-none focus:border-accent/50 focus:bg-white/10 transition-all"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
              />
            </div>
          </div>

          {prices && (
            <div className="hidden md:flex items-center gap-4 text-xs font-mono">
              <span className="text-zinc-400">
                BTC <span className="text-white font-bold">${prices.btc_usd.toLocaleString()}</span>
                <span className={prices.btc_24h_change >= 0 ? 'text-yes ml-1' : 'text-no ml-1'}>
                  {prices.btc_24h_change >= 0 ? '+' : ''}{prices.btc_24h_change.toFixed(2)}%
                </span>
              </span>
              <span className="text-zinc-400">
                ETH <span className="text-white font-bold">${prices.eth_usd.toLocaleString()}</span>
                <span className={prices.eth_24h_change >= 0 ? 'text-yes ml-1' : 'text-no ml-1'}>
                  {prices.eth_24h_change >= 0 ? '+' : ''}{prices.eth_24h_change.toFixed(2)}%
                </span>
              </span>
              <span className="text-zinc-400">
                UAH <span className="text-white font-bold">&#8372;{prices.usd_uah.toFixed(2)}</span>
              </span>
            </div>
          )}

          <div className="flex items-center gap-4">
            <button className="p-2 hover:bg-white/5 rounded-lg transition-colors text-muted">
              <Filter size={20} />
            </button>
            <button
              className="flex items-center gap-2 bg-accent hover:bg-accent/90 text-white px-4 py-2 rounded-lg text-sm font-medium transition-all shadow-lg shadow-accent/20"
              onClick={() => {
                loadData();
                loadPrices();
              }}
            >
              <RefreshCw size={16} className={cn(isLoading && "animate-spin")} />
              Refresh
            </button>
          </div>
        </header>

        {/* Scrollable Area */}
        <div className="flex-1 overflow-y-auto p-8 custom-scrollbar">
          <AnimatePresence mode="wait">
            {activeTab === 'live' && (
              <motion.div
                key="live"
                initial={{ opacity: 0, scale: 0.98 }}
                animate={{ opacity: 1, scale: 1 }}
                exit={{ opacity: 0, scale: 0.98 }}
                transition={{ duration: 0.3 }}
                className="space-y-8"
              >
                <div className="flex items-center justify-between">
                  <div>
                    <h1 className="text-2xl font-bold bg-clip-text text-transparent bg-gradient-to-br from-white to-white/60">Live Markets</h1>
                    <p className="text-muted text-sm">Real-time prediction market data from Polymarket</p>
                  </div>
                  <div className="flex gap-2">
                    <Badge label="24h Vol: $12.4M" variant="accent" />
                    <Badge label="Active: 1,240" variant="surface" />
                  </div>
                </div>

                <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-6">
                  {isLoading ? (
                    Array.from({ length: 6 }).map((_, i) => <SkeletonCard key={i} />)
                  ) : (
                    filteredMarkets.map((market) => (
                      <MarketCard
                        key={market.slug}
                        market={market}
                        onClick={() => handleMarketClick(market)}
                      />
                    ))
                  )}
                </div>
              </motion.div>
            )}

            {activeTab === 'whales' && (
              <motion.div
                key="whales"
                initial={{ opacity: 0, scale: 0.98 }}
                animate={{ opacity: 1, scale: 1 }}
                exit={{ opacity: 0, scale: 0.98 }}
                transition={{ duration: 0.3 }}
                className="space-y-8"
              >
                <div>
                  <h1 className="text-2xl font-bold bg-clip-text text-transparent bg-gradient-to-br from-white to-white/60">Whale Tracker</h1>
                  <p className="text-muted text-sm">Monitoring the largest positions and PnL leaders</p>
                </div>

                <div className="space-y-4">
                  {whales.map((whale) => (
                    <WhaleRow key={whale.address} whale={whale} />
                  ))}
                </div>
              </motion.div>
            )}

            {activeTab === 'insights' && (
              <motion.div
                key="insights"
                initial={{ opacity: 0, scale: 0.98 }}
                animate={{ opacity: 1, scale: 1 }}
                exit={{ opacity: 0, scale: 0.98 }}
                transition={{ duration: 0.3 }}
                className="space-y-8"
              >
                <div>
                  <h1 className="text-2xl font-bold bg-clip-text text-transparent bg-gradient-to-br from-white to-white/60">Market Insights</h1>
                  <p className="text-muted text-sm">Bento-style analysis of current market trends and sentiment</p>
                </div>

                <div className="grid grid-cols-1 md:grid-cols-4 md:grid-rows-3 gap-4 h-[800px]">
                  {/* Bento Item 1: Sentiment Analysis */}
                  <div className="md:col-span-2 md:row-span-2 glass rounded-3xl p-6 flex flex-col">
                    <div className="flex items-center justify-between mb-6">
                      <h3 className="text-lg font-semibold flex items-center gap-2">
                        <Zap className="text-yellow-400" size={20} />
                        Sentiment Analysis
                      </h3>
                      <Badge label="Bullish" variant="accent" />
                    </div>
                    <div className="flex-1 flex items-center justify-center">
                      <div className="relative w-48 h-48">
                        <svg className="w-full h-full" viewBox="0 0 100 100">
                          <circle cx="50" cy="50" r="45" fill="none" stroke="rgba(255,255,255,0.05)" strokeWidth="10" />
                          <circle cx="50" cy="50" r="45" fill="none" stroke="#6366f1" strokeWidth="10" strokeDasharray="282.7" strokeDashoffset="70" strokeLinecap="round" className="transition-all duration-1000" />
                        </svg>
                        <div className="absolute inset-0 flex flex-col items-center justify-center">
                          <span className="text-4xl font-bold">75%</span>
                          <span className="text-[10px] text-muted uppercase tracking-widest">Positive</span>
                        </div>
                      </div>
                    </div>
                    <p className="text-xs text-muted mt-4 text-center leading-relaxed">
                      Social sentiment across major platforms indicates a strong bullish trend for upcoming crypto-related markets.
                    </p>
                  </div>

                  {/* Bento Item 2: Volume Spikes */}
                  <div className="md:col-span-2 md:row-span-1 glass rounded-3xl p-6">
                    <div className="flex items-center justify-between mb-4">
                      <h3 className="text-sm font-semibold flex items-center gap-2">
                        <TrendingUp className="text-yes" size={18} />
                        Volume Spikes
                      </h3>
                    </div>
                    <div className="space-y-3">
                      <div className="flex items-center justify-between text-xs">
                        <span className="text-zinc-400">BTC $100k Market</span>
                        <span className="text-yes font-bold">+450%</span>
                      </div>
                      <div className="h-1.5 bg-white/5 rounded-full overflow-hidden">
                        <div className="h-full bg-yes w-[85%]" />
                      </div>
                      <div className="flex items-center justify-between text-xs">
                        <span className="text-zinc-400">US Election Market</span>
                        <span className="text-zinc-500 font-bold">+120%</span>
                      </div>
                      <div className="h-1.5 bg-white/5 rounded-full overflow-hidden">
                        <div className="h-full bg-zinc-600 w-[40%]" />
                      </div>
                    </div>
                  </div>

                  {/* Bento Item 3: Risk Assessment */}
                  <div className="md:col-span-1 md:row-span-1 glass rounded-3xl p-6 flex flex-col justify-between">
                    <ShieldAlert className="text-no mb-2" size={24} />
                    <div>
                      <h3 className="text-sm font-semibold mb-1">Risk Level</h3>
                      <p className="text-2xl font-bold text-no">Moderate</p>
                    </div>
                    <p className="text-[10px] text-muted">Volatility index is currently at 42.5</p>
                  </div>

                  {/* Bento Item 4: Global Reach */}
                  <div className="md:col-span-1 md:row-span-1 glass rounded-3xl p-6 flex flex-col justify-between">
                    <Globe className="text-blue-400 mb-2" size={24} />
                    <div>
                      <h3 className="text-sm font-semibold mb-1">Active Regions</h3>
                      <p className="text-2xl font-bold">142</p>
                    </div>
                    <p className="text-[10px] text-muted">Top region: North America</p>
                  </div>

                  {/* Bento Item 5: Market Dominance */}
                  <div className="md:col-span-2 md:row-span-1 glass rounded-3xl p-6 flex items-center gap-6">
                    <div className="w-24 h-24 flex-shrink-0">
                      <PieChartIcon className="w-full h-full text-accent opacity-50" />
                    </div>
                    <div className="flex-1">
                      <h3 className="text-sm font-semibold mb-3">Category Dominance</h3>
                      <div className="flex flex-wrap gap-2">
                        <span className="px-2 py-1 bg-white/5 rounded text-[10px] text-zinc-300">Crypto 45%</span>
                        <span className="px-2 py-1 bg-white/5 rounded text-[10px] text-zinc-300">Politics 30%</span>
                        <span className="px-2 py-1 bg-white/5 rounded text-[10px] text-zinc-300">Sports 15%</span>
                        <span className="px-2 py-1 bg-white/5 rounded text-[10px] text-zinc-300">Other 10%</span>
                      </div>
                    </div>
                  </div>

                  {/* Bento Item 6: Quick Stats */}
                  <div className="md:col-span-2 md:row-span-1 glass rounded-3xl p-6 grid grid-cols-2 gap-4">
                    <div className="space-y-1">
                      <p className="text-[10px] text-muted uppercase tracking-widest">Total Liquidity</p>
                      <p className="text-xl font-bold">$42.8M</p>
                    </div>
                    <div className="space-y-1">
                      <p className="text-[10px] text-muted uppercase tracking-widest">New Users</p>
                      <p className="text-xl font-bold">+1.2K</p>
                    </div>
                    <div className="space-y-1">
                      <p className="text-[10px] text-muted uppercase tracking-widest">Avg Trade</p>
                      <p className="text-xl font-bold">$450</p>
                    </div>
                    <div className="space-y-1">
                      <p className="text-[10px] text-muted uppercase tracking-widest">Uptime</p>
                      <p className="text-xl font-bold text-yes">99.9%</p>
                    </div>
                  </div>
                </div>
              </motion.div>
            )}

            {activeTab === 'history' && (
              <motion.div
                key="history"
                initial={{ opacity: 0, scale: 0.98 }}
                animate={{ opacity: 1, scale: 1 }}
                exit={{ opacity: 0, scale: 0.98 }}
                transition={{ duration: 0.3 }}
                className="space-y-8"
              >
                <div className="flex items-center justify-between">
                  <div>
                    <h1 className="text-2xl font-bold bg-clip-text text-transparent bg-gradient-to-br from-white to-white/60">Market History</h1>
                    <p className="text-muted text-sm">
                      {selectedMarket ? selectedMarket.question : "Select a market to view historical trends"}
                    </p>
                  </div>
                  {selectedMarket && (
                    <button
                      onClick={() => handleTabSwitch('live')}
                      className="text-accent text-sm font-medium hover:underline flex items-center gap-1"
                    >
                      Back to Markets <ChevronRight size={16} />
                    </button>
                  )}
                </div>

                {selectedMarket ? (
                  <div className="space-y-6">
                    <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
                      <StatCard
                        label="Current Price"
                        value={`${(selectedMarket.yes_price * 100).toFixed(1)}%`}
                        subValue="YES Outcome"
                        trend="up"
                      />
                      <StatCard
                        label="24h Volume"
                        value={`$${(selectedMarket.volume_24h / 1000).toFixed(1)}K`}
                        subValue="+12.4% from yesterday"
                        trend="up"
                      />
                      <StatCard
                        label="End Date"
                        value={new Date(selectedMarket.end_date).toLocaleDateString()}
                        subValue="Time remaining: 24 days"
                      />
                    </div>

                    <div className="glass rounded-2xl p-6 h-[400px]">
                      <h3 className="text-sm font-semibold text-muted mb-6 uppercase tracking-wider">Price Probability Trend</h3>
                      <ResponsiveContainer width="100%" height="100%">
                        <AreaChart data={historyData}>
                          <defs>
                            <linearGradient id="colorYes" x1="0" y1="0" x2="0" y2="1">
                              <stop offset="5%" stopColor="#22c55e" stopOpacity={0.3}/>
                              <stop offset="95%" stopColor="#22c55e" stopOpacity={0}/>
                            </linearGradient>
                            <linearGradient id="colorNo" x1="0" y1="0" x2="0" y2="1">
                              <stop offset="5%" stopColor="#ef4444" stopOpacity={0.1}/>
                              <stop offset="95%" stopColor="#ef4444" stopOpacity={0}/>
                            </linearGradient>
                          </defs>
                          <CartesianGrid strokeDasharray="3 3" stroke="rgba(255,255,255,0.05)" vertical={false} />
                          <XAxis
                            dataKey="fetched_at"
                            tickFormatter={(str) => new Date(str).toLocaleTimeString([], { hour: '2-digit' })}
                            stroke="#52525b"
                            fontSize={12}
                            tickLine={false}
                            axisLine={false}
                          />
                          <YAxis
                            stroke="#52525b"
                            fontSize={12}
                            tickLine={false}
                            axisLine={false}
                            tickFormatter={(val) => `${(val * 100).toFixed(0)}%`}
                          />
                          <Tooltip
                            contentStyle={{ backgroundColor: 'rgba(24, 24, 27, 0.8)', backdropFilter: 'blur(12px)', border: '1px solid rgba(255,255,255,0.1)', borderRadius: '12px' }}
                            itemStyle={{ fontSize: '12px' }}
                            labelStyle={{ color: '#a1a1aa', marginBottom: '4px' }}
                            labelFormatter={(label) => new Date(label).toLocaleString()}
                          />
                          <Area
                            type="monotone"
                            dataKey="yes_price"
                            stroke="#22c55e"
                            strokeWidth={2}
                            fillOpacity={1}
                            fill="url(#colorYes)"
                            name="YES Price"
                          />
                          <Area
                            type="monotone"
                            dataKey="no_price"
                            stroke="#ef4444"
                            strokeWidth={2}
                            fillOpacity={1}
                            fill="url(#colorNo)"
                            name="NO Price"
                          />
                        </AreaChart>
                      </ResponsiveContainer>
                    </div>
                  </div>
                ) : (
                  <div className="flex flex-col items-center justify-center py-20 text-center space-y-4">
                    <div className="w-16 h-16 bg-white/5 rounded-full flex items-center justify-center text-muted">
                      <BarChart3 size={32} />
                    </div>
                    <div>
                      <h3 className="text-lg font-medium">No Market Selected</h3>
                      <p className="text-muted max-w-xs">Select a market from the Live tab to analyze its historical performance and trends.</p>
                    </div>
                    <button
                      onClick={() => handleTabSwitch('live')}
                      className="bg-accent text-white px-6 py-2 rounded-lg font-medium shadow-lg shadow-accent/20"
                    >
                      Browse Markets
                    </button>
                  </div>
                )}
              </motion.div>
            )}
          </AnimatePresence>
        </div>
      </main>
    </div>
  );
}

function NavItem({ icon, label, active, onClick }: { icon: React.ReactNode, label: string, active: boolean, onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      className={cn(
        "w-full flex items-center gap-3 px-4 py-3 rounded-xl transition-all duration-200 group",
        active
          ? "bg-accent text-white shadow-lg shadow-accent/20"
          : "text-muted hover:bg-surface hover:text-zinc-100"
      )}
    >
      <span className={cn("transition-transform duration-200", active ? "scale-110" : "group-hover:scale-110")}>
        {icon}
      </span>
      <span className="font-medium text-sm">{label}</span>
      {active && (
        <motion.div
          layoutId="active-pill"
          className="ml-auto w-1.5 h-1.5 rounded-full bg-white"
        />
      )}
    </button>
  );
}

interface MarketCardProps {
  key?: string;
  market: MarketSnapshot;
  onClick: () => void;
}

function MarketCard({ market, onClick }: MarketCardProps) {
  const yesPct = (market.yes_price * 100).toFixed(1);
  const noPct = (market.no_price * 100).toFixed(1);

  return (
    <motion.div
      whileHover={{ y: -4 }}
      onClick={onClick}
      className="glass rounded-2xl p-5 cursor-pointer group transition-all hover:border-accent/50"
    >
      <div className="flex items-start justify-between mb-4">
        <span className="text-[10px] font-bold uppercase tracking-widest text-accent bg-accent/10 px-2 py-0.5 rounded">
          {market.category}
        </span>
        <div className="flex items-center gap-1 text-muted text-[10px]">
          <Activity size={12} />
          <span>{Math.floor(market.volume_24h / 1000)}K Vol</span>
        </div>
      </div>

      <h3 className="text-sm font-medium leading-relaxed mb-6 group-hover:text-accent transition-colors line-clamp-2 h-10">
        {market.question}
      </h3>

      <div className="space-y-4">
        <div className="flex items-center justify-between text-xs mb-1">
          <span className="text-yes font-semibold">YES {yesPct}%</span>
          <span className="text-no font-semibold">NO {noPct}%</span>
        </div>

        <div className="h-2 bg-zinc-800 rounded-full overflow-hidden flex">
          <motion.div
            initial={{ width: 0 }}
            animate={{ width: `${yesPct}%` }}
            className="h-full bg-yes"
          />
          <motion.div
            initial={{ width: 0 }}
            animate={{ width: `${noPct}%` }}
            className="h-full bg-no"
          />
        </div>

        <div className="flex items-center justify-between pt-2 border-t border-border/50">
          <div className="text-[10px] text-muted">
            Ends {new Date(market.end_date).toLocaleDateString()}
          </div>
          <div className="flex items-center gap-1 text-accent text-[10px] font-bold">
            ANALYZE <ChevronRight size={12} />
          </div>
        </div>
      </div>
    </motion.div>
  );
}

interface WhaleRowProps {
  key?: string;
  whale: Whale;
}

function WhaleRow({ whale }: WhaleRowProps) {
  const isProfit = whale.pnl >= 0;

  return (
    <div className="glass rounded-2xl p-5 hover:bg-surface transition-colors">
      <div className="flex flex-wrap items-center justify-between gap-4">
        <div className="flex items-center gap-4">
          <div className="w-10 h-10 rounded-full bg-zinc-800 flex items-center justify-center text-accent font-bold">
            {whale.rank}
          </div>
          <div>
            <h4 className="font-semibold">{whale.pseudonym}</h4>
            <p className="text-xs text-muted font-mono">{whale.address}</p>
          </div>
        </div>

        <div className="flex items-center gap-8">
          <div className="text-right">
            <p className="text-[10px] text-muted uppercase tracking-wider mb-1">PnL (Monthly)</p>
            <div className={cn("flex items-center gap-1 font-bold", isProfit ? "text-yes" : "text-no")}>
              {isProfit ? <ArrowUpRight size={16} /> : <ArrowDownRight size={16} />}
              ${Math.abs(whale.pnl / 1000).toFixed(1)}K
            </div>
          </div>
          <div className="text-right">
            <p className="text-[10px] text-muted uppercase tracking-wider mb-1">Total Volume</p>
            <p className="font-bold">${(whale.volume / 1000000).toFixed(1)}M</p>
          </div>
          <button className="p-2 hover:bg-zinc-800 rounded-lg transition-colors text-muted">
            <ExternalLink size={18} />
          </button>
        </div>
      </div>

      <div className="mt-4 grid grid-cols-1 md:grid-cols-2 gap-3">
        {whale.positions.map((pos, i) => (
          <div key={i} className="bg-bg/50 border border-border/50 rounded-xl p-3 flex items-center justify-between">
            <div className="flex items-center gap-3">
              <div className={cn(
                "px-2 py-1 rounded text-[10px] font-bold",
                pos.outcome === 'YES' ? "bg-yes/10 text-yes" : "bg-no/10 text-no"
              )}>
                {pos.outcome}
              </div>
              <span className="text-xs font-medium truncate max-w-[150px]">{pos.market}</span>
            </div>
            <div className="text-right">
              <p className="text-[10px] font-bold">${(pos.current_value / 1000).toFixed(1)}K</p>
              <p className="text-[8px] text-muted">Avg: {(pos.avg_price * 100).toFixed(1)}&#162;</p>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

function StatCard({ label, value, subValue, trend }: { label: string, value: string, subValue: string, trend?: 'up' | 'down' }) {
  return (
    <div className="glass rounded-2xl p-6">
      <p className="text-xs text-muted uppercase tracking-widest mb-2">{label}</p>
      <div className="flex items-end gap-2 mb-1">
        <span className="text-3xl font-bold">{value}</span>
        {trend && (
          <span className={cn("text-xs font-bold mb-1 flex items-center", trend === 'up' ? "text-yes" : "text-no")}>
            {trend === 'up' ? <ArrowUpRight size={14} /> : <ArrowDownRight size={14} />}
            12%
          </span>
        )}
      </div>
      <p className="text-xs text-muted">{subValue}</p>
    </div>
  );
}

function Badge({ label, variant }: { label: string, variant: 'accent' | 'surface' }) {
  return (
    <span className={cn(
      "px-3 py-1 rounded-full text-[10px] font-bold tracking-wide",
      variant === 'accent' ? "bg-accent/20 text-accent border border-accent/20" : "bg-surface text-muted border border-border"
    )}>
      {label}
    </span>
  );
}

function SkeletonCard() {
  return (
    <div className="glass rounded-2xl p-5 animate-pulse">
      <div className="flex justify-between mb-4">
        <div className="w-16 h-4 bg-zinc-800 rounded" />
        <div className="w-12 h-4 bg-zinc-800 rounded" />
      </div>
      <div className="w-full h-4 bg-zinc-800 rounded mb-2" />
      <div className="w-2/3 h-4 bg-zinc-800 rounded mb-6" />
      <div className="space-y-4">
        <div className="flex justify-between">
          <div className="w-10 h-3 bg-zinc-800 rounded" />
          <div className="w-10 h-3 bg-zinc-800 rounded" />
        </div>
        <div className="w-full h-2 bg-zinc-800 rounded" />
      </div>
    </div>
  );
}
