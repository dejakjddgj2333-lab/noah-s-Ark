<script setup>
import { computed, onMounted, ref } from 'vue'
import { walletApi } from '../api/wallet'
import { fmtNum, fmtDateTime, ts } from '../utils/format'

const ACCOUNTS = [
  { key: 'principal', label: '本金账户', icon: 'account_balance_wallet' },
  { key: 'income', label: '收益账户', icon: 'trending_up' },
]

const account = ref('principal')
const balances = ref({}) // { principal_balance, income_balance, principal_pending, income_pending }
const networks = ref([]) // [{ network, label, network_fee, income_min_amount, income_service_rate }]
const network = ref('')
const address = ref('')
const amount = ref('')
const quote = ref(null)
const quoteLoading = ref(false)
const records = ref([])
const loading = ref(true)
const submitting = ref(false)
const error = ref('')
const ok = ref('')

// 提现状态着色: pending=审核中 / approved=已打款 / rejected=已拒绝
const STATUS = {
  pending: { text: '审核中', cls: 'bg-amber-warn/12 text-amber-warn border-amber-warn/20' },
  approved: { text: '已打款', cls: 'bg-bull-green/12 text-bull-green border-bull-green/20' },
  rejected: { text: '已拒绝', cls: 'bg-bear-red/12 text-bear-red border-bear-red/20' },
}
const statusOf = (s) => STATUS[s] || { text: s || '--', cls: 'bg-card-navy-high text-steel-muted border-hairline' }

const cut = (v) => (v ? `${String(v).slice(0, 8)}…${String(v).slice(-6)}` : '--')
const balOf = (k) => fmtNum(balances.value[`${k}_balance`])
const pendOf = (k) => fmtNum(balances.value[`${k}_pending`])
const curNet = computed(() => networks.value.find((n) => n.network === network.value) || null)
const acctLabel = (k) => (k === 'principal' ? '本金账户' : '收益账户')

// 金额两位小数校验
const amountOk = computed(() => /^\d+(\.\d{1,2})?$/.test(amount.value) && Number(amount.value) > 0)
const amountHint = computed(() => {
  if (!amount.value) return ''
  if (!/^\d+(\.\d{1,2})?$/.test(amount.value)) return '金额最多两位小数'
  if (Number(amount.value) <= 0) return '金额需大于 0'
  return ''
})

let quoteTimer = null
function scheduleQuote() {
  quote.value = null
  clearTimeout(quoteTimer)
  if (!amountOk.value || !network.value) return
  quoteTimer = setTimeout(fetchQuote, 500) // 防抖 500ms
}

async function fetchQuote() {
  if (!amountOk.value || !network.value) return
  quoteLoading.value = true
  try {
    quote.value = await walletApi.quote({ account: account.value, amount: amount.value, network: network.value })
  } catch {
    quote.value = null
  } finally {
    quoteLoading.value = false
  }
}

async function loadBalances() {
  try {
    balances.value = (await walletApi.account()) || {}
  } catch {
    /* 静默 */
  }
}

async function loadNetworks() {
  try {
    const d = await walletApi.withdrawNetworks()
    networks.value = d?.networks || []
    if (!network.value && networks.value.length) network.value = networks.value[0].network
  } catch {
    networks.value = []
  }
}

async function loadRecords() {
  try {
    records.value = (await walletApi.withdrawalRecords()) || []
  } catch {
    /* 静默 */
  }
}

async function load() {
  loading.value = true
  await Promise.all([loadBalances(), loadNetworks(), loadRecords()])
  loading.value = false
}

async function submit() {
  error.value = ''
  ok.value = ''
  if (!address.value.trim()) {
    error.value = '请输入提现地址'
    return
  }
  if (!amountOk.value) {
    error.value = amountHint.value || '请输入有效金额'
    return
  }
  submitting.value = true
  try {
    // 提交前复核一次 quote, 防止费率变动
    const q = await walletApi.quote({ account: account.value, amount: amount.value, network: network.value })
    if (q && quote.value && Number(q.arrive_amount) !== Number(quote.value.arrive_amount)) {
      quote.value = q
      error.value = '费用已变动, 请确认后重新提交'
      return
    }
    quote.value = q || quote.value
    await walletApi.withdraw({
      account: account.value,
      network: network.value,
      address: address.value.trim(),
      amount: amount.value,
      idempotency_key: crypto.randomUUID(),
    })
    ok.value = '提现申请已提交, 等待审核'
    address.value = ''
    amount.value = ''
    quote.value = null
    loadRecords()
    loadBalances()
  } catch (e) {
    error.value = e?.response?.data?.detail || e?.message || '提现失败'
  } finally {
    submitting.value = false
  }
}

onMounted(load)
</script>

<template>
  <div v-if="loading" class="text-steel-muted font-mono-data text-mono-data py-10 text-center">数据加载中…</div>
  <div v-else class="flex flex-col gap-space-lg w-full max-w-4xl mx-auto">
    <!-- ROW 1: 账户选择 -->
    <section class="grid grid-cols-1 md:grid-cols-2 gap-4">
      <button
        v-for="a in ACCOUNTS"
        :key="a.key"
        class="text-left bg-card-navy rounded-xl border p-space-md flex flex-col justify-between transition-colors"
        :class="account === a.key ? 'border-primary-container/70' : 'border-hairline hover:border-hairline/80'"
        @click="account = a.key; scheduleQuote()"
      >
        <div class="flex items-center justify-between text-steel-muted font-mono-data text-label-sm w-full">
          <div class="flex items-center gap-1.5">
            <span class="material-symbols-outlined text-[17px]" :class="account === a.key ? 'text-primary' : 'text-steel-muted'">{{ a.icon }}</span>
            <span class="tracking-wider">{{ a.label }} {{ a.key.toUpperCase() }}</span>
          </div>
          <span
            v-if="account === a.key"
            class="text-[10px] bg-primary-container/15 text-primary px-1.5 py-0.5 rounded border border-primary-container/30"
          >
            已选择
          </span>
        </div>
        <div class="my-2.5">
          <div class="font-mono-data text-[30px] font-bold tracking-tight text-ink-white">${{ balOf(a.key) }}</div>
          <div class="flex items-center gap-2 font-mono-data text-label-sm mt-0.5">
            <span class="text-steel-muted">提现冻结中</span>
            <span class="text-amber-warn font-semibold">${{ pendOf(a.key) }}</span>
          </div>
        </div>
        <div class="pt-2 border-t border-hairline/60 flex items-center justify-between text-label-sm font-mono-data w-full">
          <span class="text-steel-muted">提现来源</span>
          <span class="text-ink-white font-semibold">{{ a.label }}</span>
        </div>
      </button>
    </section>

    <!-- ROW 2: 提现表单 -->
    <section class="bg-card-navy rounded-xl border border-hairline p-space-md flex flex-col gap-4">
      <div class="flex items-center gap-2">
        <span class="text-headline-md font-headline-md font-bold text-ink-white">提现 WITHDRAW</span>
        <span class="text-label-sm font-mono-data text-steel-muted">USDT · 人工审核打款</span>
      </div>

      <!-- 网络选择 -->
      <div>
        <div class="text-[11px] font-mono-data text-steel-muted uppercase tracking-wider mb-2">提现网络</div>
        <div class="grid grid-cols-2 md:grid-cols-4 gap-2">
          <button
            v-for="n in networks"
            :key="n.network"
            class="rounded-lg border p-2.5 text-left transition-colors"
            :class="network === n.network ? 'border-primary-container/70 bg-primary-container/10' : 'border-hairline bg-surface-slate hover:border-hairline/80'"
            @click="network = n.network; scheduleQuote()"
          >
            <div class="font-mono-data text-label-sm font-semibold" :class="network === n.network ? 'text-primary' : 'text-ink-white'">
              {{ n.label || n.network.toUpperCase() }}
            </div>
            <div class="font-mono-data text-[11px] text-steel-muted mt-0.5">
              网络费 {{ fmtNum(n.network_fee) }} USDT
            </div>
            <div v-if="n.income_service_rate != null && account === 'income'" class="font-mono-data text-[11px] text-steel-muted">
              服务费率 {{ (Number(n.income_service_rate) * 100).toFixed(2) }}%
            </div>
          </button>
        </div>
        <div v-if="!networks.length" class="text-steel-muted font-mono-data text-mono-data">暂无可提现网络</div>
      </div>

      <!-- 地址 / 金额 -->
      <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
        <div>
          <div class="text-[11px] font-mono-data text-steel-muted uppercase tracking-wider mb-1.5">提现地址</div>
          <input
            v-model="address"
            class="w-full bg-surface-slate border border-hairline rounded-lg px-3 py-2 font-mono-data text-mono-data text-ink-white placeholder:text-steel-muted focus:outline-none focus:border-primary-container/60"
            placeholder="收款地址"
          />
        </div>
        <div>
          <div class="text-[11px] font-mono-data text-steel-muted uppercase tracking-wider mb-1.5">提现金额 (USDT)</div>
          <input
            v-model="amount"
            inputmode="decimal"
            class="w-full bg-surface-slate border rounded-lg px-3 py-2 font-mono-data text-mono-data text-ink-white placeholder:text-steel-muted focus:outline-none"
            :class="amountHint ? 'border-bear-red/60 focus:border-bear-red/60' : 'border-hairline focus:border-primary-container/60'"
            placeholder="0.00"
            @input="scheduleQuote"
          />
          <div v-if="amountHint" class="text-bear-red font-mono-data text-[11px] mt-1">{{ amountHint }}</div>
        </div>
      </div>

      <!-- 费用试算 -->
      <div v-if="quoteLoading" class="text-steel-muted font-mono-data text-label-sm">费用试算中…</div>
      <div v-else-if="quote" class="bg-surface-slate border border-hairline rounded-lg p-3 font-mono-data text-label-sm">
        <div class="flex justify-between text-steel-muted">
          <span>服务费</span><span class="text-ink-white">{{ fmtNum(quote.service_fee) }} USDT</span>
        </div>
        <div class="flex justify-between text-steel-muted mt-1">
          <span>网络费</span><span class="text-ink-white">{{ fmtNum(quote.network_fee) }} USDT</span>
        </div>
        <div class="flex justify-between text-steel-muted mt-1">
          <span>总扣减</span><span class="text-bear-red">-{{ fmtNum(quote.total_deduction) }} USDT</span>
        </div>
        <div class="flex justify-between mt-2 pt-2 border-t border-hairline/60">
          <span class="text-steel-muted">实际到账</span>
          <span class="text-bull-green font-bold text-mono-data">{{ fmtNum(quote.arrive_amount) }} USDT</span>
        </div>
      </div>

      <div v-if="error" class="text-bear-red font-mono-data text-label-sm flex items-center gap-1">
        <span class="material-symbols-outlined text-[14px]">error</span>{{ error }}
      </div>
      <div v-else-if="ok" class="text-bull-green font-mono-data text-label-sm flex items-center gap-1">
        <span class="material-symbols-outlined text-[14px]">check_circle</span>{{ ok }}
      </div>

      <button
        class="w-full bg-primary-container/15 border border-primary-container/40 text-primary hover:bg-primary-container/25 font-mono-data text-mono-data font-semibold py-2.5 rounded-lg disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
        :disabled="submitting || !amountOk || !address.trim() || !network"
        @click="submit"
      >
        {{ submitting ? '提交中…' : '确认提现' }}
      </button>
    </section>

    <!-- ROW 3: 提现记录 -->
    <section class="bg-card-navy rounded-xl border border-hairline p-space-md flex flex-col mb-4">
      <div class="flex items-center justify-between pb-3 border-b border-hairline">
        <div class="text-headline-sm font-headline-sm font-bold text-ink-white">提现记录 WITHDRAWAL HISTORY</div>
        <button class="p-1 text-steel-muted hover:text-ink-white hover:bg-surface-slate rounded border border-hairline" title="刷新" @click="loadRecords">
          <span class="material-symbols-outlined text-[16px]">refresh</span>
        </button>
      </div>
      <div class="overflow-x-auto">
        <div v-if="!records.length" class="py-8 text-center text-steel-muted font-mono-data text-mono-data">暂无提现记录</div>
        <table v-else class="w-full text-left border-collapse">
          <thead>
            <tr class="border-b border-hairline text-steel-muted font-mono-data text-[11px] uppercase tracking-wider">
              <th class="py-3 px-3 font-semibold">时间 (Time)</th>
              <th class="py-3 px-3 text-center font-semibold">账户 (Account)</th>
              <th class="py-3 px-3 text-center font-semibold">网络 (Network)</th>
              <th class="py-3 px-3 text-right font-semibold">金额 (Amount)</th>
              <th class="py-3 px-3 text-right font-semibold">实际到账 (Arrive)</th>
              <th class="py-3 px-3 text-center font-semibold">状态 (Status)</th>
              <th class="py-3 px-3 text-right font-semibold">交易哈希 (Txid)</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-hairline font-mono-data text-mono-data">
            <tr v-for="r in records" :key="r.id" class="hover:bg-card-navy-high/50 transition-colors">
              <td class="py-3.5 px-3 text-steel-muted text-[12px]">{{ fmtDateTime(ts(r.created_at || r.requested_at)) }}</td>
              <td class="py-3.5 px-3 text-center text-steel-muted text-[12px]">{{ acctLabel(r.account) }}</td>
              <td class="py-3.5 px-3 text-center">
                <span class="text-[11px] bg-card-navy-high px-1.5 py-0.5 rounded text-steel-muted border border-hairline/40 uppercase">{{ r.network }}</span>
              </td>
              <td class="py-3.5 px-3 text-right font-semibold text-ink-white">{{ fmtNum(r.amount) }} USDT</td>
              <td class="py-3.5 px-3 text-right font-semibold text-bull-green">{{ fmtNum(r.arrive_amount) }} USDT</td>
              <td class="py-3.5 px-3 text-center">
                <span class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[11px] border" :class="statusOf(r.status).cls">
                  {{ statusOf(r.status).text }}
                </span>
              </td>
              <td class="py-3.5 px-3 text-right text-steel-muted text-[12px]" :title="r.txid">{{ cut(r.txid) }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
  </div>
</template>
