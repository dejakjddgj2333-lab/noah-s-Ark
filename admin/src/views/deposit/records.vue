<script setup>
import { computed, onMounted, reactive, ref } from 'vue'
import { getDepositRecords, getDepositStats } from '@/api/deposit'

const loading = ref(false)
const stats = ref({})
const list = ref([])
const total = ref(0)
const query = reactive({ status: '', network: '', username: '', page: 1, pageSize: 20 })

const STATUS_MAP = {
  confirming: { label: '确认中', type: 'warning' },
  credited: { label: '已入账', type: 'success' },
  unmatched: { label: '异常待处理', type: 'danger' },
}

async function fetchStats() {
  stats.value = await getDepositStats()
}

async function fetchList() {
  loading.value = true
  try {
    const res = await getDepositRecords(query)
    list.value = res.list
    total.value = res.total
  } finally {
    loading.value = false
  }
}

function search() {
  query.page = 1
  fetchList()
}

function shortTx(txid) {
  return txid ? `${txid.slice(0, 10)}...${txid.slice(-6)}` : '-'
}

function fmtTime(t) {
  return t ? t.replace('T', ' ').slice(0, 19) : '-'
}

const statCards = computed(() => [
  { title: '今日入账 (USDT)', value: stats.value.credited_today ?? '-', icon: 'Money', color: '#22c1a3' },
  { title: '确认中笔数', value: stats.value.confirming ?? '-', icon: 'Loading', color: '#f7b733' },
  { title: '异常待处理', value: stats.value.unmatched ?? '-', icon: 'WarningFilled', color: '#ff5f6d' },
  { title: '地址池空闲', value: stats.value.pool_free ?? '-', icon: 'Wallet', color: '#4c6fff' },
  { title: '地址池已分配', value: stats.value.pool_assigned ?? '-', icon: 'User', color: '#8a5cff' },
])

onMounted(() => {
  fetchStats()
  fetchList()
})
</script>

<template>
  <div>
    <div class="page-head ph-teal">
      <div class="ph-icon"><el-icon><Money /></el-icon></div>
      <div>
        <div class="ph-title">
          充值记录
          <span class="ph-chips">
            <span class="ph-chip ok"><i class="dot ok" />链上监控运行中</span>
            <span v-if="stats.unmatched" class="ph-chip warn"><i class="dot warn" />异常 {{ stats.unmatched }} 笔</span>
          </span>
        </div>
        <div class="ph-sub">链上入账监控 · 确认进度</div>
      </div>
      <div class="ph-right">
        <el-button :loading="loading" @click="fetchList">
          <el-icon style="margin-right: 4px"><Refresh /></el-icon>刷新数据
        </el-button>
      </div>
    </div>

    <!-- 概览卡片 -->
    <el-row :gutter="16" class="stat-row">
      <el-col v-for="c in statCards" :key="c.title" :xs="12" :sm="8" :md="4" style="flex: 1 0 0%">
        <div class="mini-stat" :style="{ '--sc': c.color }">
          <div class="ms-top">
            <span class="ms-label">{{ c.title }}</span>
            <span class="ms-icon"><el-icon :size="16"><component :is="c.icon" /></el-icon></span>
          </div>
          <div class="ms-num">{{ c.value }}</div>
        </div>
      </el-col>
    </el-row>

    <el-card shadow="never">
      <div class="toolbar">
        <el-select v-model="query.status" placeholder="状态" clearable style="width: 130px">
          <el-option label="确认中" value="confirming" />
          <el-option label="已入账" value="credited" />
          <el-option label="异常待处理" value="unmatched" />
        </el-select>
        <el-select v-model="query.network" placeholder="网络" clearable style="width: 130px">
          <el-option label="TRC20" value="trc20" />
        </el-select>
        <el-input v-model="query.username" placeholder="用户名" clearable style="width: 180px" @keyup.enter="search" />
        <el-button type="primary" :icon="'Search'" @click="search">查询</el-button>
      </div>

      <el-table v-loading="loading" :data="list" stripe>
        <el-table-column label="用户" min-width="140">
          <template #default="{ row }">
            <div class="cell-main" style="font-weight: 600">{{ row.username }}</div>
            <div class="cell-sub">单号 #{{ row.id }}</div>
          </template>
        </el-table-column>
        <el-table-column label="网络" width="100" align="center">
          <template #default="{ row }">
            <span class="net-tag" :class="row.network">{{ row.network.toUpperCase() }}</span>
          </template>
        </el-table-column>
        <el-table-column label="充值地址" min-width="150" show-overflow-tooltip>
          <template #default="{ row }">
            <span class="cell-main" style="font-family: monospace">{{ shortTx(row.address) }}</span>
          </template>
        </el-table-column>
        <el-table-column label="txid" min-width="140" show-overflow-tooltip>
          <template #default="{ row }">
            <span class="cell-main" style="font-family: monospace" :title="row.txid">{{ shortTx(row.txid) }}</span>
          </template>
        </el-table-column>
        <el-table-column label="金额 (USDT)" min-width="120" align="right">
          <template #default="{ row }">
            <div class="amt" style="color: #16a34a">+ {{ row.amount }}</div>
          </template>
        </el-table-column>
        <el-table-column label="确认数" width="100" align="center">
          <template #default="{ row }">
            <span class="cell-main">{{ row.confirmations }}/{{ row.required_confirmations }}</span>
          </template>
        </el-table-column>
        <el-table-column label="状态" width="110" align="center">
          <template #default="{ row }">
            <el-tag :type="STATUS_MAP[row.status]?.type" size="small" effect="light">{{ STATUS_MAP[row.status]?.label ?? row.status }}</el-tag>
          </template>
        </el-table-column>
        <el-table-column label="区块时间" min-width="150" align="center">
          <template #default="{ row }"><span class="cell-sub">{{ fmtTime(row.block_time) }}</span></template>
        </el-table-column>
        <el-table-column label="入账时间" min-width="150" align="center">
          <template #default="{ row }"><span class="cell-sub">{{ fmtTime(row.credited_at) }}</span></template>
        </el-table-column>
      </el-table>

      <div class="table-foot">
        <span class="cell-sub">共 {{ total }} 条充值记录</span>
        <el-pagination
          v-model:current-page="query.page"
          v-model:page-size="query.pageSize"
          :total="total"
          :page-sizes="[20, 50, 100]"
          layout="sizes, prev, pager, next"
          background
          @current-change="fetchList"
          @size-change="search"
        />
      </div>
    </el-card>
  </div>
</template>

<style scoped>
.stat-row { margin-bottom: 4px; }
.toolbar { display: flex; gap: 10px; margin-bottom: 14px; flex-wrap: wrap; }
</style>
