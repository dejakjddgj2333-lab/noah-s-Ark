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

// 主题感知图表配色 (渲染时读取当前明暗)
const isDark = () => document.documentElement.classList.contains('dark')
const axisConf = () => ({ axisLabel: { color: '#9aa3b5' }, axisLine: { lineStyle: { color: isDark() ? 'rgba(255,255,255,0.12)' : 'rgba(16,24,64,0.15)' } }, splitLine: { lineStyle: { color: isDark() ? 'rgba(255,255,255,0.06)' : 'rgba(16,24,64,0.07)' } }, nameTextStyle: { color: '#9aa3b5' } })
const ttConf = () => ({ backgroundColor: isDark() ? '#161b26' : '#ffffff', borderColor: isDark() ? 'rgba(255,255,255,0.1)' : 'rgba(16,24,64,0.12)', textStyle: { color: isDark() ? '#e8eaf0' : '#303133' } })
const pieBorder = () => (isDark() ? '#10131a' : '#ffffff')
const pieEmpty = () => (isDark() ? '#2a3040' : '#e4e7ed')
const LEGEND_TXT = { textStyle: { color: '#9aa3b5' } }

function renderCharts() {
  charts.forEach((c) => c.dispose())
  charts = []
  const dates = (s.value.user_series || []).map((d) => d.date.slice(5))

  if (trendRef.value) {
    const c = echarts.init(trendRef.value)
    c.setOption({
      tooltip: { trigger: 'axis', ...ttConf() },
      legend: { data: ['新增用户', '入账 USDT'], top: 0, ...LEGEND_TXT },
      grid: { left: 50, right: 50, top: 36, bottom: 28 },
      xAxis: { type: 'category', data: dates, boundaryGap: false, ...axisConf() },
      yAxis: [
        { type: 'value', name: '用户', minInterval: 1, ...axisConf() },
        { type: 'value', name: 'USDT', splitLine: { show: false }, ...axisConf() },
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
      tooltip: { trigger: 'axis', ...ttConf() },
      grid: { left: 60, right: 20, top: 30, bottom: 28 },
      xAxis: { type: 'category', data: dates, ...axisConf() },
      yAxis: { type: 'value', name: 'USDT', ...axisConf() },
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
      tooltip: { trigger: 'item', formatter: '{b}: {c} USDT ({d}%)', ...ttConf() },
      legend: { bottom: 0, ...LEGEND_TXT },
      series: [
        {
          type: 'pie',
          radius: ['45%', '70%'],
          center: ['50%', '45%'],
          itemStyle: { borderRadius: 6, borderColor: pieBorder(), borderWidth: 2 },
          label: { show: false },
          data: data.length ? data : [{ name: '暂无入账', value: 1, itemStyle: { color: pieEmpty() } }],
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
      tooltip: { trigger: 'item', formatter: '{b}: {c} 笔 ({d}%)', ...ttConf() },
      legend: { bottom: 0, ...LEGEND_TXT },
      series: [
        {
          type: 'pie',
          radius: ['45%', '70%'],
          center: ['50%', '45%'],
          itemStyle: { borderRadius: 6, borderColor: pieBorder(), borderWidth: 2 },
          label: { show: false },
          data: data.length ? data : [{ name: '暂无提现', value: 1, itemStyle: { color: pieEmpty() } }],
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

    // 周环比: 近 7 天新增 vs 前 7 天
    const series = (s.value.user_series || []).map((d) => d.value)
    const cur7 = series.slice(-7).reduce((a, b) => a + b, 0)
    const prev7 = series.slice(-14, -7).reduce((a, b) => a + b, 0)
    const wow = prev7 > 0 ? ((cur7 - prev7) / prev7) * 100 : null
    const wowText = wow === null ? '首周数据累计中' : `${wow >= 0 ? '↗ +' : '↘ '}${wow.toFixed(1)}% 较上周`

    // 今日新增 vs 昨日
    const today = series[series.length - 1] || 0
    const yesterday = series[series.length - 2] || 0
    const dd = today - yesterday
    const dayText = dd === 0 ? '与昨日持平' : `较昨日 ${dd > 0 ? '+' : ''}${dd} 人`

    const pending = s.value.pending_withdrawals || 0
    cards.value = [
      { title: '总用户数', value: s.value.total_users, unit: '位', icon: 'User', color: '#4c6fff', caption: wowText, capClass: wow !== null && wow < 0 ? 'down' : 'up', span: 6 },
      { title: '今日新增用户', value: s.value.today_users, unit: '人', icon: 'UserFilled', color: '#22c1a3', caption: dayText, capClass: dd < 0 ? 'down' : '', span: 6 },
      { title: '今日入账 (USDT)', value: fmt(s.value.deposit_today), unit: 'USDT', icon: 'Money', color: '#f7b733', caption: '当日资金流水待确认', capClass: '', span: 6 },
      { title: '累计入账 (USDT)', value: fmt(s.value.deposit_total), unit: 'USDT', icon: 'Coin', color: '#8a5cff', caption: '历史总链上充值汇总', capClass: '', span: 6 },
      { title: '待审核提现', value: pending, unit: '笔待办', icon: 'Wallet', color: '#ff5f6d', caption: pending > 0 ? `有 ${pending} 笔提现等待审核` : '队列畅通 · 无堆积审核', capClass: pending > 0 ? 'down' : 'up', span: 6 },
      { title: '订单总额 (USDT)', value: fmt(s.value.order_total), unit: 'USDT', icon: 'ShoppingCart', color: '#36a3f7', caption: '全部产品订单金额合计', capClass: '', tag: '核心营运指标', span: 12 },
      { title: '在售产品', value: s.value.product_count, unit: '件', icon: 'Goods', color: '#14b8a6', caption: '正常上架销售中', capClass: 'up', span: 6 },
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
    <!-- 页头: 标题 + 结算通证 + 刷新 -->
    <div class="dash-head">
      <div>
        <div class="dash-title">运营概况看板</div>
        <div class="dash-sub">实时统计监控系统用户、资金流转与订单动态</div>
      </div>
      <div class="dash-actions">
        <span class="settle-pill"><i class="settle-dot" />结算通证: USDT (TRC20/ERC20)</span>
        <el-button type="primary" @click="fetchStats">
          <el-icon style="margin-right: 4px"><Refresh /></el-icon>刷新数据
        </el-button>
      </div>
    </div>

    <el-row :gutter="16">
      <el-col v-for="item in cards" :key="item.title" :xs="24" :sm="12" :md="item.span >= 12 ? 12 : 8" :lg="item.span">
        <div class="stat-card" :style="{ '--sc': item.color }">
          <div class="sc-top">
            <div class="sc-label">
              {{ item.title }}
              <span v-if="item.tag" class="sc-tag">{{ item.tag }}</span>
            </div>
            <div class="sc-icon"><el-icon :size="18"><component :is="item.icon" /></el-icon></div>
          </div>
          <div class="sc-num">{{ item.value }}<span class="sc-unit">{{ item.unit }}</span></div>
          <div class="sc-cap" :class="item.capClass">{{ item.caption }}</div>
        </div>
      </el-col>
    </el-row>

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
/* 页头 */
.dash-head {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  flex-wrap: wrap;
  gap: 12px;
  margin-bottom: 18px;
}

.dash-title {
  font-size: 22px;
  font-weight: 700;
  color: var(--app-text);
}

.dash-sub {
  margin-top: 5px;
  font-size: 12px;
  color: var(--app-text-2);
}

.dash-actions {
  display: flex;
  align-items: center;
  gap: 12px;
}

.settle-pill {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 7px 14px;
  border-radius: 18px;
  font-size: 12px;
  color: var(--app-text-2);
  background: var(--app-surface);
  border: 1px solid var(--app-line);
}

.settle-dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: #4c6fff;
}

/* 统计卡: 浅色渐变 + 右上彩色图标, 深浅主题自适应 */
.stat-card {
  border-radius: 14px;
  padding: 18px 20px 16px;
  margin-bottom: 16px;
  border: 1px solid var(--app-line);
  background: linear-gradient(
    135deg,
    color-mix(in srgb, var(--sc) 9%, var(--app-surface)) 0%,
    var(--app-surface) 72%
  );
  box-shadow: 0 1px 3px rgba(16, 24, 64, 0.05);
  transition: box-shadow 0.25s ease;
}

html.dark .stat-card {
  background: linear-gradient(
    135deg,
    color-mix(in srgb, var(--sc) 17%, var(--app-surface)) 0%,
    var(--app-surface) 78%
  );
  box-shadow: 0 4px 16px rgba(0, 0, 0, 0.25);
}

.stat-card:hover {
  box-shadow: 0 8px 24px color-mix(in srgb, var(--sc) 18%, transparent);
}

.sc-top {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
}

.sc-label {
  font-size: 13px;
  color: var(--app-text-2);
  display: flex;
  align-items: center;
  gap: 8px;
}

.sc-tag {
  font-size: 11px;
  padding: 1px 8px;
  border-radius: 10px;
  color: var(--sc);
  background: color-mix(in srgb, var(--sc) 12%, transparent);
}

.sc-icon {
  width: 36px;
  height: 36px;
  flex: none;
  border-radius: 10px;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--sc);
  background: color-mix(in srgb, var(--sc) 14%, transparent);
}

.sc-num {
  margin-top: 12px;
  font-size: 28px;
  font-weight: 700;
  line-height: 1.2;
  color: var(--app-text);
  font-variant-numeric: tabular-nums;
}

.sc-unit {
  margin-left: 6px;
  font-size: 12px;
  font-weight: 600;
  color: var(--sc);
}

.sc-cap {
  margin-top: 8px;
  font-size: 12px;
  color: var(--app-text-2);
}

.sc-cap.up {
  color: #16a34a;
}

html.dark .sc-cap.up {
  color: #34d399;
}

.sc-cap.down {
  color: #ff5f6d;
}

.chart-card {
  margin-bottom: 16px;
}

.chart-title {
  font-weight: 600;
  color: var(--app-text);
  margin-bottom: 8px;
}

.chart {
  height: 300px;
}
</style>
