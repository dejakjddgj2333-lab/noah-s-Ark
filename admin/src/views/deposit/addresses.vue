<script setup>
import { onMounted, reactive, ref } from 'vue'
import { ElMessage } from 'element-plus'
import { generateDepositAddresses, getDepositAddresses, getDepositStats } from '@/api/deposit'

const loading = ref(false)
const generating = ref(false)
const stats = ref({})
const list = ref([])
const total = ref(0)
const query = reactive({ network: '', state: '', page: 1, pageSize: 20 })
const genForm = reactive({ network: 'trc20', count: 10 })

async function fetchStats() {
  stats.value = await getDepositStats()
}

async function fetchList() {
  loading.value = true
  try {
    const res = await getDepositAddresses(query)
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

async function handleGenerate() {
  generating.value = true
  try {
    const res = await generateDepositAddresses(genForm)
    ElMessage.success(`已生成 ${res.created} 个 ${res.network.toUpperCase()} 地址`)
    fetchStats()
    search()
  } finally {
    generating.value = false
  }
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
    <div class="page-head ph-teal">
      <div class="ph-icon"><el-icon><Wallet /></el-icon></div>
      <div>
        <div class="ph-title">充值地址池</div>
        <div class="ph-sub">地址分配 · 池水位管理</div>
      </div>
    </div>

    <el-row :gutter="12" class="stat-row">
      <el-col :span="6">
        <el-card shadow="never"><div class="stat-num">{{ stats.pool_free ?? '-' }}</div><div class="stat-label">空闲地址</div></el-card>
      </el-col>
      <el-col :span="6">
        <el-card shadow="never"><div class="stat-num">{{ stats.pool_assigned ?? '-' }}</div><div class="stat-label">已分配地址</div></el-card>
      </el-col>
      <el-col :span="6">
        <el-card shadow="never">
          <div class="gen-form">
            <el-select v-model="genForm.network" size="small" style="width: 110px">
              <el-option label="TRC20" value="trc20" />
              <el-option label="ERC20" value="erc20" />
              <el-option label="BEP20" value="bep20" />
              <el-option label="Arbitrum" value="arbitrum" />
            </el-select>
            <el-input-number v-model="genForm.count" :min="1" :max="200" size="small" />
            <el-button v-perm="'btn:deposit:generate'" type="primary" size="small" :loading="generating" @click="handleGenerate">生成地址</el-button>
          </div>
          <div class="stat-label">向地址池补充所选网络地址</div>
        </el-card>
      </el-col>
    </el-row>

    <el-card shadow="never">
      <div class="toolbar">
        <el-select v-model="query.network" placeholder="网络" clearable style="width: 130px">
          <el-option label="TRC20" value="trc20" />
          <el-option label="ERC20" value="erc20" />
          <el-option label="BEP20" value="bep20" />
          <el-option label="Arbitrum" value="arbitrum" />
        </el-select>
        <el-select v-model="query.state" placeholder="分配状态" clearable style="width: 140px">
          <el-option label="空闲" value="free" />
          <el-option label="已分配" value="assigned" />
        </el-select>
        <el-button type="primary" :icon="'Search'" @click="search">查询</el-button>
        <el-button :icon="'Refresh'" @click="fetchList">刷新</el-button>
      </div>

      <el-table v-loading="loading" :data="list" border stripe>
        <el-table-column prop="id" label="ID" width="70" />
        <el-table-column prop="network" label="网络" width="100">
          <template #default="{ row }">{{ row.network.toUpperCase() }}</template>
        </el-table-column>
        <el-table-column prop="address" label="地址" min-width="220" show-overflow-tooltip />
        <el-table-column label="分配用户" width="130">
          <template #default="{ row }">{{ row.username || '空闲' }}</template>
        </el-table-column>
        <el-table-column label="分配时间" width="160">
          <template #default="{ row }">{{ fmtTime(row.assigned_at) }}</template>
        </el-table-column>
        <el-table-column label="创建时间" width="160">
          <template #default="{ row }">{{ fmtTime(row.created_at) }}</template>
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
.stat-label { font-size: 12px; color: #909399; margin-top: 4px; }
.gen-form { display: flex; gap: 8px; align-items: center; }
.toolbar { display: flex; gap: 10px; margin-bottom: 12px; flex-wrap: wrap; }
</style>
