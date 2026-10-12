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
        <div class="ph-title">
          充值地址池
          <span class="ph-chips">
            <span class="ph-chip ok"><i class="dot ok" />空闲 {{ stats.pool_free ?? 0 }}</span>
            <span class="ph-chip info">已分配 {{ stats.pool_assigned ?? 0 }}</span>
          </span>
        </div>
        <div class="ph-sub">地址分配 · 池水位管理</div>
      </div>
      <div class="ph-right">
        <el-button :loading="loading" @click="fetchList">
          <el-icon style="margin-right: 4px"><Refresh /></el-icon>刷新数据
        </el-button>
      </div>
    </div>

    <el-card shadow="never">
      <div class="toolbar">
        <el-select v-model="query.network" placeholder="网络" clearable style="width: 130px">
          <el-option label="TRC20" value="trc20" />
          <el-option label="ERC20" value="erc20" />
          <el-option label="BEP20" value="bep20" />
          <el-option label="Arbitrum" value="arbitrum" />
        </el-select>
        <el-radio-group :model-value="query.state" @change="(v) => { query.state = v; search() }">
          <el-radio-button value="">全部</el-radio-button>
          <el-radio-button value="free">空闲</el-radio-button>
          <el-radio-button value="assigned">已分配</el-radio-button>
        </el-radio-group>
        <el-button type="primary" :icon="'Search'" @click="search">查询</el-button>
        <div style="margin-left: auto; display: flex; gap: 8px; align-items: center">
          <el-select v-model="genForm.network" size="small" style="width: 110px">
            <el-option label="TRC20" value="trc20" />
            <el-option label="ERC20" value="erc20" />
            <el-option label="BEP20" value="bep20" />
            <el-option label="Arbitrum" value="arbitrum" />
          </el-select>
          <el-input-number v-model="genForm.count" :min="1" :max="200" size="small" />
          <el-button v-perm="'btn:deposit:generate'" type="primary" size="small" :loading="generating" @click="handleGenerate">
            <el-icon style="margin-right: 4px"><Plus /></el-icon>生成地址
          </el-button>
        </div>
      </div>
      <div class="alert-bar">
        <el-icon><InfoFilled /></el-icon>
        地址池水位不足时用户充值会分配失败, 请保持空闲地址充足; 生成地址仅补充所选网络。
      </div>

      <el-table v-loading="loading" :data="list" stripe>
        <el-table-column label="地址" min-width="240">
          <template #default="{ row }">
            <div class="cell-main" style="font-family: monospace">{{ row.address }}</div>
            <div class="cell-sub">创建于 {{ fmtTime(row.created_at) }}</div>
          </template>
        </el-table-column>
        <el-table-column label="网络" width="100" align="center">
          <template #default="{ row }">
            <span class="net-tag" :class="row.network">{{ row.network.toUpperCase() }}</span>
          </template>
        </el-table-column>
        <el-table-column label="分配用户" min-width="140" show-overflow-tooltip>
          <template #default="{ row }">
            <span v-if="row.username" class="cell-main" style="font-weight: 600">{{ row.username }}</span>
            <el-tag v-else type="success" size="small" effect="plain">空闲</el-tag>
          </template>
        </el-table-column>
        <el-table-column label="分配时间" min-width="150" align="center">
          <template #default="{ row }"><span class="cell-sub">{{ fmtTime(row.assigned_at) }}</span></template>
        </el-table-column>
      </el-table>

      <div class="table-foot">
        <span class="cell-sub">共 {{ total }} 个池地址</span>
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
.toolbar { display: flex; gap: 10px; margin-bottom: 14px; flex-wrap: wrap; }
</style>
