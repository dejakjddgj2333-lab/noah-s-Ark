<script setup>
import { onMounted, ref } from 'vue'
import { getAdminStats } from '@/api/admin'

const loading = ref(false)
const s = ref(null)

const cards = ref([])

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
  } finally {
    loading.value = false
  }
}

function fmt(v) {
  const n = Number(v || 0)
  return n.toLocaleString('en-US', { maximumFractionDigits: 2 })
}

onMounted(fetchStats)
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
  margin-top: 4px;
}

.todo-body {
  display: flex;
  align-items: center;
  gap: 10px;
}
</style>
