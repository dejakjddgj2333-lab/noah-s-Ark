<script setup>
import { computed, onMounted, ref } from 'vue'
import { teamApi, settlementApi } from '../api'
import { fmtNum, fmtDateTime, ts } from '../utils/format'

// 团队等级表: [等级, 有效人数≥, 有效持仓≥, 一代%, 二代%, 三代%] (与 App team_page 一致)
const TEAM_TABLE = [
  [0, 0, 0, 5.0, 0.0, 0.0],
  [1, 5, 6000, 5.0, 3.0, 0.0],
  [2, 10, 12000, 5.0, 3.0, 2.0],
  [3, 20, 24000, 5.2, 3.1, 2.1],
  [4, 40, 48000, 5.6, 3.3, 2.3],
  [5, 70, 84000, 6.2, 3.6, 2.6],
  [6, 120, 144000, 7.0, 4.0, 3.0],
  [7, 200, 240000, 8.0, 4.5, 3.5],
  [8, 350, 420000, 9.2, 5.1, 4.1],
  [9, 600, 720000, 10.6, 5.8, 4.8],
  [10, 1000, 1200000, 12.2, 6.6, 5.6],
]

const info = ref(null)
const logs = ref([])
const loading = ref(true)
const err = ref('')

const level = computed(() => info.value?.team_level ?? 0)
const memberCount = computed(() => info.value?.member_count ?? 0)
const totalHolding = computed(() => Number(info.value?.total_holding ?? 0))
const nextRow = computed(() => TEAM_TABLE.find((r) => r[0] === level.value + 1) || null)
const memberPct = computed(() =>
  nextRow.value ? Math.min((memberCount.value / nextRow.value[1]) * 100, 100) : 100,
)
const holdingPct = computed(() =>
  nextRow.value ? Math.min((totalHolding.value / nextRow.value[2]) * 100, 100) : 100,
)

async function load() {
  loading.value = true
  err.value = ''
  try {
    const [t, l] = await Promise.allSettled([teamApi.me(), settlementApi.levelLogs('team')])
    if (t.status === 'fulfilled') info.value = t.value
    else err.value = t.reason?.message || '团队信息加载失败'
    if (l.status === 'fulfilled') logs.value = (l.value || []).slice(0, 8)
  } finally {
    loading.value = false
  }
}

onMounted(load)
</script>

<template>
  <div class="flex flex-col gap-space-lg w-full max-w-6xl mx-auto">
    <div v-if="loading" class="py-16 text-center text-steel-muted font-mono-data text-mono-data">加载中…</div>
    <div v-else-if="err" class="py-16 text-center text-bear-red font-mono-data text-mono-data">{{ err }}</div>

    <template v-else>
      <!-- 等级总览 -->
      <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
        <!-- 当前等级 -->
        <div class="p-6 rounded-xl bg-card-navy border border-hairline relative overflow-hidden">
          <div class="absolute -top-20 -right-14 w-56 h-56 rounded-full bg-primary-container/10 blur-3xl pointer-events-none"></div>
          <div class="font-label-sm text-label-sm text-steel-muted uppercase mb-3">团队等级 TEAM LEVEL</div>
          <div class="flex items-end gap-3">
            <span class="font-headline-lg text-[44px] leading-none font-bold text-primary-container">V{{ level }}</span>
            <span v-if="!nextRow" class="font-label-sm text-label-sm text-amber-warn pb-1.5">已满级 MAX</span>
          </div>
          <div class="mt-4 space-y-2 font-mono-data text-mono-data">
            <div class="flex justify-between">
              <span class="text-steel-muted">三代有效人数</span>
              <span class="text-ink-white font-semibold">{{ memberCount }} 人</span>
            </div>
            <div class="flex justify-between">
              <span class="text-steel-muted">团队有效持仓</span>
              <span class="text-ink-white font-semibold">${{ fmtNum(totalHolding) }}</span>
            </div>
          </div>
        </div>

        <!-- 升级进度 -->
        <div class="p-6 rounded-xl bg-card-navy border border-hairline">
          <div class="font-label-sm text-label-sm text-steel-muted uppercase mb-3">
            {{ nextRow ? `距 V${nextRow[0]} 升级进度` : '升级进度' }}
          </div>
          <template v-if="nextRow">
            <div class="mb-4">
              <div class="flex justify-between font-mono-data text-label-sm mb-1.5">
                <span class="text-steel-muted">有效人数</span>
                <span class="text-ink-white">{{ memberCount }} / {{ nextRow[1] }}</span>
              </div>
              <div class="w-full h-2 bg-surface-slate rounded-full overflow-hidden border border-hairline">
                <div class="h-full bg-primary-container rounded-full transition-all" :style="{ width: memberPct + '%' }"></div>
              </div>
              <div class="font-label-sm text-label-sm text-steel-muted mt-1">还差 {{ info?.next_member_gap ?? 0 }} 人</div>
            </div>
            <div>
              <div class="flex justify-between font-mono-data text-label-sm mb-1.5">
                <span class="text-steel-muted">有效持仓</span>
                <span class="text-ink-white">${{ fmtNum(totalHolding) }} / ${{ fmtNum(nextRow[2]) }}</span>
              </div>
              <div class="w-full h-2 bg-surface-slate rounded-full overflow-hidden border border-hairline">
                <div class="h-full bg-bull-green rounded-full transition-all" :style="{ width: holdingPct + '%' }"></div>
              </div>
              <div class="font-label-sm text-label-sm text-steel-muted mt-1">还差 ${{ fmtNum(info?.next_holding_gap ?? 0) }}</div>
            </div>
          </template>
          <div v-else class="py-8 text-center text-amber-warn font-mono-data text-mono-data">已达最高等级</div>
        </div>

        <!-- 当前返佣比例 -->
        <div class="p-6 rounded-xl bg-card-navy border border-hairline">
          <div class="font-label-sm text-label-sm text-steel-muted uppercase mb-3">当前返佣比例 REBATES</div>
          <div class="grid grid-cols-3 gap-2">
            <div v-for="g in [1, 2, 3]" :key="g" class="p-3 rounded-lg bg-surface-slate border border-hairline text-center">
              <div class="font-label-sm text-label-sm text-steel-muted mb-1">{{ ['', '一代', '二代', '三代'][g] }}</div>
              <div
                class="font-mono-data text-[18px] font-bold"
                :class="Number(info?.[`gen${g}_rate`]) > 0 ? 'text-bull-green' : 'text-steel-muted'"
              >
                {{ info?.[`gen${g}_rate`] ?? '0' }}%
              </div>
            </div>
          </div>
          <p class="font-label-sm text-label-sm text-steel-muted mt-3 flex items-center gap-1">
            <span class="material-symbols-outlined text-[13px]">info</span>
            比例 0 表示该代暂无返佣资格
          </p>
        </div>
      </div>

      <!-- 等级表 -->
      <div class="bg-card-navy border border-hairline rounded-xl p-6">
        <div class="flex items-center justify-between mb-5 pb-3 border-b border-hairline">
          <h3 class="font-headline-md text-headline-md font-bold text-ink-white tracking-tight flex items-center gap-2">
            <span class="material-symbols-outlined text-primary-container">military_tech</span>
            等级权益表 LEVEL TABLE
          </h3>
          <span class="font-label-sm text-label-sm text-steel-muted">有效 = 下级有持仓</span>
        </div>
        <div class="overflow-x-auto">
          <table class="w-full text-left border-collapse">
            <thead>
              <tr class="border-b border-hairline text-steel-muted font-mono-data text-[11px] uppercase tracking-wider">
                <th class="py-3 px-3 font-semibold">等级</th>
                <th class="py-3 px-3 font-semibold text-right">有效人数 ≥</th>
                <th class="py-3 px-3 font-semibold text-right">有效持仓 ≥</th>
                <th class="py-3 px-3 font-semibold text-right">一代</th>
                <th class="py-3 px-3 font-semibold text-right">二代</th>
                <th class="py-3 px-3 font-semibold text-right">三代</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-hairline font-mono-data text-mono-data">
              <tr
                v-for="r in TEAM_TABLE"
                :key="r[0]"
                class="transition-colors"
                :class="r[0] === level ? 'bg-primary-container/10 border-l-2 border-primary-container' : 'hover:bg-card-navy-high/50'"
              >
                <td class="py-2.5 px-3">
                  <span
                    class="font-bold"
                    :class="r[0] === level ? 'text-primary-container' : 'text-ink-white'"
                  >V{{ r[0] }}</span>
                  <span v-if="r[0] === level" class="ml-2 text-[10px] px-1.5 py-0.5 rounded bg-primary-container/20 text-primary-fixed-dim border border-primary-container/40">当前</span>
                </td>
                <td class="py-2.5 px-3 text-right text-steel-muted">{{ r[1] }}</td>
                <td class="py-2.5 px-3 text-right text-steel-muted">${{ fmtNum(r[2]) }}</td>
                <td class="py-2.5 px-3 text-right text-bull-green">{{ r[3] }}%</td>
                <td class="py-2.5 px-3 text-right" :class="r[4] > 0 ? 'text-bull-green' : 'text-steel-muted/50'">{{ r[4] }}%</td>
                <td class="py-2.5 px-3 text-right" :class="r[5] > 0 ? 'text-bull-green' : 'text-steel-muted/50'">{{ r[5] }}%</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <!-- 等级变动日志 -->
      <div v-if="logs.length" class="bg-card-navy border border-hairline rounded-xl p-6">
        <div class="flex items-center justify-between mb-5 pb-3 border-b border-hairline">
          <h3 class="font-headline-md text-headline-md font-bold text-ink-white tracking-tight flex items-center gap-2">
            <span class="material-symbols-outlined text-primary-container">history</span>
            等级变动记录
          </h3>
        </div>
        <div class="divide-y divide-hairline font-mono-data text-mono-data">
          <div v-for="log in logs" :key="log.id" class="py-3 flex items-center justify-between gap-3">
            <div class="flex items-center gap-2.5">
              <span class="material-symbols-outlined text-[16px] text-bull-green">arrow_upward</span>
              <span class="text-ink-white">升至 V{{ log.level }}</span>
              <span class="text-steel-muted text-label-sm">持仓 ${{ fmtNum(log.holding ?? 0) }} · {{ log.member_count ?? 0 }} 人</span>
            </div>
            <span class="text-steel-muted text-label-sm">{{ log.created_at ? fmtDateTime(ts(log.created_at)) : '--' }}</span>
          </div>
        </div>
      </div>
    </template>
  </div>
</template>
