<script setup>
import { onMounted, onBeforeUnmount, ref, computed } from 'vue'
import EChart from '../components/EChart.vue'
import { overviewApi } from '../api'
import { fmtUsd, fmtBig, fmtPct, fmtPrice, fmtTime, coinOf } from '../utils/format'

const events = ref([])
const coins = ref([])
const loading = ref(true)
const assetFilter = ref('all') // all | BTC | ETH | SOL | other
const gran = ref('24H')
let timer = null

const total24h = computed(() => coins.value.reduce((s, c) => s + Number(c.liquidation_usd_24h ?? c.liqUsd24h ?? 0), 0))
const longTotal = computed(() => coins.value.reduce((s, c) => s + Number(c.long_liquidation_usd_24h ?? c.longLiqUsd24h ?? 0), 0))
const shortTotal = computed(() => coins.value.reduce((s, c) => s + Number(c.short_liquidation_usd_24h ?? c.shortLiqUsd24h ?? 0), 0))

const longPct = computed(() => (total24h.value ? (longTotal.value / total24h.value) * 100 : null))
const shortPct = computed(() => (total24h.value ? (shortTotal.value / total24h.value) * 100 : null))
const ratio = computed(() => (longTotal.value && shortTotal.value ? (longTotal.value / shortTotal.value).toFixed(2) : null))

const maxEvent = computed(() =>
  events.value.reduce((m, e) => (Number(e.notional_usd || 0) > Number(m?.notional_usd || 0) ? e : m), null)
)

const isLong = (e) => e.side === 'long' || e.side === 'buy'
const longCount = computed(() => events.value.filter(isLong).length)
const shortCount = computed(() => events.value.length - longCount.value)

const filteredEvents = computed(() => {
  if (assetFilter.value === 'all') return events.value
  if (assetFilter.value === 'other')
    return events.value.filter((e) => !['BTC', 'ETH', 'SOL'].includes(coinOf(e.symbol)))
  return events.value.filter((e) => coinOf(e.symbol) === assetFilter.value)
})

// 爆仓分布柱状图 (按粒度分桶聚合实时事件)
const chartOption = computed(() => {
  const cfg = {
    '1H': { span: 3600e3, bucket: 5 * 60e3 },
    '4H': { span: 4 * 3600e3, bucket: 30 * 60e3 },
    '24H': { span: 24 * 3600e3, bucket: 3600e3 },
  }[gran.value]
  const newest = events.value.reduce((m, e) => Math.max(m, Number(e.ts) || 0), 0)
  // 上游缓存可能滞后: 若最新事件已超出窗口, 窗口锚定到最新事件, 保证分布可见
  const now = Date.now()
  const end = newest && now - newest > cfg.span ? newest : now
  const start = end - cfg.span
  const n = Math.ceil(cfg.span / cfg.bucket)
  const longs = Array(n).fill(0)
  const shorts = Array(n).fill(0)
  const labels = []
  const p = (x) => String(x).padStart(2, '0')
  for (let i = 0; i < n; i++) {
    const t = new Date(start + i * cfg.bucket)
    labels.push(`${p(t.getHours())}:${p(t.getMinutes())}`)
  }
  for (const e of events.value) {
    const t = Number(e.ts)
    if (!t || t < start) continue
    const i = Math.min(n - 1, Math.floor((t - start) / cfg.bucket))
    if (isLong(e)) longs[i] += Number(e.notional_usd || 0)
    else shorts[i] += Number(e.notional_usd || 0)
  }
  return {
    grid: { left: 8, right: 8, top: 12, bottom: 24 },
    tooltip: {
      trigger: 'axis',
      backgroundColor: '#121D34',
      borderColor: '#34415E',
      textStyle: { color: '#F0F0FF', fontSize: 11, fontFamily: 'JetBrains Mono' },
      valueFormatter: (v) => fmtUsd(v),
    },
    xAxis: {
      type: 'category',
      data: labels,
      axisLine: { lineStyle: { color: '#34415E' } },
      axisLabel: { color: '#9EA0B2', fontSize: 10, fontFamily: 'JetBrains Mono' },
    },
    yAxis: {
      type: 'value',
      splitLine: { lineStyle: { color: 'rgba(52,65,94,0.3)', type: 'dashed' } },
      axisLabel: { color: '#9EA0B2', fontSize: 10, fontFamily: 'JetBrains Mono', formatter: (v) => fmtBig(v, 1) },
    },
    series: [
      { name: '多单强平', type: 'bar', stack: 'liq', data: longs, itemStyle: { color: '#00E388' }, barMaxWidth: 18 },
      { name: '空单强平', type: 'bar', stack: 'liq', data: shorts, itemStyle: { color: '#FF5F6D' } },
    ],
  }
})

// 多空爆仓比例环图
const donutOption = computed(() => ({
  tooltip: { show: false },
  series: [
    {
      type: 'pie',
      radius: ['68%', '88%'],
      center: ['50%', '50%'],
      label: { show: false },
      data: [
        { value: longTotal.value, name: '多单', itemStyle: { color: '#00E388' } },
        { value: shortTotal.value, name: '空单', itemStyle: { color: '#FF5F6D' } },
      ],
    },
  ],
}))

const AVATAR = {
  BTC: 'bg-amber-warn/20 text-amber-warn',
  ETH: 'bg-primary-container/20 text-primary-fixed-dim',
  SOL: 'bg-bull-green/15 text-bull-green',
}
const avatarCls = (sym) => AVATAR[coinOf(sym)] || 'bg-card-navy-high text-steel-muted'
const avatarChar = (sym) => ({ BTC: '₿', ETH: 'Ξ', SOL: '◎' }[coinOf(sym)] || coinOf(sym).slice(0, 1))

async function load() {
  try {
    const [a, b] = await Promise.allSettled([overviewApi.liqRecent(50), overviewApi.liqCoinList()])
    if (a.status === 'fulfilled') events.value = a.value?.data || []
    if (b.status === 'fulfilled') coins.value = b.value?.coins || []
  } finally {
    loading.value = false
  }
}

onMounted(() => {
  load()
  timer = setInterval(load, 10000)
})
onBeforeUnmount(() => clearInterval(timer))
</script>

<template>
  <div v-if="loading" class="text-steel-muted font-mono-data text-mono-data py-10 text-center">数据加载中…</div>
  <div v-else class="flex flex-col gap-space-lg">
    <!-- SUB-HEADER / TERMINAL CONTEXT BAR -->
    <div class="flex items-center justify-between border-b border-hairline/60 pb-3">
      <div class="flex items-center gap-3">
        <span class="text-label-sm font-label-sm text-steel-muted uppercase tracking-wider">市场监控范围:</span>
        <div class="flex items-center gap-1.5 font-mono-data text-xs">
          <span class="px-2 py-0.5 rounded bg-surface-slate text-ink-white border border-hairline font-mono-data">全网合约 (USDT/COIN-M)</span>
          <span class="text-steel-muted">·</span>
          <span class="text-steel-muted">币安 · OKX · Bybit · Coinbase · Deribit</span>
        </div>
      </div>
      <div class="flex items-center gap-4 text-label-sm font-label-sm">
        <span class="text-steel-muted">统计周期: <span class="text-ink-white font-mono-data">过去 24 小时</span></span>
        <span class="inline-flex items-center gap-1 px-2 py-0.5 bg-bull-green/10 text-bull-green border border-bull-green/20 rounded">
          <span class="w-1.5 h-1.5 rounded-full bg-bull-green animate-pulse"></span> WEBSOCKET 活跃
        </span>
      </div>
    </div>

    <!-- ROW 1: 4 CORE METRIC CARDS -->
    <section class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
      <!-- Metric 1: 24H 爆仓总额 -->
      <div class="bg-card-navy border border-hairline rounded-xl p-4 flex flex-col justify-between hover:border-hairline/90 transition-colors">
        <div class="flex items-center justify-between">
          <span class="text-label-sm font-label-sm text-steel-muted uppercase tracking-wider">24H 爆仓总额 (Total)</span>
          <span class="material-symbols-outlined text-steel-muted text-[16px]">show_chart</span>
        </div>
        <div class="my-3">
          <div class="text-headline-lg font-mono-data font-bold tracking-tight text-ink-white">{{ fmtUsd(total24h || null) }}</div>
        </div>
        <div class="flex items-center justify-between pt-2 border-t border-hairline/50 font-mono-data text-label-sm">
          <span class="text-steel-muted">监控币种</span>
          <span class="text-ink-white font-medium">{{ coins.length }} 个</span>
        </div>
      </div>
      <!-- Metric 2: 多单爆仓 -->
      <div class="bg-card-navy border border-hairline rounded-xl p-4 flex flex-col justify-between hover:border-hairline/90 transition-colors">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-1.5">
            <span class="w-2 h-2 rounded-full bg-bull-green"></span>
            <span class="text-label-sm font-label-sm text-steel-muted uppercase tracking-wider">多单爆仓 (Long)</span>
          </div>
          <span class="px-1.5 py-0.5 rounded text-[10px] font-mono-data bg-bull-green/10 text-bull-green border border-bull-green/20">
            {{ longPct != null ? longPct.toFixed(2) + '%' : '--' }}
          </span>
        </div>
        <div class="my-3">
          <div class="text-headline-lg font-mono-data font-bold tracking-tight text-bull-green">{{ fmtUsd(longTotal || null) }}</div>
        </div>
        <div class="flex items-center justify-between pt-2 border-t border-hairline/50 font-mono-data text-label-sm">
          <span class="text-steel-muted">近期强平笔数</span>
          <span class="text-ink-white font-medium">{{ longCount }} 笔 (多头去杠杆)</span>
        </div>
      </div>
      <!-- Metric 3: 空单爆仓 -->
      <div class="bg-card-navy border border-hairline rounded-xl p-4 flex flex-col justify-between hover:border-hairline/90 transition-colors">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-1.5">
            <span class="w-2 h-2 rounded-full bg-bear-red"></span>
            <span class="text-label-sm font-label-sm text-steel-muted uppercase tracking-wider">空单爆仓 (Short)</span>
          </div>
          <span class="px-1.5 py-0.5 rounded text-[10px] font-mono-data bg-bear-red/10 text-bear-red border border-bear-red/20">
            {{ shortPct != null ? shortPct.toFixed(2) + '%' : '--' }}
          </span>
        </div>
        <div class="my-3">
          <div class="text-headline-lg font-mono-data font-bold tracking-tight text-bear-red">{{ fmtUsd(shortTotal || null) }}</div>
        </div>
        <div class="flex items-center justify-between pt-2 border-t border-hairline/50 font-mono-data text-label-sm">
          <span class="text-steel-muted">近期强平笔数</span>
          <span class="text-ink-white font-medium">{{ shortCount }} 笔 (空头逼仓)</span>
        </div>
      </div>
      <!-- Metric 4: 最大单笔爆仓 -->
      <div class="bg-card-navy border border-hairline rounded-xl p-4 flex flex-col justify-between hover:border-hairline/90 transition-colors">
        <div class="flex items-center justify-between">
          <span class="text-label-sm font-label-sm text-steel-muted uppercase tracking-wider">最大单笔爆仓 (Largest)</span>
          <span class="material-symbols-outlined text-amber-warn text-[16px]">warning</span>
        </div>
        <div class="my-3">
          <div class="text-headline-lg font-mono-data font-bold tracking-tight text-ink-white">
            {{ fmtUsd(maxEvent?.notional_usd || null) }}
          </div>
        </div>
        <div class="flex items-center justify-between pt-2 border-t border-hairline/50 font-mono-data text-label-sm">
          <span class="text-steel-muted truncate">{{ maxEvent ? `${maxEvent.symbol} · ${maxEvent.exchange || '--'}` : '--' }}</span>
          <span class="text-steel-muted">{{ maxEvent ? fmtTime(maxEvent.ts) : '--' }}</span>
        </div>
      </div>
    </section>

    <!-- ROW 2: CHARTS & ANALYTICS (GRID 8:4) -->
    <section class="grid grid-cols-1 lg:grid-cols-12 gap-4">
      <!-- LEFT: 爆仓分布堆叠柱状图 (8 COLS) -->
      <div class="lg:col-span-8 bg-card-navy border border-hairline rounded-xl p-5 flex flex-col justify-between">
        <div class="flex flex-wrap items-center justify-between gap-3 pb-4 border-b border-hairline/60">
          <div class="flex items-center gap-3">
            <span class="text-headline-sm font-headline-sm text-ink-white font-semibold">爆仓分布 (LIQUIDATION TIMELINE)</span>
            <span class="text-label-sm font-label-sm text-steel-muted">全时段双向对冲</span>
          </div>
          <div class="flex items-center gap-4">
            <div class="flex items-center gap-3 text-label-sm font-mono-data">
              <span class="flex items-center gap-1.5 text-bull-green">
                <span class="w-2.5 h-2.5 bg-bull-green rounded-sm"></span> 多头强平 {{ fmtUsd(longTotal || null) }}
              </span>
              <span class="flex items-center gap-1.5 text-bear-red">
                <span class="w-2.5 h-2.5 bg-bear-red rounded-sm"></span> 空头强平 {{ fmtUsd(shortTotal || null) }}
              </span>
            </div>
            <div class="inline-flex rounded border border-hairline bg-canvas-obsidian p-0.5 text-label-sm font-mono-data">
              <button
                v-for="g in ['1H', '4H', '24H']"
                :key="g"
                class="px-2 py-0.5 rounded transition-colors"
                :class="gran === g ? 'bg-primary-container text-ink-white font-semibold' : 'text-steel-muted hover:text-ink-white'"
                @click="gran = g"
              >{{ g }}</button>
            </div>
          </div>
        </div>
        <div class="mt-4 pt-2">
          <EChart :option="chartOption" height="220px" />
        </div>
      </div>

      <!-- RIGHT: 多空爆仓比例 环形仪表 (4 COLS) -->
      <div class="lg:col-span-4 bg-card-navy border border-hairline rounded-xl p-5 flex flex-col justify-between">
        <div class="flex items-center justify-between pb-3 border-b border-hairline/60">
          <span class="text-headline-sm font-headline-sm text-ink-white font-semibold">多空爆仓比例</span>
          <span class="text-label-sm font-mono-data text-steel-muted uppercase">RATIO METER</span>
        </div>
        <div class="flex flex-col items-center justify-center my-2 relative">
          <EChart :option="donutOption" height="176px" />
          <div class="absolute inset-0 flex flex-col items-center justify-center text-center pointer-events-none">
            <span class="text-label-sm font-mono-data text-steel-muted text-[10px] tracking-wider uppercase">多空对比</span>
            <span class="text-headline-md font-mono-data font-bold text-ink-white my-0.5">{{ ratio ? ratio + ' : 1' : '--' }}</span>
            <span class="text-label-sm font-mono-data text-bull-green text-[10px] bg-bull-green/10 px-1.5 py-0.5 rounded">
              {{ longPct != null && longPct >= 50 ? '多头承压略高' : '空头承压略高' }}
            </span>
          </div>
        </div>
        <div class="space-y-2 pt-2 border-t border-hairline/60 font-mono-data">
          <div class="flex items-center justify-between text-mono-data">
            <div class="flex items-center gap-2">
              <span class="w-2.5 h-2.5 rounded-full bg-bull-green"></span>
              <span class="text-steel-muted text-xs">多单强平</span>
            </div>
            <div class="text-right">
              <span class="text-ink-white font-semibold">{{ longPct != null ? longPct.toFixed(1) + '%' : '--' }}</span>
              <span class="text-steel-muted text-xs ml-1.5">({{ longCount }} 笔)</span>
            </div>
          </div>
          <div class="flex items-center justify-between text-mono-data">
            <div class="flex items-center gap-2">
              <span class="w-2.5 h-2.5 rounded-full bg-bear-red"></span>
              <span class="text-steel-muted text-xs">空单强平</span>
            </div>
            <div class="text-right">
              <span class="text-ink-white font-semibold">{{ shortPct != null ? shortPct.toFixed(1) + '%' : '--' }}</span>
              <span class="text-steel-muted text-xs ml-1.5">({{ shortCount }} 笔)</span>
            </div>
          </div>
          <div class="bg-surface-slate rounded p-2 text-[11px] text-steel-muted border border-hairline/60 flex items-center justify-between mt-2">
            <span>市场爆仓偏向:</span>
            <span class="text-ink-white font-medium">{{ longPct != null && longPct >= 50 ? '多头去杠杆 · 注意回踩风险' : '空头逼仓 · 注意反弹风险' }}</span>
          </div>
        </div>
      </div>
    </section>

    <!-- ROW 3: LIVE LIQUIDATION FEED -->
    <section class="bg-card-navy border border-hairline rounded-xl overflow-hidden">
      <!-- Table Toolbar -->
      <div class="px-5 py-3.5 border-b border-hairline flex flex-wrap items-center justify-between gap-4 bg-surface-slate/40">
        <div class="flex items-center gap-4">
          <div class="flex items-center gap-2">
            <span class="material-symbols-outlined text-bull-green text-[18px]">stream</span>
            <span class="text-headline-sm font-headline-sm text-ink-white font-semibold">实时爆仓明细 (LIVE LIQUIDATION FEED)</span>
          </div>
          <div class="inline-flex rounded border border-hairline bg-canvas-obsidian p-0.5 text-label-sm font-mono-data ml-2">
            <button
              v-for="f in [
                { k: 'all', t: '全部' },
                { k: 'BTC', t: 'BTC' },
                { k: 'ETH', t: 'ETH' },
                { k: 'SOL', t: 'SOL' },
                { k: 'other', t: '其他' },
              ]"
              :key="f.k"
              class="px-2.5 py-1 rounded transition-colors"
              :class="assetFilter === f.k ? 'bg-card-navy-high text-ink-white font-semibold' : 'text-steel-muted hover:text-ink-white'"
              @click="assetFilter = f.k"
            >{{ f.t }}</button>
          </div>
        </div>
        <div class="flex items-center gap-4 text-label-sm font-mono-data">
          <div class="flex items-center gap-1.5 px-2 py-1 rounded bg-bull-green/10 text-bull-green border border-bull-green/30">
            <span class="w-1.5 h-1.5 rounded-full bg-bull-green animate-ping"></span>
            <span class="font-semibold">● 实时推送中 (STREAMING)</span>
          </div>
          <div class="flex items-center gap-2 text-steel-muted">
            <span class="material-symbols-outlined text-primary-container text-[16px]">sync</span>
            <span>轮询间隔: <span class="text-ink-white font-medium">10s</span></span>
          </div>
        </div>
      </div>
      <!-- Data Table -->
      <div class="overflow-x-auto">
        <table class="w-full text-left border-collapse">
          <thead>
            <tr class="border-b border-hairline bg-surface-slate/70 text-label-sm font-mono-data text-steel-muted uppercase tracking-wider h-10">
              <th class="py-2.5 px-4 font-semibold">时间 (Time)</th>
              <th class="py-2.5 px-4 font-semibold">币种 (Asset)</th>
              <th class="py-2.5 px-4 font-semibold">交易对与平台 (Pair &amp; Venue)</th>
              <th class="py-2.5 px-4 font-semibold text-center">方向 (Side)</th>
              <th class="py-2.5 px-4 font-semibold text-right">触发价格 (Price)</th>
              <th class="py-2.5 px-4 font-semibold text-right">强平数量 (Size)</th>
              <th class="py-2.5 px-4 font-semibold text-right">名义价值 (Notional USD)</th>
              <th class="py-2.5 px-4 font-semibold text-center">强平类型 (Type)</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-hairline/60 font-mono-data text-mono-data">
            <tr v-for="(e, i) in filteredEvents" :key="i" class="hover:bg-card-navy-high/50 transition-colors h-11">
              <td class="py-2 px-4 text-steel-muted text-xs">{{ fmtTime(e.ts) }}</td>
              <td class="py-2 px-4 font-bold text-ink-white">
                <div class="flex items-center gap-2">
                  <span class="w-5 h-5 rounded-full flex items-center justify-center text-[10px] font-bold" :class="avatarCls(e.symbol)">{{ avatarChar(e.symbol) }}</span>
                  {{ coinOf(e.symbol) }}
                </div>
              </td>
              <td class="py-2 px-4">
                <span class="text-ink-white">{{ e.symbol }}</span>
                <span class="ml-2 px-1.5 py-0.5 rounded text-[10px] bg-surface-slate text-steel-muted border border-hairline">{{ e.exchange || '--' }} 永续</span>
              </td>
              <td class="py-2 px-4 text-center">
                <span
                  class="px-2 py-0.5 rounded text-xs font-semibold border"
                  :class="isLong(e) ? 'bg-bull-green/10 text-bull-green border-bull-green/30' : 'bg-bear-red/10 text-bear-red border-bear-red/30'"
                >
                  {{ isLong(e) ? '多单强平 LONG' : '空单强平 SHORT' }}
                </span>
              </td>
              <td class="py-2 px-4 text-right font-medium text-ink-white">${{ fmtPrice(e.price) }}</td>
              <td class="py-2 px-4 text-right text-steel-muted">{{ fmtBig(e.qty, 4) }} {{ coinOf(e.symbol) }}</td>
              <td class="py-2 px-4 text-right font-bold" :class="isLong(e) ? 'text-bull-green' : 'text-bear-red'">{{ fmtUsd(e.notional_usd) }}</td>
              <td class="py-2 px-4 text-center text-xs text-steel-muted">强平平仓 (Market)</td>
            </tr>
            <tr v-if="!filteredEvents.length">
              <td colspan="8" class="py-8 text-center text-steel-muted text-mono-data">暂无爆仓事件</td>
            </tr>
          </tbody>
        </table>
      </div>
      <!-- Feed Footer -->
      <div class="px-5 py-3 border-t border-hairline bg-surface-slate/30 flex items-center justify-between text-label-sm font-mono-data text-steel-muted">
        <div class="flex items-center gap-3">
          <span>展示 {{ filteredEvents.length }} 条 / 实时缓存池 {{ events.length }} 条</span>
          <span class="text-hairline">|</span>
          <span class="text-bull-green flex items-center gap-1">
            <span class="w-1.5 h-1.5 rounded-full bg-bull-green"></span> 数据源: 全网聚合清算流
          </span>
        </div>
        <div class="flex items-center gap-2">
          <span class="px-2.5 py-1 bg-canvas-obsidian border border-hairline rounded">自动刷新: 10s</span>
        </div>
      </div>
    </section>
  </div>
</template>
