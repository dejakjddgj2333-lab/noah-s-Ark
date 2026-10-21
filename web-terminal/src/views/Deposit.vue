<script setup>
import { onMounted, onUnmounted, ref } from 'vue'
import { walletApi } from '../api/wallet'
import { fmtNum, fmtDateTime, ts } from '../utils/format'

const NETWORKS = ['trc20', 'erc20', 'bep20', 'arbitrum']
const NET_LABEL = { trc20: 'TRC20 · Tron', erc20: 'ERC20 · Ethereum', bep20: 'BEP20 · BSC', arbitrum: 'Arbitrum One' }
const NET_BADGE = { trc20: 'TRON', erc20: 'ETH', bep20: 'BSC', arbitrum: 'ARB' }

const network = ref('trc20')
const addr = ref(null) // { network, address, required_confirmations, min_deposit }
const addrLoading = ref(false)
const copied = ref(false)

const records = ref([])
const loading = ref(true)

const claimTxid = ref('')
const claiming = ref(false)
const claimError = ref('')
const claimOk = ref('')

// 充值状态着色: confirming=确认中 / credited=已入账 / unmatched=无法匹配
const STATUS = {
  confirming: { text: '确认中', cls: 'bg-amber-warn/12 text-amber-warn border-amber-warn/20' },
  credited: { text: '已入账', cls: 'bg-bull-green/12 text-bull-green border-bull-green/20' },
  unmatched: { text: '无法匹配', cls: 'bg-bear-red/12 text-bear-red border-bear-red/20' },
}
const statusOf = (s) => STATUS[s] || { text: s || '--', cls: 'bg-card-navy-high text-steel-muted border-hairline' }

const cut = (v) => (v ? `${String(v).slice(0, 8)}…${String(v).slice(-6)}` : '--')
const tOf = (r) => fmtDateTime(ts(r.block_time || r.credited_at))

async function loadAddress() {
  addrLoading.value = true
  addr.value = null
  try {
    addr.value = await walletApi.address(network.value)
  } catch {
    addr.value = null
  } finally {
    addrLoading.value = false
  }
}

async function loadRecords() {
  try {
    records.value = (await walletApi.depositRecords()) || []
  } catch {
    /* 静默, 保留旧数据 */
  }
}

async function load() {
  loading.value = true
  await Promise.all([loadAddress(), loadRecords()])
  loading.value = false
}

function switchNet(n) {
  if (network.value === n) return
  network.value = n
  copied.value = false
  loadAddress()
}

async function copyAddr() {
  if (!addr.value?.address) return
  try {
    await navigator.clipboard.writeText(addr.value.address)
    copied.value = true
    setTimeout(() => (copied.value = false), 2000)
  } catch {
    copied.value = false
  }
}

async function submitClaim() {
  claimError.value = ''
  claimOk.value = ''
  const txid = claimTxid.value.trim()
  if (!txid) {
    claimError.value = '请输入链上交易哈希 (txid)'
    return
  }
  claiming.value = true
  try {
    await walletApi.claim(txid, network.value)
    claimOk.value = '补单已提交, 等待后台核对入账'
    claimTxid.value = ''
    loadRecords()
  } catch (e) {
    claimError.value = e?.response?.data?.detail || e?.message || '补单失败'
  } finally {
    claiming.value = false
  }
}

let timer = null
onMounted(() => {
  load()
  timer = setInterval(loadRecords, 30000) // 30s 轮询充值记录
})
onUnmounted(() => clearInterval(timer))
</script>

<template>
  <div v-if="loading" class="text-steel-muted font-mono-data text-mono-data py-10 text-center">数据加载中…</div>
  <div v-else class="flex flex-col gap-space-lg">
    <!-- ROW 1: 充值地址卡片 -->
    <section class="bg-card-navy rounded-xl border border-hairline p-space-md flex flex-col gap-4">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <div class="flex items-center gap-2">
          <span class="text-headline-md font-headline-md font-bold text-ink-white">充值 DEPOSIT</span>
          <span class="text-label-sm font-mono-data text-steel-muted">USDT · 选择网络后向地址转账</span>
        </div>
        <!-- 网络切换 tab -->
        <div class="flex items-center gap-1 bg-surface-slate rounded border border-hairline p-0.5 font-mono-data text-label-sm">
          <button
            v-for="n in NETWORKS"
            :key="n"
            class="px-2.5 py-1 rounded uppercase"
            :class="network === n ? 'bg-card-navy text-ink-white font-semibold' : 'text-steel-muted hover:text-ink-white'"
            @click="switchNet(n)"
          >
            {{ n }}
          </button>
        </div>
      </div>

      <div v-if="addrLoading" class="py-6 text-center text-steel-muted font-mono-data text-mono-data">地址获取中…</div>
      <div v-else-if="addr" class="flex flex-col gap-4">
        <div class="flex flex-col md:flex-row md:items-center gap-3 bg-surface-slate border border-hairline rounded-lg p-4">
          <div class="flex-1 min-w-0">
            <div class="text-[11px] font-mono-data text-steel-muted uppercase tracking-wider mb-1">
              充值地址 · {{ NET_LABEL[network] }}
            </div>
            <div class="font-mono-data text-headline-sm font-headline-sm font-semibold text-ink-white break-all leading-snug">
              {{ addr.address }}
            </div>
          </div>
          <button
            class="shrink-0 bg-primary-container/15 border border-primary-container/40 text-primary hover:bg-primary-container/25 font-mono-data text-label-sm px-3 py-2 rounded-lg flex items-center gap-1.5 transition-colors"
            @click="copyAddr"
          >
            <span class="material-symbols-outlined text-[15px]">{{ copied ? 'check' : 'content_copy' }}</span>
            <span>{{ copied ? '已复制' : '复制地址' }}</span>
          </button>
        </div>
        <div class="grid grid-cols-2 md:grid-cols-3 gap-3">
          <div class="bg-surface-slate border border-hairline rounded-lg p-3">
            <div class="text-[11px] font-mono-data text-steel-muted uppercase tracking-wider">最小充值额</div>
            <div class="font-mono-data text-headline-sm font-headline-sm font-semibold text-ink-white mt-1">
              {{ fmtNum(addr.min_deposit) }} <span class="text-steel-muted text-label-sm font-normal">USDT</span>
            </div>
          </div>
          <div class="bg-surface-slate border border-hairline rounded-lg p-3">
            <div class="text-[11px] font-mono-data text-steel-muted uppercase tracking-wider">所需确认数</div>
            <div class="font-mono-data text-headline-sm font-headline-sm font-semibold text-ink-white mt-1">
              {{ addr.required_confirmations }} <span class="text-steel-muted text-label-sm font-normal">个区块</span>
            </div>
          </div>
          <div class="bg-surface-slate border border-hairline rounded-lg p-3 col-span-2 md:col-span-1">
            <div class="text-[11px] font-mono-data text-steel-muted uppercase tracking-wider">入账说明</div>
            <div class="font-mono-data text-label-sm text-amber-warn mt-1 flex items-center gap-1">
              <span class="material-symbols-outlined text-[14px]">info</span>
              低于最小额度将无法入账
            </div>
          </div>
        </div>
      </div>
      <div v-else class="py-4 text-center text-steel-muted font-mono-data text-mono-data">
        该网络暂不支持充值, 请切换其他网络
      </div>
    </section>

    <!-- ROW 2: 补单 -->
    <section class="bg-card-navy rounded-xl border border-hairline p-space-md flex flex-col gap-3">
      <div class="flex items-center gap-2">
        <span class="material-symbols-outlined text-primary text-[18px]">restore</span>
        <span class="text-headline-sm font-headline-sm font-bold text-ink-white">链上已转未到账? 自助补单</span>
      </div>
      <p class="text-body-md font-body-md text-steel-muted">
        若链上转账已成功但长时间未入账, 请填写交易哈希 (txid) 提交补单, 系统将自动核对。
      </p>
      <div class="flex flex-col md:flex-row gap-2">
        <input
          v-model="claimTxid"
          class="flex-1 bg-surface-slate border border-hairline rounded-lg px-3 py-2 font-mono-data text-mono-data text-ink-white placeholder:text-steel-muted focus:outline-none focus:border-primary-container/60"
          placeholder="输入 txid (交易哈希)"
          @keyup.enter="submitClaim"
        />
        <button
          class="bg-primary-container/15 border border-primary-container/40 text-primary hover:bg-primary-container/25 font-mono-data text-mono-data px-5 py-2 rounded-lg disabled:opacity-50 transition-colors"
          :disabled="claiming"
          @click="submitClaim"
        >
          {{ claiming ? '提交中…' : '提交补单' }}
        </button>
      </div>
      <div v-if="claimError" class="text-bear-red font-mono-data text-label-sm flex items-center gap-1">
        <span class="material-symbols-outlined text-[14px]">error</span>{{ claimError }}
      </div>
      <div v-else-if="claimOk" class="text-bull-green font-mono-data text-label-sm flex items-center gap-1">
        <span class="material-symbols-outlined text-[14px]">check_circle</span>{{ claimOk }}
      </div>
    </section>

    <!-- ROW 3: 充值记录 -->
    <section class="bg-card-navy rounded-xl border border-hairline p-space-md flex flex-col mb-4">
      <div class="flex items-center justify-between pb-3 border-b border-hairline">
        <div class="text-headline-sm font-headline-sm font-bold text-ink-white">充值记录 DEPOSIT HISTORY</div>
        <button class="p-1 text-steel-muted hover:text-ink-white hover:bg-surface-slate rounded border border-hairline" title="刷新" @click="loadRecords">
          <span class="material-symbols-outlined text-[16px]">refresh</span>
        </button>
      </div>
      <div class="overflow-x-auto">
        <div v-if="!records.length" class="py-8 text-center text-steel-muted font-mono-data text-mono-data">暂无充值记录</div>
        <table v-else class="w-full text-left border-collapse">
          <thead>
            <tr class="border-b border-hairline text-steel-muted font-mono-data text-[11px] uppercase tracking-wider">
              <th class="py-3 px-3 font-semibold">时间 (Time)</th>
              <th class="py-3 px-3 text-center font-semibold">网络 (Network)</th>
              <th class="py-3 px-3 text-right font-semibold">金额 (Amount)</th>
              <th class="py-3 px-3 text-center font-semibold">确认数 (Conf)</th>
              <th class="py-3 px-3 text-center font-semibold">状态 (Status)</th>
              <th class="py-3 px-3 text-right font-semibold">交易哈希 (Txid)</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-hairline font-mono-data text-mono-data">
            <tr v-for="r in records" :key="r.id" class="hover:bg-card-navy-high/50 transition-colors">
              <td class="py-3.5 px-3 text-steel-muted text-[12px]">{{ tOf(r) }}</td>
              <td class="py-3.5 px-3 text-center">
                <span class="text-[11px] bg-card-navy-high px-1.5 py-0.5 rounded text-steel-muted border border-hairline/40 uppercase">
                  {{ NET_BADGE[r.network] || r.network }}
                </span>
              </td>
              <td class="py-3.5 px-3 text-right font-semibold text-ink-white">{{ fmtNum(r.amount) }} USDT</td>
              <td class="py-3.5 px-3 text-center text-steel-muted text-[12px]">
                {{ r.confirmations ?? 0 }}/{{ r.required_confirmations ?? '--' }}
              </td>
              <td class="py-3.5 px-3 text-center">
                <span class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[11px] border" :class="statusOf(r.status).cls">
                  <span v-if="r.status === 'unmatched'" class="material-symbols-outlined text-[12px]">support_agent</span>
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
