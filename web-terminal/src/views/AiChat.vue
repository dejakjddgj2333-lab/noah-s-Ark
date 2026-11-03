<script setup>
// AI 助手: 左对话 (DeepSeek SSE 流式) + 右每日综述卡片
// 对话存 localStorage 按用户分隔, 刷新/重进不丢 (最多留 50 条)
import { onMounted, onBeforeUnmount, ref, nextTick, watch } from 'vue'
import { aiApi } from '../api'
import { useUserStore } from '../store/user'

const store = useUserStore()
const LS_KEY = `ai_chat_${store.user?.id || 'anon'}`
const LS_MAX = 50

const msgs = ref([]) // {role: 'user'|'assistant', content}
const draft = ref('')
const sending = ref(false)
const listEl = ref(null)
let ctrl = null

// 每日综述
const summary = ref(null) // {date, text, cached}
const summaryLoading = ref(true)

const quicks = [
  '今天市场怎么样?',
  'BTC 现在怎么看?',
  '最近有什么重要新闻?',
  '恐慌贪婪指数说明什么?',
]

// 极简 markdown: 转义后支持 **加粗** 和 `代码`
function mdLite(s) {
  const esc = s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
  return esc
    .replace(/`([^`\n]+)`/g, '<code class="px-1 py-0.5 bg-canvas-obsidian rounded text-[11px] font-mono-data">$1</code>')
    .replace(/\*\*([^*]+)\*\*/g, '<strong class="text-ink-white font-semibold">$1</strong>')
    .replace(/\n/g, '<br>')
}

function scrollBottom() {
  nextTick(() => {
    if (listEl.value) listEl.value.scrollTop = listEl.value.scrollHeight
  })
}

// 持久化: 只留最近 LS_MAX 条, 防 localStorage 膨胀
watch(msgs, (v) => {
  try {
    localStorage.setItem(LS_KEY, JSON.stringify(v.slice(-LS_MAX)))
  } catch { /* 存储满/隐私模式, 忽略 */ }
}, { deep: true })

function restore() {
  try {
    const arr = JSON.parse(localStorage.getItem(LS_KEY) || '[]')
    if (Array.isArray(arr)) {
      msgs.value = arr.filter((m) => m && (m.role === 'user' || m.role === 'assistant') && typeof m.content === 'string')
    }
  } catch { /* 坏数据忽略 */ }
}

async function loadSummary() {
  summaryLoading.value = true
  try {
    const res = await aiApi.dailySummary()
    summary.value = res?.text ? res : null
  } catch {
    summary.value = null
  } finally {
    summaryLoading.value = false
  }
}

async function send(text) {
  const content = (text ?? draft.value).trim()
  if (!content || sending.value) return
  msgs.value.push({ role: 'user', content })
  msgs.value.push({ role: 'assistant', content: '' })
  draft.value = ''
  sending.value = true
  scrollBottom()
  ctrl = new AbortController()
  // 历史不含刚推入的两条, 最多 5 轮
  const history = msgs.value.slice(0, -2).slice(-10).map((m) => ({ role: m.role, content: m.content }))
  try {
    await aiApi.chatStream({ message: content, history, signal: ctrl.signal }, (piece) => {
      msgs.value[msgs.value.length - 1].content += piece
      scrollBottom()
    })
  } catch (e) {
    if (e?.name !== 'AbortError') {
      const last = msgs.value[msgs.value.length - 1]
      last.content = last.content || `(连接失败: ${e.message})`
    }
  } finally {
    sending.value = false
    ctrl = null
  }
}

function stop() {
  ctrl?.abort()
}

function clearAll() {
  if (sending.value) return
  msgs.value = []
}

function onKey(e) {
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault()
    send()
  }
}

onMounted(() => {
  restore()
  scrollBottom()
  loadSummary()
})
onBeforeUnmount(() => ctrl?.abort())
</script>

<template>
  <div class="flex gap-3 overflow-hidden" style="height: calc(100vh - 56px - 72px)">
    <!-- 左: AI 对话 -->
    <section class="flex-1 min-w-0 bg-card-navy border border-hairline rounded-xl flex flex-col overflow-hidden">
      <div class="px-4 py-2.5 border-b border-hairline flex items-center gap-2 flex-shrink-0">
        <span class="material-symbols-outlined text-[16px] text-primary-container">smart_toy</span>
        <span class="text-sm font-semibold text-ink-white">明策 AI 助手</span>
        <span class="font-mono-data text-[11px] text-steel-muted">数据实时注入 · AI 只做解读</span>
        <button
          class="ml-auto text-steel-muted hover:text-ink-white transition-colors disabled:opacity-40"
          title="清空对话"
          :disabled="sending || !msgs.length"
          @click="clearAll"
        >
          <span class="material-symbols-outlined text-[16px]">delete_sweep</span>
        </button>
      </div>

      <div ref="listEl" class="flex-1 min-h-0 overflow-y-auto px-4 py-3 space-y-3">
        <!-- 空状态 -->
        <div v-if="!msgs.length" class="h-full flex flex-col items-center justify-center gap-3">
          <span class="material-symbols-outlined text-[40px] text-primary-container/60">smart_toy</span>
          <div class="text-sm text-ink-white">问点什么吧</div>
          <div class="text-[12px] text-steel-muted">行情、指标、新闻都在它脑子里 (实时注入)</div>
          <div class="flex flex-wrap justify-center gap-2 mt-2 max-w-lg">
            <button
              v-for="q in quicks"
              :key="q"
              class="px-3 py-1.5 text-[12px] text-steel-muted bg-canvas-obsidian border border-hairline rounded-lg hover:text-ink-white hover:border-primary-container/60 transition-colors"
              @click="send(q)"
            >{{ q }}</button>
          </div>
        </div>

        <!-- 消息 -->
        <div v-for="(m, i) in msgs" :key="i" class="flex" :class="m.role === 'user' ? 'justify-end' : 'justify-start'">
          <div
            class="max-w-[78%] px-3.5 py-2.5 rounded-xl text-[14px] leading-relaxed break-words"
            :class="m.role === 'user'
              ? 'bg-primary-container/20 text-ink-white border border-primary-container/40 rounded-br-sm'
              : 'bg-canvas-obsidian text-steel-muted border border-hairline rounded-bl-sm'"
          >
            <span v-if="m.role === 'assistant' && !m.content && sending && i === msgs.length - 1" class="font-mono-data text-[12px] animate-pulse">思考中…</span>
            <span v-else-if="m.role === 'assistant'" v-html="mdLite(m.content)"></span>
            <span v-else class="whitespace-pre-wrap">{{ m.content }}</span>
          </div>
        </div>
      </div>

      <!-- 输入区 -->
      <div class="flex-shrink-0 border-t border-hairline p-3">
        <div class="flex items-end gap-2">
          <textarea
            v-model="draft"
            rows="1"
            placeholder="问行情、问指标、问新闻… (Enter 发送, Shift+Enter 换行)"
            class="flex-1 resize-none bg-canvas-obsidian border border-hairline rounded-lg px-3 py-2 text-[13px] text-ink-white placeholder:text-steel-muted/50 focus:outline-none focus:border-primary-container/60 min-h-[38px]"
            @keydown="onKey"
          ></textarea>
          <button
            v-if="sending"
            class="h-[38px] px-3.5 bg-bear-red/20 text-bear-red border border-bear-red/40 rounded-lg text-[12px] font-semibold hover:bg-bear-red/30 transition-colors flex items-center gap-1"
            @click="stop"
          >
            <span class="material-symbols-outlined text-[15px]">stop</span>
            <span>停止</span>
          </button>
          <button
            v-else
            class="h-[38px] px-3.5 bg-primary-container hover:bg-inverse-primary text-ink-white rounded-lg text-[12px] font-bold transition-colors flex items-center gap-1 disabled:opacity-40"
            :disabled="!draft.trim()"
            @click="send()"
          >
            <span class="material-symbols-outlined text-[15px]">send</span>
            <span>发送</span>
          </button>
        </div>
        <div class="mt-1.5 text-[11px] text-steel-muted/60 font-mono-data">AI 解读仅供参考, 不构成投资建议</div>
      </div>
    </section>

    <!-- 右: 每日市场综述 -->
    <section class="w-80 flex-shrink-0 bg-card-navy border border-hairline rounded-xl hidden lg:flex flex-col overflow-hidden">
      <div class="px-4 py-2.5 border-b border-hairline flex items-center gap-2 flex-shrink-0">
        <span class="material-symbols-outlined text-[16px] text-primary-container">today</span>
        <span class="text-sm font-semibold text-ink-white">今日市场综述</span>
        <span v-if="summary?.cached" class="ml-auto font-mono-data text-[9px] px-1 py-0.5 bg-canvas-obsidian border border-hairline rounded text-steel-muted">已缓存</span>
        <button
          class="text-steel-muted hover:text-ink-white transition-colors"
          :class="summary?.cached ? '' : 'ml-auto'"
          title="刷新"
          @click="loadSummary"
        >
          <span class="material-symbols-outlined text-[15px]">refresh</span>
        </button>
      </div>
      <div class="flex-1 min-h-0 overflow-y-auto p-4">
        <div v-if="summaryLoading" class="py-6 text-center text-steel-muted font-mono-data text-[11px] animate-pulse">AI 生成中, 稍候…</div>
        <template v-else-if="summary">
          <div class="font-mono-data text-[11px] text-steel-muted mb-2">{{ summary.date }}</div>
          <div class="text-[13px] leading-relaxed text-steel-muted" v-html="mdLite(summary.text)"></div>
        </template>
        <div v-else class="py-6 text-center text-steel-muted font-mono-data text-[11px]">综述暂不可用</div>
      </div>
      <div class="flex-shrink-0 px-4 py-2 border-t border-hairline text-[11px] text-steel-muted/60 font-mono-data">每天首次访问生成一次, 全日共享</div>
    </section>
  </div>
</template>
