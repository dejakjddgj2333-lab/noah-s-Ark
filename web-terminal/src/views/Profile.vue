<script setup>
import { computed, onMounted, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import { useUserStore } from '../store/user'
import { authApi, inviteApi, settlementApi } from '../api'
import { fmtNum, fmtDateTime, ts } from '../utils/format'

const router = useRouter()
const store = useUserStore()
const invite = ref(null)
const summary = ref({})
const devices = ref([])

const pwd = ref({ old_password: '', new_password: '', confirm: '' })
const pwdMsg = ref('')
const pwdErr = ref('')
const pwdSubmitting = ref(false)
const showPwdModal = ref(false)
const copied = ref(false)
const linkCopied = ref(false)
const uidCopied = ref(false)

// 偏好设置 (本地, localStorage 持久化)
const PREFS_KEY = 'prefs'
const savedPrefs = (() => {
  try { return JSON.parse(localStorage.getItem(PREFS_KEY) || '{}') } catch { return {} }
})()
const lang = ref(savedPrefs.lang || 'zh')
const colorScheme = ref(savedPrefs.colorScheme || 'intl')
const notif = ref({ market: true, whale: true, system: false, ...(savedPrefs.notif || {}) })

watch([lang, colorScheme, notif], () => {
  try {
    localStorage.setItem(PREFS_KEY, JSON.stringify({
      lang: lang.value,
      colorScheme: colorScheme.value,
      notif: { ...notif.value },
    }))
  } catch { /* 存储不可用则忽略 */ }
}, { deep: true })

const inviteCode = computed(() => invite.value?.invite_code || invite.value?.code || '--')
const inviteLink = computed(() =>
  inviteCode.value === '--' ? '' : `${location.origin}/register?invite=${inviteCode.value}`,
)
const invitedCount = computed(() => invite.value?.invited_count ?? invite.value?.invite_count ?? '--')
const totalCommission = computed(() => summary.value.total_commission ?? summary.value.total ?? 0)

const displayName = computed(() => store.user?.nickname || store.user?.username || '--')
const avatarChar = computed(() => (displayName.value[0] || 'M').toUpperCase())
const regTime = computed(() => {
  const t = ts(store.user?.created_at)
  return t ? fmtDateTime(t) : '--'
})

async function load() {
  const [i, s, d] = await Promise.allSettled([
    inviteApi.me(),
    settlementApi.commissionsSummary(),
    authApi.devices(),
  ])
  if (i.status === 'fulfilled') invite.value = i.value
  if (s.status === 'fulfilled') summary.value = s.value
  if (d.status === 'fulfilled') devices.value = d.value || []
  store.fetchMe().catch(() => {})
}

function openPwdModal() {
  pwdErr.value = ''
  pwd.value = { old_password: '', new_password: '', confirm: '' }
  showPwdModal.value = true
}

function closePwdModal() {
  if (pwdSubmitting.value) return
  showPwdModal.value = false
}

async function changePwd() {
  pwdErr.value = ''
  if (!pwd.value.old_password) { pwdErr.value = '请输入当前密码'; return }
  if (pwd.value.new_password.length < 8) { pwdErr.value = '新密码至少 8 位'; return }
  if (pwd.value.new_password !== pwd.value.confirm) { pwdErr.value = '两次新密码不一致'; return }
  pwdSubmitting.value = true
  try {
    await authApi.changePassword(pwd.value.old_password, pwd.value.new_password)
    pwd.value = { old_password: '', new_password: '', confirm: '' }
    showPwdModal.value = false
    pwdMsg.value = '密码已修改'
    setTimeout(() => (pwdMsg.value = ''), 3000)
  } catch (e) {
    pwdErr.value = e?.message || '修改失败, 请稍后重试'
  } finally {
    pwdSubmitting.value = false
  }
}

async function copyText(text, flag) {
  if (!text) return
  try {
    await navigator.clipboard.writeText(text)
    flag.value = true
    setTimeout(() => (flag.value = false), 1500)
  } catch { /* 剪贴板不可用则忽略 */ }
}
const copyCode = () => copyText(inviteCode.value, copied)
const copyLink = () => copyText(inviteLink.value, linkCopied)
const copyUid = () => copyText(String(store.user?.id || ''), uidCopied)

function logout() {
  store.logout()
  router.push('/login')
}

onMounted(load)
</script>

<template>
  <div class="flex flex-col gap-space-lg">
    <div class="grid grid-cols-12 gap-5">
      <!-- LEFT COLUMN: Profile & Terminal Credentials Card -->
      <div class="col-span-12 lg:col-span-4 xl:col-span-3">
        <div class="bg-card-navy border border-hairline rounded-xl p-6 sticky top-20">
          <!-- Header Avatar & Badges -->
          <div class="flex flex-col items-center text-center pb-5 border-b border-hairline">
            <div class="relative mb-3">
              <div class="w-16 h-16 rounded-full bg-card-navy-high border-2 border-primary-container/80 flex items-center justify-center text-primary font-headline-lg font-bold shadow-inner">
                {{ avatarChar }}
              </div>
              <div class="absolute -bottom-1 -right-1 w-5 h-5 rounded-full bg-surface-slate border border-hairline flex items-center justify-center" title="在线状态">
                <span class="w-2.5 h-2.5 rounded-full bg-bull-green"></span>
              </div>
            </div>
            <div class="flex items-center gap-2 mb-1">
              <h2 class="font-headline-md text-headline-md font-bold text-ink-white tracking-tight">{{ displayName }}</h2>
              <div class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full bg-primary-container/15 border border-primary-container/40 text-primary font-label-sm text-[10px] font-semibold">
                <span class="material-symbols-outlined text-[12px]">verified</span>
                PRO 会员
              </div>
            </div>
            <span class="font-mono-data text-label-sm text-steel-muted mb-3">MINGCE Terminal User</span>
            <!-- UID Row with copy -->
            <div class="w-full flex items-center justify-between px-3 py-1.5 rounded-lg bg-surface-slate border border-hairline">
              <span class="font-label-sm text-label-sm text-steel-muted">UID:</span>
              <div class="flex items-center gap-1.5">
                <span class="font-mono-data text-mono-data text-ink-white font-semibold">{{ store.user?.id ?? '--' }}</span>
                <button class="text-steel-muted hover:text-ink-white transition-colors" title="复制 UID" @click="copyUid">
                  <span class="material-symbols-outlined text-[15px]">{{ uidCopied ? 'check' : 'content_copy' }}</span>
                </button>
              </div>
            </div>
          </div>
          <!-- Detailed Specifications / Security Rows -->
          <div class="py-4 space-y-3 border-b border-hairline">
            <div class="flex items-center justify-between">
              <span class="font-body-md text-body-md text-steel-muted">邮箱认证</span>
              <div class="flex items-center gap-1.5">
                <span class="font-mono-data text-label-sm text-ink-white">{{ store.user?.email || '--' }}</span>
                <span class="inline-flex items-center gap-0.5 px-1.5 py-0.2 rounded bg-bull-green/10 text-bull-green font-label-sm text-[10px] border border-bull-green/20">
                  <span class="material-symbols-outlined text-[11px]">check_circle</span>
                  已验证
                </span>
              </div>
            </div>
            <div class="flex items-center justify-between">
              <span class="font-body-md text-body-md text-steel-muted">两步验证</span>
              <span
                class="inline-flex items-center gap-0.5 px-1.5 py-0.2 rounded font-label-sm text-[10px] border"
                :class="store.user?.has_2fa ? 'bg-bull-green/10 text-bull-green border-bull-green/20' : 'bg-amber-warn/10 text-amber-warn border-amber-warn/20'"
              >
                <span class="material-symbols-outlined text-[11px]">{{ store.user?.has_2fa ? 'check_circle' : 'warning' }}</span>
                {{ store.user?.has_2fa ? '已绑定' : '未绑定' }}
              </span>
            </div>
            <div class="flex items-center justify-between">
              <span class="font-body-md text-body-md text-steel-muted">终端会话</span>
              <div class="flex items-center gap-1 font-mono-data text-label-sm text-steel-muted">
                <span class="material-symbols-outlined text-[13px] text-bull-green">lock</span>
                AES-256 GCM
              </div>
            </div>
            <div class="flex items-center justify-between">
              <span class="font-body-md text-body-md text-steel-muted">注册时间</span>
              <span class="font-mono-data text-label-sm text-steel-muted">{{ regTime }}</span>
            </div>
          </div>
          <!-- Security Score Indicator -->
          <div class="pt-4 pb-2">
            <div class="flex justify-between items-center mb-1.5">
              <span class="font-label-sm text-label-sm text-steel-muted uppercase tracking-wider">安全防护评级</span>
              <span class="font-mono-data text-label-sm text-bull-green font-bold">高风险防御 (94/100)</span>
            </div>
            <div class="w-full h-1.5 bg-surface-slate rounded-full overflow-hidden border border-hairline">
              <div class="h-full bg-bull-green rounded-full" style="width: 94%;"></div>
            </div>
          </div>
          <!-- Actions: Logout -->
          <div class="mt-6 pt-4 border-t border-hairline space-y-2">
            <button
              class="w-full flex items-center justify-center gap-2 py-2 px-3 rounded-lg bg-transparent text-steel-muted hover:text-bear-red transition-colors font-body-md text-body-md"
              @click="logout"
            >
              <span class="material-symbols-outlined text-[16px]">power_settings_new</span>
              退出当前登录会话
            </button>
          </div>
        </div>
      </div>

      <!-- RIGHT BROAD COLUMN -->
      <div class="col-span-12 lg:col-span-8 xl:col-span-9 space-y-5">
        <!-- CARD 1: 账户安全 ACCOUNT SECURITY -->
        <div class="bg-card-navy border border-hairline rounded-xl p-6">
          <div class="flex items-center justify-between mb-5 pb-3 border-b border-hairline">
            <div>
              <h3 class="font-headline-md text-headline-md font-bold text-ink-white tracking-tight flex items-center gap-2">
                <span class="material-symbols-outlined text-primary-container">shield</span>
                账户安全 ACCOUNT SECURITY
              </h3>
              <p class="font-body-md text-body-md text-steel-muted mt-0.5">管理密码凭证、双因素身份校验与关键风险拦截</p>
            </div>
            <span class="px-2.5 py-1 rounded bg-surface-slate border border-hairline font-label-sm text-label-sm text-steel-muted">
              2FA 强制鉴权模式
            </span>
          </div>
          <div class="divide-y divide-hairline">
            <!-- Row 1: Login Password -->
            <div class="py-3.5">
              <div class="flex items-center justify-between gap-4">
                <div class="flex items-center gap-3">
                  <div class="w-9 h-9 rounded-lg bg-surface-slate border border-hairline flex items-center justify-center text-steel-muted">
                    <span class="material-symbols-outlined">key</span>
                  </div>
                  <div>
                    <div class="font-headline-sm text-headline-sm text-ink-white">登录密码</div>
                    <div class="font-body-md text-[12px] text-steel-muted">定期更新保障资本安全</div>
                  </div>
                </div>
                <div class="flex items-center gap-4">
                  <span class="font-label-sm text-label-sm text-steel-muted">已设置</span>
                  <span v-if="pwdMsg" class="font-body-md text-[12px] text-bull-green flex items-center gap-1">
                    <span class="material-symbols-outlined text-[14px]">check_circle</span>
                    {{ pwdMsg }}
                  </span>
                  <button
                    class="px-3 py-1.5 rounded-lg bg-surface-slate border border-hairline text-primary hover:text-ink-white hover:border-primary-container/80 transition-all font-body-md text-body-md"
                    @click="openPwdModal"
                  >
                    修改
                  </button>
                </div>
              </div>
            </div>
            <!-- Row 2: Google TOTP -->
            <div class="py-3.5 flex items-center justify-between gap-4">
              <div class="flex items-center gap-3">
                <div class="w-9 h-9 rounded-lg bg-surface-slate border border-hairline flex items-center justify-center text-primary">
                  <span class="material-symbols-outlined">security_update_good</span>
                </div>
                <div>
                  <div class="font-headline-sm text-headline-sm text-ink-white">谷歌验证 (TOTP)</div>
                  <div class="font-body-md text-[12px] text-steel-muted">用于出金划转、敏感配置调控与新设备准入鉴权</div>
                </div>
              </div>
              <div class="flex items-center gap-4">
                <span
                  class="inline-flex items-center gap-1 px-2 py-0.5 rounded border font-label-sm text-label-sm font-semibold"
                  :class="store.user?.has_2fa ? 'bg-bull-green/10 border-bull-green/30 text-bull-green' : 'bg-amber-warn/10 border-amber-warn/30 text-amber-warn'"
                >
                  <span class="material-symbols-outlined text-[12px]">{{ store.user?.has_2fa ? 'check_circle' : 'warning' }}</span>
                  {{ store.user?.has_2fa ? '已绑定' : '未绑定' }}
                </span>
              </div>
            </div>
            <!-- Row 3: Anti-Phishing Code -->
            <div class="py-3.5 flex items-center justify-between gap-4">
              <div class="flex items-center gap-3">
                <div class="w-9 h-9 rounded-lg bg-surface-slate border border-hairline flex items-center justify-center text-amber-warn">
                  <span class="material-symbols-outlined">phishing</span>
                </div>
                <div>
                  <div class="font-headline-sm text-headline-sm text-ink-white">防钓鱼码 ANTI-PHISHING</div>
                  <div class="font-body-md text-[12px] text-steel-muted">确认所有官方系统邮件与推送签名的专属明策防伪标识</div>
                </div>
              </div>
              <div class="flex items-center gap-4">
                <span class="inline-flex items-center gap-1 px-2 py-0.5 rounded bg-amber-warn/10 border border-amber-warn/30 text-amber-warn font-label-sm text-label-sm font-medium">
                  <span class="material-symbols-outlined text-[12px]">warning</span>
                  未设置 (推荐开启)
                </span>
                <button
                  class="px-3 py-1.5 rounded-lg bg-card-navy border border-hairline text-steel-muted font-body-md text-body-md cursor-not-allowed opacity-60"
                  disabled
                  title="请前往明策 App 设置"
                >
                  立即设置
                </button>
              </div>
            </div>
            <!-- Row 4: Audit Logs Micro Terminal Strip -->
            <div class="pt-3.5 pb-1 flex flex-col md:flex-row md:items-center justify-between gap-3 bg-card-navy-high/40 p-3 rounded-lg border border-hairline/60">
              <div class="flex items-center gap-2 flex-wrap">
                <span class="material-symbols-outlined text-steel-muted text-[16px]">receipt_long</span>
                <span class="font-label-sm text-label-sm text-steel-muted uppercase">最近鉴权审计:</span>
                <span class="font-mono-data text-mono-data text-ink-white">IP {{ (devices.find((d) => d.current) || devices[0] || {}).ip || '--' }}</span>
                <span class="font-mono-data text-label-sm text-bull-green">[成功 SUCCESS]</span>
              </div>
              <span class="font-label-sm text-label-sm text-steel-muted flex items-center gap-1">
                共 {{ devices.length }} 台已鉴权设备
              </span>
            </div>
          </div>
        </div>

        <!-- CARD 2: 偏好设置 PREFERENCES -->
        <div class="bg-card-navy border border-hairline rounded-xl p-6">
          <div class="flex items-center justify-between mb-5 pb-3 border-b border-hairline">
            <div>
              <h3 class="font-headline-md text-headline-md font-bold text-ink-white tracking-tight flex items-center gap-2">
                <span class="material-symbols-outlined text-primary-container">tune</span>
                偏好设置 PREFERENCES
              </h3>
              <p class="font-body-md text-body-md text-steel-muted mt-0.5">定制专属量化操作盘面色彩与实时市场警报规则</p>
            </div>
            <span class="font-label-sm text-label-sm text-steel-muted">已同步至本地配置</span>
          </div>
          <div class="space-y-4">
            <!-- Item 1: Interface Language -->
            <div class="flex items-center justify-between py-2 border-b border-hairline/50">
              <div>
                <div class="font-headline-sm text-headline-sm text-ink-white">界面语言</div>
                <div class="font-body-md text-[12px] text-steel-muted">终端显示语言与数字格式化国际标准</div>
              </div>
              <div class="inline-flex p-1 rounded-lg bg-surface-slate border border-hairline">
                <button
                  class="px-3.5 py-1 rounded font-label-sm text-label-sm transition-all"
                  :class="lang === 'zh' ? 'bg-primary-container text-ink-white font-semibold' : 'text-steel-muted hover:text-ink-white'"
                  @click="lang = 'zh'"
                >
                  中文
                </button>
                <button
                  class="px-3.5 py-1 rounded font-label-sm text-label-sm transition-all"
                  :class="lang === 'en' ? 'bg-primary-container text-ink-white font-semibold' : 'text-steel-muted hover:text-ink-white'"
                  @click="lang = 'en'"
                >
                  EN
                </button>
              </div>
            </div>
            <!-- Item 2: Color Palette -->
            <div class="flex flex-col md:flex-row md:items-center justify-between py-2 border-b border-hairline/50 gap-3">
              <div>
                <div class="font-headline-sm text-headline-sm text-ink-white">涨跌色彩方案</div>
                <div class="font-body-md text-[12px] text-steel-muted">K线、深度图、持仓收益与多空比率映射色彩</div>
              </div>
              <div class="flex items-center gap-2">
                <div
                  class="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-surface-slate cursor-pointer select-none"
                  :class="colorScheme === 'intl' ? 'border-2 border-primary-container' : 'border border-hairline hover:border-steel-muted/60 text-steel-muted'"
                  @click="colorScheme = 'intl'"
                >
                  <div class="flex items-center gap-1">
                    <span class="w-2.5 h-2.5 rounded-full bg-bull-green"></span>
                    <span class="w-2.5 h-2.5 rounded-full bg-bear-red"></span>
                  </div>
                  <span class="font-body-md text-body-md" :class="{ 'text-ink-white font-medium': colorScheme === 'intl' }">绿涨红跌 (国际)</span>
                  <span v-if="colorScheme === 'intl'" class="material-symbols-outlined text-primary text-[15px]">check</span>
                </div>
                <div
                  class="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-surface-slate cursor-pointer select-none"
                  :class="colorScheme === 'cn' ? 'border-2 border-primary-container' : 'border border-hairline hover:border-steel-muted/60 text-steel-muted'"
                  @click="colorScheme = 'cn'"
                >
                  <div class="flex items-center gap-1">
                    <span class="w-2.5 h-2.5 rounded-full bg-bear-red"></span>
                    <span class="w-2.5 h-2.5 rounded-full bg-bull-green"></span>
                  </div>
                  <span class="font-body-md text-body-md" :class="{ 'text-ink-white font-medium': colorScheme === 'cn' }">红涨绿跌 (国内习惯)</span>
                  <span v-if="colorScheme === 'cn'" class="material-symbols-outlined text-primary text-[15px]">check</span>
                </div>
              </div>
            </div>
            <!-- Notifications Toggle Group -->
            <div class="space-y-3 pt-2">
              <div class="font-label-sm text-label-sm text-steel-muted uppercase tracking-wider">实时推送通道 NOTIFICATIONS</div>
              <div class="flex items-center justify-between p-3 rounded-lg bg-surface-slate/60 border border-hairline">
                <div class="flex items-center gap-3">
                  <span class="material-symbols-outlined text-primary">show_chart</span>
                  <div>
                    <div class="font-headline-sm text-headline-sm text-ink-white">行情异动提醒</div>
                    <div class="font-body-md text-[12px] text-steel-muted">关注币种 15m 振幅超 3% 或急速拉升/下挫推流</div>
                  </div>
                </div>
                <label class="relative inline-flex items-center cursor-pointer">
                  <input v-model="notif.market" class="sr-only peer" type="checkbox" />
                  <div class="w-11 h-6 bg-surface-container-highest peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-ink-white after:border-hairline after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-primary-container"></div>
                </label>
              </div>
              <div class="flex items-center justify-between p-3 rounded-lg bg-surface-slate/60 border border-hairline">
                <div class="flex items-center gap-3">
                  <span class="material-symbols-outlined text-bull-green">water_drop</span>
                  <div>
                    <div class="font-headline-sm text-headline-sm text-ink-white">巨鲸推送 WHALE ALERTS</div>
                    <div class="font-body-md text-[12px] text-steel-muted">&gt;500 BTC 或 $10M 以上链上冷热钱包大额异动流</div>
                  </div>
                </div>
                <label class="relative inline-flex items-center cursor-pointer">
                  <input v-model="notif.whale" class="sr-only peer" type="checkbox" />
                  <div class="w-11 h-6 bg-surface-container-highest peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-ink-white after:border-hairline after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-primary-container"></div>
                </label>
              </div>
              <div class="flex items-center justify-between p-3 rounded-lg bg-surface-slate/60 border border-hairline">
                <div class="flex items-center gap-3">
                  <span class="material-symbols-outlined text-steel-muted">campaign</span>
                  <div>
                    <div class="font-headline-sm text-headline-sm text-ink-white">系统公告与风控披露</div>
                    <div class="font-body-md text-[12px] text-steel-muted">重大版本升级、API 速率限制调整与风控规则披露</div>
                  </div>
                </div>
                <label class="relative inline-flex items-center cursor-pointer">
                  <input v-model="notif.system" class="sr-only peer" type="checkbox" />
                  <div class="w-11 h-6 bg-surface-container-highest peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-steel-muted after:border-hairline after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-primary-container"></div>
                </label>
              </div>
            </div>
          </div>
        </div>

        <!-- CARD 3: 邀请有礼 REFERRAL REWARDS -->
        <div class="bg-card-navy border border-hairline rounded-xl p-6">
          <div class="flex flex-col sm:flex-row sm:items-center justify-between mb-5 pb-3 border-b border-hairline gap-2">
            <div>
              <div class="flex items-center gap-3">
                <h3 class="font-headline-md text-headline-md font-bold text-ink-white tracking-tight flex items-center gap-2">
                  <span class="material-symbols-outlined text-primary-container">card_giftcard</span>
                  邀请有礼 REFERRAL REWARDS
                </h3>
                <span class="inline-flex items-center gap-1 px-2 py-0.5 rounded bg-primary-container/20 border border-primary-container/40 text-primary font-label-sm text-label-sm font-semibold">
                  <span class="material-symbols-outlined text-[13px]">military_tech</span>
                  返佣席位
                </span>
              </div>
              <p class="font-body-md text-body-md text-steel-muted mt-0.5">邀请好友注册，返佣自动结算至账户</p>
            </div>
          </div>
          <div class="grid grid-cols-1 md:grid-cols-12 gap-4 mb-5">
            <!-- Code container (7 cols) -->
            <div class="md:col-span-7 p-4 rounded-xl bg-surface-slate border border-hairline flex flex-col justify-between">
              <div class="flex items-center justify-between mb-2">
                <span class="font-label-sm text-label-sm text-steel-muted uppercase">我的专属邀请码 REFERRAL CODE</span>
                <span class="font-label-sm text-[10px] text-bull-green">永久有效</span>
              </div>
              <div class="flex items-center justify-between gap-3">
                <span class="font-mono-data text-[22px] font-bold text-ink-white tracking-widest bg-card-navy px-3 py-1 rounded border border-hairline">
                  {{ inviteCode }}
                </span>
                <div class="flex items-center gap-2">
                  <button
                    class="inline-flex items-center gap-1 px-3 py-1.5 rounded-lg bg-primary-container text-ink-white hover:bg-secondary-container transition-all font-body-md text-body-md font-medium"
                    @click="copyCode"
                  >
                    <span class="material-symbols-outlined text-[16px]">{{ copied ? 'check' : 'content_copy' }}</span>
                    {{ copied ? '已复制' : '复制邀请码' }}
                  </button>
                </div>
              </div>
              <div class="mt-3 pt-2 border-t border-hairline/60 flex items-center justify-between">
                <span class="font-mono-data text-label-sm text-steel-muted truncate max-w-[280px]">{{ inviteLink || '--' }}</span>
                <button class="font-label-sm text-label-sm text-primary hover:underline" @click="copyLink">
                  {{ linkCopied ? '已复制' : '复制专属链接' }}
                </button>
              </div>
            </div>
            <!-- Metrics Stats Horizontal Bento Cards (5 cols) -->
            <div class="md:col-span-5 grid grid-cols-2 gap-3">
              <div class="p-4 rounded-xl bg-card-navy-high border border-hairline flex flex-col justify-between">
                <div class="flex items-center justify-between">
                  <span class="font-label-sm text-label-sm text-steel-muted">已邀请人数</span>
                  <span class="material-symbols-outlined text-steel-muted text-[16px]">group</span>
                </div>
                <div class="my-1">
                  <span class="font-mono-data text-[26px] font-bold text-ink-white">{{ invitedCount }}</span>
                  <span class="font-body-md text-body-md text-steel-muted ml-1">人</span>
                </div>
                <span class="font-mono-data text-label-sm text-steel-muted">通过专属邀请码注册</span>
              </div>
              <div class="p-4 rounded-xl bg-card-navy-high border border-hairline flex flex-col justify-between">
                <div class="flex items-center justify-between">
                  <span class="font-label-sm text-label-sm text-steel-muted">累计返佣金额</span>
                  <span class="material-symbols-outlined text-bull-green text-[16px]">payments</span>
                </div>
                <div class="my-1">
                  <span class="font-mono-data text-[22px] font-bold text-bull-green">${{ fmtNum(totalCommission) }}</span>
                  <span class="font-label-sm text-label-sm text-steel-muted ml-0.5">USDT</span>
                </div>
                <div class="flex items-center justify-between font-mono-data text-label-sm text-steel-muted">
                  <span>结算:</span>
                  <span class="text-ink-white font-medium">每日自动</span>
                </div>
              </div>
            </div>
          </div>
          <div class="flex items-center gap-2 p-3 rounded-lg bg-surface-slate/40 border border-hairline text-steel-muted text-[12px]">
            <span class="material-symbols-outlined text-[16px] text-primary">info</span>
            <span>返佣结算机制：每日 00:00 UTC 自动归集返佣至账户；邀请用户满足 VIP 门槛时可申请提高返佣基准。</span>
          </div>
        </div>

        <!-- CARD 4: 登录设备 DEVICES -->
        <div class="bg-card-navy border border-hairline rounded-xl p-6">
          <div class="flex items-center justify-between mb-5 pb-3 border-b border-hairline">
            <div>
              <h3 class="font-headline-md text-headline-md font-bold text-ink-white tracking-tight flex items-center gap-2">
                <span class="material-symbols-outlined text-primary-container">devices</span>
                登录设备 DEVICES
              </h3>
              <p class="font-body-md text-body-md text-steel-muted mt-0.5">当前账号所有已鉴权终端会话清单</p>
            </div>
            <span class="px-2.5 py-1 rounded bg-surface-slate border border-hairline font-label-sm text-label-sm text-steel-muted">
              {{ devices.length }} 台设备
            </span>
          </div>
          <div v-if="!devices.length" class="py-6 text-center text-steel-muted font-mono-data text-mono-data">暂无记录</div>
          <div v-else class="overflow-x-auto">
            <table class="w-full text-left border-collapse">
              <thead>
                <tr class="border-b border-hairline text-steel-muted font-mono-data text-[11px] uppercase tracking-wider">
                  <th class="py-3 px-3 font-semibold">设备 (Device)</th>
                  <th class="py-3 px-3 font-semibold">平台 (Platform)</th>
                  <th class="py-3 px-3 font-semibold">IP 地址</th>
                  <th class="py-3 px-3 font-semibold">最近活跃 (Last Seen)</th>
                  <th class="py-3 px-3 text-center font-semibold">状态 (Status)</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-hairline font-mono-data text-mono-data">
                <tr v-for="d in devices" :key="d.id" class="hover:bg-card-navy-high/50 transition-colors">
                  <td class="py-3.5 px-3">
                    <div class="flex items-center gap-2">
                      <span class="material-symbols-outlined text-steel-muted text-[16px]">{{ d.platform === 'web' ? 'language' : 'smartphone' }}</span>
                      <span class="text-ink-white font-medium">{{ d.device_name || '未命名设备' }}</span>
                    </div>
                  </td>
                  <td class="py-3.5 px-3">
                    <span class="text-[11px] bg-surface-slate text-steel-muted px-1.5 py-0.5 rounded border border-hairline">{{ d.platform || '--' }}</span>
                  </td>
                  <td class="py-3.5 px-3 text-steel-muted">{{ d.ip || '--' }}</td>
                  <td class="py-3.5 px-3 text-steel-muted">{{ d.last_seen_at ? fmtDateTime(ts(d.last_seen_at)) : '--' }}</td>
                  <td class="py-3.5 px-3 text-center">
                    <span
                      v-if="d.current"
                      class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[11px] bg-bull-green/12 text-bull-green border border-bull-green/20"
                    >
                      <span class="w-1.5 h-1.5 rounded-full bg-bull-green"></span>
                      本设备
                    </span>
                    <span v-else class="text-steel-muted text-[11px]">--</span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>

    <!-- ===== 修改登录密码 Modal ===== -->
    <div
      v-if="showPwdModal"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 px-4"
      @click.self="closePwdModal"
    >
      <div class="w-full max-w-md bg-card-navy border border-hairline rounded-xl p-6 shadow-[0_16px_48px_rgba(0,0,0,0.6)]">
        <div class="flex items-center justify-between mb-5 pb-3 border-b border-hairline">
          <h3 class="font-headline-md text-headline-md font-bold text-ink-white flex items-center gap-2">
            <span class="material-symbols-outlined text-primary-container">key</span>
            修改登录密码
          </h3>
          <button class="text-steel-muted hover:text-ink-white transition-colors" title="关闭" @click="closePwdModal">
            <span class="material-symbols-outlined text-[20px]">close</span>
          </button>
        </div>
        <div class="flex flex-col gap-3">
          <div>
            <label class="font-label-sm text-label-sm text-steel-muted block mb-1">当前密码</label>
            <input
              v-model="pwd.old_password"
              type="password"
              placeholder="请输入当前密码"
              class="w-full bg-surface border border-hairline rounded-lg text-ink-white placeholder-steel-muted/60 text-body-md font-body-md px-3 py-2 focus:border-primary-container focus:ring-1 focus:ring-primary-container focus:outline-none transition-all"
            />
          </div>
          <div>
            <label class="font-label-sm text-label-sm text-steel-muted block mb-1">新密码</label>
            <input
              v-model="pwd.new_password"
              type="password"
              placeholder="新密码 (至少 8 位)"
              class="w-full bg-surface border border-hairline rounded-lg text-ink-white placeholder-steel-muted/60 text-body-md font-body-md px-3 py-2 focus:border-primary-container focus:ring-1 focus:ring-primary-container focus:outline-none transition-all"
            />
          </div>
          <div>
            <label class="font-label-sm text-label-sm text-steel-muted block mb-1">确认新密码</label>
            <input
              v-model="pwd.confirm"
              type="password"
              placeholder="再次输入新密码"
              class="w-full bg-surface border border-hairline rounded-lg text-ink-white placeholder-steel-muted/60 text-body-md font-body-md px-3 py-2 focus:border-primary-container focus:ring-1 focus:ring-primary-container focus:outline-none transition-all"
              @keyup.enter="changePwd"
            />
          </div>
          <div v-if="pwdErr" class="flex items-center gap-1.5 font-body-md text-[12px] text-bear-red bg-bear-red/10 border border-bear-red/30 rounded-lg px-3 py-2">
            <span class="material-symbols-outlined text-[15px]">error</span>
            {{ pwdErr }}
          </div>
          <div class="flex items-center justify-end gap-2 pt-2">
            <button
              class="px-4 py-2 rounded-lg bg-surface-slate border border-hairline text-steel-muted hover:text-ink-white transition-all font-body-md text-body-md"
              :disabled="pwdSubmitting"
              @click="closePwdModal"
            >
              取消
            </button>
            <button
              class="px-4 py-2 rounded-lg bg-primary-container text-ink-white hover:bg-primary-container/90 transition-all font-body-md text-body-md font-medium flex items-center gap-1.5 disabled:opacity-60 disabled:cursor-not-allowed"
              :disabled="pwdSubmitting"
              @click="changePwd"
            >
              <span v-if="pwdSubmitting" class="material-symbols-outlined text-[16px] animate-spin">progress_activity</span>
              {{ pwdSubmitting ? '提交中…' : '确认修改' }}
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
