<script setup>
import { onMounted, onBeforeUnmount, ref, computed } from 'vue'
import EChart from '../components/EChart.vue'
import { overviewApi, marketApi } from '../api'
import { fmtUsd, fmtPct, fmtBig } from '../utils/format'

const ls = ref({})
const oi = ref({})
const liquidity = ref({})
const sentiment = ref(null)
const indicators = ref([])
const allRates = ref([]) // 资金费率 [{symbol, stablecoin_margin_list:[{exchange, funding_rate}]}]
const nextFundingTs = ref(null)
const countdown = ref('--:--:--')
const loading = ref(true)
let timer = null
let tickTimer = null

// ---------- 多空比 ----------
const longPct = computed(() => (ls.value.long_pct != null ? Number(ls.value.long_pct) : null))
const shortPct = computed(() => (ls.value.short_pct != null ? Number(ls.value.short_pct) : null))
const lsRatioText = computed(() => {
  if (longPct.value == null || shortPct.value == null) return '-- : 1'
  return (longPct.value / Math.max(shortPct.value, 0.01)).toFixed(2) + ' : 1'
})
const lsBias = computed(() => {
  if (longPct.value == null || shortPct.value == null) return '--'
  return longPct.value >= shortPct.value ? '全网资金偏好偏多' : '全网资金偏好偏空'
})

// ---------- 恐慌贪婪 ----------
const sentimentLabel = computed(() => {
  const v = sentiment.value
  if (v === null || v === undefined) return '--'
  if (v >= 75) return '极度贪婪 (EXT GREED)'
  if (v >= 50) return '贪婪 (GREED)'
  if (v >= 25) return '恐慌 (FEAR)'
  return '极度恐慌 (EXT FEAR)'
})
const sentimentChipCls = computed(() => {
  const v = sentiment.value
  if (v === null || v === undefined) return 'bg-surface-slate text-steel-muted border-hairline'
  if (v >= 50) return 'bg-amber-warn/15 text-amber-warn border-amber-warn/30'
  if (v >= 25) return 'bg-amber-warn/15 text-amber-warn border-amber-warn/30'
  return 'bg-bear-red/20 text-bear-red border-bear-red/30'
})
// 指针角度: 值 50 指向正上方 (rotate 0), 每点 1.8deg
const needleAngle = computed(() => (((sentiment.value ?? 50) - 50) * 1.8).toFixed(1))

// ---------- OI ----------
const oiText = computed(() => (oi.value.oi_usd != null ? fmtUsd(oi.value.oi_usd) : '--'))

// ---------- 稳定币 ----------
const stableTotal = computed(() => liquidity.value.stable_total_usd ?? null)
const stableChg = computed(() => liquidity.value.stable_change_1d_pct ?? null)
// 24H 净变动估算额 = 总量 * 变化%
const stableDelta = computed(() => {
  if (stableTotal.value == null || stableChg.value == null) return null
  return (stableTotal.value * stableChg.value) / 100
})
function stableOf(sym) {
  return (liquidity.value.top_stables || []).find((s) => s.name === sym) || null
}
function stableDeltaOf(sym) {
  const s = stableOf(sym)
  if (!s || s.circulating_usd == null || s.change_1d_pct == null) return null
  return (s.circulating_usd * s.change_1d_pct) / 100
}

// ---------- 顶部过滤 pills ----------
const PERIODS = ['15M', '1H', '4H', '1D', '7D', '30D']
// sparkline 为近 30 期日级序列, 周期 pill 截取尾部窗口 (数据不支持更细粒度时按窗口近似)
const PERIOD_POINTS = { '15M': 4, '1H': 8, '4H': 12, '1D': 18, '7D': 24, '30D': 30 }
const period = ref('4H')
const periodPoints = computed(() => PERIOD_POINTS[period.value] || 30)
const slicedSeries = (s) => (Array.isArray(s) ? s.slice(-periodPoints.value) : [])

const ECO_GROUPS = {
  全部主流: ['BTC', 'ETH', 'SOL'],
  BTC系: ['BTC', 'BCH', 'LTC', 'BSV'],
  ETH生态: ['ETH', 'ARB', 'OP', 'LINK', 'UNI'],
  Solana系: ['SOL'],
  DeFi衍生品: ['UNI', 'AAVE', 'DYDX', 'CRV', 'LINK'],
}
const ECO_KEYS = Object.keys(ECO_GROUPS)
const ECO_LABEL = { 全部主流: '全部主流', BTC系: 'BTC 系', ETH生态: 'ETH 生态', Solana系: 'Solana 系', DeFi衍生品: 'DeFi 衍生品' }
const eco = ref('全部主流')

// ---------- 资金费率热力矩阵 ----------
const HEAT_EXCH = ['BINANCE', 'OKX', 'BYBIT']
const heatRows = computed(() =>
  (ECO_GROUPS[eco.value] || ECO_GROUPS['全部主流']).map((coin) => {
    const hit = allRates.value.find((d) => d.symbol === coin)
    const map = {}
    for (const e of hit?.stablecoin_margin_list || []) {
      const v = Number(e.funding_rate)
      if (!isNaN(v)) map[String(e.exchange).toUpperCase()] = v
    }
    return { coin, cells: HEAT_EXCH.map((x) => (map[x] ?? null)) }
  })
)
// 费率(%) -> 格子底色
function heatBg(v) {
  if (v === null) return 'transparent'
  const a = Math.min(Math.abs(v) / 0.05, 1)
  return v >= 0 ? `rgba(0, 227, 136, ${0.08 + a * 0.4})` : `rgba(255, 95, 109, ${0.08 + a * 0.4})`
}
function rateText(v) {
  return v === null ? '--' : (v >= 0 ? '+' : '') + v.toFixed(4) + '%'
}
// 8h 结算一次 -> 年化 = rate * 3 * 365
function annualText(v) {
  return v === null ? '--' : '年化 ' + (v * 3 * 365).toFixed(1) + '%'
}
const avgAnnual = computed(() => {
  const vals = heatRows.value.flatMap((r) => r.cells).filter((v) => v !== null)
  if (!vals.length) return null
  return (vals.reduce((s, v) => s + v, 0) / vals.length) * 3 * 365
})

// ---------- 结算倒计时 ----------
function tick() {
  if (!nextFundingTs.value) {
    countdown.value = '--:--:--'
    return
  }
  let d = Math.max(0, Number(nextFundingTs.value) - Date.now())
  const p = (x) => String(x).padStart(2, '0')
  countdown.value = `${p(Math.floor(d / 3600000))}:${p(Math.floor((d % 3600000) / 60000))}:${p(Math.floor((d % 60000) / 1000))}`
}

// ---------- 指数卡 sparkline ----------
function sparkOption(series, color = '#2E5CFF') {
  return {
    grid: { left: 0, right: 0, top: 4, bottom: 0 },
    xAxis: { type: 'category', show: false, data: series.map((_, i) => i), boundaryGap: false },
    yAxis: { type: 'value', show: false, scale: true },
    series: [{
      type: 'line',
      data: series,
      showSymbol: false,
      smooth: true,
      lineStyle: { color, width: 1.5 },
      areaStyle: {
        color: { type: 'linear', x: 0, y: 0, x2: 0, y2: 1, colorStops: [{ offset: 0, color: color + '33' }, { offset: 1, color: 'transparent' }] },
      },
    }],
  }
}

async function load() {
  try {
    const [a, b, c, d, s, fr, okxFr] = await Promise.allSettled([
      overviewApi.longShortRatio('BTC'),
      overviewApi.openInterest(),
      overviewApi.liquidity(),
      overviewApi.indicators(),
      overviewApi.sentiment(),
      overviewApi.fundingExchangeRates('BTC'), // 上游忽略 symbol, 返回全币种
      marketApi.fundingRate('BTC-USDT-SWAP'),
    ])
    if (a.status === 'fulfilled') ls.value = a.value || {}
    if (b.status === 'fulfilled') oi.value = b.value || {}
    if (c.status === 'fulfilled') liquidity.value = c.value || {}
    if (d.status === 'fulfilled') indicators.value = d.value?.indicators || []
    if (s.status === 'fulfilled') sentiment.value = s.value?.fear_greed ?? null
    if (fr.status === 'fulfilled') allRates.value = fr.value?.data || []
    if (okxFr.status === 'fulfilled') {
      const t = Number(okxFr.value?.data?.[0]?.nextFundingTime)
      nextFundingTs.value = isNaN(t) ? null : t
    }
  } finally {
    loading.value = false
  }
}

onMounted(() => {
  load()
  timer = setInterval(load, 60000)
  tick()
  tickTimer = setInterval(tick, 1000)
})
onBeforeUnmount(() => {
  clearInterval(timer)
  clearInterval(tickTimer)
})
</script>

<template>
  <div v-if="loading" class="text-steel-muted font-mono-data text-body-md py-space-xl">数据加载中…</div>
  <div v-else class="flex flex-col gap-space-lg">
    <!-- 控制 / 过滤工具栏 -->
    <section class="flex flex-wrap items-center justify-between gap-y-3 border-b border-hairline pb-space-md">
      <div class="flex flex-wrap items-center gap-3">
        <div class="flex items-center bg-surface-slate border border-hairline rounded p-0.5 font-mono-data text-[11px]">
          <button
            v-for="p in PERIODS"
            :key="p"
            class="px-2.5 py-1 transition-colors"
            :class="period === p ? 'bg-primary-container text-ink-white font-semibold rounded-sm' : 'text-steel-muted hover:text-ink-white'"
            @click="period = p"
          >{{ p }}</button>
        </div>
        <div class="flex items-center gap-1 text-[12px] font-body-md">
          <button
            v-for="k in ECO_KEYS"
            :key="k"
            class="px-2.5 py-1 rounded border border-hairline transition-colors"
            :class="eco === k ? 'bg-card-navy text-ink-white font-medium border-primary-container/50' : 'bg-surface-slate text-steel-muted hover:text-ink-white hover:bg-card-navy'"
            @click="eco = k"
          >{{ ECO_LABEL[k] }}</button>
        </div>
      </div>
      <div class="flex items-center gap-3 text-steel-muted font-mono-data text-[11px]">
        <div class="flex items-center gap-1.5">
          <span class="w-1.5 h-1.5 rounded-full bg-bull-green"></span>
          <span>轮询: <span class="text-ink-white">60s 刷新</span></span>
        </div>
        <span class="text-hairline">|</span>
        <div>聚合源: <span class="text-ink-white">OKX / Binance / DefiLlama</span></div>
      </div>
    </section>

    <!-- 核心 3 列量化数据 BENTO 网格 -->
    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-gutter">
      <!-- CARD 1: 多空持仓比 -->
      <article class="bg-card-navy border border-hairline rounded-xl p-space-md flex flex-col justify-between hover:border-primary-container/60 transition-colors">
        <div>
          <div class="flex items-start justify-between border-b border-hairline pb-space-sm mb-space-sm">
            <div>
              <div class="font-label-sm text-[10px] uppercase text-primary-fixed-dim tracking-wider font-semibold">DERIVATIVES INTEL</div>
              <h2 class="font-headline-sm text-headline-sm text-ink-white">全网多空持仓比 (BTC 永续)</h2>
            </div>
            <span class="font-mono-data text-[11px] text-steel-muted/80">更新: 60s</span>
          </div>
          <div class="flex items-baseline justify-between mt-2">
            <div>
              <div class="font-mono-data text-2xl font-bold tracking-tight text-ink-white">{{ lsRatioText }}</div>
              <div class="text-[11px] font-body-md text-steel-muted mt-0.5">{{ lsBias }}</div>
            </div>
            <div class="text-right font-mono-data">
              <div class="text-bull-green font-bold text-sm">多 {{ longPct != null ? longPct.toFixed(1) + '%' : '--' }}</div>
              <div class="text-bear-red font-bold text-sm">空 {{ shortPct != null ? shortPct.toFixed(1) + '%' : '--' }}</div>
            </div>
          </div>
          <div class="mt-4">
            <div class="w-full h-3 bg-surface-slate rounded-sm flex overflow-hidden border border-hairline p-[1px]">
              <div class="h-full bg-bull-green rounded-l-[1px]" :style="{ width: (longPct ?? 50) + '%' }"></div>
              <div class="w-0.5 h-full bg-canvas-obsidian z-10"></div>
              <div class="h-full bg-bear-red rounded-r-[1px]" :style="{ width: (shortPct ?? 50) + '%' }"></div>
            </div>
            <div class="flex justify-between items-center text-[10px] font-mono-data text-steel-muted mt-1">
              <span>BULLISH BIAS ({{ longPct != null ? longPct.toFixed(1) + '%' : '--' }})</span>
              <span>BEARISH BIAS ({{ shortPct != null ? shortPct.toFixed(1) + '%' : '--' }})</span>
            </div>
          </div>
        </div>
        <div class="mt-5 pt-3 border-t border-hairline space-y-2 font-mono-data text-[11px]">
          <div class="flex justify-between text-steel-muted text-[10px] uppercase font-label-sm">
            <span>EXCHANGE</span>
            <span>RATIO</span>
            <span>PROPORTION</span>
          </div>
          <div class="flex items-center justify-between">
            <span class="text-ink-white font-medium">Binance 全局账户</span>
            <span class="font-semibold" :class="longPct != null && longPct >= shortPct ? 'text-bull-green' : 'text-bear-red'">{{ lsRatioText.replace(' : 1', '') }}</span>
            <div class="w-24 h-1.5 bg-surface-slate rounded-sm overflow-hidden flex">
              <div class="bg-bull-green h-full" :style="{ width: (longPct ?? 50) + '%' }"></div>
              <div class="bg-bear-red h-full" :style="{ width: (shortPct ?? 50) + '%' }"></div>
            </div>
          </div>
          <div class="text-[10px] text-steel-muted/70">分交易所明细需 CoinGlass 数据源</div>
        </div>
      </article>

      <!-- CARD 2: 恐慌与贪婪 -->
      <article class="bg-card-navy border border-hairline rounded-xl p-space-md flex flex-col justify-between hover:border-primary-container/60 transition-colors">
        <div>
          <div class="flex items-start justify-between border-b border-hairline pb-space-sm mb-space-sm">
            <div>
              <div class="font-label-sm text-[10px] uppercase text-primary-fixed-dim tracking-wider font-semibold">SENTIMENT GAUGE</div>
              <h2 class="font-headline-sm text-headline-sm text-ink-white">全市场恐慌与贪婪指数</h2>
            </div>
            <span class="font-mono-data text-[11px] text-steel-muted/80">更新: 5m</span>
          </div>
          <div class="flex items-baseline justify-between mt-2">
            <div class="flex items-center gap-3">
              <div class="font-mono-data text-3xl font-bold tracking-tight text-ink-white">{{ sentiment ?? '--' }}</div>
              <span v-if="sentiment != null" class="px-2 py-0.5 rounded text-[11px] font-mono-data font-bold border" :class="sentimentChipCls">{{ sentimentLabel }}</span>
            </div>
            <div class="text-right text-[11px] font-mono-data text-steel-muted">
              <div>昨日: <span class="text-ink-white font-semibold">--</span></div>
              <div>上周: <span class="text-ink-white font-semibold">--</span></div>
            </div>
          </div>
          <div class="mt-3 relative flex flex-col items-center justify-center">
            <svg class="w-56 h-28 overflow-visible" viewBox="0 0 200 110">
              <defs>
                <linearGradient id="gaugeGrad" x1="0%" x2="100%" y1="0%" y2="0%">
                  <stop offset="0%" stop-color="#FF5F6D"></stop>
                  <stop offset="35%" stop-color="#F7B733"></stop>
                  <stop offset="70%" stop-color="#00E388"></stop>
                  <stop offset="100%" stop-color="#2e5cff"></stop>
                </linearGradient>
              </defs>
              <path d="M 25 95 A 75 75 0 0 1 175 95" fill="none" stroke="#1A2742" stroke-linecap="round" stroke-width="12"></path>
              <path d="M 25 95 A 75 75 0 0 1 175 95" fill="none" opacity="0.85" stroke="url(#gaugeGrad)" stroke-dasharray="235.6" stroke-dashoffset="0" stroke-linecap="round" stroke-width="10"></path>
              <line stroke="#34415E" stroke-width="1.5" x1="25" x2="15" y1="95" y2="95"></line>
              <line stroke="#34415E" stroke-width="1.5" x1="47" x2="40" y1="42" y2="35"></line>
              <line stroke="#34415E" stroke-width="1.5" x1="100" x2="100" y1="20" y2="10"></line>
              <line stroke="#34415E" stroke-width="1.5" x1="153" x2="160" y1="42" y2="35"></line>
              <line stroke="#34415E" stroke-width="1.5" x1="175" x2="185" y1="95" y2="95"></line>
              <g :transform="`rotate(${needleAngle}, 100, 95)`">
                <line stroke="#F0F0FF" stroke-linecap="round" stroke-width="2" x1="100" x2="100" y1="95" y2="30"></line>
                <circle cx="100" cy="95" fill="#2E5CFF" r="5" stroke="#F0F0FF" stroke-width="1.5"></circle>
              </g>
            </svg>
            <div class="w-full flex justify-between text-[10px] font-mono-data text-steel-muted px-4 -mt-2">
              <span>0 (极恐)</span>
              <span class="text-amber-warn">50 (中性)</span>
              <span class="text-bull-green">100 (极贪)</span>
            </div>
          </div>
        </div>
        <div class="mt-4 pt-3 border-t border-hairline flex items-center justify-between text-[11px] font-mono-data text-steel-muted">
          <div>数据源: <span class="text-ink-white font-medium">alternative.me</span></div>
          <div class="text-bull-green font-medium">每日更新</div>
        </div>
      </article>

      <!-- CARD 3: 未平仓持仓量 OI -->
      <article class="bg-card-navy border border-hairline rounded-xl p-space-md flex flex-col justify-between hover:border-primary-container/60 transition-colors">
        <div>
          <div class="flex items-start justify-between border-b border-hairline pb-space-sm mb-space-sm">
            <div>
              <div class="font-label-sm text-[10px] uppercase text-primary-fixed-dim tracking-wider font-semibold">GLOBAL AGGREGATION</div>
              <h2 class="font-headline-sm text-headline-sm text-ink-white">全网未平仓持仓量 (OI)</h2>
            </div>
            <span class="font-mono-data text-[11px] text-bull-green flex items-center gap-1">
              <span class="w-1.5 h-1.5 rounded-full bg-bull-green"></span>
              实时
            </span>
          </div>
          <div class="flex items-baseline justify-between mt-2">
            <div>
              <div class="font-mono-data text-2xl font-bold tracking-tight text-ink-white">{{ oiText }}</div>
              <div class="text-[11px] font-mono-data text-steel-muted mt-0.5">BTC+ETH 永续名义额合计</div>
            </div>
            <div class="text-right font-mono-data text-[11px] text-steel-muted">
              <div>最高: <span class="text-ink-white">--</span></div>
              <div>最低: <span class="text-ink-white">--</span></div>
            </div>
          </div>
          <div class="mt-4 h-24 rounded border border-hairline bg-surface-slate/60 flex items-center justify-center text-[11px] font-mono-data text-steel-muted">
            24H 历史序列暂不可用 (需 CoinGlass 数据源)
          </div>
        </div>
        <div class="mt-4 pt-3 border-t border-hairline flex items-center justify-between text-[11px] font-mono-data text-steel-muted">
          <span>数据源: <strong class="text-ink-white font-normal">OKX 永续 oiUsd</strong></span>
          <span class="text-bull-green">缓存 5m</span>
        </div>
      </article>

      <!-- CARD 4: 稳定币流向 -->
      <article class="bg-card-navy border border-hairline rounded-xl p-space-md flex flex-col justify-between hover:border-primary-container/60 transition-colors">
        <div>
          <div class="flex items-start justify-between border-b border-hairline pb-space-sm mb-space-sm">
            <div>
              <div class="font-label-sm text-[10px] uppercase text-primary-fixed-dim tracking-wider font-semibold">LIQUIDITY DEPTH</div>
              <h2 class="font-headline-sm text-headline-sm text-ink-white">稳定币流通量 24H 净变动</h2>
            </div>
            <span class="font-mono-data text-[11px] text-steel-muted/80">更新: 5m</span>
          </div>
          <div class="flex items-baseline justify-between mt-2">
            <div>
              <div class="font-mono-data text-2xl font-bold tracking-tight" :class="stableDelta == null ? 'text-ink-white' : stableDelta >= 0 ? 'text-bull-green' : 'text-bear-red'">
                {{ stableDelta == null ? '--' : (stableDelta >= 0 ? '+' : '') + fmtUsd(stableDelta) }}
              </div>
              <div class="text-[11px] font-body-md text-steel-muted mt-0.5">
                总流通 {{ fmtUsd(stableTotal) }} · 24H {{ fmtPct(stableChg) }}
              </div>
            </div>
            <div class="text-right font-mono-data text-[11px]">
              <span
                v-if="stableChg != null"
                class="px-1.5 py-0.5 rounded font-semibold border"
                :class="stableChg >= 0 ? 'bg-bull-green/15 text-bull-green border-bull-green/30' : 'bg-bear-red/15 text-bear-red border-bear-red/30'"
              >{{ stableChg >= 0 ? '净增发驱动' : '净赎回收缩' }}</span>
            </div>
          </div>
          <div class="mt-4 h-20 rounded border border-hairline bg-surface-slate/60 flex items-center justify-center text-[11px] font-mono-data text-steel-muted">
            7 日净流序列暂不可用 (DefiLlama 仅提供总量)
          </div>
        </div>
        <div class="mt-4 pt-3 border-t border-hairline space-y-2 font-mono-data text-[11px]">
          <div class="flex items-center justify-between">
            <span class="text-steel-muted flex items-center gap-1.5">
              <span class="w-2 h-2 rounded-full bg-bull-green"></span>
              <span>USDT (Tether 流通 {{ fmtUsd(stableOf('USDT')?.circulating_usd) }})</span>
            </span>
            <span class="font-semibold" :class="(stableDeltaOf('USDT') ?? 0) >= 0 ? 'text-bull-green' : 'text-bear-red'">
              {{ stableDeltaOf('USDT') == null ? '--' : (stableDeltaOf('USDT') >= 0 ? '+' : '') + fmtUsd(stableDeltaOf('USDT')) }}
            </span>
          </div>
          <div class="flex items-center justify-between">
            <span class="text-steel-muted flex items-center gap-1.5">
              <span class="w-2 h-2 rounded-full bg-primary-container"></span>
              <span>USDC (Circle 流通 {{ fmtUsd(stableOf('USDC')?.circulating_usd) }})</span>
            </span>
            <span class="font-semibold" :class="(stableDeltaOf('USDC') ?? 0) >= 0 ? 'text-bull-green' : 'text-bear-red'">
              {{ stableDeltaOf('USDC') == null ? '--' : (stableDeltaOf('USDC') >= 0 ? '+' : '') + fmtUsd(stableDeltaOf('USDC')) }}
            </span>
          </div>
        </div>
      </article>

      <!-- CARD 5: 资金费率热力矩阵 -->
      <article class="bg-card-navy border border-hairline rounded-xl p-space-md flex flex-col justify-between hover:border-primary-container/60 transition-colors">
        <div>
          <div class="flex items-start justify-between border-b border-hairline pb-space-sm mb-space-sm">
            <div>
              <div class="font-label-sm text-[10px] uppercase text-primary-fixed-dim tracking-wider font-semibold">CROSS-EXCHANGE</div>
              <h2 class="font-headline-sm text-headline-sm text-ink-white">主流资产资金费率热力矩阵</h2>
            </div>
            <div class="text-right">
              <div class="font-mono-data text-[10px] text-steel-muted">结算倒计时</div>
              <div class="font-mono-data text-[11px] text-amber-warn font-semibold">{{ countdown }}</div>
            </div>
          </div>
          <div class="mt-2 font-mono-data">
            <div class="grid grid-cols-4 gap-1 text-[10px] text-steel-muted uppercase text-center pb-1">
              <div class="text-left font-label-sm">ASSET</div>
              <div class="font-label-sm">BINANCE</div>
              <div class="font-label-sm">OKX</div>
              <div class="font-label-sm">BYBIT</div>
            </div>
            <div v-for="row in heatRows" :key="row.coin" class="grid grid-cols-4 gap-1 py-1 items-center">
              <div class="text-left font-semibold text-ink-white text-[12px]">{{ row.coin }}</div>
              <div v-for="(v, i) in row.cells" :key="i" class="p-1.5 rounded border border-hairline text-center" :style="{ backgroundColor: heatBg(v) }">
                <div class="text-[11px] font-bold" :class="v == null ? 'text-steel-muted' : v >= 0 ? 'text-bull-green' : 'text-bear-red'">{{ rateText(v) }}</div>
                <div class="text-[9px] text-steel-muted">{{ annualText(v) }}</div>
              </div>
            </div>
          </div>
        </div>
        <div class="mt-4 pt-3 border-t border-hairline flex items-center justify-between text-[11px] font-mono-data text-steel-muted">
          <span>样本平均年化: <strong class="text-ink-white font-normal">{{ avgAnnual != null ? avgAnnual.toFixed(1) + '%' : '--' }}</strong></span>
          <span class="text-amber-warn font-medium">8H 结算周期</span>
        </div>
      </article>

      <!-- CARD 6+: 多维量化指数卡 -->
      <article
        v-for="ind in indicators"
        :key="ind.key"
        class="bg-card-navy border border-hairline rounded-xl p-space-md flex flex-col justify-between hover:border-primary-container/60 transition-colors"
      >
        <div>
          <div class="flex items-start justify-between border-b border-hairline pb-space-sm mb-space-sm">
            <div>
              <div class="font-label-sm text-[10px] uppercase text-primary-fixed-dim tracking-wider font-semibold">QUANT INDEX</div>
              <h2 class="font-headline-sm text-headline-sm text-ink-white">{{ ind.name }}</h2>
            </div>
            <span
              class="font-mono-data text-[11px] font-semibold"
              :class="Number(ind.change_1d) >= 0 ? 'text-bull-green' : 'text-bear-red'"
            >{{ fmtPct(ind.change_1d, 2) }}</span>
          </div>
          <div class="flex items-baseline justify-between mt-2">
            <div class="font-mono-data text-2xl font-bold tracking-tight text-ink-white">{{ Number(ind.value).toFixed(2) }}</div>
            <span class="font-mono-data text-[10px] text-steel-muted uppercase">{{ ind.key }}</span>
          </div>
          <div class="mt-4">
            <EChart
              v-if="ind.sparkline?.length > 1"
              :option="sparkOption(slicedSeries(ind.sparkline), Number(ind.change_1d) >= 0 ? '#00E388' : '#FF5F6D')"
              height="80px"
            />
            <div v-else class="h-20 rounded border border-hairline bg-surface-slate/60 flex items-center justify-center text-[11px] font-mono-data text-steel-muted">历史序列不足</div>
            <div class="flex justify-between text-[10px] font-mono-data text-steel-muted mt-1">
              <span>T-{{ periodPoints }} ({{ period }})</span>
              <span class="text-primary-fixed-dim font-semibold">当前 ({{ Number(ind.value).toFixed(2) }})</span>
            </div>
          </div>
        </div>
        <div class="mt-4 pt-3 border-t border-hairline flex items-center justify-between text-[11px] font-mono-data text-steel-muted">
          <span>1D 变化: <strong class="text-ink-white font-normal">{{ fmtPct(ind.change_1d, 2) }}</strong></span>
          <span>近 {{ periodPoints }} 期走势</span>
        </div>
      </article>
      <article v-if="!indicators.length" class="bg-card-navy border border-hairline rounded-xl p-space-md flex items-center justify-center text-steel-muted font-mono-data text-[12px] min-h-40">
        多维指数暂不可用 (数据源未配置 CoinGlass)
      </article>
    </div>

    <!-- 实时数据流终端横幅 -->
    <section class="bg-surface-slate border border-hairline rounded-lg p-space-sm flex flex-wrap items-center justify-between text-[11px] font-mono-data text-steel-muted">
      <div class="flex items-center gap-4">
        <span class="flex items-center gap-1.5 text-bull-green">
          <span class="w-2 h-2 rounded-full bg-bull-green"></span>
          <span>行情聚合源已连接</span>
        </span>
        <span class="text-hairline">|</span>
        <span>OKX / Binance / DefiLlama / alternative.me</span>
        <span class="text-hairline">|</span>
        <span>轮询周期: <strong class="text-ink-white font-normal">60s</strong></span>
      </div>
      <div class="flex items-center gap-3">
        <span>BTC 永续结算: <span class="text-ink-white">{{ countdown }}</span></span>
        <span class="px-1.5 py-0.5 rounded bg-primary-container/20 text-primary-fixed-dim border border-primary-container/40 text-[10px]">SYNCED</span>
      </div>
    </section>
  </div>
</template>
