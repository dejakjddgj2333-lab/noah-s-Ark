<script setup>
import { onMounted, onBeforeUnmount, ref, computed, watch } from 'vue'
import { useRouter } from 'vue-router'
import EChart from '../components/EChart.vue'
import { marketApi, overviewApi } from '../api'
import { fmtPrice, fmtPct, fmtBig, fmtUsd, coinOf } from '../utils/format'
import { getWatchlist, toggleWatchlist, syncWatchlist } from '../utils/watchlist'

const router = useRouter()

// 纯展示: 常见币种头像配色 / 符号 / 中文名 (对齐设计稿行情表)
const COIN_META = {
  BTC: { sym: '₿', cls: 'bg-amber-warn/20 border border-amber-warn/40 text-amber-warn', name: 'Bitcoin 比特币' },
  ETH: { sym: 'Ξ', cls: 'bg-primary-container/20 border border-primary-container/40 text-primary', name: 'Ethereum 以太坊' },
  SOL: { sym: 'S', cls: 'bg-cyan-500/20 border border-cyan-400/40 text-cyan-300', name: 'Solana 索拉纳' },
  BNB: { sym: 'B', cls: 'bg-yellow-500/20 border border-yellow-400/40 text-yellow-300', name: 'BNB 币安币' },
  XRP: { sym: '✕', cls: 'bg-blue-500/20 border border-blue-400/40 text-blue-300', name: 'Ripple 瑞波币' },
  DOGE: { sym: 'Ð', cls: 'bg-amber-600/20 border border-amber-500/40 text-amber-200', name: 'Dogecoin 狗狗币' },
  ADA: { sym: '₳', cls: 'bg-indigo-500/20 border border-indigo-400/40 text-indigo-300', name: 'Cardano 艾达币' },
  AVAX: { sym: '▲', cls: 'bg-red-500/20 border border-red-400/40 text-red-300', name: 'Avalanche 雪崩' },
  LINK: { sym: '⬡', cls: 'bg-blue-600/20 border border-blue-500/40 text-blue-400', name: 'Chainlink' },
  TON: { sym: 'T', cls: 'bg-sky-500/20 border border-sky-400/40 text-sky-300', name: 'Toncoin' },
}
function coinMeta(instId) {
  const c = coinOf(instId)
  return COIN_META[c] || {
    sym: c.slice(0, 1),
    cls: 'bg-primary-container/20 border border-primary-container/40 text-primary',
    name: instId,
  }
}
const instType = ref('SPOT')
const favOnly = ref(false) // 自选页签: 只看星标币种
const keyword = ref('')
const rows = ref([])
const stats = ref({})
const lsRatio = ref({})
const fng = ref(null)
const liqCoins = ref([])
const loading = ref(true)
const page = ref(1)
const pageSize = 20
const spark = ref({})
const watchlist = ref(getWatchlist())
let timer = null

function toggleWatch(instId) {
  watchlist.value = toggleWatchlist(instId)
}

function pct(t) {
  const open = Number(t.open24h)
  if (!open) return 0
  return ((Number(t.last) - open) / open) * 100
}

const filtered = computed(() => {
  let list = [...rows.value]
  if (favOnly.value) list = list.filter((t) => watchlist.value.includes(t.instId))
  const kw = keyword.value.trim().toUpperCase()
  if (kw) list = list.filter((t) => t.instId.includes(kw))
  return list.sort((a, b) => Number(b.volCcy24h) - Number(a.volCcy24h)).slice(0, 100)
})

const totalPages = computed(() => Math.max(1, Math.ceil(filtered.value.length / pageSize)))
const paged = computed(() => filtered.value.slice((page.value - 1) * pageSize, page.value * pageSize))
const pageNums = computed(() => {
  const t = totalPages.value
  const c = page.value
  let start = Math.max(1, Math.min(c - 1, t - 2))
  const nums = []
  for (let i = start; i <= Math.min(start + 2, t); i++) nums.push(i)
  return nums
})

// ---- 顶部遥测条 ----
const fngLabel = computed(() => {
  const v = fng.value
  if (v === null || v === undefined) return '--'
  if (v >= 75) return '极度贪婪'
  if (v >= 50) return '贪婪'
  if (v >= 25) return '恐慌'
  return '极度恐慌'
})
const fngColor = computed(() => {
  const v = fng.value
  if (v === null || v === undefined) return 'text-ink-white'
  if (v >= 50) return 'text-bull-green'
  if (v >= 25) return 'text-amber-warn'
  return 'text-bear-red'
})
const lsText = computed(() => {
  const l = Number(lsRatio.value.long_pct)
  const s = Number(lsRatio.value.short_pct)
  if (!l || !s) return '--'
  return `${(l / s).toFixed(2)} : 1`
})
const lsSub = computed(() => {
  const l = Number(lsRatio.value.long_pct)
  const s = Number(lsRatio.value.short_pct)
  if (!l || !s) return '--'
  return l >= s ? '多头占优' : '空头占优'
})
const lsSubColor = computed(() => (lsSub.value === '空头占优' ? 'text-bear-red' : 'text-bull-green'))
const liqTotal = computed(() =>
  liqCoins.value.reduce((s, c) => s + Number(c.liquidation_usd_24h ?? c.liqUsd24h ?? 0), 0)
)
const liqShortPct = computed(() => {
  const long = liqCoins.value.reduce((s, c) => s + Number(c.long_liquidation_usd_24h ?? c.longLiqUsd24h ?? 0), 0)
  const short = liqCoins.value.reduce((s, c) => s + Number(c.short_liquidation_usd_24h ?? c.shortLiqUsd24h ?? 0), 0)
  if (!long && !short) return null
  return (short / (long + short)) * 100
})

// ---- 7 日走势迷你面积图 (每页 10 行懒加载 1D x 7) ----
function sparkOption(t) {
  const data = spark.value[t.instId]
  if (!Array.isArray(data) || data.length < 2) return null
  const up = data[data.length - 1] >= data[0]
  const color = up ? '#00E388' : '#FF5F6D'
  return {
    grid: { left: 0, right: 0, top: 2, bottom: 0 },
    xAxis: { type: 'category', show: false, data: data.map((_, i) => i), boundaryGap: false },
    yAxis: { type: 'value', show: false, scale: true },
    series: [{
      type: 'line',
      data,
      showSymbol: false,
      smooth: 0.35,
      lineStyle: { color, width: 1.5 },
      areaStyle: {
        color: {
          type: 'linear', x: 0, y: 0, x2: 0, y2: 1,
          colorStops: [{ offset: 0, color: color + '33' }, { offset: 1, color: 'transparent' }],
        },
      },
    }],
  }
}

watch(paged, (list) => {
  list.forEach((t) => {
    const id = t.instId
    if (spark.value[id] !== undefined) return
    spark.value[id] = 'loading'
    marketApi.candles(id, '1D', 7)
      .then((res) => {
        const data = (res?.data || []).slice().reverse().map((c) => +c[4])
        spark.value[id] = data.length > 1 ? data : null
      })
      .catch(() => { spark.value[id] = null })
  })
}, { immediate: true })

watch(keyword, () => { page.value = 1 })

async function load() {
  try {
    const [tk, g, s, ls, lq] = await Promise.allSettled([
      marketApi.tickers(instType.value),
      overviewApi.globalStats(),
      overviewApi.sentiment(),
      overviewApi.longShortRatio('BTC'),
      overviewApi.liqCoinList(),
    ])
    if (tk.status === 'fulfilled')
      rows.value = (tk.value?.data || []).filter((t) =>
        instType.value === 'SWAP' ? t.instId.endsWith('-USDT-SWAP') : t.instId.endsWith('-USDT')
      )
    if (g.status === 'fulfilled') stats.value = g.value
    if (s.status === 'fulfilled') fng.value = s.value?.fear_greed ?? null
    if (ls.status === 'fulfilled') lsRatio.value = ls.value || {}
    if (lq.status === 'fulfilled') liqCoins.value = lq.value?.coins || []
  } finally {
    loading.value = false
  }
}

function switchType(t) {
  instType.value = t
  favOnly.value = false
  page.value = 1
  loading.value = true
  load()
}

function showFav() {
  favOnly.value = true
  page.value = 1
}

function goPage(p) {
  if (p < 1 || p > totalPages.value) return
  page.value = p
}

onMounted(() => {
  load()
  timer = setInterval(load, 15000)
  // 服务器自选同步到本地 (多端一致)
  syncWatchlist().then((list) => { watchlist.value = [...list] })
})
onBeforeUnmount(() => clearInterval(timer))
</script>

<template>
  <div class="flex flex-col gap-space-lg">
    <!-- 顶部遥测条 -->
    <div class="grid grid-cols-2 md:grid-cols-4 gap-space-md">
      <div class="bg-card-navy border border-hairline rounded-xl p-3.5 flex flex-col justify-between">
        <div class="flex items-center justify-between text-steel-muted">
          <span class="font-label-sm text-label-sm uppercase">24H 全网成交额</span>
          <span class="material-symbols-outlined text-[16px] text-steel-muted">query_stats</span>
        </div>
        <div class="flex items-baseline space-x-2 mt-1">
          <span class="font-mono-data text-ink-white font-bold text-[18px] tracking-tight">{{ fmtUsd(stats.total_volume_usd) }}</span>
          <span class="font-mono-data text-[11px] font-semibold" :class="Number(stats.market_cap_change_pct_24h) >= 0 ? 'text-bull-green' : 'text-bear-red'">{{ fmtPct(stats.market_cap_change_pct_24h) }}</span>
        </div>
      </div>
      <div class="bg-card-navy border border-hairline rounded-xl p-3.5 flex flex-col justify-between">
        <div class="flex items-center justify-between text-steel-muted">
          <span class="font-label-sm text-label-sm uppercase">全网多空比 (BTC)</span>
          <span class="material-symbols-outlined text-[16px] text-steel-muted">stacked_bar_chart</span>
        </div>
        <div class="flex items-baseline space-x-2 mt-1">
          <span class="font-mono-data text-ink-white font-bold text-[18px] tracking-tight">{{ lsText }}</span>
          <span class="font-mono-data text-[11px] font-semibold" :class="lsSubColor">{{ lsSub }}</span>
        </div>
      </div>
      <div class="bg-card-navy border border-hairline rounded-xl p-3.5 flex flex-col justify-between">
        <div class="flex items-center justify-between text-steel-muted">
          <span class="font-label-sm text-label-sm uppercase">恐惧 &amp; 贪婪指数</span>
          <span class="material-symbols-outlined text-[16px] text-steel-muted">speed</span>
        </div>
        <div class="flex items-baseline space-x-2 mt-1">
          <span class="font-mono-data font-bold text-[18px] tracking-tight" :class="fngColor">{{ fng ?? '--' }}</span>
          <span class="font-label-sm text-label-sm" :class="fngColor">{{ fngLabel }}</span>
        </div>
      </div>
      <div class="bg-card-navy border border-hairline rounded-xl p-3.5 flex flex-col justify-between">
        <div class="flex items-center justify-between text-steel-muted">
          <span class="font-label-sm text-label-sm uppercase">24H 爆仓总额</span>
          <span class="material-symbols-outlined text-[16px] text-steel-muted">warning</span>
        </div>
        <div class="flex items-baseline space-x-2 mt-1">
          <span class="font-mono-data text-ink-white font-bold text-[18px] tracking-tight">{{ liqTotal ? fmtUsd(liqTotal) : '--' }}</span>
          <span v-if="liqShortPct != null" class="font-mono-data text-bear-red text-[11px] font-semibold">空单爆仓 {{ liqShortPct.toFixed(0) }}%</span>
        </div>
      </div>
    </div>

    <!-- TAB 筛选与工具条 -->
    <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3 border-b border-hairline pb-2">
      <div class="flex items-center space-x-6">
        <button
          class="relative pb-2 transition-all"
          :class="instType === 'SPOT' && !favOnly ? 'font-headline-sm text-headline-sm text-ink-white font-semibold' : 'font-body-md text-body-md text-steel-muted hover:text-ink-white'"
          @click="switchType('SPOT')"
        >
          <span>现货</span>
          <span v-if="instType === 'SPOT' && !favOnly" class="absolute bottom-0 left-0 right-0 h-0.5 bg-primary-container rounded-full"></span>
        </button>
        <button
          class="relative pb-2 transition-all"
          :class="instType === 'SWAP' && !favOnly ? 'font-headline-sm text-headline-sm text-ink-white font-semibold' : 'font-body-md text-body-md text-steel-muted hover:text-ink-white'"
          @click="switchType('SWAP')"
        >
          <span>永续</span>
          <span v-if="instType === 'SWAP' && !favOnly" class="absolute bottom-0 left-0 right-0 h-0.5 bg-primary-container rounded-full"></span>
        </button>
        <button
          class="relative pb-2 transition-all flex items-center gap-1"
          :class="favOnly ? 'font-headline-sm text-headline-sm text-ink-white font-semibold' : 'font-body-md text-body-md text-steel-muted hover:text-ink-white'"
          @click="showFav"
        >
          <span
            class="material-symbols-outlined text-[15px]"
            :class="favOnly ? 'text-amber-warn' : ''"
            :style="favOnly ? { 'font-variation-settings': `'FILL' 1` } : {}"
          >star</span>
          <span>自选</span>
          <span class="font-mono-data text-[11px] opacity-70">{{ watchlist.length }}</span>
          <span v-if="favOnly" class="absolute bottom-0 left-0 right-0 h-0.5 bg-amber-warn rounded-full"></span>
        </button>
      </div>
      <div class="flex items-center space-x-3">
        <span class="font-mono-data text-mono-data text-steel-muted text-[11px]">共 {{ filtered.length }} 个币种</span>
        <div class="relative w-56">
          <span class="material-symbols-outlined absolute left-2.5 top-1/2 -translate-y-1/2 text-steel-muted text-[15px]">search</span>
          <input
            v-model="keyword"
            class="w-full h-7 pl-8 pr-3 bg-surface-slate rounded-lg border border-hairline text-ink-white placeholder-steel-muted text-[12px] font-mono-data focus:outline-none focus:border-primary-container focus:ring-1 focus:ring-primary-container transition-all"
            placeholder="搜索币种..."
            type="text"
          />
        </div>
        <button
          class="h-7 px-2.5 rounded-lg border border-hairline bg-surface-slate text-steel-muted hover:text-ink-white hover:border-outline flex items-center space-x-1 font-label-sm text-label-sm transition-colors"
          @click="load"
        >
          <span class="material-symbols-outlined text-[14px]">refresh</span>
          <span>刷新</span>
        </button>
      </div>
    </div>

    <!-- 行情数据表 -->
    <div class="bg-card-navy border border-hairline rounded-xl overflow-hidden shadow-2xl">
      <div class="overflow-x-auto">
        <div v-if="loading" class="p-10 text-center text-steel-muted font-label-sm text-label-sm">行情加载中…</div>
        <table v-else class="w-full text-left border-collapse">
          <thead>
            <tr class="h-11 border-b border-hairline bg-surface-slate/80 text-steel-muted font-label-sm text-label-sm uppercase select-none">
              <th class="pl-4 pr-2 w-12 text-center">#</th>
              <th class="px-3 min-w-[200px]">币种 / 资产</th>
              <th class="px-3 text-right min-w-[120px]">最新价 (USD)</th>
              <th class="px-3 text-right min-w-[110px]">24H 涨跌</th>
              <th class="px-3 text-right min-w-[120px]">24H 最高</th>
              <th class="px-3 text-right min-w-[120px]">24H 最低</th>
              <th class="px-3 text-right min-w-[130px]">24H 成交额</th>
              <th class="px-3 text-right min-w-[140px]">总市值</th>
              <th class="px-4 text-center min-w-[140px]">7日走势</th>
              <th class="pr-4 pl-2 text-center w-14">操作</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-hairline font-mono-data text-mono-data">
            <tr
              v-for="(t, i) in paged"
              :key="t.instId"
              class="h-11 hover:bg-card-navy-high transition-colors duration-150 group cursor-pointer"
              @click="router.push(`/market/${t.instId}`)"
            >
              <td class="pl-4 pr-2 text-center text-steel-muted text-[11px]">{{ (page - 1) * pageSize + i + 1 }}</td>
              <td class="px-3">
                <div class="flex items-center space-x-2.5">
                  <div class="w-6 h-6 rounded-full flex items-center justify-center font-bold text-[11px] shrink-0 uppercase" :class="coinMeta(t.instId).cls">
                    {{ coinMeta(t.instId).sym }}
                  </div>
                  <div>
                    <span class="font-headline-sm text-headline-sm font-bold text-ink-white group-hover:text-primary transition-colors">{{ coinOf(t.instId) }}</span>
                    <span class="ml-1 text-[11px] font-body-md text-steel-muted">{{ coinMeta(t.instId).name }}</span>
                  </div>
                </div>
              </td>
              <td class="px-3 text-right font-bold text-ink-white">${{ fmtPrice(t.last) }}</td>
              <td class="px-3 text-right">
                <span
                  class="inline-block px-1.5 py-0.5 rounded text-[12px] font-semibold"
                  :class="pct(t) >= 0 ? 'bg-bull-green/15 text-bull-green' : 'bg-bear-red/15 text-bear-red'"
                >{{ fmtPct(pct(t)) }}</span>
              </td>
              <td class="px-3 text-right text-steel-muted">${{ fmtPrice(t.high24h) }}</td>
              <td class="px-3 text-right text-steel-muted">${{ fmtPrice(t.low24h) }}</td>
              <td class="px-3 text-right text-ink-white">${{ fmtBig(t.volCcy24h) }}</td>
              <td class="px-3 text-right text-ink-white">--</td>
              <td class="px-4 text-center">
                <div class="w-24 h-6 inline-block align-middle">
                  <EChart v-if="sparkOption(t)" :option="sparkOption(t)" height="24px" />
                </div>
              </td>
              <td class="pr-4 pl-2 text-center">
                <button
                  class="transition-colors"
                  :class="watchlist.includes(t.instId) ? 'text-amber-warn' : 'text-steel-muted hover:text-amber-warn'"
                  title="自选"
                  @click.stop="toggleWatch(t.instId)"
                >
                  <span
                    class="material-symbols-outlined text-[16px]"
                    :style="watchlist.includes(t.instId) ? { 'font-variation-settings': `'FILL' 1` } : {}"
                  >star</span>
                </button>
              </td>
            </tr>
          </tbody>
        </table>
        <div v-if="!loading && !filtered.length" class="p-10 text-center text-steel-muted font-label-sm text-label-sm">
          {{ favOnly ? '自选还是空的, 在行情行尾点星标添加' : '无匹配币种' }}
        </div>
      </div>
      <!-- 表尾与分页条 -->
      <div class="h-11 px-4 border-t border-hairline bg-surface-slate flex flex-col sm:flex-row items-center justify-between text-steel-muted font-label-sm text-label-sm">
        <div class="flex items-center space-x-3">
          <span>显示 {{ filtered.length ? (page - 1) * pageSize + 1 : 0 }} - {{ Math.min(page * pageSize, filtered.length) }} / {{ filtered.length }} 条目</span>
          <span class="text-hairline">|</span>
          <span class="flex items-center space-x-1">
            <span class="w-1.5 h-1.5 rounded-full bg-bull-green"></span>
            <span>OKX {{ instType }} · 15S POLLING</span>
          </span>
        </div>
        <div class="flex items-center space-x-1 mt-1 sm:mt-0">
          <button
            class="w-7 h-7 rounded border border-hairline bg-card-navy flex items-center justify-center text-steel-muted hover:text-ink-white transition-colors disabled:opacity-40"
            :disabled="page <= 1"
            @click="goPage(page - 1)"
          >
            <span class="material-symbols-outlined text-[14px]">chevron_left</span>
          </button>
          <button
            v-for="n in pageNums"
            :key="n"
            class="w-7 h-7 rounded flex items-center justify-center text-[11px] transition-colors"
            :class="n === page ? 'border border-primary-container bg-primary-container/20 text-primary-container font-bold' : 'border border-hairline bg-card-navy text-steel-muted hover:text-ink-white'"
            @click="goPage(n)"
          >{{ n }}</button>
          <span v-if="totalPages > pageNums[pageNums.length - 1] + 1" class="px-1 text-steel-muted">...</span>
          <button
            v-if="totalPages > pageNums[pageNums.length - 1]"
            class="w-7 h-7 rounded border border-hairline bg-card-navy flex items-center justify-center text-steel-muted hover:text-ink-white transition-colors text-[11px]"
            @click="goPage(totalPages)"
          >{{ totalPages }}</button>
          <button
            class="w-7 h-7 rounded border border-hairline bg-card-navy flex items-center justify-center text-steel-muted hover:text-ink-white transition-colors disabled:opacity-40"
            :disabled="page >= totalPages"
            @click="goPage(page + 1)"
          >
            <span class="material-symbols-outlined text-[14px]">chevron_right</span>
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
