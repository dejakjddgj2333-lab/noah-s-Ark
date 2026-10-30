<script setup>
import { onMounted, onBeforeUnmount, ref, computed, watch } from 'vue'
import { useRoute } from 'vue-router'
import KLine from '../components/KLine.vue'
import { marketApi, alertApi } from '../api'
import { fmtPrice, fmtPct, fmtBig, fmtNum, fmtTime, coinOf } from '../utils/format'
import { inWatchlist, toggleWatchlist, syncWatchlist } from '../utils/watchlist'
import { subscribeMarket, marketWsAlive } from '../utils/marketWs'

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
  kchart.value?.reset()
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

// ---- 价格预警 (触发后 APNs + 邮件) ----
const alertOpen = ref(false)
const alerts = ref([])
const alertDir = ref('up')
const alertPrice = ref('')
const alertMsg = ref('')
const alertOk = ref(false)
const alertBusy = ref(false)
// WS 连接状态 (1s 刷新, 驱动 LIVE/POLLING 指示)
const wsLive = ref(false)

function openAlerts() {
  alertOpen.value = true
  alertMsg.value = ''
  alertOk.value = false
  alertDir.value = 'up'
  alertPrice.value = ticker.value?.last || ''
  loadAlerts()
}
async function loadAlerts() {
  try {
    const res = await alertApi.list()
    const all = res?.alerts || []
    alerts.value = all.filter((a) => a.symbol === coin.value || a.symbol === `${coin.value}USDT`)
  } catch { /* 未登录等: 列表留空 */ }
}
async function createAlert() {
  const px = Number(alertPrice.value)
  if (!px || px <= 0) { alertOk.value = false; alertMsg.value = '请输入有效的预警价'; return }
  alertBusy.value = true
  alertMsg.value = ''
  try {
    await alertApi.create({ symbol: coin.value, alert_type: 'price', direction: alertDir.value, target_price: px })
    alertOk.value = true
    alertMsg.value = '已设置, 触发后 App 推送 + 邮件提醒'
    alertPrice.value = ''
    loadAlerts()
  } catch (e) {
    alertOk.value = false
    alertMsg.value = e?.message || '设置失败, 请先登录'
  } finally {
    alertBusy.value = false
  }
}
async function removeAlert(a) {
  try { await alertApi.remove(a.id); loadAlerts() } catch { /* ignore */ }
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

// ---- 行情 WS 实时推送: 挂上等 WS, WS 断开时 8s 轮询兜底 ----
let unsubs = []
function unbindWs() {
  unsubs.forEach((u) => u())
  unsubs = []
}
function bindWs(inst) {
  unbindWs()
  // 最新价
  unsubs.push(subscribeMarket('tickers', inst, (frame) => {
    const d = frame?.data?.[0]
    if (d) ticker.value = d
  }))
  // 逐笔成交: 新帧前置, tradeId 去重
  unsubs.push(subscribeMarket('trades', inst, (frame) => {
    const data = frame?.data
    if (!Array.isArray(data) || !data.length) return
    const seen = new Set(trades.value.slice(0, 40).map((t) => t.tradeId))
    const fresh = data.filter((t) => !seen.has(t.tradeId))
    if (fresh.length) trades.value = [...fresh, ...trades.value].slice(0, 60)
  }))
  // 五档盘口
  unsubs.push(subscribeMarket('books5', inst, (frame) => {
    const d = frame?.data?.[0]
    if (d) books.value = { bids: d.bids || [], asks: (d.asks || []).slice().reverse() }
  }))
}

watch(bar, loadCandles)
watch(instId, () => { loadAll(); syncWatched(); bindWs(instId.value) })

onMounted(() => {
  loadAll()
  syncWatched()
  // 服务器自选同步完成后刷新星标 (多端一致)
  syncWatchlist().then(syncWatched)
  bindWs(instId.value)
  // WS 断开才轮询兜底 (WS 活着时数据已实时)
  timer = setInterval(() => {
    if (!marketWsAlive()) { loadTicker(); loadBooks(); loadTrades() }
  }, 8000)
  cdTimer = setInterval(() => { tickCountdown(); wsLive.value = marketWsAlive() }, 1000)
})
onBeforeUnmount(() => { clearInterval(timer); clearInterval(cdTimer); unbindWs() })
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
        <button
          class="h-9 px-4 bg-primary-container hover:bg-inverse-primary text-ink-white rounded font-headline-sm text-headline-sm font-medium flex items-center gap-1.5 transition-colors cursor-pointer shadow-none"
          @click="openAlerts"
        >
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
        <KLine ref="kchart" :candles="candles" :magnet="crossOn" />
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
          <div
            class="flex items-center gap-1.5 font-mono-data text-[11px]"
            :class="wsLive ? 'text-bull-green' : 'text-steel-muted'"
          >
            <span
              class="w-1.5 h-1.5 rounded-full"
              :class="wsLive ? 'bg-bull-green animate-pulse' : 'bg-steel-muted'"
            ></span>
            <span>{{ wsLive ? 'LIVE · WS' : '8S POLLING' }}</span>
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

    <!-- 价格预警弹窗 -->
    <div
      v-if="alertOpen"
      class="fixed inset-0 z-50 bg-canvas-obsidian/70 backdrop-blur-sm flex items-center justify-center p-4"
      @click.self="alertOpen = false"
    >
      <div class="w-full max-w-md bg-card-navy border border-hairline rounded-xl overflow-hidden">
        <div class="h-11 px-4 bg-surface-slate border-b border-hairline flex items-center justify-between select-none">
          <span class="font-headline-sm text-headline-sm font-semibold text-ink-white">{{ coin }}/USDT 价格预警</span>
          <button class="text-steel-muted hover:text-ink-white cursor-pointer" @click="alertOpen = false">
            <span class="material-symbols-outlined">close</span>
          </button>
        </div>
        <div class="p-4 flex flex-col gap-3">
          <!-- 新建 -->
          <div class="flex items-center gap-2">
            <div class="flex border border-hairline rounded overflow-hidden font-label-sm text-label-sm">
              <button
                class="px-3 py-1.5 transition-colors cursor-pointer"
                :class="alertDir === 'up' ? 'bg-bull-green/15 text-bull-green font-semibold' : 'text-steel-muted hover:text-ink-white'"
                @click="alertDir = 'up'"
              >涨破 ≥</button>
              <button
                class="px-3 py-1.5 transition-colors cursor-pointer"
                :class="alertDir === 'down' ? 'bg-bear-red/15 text-bear-red font-semibold' : 'text-steel-muted hover:text-ink-white'"
                @click="alertDir = 'down'"
              >跌破 ≤</button>
            </div>
            <input
              v-model="alertPrice"
              type="number"
              min="0"
              step="any"
              placeholder="预警价 USD"
              class="flex-1 min-w-0 h-9 px-3 bg-surface-slate border border-hairline rounded font-mono-data text-label-sm text-ink-white placeholder:text-steel-muted focus:border-primary-container focus:outline-none"
            />
            <button
              class="h-9 px-4 bg-primary-container hover:bg-inverse-primary text-ink-white rounded font-headline-sm text-headline-sm font-medium transition-colors cursor-pointer disabled:opacity-50"
              :disabled="alertBusy"
              @click="createAlert"
            >{{ alertBusy ? '提交中' : '添加' }}</button>
          </div>
          <div class="text-[11px] text-steel-muted">现价 ${{ fmtPrice(ticker?.last) }} · 触发后 App 推送 + 注册邮箱邮件提醒, 单次有效</div>
          <div v-if="alertMsg" class="text-[12px]" :class="alertOk ? 'text-bull-green' : 'text-bear-red'">{{ alertMsg }}</div>
          <!-- 我的预警 -->
          <div class="border-t border-hairline pt-2 flex flex-col divide-y divide-hairline/30 max-h-56 overflow-y-auto">
            <div v-for="a in alerts" :key="a.id" class="py-2 flex items-center justify-between font-mono-data text-[12px]">
              <span class="flex items-center gap-2">
                <span :class="a.direction === 'up' ? 'text-bull-green' : 'text-bear-red'">
                  {{ a.direction === 'up' ? '≥' : '≤' }} {{ fmtPrice(a.alert_type === 'percent' ? null : a.target_price) }}
                </span>
                <span v-if="a.alert_type === 'percent'" class="text-steel-muted">{{ a.direction === 'up' ? '涨' : '跌' }} {{ a.percent }}% (基准 {{ fmtPrice(a.baseline_price) }})</span>
                <span v-if="a.triggered" class="px-1.5 py-0.5 text-[10px] rounded bg-surface-slate text-steel-muted">已触发</span>
              </span>
              <button class="text-steel-muted hover:text-bear-red cursor-pointer" title="删除" @click="removeAlert(a)">
                <span class="material-symbols-outlined text-[16px]">delete</span>
              </button>
            </div>
            <div v-if="!alerts.length" class="py-4 text-center text-steel-muted text-[11px]">该币种暂无预警</div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
