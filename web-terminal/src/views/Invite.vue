<script setup>
import { computed, onMounted, ref } from 'vue'
import { inviteApi, settlementApi } from '../api'
import { fmtNum, fmtDateTime, ts } from '../utils/format'

const invite = ref(null)
const summary = ref(null)
const commissions = ref([])
const loading = ref(true)
const err = ref('')

const bindCode = ref('')
const binding = ref(false)
const bindErr = ref('')
const bindOk = ref('')

const codeCopied = ref(false)
const linkCopied = ref(false)

const inviteCode = computed(() => invite.value?.invite_code || '--')
// 统一走落地页: 按设备引导到 PC / 移动端
const inviteLink = computed(() =>
  invite.value?.invite_code
    ? `https://app.mingcevip.com/?invite=${invite.value.invite_code}`
    : '',
)
const canBind = computed(() => !!invite.value?.can_bind)
const genAmount = (g) => summary.value?.by_gen?.find((x) => x.gen === g)

async function load() {
  loading.value = true
  err.value = ''
  try {
    const [i, s, c] = await Promise.allSettled([
      inviteApi.me(),
      settlementApi.commissionsSummary(),
      settlementApi.commissions(),
    ])
    if (i.status === 'fulfilled') invite.value = i.value
    if (s.status === 'fulfilled') summary.value = s.value
    if (c.status === 'fulfilled') commissions.value = c.value || []
    if (i.status === 'rejected') err.value = i.reason?.message || '邀请信息加载失败'
  } finally {
    loading.value = false
  }
}

async function doBind() {
  const code = bindCode.value.trim().toUpperCase()
  if (!code) { bindErr.value = '请输入邀请码'; return }
  binding.value = true
  bindErr.value = ''
  bindOk.value = ''
  try {
    invite.value = await inviteApi.bind(code)
    bindOk.value = '绑定成功'
    bindCode.value = ''
  } catch (e) {
    bindErr.value = e?.message || '绑定失败, 请稍后重试'
  } finally {
    binding.value = false
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
const copyCode = () => copyText(inviteCode.value, codeCopied)
const copyLink = () => copyText(inviteLink.value, linkCopied)

onMounted(load)
</script>

<template>
  <div class="flex flex-col gap-space-lg w-full max-w-6xl mx-auto">
    <div v-if="loading" class="py-16 text-center text-steel-muted font-mono-data text-mono-data">加载中…</div>
    <div v-else-if="err" class="py-16 text-center text-bear-red font-mono-data text-mono-data">{{ err }}</div>

    <template v-else>
      <!-- 邀请码卡 -->
      <div class="bg-card-navy border border-hairline rounded-xl p-6 relative overflow-hidden">
        <div class="absolute -top-24 -right-16 w-64 h-64 rounded-full bg-primary-container/10 blur-3xl pointer-events-none"></div>
        <div class="flex items-center justify-between mb-5 pb-3 border-b border-hairline">
          <div>
            <h3 class="font-headline-md text-headline-md font-bold text-ink-white tracking-tight flex items-center gap-2">
              <span class="material-symbols-outlined text-primary-container">card_giftcard</span>
              邀请有礼 REFERRAL
            </h3>
            <p class="font-body-md text-body-md text-steel-muted mt-0.5">分享专属链接, 好友注册即绑定, 返佣每日自动结算</p>
          </div>
          <span class="inline-flex items-center gap-1 px-2.5 py-1 rounded bg-primary-container/20 border border-primary-container/40 text-primary font-label-sm text-label-sm font-semibold">
            <span class="material-symbols-outlined text-[13px]">military_tech</span>
            返佣席位
          </span>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
          <!-- 邀请码 -->
          <div class="p-4 rounded-xl bg-surface-slate border border-hairline flex flex-col gap-3">
            <div class="flex items-center justify-between">
              <span class="font-label-sm text-label-sm text-steel-muted uppercase">我的专属邀请码</span>
              <span class="font-label-sm text-[10px] text-bull-green">永久有效</span>
            </div>
            <div class="flex items-center justify-between gap-3 flex-wrap">
              <span class="font-mono-data text-[24px] font-bold text-ink-white tracking-[0.3em] bg-card-navy px-4 py-1.5 rounded border border-hairline">
                {{ inviteCode }}
              </span>
              <button
                class="inline-flex items-center gap-1.5 px-4 py-2 rounded-lg bg-primary-container text-ink-white hover:bg-primary-container/90 transition-all font-body-md text-body-md font-medium"
                @click="copyCode"
              >
                <span class="material-symbols-outlined text-[16px]">{{ codeCopied ? 'check' : 'content_copy' }}</span>
                {{ codeCopied ? '已复制' : '复制邀请码' }}
              </button>
            </div>
            <div class="pt-2 border-t border-hairline/60 flex items-center justify-between gap-3">
              <span class="font-mono-data text-label-sm text-steel-muted truncate">{{ inviteLink || '--' }}</span>
              <button class="shrink-0 font-label-sm text-label-sm text-primary hover:underline" @click="copyLink">
                {{ linkCopied ? '已复制' : '复制专属链接' }}
              </button>
            </div>
          </div>

          <!-- 我的邀请人 / 补绑 -->
          <div class="p-4 rounded-xl bg-surface-slate border border-hairline flex flex-col gap-3">
            <span class="font-label-sm text-label-sm text-steel-muted uppercase">我的邀请人 INVITER</span>
            <div v-if="invite?.inviter_username" class="flex items-center gap-2.5">
              <div class="w-9 h-9 rounded bg-card-navy border border-hairline flex items-center justify-center text-primary-fixed-dim font-mono-data font-bold">
                {{ invite.inviter_username.slice(0, 2).toUpperCase() }}
              </div>
              <div>
                <div class="font-headline-sm text-headline-sm text-ink-white">{{ invite.inviter_username }}</div>
                <div class="font-label-sm text-label-sm text-bull-green flex items-center gap-1">
                  <span class="material-symbols-outlined text-[12px]">check_circle</span>
                  已绑定
                </div>
              </div>
            </div>
            <div v-else-if="canBind" class="flex flex-col gap-2">
              <p class="font-body-md text-[12px] text-steel-muted">还没绑定邀请人? 输入对方邀请码完成绑定:</p>
              <div class="flex items-center gap-2">
                <input
                  v-model="bindCode"
                  class="flex-1 h-9 px-3 bg-card-navy border border-hairline rounded-lg text-ink-white placeholder-steel-muted/60 font-mono-data text-mono-data uppercase focus:border-primary-container focus:ring-1 focus:ring-primary-container focus:outline-none transition-all"
                  placeholder="输入邀请码"
                  @keyup.enter="doBind"
                />
                <button
                  class="h-9 px-4 rounded-lg bg-primary-container text-ink-white hover:bg-primary-container/90 transition-all font-body-md text-body-md font-medium disabled:opacity-60"
                  :disabled="binding"
                  @click="doBind"
                >
                  {{ binding ? '绑定中…' : '绑定' }}
                </button>
              </div>
              <div v-if="bindErr" class="font-body-md text-[12px] text-bear-red flex items-center gap-1">
                <span class="material-symbols-outlined text-[14px]">error</span>{{ bindErr }}
              </div>
              <div v-if="bindOk" class="font-body-md text-[12px] text-bull-green flex items-center gap-1">
                <span class="material-symbols-outlined text-[14px]">check_circle</span>{{ bindOk }}
              </div>
            </div>
            <div v-else class="font-body-md text-body-md text-steel-muted">
              {{ invite?.bind_block_reason || '暂不可绑定邀请人' }}
            </div>
          </div>
        </div>
      </div>

      <!-- 佣金汇总 -->
      <div class="grid grid-cols-2 lg:grid-cols-5 gap-4">
        <div class="col-span-2 lg:col-span-2 p-5 rounded-xl bg-card-navy border border-hairline">
          <div class="flex items-center justify-between mb-2">
            <span class="font-label-sm text-label-sm text-steel-muted">累计返佣</span>
            <span class="material-symbols-outlined text-bull-green text-[18px]">payments</span>
          </div>
          <div>
            <span class="font-mono-data text-[28px] font-bold text-bull-green">${{ fmtNum(summary?.total ?? 0) }}</span>
            <span class="font-label-sm text-label-sm text-steel-muted ml-1">USDT</span>
          </div>
          <div class="font-mono-data text-label-sm text-steel-muted mt-1">今日 +${{ fmtNum(summary?.today ?? 0) }}</div>
        </div>
        <div v-for="g in [1, 2, 3]" :key="g" class="p-5 rounded-xl bg-card-navy border border-hairline">
          <div class="flex items-center justify-between mb-2">
            <span class="font-label-sm text-label-sm text-steel-muted">{{ ['', '一代', '二代', '三代'][g] }}返佣</span>
            <span class="material-symbols-outlined text-steel-muted text-[16px]">group</span>
          </div>
          <div class="font-mono-data text-[20px] font-bold text-ink-white">${{ fmtNum(genAmount(g)?.amount ?? 0) }}</div>
          <div class="font-mono-data text-label-sm text-steel-muted mt-1">{{ genAmount(g)?.count ?? 0 }} 笔</div>
        </div>
      </div>

      <!-- 佣金流水 -->
      <div class="bg-card-navy border border-hairline rounded-xl p-6">
        <div class="flex items-center justify-between mb-5 pb-3 border-b border-hairline">
          <h3 class="font-headline-md text-headline-md font-bold text-ink-white tracking-tight flex items-center gap-2">
            <span class="material-symbols-outlined text-primary-container">receipt_long</span>
            返佣流水 COMMISSIONS
          </h3>
          <span class="font-label-sm text-label-sm text-steel-muted">{{ commissions.length }} 条</span>
        </div>
        <div v-if="!commissions.length" class="py-10 text-center text-steel-muted font-mono-data text-mono-data">
          暂无返佣记录, 邀请好友注册并入金后自动产生
        </div>
        <div v-else class="overflow-x-auto">
          <table class="w-full text-left border-collapse">
            <thead>
              <tr class="border-b border-hairline text-steel-muted font-mono-data text-[11px] uppercase tracking-wider">
                <th class="py-3 px-3 font-semibold">来源下级</th>
                <th class="py-3 px-3 font-semibold">代数</th>
                <th class="py-3 px-3 font-semibold text-right">返佣基数</th>
                <th class="py-3 px-3 font-semibold text-right">比例</th>
                <th class="py-3 px-3 font-semibold text-right">返佣金额</th>
                <th class="py-3 px-3 font-semibold">入账时间</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-hairline font-mono-data text-mono-data">
              <tr v-for="c in commissions" :key="c.id" class="hover:bg-card-navy-high/50 transition-colors">
                <td class="py-3 px-3 text-ink-white font-medium">{{ c.buyer_username || `#${c.buyer_id}` }}</td>
                <td class="py-3 px-3">
                  <span class="text-[11px] bg-surface-slate text-steel-muted px-1.5 py-0.5 rounded border border-hairline">
                    {{ ['', '一代', '二代', '三代'][c.gen] || `${c.gen} 代` }}
                  </span>
                </td>
                <td class="py-3 px-3 text-right text-steel-muted">${{ fmtNum(c.base_amount ?? 0) }}</td>
                <td class="py-3 px-3 text-right text-steel-muted">{{ c.rate }}%</td>
                <td class="py-3 px-3 text-right text-bull-green font-semibold">+${{ fmtNum(c.amount) }}</td>
                <td class="py-3 px-3 text-steel-muted">{{ c.created_at ? fmtDateTime(ts(c.created_at)) : '--' }}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </template>
  </div>
</template>
