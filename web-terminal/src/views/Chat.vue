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

// ---------- 轻提示 ----------
const toastMsg = ref('')
let toastTimer = null
function toast(msg) {
  toastMsg.value = msg
  clearTimeout(toastTimer)
  toastTimer = setTimeout(() => {
    toastMsg.value = ''
  }, 2400)
}

// ---------- 好友 (列表 / 申请 / 搜索添加) ----------
const showAddMenu = ref(false) // 左栏 + 下拉菜单
const friendModal = ref(false)
const friendTab = ref('list') // list | requests | search
const friends = ref([])
const friendReqs = ref({ incoming: [], outgoing: [] })
const onlineIds = ref(new Set())
const searchQ = ref('')
const searchRes = ref([])
const searching = ref(false)
const friendBusy = ref(0) // 正在处理的用户 id, 防重复点击
const reqBadge = computed(() => friendReqs.value.incoming.length)
const friendName = (f) => f.nickname || f.username || `用户${f.id}`
const RELATION_LABEL = { self: '我自己', friend: '已是好友', outgoing: '已申请', incoming: '待处理' }

async function loadFriends() {
  try {
    friends.value = (await chatApi.friends()) || []
  } catch {
    friends.value = []
  }
  try {
    const r = await chatApi.friendsOnline()
    onlineIds.value = new Set(r.online_ids || [])
  } catch { /* 在线状态失败静默 */ }
}

async function loadFriendReqs() {
  try {
    friendReqs.value = await chatApi.friendRequests()
  } catch { /* ignore */ }
}

function openFriends(tab = 'list') {
  showAddMenu.value = false
  friendTab.value = tab
  friendModal.value = true
  searchQ.value = ''
  searchRes.value = []
  loadFriends()
  loadFriendReqs()
}

let searchTimer = null
function onSearchInput() {
  clearTimeout(searchTimer)
  if (!searchQ.value.trim()) {
    searchRes.value = []
    return
  }
  searchTimer = setTimeout(doSearch, 300)
}

async function doSearch() {
  const q = searchQ.value.trim()
  if (!q || searching.value) return
  searching.value = true
  try {
    searchRes.value = (await chatApi.searchUsers(q)) || []
  } catch {
    searchRes.value = []
  } finally {
    searching.value = false
  }
}

async function sendFriendReq(u) {
  if (friendBusy.value) return
  friendBusy.value = u.id
  try {
    await chatApi.friendRequest(u.id)
    u.relation = 'outgoing'
    toast('好友申请已发送')
    loadFriendReqs()
  } catch (e) {
    toast(e.message || '申请失败')
  } finally {
    friendBusy.value = 0
  }
}

async function acceptReq(r) {
  try {
    await chatApi.friendAccept(r.id)
    toast('已添加为好友')
    loadFriends()
    loadFriendReqs()
  } catch (e) {
    toast(e.message || '操作失败')
  }
}

async function rejectReq(r) {
  try {
    await chatApi.friendReject(r.id)
    loadFriendReqs()
  } catch (e) {
    toast(e.message || '操作失败')
  }
}

async function removeFriend(f) {
  if (!confirm(`确定删除好友 ${friendName(f)} 吗?`)) return
  try {
    await chatApi.friendRemove(f.id)
    friends.value = friends.value.filter((x) => x.id !== f.id)
    toast('已删除好友')
  } catch (e) {
    toast(e.message || '删除失败')
  }
}

// 发起单聊: 复用后端已有会话, 成功后跳进去
async function chatWith(u) {
  try {
    const conv = await chatApi.createDirect(u.id)
    friendModal.value = false
    await loadConversations()
    const c = conversations.value.find((x) => x.id === conv.id)
    if (c) select(c)
  } catch (e) {
    toast(e.message || '发起会话失败')
  }
}

// ---------- 建群 ----------
const groupModal = ref(false)
const groupName = ref('')
const groupSel = ref(new Set())
const groupBusy = ref(false)

function openGroup() {
  showAddMenu.value = false
  groupName.value = ''
  groupSel.value = new Set()
  groupModal.value = true
  loadFriends()
}

function toggleSetMember(setRef, id) {
  const s = new Set(setRef.value)
  if (s.has(id)) s.delete(id)
  else s.add(id)
  setRef.value = s
}

async function submitGroup() {
  const name = groupName.value.trim()
  if (!name) return toast('请输入群名称')
  if (groupBusy.value) return
  groupBusy.value = true
  try {
    const conv = await chatApi.createGroup(name, [...groupSel.value])
    groupModal.value = false
    await loadConversations()
    const c = conversations.value.find((x) => x.id === conv.id)
    if (c) select(c)
    toast('群聊已创建')
  } catch (e) {
    toast(e.message || '建群失败')
  } finally {
    groupBusy.value = false
  }
}

// ---------- 群管理 (右栏) ----------
const isGroup = computed(() => current.value?.type === 'group')
const myRole = computed(() => {
  const me = members.value.find((m) => (m.user_id ?? m.id) === store.user?.id)
  return me?.role || ''
})
const amOwner = computed(() => myRole.value === 'owner')

const addMemberModal = ref(false)
const addSel = ref(new Set())
const addBusy = ref(false)
// 只能从好友里拉人, 且过滤已在群内的
const addCandidates = computed(() =>
  friends.value.filter((f) => !members.value.some((m) => (m.user_id ?? m.id) === f.id))
)

function openAddMember() {
  addSel.value = new Set()
  addMemberModal.value = true
  loadFriends()
}

async function submitAddMembers() {
  if (!addSel.value.size || addBusy.value || !current.value) return
  addBusy.value = true
  try {
    for (const uid of addSel.value) {
      await chatApi.addMember(current.value.id, uid)
    }
    addMemberModal.value = false
    const res = await chatApi.members(current.value.id)
    members.value = res.items || res || []
    toast('已添加成员')
  } catch (e) {
    toast(e.message || '添加失败')
  } finally {
    addBusy.value = false
  }
}

async function kickMember(m) {
  const name = memberName(m)
  if (!confirm(`确定将 ${name} 移出群聊吗?`)) return
  try {
    await chatApi.removeMember(current.value.id, m.user_id ?? m.id)
    members.value = members.value.filter((x) => (x.user_id ?? x.id) !== (m.user_id ?? m.id))
    toast('已移出成员')
  } catch (e) {
    toast(e.message || '移除失败')
  }
}

// 改群名 (仅群主)
const renaming = ref(false)
const renameVal = ref('')
function startRename() {
  renameVal.value = current.value?.name || ''
  renaming.value = true
}
async function submitRename() {
  const name = renameVal.value.trim()
  if (!name) return toast('群名不能为空')
  try {
    await chatApi.renameGroup(current.value.id, name)
    current.value.name = name
    renaming.value = false
    loadConversations()
    toast('群名已修改')
  } catch (e) {
    toast(e.message || '修改失败')
  }
}

// 退出群聊 (群) / 删除会话 (单聊对我隐藏)
async function leaveConv() {
  const c = current.value
  if (!c) return
  if (!confirm(c.type === 'group' ? '确定退出该群聊吗?' : '确定删除该会话吗?')) return
  try {
    await chatApi.deleteConversation(c.id)
    current.value = null
    messages.value = []
    members.value = []
    loadConversations()
  } catch (e) {
    toast(e.message || '操作失败')
  }
}

// 收到好友申请 / 群变更 (改名/加人/踢人) 的实时事件
function onWsFriendRequest() {
  loadFriendReqs()
  toast('收到新的好友申请')
}
function onWsGroupChanged(ev) {
  loadConversations()
  if (!current.value || ev.conversation_id !== current.value.id) return
  if (ev.type === 'group_updated' && ev.name) current.value.name = ev.name
  chatApi
    .members(current.value.id)
    .then((res) => {
      members.value = res.items || res || []
    })
    .catch(() => {})
  // 我被踢出当前群: 清空并回列表
  if (ev.type === 'member_removed' && ev.user_id === store.user?.id) {
    current.value = null
    messages.value = []
    members.value = []
    toast('你已被移出该群聊')
  }
}

onMounted(() => {
  loadConversations()
  loadFriendReqs()
  chatWs.connect()
  chatWs.on('message', onWsMessage)
  chatWs.on('read', onWsRead)
  chatWs.on('friend_request', onWsFriendRequest)
  chatWs.on('group_updated', onWsGroupChanged)
  chatWs.on('member_added', onWsGroupChanged)
  chatWs.on('member_removed', onWsGroupChanged)
  timer = setInterval(loadMessages, 5000) // WS 之外的兜底轮询
})
onBeforeUnmount(() => {
  clearInterval(timer)
  chatWs.off('message', onWsMessage)
  chatWs.off('read', onWsRead)
  chatWs.off('friend_request', onWsFriendRequest)
  chatWs.off('group_updated', onWsGroupChanged)
  chatWs.off('member_added', onWsGroupChanged)
  chatWs.off('member_removed', onWsGroupChanged)
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
          <div class="relative">
            <button
              class="relative transition-colors"
              :class="showAddMenu ? 'text-primary-container' : 'text-steel-muted hover:text-ink-white'"
              title="好友 / 建群"
              @click="showAddMenu = !showAddMenu"
            >
              <span class="material-symbols-outlined text-[16px]">add</span>
              <span v-if="reqBadge" class="absolute -top-1 -right-1 w-2 h-2 rounded-full bg-bear-red"></span>
            </button>
            <!-- 透明遮罩: 点击外部收起菜单 -->
            <div v-if="showAddMenu" class="fixed inset-0 z-10" @click="showAddMenu = false"></div>
            <div v-if="showAddMenu" class="absolute right-0 top-full mt-1 z-20 bg-card-navy border border-hairline rounded-lg p-1 shadow-lg w-36">
              <button
                class="w-full flex items-center gap-2 px-2.5 py-1.5 rounded text-xs text-steel-muted hover:text-ink-white hover:bg-card-navy-high transition-colors"
                @click="openFriends('search')"
              >
                <span class="material-symbols-outlined text-[15px]">person_add</span>
                添加好友
              </button>
              <button
                class="w-full flex items-center gap-2 px-2.5 py-1.5 rounded text-xs text-steel-muted hover:text-ink-white hover:bg-card-navy-high transition-colors"
                @click="openGroup"
              >
                <span class="material-symbols-outlined text-[15px]">group_add</span>
                创建群聊
              </button>
              <button
                class="w-full flex items-center justify-between gap-2 px-2.5 py-1.5 rounded text-xs text-steel-muted hover:text-ink-white hover:bg-card-navy-high transition-colors"
                @click="openFriends('list')"
              >
                <span class="flex items-center gap-2">
                  <span class="material-symbols-outlined text-[15px]">group</span>
                  我的好友
                </span>
                <span v-if="reqBadge" class="px-1.5 rounded-full bg-bear-red/20 text-bear-red border border-bear-red/30 font-mono-data text-[10px]">{{ reqBadge }}</span>
              </button>
            </div>
          </div>
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
            <span class="font-mono-data text-primary-container font-bold text-base">{{ isGroup ? '👥' : '#' }}</span>
            <!-- 群主点击笔图标可内联改群名 -->
            <div v-if="renaming" class="flex items-center gap-1.5">
              <input
                v-model="renameVal"
                type="text"
                maxlength="32"
                class="bg-card-navy-high border border-primary-container/50 rounded px-2 py-0.5 text-xs text-ink-white focus:outline-none w-36"
                @keydown.enter="submitRename"
                @keydown.esc="renaming = false"
              />
              <button class="text-bull-green hover:opacity-80" title="确认" @click="submitRename">
                <span class="material-symbols-outlined text-[16px]">check</span>
              </button>
              <button class="text-steel-muted hover:text-ink-white" title="取消" @click="renaming = false">
                <span class="material-symbols-outlined text-[16px]">close</span>
              </button>
            </div>
            <template v-else>
              <h2 class="font-headline-sm text-headline-sm text-ink-white truncate">{{ current ? (current.title || current.name || `会话 ${current.id}`) : '聊天室' }}</h2>
              <button
                v-if="isGroup && amOwner"
                class="text-steel-muted hover:text-primary-container transition-colors"
                title="修改群名"
                @click="startRename"
              >
                <span class="material-symbols-outlined text-[14px]">edit</span>
              </button>
            </template>
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
          <button
            v-if="current"
            class="p-1.5 rounded hover:bg-card-navy-high text-steel-muted hover:text-bear-red transition-colors"
            :title="isGroup ? '退出群聊' : '删除会话'"
            @click="leaveConv"
          >
            <span class="material-symbols-outlined text-[16px]">logout</span>
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
          <button
            v-if="isGroup"
            class="text-steel-muted hover:text-primary-container transition-colors"
            title="邀请好友进群"
            @click="openAddMember"
          >
            <span class="material-symbols-outlined text-[16px]">person_add</span>
          </button>
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
          <div class="flex items-center gap-1 flex-shrink-0">
            <!-- 群主可踢人 (不能踢群主和自己), 悬停行才显示 -->
            <button
              v-if="amOwner && m.role !== 'owner' && (m.user_id ?? m.id) !== store.user?.id"
              class="opacity-0 group-hover:opacity-100 text-steel-muted hover:text-bear-red transition-all"
              title="移出群聊"
              @click.stop="kickMember(m)"
            >
              <span class="material-symbols-outlined text-[14px]">person_remove</span>
            </button>
            <span class="w-1.5 h-1.5 rounded-full bg-bull-green"></span>
          </div>
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

    <!-- 轻提示 -->
    <div
      v-if="toastMsg"
      class="fixed bottom-8 left-1/2 -translate-x-1/2 z-[60] px-4 py-2 rounded-lg bg-card-navy-high border border-primary-container/40 text-xs text-ink-white shadow-lg font-body-md"
    >{{ toastMsg }}</div>

    <!-- 好友弹窗: 列表 / 申请 / 搜索添加 -->
    <div v-if="friendModal" class="fixed inset-0 z-50 bg-black/60 flex items-center justify-center p-4" @click.self="friendModal = false">
      <div class="w-[26rem] max-w-full bg-card-navy border border-hairline rounded-xl shadow-xl flex flex-col overflow-hidden" style="max-height: 70vh">
        <div class="flex items-center justify-between px-4 pt-3 pb-0 border-b border-hairline">
          <div class="flex gap-1">
            <button
              v-for="t in [['list', '好友'], ['requests', '申请'], ['search', '添加好友']]"
              :key="t[0]"
              class="relative px-3 py-2 text-xs font-headline-sm transition-colors border-b-2 -mb-px"
              :class="friendTab === t[0] ? 'text-primary-container border-primary-container' : 'text-steel-muted border-transparent hover:text-ink-white'"
              @click="friendTab = t[0]"
            >
              {{ t[1] }}
              <span v-if="t[0] === 'requests' && reqBadge" class="ml-1 px-1.5 rounded-full bg-bear-red/20 text-bear-red border border-bear-red/30 font-mono-data text-[10px]">{{ reqBadge }}</span>
            </button>
          </div>
          <button class="text-steel-muted hover:text-ink-white transition-colors" @click="friendModal = false">
            <span class="material-symbols-outlined text-[18px]">close</span>
          </button>
        </div>

        <!-- 好友列表 -->
        <div v-if="friendTab === 'list'" class="flex-1 overflow-y-auto p-3 space-y-1">
          <div v-if="!friends.length" class="py-10 text-center text-steel-muted font-mono-data text-[11px]">暂无好友, 去「添加好友」搜一个吧</div>
          <div
            v-for="f in friends"
            :key="f.id"
            class="flex items-center justify-between p-2 rounded-lg hover:bg-card-navy-high/60 transition-colors"
          >
            <div class="flex items-center gap-2.5 truncate">
              <div class="relative flex-shrink-0">
                <div class="w-8 h-8 rounded-full bg-card-navy-high border border-hairline flex items-center justify-center font-mono-data text-xs text-ink-white">
                  {{ avatarOf(friendName(f)) }}
                </div>
                <span
                  class="absolute -bottom-0.5 -right-0.5 w-2.5 h-2.5 rounded-full border-2 border-card-navy"
                  :class="onlineIds.has(f.id) ? 'bg-bull-green' : 'bg-steel-muted/50'"
                  :title="onlineIds.has(f.id) ? '在线' : '离线'"
                ></span>
              </div>
              <div class="flex flex-col truncate">
                <span class="text-xs font-headline-sm text-ink-white truncate">{{ friendName(f) }}</span>
                <span class="text-[10px] font-mono-data text-steel-muted">@{{ f.username }}</span>
              </div>
            </div>
            <div class="flex items-center gap-1 flex-shrink-0">
              <button
                class="px-2 py-1 rounded bg-primary-container/20 border border-primary-container/40 text-primary-container text-[11px] font-headline-sm hover:bg-primary-container/30 transition-colors"
                @click="chatWith(f)"
              >发消息</button>
              <button class="p-1 rounded text-steel-muted hover:text-bear-red transition-colors" title="删除好友" @click="removeFriend(f)">
                <span class="material-symbols-outlined text-[15px]">delete</span>
              </button>
            </div>
          </div>
        </div>

        <!-- 好友申请 -->
        <div v-else-if="friendTab === 'requests'" class="flex-1 overflow-y-auto p-3 space-y-1">
          <div v-if="!friendReqs.incoming.length && !friendReqs.outgoing.length" class="py-10 text-center text-steel-muted font-mono-data text-[11px]">暂无待处理申请</div>
          <div v-if="friendReqs.incoming.length" class="px-1 pt-1 pb-0.5 text-[10px] font-mono-data text-steel-muted uppercase">收到的申请</div>
          <div
            v-for="r in friendReqs.incoming"
            :key="'in-' + r.id"
            class="flex items-center justify-between p-2 rounded-lg hover:bg-card-navy-high/60 transition-colors"
          >
            <div class="flex items-center gap-2.5 truncate">
              <div class="w-8 h-8 rounded-full bg-card-navy-high border border-hairline flex items-center justify-center font-mono-data text-xs text-ink-white flex-shrink-0">
                {{ avatarOf(r.username) }}
              </div>
              <span class="text-xs font-headline-sm text-ink-white truncate">@{{ r.username }}</span>
            </div>
            <div class="flex items-center gap-1 flex-shrink-0">
              <button
                class="px-2 py-1 rounded bg-bull-green/15 border border-bull-green/40 text-bull-green text-[11px] font-headline-sm hover:bg-bull-green/25 transition-colors"
                @click="acceptReq(r)"
              >接受</button>
              <button
                class="px-2 py-1 rounded bg-card-navy-high border border-hairline text-steel-muted text-[11px] font-headline-sm hover:text-ink-white transition-colors"
                @click="rejectReq(r)"
              >拒绝</button>
            </div>
          </div>
          <div v-if="friendReqs.outgoing.length" class="px-1 pt-2 pb-0.5 text-[10px] font-mono-data text-steel-muted uppercase">我发出的申请</div>
          <div
            v-for="r in friendReqs.outgoing"
            :key="'out-' + r.id"
            class="flex items-center justify-between p-2 rounded-lg"
          >
            <div class="flex items-center gap-2.5 truncate">
              <div class="w-8 h-8 rounded-full bg-card-navy-high border border-hairline flex items-center justify-center font-mono-data text-xs text-ink-white flex-shrink-0">
                {{ avatarOf(r.username) }}
              </div>
              <span class="text-xs font-headline-sm text-ink-white truncate">@{{ r.username }}</span>
            </div>
            <span class="text-[11px] font-mono-data text-steel-muted flex-shrink-0">等待对方通过</span>
          </div>
        </div>

        <!-- 搜索添加 -->
        <div v-else class="flex-1 overflow-y-auto p-3 space-y-1 flex flex-col">
          <div class="flex items-center gap-2 bg-card-navy-high border border-hairline rounded-lg px-2.5 py-1.5 mb-1 focus-within:border-primary-container transition-colors">
            <span class="material-symbols-outlined text-[15px] text-steel-muted">search</span>
            <input
              v-model="searchQ"
              type="text"
              class="flex-1 bg-transparent border-0 text-xs text-ink-white placeholder-steel-muted focus:ring-0 focus:outline-none"
              placeholder="输入用户名搜索…"
              @input="onSearchInput"
              @keydown.enter="doSearch"
            />
          </div>
          <div v-if="searching" class="py-6 text-center text-steel-muted font-mono-data text-[11px]">搜索中…</div>
          <div v-else-if="searchQ.trim() && !searchRes.length" class="py-6 text-center text-steel-muted font-mono-data text-[11px]">未找到用户</div>
          <div v-else-if="!searchQ.trim()" class="py-6 text-center text-steel-muted font-mono-data text-[11px]">按用户名模糊搜索</div>
          <div
            v-for="u in searchRes"
            :key="u.id"
            class="flex items-center justify-between p-2 rounded-lg hover:bg-card-navy-high/60 transition-colors"
          >
            <div class="flex items-center gap-2.5 truncate">
              <div class="w-8 h-8 rounded-full bg-card-navy-high border border-hairline flex items-center justify-center font-mono-data text-xs text-ink-white flex-shrink-0">
                {{ avatarOf(u.nickname || u.username) }}
              </div>
              <div class="flex flex-col truncate">
                <span class="text-xs font-headline-sm text-ink-white truncate">{{ u.nickname || u.username }}</span>
                <span class="text-[10px] font-mono-data text-steel-muted">@{{ u.username }}</span>
              </div>
            </div>
            <div class="flex-shrink-0">
              <button
                v-if="u.relation === 'none'"
                class="px-2 py-1 rounded bg-primary-container/20 border border-primary-container/40 text-primary-container text-[11px] font-headline-sm hover:bg-primary-container/30 transition-colors disabled:opacity-40"
                :disabled="friendBusy === u.id"
                @click="sendFriendReq(u)"
              >加好友</button>
              <button
                v-else-if="u.relation === 'friend'"
                class="px-2 py-1 rounded bg-primary-container/20 border border-primary-container/40 text-primary-container text-[11px] font-headline-sm hover:bg-primary-container/30 transition-colors"
                @click="chatWith(u)"
              >发消息</button>
              <button
                v-else-if="u.relation === 'incoming'"
                class="px-2 py-1 rounded bg-bull-green/15 border border-bull-green/40 text-bull-green text-[11px] font-headline-sm hover:bg-bull-green/25 transition-colors"
                @click="friendTab = 'requests'"
              >去处理</button>
              <span v-else class="text-[11px] font-mono-data text-steel-muted">{{ RELATION_LABEL[u.relation] }}</span>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- 创建群聊弹窗 -->
    <div v-if="groupModal" class="fixed inset-0 z-50 bg-black/60 flex items-center justify-center p-4" @click.self="groupModal = false">
      <div class="w-96 max-w-full bg-card-navy border border-hairline rounded-xl shadow-xl flex flex-col overflow-hidden" style="max-height: 70vh">
        <div class="flex items-center justify-between px-4 py-3 border-b border-hairline">
          <span class="text-xs font-headline-sm tracking-wider text-steel-muted uppercase flex items-center gap-1.5">
            <span class="material-symbols-outlined text-[15px] text-primary-container">group_add</span>
            创建群聊
          </span>
          <button class="text-steel-muted hover:text-ink-white transition-colors" @click="groupModal = false">
            <span class="material-symbols-outlined text-[18px]">close</span>
          </button>
        </div>
        <div class="p-3 border-b border-hairline">
          <input
            v-model="groupName"
            type="text"
            maxlength="32"
            class="w-full bg-card-navy-high border border-hairline rounded-lg px-3 py-2 text-xs text-ink-white placeholder-steel-muted focus:outline-none focus:border-primary-container transition-colors"
            placeholder="群名称 (必填, 最长 32 字)"
            @keydown.enter="submitGroup"
          />
        </div>
        <div class="flex-1 overflow-y-auto p-3 space-y-1">
          <div class="px-1 pb-1 text-[10px] font-mono-data text-steel-muted uppercase">选择好友 ({{ groupSel.size }} 已选)</div>
          <div v-if="!friends.length" class="py-8 text-center text-steel-muted font-mono-data text-[11px]">暂无好友, 也可以先建空群</div>
          <button
            v-for="f in friends"
            :key="f.id"
            class="w-full flex items-center justify-between p-2 rounded-lg transition-colors"
            :class="groupSel.has(f.id) ? 'bg-primary-container/15 border border-primary-container/40' : 'hover:bg-card-navy-high/60 border border-transparent'"
            @click="toggleSetMember(groupSel, f.id)"
          >
            <div class="flex items-center gap-2.5 truncate">
              <div class="w-8 h-8 rounded-full bg-card-navy-high border border-hairline flex items-center justify-center font-mono-data text-xs text-ink-white flex-shrink-0">
                {{ avatarOf(friendName(f)) }}
              </div>
              <span class="text-xs font-headline-sm text-ink-white truncate">{{ friendName(f) }}</span>
            </div>
            <span
              class="material-symbols-outlined text-[16px] flex-shrink-0"
              :class="groupSel.has(f.id) ? 'text-primary-container' : 'text-steel-muted/40'"
            >{{ groupSel.has(f.id) ? 'check_circle' : 'radio_button_unchecked' }}</span>
          </button>
        </div>
        <div class="p-3 border-t border-hairline flex justify-end">
          <button
            class="flex items-center gap-1.5 bg-primary-container hover:bg-inverse-primary text-ink-white px-4 py-1.5 rounded-lg text-xs font-headline-sm transition-colors disabled:opacity-40"
            :disabled="!groupName.trim() || groupBusy"
            @click="submitGroup"
          >{{ groupBusy ? '创建中…' : '创建群聊' }}</button>
        </div>
      </div>
    </div>

    <!-- 邀请好友进群弹窗 -->
    <div v-if="addMemberModal" class="fixed inset-0 z-50 bg-black/60 flex items-center justify-center p-4" @click.self="addMemberModal = false">
      <div class="w-96 max-w-full bg-card-navy border border-hairline rounded-xl shadow-xl flex flex-col overflow-hidden" style="max-height: 70vh">
        <div class="flex items-center justify-between px-4 py-3 border-b border-hairline">
          <span class="text-xs font-headline-sm tracking-wider text-steel-muted uppercase flex items-center gap-1.5">
            <span class="material-symbols-outlined text-[15px] text-primary-container">person_add</span>
            邀请好友进群
          </span>
          <button class="text-steel-muted hover:text-ink-white transition-colors" @click="addMemberModal = false">
            <span class="material-symbols-outlined text-[18px]">close</span>
          </button>
        </div>
        <div class="flex-1 overflow-y-auto p-3 space-y-1">
          <div v-if="!addCandidates.length" class="py-8 text-center text-steel-muted font-mono-data text-[11px]">没有可邀请的好友 (好友都已在群内)</div>
          <button
            v-for="f in addCandidates"
            :key="f.id"
            class="w-full flex items-center justify-between p-2 rounded-lg transition-colors"
            :class="addSel.has(f.id) ? 'bg-primary-container/15 border border-primary-container/40' : 'hover:bg-card-navy-high/60 border border-transparent'"
            @click="toggleSetMember(addSel, f.id)"
          >
            <div class="flex items-center gap-2.5 truncate">
              <div class="w-8 h-8 rounded-full bg-card-navy-high border border-hairline flex items-center justify-center font-mono-data text-xs text-ink-white flex-shrink-0">
                {{ avatarOf(friendName(f)) }}
              </div>
              <span class="text-xs font-headline-sm text-ink-white truncate">{{ friendName(f) }}</span>
            </div>
            <span
              class="material-symbols-outlined text-[16px] flex-shrink-0"
              :class="addSel.has(f.id) ? 'text-primary-container' : 'text-steel-muted/40'"
            >{{ addSel.has(f.id) ? 'check_circle' : 'radio_button_unchecked' }}</span>
          </button>
        </div>
        <div class="p-3 border-t border-hairline flex justify-end">
          <button
            class="flex items-center gap-1.5 bg-primary-container hover:bg-inverse-primary text-ink-white px-4 py-1.5 rounded-lg text-xs font-headline-sm transition-colors disabled:opacity-40"
            :disabled="!addSel.size || addBusy"
            @click="submitAddMembers"
          >{{ addBusy ? '添加中…' : `添加 ${addSel.size || ''} 人` }}</button>
        </div>
      </div>
    </div>
  </div>
</template>
