<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue'
import { productApi, orderApi, settlementApi, accountApi, inviteApi, vipApi } from '../api'
import { fmtNum } from '../utils/format'

const products = ref([])
const orders = ref([])
const summary = ref({})
const account = ref({})
const vip = ref(null)
const logs = ref([])
const loading = ref(true)
const tab = ref('all')
const logTab = ref('all')

// 计息方式文案映射
const METHOD = {
  daily: '每日返息',
  period_7d: '7天一返',
  period_30d: '30天一返',
  period_1h: '每小时返',
  expiry: '到期还本付息',
  maturity: '到期还本付息', // 旧值容错
}

// 资金明细类型文案映射 (与后端 change_type 对齐)
const LOG_TYPE = {
  deposit_credited: '充值入账',
  purchase: '申购扣款',
  income_settled: '利息结算',
  principal_returned: '本金返还',
  commission: '返佣入账',
  convert_out: '收益转出',
  convert_in: '本金转入',
  withdraw_request: '提现申请',
  withdraw_approve: '提现通过',
  withdraw_reject: '提现退回',
  admin_adjust: '人工调整',
}

// 利率容错: 原始值 >1 视为已是百分数, 否则按小数 (0.008=0.8%) 处理
function ratePct(r) {
  const n = Number(r)
  if (isNaN(n)) return 0
  return n > 1 ? n : n * 100
}
function rateFrac(r) {
  const n = Number(r)
  if (isNaN(n)) return 0
  return n > 1 ? n / 100 : n
}
// 日化展示 (优先 actual_daily_rate)
function dailyRate(o) {
  return ratePct(o.actual_daily_rate ?? o.base_daily_rate).toFixed(2) + '%'
}
// 年化展示 (产品卡)
function annual(p) {
  return (ratePct(p.base_daily_rate) * 365).toFixed(2) + '%'
}
// 预期收益自算: 本金 × 日化 × 天数
function expected(o) {
  const amt = Number(o.amount || 0)
  const r = rateFrac(o.actual_daily_rate ?? o.base_daily_rate)
  return amt * r * Number(o.duration_days || 0)
}

async function load() {
  try {
    const [p, o, s, a, v] = await Promise.allSettled([
      productApi.list(),
      orderApi.list(),
      settlementApi.commissionsSummary(),
      accountApi.depositAccount(),
      vipApi.me(),
    ])
    if (p.status === 'fulfilled') products.value = p.value || []
    if (o.status === 'fulfilled') orders.value = o.value?.items || o.value || []
    if (s.status === 'fulfilled') summary.value = s.value || {}
    if (a.status === 'fulfilled') account.value = a.value || {}
    if (v.status === 'fulfilled') vip.value = v.value || null
    await loadLogs()
  } finally {
    loading.value = false
  }
}

async function loadLogs() {
  try {
    const params = logTab.value === 'all' ? {} : { account: logTab.value }
    logs.value = (await settlementApi.accountLogs(params)) || []
  } catch {
    logs.value = []
  }
}
watch(logTab, loadLogs)

const isActive = (o) => o.status === 'effective'
const activeOrders = computed(() => orders.value.filter(isActive))
const doneOrders = computed(() => orders.value.filter((o) => !isActive(o)))
const shownOrders = computed(() =>
  tab.value === 'active' ? activeOrders.value : tab.value === 'done' ? doneOrders.value : orders.value,
)

const totalPrincipal = computed(() =>
  activeOrders.value.reduce((s, o) => s + Number(o.amount || 0), 0),
)

// ---------- 产品过滤 tab ----------
const productTab = ref('all')
const filteredProducts = computed(() => {
  const list = products.value
  if (productTab.value === 'short') return list.filter((p) => Number(p.duration_days) <= 7)
  if (productTab.value === 'long') return list.filter((p) => Number(p.duration_days) > 7)
  if (productTab.value === 'vip') return list.filter((p) => Number(p.vip_level_req) > 0)
  return list
})
const totalProfit = computed(() =>
  orders.value.reduce((s, o) => s + expected(o), 0),
)
const totalCommission = computed(() => summary.value.total ?? 0)
const pendingTotal = computed(
  () => Number(account.value.principal_pending || 0) + Number(account.value.income_pending || 0),
)

function uuid() {
  return crypto.randomUUID?.() || `${Date.now()}-${Math.random().toString(16).slice(2)}`
}

// ---------- 申购弹层 ----------
const buy = reactive({
  show: false,
  product: null,
  amount: '',
  key: '',
  err: '',
  submitting: false,
  inviteChecked: false,
  inviteWarn: false,
})

function openBuy(p) {
  Object.assign(buy, {
    show: true,
    product: p,
    amount: '',
    key: uuid(), // 打开时生成一次幂等键, 重试沿用同键
    err: '',
    submitting: false,
    inviteChecked: false,
    inviteWarn: false,
  })
}
function closeBuy() {
  buy.show = false
}

function validateBuy() {
  const amt = Number(buy.amount)
  if (!buy.amount || isNaN(amt) || amt <= 0) return '请输入有效的申购金额'
  const min = Number(buy.product?.min_amount)
  const max = Number(buy.product?.max_amount)
  if (!isNaN(min) && amt < min) return `单笔起投 ${fmtNum(min)} USDT`
  if (!isNaN(max) && max > 0 && amt > max) return `单笔上限 ${fmtNum(max)} USDT`
  return ''
}

async function confirmBuy() {
  buy.err = validateBuy()
  if (buy.err) return
  // 提交前预检邀请关系 (接口失败不阻塞)
  if (!buy.inviteChecked) {
    buy.inviteChecked = true
    try {
      const inv = await inviteApi.me()
      const bound = inv?.bound ?? (inv?.inviter_id != null)
      const canBind = inv?.canBind ?? inv?.can_bind
      if (!bound && canBind) {
        buy.inviteWarn = true
        return // 等用户确认"继续购买"
      }
    } catch {
      /* 预检失败不阻塞购买 */
    }
  }
  buy.submitting = true
  buy.err = ''
  try {
    await orderApi.create({
      product_id: buy.product.id,
      amount: String(Number(buy.amount)),
      idempotency_key: buy.key,
    })
    closeBuy()
    await load()
  } catch (e) {
    buy.err = e?.response?.data?.detail || e.message || '申购失败, 请稍后重试'
  } finally {
    buy.submitting = false
  }
}

// ---------- 收益转本金弹窗 ----------
const cv = reactive({
  show: false,
  amount: '',
  key: '',
  err: '',
  submitting: false,
  quote: null,
  quoting: false,
})

function openConvert() {
  Object.assign(cv, {
    show: true,
    amount: '',
    key: uuid(),
    err: '',
    submitting: false,
    quote: null,
    quoting: false,
  })
}
function closeConvert() {
  cv.show = false
}

// 金额变动后自动拉报价 (防抖)
let quoteTimer = null
watch(
  () => cv.amount,
  (val) => {
    cv.quote = null
    cv.err = ''
    clearTimeout(quoteTimer)
    const amt = Number(val)
    if (!cv.show || !val || isNaN(amt) || amt <= 0) return
    quoteTimer = setTimeout(async () => {
      cv.quoting = true
      try {
        cv.quote = await accountApi.convertQuote({ amount: val })
      } catch (e) {
        cv.err = e?.response?.data?.detail || e.message || '报价失败'
      } finally {
        cv.quoting = false
      }
    }, 400)
  },
)

async function confirmConvert() {
  const amt = Number(cv.amount)
  if (!cv.amount || isNaN(amt) || amt <= 0) {
    cv.err = '请输入有效的转化金额'
    return
  }
  if (amt > Number(account.value.income_balance || 0)) {
    cv.err = '超出收益账户可用余额'
    return
  }
  cv.submitting = true
  cv.err = ''
  try {
    await accountApi.convert({ amount: cv.amount, idempotency_key: cv.key })
    closeConvert()
    await load()
  } catch (e) {
    cv.err = e?.response?.data?.detail || e.message || '转化失败, 请稍后重试'
  } finally {
    cv.submitting = false
  }
}

function fmtTime16(v) {
  if (!v) return '--'
  return String(v).slice(0, 16).replace('T', ' ')
}
function fmtDate(v) {
  if (!v) return '--'
  return String(v).slice(0, 10)
}

const COIN_ICON = ['₮', '₿', 'Ξ', '⚡']
function coinIcon(i) {
  return COIN_ICON[i % COIN_ICON.length]
}

onMounted(load)
</script>

<template>
  <div v-if="loading" class="text-steel-muted font-mono-data text-mono-data py-10 text-center">数据加载中…</div>
  <div v-else class="flex flex-col gap-space-lg">
    <!-- PAGE HEADER -->
    <header class="flex flex-wrap items-end justify-between gap-3">
      <div class="flex flex-col gap-1.5">
        <div class="font-mono-data text-[11px] uppercase tracking-widest text-steel-muted">
          HOME&nbsp;&nbsp;/&nbsp;&nbsp;PORTFOLIO&nbsp;&nbsp;/&nbsp;&nbsp;<span class="text-primary">ASSET MANAGEMENT ENGINE</span>
        </div>
        <div class="flex items-center gap-3">
          <h1 class="text-headline-md font-headline-md font-bold text-ink-white">理财资产综合控制台</h1>
          <span class="text-[11px] font-mono-data text-primary border border-primary/40 bg-primary-container/15 px-2 py-0.5 rounded">
            v3.4.1 核心结算系统
          </span>
        </div>
      </div>
      <div class="flex items-center gap-2 font-mono-data text-label-sm">
        <span class="text-steel-muted">实时资产折算汇率:</span>
        <span class="text-ink-white font-semibold bg-card-navy border border-hairline rounded px-2 py-1">
          1 USDT = <span class="text-bull-green">$1.0002</span> USD
        </span>
      </div>
    </header>

    <!-- ROW 0: 双账户余额区 -->
    <section class="grid grid-cols-1 md:grid-cols-3 gap-4">
      <!-- 本金账户 -->
      <div class="bg-card-navy rounded-xl border border-hairline p-space-md flex flex-col justify-between">
        <div class="flex items-center justify-between text-steel-muted font-mono-data text-label-sm">
          <div class="flex items-center gap-1.5">
            <span class="material-symbols-outlined text-primary text-[17px]">account_balance_wallet</span>
            <span class="tracking-wider">本金账户 PRINCIPAL</span>
          </div>
          <span class="text-[10px] bg-card-navy-high px-1.5 py-0.5 rounded text-steel-muted border border-hairline/40">可申购</span>
        </div>
        <div class="my-2.5">
          <div class="font-mono-data text-[30px] font-bold tracking-tight text-ink-white">
            ${{ fmtNum(account.principal_balance) }}
          </div>
          <div class="flex items-center gap-2 font-mono-data text-label-sm mt-0.5">
            <span class="text-steel-muted">提现处理中</span>
            <span class="text-amber-warn font-semibold">${{ fmtNum(account.principal_pending) }}</span>
          </div>
        </div>
        <div class="pt-2 border-t border-hairline/60 flex items-center justify-between text-label-sm font-mono-data">
          <span class="text-steel-muted">来源</span>
          <span class="text-steel-muted">链上充值 / 本金返还 / 收益转化</span>
        </div>
      </div>
      <!-- 收益账户 -->
      <div class="bg-card-navy rounded-xl border border-hairline p-space-md flex flex-col justify-between">
        <div class="flex items-center justify-between text-steel-muted font-mono-data text-label-sm">
          <div class="flex items-center gap-1.5">
            <span class="material-symbols-outlined text-bull-green text-[17px]">savings</span>
            <span class="tracking-wider">收益账户 INCOME</span>
          </div>
          <span
            v-if="vip"
            class="text-[10px] bg-bull-green/10 text-bull-green px-1.5 py-0.5 rounded border border-bull-green/30"
          >
            VIP{{ vip.vip_level ?? 0 }}
            <template v-if="Number(vip.bonus_rate) > 0"> · 加成 +{{ ratePct(vip.bonus_rate).toFixed(2) }}%</template>
          </span>
        </div>
        <div class="my-2.5">
          <div class="font-mono-data text-[30px] font-bold tracking-tight text-bull-green">
            ${{ fmtNum(account.income_balance) }}
          </div>
          <div class="flex items-center gap-2 font-mono-data text-label-sm mt-0.5">
            <span class="text-steel-muted">提现处理中</span>
            <span class="text-amber-warn font-semibold">${{ fmtNum(account.income_pending) }}</span>
          </div>
        </div>
        <div class="pt-2 border-t border-hairline/60 flex items-center justify-between text-label-sm font-mono-data">
          <span class="text-steel-muted">来源</span>
          <span class="text-steel-muted">利息结算 / 邀请返佣</span>
        </div>
      </div>
      <!-- 收益转本金 -->
      <div class="bg-card-navy rounded-xl border border-hairline p-space-md flex flex-col justify-between">
        <div class="flex items-center justify-between text-steel-muted font-mono-data text-label-sm">
          <div class="flex items-center gap-1.5">
            <span class="material-symbols-outlined text-amber-warn text-[17px]">currency_exchange</span>
            <span class="tracking-wider">收益转本金 CONVERT</span>
          </div>
          <span class="text-[10px] text-steel-muted">全免转账滑点</span>
        </div>
        <div class="my-2.5 flex flex-col gap-2">
          <div class="text-body-md font-body-md text-steel-muted leading-relaxed">
            收益账户余额可直接转为本金, 可即刻用于申购高息理财, 仅收取极微量系统服务费。
          </div>
          <div class="flex items-center justify-between font-mono-data text-label-sm bg-canvas-obsidian border border-hairline/60 rounded-lg px-3 py-2">
            <span class="text-steel-muted">全部提现处理中</span>
            <span class="text-ink-white font-semibold">${{ fmtNum(pendingTotal) }}</span>
          </div>
        </div>
        <div class="flex flex-col gap-2">
          <button
            class="w-full px-4 py-2.5 rounded-lg bg-primary-container text-ink-white hover:bg-primary-container/90 transition-all font-body-md text-body-md font-semibold flex items-center justify-center gap-1.5 disabled:opacity-50 disabled:cursor-not-allowed"
            :disabled="Number(account.income_balance || 0) <= 0"
            @click="openConvert"
          >
            <span class="material-symbols-outlined text-[16px]">swap_horiz</span>
            立即将收益转本金 (${{ fmtNum(account.income_balance) }})
          </button>
          <div class="grid grid-cols-2 gap-2">
            <router-link
              class="px-4 py-2 rounded-lg bg-canvas-obsidian border border-hairline text-bull-green hover:border-bull-green/50 transition-all font-body-md text-body-md font-medium flex items-center justify-center gap-1.5"
              to="/deposit"
            >
              <span class="material-symbols-outlined text-[16px]">south</span>
              充值资产
            </router-link>
            <router-link
              class="px-4 py-2 rounded-lg bg-canvas-obsidian border border-hairline text-amber-warn hover:border-amber-warn/50 transition-all font-body-md text-body-md font-medium flex items-center justify-center gap-1.5"
              to="/withdraw"
            >
              <span class="material-symbols-outlined text-[16px]">north</span>
              提现至钱包
            </router-link>
          </div>
        </div>
      </div>
    </section>

    <!-- ROW 1: 3 STAT KPI CARDS -->
    <section class="grid grid-cols-1 md:grid-cols-3 gap-4">
      <!-- Card 1: 累计返佣 -->
      <div class="bg-card-navy rounded-xl border border-hairline p-space-md flex flex-col justify-between hover:border-hairline/80 transition-colors">
        <div class="flex items-center justify-between text-steel-muted font-mono-data text-label-sm">
          <div class="flex items-center gap-1.5">
            <span class="material-symbols-outlined text-steel-muted text-[17px]">payments</span>
            <span class="tracking-wider">累计返佣 COMMISSION</span>
          </div>
          <span class="text-[10px] bg-card-navy-high px-1.5 py-0.5 rounded text-steel-muted border border-hairline/40">USDT结算</span>
        </div>
        <div class="my-2.5">
          <div class="font-mono-data text-[30px] font-bold tracking-tight text-ink-white flex items-baseline gap-2">
            <span>${{ fmtNum(totalCommission) }}</span>
          </div>
          <div class="flex items-center gap-2 font-mono-data text-label-sm mt-0.5">
            <span class="text-steel-muted">今日返佣</span>
            <span class="text-bull-green font-semibold">+${{ fmtNum(summary.today) }}</span>
          </div>
        </div>
        <div class="pt-2 border-t border-hairline/60 flex items-center justify-between text-label-sm font-mono-data">
          <span class="text-steel-muted">结算方式</span>
          <span class="text-bull-green font-semibold flex items-center gap-0.5">
            <span class="material-symbols-outlined text-[14px]">arrow_drop_up</span>
            每期自动结算
          </span>
        </div>
      </div>
      <!-- Card 2: 预期收益 -->
      <div class="bg-card-navy rounded-xl border border-hairline p-space-md flex flex-col justify-between hover:border-hairline/80 transition-colors">
        <div class="flex items-center justify-between text-steel-muted font-mono-data text-label-sm">
          <div class="flex items-center gap-1.5">
            <span class="material-symbols-outlined text-bull-green text-[17px]">trending_up</span>
            <span class="tracking-wider">预期收益 EXPECTED PnL</span>
          </div>
          <span class="text-[10px] bg-bull-green/10 text-bull-green px-1.5 py-0.5 rounded border border-bull-green/30">理财订单</span>
        </div>
        <div class="my-2.5">
          <div class="font-mono-data text-[30px] font-bold tracking-tight text-bull-green flex items-baseline gap-2">
            <span>+${{ fmtNum(totalProfit) }}</span>
          </div>
          <div class="flex items-center gap-2 font-mono-data text-label-sm mt-0.5">
            <span class="text-steel-muted">全部订单预期收益合计 (本金×日化×期限)</span>
          </div>
        </div>
        <div class="pt-2 border-t border-hairline/60 flex items-center justify-between text-label-sm font-mono-data">
          <span class="text-steel-muted">订单总数</span>
          <span class="text-ink-white font-semibold">{{ orders.length }} 笔</span>
        </div>
      </div>
      <!-- Card 3: 在投产品 -->
      <div class="bg-card-navy rounded-xl border border-hairline p-space-md flex flex-col justify-between hover:border-hairline/80 transition-colors">
        <div class="flex items-center justify-between text-steel-muted font-mono-data text-label-sm">
          <div class="flex items-center gap-1.5">
            <span class="material-symbols-outlined text-primary text-[17px]">savings</span>
            <span class="tracking-wider">在投产品 ACTIVE PRODUCTS</span>
          </div>
          <a class="text-[11px] text-primary hover:underline flex items-center gap-0.5" href="#positions">
            我的持仓 →
          </a>
        </div>
        <div class="my-2.5">
          <div class="font-mono-data text-[30px] font-bold tracking-tight text-ink-white flex items-baseline gap-2">
            <span class="text-primary">{{ activeOrders.length }}</span>
            <span class="text-headline-sm font-headline-sm text-steel-muted font-normal">笔计息中</span>
          </div>
          <div class="flex items-center gap-2 font-mono-data text-label-sm mt-0.5">
            <span class="text-steel-muted">在投本金</span>
            <span class="text-ink-white font-semibold">${{ fmtNum(totalPrincipal) }}</span>
          </div>
        </div>
        <div class="pt-2 border-t border-hairline/60 flex items-center justify-between text-label-sm font-mono-data">
          <span class="text-steel-muted">可选产品</span>
          <span class="text-amber-warn font-semibold">{{ products.length }} 款上架中</span>
        </div>
      </div>
    </section>

    <!-- ROW 2: PRODUCTS GRID -->
    <section class="flex flex-col gap-3">
      <div class="flex flex-wrap items-center justify-between gap-3 bg-card-navy rounded-xl border border-hairline px-4 py-3">
        <div class="flex flex-wrap items-center gap-2.5">
          <span class="text-headline-sm font-headline-sm font-bold text-ink-white">理财产品</span>
          <span class="font-mono-data text-[11px] uppercase tracking-widest text-steel-muted">WEALTH PRODUCTS</span>
          <span class="text-[11px] font-mono-data text-steel-muted border border-hairline px-2 py-0.5 rounded">低风险</span>
          <span class="text-[11px] font-mono-data text-steel-muted border border-hairline px-2 py-0.5 rounded">高流动性</span>
          <span class="text-[11px] font-mono-data text-steel-muted border border-hairline px-2 py-0.5 rounded">智能计息</span>
        </div>
        <div class="flex items-center gap-1 font-mono-data text-label-sm">
          <button
            class="px-2.5 py-1 rounded transition-all"
            :class="productTab === 'all' ? 'bg-primary-container text-ink-white font-semibold' : 'text-steel-muted hover:text-ink-white'"
            @click="productTab = 'all'"
          >
            全部 ({{ products.length }})
          </button>
          <button
            class="px-2.5 py-1 rounded transition-all"
            :class="productTab === 'short' ? 'bg-primary-container text-ink-white font-semibold' : 'text-steel-muted hover:text-ink-white'"
            @click="productTab = 'short'"
          >
            短周期
          </button>
          <button
            class="px-2.5 py-1 rounded transition-all"
            :class="productTab === 'long' ? 'bg-primary-container text-ink-white font-semibold' : 'text-steel-muted hover:text-ink-white'"
            @click="productTab = 'long'"
          >
            中长期
          </button>
          <button
            class="px-2.5 py-1 rounded transition-all"
            :class="productTab === 'vip' ? 'bg-primary-container text-ink-white font-semibold' : 'text-steel-muted hover:text-ink-white'"
            @click="productTab = 'vip'"
          >
            VIP专享
          </button>
        </div>
      </div>
      <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div
          v-for="p in filteredProducts"
          :key="p.id"
          class="bg-card-navy rounded-xl border border-hairline p-space-md flex flex-col justify-between hover:border-primary-container/60 transition-colors group"
        >
          <div>
            <div class="flex items-center justify-between mb-2.5">
              <div class="flex items-center gap-1.5">
                <span class="text-[11px] font-mono-data font-semibold text-primary bg-primary-container/15 border border-primary-container/30 px-2 py-0.5 rounded">
                  {{ METHOD[p.return_method] || '稳健增利' }}
                </span>
                <span class="text-[11px] font-mono-data text-steel-muted bg-card-navy-high border border-hairline/60 px-2 py-0.5 rounded">
                  {{ p.duration_days }}天定期
                </span>
              </div>
              <div class="flex items-center gap-1.5">
                <span
                  v-if="Number(p.vip_level_req) > 0"
                  class="text-[11px] font-mono-data font-semibold text-amber-warn bg-amber-warn/10 border border-amber-warn/30 px-2 py-0.5 rounded"
                >
                  VIP专享
                </span>
                <span class="material-symbols-outlined text-bull-green text-[18px]">check_circle</span>
              </div>
            </div>
            <h3 class="text-headline-sm font-headline-sm font-semibold text-ink-white">
              {{ p.name }}
            </h3>
            <div class="font-mono-data text-[11px] uppercase tracking-wider text-steel-muted mt-0.5 truncate">
              {{ p.name_en || p.description || '' }}
            </div>
            <div class="mt-3.5 mb-3 bg-canvas-obsidian border border-hairline/60 rounded-lg px-3.5 py-3">
              <div class="text-[11px] font-mono-data text-steel-muted uppercase tracking-wider">参考年化 (APY)</div>
              <div class="text-[32px] font-mono-data font-bold text-bull-green tracking-tight leading-none mt-1.5">
                {{ annual(p) }}
              </div>
              <div class="flex items-center justify-between font-mono-data text-[11px] mt-2">
                <span class="text-steel-muted">日化收益: <span class="text-ink-white font-semibold">{{ ratePct(p.base_daily_rate).toFixed(2) }}%</span></span>
                <span class="text-steel-muted">USDT 标价</span>
              </div>
            </div>
            <div class="space-y-1.5 font-mono-data text-label-sm">
              <div class="flex justify-between text-steel-muted">
                <span>投资期限:</span>
                <span class="text-ink-white font-medium">{{ p.duration_days }} 天 (锁定)</span>
              </div>
              <div class="flex justify-between text-steel-muted">
                <span>起投门槛:</span>
                <span class="text-ink-white font-medium">{{ fmtNum(p.min_amount, 0) }} USDT</span>
              </div>
              <div class="flex justify-between text-steel-muted">
                <span>单笔上限:</span>
                <span class="text-ink-white font-medium">{{ fmtNum(p.max_amount, 0) }} USDT</span>
              </div>
              <div class="flex justify-between text-steel-muted">
                <span>计息方式:</span>
                <span class="text-ink-white font-medium">{{ METHOD[p.return_method] || p.return_method }}</span>
              </div>
            </div>
          </div>
          <div>
            <button
              class="w-full bg-primary-container text-ink-white font-mono-data text-mono-data py-2.5 px-4 rounded-lg flex items-center justify-center gap-1.5 hover:bg-primary-container/90 transition-all mt-4"
              @click="openBuy(p)"
            >
              <span class="material-symbols-outlined text-[16px]">add_shopping_cart</span>
              <span>立即申购</span>
            </button>
          </div>
        </div>
        <div
          v-if="!filteredProducts.length"
          class="bg-card-navy rounded-xl border border-hairline p-space-md text-steel-muted font-mono-data text-mono-data text-center md:col-span-3"
        >
          {{ products.length ? '该分类下暂无产品' : '暂无上架产品' }}
        </div>
      </div>
    </section>

    <!-- ROW 3: MY POSITIONS TABLE -->
    <section class="bg-card-navy rounded-xl border border-hairline p-space-md flex flex-col" id="positions">
      <div class="flex flex-wrap items-center justify-between gap-3 pb-3 border-b border-hairline">
        <div class="flex items-center gap-4">
          <div class="text-headline-sm font-headline-sm font-bold text-ink-white">我的持仓 MY POSITIONS</div>
          <div class="flex items-center gap-1 bg-surface-slate rounded border border-hairline p-0.5 font-mono-data text-label-sm">
            <button
              class="px-2.5 py-1 rounded"
              :class="tab === 'all' ? 'bg-card-navy text-ink-white font-semibold' : 'text-steel-muted hover:text-ink-white'"
              @click="tab = 'all'"
            >
              全部持仓 ({{ orders.length }})
            </button>
            <button
              class="px-2.5 py-1 rounded"
              :class="tab === 'active' ? 'bg-card-navy text-ink-white font-semibold' : 'text-steel-muted hover:text-ink-white'"
              @click="tab = 'active'"
            >
              计息中 ({{ activeOrders.length }})
            </button>
            <button
              class="px-2.5 py-1 rounded"
              :class="tab === 'done' ? 'bg-card-navy text-ink-white font-semibold' : 'text-steel-muted hover:text-ink-white'"
              @click="tab = 'done'"
            >
              已完成 ({{ doneOrders.length }})
            </button>
          </div>
        </div>
        <div class="flex items-center gap-3">
          <button class="p-1 text-steel-muted hover:text-ink-white hover:bg-surface-slate rounded border border-hairline" title="刷新" @click="load">
            <span class="material-symbols-outlined text-[16px]">refresh</span>
          </button>
        </div>
      </div>
      <div class="overflow-x-auto">
        <div v-if="!shownOrders.length" class="py-8 text-center text-steel-muted font-mono-data text-mono-data">暂无订单</div>
        <table v-else class="w-full text-left border-collapse">
          <thead>
            <tr class="border-b border-hairline text-steel-muted font-mono-data text-[11px] uppercase tracking-wider">
              <th class="py-3 px-3 font-semibold">产品名称 (Product)</th>
              <th class="py-3 px-3 text-right font-semibold">本金 (Principal)</th>
              <th class="py-3 px-3 text-right font-semibold">日化 (Daily)</th>
              <th class="py-3 px-3 text-right font-semibold">预期收益 (Profit)</th>
              <th class="py-3 px-3 text-center font-semibold">起息日 (Start)</th>
              <th class="py-3 px-3 text-center font-semibold">到期日 (Maturity)</th>
              <th class="py-3 px-3 text-center font-semibold">状态 (Status)</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-hairline font-mono-data text-mono-data">
            <tr
              v-for="(o, i) in shownOrders"
              :key="o.id"
              class="hover:bg-card-navy-high/50 transition-colors"
              :class="{ 'bg-card-navy/40': !isActive(o) }"
            >
              <td class="py-3.5 px-3">
                <div class="flex items-center gap-2">
                  <div
                    class="w-5 h-5 rounded-full flex items-center justify-center font-bold text-[10px]"
                    :class="isActive(o) ? 'bg-bull-green/20 text-bull-green' : 'bg-card-navy-high text-steel-muted'"
                  >
                    {{ coinIcon(i) }}
                  </div>
                  <div>
                    <div :class="isActive(o) ? 'text-ink-white font-semibold' : 'text-steel-muted font-medium'">
                      {{ o.product_name || `#${o.product_id}` }}
                    </div>
                    <div class="text-[11px] text-steel-muted">订单 #{{ o.id }}</div>
                  </div>
                </div>
              </td>
              <td class="py-3.5 px-3 text-right font-medium" :class="isActive(o) ? 'text-ink-white' : 'text-steel-muted'">
                {{ fmtNum(o.amount) }} USDT
              </td>
              <td class="py-3.5 px-3 text-right font-medium" :class="isActive(o) ? 'text-ink-white' : 'text-steel-muted'">
                {{ dailyRate(o) }}
              </td>
              <td class="py-3.5 px-3 text-right font-semibold" :class="isActive(o) ? 'text-bull-green' : 'text-steel-muted'">
                +${{ fmtNum(expected(o)) }}
              </td>
              <td class="py-3.5 px-3 text-center text-steel-muted text-[12px]">
                <div :class="{ 'text-ink-white': isActive(o) }">{{ fmtDate(o.effective_at) }}</div>
              </td>
              <td class="py-3.5 px-3 text-center text-steel-muted text-[12px]">
                <div :class="{ 'text-ink-white': isActive(o) }">{{ fmtDate(o.expires_at) }}</div>
              </td>
              <td class="py-3.5 px-3 text-center">
                <span
                  v-if="isActive(o)"
                  class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[11px] bg-bull-green/12 text-bull-green border border-bull-green/20"
                >
                  <span class="w-1.5 h-1.5 rounded-full bg-bull-green"></span>
                  计息中
                </span>
                <span
                  v-else
                  class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[11px] bg-card-navy-high text-steel-muted border border-hairline"
                >
                  已完成
                </span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <!-- ROW 4: 资金明细 -->
    <section class="bg-card-navy rounded-xl border border-hairline p-space-md flex flex-col mb-4">
      <div class="flex flex-wrap items-center justify-between gap-3 pb-3 border-b border-hairline">
        <div class="flex items-center gap-4">
          <div class="text-headline-sm font-headline-sm font-bold text-ink-white">资金明细 ACCOUNT LOGS</div>
          <div class="flex items-center gap-1 bg-surface-slate rounded border border-hairline p-0.5 font-mono-data text-label-sm">
            <button
              class="px-2.5 py-1 rounded"
              :class="logTab === 'all' ? 'bg-card-navy text-ink-white font-semibold' : 'text-steel-muted hover:text-ink-white'"
              @click="logTab = 'all'"
            >
              全部
            </button>
            <button
              class="px-2.5 py-1 rounded"
              :class="logTab === 'principal' ? 'bg-card-navy text-ink-white font-semibold' : 'text-steel-muted hover:text-ink-white'"
              @click="logTab = 'principal'"
            >
              本金账户
            </button>
            <button
              class="px-2.5 py-1 rounded"
              :class="logTab === 'income' ? 'bg-card-navy text-ink-white font-semibold' : 'text-steel-muted hover:text-ink-white'"
              @click="logTab = 'income'"
            >
              收益账户
            </button>
          </div>
        </div>
        <button class="p-1 text-steel-muted hover:text-ink-white hover:bg-surface-slate rounded border border-hairline" title="刷新" @click="loadLogs">
          <span class="material-symbols-outlined text-[16px]">refresh</span>
        </button>
      </div>
      <div class="overflow-x-auto">
        <div v-if="!logs.length" class="py-8 text-center text-steel-muted font-mono-data text-mono-data">暂无资金明细</div>
        <table v-else class="w-full text-left border-collapse">
          <thead>
            <tr class="border-b border-hairline text-steel-muted font-mono-data text-[11px] uppercase tracking-wider">
              <th class="py-3 px-3 font-semibold">时间 (Time)</th>
              <th class="py-3 px-3 font-semibold">账户 (Account)</th>
              <th class="py-3 px-3 font-semibold">类型 (Type)</th>
              <th class="py-3 px-3 text-right font-semibold">金额 (Amount)</th>
              <th class="py-3 px-3 text-right font-semibold">变动后余额 (Balance)</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-hairline font-mono-data text-mono-data">
            <tr v-for="g in logs" :key="g.id" class="hover:bg-card-navy-high/50 transition-colors">
              <td class="py-3 px-3 text-steel-muted text-[12px]">{{ fmtTime16(g.created_at) }}</td>
              <td class="py-3 px-3 text-steel-muted text-[12px]">{{ g.account === 'principal' ? '本金' : g.account === 'income' ? '收益' : g.account }}</td>
              <td class="py-3 px-3 text-ink-white text-[12px]">{{ LOG_TYPE[g.change_type] || g.change_type }}</td>
              <td
                class="py-3 px-3 text-right font-semibold"
                :class="Number(g.amount) >= 0 ? 'text-bull-green' : 'text-bear-red'"
              >
                {{ Number(g.amount) >= 0 ? '+' : '' }}${{ fmtNum(g.amount) }}
              </td>
              <td class="py-3 px-3 text-right text-steel-muted">${{ fmtNum(g.balance_after) }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <!-- ===== 申购弹层 ===== -->
    <div
      v-if="buy.show"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 px-4"
      @click.self="closeBuy"
    >
      <div class="w-full max-w-md bg-card-navy border border-hairline rounded-xl p-6 shadow-[0_16px_48px_rgba(0,0,0,0.6)]">
        <div class="flex items-center justify-between mb-5 pb-3 border-b border-hairline">
          <h3 class="font-headline-md text-headline-md font-bold text-ink-white flex items-center gap-2">
            <span class="material-symbols-outlined text-primary-container">add_shopping_cart</span>
            申购 {{ buy.product?.name }}
          </h3>
          <button class="text-steel-muted hover:text-ink-white transition-colors" title="关闭" @click="closeBuy">
            <span class="material-symbols-outlined text-[20px]">close</span>
          </button>
        </div>
        <div class="flex flex-col gap-3">
          <div class="font-mono-data text-label-sm text-steel-muted space-y-1">
            <div class="flex justify-between">
              <span>日化 / 年化</span>
              <span class="text-bull-green font-semibold">
                {{ ratePct(buy.product?.base_daily_rate).toFixed(2) }}% / {{ annual(buy.product || {}) }}
              </span>
            </div>
            <div class="flex justify-between">
              <span>期限 / 计息方式</span>
              <span class="text-ink-white">{{ buy.product?.duration_days }} 天 · {{ METHOD[buy.product?.return_method] || buy.product?.return_method }}</span>
            </div>
            <div class="flex justify-between">
              <span>限额</span>
              <span class="text-ink-white">{{ fmtNum(buy.product?.min_amount, 0) }} ~ {{ fmtNum(buy.product?.max_amount, 0) }} USDT</span>
            </div>
            <div class="flex justify-between">
              <span>本金账户可用</span>
              <span class="text-ink-white">${{ fmtNum(account.principal_balance) }}</span>
            </div>
          </div>
          <div>
            <label class="font-label-sm text-label-sm text-steel-muted block mb-1">申购金额 (USDT)</label>
            <input
              v-model="buy.amount"
              type="number"
              min="0"
              step="0.01"
              :placeholder="`起投 ${fmtNum(buy.product?.min_amount, 0)} USDT`"
              class="w-full bg-surface border border-hairline rounded-lg text-ink-white placeholder-steel-muted/60 text-body-md font-body-md px-3 py-2 focus:border-primary-container focus:ring-1 focus:ring-primary-container focus:outline-none transition-all"
              @keyup.enter="confirmBuy"
            />
          </div>
          <div
            v-if="buy.inviteWarn"
            class="flex items-start gap-1.5 font-body-md text-[12px] text-amber-warn bg-amber-warn/10 border border-amber-warn/30 rounded-lg px-3 py-2"
          >
            <span class="material-symbols-outlined text-[15px] mt-px">warning</span>
            <span>未绑定邀请关系, 继续购买将失去补绑资格。点击"继续购买"表示确认。</span>
          </div>
          <div v-if="buy.err" class="flex items-center gap-1.5 font-body-md text-[12px] text-bear-red bg-bear-red/10 border border-bear-red/30 rounded-lg px-3 py-2">
            <span class="material-symbols-outlined text-[15px]">error</span>
            {{ buy.err }}
          </div>
          <div class="flex items-center justify-end gap-2 pt-2">
            <button
              class="px-4 py-2 rounded-lg bg-surface-slate border border-hairline text-steel-muted hover:text-ink-white transition-all font-body-md text-body-md"
              :disabled="buy.submitting"
              @click="closeBuy"
            >
              取消
            </button>
            <button
              class="px-4 py-2 rounded-lg bg-primary-container text-ink-white hover:bg-primary-container/90 transition-all font-body-md text-body-md font-medium flex items-center gap-1.5 disabled:opacity-60 disabled:cursor-not-allowed"
              :disabled="buy.submitting"
              @click="confirmBuy"
            >
              <span v-if="buy.submitting" class="material-symbols-outlined text-[16px] animate-spin">progress_activity</span>
              {{ buy.submitting ? '提交中…' : buy.inviteWarn ? '继续购买' : '确认申购' }}
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- ===== 收益转本金弹窗 ===== -->
    <div
      v-if="cv.show"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 px-4"
      @click.self="closeConvert"
    >
      <div class="w-full max-w-md bg-card-navy border border-hairline rounded-xl p-6 shadow-[0_16px_48px_rgba(0,0,0,0.6)]">
        <div class="flex items-center justify-between mb-5 pb-3 border-b border-hairline">
          <h3 class="font-headline-md text-headline-md font-bold text-ink-white flex items-center gap-2">
            <span class="material-symbols-outlined text-primary-container">currency_exchange</span>
            收益转本金
          </h3>
          <button class="text-steel-muted hover:text-ink-white transition-colors" title="关闭" @click="closeConvert">
            <span class="material-symbols-outlined text-[20px]">close</span>
          </button>
        </div>
        <div class="flex flex-col gap-3">
          <div class="flex justify-between font-mono-data text-label-sm text-steel-muted">
            <span>收益账户可用</span>
            <span class="text-bull-green font-semibold">${{ fmtNum(account.income_balance) }}</span>
          </div>
          <div>
            <label class="font-label-sm text-label-sm text-steel-muted block mb-1">转化金额 (USDT)</label>
            <input
              v-model="cv.amount"
              type="number"
              min="0"
              step="0.01"
              placeholder="请输入转化金额"
              class="w-full bg-surface border border-hairline rounded-lg text-ink-white placeholder-steel-muted/60 text-body-md font-body-md px-3 py-2 focus:border-primary-container focus:ring-1 focus:ring-primary-container focus:outline-none transition-all"
              @keyup.enter="confirmConvert"
            />
          </div>
          <!-- 报价预览 -->
          <div v-if="cv.quoting" class="font-mono-data text-label-sm text-steel-muted flex items-center gap-1.5">
            <span class="material-symbols-outlined text-[15px] animate-spin">progress_activity</span>
            报价计算中…
          </div>
          <div v-else-if="cv.quote" class="bg-surface-slate border border-hairline rounded-lg p-3 font-mono-data text-label-sm space-y-1.5">
            <div class="flex justify-between text-steel-muted">
              <span>服务费 ({{ ratePct(cv.quote.rate).toFixed(2) }}%)</span>
              <span class="text-bear-red">-${{ fmtNum(cv.quote.service_fee) }}</span>
            </div>
            <div class="flex justify-between text-steel-muted">
              <span>实际到账本金</span>
              <span class="text-bull-green font-semibold">+${{ fmtNum(cv.quote.arrive_amount) }}</span>
            </div>
            <div class="flex justify-between text-steel-muted">
              <span>单笔下限</span>
              <span class="text-ink-white">{{ fmtNum(cv.quote.min_amount) }} USDT</span>
            </div>
          </div>
          <div v-if="cv.err" class="flex items-center gap-1.5 font-body-md text-[12px] text-bear-red bg-bear-red/10 border border-bear-red/30 rounded-lg px-3 py-2">
            <span class="material-symbols-outlined text-[15px]">error</span>
            {{ cv.err }}
          </div>
          <div class="flex items-center justify-end gap-2 pt-2">
            <button
              class="px-4 py-2 rounded-lg bg-surface-slate border border-hairline text-steel-muted hover:text-ink-white transition-all font-body-md text-body-md"
              :disabled="cv.submitting"
              @click="closeConvert"
            >
              取消
            </button>
            <button
              class="px-4 py-2 rounded-lg bg-primary-container text-ink-white hover:bg-primary-container/90 transition-all font-body-md text-body-md font-medium flex items-center gap-1.5 disabled:opacity-60 disabled:cursor-not-allowed"
              :disabled="cv.submitting"
              @click="confirmConvert"
            >
              <span v-if="cv.submitting" class="material-symbols-outlined text-[16px] animate-spin">progress_activity</span>
              {{ cv.submitting ? '提交中…' : '确认转化' }}
            </button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
