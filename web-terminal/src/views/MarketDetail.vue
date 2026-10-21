<script setup>
import { onMounted, onBeforeUnmount, ref, computed, watch } from 'vue'
import { useRoute } from 'vue-router'
import EChart from '../components/EChart.vue'
import { marketApi } from '../api'
import { fmtPrice, fmtPct, fmtBig, fmtNum, fmtTime, coinOf } from '../utils/format'
import { inWatchlist, toggleWatchlist } from '../utils/watchlist'

const route = useRoute()
const instId = computed(() => route.params.instId)
const coin = computed(() => coinOf(instId.value))
// 纯展示: 常见币种英文全名 (对齐设计稿顶部报价条)
const COIN_NAMES = {
  BTC: 'Bitcoin', ETH: 'Ethereum', SOL: 'Solana', BNB: 'BNB', XRP: 'Ripple',
  DOGE: 'Dogecoin', ADA: 'Cardano', AVAX: 'Avalanche', LINK: 'Chainlink', TON: 'Toncoin',
}
const coinName = computed(() => COIN_NAMES[coin.value] || coin.value)
const isSwap = computed(() => instId.value.endsWith('-SWAP'))
const bar = ref('1H')
const bars = ['15m', '1H', '4H', '1D', '1W']

const ticker = ref(null)
const candles = ref([])
const books = ref({ bids: [], asks: [] })
const trades = ref([])
const funding = ref(null)
const fCountdown = ref('--')
let timer = null
let cdTimer = null

// ---- 图表工具: 十字光标 / 重置缩放 / 全屏 ----
const kchart = ref(null)
const chartWrap = ref(null)
const crossOn = ref(false)
function toggleCross() { crossOn.value = !crossOn.value }
function resetZoom() {
  try { kchart.value?.getChart()?.dispatchAction({ type: 'restore' }) } catch { /* 静默降级 */ }
}
function toggleFullscreen() {
  try {
    if (document.fullscreenElement) document.exitFullscreen()
    else chartWrap.value?.requestFullscreen?.()
  } catch { /* 静默降级 */ }
}

// ---- 自选 (localStorage) ----
const watched = ref(false)
function syncWatched() { watched.value = inWatchlist(instId.value) }
function toggleWatch() {
  toggleWatchlist(instId.value)
  syncWatched()
}

function pct() {
  const t = ticker.value
  if (!t || !Number(t.open24h)) return 0
  return ((Number(t.last) - Number(t.open24h)) / Number(t.open24h)) * 100
}
const up = computed(() => pct() >= 0)

// ---- K线: 专业版 (MA / 高低点标记 / 最新价线 / 自定义提示 / 滚轮缩放) ----
function pxDec(v) {
  const n = Math.abs(Number(v) || 0)
  if (n >= 1000) return 2
  if (n >= 1) return n >= 100 ? 2 : 4
  return 6
}
function calcMA(n, arr) {
  // arr: [o,c,l,h]
  return arr.map((_, i) => {
    if (i < n - 1) return '-'
    let s = 0
    for (let j = 0; j < n; j++) s += arr[i - j][1]
    return +(s / n).toFixed(8)
  })
}
const klineOption = computed(() => {
  const data = candles.value.map((c) => [+c[1], +c[4], +c[3], +c[2]]) // o c l h (echarts 顺序)
  const cats = candles.value.map((c) => fmtTime(+c[0]))
  const vols = candles.value.map((c) => +c[5])
  const dec = pxDec(data.length ? data[data.length - 1][1] : 1)
  const fmtP = (v) => Number(v).toLocaleString('en-US', { minimumFractionDigits: dec, maximumFractionDigits: dec })

  // 当前视图最高/最低 (基于全部已加载K线)
  let hi = -Infinity, lo = Infinity, hiI = 0, loI = 0
  data.forEach((d, i) => {
    if (d[3] > hi) { hi = d[3]; hiI = i }
    if (d[2] < lo) { lo = d[2]; loI = i }
  })
  const last = data.length ? data[data.length - 1] : null
  const lastUp = last ? last[1] >= last[0] : true
  const lastColor = lastUp ? '#00E388' : '#FF5F6D'

  return {
    backgroundColor: 'transparent',
    animation: false,
    tooltip: {
      trigger: 'axis',
      axisPointer: { type: crossOn.value ? 'cross' : 'line' },
      backgroundColor: 'rgba(13,21,40,0.95)',
      borderColor: '#34415E',
      textStyle: { color: '#F0F0FF', fontSize: 11, fontFamily: 'JetBrains Mono' },
      formatter: (ps) => {
        const i = ps[0]?.dataIndex ?? 0
        const d = data[i]
        if (!d) return ''
        const chg = d[0] ? ((d[1] - d[0]) / d[0]) * 100 : 0
        const c = chg >= 0 ? '#00E388' : '#FF5F6D'
        return [
          `<div style="color:#9EA0B2">${cats[i]}</div>`,
          `开 <b>${fmtP(d[0])}</b>&nbsp;&nbsp;收 <b style="color:${c}">${fmtP(d[1])}</b>`,
          `高 <b style="color:#00E388">${fmtP(d[3])}</b>&nbsp;&nbsp;低 <b style="color:#FF5F6D">${fmtP(d[2])}</b>`,
          `涨跌 <b style="color:${c}">${chg >= 0 ? '+' : ''}${chg.toFixed(2)}%</b>&nbsp;&nbsp;量 <b>${vols[i]?.toLocaleString('en-US') ?? '-'}</b>`,
        ].join('<br/>')
      },
    },
    axisPointer: { link: [{ xAxisIndex: 'all' }] },
    dataZoom: [{ type: 'inside', xAxisIndex: [0, 1], start: 40, end: 100 }],
    xAxis: [
      { type: 'category', data: cats, axisLine: { lineStyle: { color: '#34415E' } }, axisLabel: { color: '#9EA0B2', fontSize: 10, fontFamily: 'JetBrains Mono' } },
      { type: 'category', gridIndex: 1, data: cats, axisLine: { lineStyle: { color: '#34415E' } }, axisLabel: { show: false } },
    ],
    yAxis: [
      { scale: true, position: 'right', splitLine: { lineStyle: { color: 'rgba(52,65,94,0.3)' } }, axisLabel: { color: '#9EA0B2', fontSize: 10, fontFamily: 'JetBrains Mono', formatter: (v) => fmtP(v) } },
      { gridIndex: 1, scale: true, position: 'right', splitNumber: 2, splitLine: { show: false }, axisLabel: { show: false } },
    ],
    grid: [
      { left: 8, right: 76, top: 16, height: '62%' },
      { left: 8, right: 76, top: '72%', height: '18%' },
    ],
    series: [
      {
        name: 'K线',
        type: 'candlestick',
        data,
        itemStyle: { color: '#00E388', color0: '#FF5F6D', borderColor: '#00E388', borderColor0: '#FF5F6D' },
        markPoint: {
          symbol: 'circle',
          symbolSize: 0.1, // 只要文字标签
          label: {
            show: true,
            position: 'top',
            fontSize: 10,
            fontFamily: 'JetBrains Mono',
            color: '#F0F0FF',
            backgroundColor: 'rgba(13,21,40,0.85)',
            borderColor: '#34415E',
            borderWidth: 1,
            borderRadius: 3,
            padding: [2, 5],
          },
          data: [
            { name: '最高', coord: [hiI, hi], value: `高 ${fmtP(hi)}`, label: { position: 'top' } },
            { name: '最低', coord: [loI, lo], value: `低 ${fmtP(lo)}`, label: { position: 'bottom' } },
          ],
        },
        markLine: {
          symbol: 'none',
          silent: true,
          animation: false,
          label: {
            show: true,
            position: 'insideEndTop',
            fontSize: 10,
            fontFamily: 'JetBrains Mono',
            color: '#070D1C',
            backgroundColor: lastColor,
            borderRadius: 2,
            padding: [2, 5],
            formatter: () => fmtP(last ? last[1] : 0),
          },
          lineStyle: { color: lastColor, type: 'dashed', width: 1, opacity: 0.8 },
          data: last ? [{ yAxis: last[1] }] : [],
        },
      },
      { name: 'MA5', type: 'line', data: calcMA(5, data), smooth: true, showSymbol: false, lineStyle: { width: 1, color: '#F7B733' }, z: 3 },
      { name: 'MA10', type: 'line', data: calcMA(10, data), smooth: true, showSymbol: false, lineStyle: { width: 1, color: '#B8C3FF' }, z: 3 },
      { name: 'MA20', type: 'line', data: calcMA(20, data), smooth: true, showSymbol: false, lineStyle: { width: 1, color: '#C26BFF' }, z: 3 },
      {
        name: '成交量',
        type: 'bar',
        xAxisIndex: 1,
        yAxisIndex: 1,
        data: candles.value.map((c) => ({
          value: +c[5],
          itemStyle: { color: +c[4] >= +c[1] ? 'rgba(0,227,136,0.5)' : 'rgba(255,95,109,0.5)' },
        })),
      },
    ],
  }
})

// ---- 盘口精度聚合: 卖盘向上取整 / 买盘向下取整, 同档合并数量 ----
const maLegend = computed(() => {
  const data = candles.value.map((c) => [+c[1], +c[4], +c[3], +c[2]])
  const dec = pxDec(data.length ? data[data.length - 1][1] : 1)
  const fmtP = (v) => (typeof v === 'number' ? v.toLocaleString('en-US', { minimumFractionDigits: dec, maximumFractionDigits: dec }) : '--')
  const defs = [
    { name: 'MA5', n: 5, color: '#F7B733' },
    { name: 'MA10', n: 10, color: '#B8C3FF' },
    { name: 'MA20', n: 20, color: '#C26BFF' },
  ]
  return defs.map((d) => {
    const arr = calcMA(d.n, data)
    const v = arr.length ? arr[arr.length - 1] : '-'
    return { ...d, value: fmtP(v) }
  })
})
const PRECISIONS = [0.01, 0.1, 1.0]
const precision = ref(0.1)
const pxDecimals = computed(() => (precision.value >= 1 ? 0 : precision.value >= 0.1 ? 1 : 2))
function fmtPx(px) {
  const n = Number(px)
  if (isNaN(n)) return '--'
  return n.toFixed(pxDecimals.value)
}
function aggLevels(levels, side) {
  const p = precision.value
  const map = new Map()
  for (const lv of levels || []) {
    const n = Number(lv[0])
    if (isNaN(n)) continue
    const bucket = side === 'ask' ? Math.ceil(n / p) * p : Math.floor(n / p) * p
    const key = bucket.toFixed(8)
    map.set(key, (map.get(key) || 0) + Number(lv[1] || 0))
  }
  const arr = [...map.entries()].map(([px, sz]) => [px, sz])
  arr.sort((a, b) => (side === 'ask' ? Number(a[0]) - Number(b[0]) : Number(b[0]) - Number(a[0])))
  return arr
}

// ---- 盘口: 卖 8 档 (上高下低) + 买 8 档, 带累计深度条 ----
const asks8 = computed(() => aggLevels(books.value.asks, 'ask').slice(0, 6).reverse())
const bids8 = computed(() => aggLevels(books.value.bids, 'bid').slice(0, 6))

const askRows = computed(() => {
  const list = asks8.value
  const cum = new Array(list.length)
  let s = 0
  for (let i = list.length - 1; i >= 0; i--) { s += Number(list[i][1]); cum[i] = s }
  const max = cum[0] || 1
  return list.map((a, i) => ({ px: a[0], sz: Number(a[1]), cum: cum[i], w: (cum[i] / max) * 100 }))
})

const bidRows = computed(() => {
  const list = bids8.value
  let s = 0
  const rows = list.map((b) => {
    s += Number(b[1])
    return { px: b[0], sz: Number(b[1]), cum: s }
  })
  const max = s || 1
  rows.forEach((r) => { r.w = (r.cum / max) * 100 })
  return rows
})

const buyPct = computed(() => {
  const b = bids8.value.reduce((s, x) => s + Number(x[1]), 0)
  const a = asks8.value.reduce((s, x) => s + Number(x[1]), 0)
  if (!a && !b) return 50
  return Math.round((b / (a + b)) * 100)
})

const spread = computed(() => {
  const a = asks8.value[asks8.value.length - 1]
  const b = bids8.value[0]
  if (!a || !b) return null
  return Number(a[0]) - Number(b[0])
})

// ---- 逐笔成交: 大额单标记 ----
const trades16 = computed(() => trades.value.slice(0, 30))
const whaleQty = computed(() => {
  if (!trades16.value.length) return Infinity
  const avg = trades16.value.reduce((s, t) => s + Number(t.sz), 0) / trades16.value.length
  return avg * 4
})

const fundingText = computed(() => {
  if (!isSwap.value) return '--'
  const r = Number(funding.value?.fundingRate)
  if (isNaN(r)) return '--'
  return (r >= 0 ? '+' : '') + (r * 100).toFixed(4) + '%'
})

function tickCountdown() {
  const t = Number(funding.value?.nextFundingTime)
  if (!t) { fCountdown.value = '--'; return }
  let d = Math.max(0, t - Date.now())
  const p = (x) => String(x).padStart(2, '0')
  const h = Math.floor(d / 3600000); d %= 3600000
  const m = Math.floor(d / 60000)
  const s = Math.floor((d % 60000) / 1000)
  fCountdown.value = `${p(h)}:${p(m)}:${p(s)}`
}

async function loadTicker() {
  try {
    const res = await marketApi.ticker(instId.value)
    ticker.value = res?.data?.[0] || null
  } catch { /* 保留旧值 */ }
}
async function loadCandles() {
  try {
    const res = await marketApi.candles(instId.value, bar.value, 120)
    candles.value = (res?.data || []).reverse() // OKX 新在前
  } catch { /* ignore */ }
}
async function loadBooks() {
  try {
    const res = await marketApi.books(instId.value, 14)
    const d = res?.data?.[0]
    if (d) books.value = { bids: d.bids || [], asks: (d.asks || []).slice().reverse() }
  } catch { /* ignore */ }
}
async function loadTrades() {
  try {
    const res = await marketApi.trades(instId.value, 30)
    trades.value = res?.data || []
  } catch { /* ignore */ }
}
async function loadFunding() {
  if (!isSwap.value) { funding.value = null; return }
  try {
    const res = await marketApi.fundingRate(instId.value)
    funding.value = res?.data?.[0] || null
  } catch { /* ignore */ }
}

function loadAll() {
  loadTicker()
  loadCandles()
  loadBooks()
  loadTrades()
  loadFunding()
}

watch(bar, loadCandles)
watch(instId, () => { loadAll(); syncWatched() })

onMounted(() => {
  loadAll()
  syncWatched()
  timer = setInterval(() => { loadTicker(); loadBooks(); loadTrades() }, 8000)
  cdTimer = setInterval(tickCountdown, 1000)
})
onBeforeUnmount(() => { clearInterval(timer); clearInterval(cdTimer) })
</script>

<template>
  <!-- 定高布局: 左 K线 / 右 盘口+成交, 高度拉满视口 -->
  <div class="flex flex-col gap-3" style="height: calc(100vh - 56px - 72px)">
    <!-- A. 顶部报价条 -->
    <section class="w-full bg-card-navy border border-hairline rounded-xl p-3.5 flex items-center justify-between select-none flex-wrap gap-4">
      <div class="flex items-center gap-6 flex-wrap">
        <!-- 币种图标 + 名称 -->
        <div class="flex items-center gap-3 pr-6 border-r border-hairline">
          <div
            class="w-9 h-9 rounded-full flex items-center justify-center font-bold font-mono-data text-base"
            :class="coin === 'BTC' ? 'bg-[#F7931A]/10 border border-[#F7931A]/30 text-[#F7931A]' : 'bg-primary-container/15 border border-primary-container/40 text-primary'"
          >{{ coin === 'BTC' ? '₿' : coin.slice(0, 1) }}</div>
          <div class="flex flex-col">
            <div class="flex items-center gap-2">
              <h1 class="font-headline-md text-headline-md font-bold text-ink-white">{{ coinName }}</h1>
              <span class="font-mono-data text-mono-data text-steel-muted font-medium">{{ coin }}/USDT</span>
            </div>
            <div class="flex items-center gap-1.5 mt-0.5">
              <span
                class="px-1.5 py-0.5 text-[10px] font-label-sm rounded"
                :class="isSwap ? 'bg-surface-slate border border-hairline text-steel-muted' : 'bg-primary-container/20 border border-primary-container/40 text-primary'"
              >现货 SPOT</span>
              <span
                class="px-1.5 py-0.5 text-[10px] font-label-sm rounded"
                :class="isSwap ? 'bg-primary-container/20 border border-primary-container/40 text-primary' : 'bg-surface-slate border border-hairline text-steel-muted'"
              >PERP 永续</span>
            </div>
          </div>
        </div>
        <!-- 大价显示 -->
        <div class="flex items-baseline gap-3">
          <span class="font-mono-data text-headline-lg font-bold tracking-tight" :class="up ? 'text-bull-green' : 'text-bear-red'">${{ fmtPrice(ticker?.last) }}</span>
          <div
            class="px-2 py-0.5 rounded font-mono-data text-label-sm font-semibold flex items-center gap-0.5"
            :class="up ? 'bg-bull-green/10 border border-bull-green/30 text-bull-green' : 'bg-bear-red/10 border border-bear-red/30 text-bear-red'"
          >
            <span class="material-symbols-outlined text-[12px]">{{ up ? 'arrow_upward' : 'arrow_downward' }}</span>
            <span>{{ fmtPct(pct()) }}</span>
          </div>
        </div>
        <!-- 指标网格 -->
        <div class="flex items-center gap-5 pl-4 border-l border-hairline font-mono-data text-label-sm flex-wrap">
          <div class="flex flex-col">
            <span class="text-steel-muted text-[10px]">24H 最高</span>
            <span class="text-ink-white font-medium">${{ fmtPrice(ticker?.high24h) }}</span>
          </div>
          <div class="flex flex-col">
            <span class="text-steel-muted text-[10px]">24H 最低</span>
            <span class="text-ink-white font-medium">${{ fmtPrice(ticker?.low24h) }}</span>
          </div>
          <div class="flex flex-col">
            <span class="text-steel-muted text-[10px]">24H 成交量({{ coin }})</span>
            <span class="text-ink-white font-medium">{{ fmtNum(ticker?.vol24h, 2) }}</span>
          </div>
          <div class="flex flex-col">
            <span class="text-steel-muted text-[10px]">24H 成交额(USDT)</span>
            <span class="text-ink-white font-medium">${{ fmtBig(ticker?.volCcy24h) }}</span>
          </div>
          <div class="flex flex-col">
            <span class="text-steel-muted text-[10px]">资金费率 / 倒计时</span>
            <span class="font-medium" :class="isSwap ? 'text-bull-green' : 'text-steel-muted'">
              {{ fundingText }}
              <span v-if="isSwap" class="text-steel-muted text-[10px]">{{ fCountdown }}</span>
            </span>
          </div>
        </div>
      </div>
      <!-- 操作按钮 -->
      <div class="flex items-center gap-2.5">
        <button
          class="h-9 px-3 bg-surface-slate hover:bg-card-navy-high border border-hairline rounded font-headline-sm text-headline-sm flex items-center gap-1.5 transition-colors cursor-pointer"
          :class="watched ? 'text-amber-warn' : 'text-primary'"
          @click="toggleWatch"
        >
          <span
            class="material-symbols-outlined"
            :class="watched ? 'text-amber-warn' : 'text-primary'"
            :style="watched ? 'font-variation-settings: &quot;FILL&quot; 1' : ''"
          >star</span>
          <span>{{ watched ? '已自选' : '加入自选' }}</span>
        </button>
        <button class="h-9 px-4 bg-primary-container hover:bg-inverse-primary text-ink-white rounded font-headline-sm text-headline-sm font-medium flex items-center gap-1.5 transition-colors cursor-pointer shadow-none">
          <span class="material-symbols-outlined">notifications_active</span>
          <span>设置价格预警</span>
        </button>
      </div>
    </section>

    <!-- B+C. 左 K线 / 右栏(盘口上, 成交下) -->
    <div class="flex gap-3 w-full flex-1 min-h-0">
    <!-- B. K 线图 -->
    <section class="flex-1 min-w-0 bg-card-navy border border-hairline rounded-xl flex flex-col overflow-hidden">
      <div class="h-10 px-3 bg-surface-slate border-b border-hairline flex items-center justify-between select-none">
        <div class="flex items-center gap-0.5 font-label-sm text-label-sm">
          <button
            v-for="b in bars"
            :key="b"
            class="px-2 py-1 transition-colors cursor-pointer"
            :class="bar === b ? 'text-ink-white font-semibold border-b-2 border-primary-container bg-card-navy' : 'text-steel-muted hover:text-ink-white rounded'"
            @click="bar = b"
          >{{ b }}</button>
        </div>
        <!-- MA 指标读数 -->
        <div class="hidden lg:flex items-center gap-3 pl-3 ml-1 border-l border-hairline font-mono-data text-[10px]">
          <span v-for="m in maLegend" :key="m.name" class="flex items-center gap-1">
            <span class="font-semibold" :style="{ color: m.color }">{{ m.name }}</span>
            <span class="text-ink-white">{{ m.value }}</span>
          </span>
        </div>
        <div class="flex items-center gap-2 text-steel-muted">
          <span class="font-mono-data text-[11px] mr-2">OKX · {{ bar }}</span>
          <button
            class="p-1 cursor-pointer transition-colors"
            :class="crossOn ? 'text-primary' : 'hover:text-ink-white'"
            title="十字光标"
            @click="toggleCross"
          ><span class="material-symbols-outlined">adjust</span></button>
          <button class="p-1 hover:text-ink-white cursor-pointer" title="重置缩放" @click="resetZoom"><span class="material-symbols-outlined">restart_alt</span></button>
          <button class="p-1 hover:text-ink-white cursor-pointer" title="全屏图表" @click="toggleFullscreen"><span class="material-symbols-outlined">fullscreen</span></button>
        </div>
      </div>
      <div ref="chartWrap" class="relative w-full flex-1 min-h-0 bg-canvas-obsidian">
        <EChart ref="kchart" :option="klineOption" height="100%" />
      </div>
    </section>

    <!-- C. 右栏: 盘口深度 + 逐笔成交 -->
    <section class="w-96 flex-shrink-0 hidden md:flex flex-col gap-3 min-h-0">
      <!-- 上: 盘口深度 -->
      <div class="flex-[1.25] min-h-0 bg-card-navy border border-hairline rounded-xl flex flex-col overflow-hidden">
        <div class="min-h-10 px-3 py-1 bg-surface-slate border-b border-hairline flex items-center justify-between flex-wrap gap-x-3 gap-y-1 select-none">
          <div class="flex items-center gap-2">
            <span class="font-headline-sm text-headline-sm font-semibold text-ink-white">盘口深度</span>
            <span class="font-mono-data text-[11px] text-steel-muted hidden lg:inline">L2 ORDERBOOK</span>
          </div>
          <div class="flex items-center gap-2">
            <div class="flex items-center gap-1.5 font-mono-data text-[10px]">
              <span class="text-bull-green">买 {{ buyPct }}%</span>
              <div class="w-14 h-1.5 bg-surface-slate rounded-full overflow-hidden flex border border-hairline">
                <div class="bg-bull-green h-full" :style="{ width: buyPct + '%' }"></div>
                <div class="bg-bear-red h-full" :style="{ width: (100 - buyPct) + '%' }"></div>
              </div>
              <span class="text-bear-red">{{ 100 - buyPct }}% 卖</span>
            </div>
            <!-- 精度切换 (对齐设计稿) -->
            <div class="hidden md:flex items-center border border-hairline rounded overflow-hidden font-mono-data text-[10px]">
              <button
                v-for="p in PRECISIONS"
                :key="p"
                class="px-2 py-0.5 transition-colors"
                :class="precision === p ? 'bg-card-navy-high text-ink-white font-medium' : 'bg-surface-slate text-steel-muted hover:text-ink-white'"
                @click="precision = p"
              >{{ p.toFixed(2).replace(/0+$/, '').replace(/\.$/, '.0') }}</button>
            </div>
          </div>
        </div>
        <div class="grid grid-cols-3 px-3 py-1.5 bg-surface-slate/50 border-b border-hairline font-label-sm text-[10px] text-steel-muted uppercase select-none">
          <div class="text-left">价格 (USD)</div>
          <div class="text-right">数量 ({{ coin }})</div>
          <div class="text-right">累计深度 ({{ coin }})</div>
        </div>
        <div class="flex-1 min-h-0 overflow-y-auto flex flex-col font-mono-data text-[12px] select-none justify-between">
          <!-- 卖盘 -->
          <div class="flex flex-col justify-end flex-1">
            <div v-for="(a, i) in askRows" :key="'a' + i" class="relative grid grid-cols-3 px-3 py-px leading-[16px] hover:bg-card-navy-high/50 cursor-pointer">
              <div class="absolute right-0 top-0 bottom-0 bg-bear-red/15" :style="{ width: a.w + '%' }"></div>
              <div class="text-bear-red font-medium relative z-10">{{ fmtPx(a.px) }}</div>
              <div class="text-right text-ink-white relative z-10">{{ a.sz.toFixed(3) }}</div>
              <div class="text-right text-steel-muted relative z-10">{{ a.cum.toFixed(3) }}</div>
            </div>
          </div>
          <!-- 中间价差条 -->
          <div class="py-1.5 px-3 bg-surface-slate border-y border-hairline flex items-center justify-between flex-wrap gap-2">
            <div class="flex items-center gap-2">
              <span class="font-mono-data text-headline-sm font-bold" :class="up ? 'text-bull-green' : 'text-bear-red'">{{ fmtPrice(ticker?.last) }}</span>
              <span class="material-symbols-outlined text-[14px]" :class="up ? 'text-bull-green' : 'text-bear-red'">{{ up ? 'north' : 'south' }}</span>
              <span class="text-[11px]" :class="up ? 'text-bull-green' : 'text-bear-red'">{{ fmtPct(pct()) }}</span>
            </div>
            <div class="flex items-center gap-4 text-steel-muted text-[11px]">
              <span>价差: <span class="text-ink-white">{{ spread != null ? spread.toFixed(2) : '--' }}</span></span>
            </div>
          </div>
          <!-- 买盘 -->
          <div class="flex flex-col flex-1">
            <div v-for="(b, i) in bidRows" :key="'b' + i" class="relative grid grid-cols-3 px-3 py-px leading-[16px] hover:bg-card-navy-high/50 cursor-pointer">
              <div class="absolute right-0 top-0 bottom-0 bg-bull-green/15" :style="{ width: b.w + '%' }"></div>
              <div class="text-bull-green font-medium relative z-10">{{ fmtPx(b.px) }}</div>
              <div class="text-right text-ink-white relative z-10">{{ b.sz.toFixed(3) }}</div>
              <div class="text-right text-steel-muted relative z-10">{{ b.cum.toFixed(3) }}</div>
            </div>
          </div>
        </div>
      </div>

      <!-- 下: 最新逐笔成交 -->
      <div class="flex-1 min-h-0 bg-card-navy border border-hairline rounded-xl flex flex-col overflow-hidden">
        <div class="h-10 px-3 bg-surface-slate border-b border-hairline flex items-center justify-between select-none">
          <div class="flex items-center gap-2">
            <span class="font-headline-sm text-headline-sm font-semibold text-ink-white">最新逐笔成交</span>
            <span class="font-mono-data text-[11px] text-steel-muted">RECENT TRADES</span>
          </div>
          <div class="flex items-center gap-1.5 font-mono-data text-[11px] text-bull-green">
            <span class="w-1.5 h-1.5 rounded-full bg-bull-green"></span>
            <span>8S POLLING</span>
          </div>
        </div>
        <div class="grid grid-cols-3 px-3 py-1.5 bg-surface-slate/50 border-b border-hairline font-label-sm text-[10px] text-steel-muted uppercase select-none">
          <div class="text-left">时间</div>
          <div class="text-center">价格 (USD)</div>
          <div class="text-right">数量 ({{ coin }})</div>
        </div>
        <div class="flex-1 min-h-0 overflow-y-auto flex flex-col font-mono-data text-[12px] divide-y divide-hairline/20 select-none">
          <div
            v-for="(t, i) in trades16"
            :key="i"
            class="grid grid-cols-3 px-3 py-1 hover:bg-card-navy-high/50"
            :class="Number(t.sz) >= whaleQty ? (t.side === 'buy' ? 'bg-bull-green/5' : 'bg-bear-red/5') : ''"
          >
            <span class="text-steel-muted">{{ fmtTime(t.ts) }}</span>
            <span class="text-center font-medium" :class="t.side === 'buy' ? 'text-bull-green' : 'text-bear-red'">{{ fmtPrice(t.px) }}</span>
            <span
              class="text-right flex items-center justify-end gap-1"
              :class="Number(t.sz) >= whaleQty ? (t.side === 'buy' ? 'text-bull-green font-bold' : 'text-bear-red font-bold') : 'text-ink-white'"
            >
              <span
                v-if="Number(t.sz) >= whaleQty"
                class="text-[10px] px-1 rounded"
                :class="t.side === 'buy' ? 'bg-bull-green/20' : 'bg-bear-red/20'"
              >⚡ WHALE</span>
              <span>{{ Number(t.sz).toFixed(3) }}</span>
            </span>
          </div>
          <div v-if="!trades16.length" class="p-6 text-center text-steel-muted text-[11px]">暂无成交数据</div>
        </div>
      </div>
    </section>
    </div>
  </div>
</template>
