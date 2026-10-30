<script setup>
import { computed, onMounted, onBeforeUnmount, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useUserStore } from '../store/user'
import { newsApi } from '../api'
import { fmtAgo, ts } from '../utils/format'

const route = useRoute()
const router = useRouter()
const store = useUserStore()
const keyword = ref('')

const navs = [
  { path: '/overview', name: '概览', en: 'OVERVIEW', icon: 'dashboard' },
  { path: '/market', name: '行情', en: 'MARKET', icon: 'candlestick_chart' },
  { path: '/multi', name: '多维数据', en: 'MULTI-DIM', icon: 'query_stats' },
  { path: '/liquidation', name: '爆仓监控', en: 'LIQUIDATION', icon: 'crisis_alert', alert: true },
  { path: '/whale', name: '巨鲸动向', en: 'WHALE', icon: 'visibility' },
  { path: '/funding', name: '资金费率', en: 'FUNDING', icon: 'percent' },
  { path: '/news', name: '资讯', en: 'NEWS', icon: 'newspaper' },
  { path: '/chat', name: '聊天', en: 'CHAT', icon: 'chat' },
  { path: '/invite', name: '邀请', en: 'INVITE', icon: 'card_giftcard' },
  { path: '/team', name: '团队', en: 'TEAM', icon: 'groups' },
  { path: '/assets', name: '资产理财', en: 'ASSETS', icon: 'account_balance_wallet' },
  { path: '/profile', name: '我的', en: 'PROFILE', icon: 'person' },
]

const active = computed(() => {
  const p = route.path
  if (p.startsWith('/market')) return '/market'
  if (p.startsWith('/news')) return '/news'
  return p
})

const pageEn = computed(() => navs.find((n) => n.path === active.value)?.en || 'TERMINAL')
const avatarText = computed(() => (store.user?.username || 'M').slice(0, 2).toUpperCase())

function onSearch() {
  const kw = keyword.value.trim().toUpperCase()
  if (!kw) return
  const inst = kw.includes('-') || kw.endsWith('USDT') ? kw : `${kw}-USDT`
  router.push(`/market/${encodeURIComponent(inst)}`)
  keyword.value = ''
}

function logout() {
  store.logout()
  router.push('/login')
}

// ---------- 通知待办下拉 ----------
const notifOpen = ref(false)
const notifLoading = ref(false)
const notifErr = ref('')
const notices = ref([])

async function toggleNotif() {
  notifOpen.value = !notifOpen.value
  if (notifOpen.value && !notices.value.length) loadNotices()
}

async function loadNotices() {
  notifLoading.value = true
  notifErr.value = ''
  try {
    const res = await newsApi.list({ limit: 6 })
    notices.value = res?.items || res?.data || []
  } catch (e) {
    notifErr.value = e?.message || '通知加载失败'
  } finally {
    notifLoading.value = false
  }
}

function openNotice(n) {
  notifOpen.value = false
  router.push(`/news/${n.id}`)
}

function goAllNews() {
  notifOpen.value = false
  router.push('/news')
}

function onDocClick(e) {
  if (!notifOpen.value) return
  if (!e.target.closest?.('[data-notif]')) notifOpen.value = false
}
onMounted(() => document.addEventListener('click', onDocClick))
onBeforeUnmount(() => document.removeEventListener('click', onDocClick))
</script>

<template>
  <div class="bg-canvas-obsidian text-ink-white font-body-md text-body-md min-h-screen">
    <!-- ===== SideNavBar (设计稿还原) ===== -->
    <aside class="fixed top-0 left-0 h-screen w-60 z-40 bg-surface-slate flex flex-col justify-between px-3 py-5 border-r border-hairline">
      <div class="flex flex-col gap-5">
        <!-- Logo -->
        <div class="px-2 py-2 flex items-center justify-between border-b border-hairline pb-4 cursor-pointer" @click="router.push('/overview')">
          <div class="flex items-center gap-space-sm">
            <div class="w-8 h-8 rounded bg-primary-container/20 border border-primary-container flex items-center justify-center text-primary-container shadow-[0_0_12px_rgba(46,92,255,0.35)]">
              <span class="material-symbols-outlined text-[20px]">terminal</span>
            </div>
            <div>
              <div class="font-headline-md text-headline-md font-bold tracking-tight text-ink-white flex items-center gap-1">
                明策 <span class="text-primary-container font-extrabold tracking-wider">MINGCE</span>
              </div>
              <div class="font-label-sm text-label-sm text-steel-muted tracking-widest">TERMINAL v4.2</div>
            </div>
          </div>
        </div>
        <!-- Nav -->
        <nav class="flex flex-col gap-1.5">
          <a
            v-for="n in navs"
            :key="n.path"
            class="flex items-center gap-space-sm px-3 py-2.5 rounded-md font-headline-sm text-headline-sm cursor-pointer transition-colors duration-150"
            :class="active === n.path
              ? 'bg-card-navy text-ink-white border-l-2 border-primary-container shadow-[inset_0_0_16px_rgba(46,92,255,0.08)]'
              : 'text-steel-muted font-body-md text-body-md hover:bg-card-navy hover:text-ink-white'"
            @click="router.push(n.path)"
          >
            <span
              class="material-symbols-outlined text-[18px]"
              :class="{ 'text-primary-container': active === n.path, 'text-bear-red/80': n.alert && active !== n.path }"
            >{{ n.icon }}</span>
            <span>{{ n.name }}</span>
            <span v-if="n.alert" class="ml-auto font-label-sm text-[9px] px-1 bg-bear-red/20 text-bear-red border border-bear-red/40 rounded">ALERT</span>
            <span v-else-if="active === n.path" class="ml-auto w-1.5 h-1.5 rounded-full bg-primary-container animate-pulse"></span>
          </a>
        </nav>
      </div>
      <!-- 底部操作员卡 -->
      <div class="flex flex-col gap-space-sm pt-space-sm border-t border-hairline">
        <div class="p-2.5 bg-card-navy rounded border border-hairline flex flex-col gap-1.5 font-label-sm text-label-sm">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-1 text-ink-white">
              <span class="material-symbols-outlined text-[15px] text-primary-fixed-dim">badge</span>
              <span>操作员: {{ store.user?.username || '--' }}</span>
            </div>
            <span class="px-1 text-[9px] bg-primary-container/20 text-primary-fixed-dim border border-primary-container/40 rounded">PRO</span>
          </div>
          <div class="flex items-center justify-between text-steel-muted text-[10px]">
            <div class="flex items-center gap-1">
              <span class="w-1.5 h-1.5 rounded-full bg-bull-green"></span>
              <span>HK-CENTRAL-01</span>
            </div>
            <div class="font-mono-data text-bull-green flex items-center gap-0.5">
              <span class="material-symbols-outlined text-[12px]">wifi_tethering</span>
              <span>12ms</span>
            </div>
          </div>
          <div class="text-[9px] text-steel-muted font-mono-data tracking-wider opacity-60">AES-256 GCM · ZERO LOG</div>
        </div>
      </div>
    </aside>

    <!-- ===== TopBar (设计稿还原) ===== -->
    <header class="fixed top-0 left-60 right-0 h-14 z-30 border-b border-hairline bg-canvas-obsidian flex justify-between items-center px-margin">
      <div class="flex items-center gap-space-md">
        <div class="flex items-center gap-2">
          <h1 class="font-headline-sm text-headline-sm font-semibold tracking-wide text-ink-white">{{ pageEn }}</h1>
          <span class="text-hairline">/</span>
          <span class="font-mono-data text-[11px] px-2 py-0.5 rounded bg-surface-slate border border-hairline text-steel-muted flex items-center gap-1">
            <span class="w-1.5 h-1.5 rounded-full bg-bull-green animate-ping"></span>
            STATUS: LIVE FEED
          </span>
        </div>
      </div>
      <!-- 搜索 -->
      <div class="relative w-96 max-w-md hidden md:block">
        <div class="absolute inset-y-0 left-0 pl-2.5 flex items-center pointer-events-none text-steel-muted">
          <span class="material-symbols-outlined text-[16px]">search</span>
        </div>
        <input
          v-model="keyword"
          class="w-full h-8 pl-8 pr-12 text-[12px] font-mono-data bg-surface-slate text-ink-white placeholder-steel-muted border border-hairline rounded focus:outline-none focus:border-primary-container focus:ring-1 focus:ring-primary-container transition-all"
          placeholder="输入代码/指标快捷键 (⌘+K)"
          type="text"
          @keyup.enter="onSearch"
        />
        <div class="absolute inset-y-0 right-0 pr-2 flex items-center">
          <kbd class="px-1.5 py-0.5 text-[10px] font-mono-data bg-card-navy text-steel-muted border border-hairline rounded">⌘K</kbd>
        </div>
      </div>
      <!-- 右侧状态簇 -->
      <div class="flex items-center gap-space-md">
        <div class="hidden lg:flex items-center gap-1.5 px-2.5 py-1 bg-surface-slate border border-hairline rounded text-[11px] font-mono-data">
          <span class="w-2 h-2 rounded-full bg-bull-green"></span>
          <span class="text-steel-muted">市场活跃度</span>
          <span class="text-bull-green font-semibold">HIGH</span>
        </div>
        <div class="hidden xl:flex items-center gap-1 text-[11px] font-mono-data text-steel-muted">
          <span class="material-symbols-outlined text-[15px] text-bull-green">speed</span>
          <span>SSL 256-BIT · 14ms</span>
        </div>
        <div class="relative" data-notif>
          <button
            class="relative p-1 transition-colors duration-150"
            :class="notifOpen ? 'text-ink-white' : 'text-steel-muted hover:text-ink-white'"
            title="通知待办"
            @click="toggleNotif"
          >
            <span class="material-symbols-outlined text-[20px]">notifications</span>
            <span v-if="notices.length" class="absolute top-0.5 right-0.5 w-2 h-2 rounded-full bg-bear-red border-2 border-canvas-obsidian"></span>
          </button>
          <!-- 通知下拉面板 -->
          <div
            v-if="notifOpen"
            class="absolute right-0 top-10 w-80 bg-card-navy border border-hairline rounded-lg shadow-[0_8px_24px_rgba(0,0,0,0.5)] z-50 overflow-hidden"
          >
            <div class="flex items-center justify-between px-3 py-2.5 border-b border-hairline">
              <span class="font-headline-sm text-headline-sm text-ink-white flex items-center gap-1.5">
                <span class="material-symbols-outlined text-[16px] text-primary-container">notifications</span>
                通知待办
              </span>
              <button class="text-steel-muted hover:text-ink-white transition-colors" title="刷新" @click="loadNotices">
                <span class="material-symbols-outlined text-[15px]">refresh</span>
              </button>
            </div>
            <div class="max-h-72 overflow-y-auto">
              <div v-if="notifLoading" class="py-6 text-center text-steel-muted font-mono-data text-[11px]">加载中…</div>
              <div v-else-if="notifErr" class="py-6 text-center text-bear-red font-mono-data text-[11px]">{{ notifErr }}</div>
              <div v-else-if="!notices.length" class="py-6 text-center text-steel-muted font-mono-data text-[11px]">暂无通知</div>
              <a
                v-for="n in notices"
                v-else
                :key="n.id"
                class="block px-3 py-2.5 border-b border-hairline/50 last:border-b-0 hover:bg-card-navy-high cursor-pointer transition-colors"
                @click="openNotice(n)"
              >
                <div class="flex items-center gap-1.5 mb-0.5">
                  <span class="w-1.5 h-1.5 rounded-full bg-primary-container shrink-0"></span>
                  <span class="font-mono-data text-[10px] text-steel-muted">{{ fmtAgo(ts(n.publish_at)) }}</span>
                </div>
                <p class="font-body-md text-[12px] text-on-surface line-clamp-2 leading-snug">{{ n.title }}</p>
              </a>
            </div>
            <button
              class="w-full py-2 text-center font-label-sm text-label-sm text-primary-fixed-dim hover:text-ink-white hover:bg-card-navy-high border-t border-hairline transition-colors"
              @click="goAllNews"
            >
              查看全部
            </button>
          </div>
        </div>
        <button class="hidden sm:flex items-center gap-1 px-3 py-1 bg-bull-green/90 hover:bg-bull-green text-canvas-obsidian font-label-sm text-label-sm font-semibold rounded transition-all duration-150" @click="router.push('/deposit')" title="充值">
          <span class="material-symbols-outlined text-[14px]">south</span>
          <span>充值</span>
        </button>
        <button class="hidden sm:flex items-center gap-1 px-3 py-1 bg-card-navy hover:bg-card-navy-high text-ink-white font-label-sm text-label-sm border border-hairline hover:border-amber-warn/60 rounded transition-all duration-150" @click="router.push('/withdraw')" title="提现">
          <span class="material-symbols-outlined text-[14px]">north</span>
          <span>提现</span>
        </button>
        <button class="hidden sm:flex items-center gap-1 px-3 py-1 bg-card-navy hover:bg-card-navy-high text-primary-fixed-dim font-label-sm text-label-sm border border-hairline hover:border-primary-container rounded transition-all duration-150" @click="logout" title="退出登录">
          <span class="material-symbols-outlined text-[14px]">logout</span>
          <span>断开终端</span>
        </button>
        <div class="flex items-center gap-2 pl-2 border-l border-hairline cursor-pointer" @click="router.push('/profile')">
          <div class="w-8 h-8 rounded bg-card-navy border border-hairline flex items-center justify-center font-mono-data text-xs text-primary-fixed-dim font-bold shadow-inner" :title="store.user?.username">
            {{ avatarText }}
          </div>
        </div>
      </div>
    </header>

    <!-- ===== 内容区 ===== -->
    <main class="ml-60 pt-14 min-h-screen terminal-grid-bg px-8 pb-10">
      <div class="pt-8">
        <router-view />
      </div>
    </main>
  </div>
</template>

<style>
/* 设计稿网格底纹 (全局, 非 scoped) */
.terminal-grid-bg {
  background-image:
    linear-gradient(rgba(52, 65, 94, 0.12) 1px, transparent 1px),
    linear-gradient(90deg, rgba(52, 65, 94, 0.12) 1px, transparent 1px);
  background-size: 32px 32px;
}
body { background: #070d1c; }
</style>
