<script setup>
import { computed, onMounted, ref } from 'vue'
import { productApi, orderApi, settlementApi } from '../api'
import { fmtNum } from '../utils/format'

const products = ref([])
const orders = ref([])
const summary = ref({})
const loading = ref(true)
const tab = ref('all')
const autoRenew = ref(true)

const METHOD = { daily: '每日返息', maturity: '到期还本付息' }

async function load() {
  try {
    const [p, o, s] = await Promise.allSettled([
      productApi.list(),
      orderApi.list({ page_size: 50 }),
      settlementApi.commissionsSummary(),
    ])
    if (p.status === 'fulfilled') products.value = p.value || []
    if (o.status === 'fulfilled') orders.value = o.value?.items || o.value || []
    if (s.status === 'fulfilled') summary.value = s.value || {}
  } finally {
    loading.value = false
  }
}

// 日化 -> 年化展示
function annual(p) {
  return (Number(p.base_daily_rate) * 365 * 100).toFixed(2) + '%'
}

const isActive = (o) => o.status === 'active' || o.status === 'holding'
const activeOrders = computed(() => orders.value.filter(isActive))
const doneOrders = computed(() => orders.value.filter((o) => !isActive(o)))
const shownOrders = computed(() =>
  tab.value === 'active' ? activeOrders.value : tab.value === 'done' ? doneOrders.value : orders.value,
)

const totalPrincipal = computed(() =>
  activeOrders.value.reduce((s, o) => s + Number(o.amount || 0), 0),
)
const totalProfit = computed(() =>
  orders.value.reduce((s, o) => s + Number(o.expected_return || 0), 0),
)
const totalCommission = computed(() => summary.value.total_commission ?? summary.value.total ?? 0)

function curValue(o) {
  const v = Number(o.amount || 0) + Number(o.expected_return || 0)
  return fmtNum(v)
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
            <span class="text-steel-muted">邀请返佣累计入账</span>
          </div>
        </div>
        <div class="pt-2 border-t border-hairline/60 flex items-center justify-between text-label-sm font-mono-data">
          <span class="text-steel-muted">结算方式</span>
          <span class="text-bull-green font-semibold flex items-center gap-0.5">
            <span class="material-symbols-outlined text-[14px]">arrow_drop_up</span>
            每日自动结算
          </span>
        </div>
      </div>
      <!-- Card 2: 累计收益 -->
      <div class="bg-card-navy rounded-xl border border-hairline p-space-md flex flex-col justify-between hover:border-hairline/80 transition-colors">
        <div class="flex items-center justify-between text-steel-muted font-mono-data text-label-sm">
          <div class="flex items-center gap-1.5">
            <span class="material-symbols-outlined text-bull-green text-[17px]">trending_up</span>
            <span class="tracking-wider">累计收益 CUMULATIVE PnL</span>
          </div>
          <span class="text-[10px] bg-bull-green/10 text-bull-green px-1.5 py-0.5 rounded border border-bull-green/30">理财订单</span>
        </div>
        <div class="my-2.5">
          <div class="font-mono-data text-[30px] font-bold tracking-tight text-bull-green flex items-baseline gap-2">
            <span>+${{ fmtNum(totalProfit) }}</span>
          </div>
          <div class="flex items-center gap-2 font-mono-data text-label-sm mt-0.5">
            <span class="text-steel-muted">全部订单预期收益合计</span>
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
            <span class="text-headline-sm font-headline-sm text-steel-muted font-normal">笔进行中</span>
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
      <div class="flex flex-wrap items-center justify-between gap-3">
        <div class="flex items-center gap-2">
          <span class="text-headline-md font-headline-md font-bold text-ink-white">理财产品 WEALTH PRODUCTS</span>
          <span class="text-label-sm font-mono-data text-steel-muted">低风险 · 高流动性 · 智能计息</span>
        </div>
      </div>
      <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div
          v-for="p in products"
          :key="p.id"
          class="bg-card-navy rounded-xl border border-hairline p-space-md flex flex-col justify-between hover:border-primary-container/60 transition-colors group"
        >
          <div>
            <div class="flex items-center justify-between mb-2">
              <span class="text-[11px] font-mono-data font-semibold text-primary bg-primary-container/15 border border-primary-container/30 px-2 py-0.5 rounded">
                {{ METHOD[p.return_method] || '稳健增利' }} · {{ p.duration_days }}天定期
              </span>
              <span class="material-symbols-outlined text-steel-muted group-hover:text-primary transition-colors text-[18px]">verified</span>
            </div>
            <h3 class="text-headline-sm font-headline-sm font-semibold text-ink-white mt-1">
              {{ p.name }}
            </h3>
            <div class="mt-4 mb-3">
              <div class="text-[11px] font-mono-data text-steel-muted uppercase tracking-wider">参考年化 (APY)</div>
              <div class="text-[34px] font-mono-data font-bold text-bull-green tracking-tight leading-none mt-1">
                {{ annual(p) }}
              </div>
            </div>
            <div class="space-y-1.5 py-3 border-t border-hairline/60 font-mono-data text-label-sm">
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
            <p v-if="p.description" class="text-body-md font-body-md text-steel-muted mt-1">{{ p.description }}</p>
          </div>
          <div>
            <button
              class="w-full bg-card-navy border border-hairline text-steel-muted font-mono-data text-mono-data py-2 px-4 rounded-lg flex items-center justify-center gap-1.5 cursor-not-allowed opacity-60 mt-4"
              disabled
            >
              <span class="material-symbols-outlined text-[16px]">smartphone</span>
              <span>App 内申购</span>
            </button>
          </div>
        </div>
        <div
          v-if="!products.length"
          class="bg-card-navy rounded-xl border border-hairline p-space-md text-steel-muted font-mono-data text-mono-data text-center md:col-span-3"
        >
          暂无上架产品
        </div>
      </div>
    </section>

    <!-- ROW 3: MY POSITIONS TABLE -->
    <section class="bg-card-navy rounded-xl border border-hairline p-space-md flex flex-col mb-4" id="positions">
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
              已到期 ({{ doneOrders.length }})
            </button>
          </div>
        </div>
        <div class="flex items-center gap-3">
          <label class="flex items-center gap-2 cursor-pointer text-label-sm font-mono-data text-steel-muted select-none">
            <span>到期自动续投</span>
            <div class="relative inline-flex items-center cursor-pointer">
              <input v-model="autoRenew" class="sr-only peer" type="checkbox" />
              <div class="w-8 h-4 bg-surface-slate peer-focus:outline-none rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-ink-white after:border-hairline after:border after:rounded-full after:h-3 after:w-3 after:transition-all peer-checked:bg-primary-container border border-hairline"></div>
            </div>
          </label>
          <button class="p-1 text-steel-muted hover:text-ink-white hover:bg-surface-slate rounded border border-hairline" title="Refresh Table" @click="load">
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
              <th class="py-3 px-3 text-right font-semibold">投入本金 (Principal)</th>
              <th class="py-3 px-3 text-right font-semibold">当前价值 (Current Value)</th>
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
                      {{ o.product_name || o.product?.name || `#${o.product_id}` }}
                    </div>
                    <div class="text-[11px] text-steel-muted">订单 #{{ o.id }}</div>
                  </div>
                </div>
              </td>
              <td class="py-3.5 px-3 text-right font-medium" :class="isActive(o) ? 'text-ink-white' : 'text-steel-muted'">
                {{ fmtNum(o.amount) }} USDT
              </td>
              <td class="py-3.5 px-3 text-right font-bold" :class="isActive(o) ? 'text-ink-white' : 'text-steel-muted'">
                {{ curValue(o) }} USDT
              </td>
              <td class="py-3.5 px-3 text-right font-semibold" :class="isActive(o) ? 'text-bull-green' : 'text-steel-muted'">
                {{ o.expected_return != null ? '+$' + fmtNum(o.expected_return) : '--' }}
              </td>
              <td class="py-3.5 px-3 text-center text-steel-muted text-[12px]">
                <div :class="{ 'text-ink-white': isActive(o) }">{{ (o.start_at || '').slice(0, 10) || '--' }}</div>
              </td>
              <td class="py-3.5 px-3 text-center text-steel-muted text-[12px]">
                <div :class="{ 'text-ink-white': isActive(o) }">{{ (o.end_at || o.mature_at || '').slice(0, 10) || '--' }}</div>
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
                  {{ o.status }}
                </span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
  </div>
</template>
