<script setup>
import { computed, onMounted, onBeforeUnmount, ref } from 'vue'
import { useRouter } from 'vue-router'
import { newsApi, marketApi, interactionApi } from '../api'
import { fmtAgo, fmtPct, fmtPrice, fmtUsd, ts, coinOf } from '../utils/format'

const router = useRouter()

// ---------- 分类 tabs ----------
const CATS = [
  { key: '', name: '全部', en: '' },
  { key: 'flash', name: '快讯', en: 'FLASH' },
  { key: 'news', name: '新闻', en: 'NEWS' },
  { key: 'research', name: '深度', en: 'INSIGHTS' },
  { key: 'notice', name: '公告', en: 'NOTICE' },
]
const cat = ref('')
const page = ref(1)
const pageSize = 20
const total = ref(0)
const list = ref([])
const loading = ref(true)

// 分类 -> 设计稿配色 (快讯=钴蓝 / 深度=琥珀 / 公告=红 / 新闻=绿)
const CAT_STYLE = {
  flash: { bar: 'bg-primary-container', badge: 'bg-primary-container/20 text-primary', hover: 'group-hover:text-primary' },
  research: { bar: 'bg-amber-warn', badge: 'bg-amber-warn/20 text-amber-warn', hover: 'group-hover:text-amber-warn' },
  notice: { bar: 'bg-bear-red', badge: 'bg-bear-red/20 text-bear-red', hover: 'group-hover:text-bear-red' },
  news: { bar: 'bg-bull-green', badge: 'bg-bull-green/20 text-bull-green', hover: 'group-hover:text-bull-green' },
}
const catName = { flash: '快讯', news: '新闻', research: '深度', notice: '公告' }
const catEn = { flash: 'FLASH', news: 'NEWS', research: 'INSIGHTS', notice: 'NOTICE' }
const LEGEND = [
  { key: 'flash', dot: 'bg-primary-container' },
  { key: 'research', dot: 'bg-amber-warn' },
  { key: 'notice', dot: 'bg-bear-red' },
  { key: 'news', dot: 'bg-bull-green' },
]
const styleOf = (c) => CAT_STYLE[c] || { bar: 'bg-hairline', badge: 'bg-surface-slate text-steel-muted', hover: 'group-hover:text-primary' }

async function load() {
  loading.value = true
  try {
    const res = await newsApi.list({ category: cat.value || undefined, page: page.value, page_size: pageSize })
    list.value = res.items || []
    total.value = res.total || 0
  } finally {
    loading.value = false
  }
}

function switchCat(c) {
  cat.value = c
  page.value = 1
  load()
}

const lastPage = computed(() => Math.max(1, Math.ceil(total.value / pageSize)))
const rangeText = computed(() => {
  if (!total.value) return '0-0'
  const start = (page.value - 1) * pageSize + 1
  const end = Math.min(total.value, page.value * pageSize)
  return `${start}-${end}`
})
// 分页窗口: 1 ... c-1 c c+1 ... last
const pageItems = computed(() => {
  const last = lastPage.value
  const cur = page.value
  const set = new Set([1, last, cur - 1, cur, cur + 1])
  const nums = [...set].filter((n) => n >= 1 && n <= last).sort((a, b) => a - b)
  const out = []
  let prev = 0
  for (const n of nums) {
    if (n - prev > 1) out.push('...')
    out.push(n)
    prev = n
  }
  return out
})
function goPage(p) {
  if (p < 1 || p > lastPage.value || p === page.value) return
  page.value = p
  load()
}

function openDetail(n) {
  router.push(`/news/${n.id}`)
}
function openSource(n) {
  if (n.source_url) window.open(n.source_url, '_blank', 'noopener')
  else openDetail(n)
}
async function favRow(n) {
  try {
    await interactionApi.favorite('news', n.id)
    n.favorite_count = (n.favorite_count || 0) + 1
  } catch { /* 提示省略 */ }
}

// ---------- 右栏: 24H 热榜 (现货涨幅 TOP5) ----------
const hot = ref([])
async function loadHot() {
  try {
    const res = await marketApi.tickers('SPOT')
    const rows = (res?.data || []).filter((t) => t.instId.endsWith('-USDT') && Number(t.open24h) > 0)
    hot.value = rows
      .map((t) => ({ ...t, pct: ((Number(t.last) - Number(t.open24h)) / Number(t.open24h)) * 100 }))
      .sort((a, b) => b.pct - a.pct)
      .slice(0, 5)
  } catch { hot.value = [] }
}

// ---------- 右栏: 宏观日历 ----------
const events = ref([])
async function loadEvents() {
  try {
    const res = await newsApi.macroCalendar()
    events.value = res.items || []
  } catch { events.value = [] }
}
const evDot = (imp) => (Number(imp) >= 3 ? 'bg-bear-red' : Number(imp) === 2 ? 'bg-amber-warn' : 'bg-primary-container')
const evTimeCls = (imp) => (Number(imp) >= 3 ? 'text-amber-warn' : 'text-ink-white')

// 当月日历网格 (周一开头)
const now = new Date()
const MONTHS = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC']
const monthLabel = `${MONTHS[now.getMonth()]} ${now.getFullYear()}`
const WEEK = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU']
const calCells = computed(() => {
  const y = now.getFullYear()
  const m = now.getMonth()
  const firstWd = (new Date(y, m, 1).getDay() + 6) % 7 // 周一=0
  const days = new Date(y, m + 1, 0).getDate()
  const prevDays = new Date(y, m, 0).getDate()
  const cells = []
  for (let i = firstWd - 1; i >= 0; i--) cells.push({ d: prevDays - i, dim: true })
  for (let d = 1; d <= days; d++) cells.push({ d, today: d === now.getDate(), weekend: [5, 6].includes((firstWd + d - 1) % 7) })
  let n = 1
  while (cells.length % 7 !== 0) cells.push({ d: n++, dim: true })
  return cells
})

let timer = null
onMounted(() => {
  load()
  loadHot()
  loadEvents()
  timer = setInterval(loadHot, 60000)
})
onBeforeUnmount(() => clearInterval(timer))
</script>

<template>
  <div class="flex flex-col gap-space-lg">
    <!-- ==================== 分类 TABS & 工具栏 ==================== -->
    <div class="px-8 py-2 -mx-8 -mt-8 bg-surface-slate/60 border-b border-hairline flex items-center justify-between select-none">
      <nav class="flex items-center gap-6">
        <button
          v-for="c in CATS"
          :key="c.key"
          class="relative py-2 flex items-center gap-2 font-headline-sm text-headline-sm transition-colors border-b-2 -mb-[1px]"
          :class="cat === c.key
            ? 'text-ink-white font-bold border-primary-container'
            : 'text-steel-muted hover:text-ink-white border-transparent'"
          @click="switchCat(c.key)"
        >
          <span>{{ c.name }}</span>
          <span v-if="cat === c.key" class="font-mono-data text-label-sm px-1.5 rounded-full bg-primary-container/20 text-primary border border-primary-container/30">{{ total }}</span>
          <span v-else-if="c.en" class="font-mono-data text-[10px] tracking-wider text-steel-muted/70">{{ c.en }}</span>
        </button>
      </nav>
      <div class="flex items-center gap-4 text-xs font-mono-data">
        <span class="text-steel-muted">共 <span class="text-ink-white font-bold">{{ total }}</span> 条</span>
        <button class="flex items-center gap-1.5 text-steel-muted/80 hover:text-ink-white text-[11px] transition-colors" title="刷新" @click="load">
          <span class="material-symbols-outlined text-[14px] text-bull-green" :class="{ 'animate-spin': loading }">sync</span>
          <span>刷新</span>
        </button>
      </div>
    </div>

    <!-- ==================== 主 BENTO 网格 (8:4) ==================== -->
    <main class="grid grid-cols-12 gap-6">
      <!-- 左栏: 资讯流 -->
      <section class="col-span-8 flex flex-col gap-4">
        <div class="bg-card-navy border border-hairline rounded-xl overflow-hidden shadow-2xl flex flex-col">
          <!-- 卡头 -->
          <div class="px-5 py-3 bg-surface-slate/80 border-b border-hairline flex items-center justify-between">
            <div class="flex items-center gap-2">
              <span class="font-headline-sm text-headline-sm text-ink-white font-bold tracking-tight">机构级即时情报流</span>
              <span class="font-mono-data text-label-sm text-primary px-2 py-0.5 rounded bg-primary-container/15 border border-primary-container/20">LIVE WIRE</span>
            </div>
            <div class="flex items-center gap-3 text-steel-muted text-xs font-mono-data">
              <span v-for="l in LEGEND" :key="l.key" class="flex items-center gap-1">
                <span class="w-2 h-2 rounded-full" :class="l.dot"></span> {{ catName[l.key] }}
              </span>
            </div>
          </div>
          <!-- 列表 -->
          <div v-if="loading" class="px-5 py-10 text-center text-steel-muted font-mono-data text-xs">加载中…</div>
          <div v-else-if="!list.length" class="px-5 py-10 text-center text-steel-muted font-mono-data text-xs">暂无资讯</div>
          <div v-else class="divide-y divide-hairline">
            <article
              v-for="n in list"
              :key="n.id"
              class="group relative flex transition-colors duration-150 hover:bg-card-navy-high cursor-pointer"
              @click="openDetail(n)"
            >
              <div class="w-2 flex-shrink-0" :class="styleOf(n.category).bar"></div>
              <div class="flex-1 px-4 py-3 flex flex-col justify-between">
                <div class="flex items-center justify-between gap-4 mb-1">
                  <div class="flex items-center gap-2 min-w-0">
                    <span class="font-mono-data text-label-sm px-1.5 py-0.5 rounded font-bold whitespace-nowrap" :class="styleOf(n.category).badge">
                      {{ catName[n.category] || n.category }} {{ catEn[n.category] || '' }}
                    </span>
                    <h2 class="font-headline-sm text-headline-sm text-ink-white font-bold transition-colors truncate" :class="styleOf(n.category).hover">
                      {{ n.title }}
                    </h2>
                  </div>
                  <div class="flex items-center gap-1.5 opacity-0 group-hover:opacity-100 transition-opacity flex-shrink-0">
                    <button class="p-1 rounded hover:bg-surface-slate text-steel-muted hover:text-ink-white" title="收藏" @click.stop="favRow(n)">
                      <span class="material-symbols-outlined text-[16px]">bookmark</span>
                    </button>
                    <button class="p-1 rounded hover:bg-surface-slate text-steel-muted hover:text-ink-white" title="原文链接" @click.stop="openSource(n)">
                      <span class="material-symbols-outlined text-[16px] text-primary">open_in_new</span>
                    </button>
                  </div>
                </div>
                <p v-if="n.summary" class="text-steel-muted text-[13px] line-clamp-1 font-body-md pr-12">{{ n.summary }}</p>
                <div class="flex items-center justify-between mt-2 pt-1 border-t border-hairline/40 text-[11px] font-mono-data text-steel-muted">
                  <div class="flex items-center gap-3">
                    <span class="text-ink-white font-medium">{{ n.source || '快讯' }}</span>
                    <span>·</span>
                    <span class="text-steel-muted font-mono-data">{{ fmtAgo(ts(n.publish_at)) }}</span>
                  </div>
                  <div class="flex items-center gap-3">
                    <span v-if="n.like_count" class="text-steel-muted">赞 {{ n.like_count }}</span>
                    <span v-if="n.comment_count" class="text-steel-muted">评论 {{ n.comment_count }}</span>
                    <span v-if="n.favorite_count" class="text-primary">收藏 {{ n.favorite_count }}</span>
                  </div>
                </div>
              </div>
            </article>
          </div>
          <!-- 分页 -->
          <div class="px-5 py-3 bg-surface-slate/80 border-t border-hairline flex items-center justify-between font-mono-data text-xs">
            <div class="flex items-center gap-2 text-steel-muted">
              <span>显示第 <span class="text-ink-white font-bold">{{ rangeText }}</span> 条 / 共 <span class="text-ink-white font-bold">{{ total }}</span> 条</span>
            </div>
            <div class="flex items-center gap-1">
              <button
                class="px-2.5 py-1 rounded bg-surface-slate border border-hairline text-steel-muted hover:text-ink-white hover:border-primary-container transition-all flex items-center disabled:opacity-40"
                :disabled="page <= 1"
                @click="goPage(page - 1)"
              >
                <span class="material-symbols-outlined text-[16px]">chevron_left</span>
              </button>
              <template v-for="(p, i) in pageItems" :key="i">
                <span v-if="p === '...'" class="px-1 text-steel-muted">...</span>
                <button
                  v-else
                  class="px-3 py-1 rounded transition-all"
                  :class="p === page
                    ? 'bg-primary-container text-ink-white font-bold'
                    : 'bg-card-navy border border-hairline text-steel-muted hover:text-ink-white'"
                  @click="goPage(p)"
                >{{ p }}</button>
              </template>
              <button
                class="px-2.5 py-1 rounded bg-surface-slate border border-hairline text-steel-muted hover:text-ink-white hover:border-primary-container transition-all flex items-center disabled:opacity-40"
                :disabled="page >= lastPage"
                @click="goPage(page + 1)"
              >
                <span class="material-symbols-outlined text-[16px]">chevron_right</span>
              </button>
            </div>
          </div>
        </div>
      </section>

      <!-- 右栏 -->
      <section class="col-span-4 flex flex-col gap-5">
        <!-- 卡 1: 24H 涨幅热榜 -->
        <div class="bg-card-navy border border-hairline rounded-xl overflow-hidden shadow-xl flex flex-col">
          <div class="px-4 py-3 bg-surface-slate/90 border-b border-hairline flex items-center justify-between">
            <div class="flex items-center gap-2">
              <span class="material-symbols-outlined text-primary text-[18px]">local_fire_department</span>
              <h3 class="font-headline-sm text-headline-sm text-ink-white font-bold tracking-tight">24H 热榜 TOP GAINERS</h3>
            </div>
            <span class="font-mono-data text-[11px] text-steel-muted">1m 刷新</span>
          </div>
          <div class="p-3 flex flex-col gap-2">
            <div v-if="!hot.length" class="py-6 text-center text-steel-muted font-mono-data text-[11px]">暂无数据</div>
            <div
              v-for="(t, i) in hot"
              :key="t.instId"
              class="p-2.5 rounded-lg bg-surface-slate/70 border border-hairline/80 hover:bg-card-navy-high transition-colors flex items-start gap-3 group cursor-pointer"
              @click="router.push(`/market/${t.instId}`)"
            >
              <span class="font-mono-data text-headline-md font-bold text-primary w-6 text-center leading-none mt-0.5">{{ String(i + 1).padStart(2, '0') }}</span>
              <div class="flex-1 min-w-0">
                <div class="flex items-center justify-between mb-1">
                  <div class="flex items-center gap-1.5">
                    <span class="px-1.5 rounded bg-card-navy border border-hairline text-[10px] font-mono-data font-semibold text-ink-white">{{ coinOf(t.instId) }}</span>
                    <span class="font-mono-data text-[11px] font-bold" :class="t.pct >= 0 ? 'text-bull-green' : 'text-bear-red'">{{ fmtPct(t.pct) }}</span>
                  </div>
                  <span class="font-mono-data text-[10px] text-ink-white font-semibold">{{ fmtPrice(t.last) }}</span>
                </div>
                <h4 class="font-body-md text-ink-white text-xs font-semibold leading-snug group-hover:text-primary transition-colors truncate">
                  {{ t.instId }} 永续/现货
                </h4>
                <div class="flex items-center justify-between mt-1 text-[10px] font-mono-data text-steel-muted">
                  <span>24H 成交额 {{ fmtUsd(t.volCcy24h) }}</span>
                  <span>24H 高 {{ fmtPrice(t.high24h) }}</span>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- 卡 2: 宏观日历 -->
        <div class="bg-card-navy border border-hairline rounded-xl overflow-hidden shadow-xl flex flex-col">
          <div class="px-4 py-3 bg-surface-slate/90 border-b border-hairline flex items-center justify-between">
            <div class="flex items-center gap-2">
              <span class="material-symbols-outlined text-primary text-[18px]">calendar_month</span>
              <h3 class="font-headline-sm text-headline-sm text-ink-white font-bold tracking-tight">EVENT CALENDAR</h3>
            </div>
            <span class="font-mono-data text-xs text-ink-white font-bold px-1">{{ monthLabel }}</span>
          </div>
          <div class="p-4 flex flex-col gap-3">
            <div class="grid grid-cols-7 gap-1 text-center font-mono-data text-[11px]">
              <span v-for="w in WEEK" :key="w" class="text-steel-muted py-1 font-semibold">{{ w }}</span>
              <template v-for="(c, i) in calCells" :key="i">
                <div v-if="c.today" class="py-1 rounded bg-primary-container text-ink-white font-bold flex flex-col items-center justify-center shadow-lg shadow-primary-container/30">
                  <span>{{ String(c.d).padStart(2, '0') }}</span>
                  <span class="w-1 h-1 rounded-full bg-ink-white mt-0.5"></span>
                </div>
                <span v-else class="py-1.5" :class="c.dim ? 'text-steel-muted/30' : c.weekend ? 'text-steel-muted/80' : 'text-ink-white'">
                  {{ String(c.d).padStart(2, '0') }}
                </span>
              </template>
            </div>
            <!-- 今日事件 -->
            <div class="mt-2 pt-3 border-t border-hairline flex flex-col gap-2">
              <div class="flex items-center justify-between text-[11px] font-mono-data">
                <span class="text-steel-muted font-medium">今日关键事件</span>
                <span class="text-primary font-bold">{{ events.length }} 项</span>
              </div>
              <div v-if="!events.length" class="py-3 text-center text-steel-muted font-mono-data text-[11px]">今日暂无宏观事件</div>
              <div
                v-for="e in events"
                :key="e.id"
                class="p-2 rounded bg-surface-slate/80 border border-hairline/70 flex items-start justify-between gap-2"
              >
                <div class="flex items-start gap-2 min-w-0">
                  <span class="w-1.5 h-1.5 rounded-full mt-1.5 flex-shrink-0" :class="evDot(e.importance)"></span>
                  <div class="flex flex-col min-w-0">
                    <span class="font-body-md text-xs font-semibold text-ink-white truncate">{{ e.name }}</span>
                    <span class="font-mono-data text-[10px] text-steel-muted">
                      {{ e.country || e.currency }}<template v-if="e.forecast !== null && e.forecast !== undefined"> · 预期 {{ e.forecast }}{{ e.unit || '' }}</template>
                    </span>
                  </div>
                </div>
                <span class="font-mono-data text-[11px] font-bold flex-shrink-0" :class="evTimeCls(e.importance)">{{ e.event_at }}</span>
              </div>
            </div>
          </div>
        </div>
      </section>
    </main>
  </div>
</template>
