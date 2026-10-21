<script setup>
import { onMounted, onBeforeUnmount, ref, computed, nextTick } from 'vue'
import { chatApi, marketApi } from '../api'
import { useUserStore } from '../store/user'
import { fmtTime } from '../utils/format'
import { chatWs } from '../utils/chatWs'

const store = useUserStore()
const conversations = ref([])
const current = ref(null)
const messages = ref([])
const members = ref([])
const draft = ref('')
const sending = ref(false)
const loading = ref(true)
const listEl = ref(null)
const peerReadId = ref(null) // 单聊对方已读游标; null = 群聊/未加载, 不画回执
let timer = null

async function loadConversations() {
  try {
    const res = await chatApi.conversations()
    conversations.value = res.items || res || []
    if (!current.value && conversations.value.length) select(conversations.value[0])
  } finally {
    loading.value = false
  }
}

async function loadMessages(scroll = false) {
  if (!current.value) return
  try {
    const res = await chatApi.messages(current.value.id, { limit: 50 })
    messages.value = (res.items || res || []).slice().reverse()
    if (scroll) {
      await nextTick()
      listEl.value && (listEl.value.scrollTop = listEl.value.scrollHeight)
    }
  } catch { /* ignore */ }
}

function scrollBottom() {
  listEl.value && (listEl.value.scrollTop = listEl.value.scrollHeight)
}

// 推进已读游标到当前最大消息 id, 并清掉本地未读角标
function doMarkRead() {
  const c = current.value
  if (!c) return
  const id = messages.value.reduce((max, m) => Math.max(max, m.id || 0), 0)
  if (!id) return
  chatApi.markRead(c.id, id).catch(() => {})
  c.unread_count = 0
}

async function select(c) {
  current.value = c
  searchQuery.value = ''
  peerReadId.value = null
  await loadMessages(true)
  doMarkRead()
  // 单聊拉对方已读游标, 用于回执双勾
  if (c.type === 'direct') {
    try {
      const st = await chatApi.peerReadState(c.id)
      if (current.value?.id === c.id) peerReadId.value = st.peer_last_read_message_id ?? null
    } catch { peerReadId.value = null }
  }
  try {
    const res = await chatApi.members(c.id)
    members.value = res.items || res || []
  } catch { members.value = [] }
}

async function send() {
  const text = draft.value.trim()
  if (!text || !current.value || sending.value) return
  sending.value = true
  try {
    const out = await chatApi.sendMessage(current.value.id, { type: 'text', content: text })
    draft.value = ''
    // 本地立即上屏 (单聊单勾), 不等 WS 回包
    if (out && out.id != null && !messages.value.some((x) => x.id === out.id)) {
      messages.value.push(out)
      await nextTick()
      scrollBottom()
    }
    await loadMessages(true)
    doMarkRead()
  } catch { /* ignore */ } finally {
    sending.value = false
  }
}

function onKeydown(e) {
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault()
    send()
  }
}

// ---------- WebSocket 实时事件 ----------
function onWsMessage(ev) {
  const convId = ev.conversation_id
  const msg = ev.message
  if (!convId || !msg || msg.id == null) return
  const mine = msg.sender?.id != null && msg.sender?.id === store.user?.id
  if (current.value && current.value.id === convId) {
    // 当前房间: 追加消息并按最新消息推进已读
    if (!messages.value.some((x) => x.id === msg.id)) {
      const el = listEl.value
      const nearBottom = !el || el.scrollHeight - el.scrollTop - el.clientHeight < 120
      messages.value.push(msg)
      if (nearBottom) nextTick(scrollBottom)
    }
    doMarkRead()
    return
  }
  // 其他房间: 未读+1 并顶到最前 (自己发的消息不计未读)
  const idx = conversations.value.findIndex((x) => x.id === convId)
  if (idx >= 0) {
    const c = conversations.value[idx]
    if (!mine) c.unread_count = (c.unread_count || 0) + 1
    c.last_message = {
      id: msg.id,
      msg_type: msg.msg_type,
      content: msg.content,
      sender_name: msg.sender?.nickname || msg.sender?.username || '',
      created_at: msg.created_at,
      is_mine: mine,
      read: null,
    }
    conversations.value.splice(idx, 1)
    conversations.value.unshift(c)
  } else {
    loadConversations() // 未知会话 (新会话), 重新拉列表
  }
}

function onWsRead(ev) {
  if (!current.value || ev.conversation_id !== current.value.id) return
  const id = Number(ev.message_id)
  if (!isNaN(id) && (peerReadId.value == null || id > peerReadId.value)) peerReadId.value = id
}

const isMine = (m) => m.sender?.id != null && m.sender?.id === store.user?.id
const nameOf = (m) =>
  m.sender?.nickname ||
  m.sender?.username ||
  (isMine(m) ? store.user?.nickname || store.user?.username || '我' : `用户${m.sender?.id ?? ''}`)
const avatarOf = (name) => (name || 'U').slice(0, 2).toUpperCase()
const timeOf = (m) => fmtTime(m.created_at ? new Date(m.created_at).getTime() : null)
const memberName = (m) => m.nickname || m.username || `用户${m.user_id ?? m.id ?? ''}`
const roleBadge = (m) => (m.role === 'owner' ? '群主' : m.role && m.role !== 'member' ? '管理' : '')

// ---------- 钉选会话 (localStorage 持久化) ----------
function readPinned() {
  try {
    return new Set(JSON.parse(localStorage.getItem('pinnedChats') || '[]'))
  } catch {
    return new Set()
  }
}
const pinned = ref(readPinned())
const isPinned = (id) => pinned.value.has(id)
function togglePin(c) {
  if (!c) return
  const s = new Set(pinned.value)
  if (s.has(c.id)) s.delete(c.id)
  else s.add(c.id)
  pinned.value = s
  try {
    localStorage.setItem('pinnedChats', JSON.stringify([...s]))
  } catch { /* ignore */ }
}
const sortedConversations = computed(() =>
  [...conversations.value].sort((a, b) => Number(isPinned(b.id)) - Number(isPinned(a.id)))
)

// ---------- 频道内搜索 ----------
const searchOpen = ref(false)
const searchQuery = ref('')
function toggleSearch() {
  searchOpen.value = !searchOpen.value
  if (!searchOpen.value) searchQuery.value = ''
}
const shownMessages = computed(() => {
  const q = searchQuery.value.trim().toLowerCase()
  if (!q) return messages.value
  return messages.value.filter((m) => String(m.content || '').toLowerCase().includes(q))
})

// ---------- 输入条插入工具 ----------
const draftEl = ref(null)
const showEmoji = ref(false)
const showMention = ref(false)
const EMOJIS = ['👍', '🔥', '🚀', '📈', '📉', '💰', '⚠️', '🎯', '🐳', '💎', '🤝', '😂']
function insertText(t) {
  const el = draftEl.value
  if (el && typeof el.selectionStart === 'number') {
    const s = el.selectionStart
    const e = el.selectionEnd
    draft.value = draft.value.slice(0, s) + t + draft.value.slice(e)
    nextTick(() => {
      el.focus()
      const p = s + t.length
      el.setSelectionRange(p, p)
    })
  } else {
    draft.value += t
  }
}
function pickEmoji(e) {
  insertText(e)
  showEmoji.value = false
}
function pickMember(m) {
  insertText('@' + memberName(m) + ' ')
  showMention.value = false
}
function insertCode() {
  insertText('\n```\n\n```\n')
}
async function insertTicker() {
  try {
    const res = await marketApi.ticker('BTC-USDT')
    const d = res?.data?.[0] || res?.data || {}
    const last = Number(d.last)
    if (isNaN(last)) return
    const open = Number(d.open24h)
    const pct = !isNaN(open) && open ? ((last - open) / open) * 100 : null
    insertText(
      `[BTC $${last.toLocaleString('en-US')}${pct != null ? ' ' + (pct >= 0 ? '+' : '') + pct.toFixed(2) + '%' : ''}]`
    )
  } catch { /* 静默降级 */ }
}

// ---------- 成员过滤 ----------
const memberFilter = ref('all') // all | online | admin
const showFilterMenu = ref(false)
const FILTER_LABEL = { all: '全部', online: '仅在线', admin: '仅管理' }
const isAdminMember = (m) => m.role === 'owner' || (m.role && m.role !== 'member')
const isOnlineMember = (m) => m.online !== false && m.is_online !== false
const filteredMembers = computed(() => {
  if (memberFilter.value === 'online') return members.value.filter(isOnlineMember)
  if (memberFilter.value === 'admin') return members.value.filter(isAdminMember)
  return members.value
})
function setMemberFilter(f) {
  memberFilter.value = f
  showFilterMenu.value = false
}

onMounted(() => {
  loadConversations()
  chatWs.connect()
  chatWs.on('message', onWsMessage)
  chatWs.on('read', onWsRead)
  timer = setInterval(loadMessages, 5000) // WS 之外的兜底轮询
})
onBeforeUnmount(() => {
  clearInterval(timer)
  chatWs.off('message', onWsMessage)
  chatWs.off('read', onWsRead)
})
</script>

<template>
  <!-- 三栏金融情报操盘聊天布局 -->
  <div class="flex gap-4 overflow-hidden" style="height: calc(100vh - 56px - 72px)">
    <!-- 3.1 左窄栏: 情报频道 -->
    <section class="w-56 flex-shrink-0 bg-card-navy border border-hairline rounded-xl flex flex-col justify-between overflow-hidden shadow-sm">
      <div class="min-h-0 flex flex-col">
        <div class="p-3 border-b border-hairline flex items-center justify-between">
          <span class="text-xs font-headline-sm tracking-wider text-steel-muted uppercase flex items-center gap-1.5">
            <span class="material-symbols-outlined text-[15px] text-primary-container">tag</span>
            情报频道 CHANNELS
          </span>
          <button
            class="text-steel-muted/40 cursor-not-allowed"
            title="频道由管理员创建"
            disabled
          >
            <span class="material-symbols-outlined text-[16px]">add</span>
          </button>
        </div>
        <div class="p-2 space-y-1 overflow-y-auto">
          <div v-if="loading" class="py-6 text-center text-steel-muted font-mono-data text-[11px]">加载中…</div>
          <div v-else-if="!conversations.length" class="py-6 text-center text-steel-muted font-mono-data text-[11px]">暂无会话</div>
          <div
            v-for="c in sortedConversations"
            :key="c.id"
            class="flex items-center justify-between px-2.5 py-2 rounded-lg cursor-pointer transition-colors group"
            :class="current?.id === c.id
              ? 'bg-card-navy-high border-l-2 border-primary-container'
              : 'hover:bg-card-navy-high/60'"
            @click="select(c)"
          >
            <div class="flex items-center gap-2 truncate">
              <span class="font-mono-data font-bold text-sm" :class="current?.id === c.id ? 'text-primary-container' : 'text-steel-muted group-hover:text-ink-white'">#</span>
              <span class="text-xs truncate" :class="current?.id === c.id ? 'font-headline-sm text-ink-white' : 'font-body-md text-steel-muted group-hover:text-ink-white'">
                {{ c.title || c.name || `会话 ${c.id}` }}
              </span>
            </div>
            <div class="flex items-center gap-1 flex-shrink-0">
              <span
                v-if="isPinned(c.id)"
                class="material-symbols-outlined text-[13px] text-primary-container cursor-pointer hover:text-bear-red transition-colors"
                title="取消钉选"
                @click.stop="togglePin(c)"
              >push_pin</span>
              <span
                v-if="c.unread_count"
                class="px-1.5 rounded-full font-mono-data text-[10px] font-semibold"
                :class="current?.id === c.id
                  ? 'bg-primary-container text-ink-white'
                  : 'bg-bear-red/20 text-bear-red border border-bear-red/30'"
              >{{ c.unread_count }}</span>
            </div>
          </div>
        </div>
      </div>
      <!-- 底部状态区 -->
      <div class="p-3 border-t border-hairline bg-surface-slate/80">
        <div class="flex items-center justify-between text-xs font-mono-data text-steel-muted mb-1.5">
          <div class="flex items-center gap-2">
            <span class="w-2 h-2 rounded-full bg-bull-green animate-pulse"></span>
            <span class="text-ink-white font-medium">在线 {{ members.length || '--' }}</span>
          </div>
          <span class="material-symbols-outlined text-[15px] text-steel-muted" title="加密通道">lock</span>
        </div>
        <div class="flex justify-between text-[10px] font-mono-data text-steel-muted">
          <span>WS 实时 · 5s 轮询兜底</span>
          <span class="text-bull-green">SYNCED</span>
        </div>
      </div>
    </section>

    <!-- 3.2 中栏: 核心消息流与操作台 -->
    <section class="flex-1 min-w-0 bg-card-navy border border-hairline rounded-xl flex flex-col justify-between overflow-hidden shadow-sm">
      <!-- 消息流顶部信息条 -->
      <header class="h-12 flex-shrink-0 border-b border-hairline px-4 flex items-center justify-between bg-surface-slate/60">
        <div class="flex items-center gap-3 min-w-0">
          <div class="flex items-center gap-1.5">
            <span class="font-mono-data text-primary-container font-bold text-base">#</span>
            <h2 class="font-headline-sm text-headline-sm text-ink-white truncate">{{ current ? (current.title || current.name || `会话 ${current.id}`) : '聊天室' }}</h2>
          </div>
          <span class="text-hairline">|</span>
          <p class="text-xs text-steel-muted truncate max-w-md">WebSocket 实时 · {{ messages.length }} 条消息</p>
        </div>
        <div class="flex items-center gap-2">
          <button
            class="flex items-center gap-1 px-2.5 py-1 rounded border text-xs font-mono-data transition-colors"
            :class="current && isPinned(current.id)
              ? 'bg-primary-container/20 border-primary-container/50 text-primary-container'
              : 'bg-card-navy hover:bg-card-navy-high border-hairline text-steel-muted hover:text-ink-white'"
            :title="current && isPinned(current.id) ? '取消钉选此频道' : '钉选此频道到列表顶部'"
            :disabled="!current"
            @click="togglePin(current)"
          >
            <span class="material-symbols-outlined text-[14px]">push_pin</span>
            <span>{{ current && isPinned(current.id) ? '已钉选' : '钉选' }}</span>
          </button>
          <button
            class="p-1.5 rounded transition-colors"
            :class="searchOpen ? 'bg-primary-container/20 text-primary-container' : 'hover:bg-card-navy-high text-steel-muted hover:text-ink-white'"
            title="搜索此频道历史消息"
            @click="toggleSearch"
          >
            <span class="material-symbols-outlined text-[16px]">search</span>
          </button>
          <button class="p-1.5 rounded hover:bg-card-navy-high text-steel-muted hover:text-ink-white transition-colors" title="刷新消息" @click="loadMessages(true)">
            <span class="material-symbols-outlined text-[16px]">sync</span>
          </button>
        </div>
      </header>

      <!-- 频道内搜索条 -->
      <div v-if="searchOpen" class="flex-shrink-0 px-4 py-2 border-b border-hairline bg-card-navy-high/40 flex items-center gap-2">
        <span class="material-symbols-outlined text-[15px] text-steel-muted">search</span>
        <input
          v-model="searchQuery"
          type="text"
          class="flex-1 bg-transparent border-0 text-xs text-ink-white placeholder-steel-muted focus:ring-0 focus:outline-none font-body-md"
          placeholder="在当前频道消息中搜索…"
        />
        <span v-if="searchQuery.trim()" class="px-1.5 py-0.5 rounded bg-primary-container/20 text-primary-fixed-dim border border-primary-container/40 font-mono-data text-[10px]">
          匹配 {{ shownMessages.length }} 条
        </span>
        <button class="p-1 rounded text-steel-muted hover:text-ink-white transition-colors" title="关闭搜索" @click="toggleSearch">
          <span class="material-symbols-outlined text-[14px]">close</span>
        </button>
      </div>

      <!-- 消息滚动区域 -->
      <div ref="listEl" class="flex-1 p-4 overflow-y-auto space-y-3.5 pr-2">
        <div v-if="!shownMessages.length" class="py-10 text-center text-steel-muted font-mono-data text-[11px]">
          {{ searchQuery.trim() ? '无匹配消息' : '暂无消息, 来说第一句' }}
        </div>
        <template v-for="m in shownMessages" :key="m.id">
          <!-- 系统消息 (胶囊) -->
          <div v-if="m.type === 'system'" class="flex items-center justify-center my-2">
            <div class="px-3 py-1 rounded-full bg-surface-slate border border-hairline text-steel-muted font-mono-data text-[11px] flex items-center gap-2 shadow-inner">
              <span class="w-1.5 h-1.5 rounded-full bg-steel-muted"></span>
              <span>系统: {{ m.content }} · {{ timeOf(m) }}</span>
            </div>
          </div>
          <!-- 自己发送的消息 (右对齐高亮) -->
          <div v-else-if="isMine(m)" class="flex items-start justify-end gap-3 pt-1">
            <div class="flex flex-col items-end max-w-2xl min-w-0">
              <div class="flex items-center gap-2 mb-1">
                <span class="text-steel-muted font-mono-data text-[11px]">{{ timeOf(m) }}</span>
                <!-- 单聊已读回执: 已读双勾(青绿) / 未读单勾 -->
                <span
                  v-if="peerReadId != null && m.id != null"
                  class="material-symbols-outlined text-[14px] leading-none"
                  :class="m.id <= peerReadId ? 'text-[#00E388]' : 'text-steel-muted'"
                  :title="m.id <= peerReadId ? '已读' : '已送达'"
                >{{ m.id <= peerReadId ? 'done_all' : 'done' }}</span>
                <span class="font-headline-sm text-xs text-primary font-semibold">{{ nameOf(m) }} (我)</span>
              </div>
              <div class="bg-primary-container/20 border border-primary-container/40 rounded-lg p-3 text-xs text-ink-white leading-relaxed shadow-sm whitespace-pre-wrap break-words">
                {{ m.content }}
              </div>
            </div>
            <div class="w-8 h-8 rounded-full bg-primary-container border border-primary text-ink-white flex items-center justify-center font-mono-data text-xs font-bold flex-shrink-0 shadow-sm">
              {{ avatarOf(nameOf(m)) }}
            </div>
          </div>
          <!-- 他人消息 -->
          <div v-else class="flex items-start gap-3">
            <div class="w-8 h-8 rounded-full bg-card-navy-high border border-hairline flex items-center justify-center font-mono-data text-xs font-bold text-ink-white flex-shrink-0">
              {{ avatarOf(nameOf(m)) }}
            </div>
            <div class="flex-1 max-w-3xl min-w-0">
              <div class="flex items-center gap-2 mb-1">
                <span class="font-headline-sm text-xs text-ink-white font-semibold">{{ nameOf(m) }}</span>
                <span class="text-steel-muted font-mono-data text-[11px]">{{ timeOf(m) }}</span>
              </div>
              <div class="bg-card-navy-high border border-hairline/80 rounded-lg p-2.5 text-xs text-ink-white leading-relaxed whitespace-pre-wrap break-words">
                {{ m.content }}
              </div>
            </div>
          </div>
        </template>
      </div>

      <!-- 底部输入条 -->
      <footer class="p-3 flex-shrink-0 border-t border-hairline bg-surface-slate relative">
        <!-- 表情面板 -->
        <div v-if="showEmoji" class="absolute bottom-full left-3 mb-2 z-10 bg-card-navy border border-hairline rounded-lg p-2 shadow-lg grid grid-cols-6 gap-1 w-56">
          <button
            v-for="e in EMOJIS"
            :key="e"
            type="button"
            class="p-1.5 rounded hover:bg-card-navy-high text-base transition-colors"
            @click="pickEmoji(e)"
          >{{ e }}</button>
        </div>
        <!-- 提及成员面板 -->
        <div v-if="showMention" class="absolute bottom-full left-3 mb-2 z-10 bg-card-navy border border-hairline rounded-lg p-1.5 shadow-lg w-56 max-h-48 overflow-y-auto">
          <div v-if="!members.length" class="py-4 text-center text-steel-muted font-mono-data text-[11px]">暂无成员</div>
          <button
            v-for="m in members"
            :key="m.user_id ?? m.id"
            type="button"
            class="w-full flex items-center gap-2 p-1.5 rounded hover:bg-card-navy-high transition-colors text-left"
            @click="pickMember(m)"
          >
            <span class="w-5 h-5 rounded-full bg-card-navy-high border border-hairline flex items-center justify-center font-mono-data text-[10px] text-ink-white flex-shrink-0">{{ avatarOf(memberName(m)) }}</span>
            <span class="text-xs text-ink-white truncate">{{ memberName(m) }}</span>
          </button>
        </div>
        <div class="bg-card-navy border border-hairline rounded-lg p-2 focus-within:border-primary-container transition-colors">
          <textarea
            ref="draftEl"
            v-model="draft"
            class="w-full bg-transparent border-0 resize-none text-xs text-ink-white placeholder-steel-muted focus:ring-0 focus:outline-none p-1 font-body-md"
            :placeholder="current ? `在 # ${current.title || current.name || '会话'} 中发言...` : '请选择会话'"
            rows="2"
            :disabled="!current"
            @keydown="onKeydown"
          ></textarea>
          <div class="flex items-center justify-between pt-2 border-t border-hairline/60">
            <div class="flex items-center gap-1">
              <button
                class="p-1 rounded transition-colors"
                :class="showEmoji ? 'bg-card-navy-high text-ink-white' : 'text-steel-muted hover:text-ink-white hover:bg-card-navy-high'"
                title="插入表情"
                type="button"
                @click="showEmoji = !showEmoji; showMention = false"
              >
                <span class="material-symbols-outlined text-[16px]">sentiment_satisfied</span>
              </button>
              <button class="p-1 rounded text-steel-muted hover:text-ink-white hover:bg-card-navy-high transition-colors" title="插入代码块" type="button" @click="insertCode">
                <span class="material-symbols-outlined text-[16px]">code</span>
              </button>
              <button
                class="p-1 rounded transition-colors"
                :class="showMention ? 'bg-card-navy-high text-ink-white' : 'text-steel-muted hover:text-ink-white hover:bg-card-navy-high'"
                title="提及成员"
                type="button"
                @click="showMention = !showMention; showEmoji = false"
              >
                <span class="material-symbols-outlined text-[16px]">alternate_email</span>
              </button>
              <button class="p-1 rounded text-steel-muted hover:text-ink-white hover:bg-card-navy-high transition-colors" title="插入 BTC 实时行情" type="button" @click="insertTicker">
                <span class="material-symbols-outlined text-[16px]">insights</span>
              </button>
            </div>
            <div class="flex items-center gap-3">
              <span class="text-[11px] font-mono-data text-steel-muted">Enter 发送 · ⇧+Enter 换行</span>
              <button
                class="flex items-center gap-1.5 bg-primary-container hover:bg-inverse-primary text-ink-white px-3 py-1.5 rounded-lg text-xs font-headline-sm transition-colors shadow-sm disabled:opacity-40"
                :disabled="!draft.trim() || !current || sending"
                @click="send"
              >
                <span>发送</span>
                <span class="material-symbols-outlined text-[14px]">send</span>
              </button>
            </div>
          </div>
        </div>
      </footer>
    </section>

    <!-- 3.3 右窄栏: 在线成员列表 -->
    <aside class="w-60 flex-shrink-0 bg-card-navy border border-hairline rounded-xl flex flex-col justify-between overflow-hidden shadow-sm">
      <div class="p-3 border-b border-hairline flex items-center justify-between relative">
        <span class="text-xs font-headline-sm tracking-wider text-steel-muted uppercase flex items-center gap-1.5">
          <span class="material-symbols-outlined text-[15px] text-bull-green">group</span>
          在线成员 ONLINE ({{ filteredMembers.length }})
        </span>
        <div class="flex items-center gap-1.5">
          <span v-if="memberFilter !== 'all'" class="px-1.5 py-0.5 rounded bg-primary-container/20 text-primary-fixed-dim border border-primary-container/40 font-mono-data text-[9px]">
            {{ FILTER_LABEL[memberFilter] }}
          </span>
          <button
            class="transition-colors"
            :class="showFilterMenu || memberFilter !== 'all' ? 'text-primary-container' : 'text-steel-muted hover:text-ink-white'"
            title="成员过滤"
            @click="showFilterMenu = !showFilterMenu"
          >
            <span class="material-symbols-outlined text-[16px]">filter_list</span>
          </button>
        </div>
        <div v-if="showFilterMenu" class="absolute right-2 top-full mt-1 z-10 bg-card-navy border border-hairline rounded-lg p-1 shadow-lg w-28">
          <button
            v-for="(label, key) in FILTER_LABEL"
            :key="key"
            class="w-full text-left px-2.5 py-1.5 rounded text-xs transition-colors"
            :class="memberFilter === key ? 'bg-primary-container/20 text-primary-container font-semibold' : 'text-steel-muted hover:text-ink-white hover:bg-card-navy-high'"
            @click="setMemberFilter(key)"
          >{{ label }}</button>
        </div>
      </div>
      <div class="flex-1 overflow-y-auto p-2 space-y-1">
        <div v-if="!filteredMembers.length" class="py-6 text-center text-steel-muted font-mono-data text-[11px]">--</div>
        <div
          v-for="m in filteredMembers.slice(0, 30)"
          :key="m.user_id ?? m.id"
          class="flex items-center justify-between p-2 rounded-lg hover:bg-card-navy-high cursor-pointer transition-colors group"
          :class="{ 'bg-card-navy-high/50 border border-primary-container/20': (m.user_id ?? m.id) === store.user?.id }"
        >
          <div class="flex items-center gap-2.5 truncate">
            <div
              class="w-7 h-7 rounded-full border flex items-center justify-center font-mono-data text-xs flex-shrink-0"
              :class="(m.user_id ?? m.id) === store.user?.id
                ? 'bg-primary-container text-ink-white border-primary font-bold'
                : 'bg-card-navy-high border-hairline text-ink-white'"
            >
              {{ avatarOf(memberName(m)) }}
            </div>
            <div class="flex flex-col truncate">
              <span class="text-xs font-headline-sm truncate transition-colors" :class="(m.user_id ?? m.id) === store.user?.id ? 'text-primary font-semibold' : 'text-ink-white group-hover:text-primary'">
                {{ memberName(m) }}<template v-if="(m.user_id ?? m.id) === store.user?.id"> (我)</template>
              </span>
              <div v-if="roleBadge(m)" class="flex items-center gap-1">
                <span class="px-1 rounded bg-amber-warn/15 text-amber-warn text-[9px] font-mono-data border border-amber-warn/30">{{ roleBadge(m) }}</span>
              </div>
            </div>
          </div>
          <span class="w-1.5 h-1.5 rounded-full bg-bull-green flex-shrink-0"></span>
        </div>
      </div>
      <!-- 底部席位状态 -->
      <div class="p-3 border-t border-hairline bg-surface-slate/80 text-[11px] font-mono-data text-steel-muted">
        <div class="flex justify-between items-center mb-1">
          <span>当前席位:</span>
          <span class="text-ink-white">{{ store.user?.username || '--' }}</span>
        </div>
        <div class="flex justify-between items-center">
          <span>同步状态:</span>
          <span class="text-bull-green">WS LIVE</span>
        </div>
      </div>
    </aside>
  </div>
</template>
