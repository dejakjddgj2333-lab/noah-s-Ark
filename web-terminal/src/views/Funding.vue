<script setup>
import { onMounted, onBeforeUnmount, ref, computed } from 'vue'
import { overviewApi } from '../api'
import { fmtPct, cls } from '../utils/format'

const allRates = ref([]) // 全币种 [{symbol, stablecoin_margin_list:[...]}] — 上游忽略 symbol 返回全币种
const history = ref([])
const loading = ref(true)
const nowTs = ref(Date.now())
let timer = null
let tick = null

const HEAT_COINS = ['BTC', 'ETH', 'SOL', 'DOGE', 'XRP', 'ARB', 'BNB', 'LINK']
const HEAT_EXCHANGES = ['Binance', 'OKX', 'Bybit', 'Bitget', 'Gate']

function rateOf(r) {
  const v = Number(r.funding_rate ?? r.fundingRate ?? r.rate)
  return isNaN(v) ? null : v // 后端已按 % 量纲返回
}

// 摊平: [{symbol, exchange, rate, next_funding_time, interval}]
const flatRates = computed(() => {
  const out = []
  for (const d of allRates.value) {
    for (const e of d.stablecoin_margin_list || []) {
      const v = rateOf(e)
      if (v !== null) out.push({ symbol: d.symbol, exchange: e.exchange, rate: v, next_funding_time: e.next_funding_time, interval: e.funding_rate_interval })
    }
  }
  return out
})

// 全市场平均费率
const avgAll = computed(() => {
  if (!flatRates.value.length) return null
  return flatRates.value.reduce((s, r) => s + r.rate, 0) / flatRates.value.length
})
// 全网最高 / 最低费率标的
const highest = computed(() => flatRates.value.reduce((m, r) => (m === null || r.rate > m.rate ? r : m), null))
const lowest = computed(() => flatRates.value.reduce((m, r) => (m === null || r.rate < m.rate ? r : m), null))

// 年化折算: 8H 一期, 每日 3 期
const annualized = (r) => (r === null || r === undefined ? null : r * 3 * 365)

// 热力图: coin -> { exchange -> rate }
const heatmap = computed(() => {
  const map = {}
  for (const c of HEAT_COINS) {
    const hit = allRates.value.find((d) => d.symbol === c)
    const row = {}
    for (const e of hit?.stablecoin_margin_list || []) {
      const v = rateOf(e)
      if (v !== null) row[e.exchange] = v
    }
    map[c] = row
  }
  return map
})

// 费率 -> 格子底色 (绿正红负, 深浅按绝对值)
function heatColor(v) {
  if (v === null || v === undefined) return 'transparent'
  const a = Math.min(Math.abs(v) / 0.05, 1) // 0.05% 封顶饱和
  return v >= 0 ? `rgba(0, 227, 136, ${0.1 + a * 0.6})` : `rgba(255, 95, 109, ${0.1 + a * 0.6})`
}
const heatTextCls = (v) =>
  v === null || v === undefined
    ? 'text-steel-muted'
    : Math.abs(v) >= 0.035
      ? 'text-canvas-obsidian font-semibold'
      : v >= 0
        ? 'text-bull-green'
        : 'text-bear-red'

// 费率明细全景表行: 每币种跨所费率/均值/年化/基差
const MATRIX_EXCHANGES = ['Binance', 'OKX', 'Bybit']
const matrixRows = computed(() =>
  HEAT_COINS.map((c) => {
    const entries = flatRates.value.filter((r) => r.symbol === c)
    if (!entries.length) return null
    const rates = MATRIX_EXCHANGES.map((ex) => entries.find((r) => r.exchange === ex)?.rate ?? null)
    const vals = entries.map((r) => r.rate)
    const avg = vals.reduce((s, v) => s + v, 0) / vals.length
    const spreadBps = (Math.max(...vals) - Math.min(...vals)) * 100 // % -> bps
    const nextTs = entries
      .map((r) => Number(r.next_funding_time))
      .filter((t) => t > nowTs.value)
      .sort((a, b) => a - b)[0]
    return { symbol: c, rates, avg, apr: annualized(avg), spreadBps, nextTs: nextTs || null }
  }).filter(Boolean)
)

// 倒计时 HH:MM:SS
function countdown(target) {
  if (!target) return '--:--:--'
  let s = Math.max(0, Math.floor((Number(target) - nowTs.value) / 1000))
  const p = (x) => String(x).padStart(2, '0')
  return `${p(Math.floor(s / 3600))}:${p(Math.floor((s % 3600) / 60))}:${p(s % 60)}`
}

// 平均费率迷你走势 (BTC 近 7 日 8H 历史)
const sparkPath = computed(() => {
  const pts = history.value.map((h) => Number(h.rate)).filter((v) => !isNaN(v))
  if (pts.length < 2) return ''
  const min = Math.min(...pts)
  const max = Math.max(...pts)
  const span = max - min || 1
  return pts
    .map((v, i) => `${((i / (pts.length - 1)) * 100).toFixed(1)} ${(32 - ((v - min) / span) * 26).toFixed(1)}`)
    .join(' L ')
})
const sparkArea = computed(() => (sparkPath.value ? `M ${sparkPath.value} L 100 36 L 0 36 Z` : ''))

const COIN_AVATAR = {
  BTC: 'text-amber-warn', ETH: 'text-primary-fixed-dim', SOL: 'text-bull-green', DOGE: 'text-amber-warn',
  XRP: 'text-steel-muted', ARB: 'text-primary-fixed-dim', BNB: 'text-amber-warn', LINK: 'text-primary-fixed-dim',
}
const COIN_CHAR = { BTC: '₿', ETH: 'Ξ', DOGE: 'Ð', AVAX: '▲', LINK: '⬡' }

// ---------- 8H 当前 / 24H 均值 口径切换 ----------
const rateMode = ref('8h') // '8h' | '24h'
const histAvg = ref({}) // symbol -> 近 3 期 (≈24H) 费率均值
let histLoading = false
async function loadHistAvgs() {
  if (histLoading) return
  histLoading = true
  try {
    const res = await Promise.allSettled(HEAT_COINS.map((c) => overviewApi.fundingHistory(c)))
    const map = {}
    res.forEach((r, i) => {
      if (r.status !== 'fulfilled') return
      const pts = (r.value?.history || []).map((h) => Number(h.rate)).filter((v) => !isNaN(v))
      const last3 = pts.slice(-3) // 8H 一期, 近 3 期 ≈ 24H
      if (last3.length) map[HEAT_COINS[i]] = last3.reduce((s, v) => s + v, 0) / last3.length
    })
    histAvg.value = map
  } finally {
    histLoading = false
  }
}
function setMode(m) {
  rateMode.value = m
  if (m === '24h' && !Object.keys(histAvg.value).length) loadHistAvgs()
}
// 热力图单元格口径: 24H 模式为币种级均值 (OKX 历史序列), 8H 模式为各所当前费率
function cellRate(c, ex) {
  if (rateMode.value === '24h') return histAvg.value[c] ?? null
  return heatmap.value[c]?.[ex] ?? null
}
// 明细表均值/年化按口径切换
const avgOf = (row) => (rateMode.value === '24h' ? (histAvg.value[row.symbol] ?? null) : row.avg)
const aprOf = (row) => annualized(avgOf(row))

// ---------- 查看基差 (行内展开) ----------
const expanded = ref(null)
function toggleBasis(symbol) {
  expanded.value = expanded.value === symbol ? null : symbol
}
function basisDetail(symbol) {
  const entries = flatRates.value.filter((r) => r.symbol === symbol)
  if (!entries.length) return null
  const hi = entries.reduce((a, b) => (b.rate > a.rate ? b : a))
  const lo = entries.reduce((a, b) => (b.rate < a.rate ? b : a))
  return { entries, hi, lo, spreadBps: (hi.rate - lo.rate) * 100 }
}

async function load() {
  try {
    const [a, b] = await Promise.allSettled([
      overviewApi.fundingExchangeRates('BTC'), // 上游忽略 symbol, 返回全币种
      overviewApi.fundingHistory('BTC'),
    ])
    if (a.status === 'fulfilled') allRates.value = a.value?.data || []
    if (b.status === 'fulfilled') history.value = b.value?.history || []
  } finally {
    loading.value = false
  }
}

onMounted(() => {
  load()
  timer = setInterval(load, 60000)
  tick = setInterval(() => (nowTs.value = Date.now()), 1000)
})
onBeforeUnmount(() => {
  clearInterval(timer)
  clearInterval(tick)
})
</script>

<template>
  <div v-if="loading" class="text-steel-muted font-mono-data text-mono-data py-10 text-center">数据加载中…</div>
  <div v-else class="flex flex-col gap-space-lg">
    <!-- SUBHEADER / STATUS SUMMARY BANNER -->
    <div class="flex flex-wrap items-center justify-between gap-4 pb-2 border-b border-hairline">
      <div class="flex items-center gap-3">
        <h1 class="text-headline-lg font-headline-lg text-ink-white tracking-tight">全网资金费率矩阵与套利引擎</h1>
        <span class="px-2 py-0.5 rounded bg-card-navy border border-hairline text-steel-muted font-mono-data text-label-sm">
          UTC 结算窗口: 00:00 / 08:00 / 16:00
        </span>
      </div>
      <div class="flex items-center gap-3">
        <span class="text-steel-muted font-body-md text-label-sm flex items-center gap-1.5">
          <span class="w-1.5 h-1.5 rounded-full bg-bull-green"></span> 聚合 {{ HEAT_EXCHANGES.length }} 家主流交易所衍生品节点
        </span>
        <button
          class="h-7 px-2.5 bg-card-navy hover:bg-surface-slate border border-hairline text-ink-white font-mono-data text-label-sm rounded flex items-center gap-1.5 transition-colors"
          @click="load"
        >
          <span class="material-symbols-outlined text-[14px]">refresh</span>
          <span>强制重校</span>
        </button>
      </div>
    </div>

    <!-- ROW 1: 3 KPI METRIC CARDS -->
    <section class="grid grid-cols-1 md:grid-cols-3 gap-4">
      <!-- Card 1: 全市场平均资金费率 -->
      <div class="bg-card-navy border border-hairline rounded-xl p-5 flex flex-col justify-between relative overflow-hidden">
        <div class="flex items-start justify-between">
          <div class="flex flex-col gap-1">
            <span class="text-steel-muted font-headline-sm text-label-sm uppercase tracking-wider">AVERAGE FUNDING RATE</span>
            <span class="text-ink-white font-headline-md text-headline-sm">全市场平均资金费率</span>
          </div>
          <span class="p-1.5 bg-surface-slate border border-hairline rounded text-amber-warn">
            <span class="material-symbols-outlined text-[20px]">query_stats</span>
          </span>
        </div>
        <div class="my-4 flex items-baseline justify-between">
          <div>
            <div class="text-amber-warn font-mono-data text-[32px] font-bold tracking-tight leading-none">{{ fmtPct(avgAll, 4) }}</div>
            <div class="text-steel-muted font-body-md text-label-sm mt-1.5">
              年化折算参考: <span class="font-mono-data text-ink-white">{{ fmtPct(annualized(avgAll), 2) }} p.a.</span>
            </div>
          </div>
          <!-- Mini Sparkline (BTC 近 7 日费率) -->
          <div class="w-24 h-9 flex items-end">
            <svg v-if="sparkPath" class="w-full h-full text-amber-warn" fill="none" viewBox="0 0 100 36" preserveAspectRatio="none">
              <path :d="'M ' + sparkPath" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2"></path>
              <path :d="sparkArea" fill="currentColor" fill-opacity="0.1" stroke="none"></path>
            </svg>
          </div>
        </div>
        <div class="pt-3 border-t border-hairline flex flex-col gap-1.5">
          <div class="flex items-center justify-between font-label-sm text-[11px]">
            <span class="text-amber-warn font-medium flex items-center gap-1">
              <span class="w-1.5 h-1.5 rounded-full bg-amber-warn"></span>
              {{ avgAll != null && avgAll >= 0 ? '多头持仓偏多 · 情绪轻微亢奋' : '空头持仓偏多 · 情绪偏谨慎' }}
            </span>
            <span class="text-steel-muted font-mono-data">基准 8H</span>
          </div>
          <div class="text-steel-muted font-mono-data text-[11px]">
            监控合约: <span class="text-ink-white">{{ allRates.length }}</span> 币种 · <span class="text-ink-white">{{ flatRates.length }}</span> 个所别费率
          </div>
        </div>
      </div>

      <!-- Card 2: 全网最高费率标的 -->
      <div class="bg-card-navy border border-hairline rounded-xl p-5 flex flex-col justify-between relative overflow-hidden">
        <div class="flex items-start justify-between">
          <div class="flex flex-col gap-1">
            <div class="flex items-center gap-2">
              <span class="text-steel-muted font-headline-sm text-label-sm uppercase tracking-wider">HIGHEST RATE</span>
              <span class="px-1.5 py-0.5 rounded bg-bull-green/10 text-bull-green border border-bull-green/30 font-mono-data text-[10px]">
                多头极度溢价
              </span>
            </div>
            <div class="flex items-center gap-1.5">
              <span class="text-ink-white font-headline-md text-headline-sm font-semibold">{{ highest ? highest.symbol + 'USDT' : '--' }}</span>
              <span class="text-steel-muted font-label-sm text-[11px]">永续合约</span>
            </div>
          </div>
          <span class="p-1.5 bg-surface-slate border border-hairline rounded text-bull-green">
            <span class="material-symbols-outlined text-[20px]">trending_up</span>
          </span>
        </div>
        <div class="my-4 flex items-baseline justify-between">
          <div>
            <div class="text-bull-green font-mono-data text-[32px] font-bold tracking-tight leading-none">{{ fmtPct(highest?.rate, 4) }}</div>
            <div class="text-steel-muted font-body-md text-label-sm mt-1.5">
              年化折算: <span class="font-mono-data text-bull-green font-semibold">{{ fmtPct(annualized(highest?.rate), 2) }} p.a.</span>
            </div>
          </div>
          <div class="text-right flex flex-col items-end">
            <span class="px-2 py-0.5 rounded bg-surface-slate border border-hairline text-ink-white font-mono-data text-label-sm">{{ highest?.exchange || '--' }}</span>
            <span class="text-[10px] text-steel-muted font-mono-data mt-1">深度流动性 T0</span>
          </div>
        </div>
        <div class="pt-3 border-t border-hairline flex flex-col gap-1.5">
          <div class="flex items-center justify-between font-label-sm text-[11px]">
            <span class="text-bull-green font-medium flex items-center gap-1">
              <span class="inline-block w-1.5 h-1.5 rounded-full bg-bull-green animate-pulse"></span>
              多空偏离度: 极度贴水 (多付空)
            </span>
            <span class="text-steel-muted font-mono-data">8H 一期</span>
          </div>
          <div class="text-steel-muted font-mono-data text-[11px]">
            建议策略: <span class="text-ink-white font-medium">现货多头 + 永续空头基差套利</span>
          </div>
        </div>
      </div>

      <!-- Card 3: 全网最低/负费率标的 -->
      <div class="bg-card-navy border border-hairline rounded-xl p-5 flex flex-col justify-between relative overflow-hidden">
        <div class="flex items-start justify-between">
          <div class="flex flex-col gap-1">
            <div class="flex items-center gap-2">
              <span class="text-steel-muted font-headline-sm text-label-sm uppercase tracking-wider">LOWEST RATE</span>
              <span class="px-1.5 py-0.5 rounded bg-bear-red/10 text-bear-red border border-bear-red/30 font-mono-data text-[10px]">
                反向套利敞口
              </span>
            </div>
            <div class="flex items-center gap-1.5">
              <span class="text-ink-white font-headline-md text-headline-sm font-semibold">{{ lowest ? lowest.symbol + 'USDT' : '--' }}</span>
              <span class="text-steel-muted font-label-sm text-[11px]">永续合约</span>
            </div>
          </div>
          <span class="p-1.5 bg-surface-slate border border-hairline rounded text-bear-red">
            <span class="material-symbols-outlined text-[20px]">trending_down</span>
          </span>
        </div>
        <div class="my-4 flex items-baseline justify-between">
          <div>
            <div class="text-bear-red font-mono-data text-[32px] font-bold tracking-tight leading-none">{{ fmtPct(lowest?.rate, 4) }}</div>
            <div class="text-steel-muted font-body-md text-label-sm mt-1.5">
              年化折算: <span class="font-mono-data text-bear-red font-semibold">{{ fmtPct(annualized(lowest?.rate), 2) }} p.a.</span>
            </div>
          </div>
          <div class="text-right flex flex-col items-end">
            <span class="px-2 py-0.5 rounded bg-surface-slate border border-hairline text-ink-white font-mono-data text-label-sm">{{ lowest?.exchange || '--' }}</span>
            <span class="text-[10px] text-steel-muted font-mono-data mt-1">空头持仓密集</span>
          </div>
        </div>
        <div class="pt-3 border-t border-hairline flex flex-col gap-1.5">
          <div class="flex items-center justify-between font-label-sm text-[11px]">
            <span class="text-bear-red font-medium flex items-center gap-1">
              <span class="inline-block w-1.5 h-1.5 rounded-full bg-bear-red animate-pulse"></span>
              状态: 空头支付多头 (空头挤压预警)
            </span>
            <span class="text-steel-muted font-mono-data">8H 一期</span>
          </div>
          <div class="text-steel-muted font-mono-data text-[11px]">
            建议策略: <span class="text-ink-white font-medium">多头持仓获取费率分红</span>
          </div>
        </div>
      </div>
    </section>

    <!-- ROW 2: SPLIT LAYOUT (Heatmap 8 Cols + Intel 4 Cols) -->
    <section class="grid grid-cols-1 lg:grid-cols-12 gap-4">
      <!-- Left Card: Cross-Exchange Heatmap -->
      <div class="lg:col-span-8 bg-card-navy border border-hairline rounded-xl p-5 flex flex-col justify-between">
        <div class="flex flex-wrap items-center justify-between gap-3 pb-4 border-b border-hairline">
          <div class="flex items-center gap-2.5">
            <span class="material-symbols-outlined text-primary-fixed-dim text-[20px]">grid_view</span>
            <span class="text-ink-white font-headline-md text-headline-sm font-semibold">全网费率热力图 CROSS-EXCHANGE HEATMAP</span>
          </div>
          <div class="flex items-center gap-4">
            <div class="hidden sm:flex items-center gap-1.5 text-[10px] font-mono-data text-steel-muted">
              <span>&lt;-0.02%</span>
              <div class="w-3 h-3 rounded-sm bg-bear-red/80"></div>
              <div class="w-3 h-3 rounded-sm bg-bear-red/30"></div>
              <div class="w-3 h-3 rounded-sm bg-surface-slate border border-hairline"></div>
              <div class="w-3 h-3 rounded-sm bg-bull-green/30"></div>
              <div class="w-3 h-3 rounded-sm bg-bull-green/80"></div>
              <span>&gt;+0.03%</span>
            </div>
            <div class="flex rounded bg-surface-slate border border-hairline p-0.5">
              <button
                class="px-2.5 py-1 font-mono-data text-label-sm rounded transition-colors"
                :class="rateMode === '8h' ? 'text-ink-white bg-card-navy font-medium shadow-sm' : 'text-steel-muted hover:text-ink-white'"
                @click="setMode('8h')"
              >
                8H 当前周期
              </button>
              <button
                class="px-2.5 py-1 font-mono-data text-label-sm rounded transition-colors"
                :class="rateMode === '24h' ? 'text-ink-white bg-card-navy font-medium shadow-sm' : 'text-steel-muted hover:text-ink-white'"
                @click="setMode('24h')"
              >
                24H 均值
              </button>
            </div>
          </div>
        </div>
        <!-- Heatmap Matrix Table -->
        <div class="overflow-x-auto my-3">
          <table class="w-full border-collapse">
            <thead>
              <tr class="border-b border-hairline">
                <th class="py-2.5 px-3 text-left font-mono-data text-label-sm text-steel-muted font-semibold bg-surface-slate/50">EXCHANGE</th>
                <th v-for="c in HEAT_COINS" :key="c" class="py-2.5 px-2 text-center font-mono-data text-label-sm text-ink-white">{{ c }}</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-hairline">
              <tr v-for="ex in HEAT_EXCHANGES" :key="ex">
                <td class="py-3 px-3 font-headline-sm text-headline-sm text-ink-white font-medium bg-surface-slate/40">{{ ex }}</td>
                <td v-for="c in HEAT_COINS" :key="c" class="p-1.5">
                  <div
                    class="h-10 rounded flex items-center justify-center font-mono-data text-[12px] font-medium border border-hairline/40"
                    :class="heatTextCls(cellRate(c, ex))"
                    :style="{ background: heatColor(cellRate(c, ex)) }"
                  >{{ cellRate(c, ex) != null ? fmtPct(cellRate(c, ex), 3, true) : '--' }}</div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <div class="pt-3 border-t border-hairline flex items-center justify-between font-mono-data text-label-sm text-steel-muted">
          <span>* 颜色饱和度深度绑定费率绝对值偏离度{{ rateMode === '24h' ? ' · 当前为 24H 均值口径 (近 3 期结算均值)' : '' }}</span>
          <span v-if="highest && lowest">
            高亮基差利差: {{ highest.symbol }} ({{ fmtPct(highest.rate, 3) }}) / {{ lowest.symbol }} ({{ fmtPct(lowest.rate, 3) }})
          </span>
        </div>
      </div>

      <!-- Right Card: Intel & Arbitrage Guidelines -->
      <div class="lg:col-span-4 bg-card-navy border border-hairline rounded-xl p-5 flex flex-col justify-between">
        <div class="flex items-center gap-2 pb-3 border-b border-hairline">
          <span class="material-symbols-outlined text-primary-fixed-dim text-[20px]">lightbulb</span>
          <span class="text-ink-white font-headline-md text-headline-sm font-semibold">费率机制与套利说明 INTEL &amp; GUIDELINES</span>
        </div>
        <div class="flex flex-col gap-4 my-2">
          <div class="p-3 rounded bg-surface-slate border border-hairline flex flex-col gap-1.5">
            <div class="flex items-center gap-2 text-primary-fixed-dim font-headline-sm text-headline-sm">
              <span class="material-symbols-outlined text-[16px]">sync_alt</span>
              <span>1. 结算机制与资金流向</span>
            </div>
            <p class="text-steel-muted text-[12px] leading-relaxed">
              资金费率每 8 小时（00:00, 08:00, 16:00 UTC）在多空交易者之间直接结算，不经由交易所收取。当费率为正，多头向空头支付；当费率为负，空头向多头支付。
            </p>
          </div>
          <div class="p-3 rounded bg-surface-slate border border-hairline flex flex-col gap-1.5">
            <div class="flex items-center gap-2 text-amber-warn font-headline-sm text-headline-sm">
              <span class="material-symbols-outlined text-[16px]">troubleshoot</span>
              <span>2. 市场多空情绪锚定</span>
            </div>
            <p class="text-steel-muted text-[12px] leading-relaxed">
              正费率溢价过高（&gt;0.03%）反映市场杠杆极度看涨，伴随潜在多头挤压风险；深度负费率通常预示强支撑反弹或空头回补窗口。
            </p>
          </div>
          <div class="p-3 rounded bg-surface-slate border border-hairline flex flex-col gap-1.5">
            <div class="flex items-center gap-2 text-bull-green font-headline-sm text-headline-sm">
              <span class="material-symbols-outlined text-[16px]">account_balance</span>
              <span>3. 现货-合约跨期期现套利 (Cash &amp; Carry)</span>
            </div>
            <p class="text-steel-muted text-[12px] leading-relaxed">
              利用不同交易所费率差异进行跨平台套利（如币安做空同时OKX做多相同标的），或买入现货同时做空高正费率永续合约，无方向性风险获取稳健年化资金费收益。
            </p>
          </div>
        </div>
        <div class="pt-3 border-t border-hairline flex items-center justify-between font-mono-data text-[11px] text-steel-muted">
          <span>风险评级: 低至中性 (Delta Neutral)</span>
          <span class="text-primary-fixed-dim flex items-center gap-0.5">
            <span>策略回测文档</span>
            <span class="material-symbols-outlined text-[12px]">arrow_forward</span>
          </span>
        </div>
      </div>
    </section>

    <!-- ROW 3: LIVE FUNDING ARBITRAGE MATRIX FULL TABLE -->
    <section class="bg-card-navy border border-hairline rounded-xl p-5 flex flex-col gap-4">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <div class="flex items-center gap-2.5">
          <span class="material-symbols-outlined text-primary-fixed-dim text-[22px]">table_chart</span>
          <div>
            <span class="text-ink-white font-headline-md text-headline-sm font-semibold">费率明细全景表 LIVE FUNDING ARBITRAGE MATRIX</span>
            <span class="ml-2 text-steel-muted font-mono-data text-label-sm">{{ matrixRows.length }} 对核心衍生品流动性池</span>
          </div>
        </div>
        <div class="flex items-center gap-3">
          <div class="flex items-center gap-2 px-2.5 py-1 bg-surface-slate border border-hairline rounded font-mono-data text-label-sm text-steel-muted">
            <span class="w-1.5 h-1.5 rounded-full bg-bull-green"></span>
            <span>自动重拉取: 60s</span>
          </div>
        </div>
      </div>
      <!-- Data Table -->
      <div class="overflow-x-auto border border-hairline rounded-lg">
        <table class="w-full text-left border-collapse">
          <thead>
            <tr class="bg-surface-slate border-b border-hairline text-steel-muted font-mono-data text-label-sm uppercase tracking-wider">
              <th class="py-3 px-4">标的资产 (PERP)</th>
              <th class="py-3 px-3 text-right">Binance 费率</th>
              <th class="py-3 px-3 text-right">OKX 费率</th>
              <th class="py-3 px-3 text-right">Bybit 费率</th>
              <th class="py-3 px-3 text-right">{{ rateMode === '24h' ? '24H 均值 (Avg)' : '全网均值 (Avg)' }}</th>
              <th class="py-3 px-4 text-center">下次结算倒计时</th>
              <th class="py-3 px-3 text-right">{{ rateMode === '24h' ? '24H 年化 (APR)' : '8H 预期年化 (APR)' }}</th>
              <th class="py-3 px-4 text-center">跨所基差 / 操作</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-hairline font-mono-data text-mono-data">
            <template v-for="row in matrixRows" :key="row.symbol">
              <tr class="hover:bg-surface-slate/60 transition-colors">
                <td class="py-3 px-4">
                  <div class="flex items-center gap-2.5">
                    <div
                      class="w-6 h-6 rounded-full bg-surface-slate border border-hairline flex items-center justify-center font-bold text-[10px]"
                      :class="COIN_AVATAR[row.symbol] || 'text-steel-muted'"
                    >{{ COIN_CHAR[row.symbol] || row.symbol.slice(0, 1) }}</div>
                    <div class="flex flex-col">
                      <span class="text-ink-white font-headline-sm font-semibold">{{ row.symbol }}USDT</span>
                      <span class="text-[10px] text-steel-muted">{{ row.symbol }} 永续</span>
                    </div>
                  </div>
                </td>
                <td v-for="(r, i) in row.rates" :key="i" class="py-3 px-3 text-right" :class="cls(r) === 'down' ? 'text-bear-red' : 'text-bull-green'">
                  {{ r != null ? fmtPct(r, 4) : '--' }}
                </td>
                <td class="py-3 px-3 text-right font-medium" :class="cls(avgOf(row)) === 'down' ? 'text-bear-red' : 'text-bull-green'">
                  {{ avgOf(row) != null ? fmtPct(avgOf(row), 4) : '--' }}
                </td>
                <td class="py-3 px-4 text-center">
                  <span class="inline-flex items-center gap-1.5 px-2 py-0.5 rounded bg-surface-slate border border-hairline text-ink-white font-mono-data text-label-sm">
                    <span class="w-1.5 h-1.5 rounded-full" :class="cls(row.avg) === 'down' ? 'bg-bear-red animate-pulse' : 'bg-bull-green'"></span>
                    {{ countdown(row.nextTs) }}
                  </span>
                </td>
                <td class="py-3 px-3 text-right font-bold" :class="cls(aprOf(row)) === 'down' ? 'text-bear-red' : 'text-bull-green'">
                  {{ aprOf(row) != null ? fmtPct(aprOf(row), 2) : '--' }}
                </td>
                <td class="py-3 px-4 text-center">
                  <div class="flex items-center justify-center gap-2">
                    <span class="text-[11px]" :class="row.spreadBps >= 5 ? 'text-bear-red' : 'text-steel-muted'">
                      Δ {{ row.spreadBps.toFixed(1) }} bps{{ row.spreadBps >= 5 ? ' (套利)' : '' }}
                    </span>
                    <button
                      class="h-6 px-2.5 rounded border font-headline-sm text-label-sm transition-colors"
                      :class="expanded === row.symbol
                        ? 'bg-primary-container text-white border-primary-container'
                        : 'bg-surface-slate hover:bg-primary-container text-ink-white hover:text-white border-hairline'"
                      @click="toggleBasis(row.symbol)"
                    >
                      {{ expanded === row.symbol ? '收起' : '查看基差' }}
                    </button>
                  </div>
                </td>
              </tr>
              <!-- 基差内联详情行 -->
              <tr v-if="expanded === row.symbol" class="bg-surface-slate/40">
                <td colspan="8" class="py-3 px-4">
                  <div v-if="basisDetail(row.symbol)" class="flex flex-col gap-2">
                    <div class="flex flex-wrap items-center gap-2">
                      <span
                        v-for="e in basisDetail(row.symbol).entries"
                        :key="e.exchange"
                        class="px-2 py-1 rounded border font-mono-data text-[11px] flex items-center gap-1.5"
                        :class="e.exchange === basisDetail(row.symbol).hi.exchange
                          ? 'bg-bull-green/10 border-bull-green/40 text-bull-green'
                          : e.exchange === basisDetail(row.symbol).lo.exchange
                            ? 'bg-bear-red/10 border-bear-red/40 text-bear-red'
                            : 'bg-card-navy border-hairline text-ink-white'"
                      >
                        <span class="font-semibold">{{ e.exchange }}</span>
                        <span>{{ fmtPct(e.rate, 4) }}</span>
                        <span v-if="e.exchange === basisDetail(row.symbol).hi.exchange" class="text-[9px] uppercase">最高</span>
                        <span v-else-if="e.exchange === basisDetail(row.symbol).lo.exchange" class="text-[9px] uppercase">最低</span>
                      </span>
                    </div>
                    <div class="text-steel-muted font-mono-data text-[11px]">
                      价差最大两家: <span class="text-bull-green">{{ basisDetail(row.symbol).hi.exchange }}</span> / <span class="text-bear-red">{{ basisDetail(row.symbol).lo.exchange }}</span>
                      · Δ {{ basisDetail(row.symbol).spreadBps.toFixed(1) }} bps
                      <span v-if="basisDetail(row.symbol).spreadBps >= 5" class="text-amber-warn"> · 满足跨所套利阈值</span>
                    </div>
                  </div>
                  <div v-else class="text-steel-muted font-mono-data text-[11px]">该币种暂无所别费率明细</div>
                </td>
              </tr>
            </template>
            <tr v-if="!matrixRows.length">
              <td colspan="8" class="py-8 text-center text-steel-muted text-mono-data">暂无费率数据</td>
            </tr>
          </tbody>
        </table>
      </div>
      <!-- Table Footer -->
      <div class="pt-2 flex flex-wrap items-center justify-between gap-3 text-steel-muted font-mono-data text-label-sm">
        <div class="flex items-center gap-4">
          <span class="flex items-center gap-1.5">
            <span class="w-2 h-2 rounded-full bg-bull-green"></span>
            数据刷新间隔: 60s 轮询
          </span>
          <span>•</span>
          <span>已同步 {{ HEAT_EXCHANGES.length }} 家交易所合约节点</span>
          <span>•</span>
          <span>结算周期: 8H</span>
        </div>
        <div class="flex items-center gap-2">
          <span class="text-steel-muted text-[11px]">显示 {{ matrixRows.length }} 条核心标的</span>
        </div>
      </div>
    </section>
  </div>
</template>
