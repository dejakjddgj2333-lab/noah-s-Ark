<script setup>
import { onBeforeUnmount, onMounted, ref } from 'vue'
import * as echarts from 'echarts'
import { getAdminStats } from '@/api/admin'

const loading = ref(false)
const s = ref(null)
const cards = ref([])

const trendRef = ref()
const orderRef = ref()
const networkRef = ref()
const withdrawRef = ref()
let charts = []

function fmt(v) {
  const n = Number(v || 0)
  return n.toLocaleString('en-US', { maximumFractionDigits: 2 })
}

const NET_LABEL = { trc20: 'TRC20', erc20: 'ERC20', bep20: 'BEP20', arbitrum: 'Arbitrum' }
const WD_LABEL = { pending: '待审核', approved: '已打款', rejected: '已拒绝' }

function renderCharts() {
  charts.forEach((c) => c.dispose())
  charts = []
  const dates = (s.value.user_series || []).map((d) => d.date.slice(5))

  if (trendRef.value) {
    const c = echarts.init(trendRef.value)
    c.setOption({
      tooltip: { trigger: 'axis' },
      legend: { data: ['新增用户', '入账 USDT'], top: 0 },
      grid: { left: 50, right: 50, top: 36, bottom: 28 },
      xAxis: { type: 'category', data: dates, boundaryGap: false },
      yAxis: [
        { type: 'value', name: '用户', minInterval: 1 },
        { type: 'value', name: 'USDT', splitLine: { show: false } },
      ],
      series: [
        {
          name: '新增用户',
          type: 'line',
          smooth: true,
          data: (s.value.user_series || []).map((d) => d.value),
          lineStyle: { width: 3, color: '#4c6fff' },
          itemStyle: { color: '#4c6fff' },
          areaStyle: {
            color: {
              type: 'linear', x: 0, y: 0, x2: 0, y2: 1,
              colorStops: [
                { offset: 0, color: 'rgba(76,111,255,0.25)' },
                { offset: 1, color: 'rgba(76,111,255,0)' },
              ],
            },
          },
        },
        {
          name: '入账 USDT',
          type: 'line',
          smooth: true,
          yAxisIndex: 1,
          data: (s.value.deposit_series || []).map((d) => d.value),
          lineStyle: { width: 3, color: '#22c1a3' },
          itemStyle: { color: '#22c1a3' },
          areaStyle: {
            color: {
              type: 'linear', x: 0, y: 0, x2: 0, y2: 1,
              colorStops: [
                { offset: 0, color: 'rgba(34,193,163,0.25)' },
                { offset: 1, color: 'rgba(34,193,163,0)' },
              ],
            },
          },
        },
      ],
    })
    charts.push(c)
  }

  if (orderRef.value) {
    const c = echarts.init(orderRef.value)
    c.setOption({
      tooltip: { trigger: 'axis' },
      grid: { left: 60, right: 20, top: 30, bottom: 28 },
      xAxis: { type: 'category', data: dates },
      yAxis: { type: 'value', name: 'USDT' },
      series: [
        {
          name: '下单金额',
          type: 'bar',
          data: (s.value.order_series || []).map((d) => d.value),
          barMaxWidth: 22,
          itemStyle: {
            borderRadius: [6, 6, 0, 0],
            color: {
              type: 'linear', x: 0, y: 0, x2: 0, y2: 1,
              colorStops: [
                { offset: 0, color: '#8a5cff' },
                { offset: 1, color: '#4c6fff' },
              ],
            },
          },
        },
      ],
    })
    charts.push(c)
  }

  if (networkRef.value) {
    const data = (s.value.network_dist || []).map((d) => ({
      name: NET_LABEL[d.network] || d.network,
      value: d.amount,
    }))
    const c = echarts.init(networkRef.value)
    c.setOption({
      tooltip: { trigger: 'item', formatter: '{b}: {c} USDT ({d}%)' },
      legend: { bottom: 0 },
      series: [
        {
          type: 'pie',
          radius: ['45%', '70%'],
          center: ['50%', '45%'],
          itemStyle: { borderRadius: 6, borderColor: '#fff', borderWidth: 2 },
          label: { show: false },
          data: data.length ? data : [{ name: '暂无入账', value: 1, itemStyle: { color: '#e4e7ed' } }],
          color: ['#26a17b', '#627eea', '#f0b90b', '#28a0f0'],
        },
      ],
    })
    charts.push(c)
  }

  if (withdrawRef.value) {
    const data = (s.value.withdraw_status || []).map((d) => ({
      name: WD_LABEL[d.status] || d.status,
      value: d.count,
    }))
    const c = echarts.init(withdrawRef.value)
    c.setOption({
      tooltip: { trigger: 'item', formatter: '{b}: {c} 笔 ({d}%)' },
      legend: { bottom: 0 },
      series: [
        {
          type: 'pie',
          radius: ['45%', '70%'],
          center: ['50%', '45%'],
          itemStyle: { borderRadius: 6, borderColor: '#fff', borderWidth: 2 },
          label: { show: false },
          data: data.length ? data : [{ name: '暂无提现', value: 1, itemStyle: { color: '#e4e7ed' } }],
          color: ['#f7b733', '#22c1a3', '#ff5f6d'],
        },
      ],
    })
    charts.push(c)
  }
}

async function fetchStats() {
  loading.value = true
  try {
    s.value = await getAdminStats()
    cards.value = [
      { title: '总用户数', value: s.value.total_users, icon: 'User', from: '#4c6fff', to: '#6a5cff' },
      { title: '今日新增用户', value: s.value.today_users, icon: 'TrendCharts', from: '#22c1a3', to: '#38d9b8' },
      { title: '今日入账 (USDT)', value: fmt(s.value.deposit_today), icon: 'Money', from: '#f7b733', to: '#fc4a1a' },
      { title: '累计入账 (USDT)', value: fmt(s.value.deposit_total), icon: 'Coin', from: '#8a5cff', to: '#c26bff' },
      { title: '待审核提现', value: s.value.pending_withdrawals, icon: 'Wallet', from: '#ff5f6d', to: '#ff9966' },
      { title: '订单总额 (USDT)', value: fmt(s.value.order_total), icon: 'ShoppingCart', from: '#36a3f7', to: '#36d1f7' },
      { title: '在售产品', value: s.value.product_count, icon: 'Goods', from: '#5b86e5', to: '#36d1dc' },
    ]
    setTimeout(renderCharts, 0)
  } finally {
    loading.value = false
  }
}

function onResize() {
  charts.forEach((c) => c.resize())
}

onMounted(() => {
  fetchStats()
  window.addEventListener('resize', onResize)
})

onBeforeUnmount(() => {
  window.removeEventListener('resize', onResize)
  charts.forEach((c) => c.dispose())
})
</script>

<template>
  <div v-loading="loading">
    <el-row :gutter="16">
      <el-col v-for="item in cards" :key="item.title" :xs="24" :sm="12" :md="8" :lg="6">
        <div class="stat-card" :style="{ background: `linear-gradient(135deg, ${item.from}, ${item.to})` }">
          <el-icon :size="30" class="stat-icon"><component :is="item.icon" /></el-icon>
          <div class="stat-value">{{ item.value }}</div>
          <div class="stat-title">{{ item.title }}</div>
        </div>
      </el-col>
    </el-row>

    <el-card v-if="s && s.pending_withdrawals > 0" class="todo-card">
      <div class="todo-body">
        <el-icon :size="20" color="#ff5f6d"><BellFilled /></el-icon>
        <span>有 {{ s.pending_withdrawals }} 笔提现待审核</span>
        <el-button type="primary" size="small" @click="$router.push('/withdrawal/list')">
          去审核
        </el-button>
      </div>
    </el-card>

    <el-row :gutter="16" v-if="s">
      <el-col :xs="24" :md="16">
        <el-card shadow="never" class="chart-card">
          <div class="chart-title">近 14 天趋势</div>
          <div ref="trendRef" class="chart" />
        </el-card>
      </el-col>
      <el-col :xs="24" :md="8">
        <el-card shadow="never" class="chart-card">
          <div class="chart-title">入账网络分布</div>
          <div ref="networkRef" class="chart" />
        </el-card>
      </el-col>
      <el-col :xs="24" :md="16">
        <el-card shadow="never" class="chart-card">
          <div class="chart-title">近 14 天订单金额</div>
          <div ref="orderRef" class="chart" />
        </el-card>
      </el-col>
      <el-col :xs="24" :md="8">
        <el-card shadow="never" class="chart-card">
          <div class="chart-title">提现状态分布</div>
          <div ref="withdrawRef" class="chart" />
        </el-card>
      </el-col>
    </el-row>
  </div>
</template>

<style scoped>
.stat-card {
  border-radius: 14px;
  padding: 22px 20px;
  margin-bottom: 16px;
  color: #fff;
  box-shadow: 0 8px 20px rgba(16, 24, 64, 0.18);
}

.stat-icon {
  opacity: 0.85;
}

.stat-value {
  font-size: 26px;
  font-weight: 700;
  margin-top: 10px;
}

.stat-title {
  font-size: 13px;
  opacity: 0.85;
  margin-top: 4px;
}

.todo-card {
  margin-bottom: 16px;
}

.todo-body {
  display: flex;
  align-items: center;
  gap: 10px;
}

.chart-card {
  margin-bottom: 16px;
}

.chart-title {
  font-weight: 600;
  color: #303133;
  margin-bottom: 8px;
}

.chart {
  height: 300px;
}
</style>
