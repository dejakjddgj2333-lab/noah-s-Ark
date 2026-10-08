<script setup>
import { onMounted, reactive, ref } from 'vue'
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

onMounted(() => {
  fetchStats()
  fetchList()
})
</script>

<template>
  <div>
    <!-- 概览卡片 -->
    <el-row :gutter="12" class="stat-row">
      <el-col :span="5">
        <el-card shadow="never"><div class="stat-num">{{ stats.credited_today ?? '-' }}</div><div class="stat-label">今日入账 (USDT)</div></el-card>
      </el-col>
      <el-col :span="5">
        <el-card shadow="never"><div class="stat-num">{{ stats.confirming ?? '-' }}</div><div class="stat-label">确认中笔数</div></el-card>
      </el-col>
      <el-col :span="5">
        <el-card shadow="never"><div class="stat-num warn">{{ stats.unmatched ?? '-' }}</div><div class="stat-label">异常待处理</div></el-card>
      </el-col>
      <el-col :span="4">
        <el-card shadow="never"><div class="stat-num">{{ stats.pool_free ?? '-' }}</div><div class="stat-label">地址池空闲</div></el-card>
      </el-col>
      <el-col :span="5">
        <el-card shadow="never"><div class="stat-num">{{ stats.pool_assigned ?? '-' }}</div><div class="stat-label">地址池已分配</div></el-card>
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
        <el-button :icon="'Refresh'" @click="fetchList">刷新</el-button>
      </div>

      <el-table v-loading="loading" :data="list" border stripe>
        <el-table-column prop="id" label="ID" width="70" />
        <el-table-column prop="username" label="用户" width="120" show-overflow-tooltip />
        <el-table-column prop="network" label="网络" width="90">
          <template #default="{ row }">{{ row.network.toUpperCase() }}</template>
        </el-table-column>
        <el-table-column prop="address" label="充值地址" min-width="180" show-overflow-tooltip />
        <el-table-column label="txid" min-width="140" show-overflow-tooltip>
          <template #default="{ row }">{{ shortTx(row.txid) }}</template>
        </el-table-column>
        <el-table-column prop="amount" label="金额 (USDT)" width="120" align="right" />
        <el-table-column label="确认数" width="110" align="center">
          <template #default="{ row }">{{ row.confirmations }}/{{ row.required_confirmations }}</template>
        </el-table-column>
        <el-table-column label="状态" width="110" align="center">
          <template #default="{ row }">
            <el-tag :type="STATUS_MAP[row.status]?.type">{{ STATUS_MAP[row.status]?.label ?? row.status }}</el-tag>
          </template>
        </el-table-column>
        <el-table-column label="区块时间" width="160">
          <template #default="{ row }">{{ fmtTime(row.block_time) }}</template>
        </el-table-column>
        <el-table-column label="入账时间" width="160">
          <template #default="{ row }">{{ fmtTime(row.credited_at) }}</template>
        </el-table-column>
      </el-table>

      <el-pagination
        v-model:current-page="query.page"
        v-model:page-size="query.pageSize"
        :total="total"
        :page-sizes="[20, 50, 100]"
        layout="total, sizes, prev, pager, next"
        style="margin-top: 12px; justify-content: flex-end"
        @current-change="fetchList"
        @size-change="search"
      />
    </el-card>
  </div>
</template>

<style scoped>
.stat-row { margin-bottom: 12px; }
.stat-num { font-size: 22px; font-weight: 700; }
.stat-num.warn { color: #f56c6c; }
.stat-label { font-size: 12px; color: #909399; margin-top: 4px; }
.toolbar { display: flex; gap: 10px; margin-bottom: 12px; flex-wrap: wrap; }
</style>
