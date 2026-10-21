<script setup>
import { onMounted, onBeforeUnmount, ref, computed } from 'vue'
import { useRouter } from 'vue-router'
import EChart from '../components/EChart.vue'
import { overviewApi, marketApi, newsApi } from '../api'
import { fmtUsd, fmtPct, fmtBig, fmtPrice, fmtTime, fmtAgo, coinOf, ts } from '../utils/format'

const router = useRouter()

// 纯展示: 币种标签 chip (对齐设计稿涨幅榜)
const COIN_TAGS = {
  BTC: 'POW', ETH: 'L1', SOL: 'HIGH-TPS', SUI: 'MOVE', TAO: 'DE-AI',
  RENDER: 'AI/GPU', XRP: 'PAYMENT', DOGE: 'MEME', ADA: 'L1', LINK: 'ORACLE',
  AVAX: 'L1', TON: 'L1', BNB: 'CEX', DOT: 'L0', NEAR: 'L1', FET: 'AI',
}

const stats = ref({})
const sentiment = ref(null)
const lsRatio = ref({})
const gainers = ref([])
const allRows = ref([]) // TOP30 按成交额, 供涨幅榜 tab 过滤
const gainerTab = ref('main')
const GAINER_TABS = [
  { key: 'main', label: '主流币' },
  { key: 'aidefi', label: 'AI / DeFi' },
  { key: 'new', label: '新上线' },
]
const sparks = ref({}) // instId -> closes[]
const newsList = ref([])
const wireFilter = ref('all')
const WIRE_FILTERS = [
  { key: 'all', label: '全部快讯', kws: [] },
  { key: 'whale', label: '巨鲸异动', kws: ['巨鲸', 'whale', '鲸鱼', '大户'] },
  { key: 'liq', label: '宏观清算', kws: ['清算', '爆仓', 'liquidat', '宏观', '美联储', '加息', '降息'] },
  { key: 'chain', label: '链上异动', kws: ['链上', 'on-chain', 'onchain', '流入', '流出', '转账'] },
]
const filteredNews = computed(() => {
  const f = WIRE_FILTERS.find((x) => x.key === wireFilter.value)
  if (!f || !f.kws.length) return newsList.value
  return newsList.value.filter((n) => {
    const text = `${n.title || ''} ${n.summary || ''} ${n.content || ''}`.toLowerCase()
    return f.kws.some((kw) => text.includes(kw.toLowerCase()))
  })
})
const filteredGainers = computed(() => {
  if (gainerTab.value === 'aidefi') {
    return gainers.value.filter((t) => /AI|DEFI/i.test(COIN_TAGS[coinOf(t.instId)] || ''))
  }
  if (gainerTab.value === 'new') {
    return [...allRows.value].sort((a, b) => Number(a.volCcy24h) - Number(b.volCcy24h)).slice(0, 6)
  }
  return gainers.value
})
const btcTicker = ref(null)
const btcCandles = ref([])
const btcBar = ref('1H')
const BTC_BARS = [
  { label: '1M', bar: '1m' },
  { label: '15M', bar: '15m' },
  { label: '1H', bar: '1H' },
  { label: '4H', bar: '4H' },
  { label: '1D', bar: '1D' },
]
async function loadBtcCandles() {
  try {
    const res = await marketApi.candles('BTC-USDT', btcBar.value, 72)
    btcCandles.value = (res?.data || []).reverse()
  } catch { /* 保留旧值 */ }
}
function setBtcBar(b) {
  if (btcBar.value === b) return
  btcBar.value = b
  loadBtcCandles()
}
const funding = ref(null) // BTC 永续资金费率 (%)
const depth = ref({ bid: null, ask: null })
const loading = ref(true)
let timer = null

// ---------- 情绪 ----------
const sentimentLabel = computed(() => {
  const v = sentiment.value
  if (v === null || v === undefined) return '--'
  if (v >= 75) return '极度贪婪'
  if (v >= 50) return '贪婪'
  if (v >= 25) return '恐慌'
  return '极度恐慌'
})
const sentimentEn = computed(() => {
  const v = sentiment.value
  if (v === null || v === undefined) return ''
  if (v >= 75) return 'EXT GREED'
  if (v >= 50) return 'GREED'
  if (v >= 25) return 'FEAR'
  return 'EXT FEAR'
})
const sentimentChipCls = computed(() => {
  const v = sentiment.value
  if (v === null || v === undefined) return 'bg-surface-slate text-steel-muted border-hairline'
  if (v >= 50) return 'bg-bull-green/10 text-bull-green border-bull-green/30'
  if (v >= 25) return 'bg-amber-warn/10 text-amber-warn border-amber-warn/30'
  return 'bg-bear-red/10 text-bear-red border-bear-red/30'
})
const sentimentValueCls = computed(() => {
  const v = sentiment.value
  if (v === null || v === undefined) return 'text-ink-white'
  if (v >= 50) return 'text-bull-green'
  if (v >= 25) return 'text-amber-warn'
  return 'text-bear-red'
})

// ---------- 占比 ----------
const btcDom = computed(() => (stats.value.btc_dominance != null ? Number(stats.value.btc_dominance) : null))
const ethDom = computed(() => (stats.value.eth_dominance != null ? Number(stats.value.eth_dominance) : null))
const otherDom = computed(() => (btcDom.value != null && ethDom.value != null ? 100 - btcDom.value - ethDom.value : null))

// ---------- 多空 ----------
const longPct = computed(() => (lsRatio.value.long_pct != null ? Number(lsRatio.value.long_pct) : null))
const shortPct = computed(() => (lsRatio.value.short_pct != null ? Number(lsRatio.value.short_pct) : null))
const lsText = computed(() => {
  if (longPct.value == null || shortPct.value == null) return '--'
  return (longPct.value / Math.max(shortPct.value, 0.01)).toFixed(2) + ':1'
})
const lsLead = computed(() => {
  if (longPct.value == null || shortPct.value == null) return { text: '--', cls: 'text-steel-muted' }
  return longPct.value >= shortPct.value
    ? { text: '多头主导', cls: 'text-bull-green' }
    : { text: '空头主导', cls: 'text-bear-red' }
})

function pct(t) {
  const open = Number(t?.open24h)
  if (!open) return 0
  return ((Number(t.last) - open) / open) * 100
}

// ---------- 涨幅榜 sparkline ----------
function sparkOption(closes) {
  const up = closes.length > 1 && closes[closes.length - 1] >= closes[0]
  const color = up ? '#00E388' : '#FF5F6D'
  return {
    grid: { left: 0, right: 0, top: 2, bottom: 2 },
    xAxis: { type: 'category', show: false, data: closes.map((_, i) => i), boundaryGap: false },
    yAxis: { type: 'value', show: false, scale: true },
    series: [{
      type: 'line',
      data: closes,
      showSymbol: false,
      smooth: 0.3,
      lineStyle: { color, width: 1.5 },
    }],
  }
}

// ---------- BTC 迷你 K 线 ----------
const UP = '#00E388'
const DOWN = '#FF5F6D'

function maSeries(closes, n) {
  return closes.map((_, i) => {
    if (i < n - 1) return null
    const seg = closes.slice(i - n + 1, i + 1)
    return +(seg.reduce((s, v) => s + v, 0) / n).toFixed(2)
  })
}

const btcCloses = computed(() => btcCandles.value.map((c) => +c[4]))
const ma7Last = computed(() => {
  const m = maSeries(btcCloses.value, 7)
  return m.length ? m[m.length - 1] : null
})
const ma25Last = computed(() => {
  const m = maSeries(btcCloses.value, 25)
  return m.length ? m[m.length - 1] : null
})

const btcChartOption = computed(() => {
  const rows = btcCandles.value.slice(-36)
  if (!rows.length) return {}
  const cats = rows.map((_, i) => i)
  const kdata = rows.map((c) => [+c[1], +c[4], +c[3], +c[2]]) // o c l h
  const closes = rows.map((c) => +c[4])
  const vols = rows.map((c) => +c[5])
  // 视图内最高/最低 + 最新价
  let hi = -Infinity, lo = Infinity, hiI = 0, loI = 0
  kdata.forEach((d, i) => {
    if (d[3] > hi) { hi = d[3]; hiI = i }
    if (d[2] < lo) { lo = d[2]; loI = i }
  })
  const lastUp = kdata[kdata.length - 1][1] >= kdata[kdata.length - 1][0]
  const lastColor = lastUp ? UP : DOWN
  const fmtK = (v) => Number(v).toLocaleString('en-US', { maximumFractionDigits: 1 })
  return {
    animation: false,
    grid: [
      { left: 2, right: 52, top: 10, height: '64%' },
      { left: 2, right: 52, top: '78%', height: '18%' },
    ],
    xAxis: [
      { type: 'category', show: false, data: cats },
      { type: 'category', show: false, data: cats, gridIndex: 1 },
    ],
    yAxis: [
      { type: 'value', show: false, scale: true },
      { type: 'value', show: false, scale: true, gridIndex: 1 },
    ],
    series: [
      {
        type: 'candlestick',
        data: kdata,
        barWidth: '55%',
        itemStyle: { color: UP, color0: DOWN, borderColor: UP, borderColor0: DOWN },
        markPoint: {
          symbol: 'circle',
          symbolSize: 0.1,
          label: {
            show: true,
            fontSize: 9,
            fontFamily: 'JetBrains Mono',
            color: '#F0F0FF',
            backgroundColor: 'rgba(13,21,40,0.85)',
            borderColor: '#34415E',
            borderWidth: 1,
            borderRadius: 3,
            padding: [1, 4],
          },
          data: [
            { coord: [hiI, hi], value: fmtK(hi), label: { position: 'top' } },
            { coord: [loI, lo], value: fmtK(lo), label: { position: 'bottom' } },
          ],
        },
        markLine: {
          symbol: 'none',
          silent: true,
          animation: false,
          label: {
            show: true,
            position: 'insideEndTop',
            fontSize: 9,
            fontFamily: 'JetBrains Mono',
            color: '#070D1C',
            backgroundColor: lastColor,
            borderRadius: 2,
            padding: [1, 4],
            formatter: () => fmtK(kdata[kdata.length - 1][1]),
          },
          lineStyle: { color: lastColor, type: 'dashed', width: 1, opacity: 0.8 },
          data: [{ yAxis: kdata[kdata.length - 1][1] }],
        },
      },
      { type: 'line', data: maSeries(closes, 7), showSymbol: false, smooth: 0.3, lineStyle: { color: '#2E5CFF', width: 1.5 } },
      { type: 'line', data: maSeries(closes, 25), showSymbol: false, smooth: 0.3, lineStyle: { color: '#F7B733', width: 1.2, type: 'dashed' } },
      {
        type: 'bar',
        xAxisIndex: 1,
        yAxisIndex: 1,
        barWidth: '55%',
        data: kdata.map((k, i) => ({
          value: vols[i],
          itemStyle: { color: k[1] >= k[0] ? 'rgba(0,227,136,0.55)' : 'rgba(255,95,109,0.55)' },
        })),
      },
    ],
  }
})

// ---------- 盘口 ----------
const spreadPct = computed(() => {
  const b = Number(depth.value.bid?.[0])
  const a = Number(depth.value.ask?.[0])
  if (!b || !a) return '--'
  return (((a - b) / b) * 100).toFixed(3) + '%'
})

async function load() {
  try {
    const [g, s, ls, tk, nw, bt, bc, fr, bk] = await Promise.allSettled([
      overviewApi.globalStats(),
      overviewApi.sentiment(),
      overviewApi.longShortRatio('BTC'),
      marketApi.tickers('SPOT'),
      newsApi.list({ limit: 8 }),
      marketApi.ticker('BTC-USDT'),
      marketApi.candles('BTC-USDT', btcBar.value, 72),
      marketApi.fundingRate('BTC-USDT-SWAP'),
      marketApi.books('BTC-USDT-SWAP', 5),
    ])
    if (g.status === 'fulfilled') stats.value = g.value
    if (s.status === 'fulfilled') sentiment.value = s.value?.fear_greed ?? null
    if (ls.status === 'fulfilled') lsRatio.value = ls.value || {}
    if (bt.status === 'fulfilled') btcTicker.value = bt.value?.data?.[0] || null
    if (bc.status === 'fulfilled') btcCandles.value = (bc.value?.data || []).reverse()
    if (fr.status === 'fulfilled') {
      const v = Number(fr.value?.data?.[0]?.fundingRate)
      funding.value = isNaN(v) ? null : v * 100
    }
    if (bk.status === 'fulfilled') {
      const d = bk.value?.data?.[0] || {}
      depth.value = { bid: d.bids?.[0] || null, ask: d.asks?.[0] || null }
    }
    if (tk.status === 'fulfilled') {
      const rows = (tk.value?.data || [])
        .filter((t) => t.instId.endsWith('-USDT'))
        .sort((a, b) => Number(b.volCcy24h) - Number(a.volCcy24h))
        .slice(0, 30)
      gainers.value = [...rows].sort((a, b) => pct(b) - pct(a)).slice(0, 6)
      allRows.value = rows
      // 每个上榜币拉 24 根 1H 收盘做 sparkline
      const results = await Promise.allSettled(
        gainers.value.map((t) => marketApi.candles(t.instId, '1H', 24))
      )
      const map = {}
      results.forEach((r, i) => {
        if (r.status === 'fulfilled') {
          map[gainers.value[i].instId] = (r.value?.data || []).reverse().map((c) => +c[4])
        }
      })
      sparks.value = map
    }
    if (nw.status === 'fulfilled') {
      const d = nw.value
      newsList.value = (d.items || d.data || d || []).slice(0, 6)
    }
  } finally {
    loading.value = false
  }
}

onMounted(() => {
  load()
  timer = setInterval(load, 30000)
})
onBeforeUnmount(() => clearInterval(timer))
</script>

<template>
  <div v-if="loading" class="text-steel-muted font-mono-data text-body-md py-space-xl">数据加载中…</div>
  <div v-else class="flex flex-col gap-space-lg">
    <!-- ROW 1: 4 STATS CARDS -->
    <section class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-gutter">
      <!-- Card 1: 全网总市值 -->
      <div class="bg-card-navy border border-hairline rounded-xl p-space-md flex flex-col justify-between hover:border-primary-container/60 transition-colors duration-150">
        <div class="flex items-center justify-between text-steel-muted">
          <span class="font-label-sm text-label-sm uppercase tracking-wider">GLOBAL MARKET CAP</span>
          <span class="material-symbols-outlined text-[18px] text-steel-muted">public</span>
        </div>
        <div class="mt-2">
          <div class="text-[11px] text-steel-muted">全网总市值</div>
          <div class="font-mono-data text-2xl font-bold text-ink-white tracking-tight mt-0.5">{{ fmtUsd(stats.total_market_cap_usd) }}</div>
        </div>
        <div class="mt-3 pt-2.5 border-t border-hairline flex items-center justify-between text-[11px] font-mono-data">
          <div class="flex items-center gap-1" :class="Number(stats.market_cap_change_pct_24h) >= 0 ? 'text-bull-green' : 'text-bear-red'">
            <span class="material-symbols-outlined text-[14px]">{{ Number(stats.market_cap_change_pct_24h) >= 0 ? 'arrow_drop_up' : 'arrow_drop_down' }}</span>
            <span>{{ fmtPct(stats.market_cap_change_pct_24h) }} 24H</span>
          </div>
          <div class="text-steel-muted">24H 成交 <span class="text-ink-white font-medium">{{ fmtUsd(stats.total_volume_usd) }}</span></div>
        </div>
      </div>
      <!-- Card 2: BTC 市值占比 -->
      <div class="bg-card-navy border border-hairline rounded-xl p-space-md flex flex-col justify-between hover:border-primary-container/60 transition-colors duration-150">
        <div class="flex items-center justify-between text-steel-muted">
          <span class="font-label-sm text-label-sm uppercase tracking-wider">BTC DOMINANCE</span>
          <span class="material-symbols-outlined text-[18px] text-steel-muted">pie_chart</span>
        </div>
        <div class="mt-2">
          <div class="text-[11px] text-steel-muted">BTC 占有率</div>
          <div class="font-mono-data text-2xl font-bold text-ink-white tracking-tight mt-0.5">{{ btcDom != null ? btcDom.toFixed(1) + '%' : '--' }}</div>
        </div>
        <div class="mt-3 pt-2.5 border-t border-hairline flex flex-col gap-1.5">
          <div class="flex items-center justify-between text-[11px] font-mono-data">
            <span class="text-primary-fixed-dim">ETH {{ ethDom != null ? ethDom.toFixed(1) + '%' : '--' }}</span>
            <span class="text-steel-muted">OTHERS {{ otherDom != null ? otherDom.toFixed(1) + '%' : '--' }}</span>
          </div>
          <div class="w-full h-1.5 bg-surface-slate rounded-full overflow-hidden flex border border-hairline">
            <div class="h-full bg-primary-container" :style="{ width: (btcDom ?? 0) + '%' }"></div>
            <div class="h-full bg-steel-muted/40" :style="{ width: (100 - (btcDom ?? 0)) + '%' }"></div>
          </div>
        </div>
      </div>
      <!-- Card 3: 多空账户比 -->
      <div class="bg-card-navy border border-hairline rounded-xl p-space-md flex flex-col justify-between hover:border-primary-container/60 transition-colors duration-150">
        <div class="flex items-center justify-between text-steel-muted">
          <span class="font-label-sm text-label-sm uppercase tracking-wider">MARKET BREADTH</span>
          <span class="material-symbols-outlined text-[18px] text-steel-muted">compare_arrows</span>
        </div>
        <div class="mt-2">
          <div class="text-[11px] text-steel-muted">全局账户多空 (多/空)</div>
          <div class="font-mono-data text-2xl font-bold text-ink-white tracking-tight mt-0.5 flex items-baseline gap-1.5">
            <span class="text-bull-green">{{ longPct != null ? longPct.toFixed(0) + '%' : '--' }}</span>
            <span class="text-steel-muted text-base font-normal">/</span>
            <span class="text-bear-red">{{ shortPct != null ? shortPct.toFixed(0) + '%' : '--' }}</span>
          </div>
        </div>
        <div class="mt-3 pt-2.5 border-t border-hairline flex flex-col gap-1.5">
          <div class="flex items-center justify-between text-[11px] font-mono-data">
            <span :class="lsLead.cls">{{ lsLead.text }}</span>
            <span class="text-steel-muted">多空比 {{ lsText }}</span>
          </div>
          <div class="w-full h-1.5 bg-surface-slate rounded-full overflow-hidden flex border border-hairline">
            <div class="h-full bg-bull-green" :style="{ width: (longPct ?? 50) + '%' }"></div>
            <div class="h-full bg-bear-red" :style="{ width: (shortPct ?? 50) + '%' }"></div>
          </div>
        </div>
      </div>
      <!-- Card 4: 情绪指数 -->
      <div class="bg-card-navy border border-hairline rounded-xl p-space-md flex flex-col justify-between hover:border-primary-container/60 transition-colors duration-150">
        <div class="flex items-center justify-between text-steel-muted">
          <span class="font-label-sm text-label-sm uppercase tracking-wider">SENTIMENT INDEX</span>
          <span class="material-symbols-outlined text-[18px] text-amber-warn">speed</span>
        </div>
        <div class="mt-2 flex items-baseline justify-between">
          <div>
            <div class="text-[11px] text-steel-muted">恐慌贪婪指数</div>
            <div class="font-mono-data text-2xl font-bold tracking-tight mt-0.5 flex items-center gap-2" :class="sentimentValueCls">
              <span>{{ sentiment ?? '--' }}</span>
              <span v-if="sentiment != null" class="px-2 py-0.5 text-xs font-headline-sm rounded border" :class="sentimentChipCls">{{ sentimentLabel }} ({{ sentimentEn }})</span>
            </div>
          </div>
        </div>
        <div class="mt-3 pt-2.5 border-t border-hairline flex items-center justify-between text-[11px] font-mono-data">
          <div class="text-steel-muted">数据源: <span class="text-ink-white">alternative.me</span></div>
          <div v-if="sentiment != null && sentiment >= 75" class="text-amber-warn flex items-center gap-0.5">
            <span class="w-1.5 h-1.5 rounded-full bg-amber-warn"></span>
            <span>极度亢奋临界点</span>
          </div>
          <div v-else class="text-steel-muted flex items-center gap-0.5">
            <span class="w-1.5 h-1.5 rounded-full bg-steel-muted"></span>
            <span>常规波动区间</span>
          </div>
        </div>
      </div>
    </section>

    <!-- ROW 2: 涨幅榜 (7) + BTC 迷你 K 线 (5) -->
    <section class="grid grid-cols-1 lg:grid-cols-12 gap-gutter">
      <!-- TOP GAINERS TABLE -->
      <div class="lg:col-span-7 bg-card-navy border border-hairline rounded-xl p-space-md flex flex-col justify-between">
        <div>
          <div class="flex flex-wrap items-center justify-between gap-2 pb-space-sm border-b border-hairline">
            <div class="flex items-center gap-2">
              <span class="material-symbols-outlined text-primary-container text-[20px]">trending_up</span>
              <h2 class="font-headline-md text-headline-md text-ink-white">24H 涨幅榜 TOP GAINERS</h2>
              <span class="font-mono-data text-[10px] text-steel-muted px-1.5 py-0.5 bg-surface-slate border border-hairline rounded">30s实时</span>
            </div>
            <div class="flex items-center bg-surface-slate p-0.5 rounded border border-hairline text-label-sm font-label-sm">
              <button
                v-for="t in GAINER_TABS"
                :key="t.key"
                class="px-2.5 py-1 transition-colors"
                :class="gainerTab === t.key ? 'bg-card-navy text-ink-white rounded shadow-sm border border-hairline/50' : 'text-steel-muted hover:text-ink-white'"
                @click="gainerTab = t.key"
              >{{ t.label }}</button>
            </div>
          </div>
          <div class="overflow-x-auto mt-2">
            <table class="w-full text-left border-collapse">
              <thead>
                <tr class="border-b border-hairline text-steel-muted font-label-sm text-label-sm tracking-wider uppercase">
                  <th class="py-2.5 pl-1 w-8">#</th>
                  <th class="py-2.5">交易对</th>
                  <th class="py-2.5 text-right">最新价 (USDT)</th>
                  <th class="py-2.5 text-right">24H 涨跌幅</th>
                  <th class="py-2.5 text-right">24H 成交额</th>
                  <th class="py-2.5 text-right pr-2">24H 趋势</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-hairline/60 font-mono-data text-xs">
                <tr v-if="!filteredGainers.length">
                  <td colspan="6" class="py-8 text-center text-steel-muted font-label-sm text-label-sm">该分类暂无上榜币种</td>
                </tr>
                <tr v-for="(t, i) in filteredGainers" :key="t.instId" class="hover:bg-surface-slate/70 transition-colors cursor-pointer" @click="router.push(`/market/${t.instId}`)">
                  <td class="py-2.5 pl-1 text-steel-muted">{{ String(i + 1).padStart(2, '0') }}</td>
                  <td class="py-2.5">
                    <div class="flex items-center gap-2">
                      <span class="font-bold text-ink-white">{{ coinOf(t.instId) }}</span>
                      <span class="text-[10px] text-steel-muted font-normal">{{ t.instId }}</span>
                      <span
                        v-if="COIN_TAGS[coinOf(t.instId)]"
                        class="px-1 text-[9px] bg-card-navy-high border border-hairline rounded text-steel-muted shrink-0"
                      >{{ COIN_TAGS[coinOf(t.instId)] }}</span>
                    </div>
                  </td>
                  <td class="py-2.5 text-right text-ink-white font-semibold">{{ fmtPrice(t.last) }}</td>
                  <td class="py-2.5 text-right">
                    <span
                      class="inline-block px-1.5 py-0.5 rounded text-[11px] font-semibold border"
                      :class="pct(t) >= 0 ? 'bg-bull-green/15 text-bull-green border-bull-green/30' : 'bg-bear-red/15 text-bear-red border-bear-red/30'"
                    >{{ fmtPct(pct(t)) }}</span>
                  </td>
                  <td class="py-2.5 text-right text-steel-muted">{{ fmtBig(t.volCcy24h) }}</td>
                  <td class="py-2.5 text-right pr-2">
                    <EChart v-if="sparks[t.instId]?.length > 1" :option="sparkOption(sparks[t.instId])" height="20px" style="width: 64px" class="inline-block" />
                    <span v-else class="text-steel-muted">--</span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
        <div class="pt-3 border-t border-hairline flex items-center justify-between text-[11px] font-mono-data text-steel-muted">
          <span>展示 TOP 6 · 按 24H 涨跌幅排序 (USDT 现货)</span>
          <button class="hover:text-primary-fixed-dim transition-colors flex items-center gap-0.5 text-ink-white" @click="router.push('/market')">
            <span>进入全维行情矩阵</span>
            <span class="material-symbols-outlined text-[14px]">chevron_right</span>
          </button>
        </div>
      </div>

      <!-- BTC/USDT MINI K-LINE -->
      <div class="lg:col-span-5 bg-card-navy border border-hairline rounded-xl p-space-md flex flex-col justify-between">
        <div>
          <div class="flex items-start justify-between pb-2.5 border-b border-hairline">
            <div>
              <div class="flex items-center gap-2">
                <span class="font-headline-md text-headline-md font-bold text-ink-white tracking-wide">BTC/USDT</span>
                <span class="font-mono-data text-[10px] px-1 bg-primary-container/20 text-primary-fixed-dim border border-primary-container/40 rounded">PERP 永续</span>
                <span class="w-2 h-2 rounded-full bg-bull-green animate-pulse"></span>
              </div>
              <div class="flex items-baseline gap-2 mt-1 font-mono-data">
                <span class="text-xl font-bold text-ink-white">${{ fmtPrice(btcTicker?.last) }}</span>
                <span class="text-xs font-semibold" :class="pct(btcTicker) >= 0 ? 'text-bull-green' : 'text-bear-red'">{{ fmtPct(pct(btcTicker)) }}</span>
              </div>
            </div>
            <div class="flex items-center gap-1 bg-surface-slate p-0.5 rounded border border-hairline text-label-sm font-label-sm">
              <button
                v-for="b in BTC_BARS"
                :key="b.bar"
                class="px-1.5 py-0.5 transition-colors"
                :class="btcBar === b.bar ? 'bg-primary-container text-ink-white rounded' : 'text-steel-muted hover:text-ink-white'"
                @click="setBtcBar(b.bar)"
              >{{ b.label }}</button>
            </div>
          </div>
          <div class="grid grid-cols-3 gap-2 py-2 text-[10px] font-mono-data border-b border-hairline text-steel-muted">
            <div>24H 最高: <span class="text-ink-white font-medium">${{ fmtPrice(btcTicker?.high24h) }}</span></div>
            <div>24H 最低: <span class="text-ink-white font-medium">${{ fmtPrice(btcTicker?.low24h) }}</span></div>
            <div class="text-right">资金率: <span :class="funding != null ? (funding >= 0 ? 'text-bull-green' : 'text-bear-red') : 'text-steel-muted'">{{ funding != null ? fmtPct(funding, 4) : '--' }}</span></div>
          </div>
          <!-- K 线图 -->
          <div class="relative w-full h-44 bg-surface-slate/80 rounded border border-hairline mt-3 overflow-hidden p-2 flex flex-col justify-between">
            <div class="absolute inset-0 flex flex-col justify-between pointer-events-none opacity-20">
              <div class="border-b border-dashed border-steel-muted h-0 w-full"></div>
              <div class="border-b border-dashed border-steel-muted h-0 w-full"></div>
              <div class="border-b border-dashed border-steel-muted h-0 w-full"></div>
              <div class="border-b border-dashed border-steel-muted h-0 w-full"></div>
            </div>
            <div class="flex items-center gap-3 text-[10px] font-mono-data z-10">
              <span class="text-primary-fixed-dim flex items-center gap-1"><span class="w-2 h-0.5 bg-primary-container"></span> MA7: {{ ma7Last != null ? fmtPrice(ma7Last) : '--' }}</span>
              <span class="text-amber-warn flex items-center gap-1"><span class="w-2 h-0.5 bg-amber-warn"></span> MA25: {{ ma25Last != null ? fmtPrice(ma25Last) : '--' }}</span>
            </div>
            <EChart :option="btcChartOption" height="132px" />
          </div>
        </div>
        <!-- 盘口微件 -->
        <div class="mt-3 p-2 bg-surface-slate rounded border border-hairline font-mono-data text-[11px] flex items-center justify-between">
          <div class="flex items-center gap-1.5">
            <span class="text-steel-muted">买一:</span>
            <span class="text-bull-green font-semibold">{{ depth.bid ? fmtPrice(depth.bid[0]) : '--' }}</span>
            <span class="text-steel-muted text-[10px]">({{ depth.bid ? fmtBig(depth.bid[1]) + ' BTC' : '--' }})</span>
          </div>
          <div class="text-steel-muted text-[10px] px-1 bg-card-navy border border-hairline rounded">点差 {{ spreadPct }}</div>
          <div class="flex items-center gap-1.5">
            <span class="text-steel-muted">卖一:</span>
            <span class="text-bear-red font-semibold">{{ depth.ask ? fmtPrice(depth.ask[0]) : '--' }}</span>
            <span class="text-steel-muted text-[10px]">({{ depth.ask ? fmtBig(depth.ask[1]) + ' BTC' : '--' }})</span>
          </div>
        </div>
      </div>
    </section>

    <!-- ROW 3: 实时情报快讯 -->
    <section class="bg-card-navy border border-hairline rounded-xl p-space-md flex flex-col gap-space-sm">
      <div class="flex flex-wrap items-center justify-between gap-2 pb-space-sm border-b border-hairline">
        <div class="flex items-center gap-2">
          <span class="material-symbols-outlined text-primary-container text-[20px]">rss_feed</span>
          <h2 class="font-headline-md text-headline-md text-ink-white">TERMINAL INTEL WIRE 实时情报快讯</h2>
          <span class="flex items-center gap-1 px-2 py-0.5 rounded-full bg-bull-green/10 border border-bull-green/30 text-bull-green text-[10px] font-mono-data">
            <span class="w-1.5 h-1.5 rounded-full bg-bull-green animate-ping"></span>
            LIVE RADAR
          </span>
        </div>
        <div class="flex items-center gap-1.5 text-label-sm font-label-sm">
          <button
            v-for="f in WIRE_FILTERS"
            :key="f.key"
            class="px-2.5 py-1 rounded transition-colors"
            :class="wireFilter === f.key ? 'bg-primary-container text-ink-white' : 'bg-surface-slate text-steel-muted hover:text-ink-white border border-hairline'"
            @click="wireFilter = f.key"
          >{{ f.label }}</button>
        </div>
      </div>
      <div v-if="!filteredNews.length" class="py-6 text-center text-steel-muted font-mono-data text-[12px]">{{ wireFilter === 'all' ? '暂无快讯' : '该分类暂无快讯' }}</div>
      <div class="divide-y divide-hairline">
        <div
          v-for="n in filteredNews"
          :key="n.id"
          class="py-3 flex flex-col md:flex-row md:items-center justify-between gap-2 hover:bg-surface-slate/40 px-2 rounded transition-colors cursor-pointer"
          @click="router.push(`/news/${n.id}`)"
        >
          <div class="flex items-start md:items-center gap-3">
            <span class="font-mono-data text-xs text-steel-muted shrink-0 pt-0.5 md:pt-0">{{ fmtTime(ts(n.publish_at)) }}</span>
            <span class="px-2 py-0.5 text-[10px] font-mono-data rounded bg-primary-container/20 text-primary-fixed-dim border border-primary-container/40 shrink-0">{{ n.source || '快讯' }}</span>
            <p class="text-ink-white text-body-md font-body-md">{{ n.title }}</p>
          </div>
          <div class="flex items-center gap-3 ml-auto md:ml-0 shrink-0 font-mono-data text-xs text-steel-muted">
            <span class="text-[11px] text-steel-muted/80">{{ fmtAgo(ts(n.publish_at)) }}</span>
            <button
              class="px-2 py-0.5 bg-surface-slate hover:bg-card-navy-high text-primary-fixed-dim border border-hairline rounded text-[11px] transition-colors flex items-center gap-0.5"
              @click.stop="router.push(`/news/${n.id}`)"
            >
              <span>深度分析</span>
              <span class="material-symbols-outlined text-[13px]">north_east</span>
            </button>
          </div>
        </div>
      </div>
      <div class="pt-2 border-t border-hairline flex items-center justify-between text-[11px] font-mono-data text-steel-muted">
        <div class="flex items-center gap-2">
          <span class="w-1.5 h-1.5 rounded-full bg-bull-green"></span>
          <span>POLLING FEED: 30S REFRESH</span>
        </div>
        <button class="hover:text-primary-fixed-dim transition-colors flex items-center gap-0.5 text-ink-white" @click="router.push('/news')">
          <span>全部资讯</span>
          <span class="material-symbols-outlined text-[14px]">chevron_right</span>
        </button>
      </div>
    </section>
  </div>
</template>
