<script setup>
import { onMounted, onBeforeUnmount, ref, computed } from 'vue'
import EChart from '../components/EChart.vue'
import { overviewApi } from '../api'
import { fmtUsd, fmtBig, fmtTime, coinOf } from '../utils/format'

const alerts = ref([])
const status = ref({})
const sideFilter = ref('all') // all | Buy | Sell
const threshold = ref(0) // 名义价值阈值 (USD)
const loading = ref(true)
let timer = null

const THRESHOLDS = [
  { v: 0, t: '全部' },
  { v: 1e6, t: '≥$1M' },
  { v: 5e6, t: '≥$5M' },
  { v: 1e7, t: '≥$10M' },
]

const filtered = computed(() =>
  alerts.value.filter(
    (a) =>
      (sideFilter.value === 'all' || a.side === sideFilter.value) &&
      Number(a.positionSize || 0) >= threshold.value
  )
)

const totalUsd = computed(() => alerts.value.reduce((s, a) => s + Number(a.positionSize || 0), 0))
const buyUsd = computed(() => alerts.value.filter((a) => a.side === 'Buy').reduce((s, a) => s + Number(a.positionSize || 0), 0))
const sellUsd = computed(() => alerts.value.filter((a) => a.side === 'Sell').reduce((s, a) => s + Number(a.positionSize || 0), 0))
const netUsd = computed(() => buyUsd.value - sellUsd.value)

// 大额成交币种分布 (Top3 + 其他)
const DIST_COLORS = ['#2E5CFF', '#627EEA', '#00E388', '#9EA0B2']
const coinDist = computed(() => {
  const map = {}
  for (const a of alerts.value) {
    const c = coinOf(a.symbol)
    map[c] = (map[c] || 0) + Number(a.positionSize || 0)
  }
  const sorted = Object.entries(map).sort((x, y) => y[1] - x[1])
  const top = sorted.slice(0, 3).map(([symbol, value], i) => ({ symbol, value, color: DIST_COLORS[i] }))
  const rest = sorted.slice(3).reduce((s, [, v]) => s + v, 0)
  if (rest > 0) top.push({ symbol: '其他', value: rest, color: DIST_COLORS[3] })
  return top
})

const donutOption = computed(() => ({
  tooltip: { show: false },
  series: [
    {
      type: 'pie',
      radius: ['68%', '88%'],
      center: ['50%', '50%'],
      label: { show: false },
      data: coinDist.value.map((d) => ({ value: d.value, name: d.symbol, itemStyle: { color: d.color } })),
    },
  ],
}))

// 24H 买卖方向时序柱状图 (6 个 4H 桶)
const trendBars = computed(() => {
  const now = Date.now()
  const start = now - 24 * 3600e3
  const buckets = Array.from({ length: 6 }, () => ({ buy: 0, sell: 0 }))
  for (const a of alerts.value) {
    const t = Number(a.time)
    if (!t || t < start) continue
    const i = Math.min(5, Math.floor((t - start) / (4 * 3600e3)))
    if (a.side === 'Buy') buckets[i].buy += Number(a.positionSize || 0)
    else buckets[i].sell += Number(a.positionSize || 0)
  }
  const max = Math.max(1, ...buckets.map((b) => Math.max(b.buy, b.sell)))
  const p = (x) => String(x).padStart(2, '0')
  const labels = buckets.map((_, i) => {
    const t = new Date(start + i * 4 * 3600e3)
    return `${p(t.getHours())}h`
  })
  return buckets.map((b, i) => ({
    label: i === 5 ? 'Now' : labels[i],
    net: b.buy - b.sell,
    height: Math.max(6, Math.round((Math.max(b.buy, b.sell) / max) * 92)),
    isBuy: b.buy >= b.sell,
  }))
})

const SOURCE_BADGE = {
  hyperliquid: 'bg-[#627EEA]/15 text-[#8fa2ff] border-[#627EEA]/30',
  binance: 'bg-[#F3BA2F]/15 text-[#f3ba2f] border-[#F3BA2F]/30',
}
const sourceCls = (a) => {
  const s = String(a.source || '').toLowerCase()
  for (const k of Object.keys(SOURCE_BADGE)) if (s.includes(k)) return SOURCE_BADGE[k]
  return 'bg-card-navy-high text-steel-muted border-hairline'
}

async function load() {
  try {
    const [a, s] = await Promise.allSettled([overviewApi.whaleAlerts(), overviewApi.whaleStatus()])
    if (a.status === 'fulfilled') alerts.value = a.value?.alerts || []
    if (s.status === 'fulfilled') status.value = s.value || {}
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
    <!-- 1. TOP FILTER BAR CARD -->
    <section class="bg-card-navy border border-hairline rounded-xl p-4 flex flex-wrap items-center justify-between gap-4">
      <div class="flex flex-wrap items-center gap-4">
        <!-- Side Filter Pills -->
        <div class="flex items-center gap-1.5 bg-canvas-obsidian/60 p-1 rounded-xl border border-hairline">
          <button
            class="px-3 py-1 rounded font-headline-sm text-headline-sm transition-all"
            :class="sideFilter === 'all' ? 'bg-primary-container text-ink-white shadow-sm' : 'hover:bg-card-navy-high text-steel-muted hover:text-ink-white'"
            @click="sideFilter = 'all'"
          >全部</button>
          <button
            class="px-3 py-1 rounded font-headline-sm text-headline-sm transition-all flex items-center gap-1.5"
            :class="sideFilter === 'Buy' ? 'bg-primary-container text-ink-white shadow-sm' : 'hover:bg-card-navy-high text-steel-muted hover:text-ink-white'"
            @click="sideFilter = 'Buy'"
          >
            <span class="w-2 h-2 rounded-full bg-bull-green"></span>
            <span>买入</span>
          </button>
          <button
            class="px-3 py-1 rounded font-headline-sm text-headline-sm transition-all flex items-center gap-1.5"
            :class="sideFilter === 'Sell' ? 'bg-primary-container text-ink-white shadow-sm' : 'hover:bg-card-navy-high text-steel-muted hover:text-ink-white'"
            @click="sideFilter = 'Sell'"
          >
            <span class="w-2 h-2 rounded-full bg-bear-red"></span>
            <span>卖出</span>
          </button>
        </div>
        <div class="h-5 w-px bg-hairline hidden sm:block"></div>
        <!-- Value Threshold Buttons -->
        <div class="flex items-center gap-1.5">
          <span class="text-label-sm font-label-sm text-steel-muted mr-1">阈值:</span>
          <button
            v-for="t in THRESHOLDS"
            :key="t.v"
            class="px-2.5 py-1 rounded font-mono-data text-mono-data border transition-colors"
            :class="threshold === t.v
              ? 'bg-card-navy-high text-primary-fixed-dim border-primary-container/40'
              : 'bg-surface-slate text-steel-muted hover:text-ink-white border-hairline'"
            @click="threshold = t.v"
          >{{ t.t }}</button>
        </div>
      </div>
      <!-- Right Meta Metrics -->
      <div class="flex items-center gap-5 text-mono-data font-mono-data text-steel-muted text-[12px]">
        <div class="flex items-center gap-1.5">
          <span class="material-symbols-outlined text-[15px] text-primary-fixed-dim">visibility</span>
          <span>监控大额成交:</span>
          <span class="text-ink-white font-semibold">{{ alerts.length }} 笔</span>
        </div>
        <div class="h-3.5 w-px bg-hairline"></div>
        <div class="flex items-center gap-1.5">
          <span class="material-symbols-outlined text-[15px]" :class="status.hl_connected ? 'text-bull-green' : 'text-amber-warn'">speed</span>
          <span>数据流:</span>
          <span class="font-semibold" :class="status.hl_connected ? 'text-bull-green' : 'text-amber-warn'">
            {{ status.hl_connected ? '已连接' : '重连中' }}{{ status.last_msg_age_s != null ? ` · ${status.last_msg_age_s}s 前` : '' }}
          </span>
        </div>
      </div>
    </section>

    <!-- 2. GRID: 8 Cols Table / 4 Cols Analytics -->
    <div class="grid grid-cols-1 lg:grid-cols-12 gap-6 items-start">
      <!-- LEFT: LARGE TRANSFERS TABLE -->
      <section class="lg:col-span-8 bg-card-navy border border-hairline rounded-xl flex flex-col overflow-hidden">
        <!-- Table Header Toolbar -->
        <div class="p-4 border-b border-hairline flex flex-wrap items-center justify-between gap-3 bg-surface-slate/30">
          <div class="flex items-center gap-3">
            <h2 class="text-headline-sm font-headline-sm text-ink-white font-bold flex items-center gap-2">
              <span class="material-symbols-outlined text-primary-container">list_alt</span>
              <span>大额成交流水 LARGE TRANSFERS</span>
            </h2>
            <div class="flex items-center gap-1.5 px-2 py-0.5 rounded bg-bull-green/10 border border-bull-green/20">
              <span class="w-1.5 h-1.5 rounded-full bg-bull-green animate-pulse"></span>
              <span class="text-[10px] font-mono-data text-bull-green font-medium">实时推送 ACTIVE</span>
            </div>
          </div>
          <div class="flex items-center gap-3">
            <div class="flex items-center gap-1.5 text-label-sm font-label-sm text-steel-muted">
              <span class="material-symbols-outlined text-[14px]">sync</span>
              <span>自动刷新: <strong class="text-ink-white font-mono-data">10s</strong></span>
            </div>
            <span class="px-2 py-1 rounded bg-surface-slate border border-hairline text-label-sm font-label-sm text-steel-muted">
              Hyperliquid + Binance 双源
            </span>
          </div>
        </div>
        <!-- Data Table -->
        <div class="overflow-x-auto">
          <table class="w-full text-left border-collapse">
            <thead>
              <tr class="border-b border-hairline bg-surface-slate/60 text-label-sm font-label-sm text-steel-muted uppercase tracking-wider">
                <th class="py-3 px-3 pl-4">时间</th>
                <th class="py-3 px-2">来源</th>
                <th class="py-3 px-3">交易方</th>
                <th class="py-3 px-2">币种</th>
                <th class="py-3 px-4 text-right">名义价值</th>
                <th class="py-3 px-3 text-center">资金动向</th>
                <th class="py-3 px-3 pr-4 text-center">详情</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-hairline font-mono-data text-mono-data text-[12px]">
              <tr v-for="(a, i) in filtered" :key="i" class="hover:bg-card-navy-high transition-colors group h-12">
                <td class="py-2.5 px-3 pl-4 text-steel-muted whitespace-nowrap">{{ fmtTime(a.time) }}</td>
                <td class="py-2.5 px-2">
                  <span class="px-1.5 py-0.5 rounded text-[10px] font-bold border" :class="sourceCls(a)">{{ a.source || '链上' }}</span>
                </td>
                <td class="py-2.5 px-3 text-ink-white">
                  <span class="truncate inline-block max-w-[140px] align-middle" :title="a.user">{{ a.user || '匿名大户' }}</span>
                </td>
                <td class="py-2.5 px-2 font-bold text-ink-white">{{ coinOf(a.symbol) }}</td>
                <td class="py-2.5 px-4 text-right font-bold text-ink-white tracking-tight">{{ fmtUsd(a.positionSize) }}</td>
                <td class="py-2.5 px-3 text-center">
                  <span
                    class="inline-flex items-center px-2 py-0.5 rounded text-[11px] font-semibold border"
                    :class="a.side === 'Buy' ? 'bg-bull-green/15 text-bull-green border-bull-green/30' : 'bg-bear-red/15 text-bear-red border-bear-red/30'"
                  >
                    {{ a.side === 'Buy' ? '大额买入' : '大额卖出' }}
                  </span>
                </td>
                <td class="py-2.5 px-3 pr-4 text-center">
                  <span class="text-steel-muted inline-block" title="实时流事件">
                    <span class="material-symbols-outlined text-[16px]">open_in_new</span>
                  </span>
                </td>
              </tr>
              <tr v-if="!filtered.length">
                <td colspan="7" class="py-8 text-center text-steel-muted text-mono-data">暂无大额成交</td>
              </tr>
            </tbody>
          </table>
        </div>
        <!-- Table Footer -->
        <div class="p-3 border-t border-hairline bg-surface-slate/20 flex flex-wrap items-center justify-between gap-3 text-mono-data font-mono-data text-[12px] text-steel-muted">
          <div>
            显示 <span class="text-ink-white">{{ filtered.length }}</span> / 共 <span class="text-ink-white">{{ alerts.length }}</span> 条异动
          </div>
          <div class="flex items-center gap-1.5">
            <span class="px-2.5 py-1 rounded bg-card-navy-high text-primary-fixed-dim border border-primary-container/40">实时缓存</span>
          </div>
        </div>
      </section>

      <!-- RIGHT: ANALYTICS CARDS -->
      <div class="lg:col-span-4 flex flex-col gap-6">
        <!-- Card 1: 大额成交币种分布 -->
        <div class="bg-card-navy border border-hairline rounded-xl p-5 flex flex-col gap-4">
          <div class="flex items-center justify-between pb-3 border-b border-hairline">
            <div class="flex items-center gap-2">
              <span class="material-symbols-outlined text-primary-fixed-dim text-[20px]">pie_chart</span>
              <h3 class="text-headline-sm font-headline-sm text-ink-white font-bold">大额成交币种分布</h3>
            </div>
            <span class="text-label-sm font-label-sm px-2 py-0.5 rounded bg-surface-slate text-steel-muted border border-hairline font-mono-data">
              实时缓存
            </span>
          </div>
          <!-- Donut -->
          <div class="relative flex items-center justify-center py-2">
            <EChart :option="donutOption" height="192px" />
            <div class="absolute inset-0 flex flex-col items-center justify-center pointer-events-none text-center">
              <span class="text-label-sm font-label-sm text-steel-muted uppercase">总成交名义</span>
              <span class="text-headline-md font-mono-data font-bold text-ink-white tracking-tight">{{ fmtUsd(totalUsd || null) }}</span>
              <span class="text-[10px] font-mono-data text-bull-green flex items-center gap-0.5">
                <span class="material-symbols-outlined text-[12px]">trending_up</span>
                <span>{{ alerts.length }} 笔监控中</span>
              </span>
            </div>
          </div>
          <!-- Breakdown Progress & Legends -->
          <div class="flex flex-col gap-2.5 pt-1">
            <div v-for="d in coinDist" :key="d.symbol" class="flex flex-col gap-1">
              <div class="flex items-center justify-between text-[12px] font-mono-data">
                <div class="flex items-center gap-2">
                  <span class="w-2.5 h-2.5 rounded-sm" :style="{ background: d.color }"></span>
                  <span class="text-ink-white font-medium">{{ d.symbol }}</span>
                </div>
                <div class="text-right">
                  <span class="text-ink-white font-bold">{{ totalUsd ? ((d.value / totalUsd) * 100).toFixed(1) + '%' : '--' }}</span>
                  <span class="text-steel-muted text-[11px] ml-1.5">({{ fmtUsd(d.value) }})</span>
                </div>
              </div>
              <div class="w-full bg-surface-slate h-1.5 rounded-full overflow-hidden">
                <div class="h-full rounded-full" :style="{ background: d.color, width: (totalUsd ? (d.value / totalUsd) * 100 : 0) + '%' }"></div>
              </div>
            </div>
            <div v-if="!coinDist.length" class="text-steel-muted text-mono-data font-mono-data text-center py-3">暂无数据</div>
          </div>
          <div class="mt-1 pt-3 border-t border-hairline flex items-center justify-between text-[11px] font-mono-data text-steel-muted">
            <span>数据源:</span>
            <span class="text-ink-white font-bold">Hyperliquid + Binance</span>
          </div>
        </div>

        <!-- Card 2: 买卖净额 -->
        <div class="bg-card-navy border border-hairline rounded-xl p-5 flex flex-col gap-4">
          <div class="flex items-center justify-between pb-3 border-b border-hairline">
            <div class="flex items-center gap-2">
              <span class="material-symbols-outlined text-bull-green text-[20px]">currency_exchange</span>
              <h3 class="text-headline-sm font-headline-sm text-ink-white font-bold">大额买卖净额</h3>
            </div>
            <span class="text-[11px] font-mono-data text-steel-muted">实时缓存视点</span>
          </div>
          <div class="flex flex-col gap-1">
            <div class="text-[11px] font-mono-data uppercase tracking-wider text-steel-muted">
              巨鲸净买入额 (NET WHALE FLOW)
            </div>
            <div
              class="text-[34px] font-mono-data font-bold tracking-tight leading-none"
              :class="netUsd >= 0 ? 'text-bull-green' : 'text-bear-red'"
            >
              {{ (netUsd >= 0 ? '+' : '-') + fmtUsd(Math.abs(netUsd)) }}
            </div>
            <div class="flex items-center gap-2 mt-2">
              <span
                class="px-2 py-0.5 rounded text-[11px] font-semibold border flex items-center gap-1 font-mono-data"
                :class="netUsd >= 0 ? 'bg-bull-green/15 text-bull-green border-bull-green/30' : 'bg-bear-red/15 text-bear-red border-bear-red/30'"
              >
                <span class="material-symbols-outlined text-[13px]">{{ netUsd >= 0 ? 'arrow_outward' : 'trending_down' }}</span>
                <span>{{ netUsd >= 0 ? '买盘占优 (ACCUMULATION)' : '卖盘占优 (DISTRIBUTION)' }}</span>
              </span>
            </div>
          </div>
          <div class="grid grid-cols-2 gap-3 p-3 rounded bg-surface-slate/80 border border-hairline font-mono-data text-[12px]">
            <div>
              <div class="text-steel-muted text-[11px]">大额买入 (吸筹)</div>
              <div class="text-bull-green font-bold text-[14px] mt-0.5">{{ fmtUsd(buyUsd || null) }}</div>
            </div>
            <div class="border-l border-hairline pl-3">
              <div class="text-steel-muted text-[11px]">大额卖出 (抛压)</div>
              <div class="text-bear-red font-bold text-[14px] mt-0.5">{{ fmtUsd(sellUsd || null) }}</div>
            </div>
          </div>
          <!-- Trend Bar Chart (4H buckets) -->
          <div class="flex flex-col gap-1.5 pt-1">
            <div class="flex items-center justify-between text-[11px] font-mono-data text-steel-muted">
              <span>24H 走势时序柱状图 (每4小时)</span>
              <span>基准线: 0 轴</span>
            </div>
            <div class="h-20 w-full bg-canvas-obsidian/40 rounded border border-hairline p-2 flex items-end justify-between gap-2 relative">
              <div class="absolute left-2 right-2 bottom-[35%] h-px bg-hairline/80 z-0 border-dashed border-t"></div>
              <div v-for="(b, i) in trendBars" :key="i" class="flex-1 flex flex-col items-center h-full justify-end z-10 group relative">
                <div
                  class="w-full rounded-t transition-all"
                  :class="[b.isBuy ? 'bg-bull-green/80 hover:bg-bull-green' : 'bg-bear-red/80 hover:bg-bear-red', i === trendBars.length - 1 ? 'shadow-[0_0_8px_rgba(0,227,136,0.3)]' : '']"
                  :style="{ height: b.height + '%' }"
                  :title="fmtUsd(Math.abs(b.net))"
                ></div>
                <span class="text-[9px] font-mono-data mt-1" :class="i === trendBars.length - 1 ? 'text-bull-green font-bold' : 'text-steel-muted'">{{ b.label }}</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
