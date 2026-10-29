<script setup>
import { onMounted, ref, computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { newsApi, interactionApi, overviewApi, marketApi } from '../api'
import { fmtDateTime, fmtAgo, fmtPct, fmtPrice, fmtUsd, ts } from '../utils/format'
import EChart from '../components/EChart.vue'

const route = useRoute()
const router = useRouter()
const article = ref(null)
const related = ref([])
const sentiment = ref(null)
const loading = ref(true)
const liked = ref(false)
const faved = ref(false)
const comments = ref([])
const commentsErr = ref('')
const commentText = ref('')
const commentSending = ref(false)
const commentMsg = ref('')

const catName = { flash: '快讯', news: '新闻', research: '深度研报', notice: '公告' }

const sentLabel = computed(() => {
  const v = sentiment.value
  if (v == null) return '--'
  if (v >= 75) return 'EXTREME GREED / 极度贪婪'
  if (v >= 50) return 'GREED / 贪婪'
  if (v >= 25) return 'FEAR / 恐慌'
  return 'EXTREME FEAR / 极度恐慌'
})
const sentColor = computed(() =>
  sentiment.value == null ? 'text-steel-muted' : sentiment.value >= 50 ? 'text-bull-green' : sentiment.value >= 25 ? 'text-amber-warn' : 'text-bear-red'
)

const gaugeOption = computed(() => ({
  series: [{
    type: 'gauge',
    startAngle: 200, endAngle: -20, min: 0, max: 100, radius: '100%', center: ['50%', '64%'],
    axisLine: { lineStyle: { width: 8, color: [[0.25, '#FF5F6D'], [0.5, '#F7B733'], [0.75, '#2E5CFF'], [1, '#00E388']] } },
    pointer: { length: '55%', width: 3, itemStyle: { color: '#F0F0FF' } },
    axisTick: { show: false }, splitLine: { show: false }, axisLabel: { show: false },
    detail: { formatter: '{value}', color: '#F0F0FF', fontSize: 22, fontFamily: 'JetBrains Mono', offsetCenter: [0, '35%'] },
    data: [{ value: sentiment.value ?? 0 }],
  }],
}))

// 简单 markdown 段落渲染: 按空行分段, 去 markdown 标记
const paragraphs = computed(() => {
  const c = article.value?.content || ''
  return c
    .split(/\n{2,}/)
    .map((p) => p.replace(/[#*>`]/g, '').trim())
    .filter(Boolean)
})

// 预估阅读用时 (~400 字/分钟)
const readMinutes = computed(() => Math.max(1, Math.round((article.value?.content || '').length / 400)))

// 从正文提取高关联标的
const relatedCoins = computed(() => {
  const text = `${article.value?.title || ''} ${article.value?.summary || ''} ${article.value?.content || ''}`
  const found = text.match(/\b(BTC|ETH|SOL|BNB|XRP|DOGE|ADA|SUI|OKB|LTC)\b/gi) || []
  return [...new Set(found.map((s) => s.toUpperCase()))].slice(0, 3)
})

const sentiText = computed(() => {
  const s = article.value?.sentiment
  return s === 'positive' ? '偏多' : s === 'negative' ? '偏空' : s ? '中性' : '--'
})

// ---------- 关联资产雷达 (BTC/ETH 实时行情 + 1H 走势) ----------
const assets = ref([])
function sparkPoints(candles) {
  // OKX candles: 倒序 [ts, o, h, l, c, ...]
  const closes = (candles || []).map((c) => Number(c[4])).filter((n) => !isNaN(n)).reverse()
  if (closes.length < 2) return ''
  const min = Math.min(...closes)
  const max = Math.max(...closes)
  const span = max - min || 1
  return closes
    .map((v, i) => `${((i / (closes.length - 1)) * 60).toFixed(1)},${(14 - ((v - min) / span) * 12).toFixed(1)}`)
    .join(' ')
}
async function loadAssets() {
  const defs = [
    { inst: 'BTC-USDT', icon: '₿', iconCls: 'bg-amber-warn/10 text-amber-warn border-amber-warn/30' },
    { inst: 'ETH-USDT', icon: 'Ξ', iconCls: 'bg-primary/10 text-primary border-primary/30' },
  ]
  const out = []
  for (const d of defs) {
    try {
      const [t, cd] = await Promise.all([
        marketApi.ticker(d.inst),
        marketApi.candles(d.inst, '1H', 24).catch(() => null),
      ])
      const tk = t?.data?.[0] || t?.data || {}
      const open = Number(tk.open24h)
      const pct = open ? ((Number(tk.last) - open) / open) * 100 : null
      out.push({
        ...d,
        price: tk.last,
        pct,
        vol: tk.volCcy24h,
        points: sparkPoints(cd?.data),
      })
    } catch { /* 单个失败忽略 */ }
  }
  assets.value = out
}
const totalVol = computed(() => assets.value.reduce((s, a) => s + Number(a.vol || 0), 0))

async function loadInteraction(id) {
  liked.value = false
  faved.value = false
  comments.value = []
  commentMsg.value = ''
  try {
    const st = await interactionApi.state('news', [id])
    const entry = Array.isArray(st)
      ? st.find((x) => String(x.target_id ?? x.id) === String(id))
      : (st?.[id] || st?.[String(id)] || st?.items?.[id] || null)
    if (entry) {
      liked.value = !!(entry.liked ?? entry.is_liked)
      faved.value = !!(entry.favorited ?? entry.faved ?? entry.is_favorite)
    }
  } catch { /* 状态拉取失败静默 */ }
  try {
    const res = await interactionApi.comments('news', id)
    comments.value = res?.items || res?.data || (Array.isArray(res) ? res : [])
    commentsErr.value = ''
  } catch (e) {
    commentsErr.value = e?.message || '评论加载失败'
  }
}

async function submitComment() {
  const content = commentText.value.trim()
  if (!content || commentSending.value) return
  commentSending.value = true
  commentMsg.value = ''
  try {
    const c = await interactionApi.addComment({ target_type: 'news', target_id: article.value.id, content })
    comments.value.unshift(c?.id ? c : {
      id: `local-${Date.now()}`,
      content,
      nickname: '我',
      username: '我',
      created_at: Date.now(),
    })
    commentText.value = ''
  } catch (e) {
    commentMsg.value = e?.message || '评论提交失败'
  } finally {
    commentSending.value = false
  }
}

async function load() {
  loading.value = true
  try {
    const id = route.params.id
    article.value = await newsApi.detail(id)
    loadInteraction(id)
    const rel = await newsApi.list({ category: article.value.category, page_size: 5 }).catch(() => null)
    if (rel) related.value = (rel.items || []).filter((n) => String(n.id) !== String(id)).slice(0, 4)
    const s = await overviewApi.sentiment().catch(() => null)
    if (s) sentiment.value = s.fear_greed ?? null
    loadAssets()
  } finally {
    loading.value = false
  }
}

async function toggleLike() {
  try {
    await interactionApi.like('news', article.value.id)
    liked.value = !liked.value
    article.value.like_count += liked.value ? 1 : -1
  } catch { /* 提示省略 */ }
}
async function toggleFav() {
  try {
    await interactionApi.favorite('news', article.value.id)
    faved.value = !faved.value
    article.value.favorite_count += faved.value ? 1 : -1
  } catch { /* 提示省略 */ }
}
function copyCitation() {
  const text = `${article.value?.title || ''}\n${location.href}`
  navigator.clipboard?.writeText(text).catch(() => {})
}
function openSource() {
  if (article.value?.source_url) window.open(article.value.source_url, '_blank', 'noopener')
}

onMounted(load)
</script>

<template>
  <div class="flex flex-col gap-space-lg">
    <div v-if="loading" class="py-16 text-center text-steel-muted font-mono-data text-xs">加载中…</div>
    <div v-else-if="!article" class="py-16 text-center text-steel-muted font-mono-data text-xs">资讯不存在</div>

    <!-- ==================== 双栏布局 ==================== -->
    <main v-else class="grid grid-cols-12 gap-6 items-start">
      <!-- 左栏: 文章详情 -->
      <article class="col-span-12 lg:col-span-8 bg-card-navy border border-hairline rounded-xl p-6 lg:p-8 flex flex-col gap-6 shadow-none">
        <!-- 头部徽标 -->
        <div class="flex flex-col gap-4 border-b border-hairline pb-5">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <div class="flex items-center gap-2.5 flex-wrap">
              <!-- 来源胶囊 -->
              <span class="px-2.5 py-0.5 rounded-full bg-primary-container/15 border border-primary-container/30 text-primary font-label-sm text-label-sm tracking-wide inline-flex items-center gap-1.5">
                <span class="w-1.5 h-1.5 rounded-full bg-primary-container"></span>
                {{ article.source || '快讯' }}
              </span>
              <!-- 分类标签 -->
              <span class="px-2 py-0.5 rounded bg-surface-slate border border-hairline text-steel-muted font-label-sm text-label-sm uppercase">
                {{ catName[article.category] || article.category }}
              </span>
              <!-- 发布时间 -->
              <span class="font-mono-data text-mono-data text-steel-muted flex items-center gap-1">
                <span class="material-symbols-outlined" style="font-size: 14px;">schedule</span>
                {{ fmtDateTime(ts(article.publish_at)) }} · {{ fmtAgo(ts(article.publish_at)) }}
              </span>
            </div>
            <!-- 快捷操作 -->
            <div class="flex items-center gap-1">
              <button class="p-1.5 rounded hover:bg-card-navy-high transition-colors" :class="faved ? 'text-primary' : 'text-steel-muted hover:text-ink-white'" title="收藏" @click="toggleFav">
                <span class="material-symbols-outlined">bookmark</span>
              </button>
              <button class="p-1.5 rounded hover:bg-card-navy-high text-steel-muted hover:text-ink-white transition-colors" title="复制链接" @click="copyCitation">
                <span class="material-symbols-outlined">share</span>
              </button>
              <button v-if="article.source_url" class="p-1.5 rounded hover:bg-card-navy-high text-steel-muted hover:text-ink-white transition-colors" title="原网页链接" @click="openSource">
                <span class="material-symbols-outlined">open_in_new</span>
              </button>
            </div>
          </div>
          <!-- 标题 -->
          <h1 class="font-headline-lg text-headline-lg text-ink-white tracking-tight leading-snug">
            {{ article.title }}
          </h1>
          <!-- 元信息条 -->
          <div class="grid grid-cols-2 sm:grid-cols-3 gap-3 p-3 rounded-lg bg-surface-slate/80 border border-hairline">
            <div class="flex flex-col">
              <span class="text-label-sm font-label-sm text-steel-muted uppercase">来源 / 发布机构</span>
              <span class="font-mono-data text-mono-data text-ink-white font-medium flex items-center gap-1.5 mt-0.5">
                <span class="material-symbols-outlined text-primary" style="font-size: 14px;">verified</span>
                {{ article.source || 'MINGCE' }}
              </span>
            </div>
            <div class="flex flex-col">
              <span class="text-label-sm font-label-sm text-steel-muted uppercase">预估阅读用时</span>
              <span class="font-mono-data text-mono-data text-ink-white font-medium flex items-center gap-1.5 mt-0.5">
                <span class="material-symbols-outlined text-steel-muted" style="font-size: 14px;">hourglass_top</span>
                {{ readMinutes }} min · {{ (article.content || '').length }} 字
              </span>
            </div>
            <div class="flex flex-col col-span-2 sm:col-span-1">
              <span class="text-label-sm font-label-sm text-steel-muted uppercase">高关联标的资产</span>
              <div class="flex items-center gap-1.5 mt-0.5">
                <span v-if="!relatedCoins.length" class="font-mono-data text-mono-data text-steel-muted">--</span>
                <span v-for="c in relatedCoins" :key="c" class="px-1.5 py-0.5 rounded bg-card-navy text-primary font-mono-data text-label-sm border border-hairline">{{ c }}</span>
              </div>
            </div>
          </div>
        </div>

        <!-- 正文 -->
        <div class="flex flex-col gap-5 text-on-surface">
          <!-- 摘要高亮引用块 -->
          <blockquote v-if="article.summary" class="bg-card-navy-high border-l-4 border-primary-container p-4 rounded-r-lg my-2">
            <div class="flex items-start gap-3">
              <span class="material-symbols-outlined text-primary-container shrink-0 mt-0.5">format_quote</span>
              <div class="flex flex-col gap-1">
                <p class="font-body-lg text-ink-white font-medium italic leading-relaxed">{{ article.summary }}</p>
                <div class="flex items-center gap-2 mt-1">
                  <span class="text-label-sm font-label-sm text-primary font-semibold">— {{ article.source || 'MINGCE' }}</span>
                  <span class="text-label-sm font-label-sm text-steel-muted">情绪倾向: {{ sentiText }}</span>
                </div>
              </div>
            </div>
          </blockquote>
          <p v-for="(p, i) in paragraphs" :key="i" class="font-body-lg text-body-lg text-on-surface leading-relaxed text-justify">
            {{ p }}
          </p>
        </div>

        <!-- 底部标签 & 互动栏 -->
        <div class="border-t border-hairline pt-5 flex flex-wrap items-center justify-between gap-4 mt-2">
          <div class="flex items-center gap-2">
            <span class="px-2.5 py-1 rounded bg-surface-slate border border-hairline text-steel-muted font-label-sm text-label-sm">
              #{{ catName[article.category] || article.category }}
            </span>
            <span v-if="article.source" class="px-2.5 py-1 rounded bg-surface-slate border border-hairline text-steel-muted font-label-sm text-label-sm">
              #{{ article.source }}
            </span>
          </div>
          <div class="flex items-center gap-2">
            <button
              class="flex items-center gap-1.5 px-3 py-1.5 rounded-lg border font-label-sm text-label-sm transition-colors"
              :class="liked
                ? 'bg-bull-green/15 border-bull-green/40 text-bull-green'
                : 'bg-surface-slate hover:bg-card-navy-high border-hairline text-steel-muted hover:text-ink-white'"
              @click="toggleLike"
            >
              <span class="material-symbols-outlined" style="font-size: 16px;">thumb_up</span>
              <span>赞同 ({{ article.like_count ?? 0 }})</span>
            </button>
            <button
              class="flex items-center gap-1.5 px-3 py-1.5 rounded-lg border font-label-sm text-label-sm transition-colors"
              :class="faved
                ? 'bg-primary-container/20 border-primary-container/40 text-primary'
                : 'bg-surface-slate hover:bg-card-navy-high border-hairline text-steel-muted hover:text-ink-white'"
              @click="toggleFav"
            >
              <span class="material-symbols-outlined" style="font-size: 16px;">bookmark</span>
              <span>{{ faved ? '已收藏' : '收藏' }} ({{ article.favorite_count ?? 0 }})</span>
            </button>
            <button
              v-if="article.source_url"
              class="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-primary-container/20 border border-primary-container/40 text-primary hover:bg-primary-container/30 font-label-sm text-label-sm transition-colors"
              @click="openSource"
            >
              <span class="material-symbols-outlined" style="font-size: 16px;">open_in_new</span>
              <span>查看原文</span>
            </button>
          </div>
        </div>

        <!-- 评论区 -->
        <div class="border-t border-hairline pt-5 flex flex-col gap-4">
          <div class="flex items-center gap-2">
            <span class="material-symbols-outlined text-primary">forum</span>
            <span class="font-headline-sm text-headline-sm text-ink-white">评论 COMMENTS</span>
            <span class="font-mono-data text-label-sm text-steel-muted">({{ comments.length }})</span>
          </div>
          <!-- 提交框 -->
          <div class="flex flex-col gap-2">
            <textarea
              v-model="commentText"
              rows="2"
              maxlength="500"
              placeholder="写下你的看法…"
              class="w-full bg-surface-slate border border-hairline rounded-lg text-ink-white placeholder-steel-muted/60 text-body-md font-body-md px-3 py-2 focus:border-primary-container focus:ring-1 focus:ring-primary-container focus:outline-none transition-all resize-none"
            ></textarea>
            <div class="flex items-center justify-between">
              <span v-if="commentMsg" class="font-body-md text-[12px] text-bear-red flex items-center gap-1">
                <span class="material-symbols-outlined text-[14px]">error</span>
                {{ commentMsg }}
              </span>
              <span v-else class="font-mono-data text-[10px] text-steel-muted">{{ commentText.length }}/500</span>
              <button
                class="px-4 py-1.5 rounded-lg bg-primary-container text-ink-white hover:bg-primary-container/90 transition-all font-body-md text-body-md font-medium flex items-center gap-1.5 disabled:opacity-60 disabled:cursor-not-allowed"
                :disabled="commentSending || !commentText.trim()"
                @click="submitComment"
              >
                <span v-if="commentSending" class="material-symbols-outlined text-[15px] animate-spin">progress_activity</span>
                {{ commentSending ? '提交中…' : '发布评论' }}
              </button>
            </div>
          </div>
          <!-- 列表 -->
          <div v-if="commentsErr" class="py-4 text-center text-bear-red font-mono-data text-[11px]">{{ commentsErr }}</div>
          <div v-else-if="!comments.length" class="py-4 text-center text-steel-muted font-mono-data text-[11px]">暂无评论, 来抢沙发</div>
          <div v-else class="flex flex-col divide-y divide-hairline">
            <div v-for="c in comments" :key="c.id" class="py-3 first:pt-0 last:pb-0 flex gap-2.5">
              <div class="w-7 h-7 shrink-0 rounded bg-card-navy-high border border-hairline flex items-center justify-center font-mono-data text-[11px] text-primary-fixed-dim font-bold">
                {{ (c.nickname || c.username || 'U')[0].toUpperCase() }}
              </div>
              <div class="flex flex-col gap-0.5 min-w-0">
                <div class="flex items-center gap-2">
                  <span class="font-label-sm text-label-sm text-ink-white font-medium">{{ c.nickname || c.username || '用户' }}</span>
                  <span class="font-mono-data text-[10px] text-steel-muted">{{ fmtAgo(ts(c.created_at)) }}</span>
                </div>
                <p class="font-body-md text-body-md text-on-surface leading-snug break-words">{{ c.content }}</p>
              </div>
            </div>
          </div>
        </div>
      </article>

      <!-- 右栏: 情报侧栏 -->
      <div class="col-span-12 lg:col-span-4 flex flex-col gap-6 self-start sticky top-[88px]">
        <!-- 卡 1: 情绪指标 -->
        <div class="bg-card-navy border border-hairline rounded-xl p-5 flex flex-col gap-4">
          <div class="flex items-center justify-between border-b border-hairline pb-3">
            <div class="flex items-center gap-2">
              <span class="material-symbols-outlined text-bull-green">speed</span>
              <span class="font-headline-sm text-headline-sm text-ink-white">市场情绪指标 MARKET SENTIMENT</span>
            </div>
            <span class="font-mono-data text-label-sm text-bull-green bg-bull-green/10 border border-bull-green/30 px-2 py-0.5 rounded uppercase">LIVE</span>
          </div>
          <div class="flex flex-col items-center py-2">
            <EChart :option="gaugeOption" height="130px" />
            <div class="flex flex-col items-center mt-1">
              <div class="flex items-baseline gap-1.5">
                <span class="font-mono-data text-3xl font-bold tracking-tight" :class="sentColor">{{ sentiment ?? '--' }}</span>
                <span class="font-headline-sm text-headline-sm font-bold tracking-wide" :class="sentColor">{{ sentLabel }}</span>
              </div>
              <div class="flex justify-between w-48 text-[10px] font-mono-data text-steel-muted mt-2 px-1">
                <span>0 极度恐慌</span>
                <span>50 中性</span>
                <span>100 极度贪婪</span>
              </div>
            </div>
          </div>
        </div>

        <!-- 卡 2: 相关阅读 -->
        <div class="bg-card-navy border border-hairline rounded-xl p-5 flex flex-col gap-3">
          <div class="flex items-center justify-between border-b border-hairline pb-3">
            <div class="flex items-center gap-2">
              <span class="material-symbols-outlined text-primary">feed</span>
              <span class="font-headline-sm text-headline-sm text-ink-white">相关阅读 RELATED BRIEFINGS</span>
            </div>
            <a class="font-label-sm text-label-sm text-primary hover:underline cursor-pointer" @click="router.push('/news')">查看全部</a>
          </div>
          <div v-if="!related.length" class="py-4 text-center text-steel-muted font-mono-data text-[11px]">暂无相关</div>
          <div v-else class="flex flex-col divide-y divide-hairline">
            <a
              v-for="r in related"
              :key="r.id"
              class="py-2.5 first:pt-0 last:pb-0 group block transition-colors cursor-pointer"
              @click="router.push(`/news/${r.id}`).then(load)"
            >
              <div class="flex items-center gap-2 mb-1">
                <span class="px-1.5 rounded bg-surface-slate border border-hairline text-steel-muted font-mono-data text-[10px]">#{{ catName[r.category] || r.category }}</span>
                <span class="font-mono-data text-label-sm text-steel-muted">{{ fmtAgo(ts(r.publish_at)) }}</span>
              </div>
              <p class="font-body-md text-body-md text-on-surface group-hover:text-primary transition-colors line-clamp-2 leading-snug">
                {{ r.title }}
              </p>
            </a>
          </div>
        </div>

        <!-- 卡 3: 关联资产雷达 -->
        <div class="bg-card-navy border border-hairline rounded-xl p-5 flex flex-col gap-3">
          <div class="flex items-center justify-between border-b border-hairline pb-3">
            <div class="flex items-center gap-2">
              <span class="material-symbols-outlined text-primary">radar</span>
              <span class="font-headline-sm text-headline-sm text-ink-white">关联资产异动 RELATED ASSET RADAR</span>
            </div>
            <span class="text-label-sm font-label-sm text-steel-muted">REAL-TIME</span>
          </div>
          <div v-if="!assets.length" class="py-4 text-center text-steel-muted font-mono-data text-[11px]">加载中…</div>
          <div
            v-for="a in assets"
            :key="a.inst"
            class="p-3 rounded-lg bg-surface-slate border border-hairline flex items-center justify-between hover:border-primary-container transition-colors cursor-pointer"
            @click="router.push(`/market/${a.inst}`)"
          >
            <div class="flex items-center gap-3">
              <div class="w-8 h-8 rounded border flex items-center justify-center font-bold font-mono-data text-xs" :class="a.iconCls">
                {{ a.icon }}
              </div>
              <div class="flex flex-col">
                <div class="flex items-center gap-1.5">
                  <span class="font-headline-sm text-headline-sm text-ink-white font-bold">{{ a.inst.replace('-', '/') }}</span>
                  <span class="text-[10px] font-label-sm text-steel-muted bg-card-navy px-1 rounded">OKX</span>
                </div>
                <span class="font-mono-data text-mono-data text-ink-white font-semibold">${{ fmtPrice(a.price) }}</span>
              </div>
            </div>
            <div class="flex flex-col items-end">
              <span class="font-mono-data text-mono-data font-bold flex items-center gap-0.5" :class="(a.pct ?? 0) >= 0 ? 'text-bull-green' : 'text-bear-red'">
                <span class="material-symbols-outlined" style="font-size: 14px;">{{ (a.pct ?? 0) >= 0 ? 'arrow_drop_up' : 'arrow_drop_down' }}</span>
                {{ fmtPct(a.pct) }}
              </span>
              <svg v-if="a.points" class="w-16 h-4 fill-none mt-1" :class="(a.pct ?? 0) >= 0 ? 'stroke-bull-green' : 'stroke-bear-red'" viewBox="0 0 60 16">
                <polyline :points="a.points" stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5"></polyline>
              </svg>
            </div>
          </div>
          <div class="flex items-center justify-between pt-1 text-label-sm font-label-sm text-steel-muted">
            <span class="flex items-center gap-1">
              <span class="w-1.5 h-1.5 rounded-full bg-bull-green"></span>
              FEED ACTIVE
            </span>
            <span>24H VOL {{ fmtUsd(totalVol) }}</span>
          </div>
        </div>
      </div>
    </main>
  </div>
</template>
