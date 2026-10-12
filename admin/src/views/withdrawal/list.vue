<script setup>
import { onMounted, reactive, ref } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { getAdminWithdrawals, approveWithdrawal, rejectWithdrawal } from '@/api/product'

const loading = ref(false)
const list = ref([])
const query = reactive({ status: 'pending' })

const STATUS_MAP = {
  pending: { label: '待审核', type: 'warning' },
  approved: { label: '已打款', type: 'success' },
  rejected: { label: '已拒绝', type: 'info' },
}

async function fetchList() {
  loading.value = true
  try {
    list.value = await getAdminWithdrawals(query.status ? { status: query.status } : {})
  } finally {
    loading.value = false
  }
}

async function approve(row) {
  let txid = ''
  try {
    const { value } = await ElMessageBox.prompt(
      `通过 ${row.amount} USDT 提现申请？请输入打款交易号（可稍后补录）`, '审核通过',
      { confirmButtonText: '确认通过', inputPlaceholder: 'txid（可选）' },
    )
    txid = value || ''
  } catch { return }
  await approveWithdrawal(row.id, { txid })
  ElMessage.success('已通过')
  fetchList()
}

async function reject(row) {
  let remark = ''
  try {
    const { value } = await ElMessageBox.prompt('拒绝后金额+费用将全额退回用户', '拒绝提现', {
      confirmButtonText: '确认拒绝',
      inputPlaceholder: '拒绝原因',
    })
    remark = value || ''
  } catch { return }
  await rejectWithdrawal(row.id, { remark })
  ElMessage.success('已拒绝并退回')
  fetchList()
}

function shortAddr(a) {
  return a ? `${a.slice(0, 8)}...${a.slice(-6)}` : '-'
}

onMounted(fetchList)
</script>

<template>
  <div>
    <div class="page-head ph-orange">
      <div class="ph-icon"><el-icon><CreditCard /></el-icon></div>
      <div>
        <div class="ph-title">
          提现审核
          <span class="ph-chips">
            <span v-if="query.status === 'pending'" class="ph-chip warn"><i class="dot warn" />待办 {{ list.length }} 笔</span>
            <span v-else class="ph-chip info">{{ list.length }} 笔记录</span>
          </span>
        </div>
        <div class="ph-sub">提现申请 · 打款 · 拒绝</div>
      </div>
      <div class="ph-right">
        <el-button :loading="loading" @click="fetchList">
          <el-icon style="margin-right: 4px"><Refresh /></el-icon>刷新数据
        </el-button>
      </div>
    </div>

    <el-card shadow="never">
      <div class="toolbar">
        <el-radio-group :model-value="query.status" @change="(v) => { query.status = v; fetchList() }">
          <el-radio-button value="pending">待审核</el-radio-button>
          <el-radio-button value="approved">已打款</el-radio-button>
          <el-radio-button value="rejected">已拒绝</el-radio-button>
          <el-radio-button value="">全部</el-radio-button>
        </el-radio-group>
      </div>
      <div class="alert-bar">
        <el-icon><InfoFilled /></el-icon>
        通过后请尽快链上打款并补录 TXID; 拒绝会将金额与费用全额退回用户账户。
      </div>

      <el-table :data="list" v-loading="loading" stripe>
        <el-table-column label="申请" min-width="170">
          <template #default="{ row }">
            <div class="cell-main" style="font-weight: 600">#{{ row.id }} · UID: {{ row.user_id }}</div>
            <div class="cell-sub">{{ row.created_at?.replace('T', ' ')?.slice(0, 19) }}</div>
          </template>
        </el-table-column>
        <el-table-column label="账户" width="80" align="center">
          <template #default="{ row }">
            <el-tag :type="row.account === 'income' ? 'success' : 'primary'" effect="plain" size="small">
              {{ row.account === 'income' ? '收益' : '本金' }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column label="金额 / 费用" min-width="150" align="right">
          <template #default="{ row }">
            <div class="amt">{{ row.amount }} <span class="amt-unit">USDT</span></div>
            <div class="cell-sub">服务费 {{ row.service_fee }} · 网络费 {{ row.network_fee }}</div>
          </template>
        </el-table-column>
        <el-table-column label="实际到账" min-width="110" align="right">
          <template #default="{ row }">
            <span class="amt" style="color: #16a34a">{{ row.arrive_amount }}</span>
          </template>
        </el-table-column>
        <el-table-column label="网络" width="100" align="center">
          <template #default="{ row }">
            <span class="net-tag" :class="row.network">{{ row.network?.toUpperCase() }}</span>
          </template>
        </el-table-column>
        <el-table-column label="地址" min-width="180" show-overflow-tooltip>
          <template #default="{ row }">
            <el-tooltip :content="row.address">
              <span class="cell-main" style="font-family: monospace">{{ shortAddr(row.address) }}</span>
            </el-tooltip>
          </template>
        </el-table-column>
        <el-table-column label="状态" width="90" align="center">
          <template #default="{ row }">
            <el-tag :type="STATUS_MAP[row.status]?.type" size="small" effect="light">{{ STATUS_MAP[row.status]?.label }}</el-tag>
          </template>
        </el-table-column>
        <el-table-column prop="txid" label="TXID" min-width="140" show-overflow-tooltip>
          <template #default="{ row }">
            <span class="cell-main" style="font-family: monospace">{{ row.txid || '-' }}</span>
          </template>
        </el-table-column>
        <el-table-column label="操作" width="150" fixed="right" align="center">
          <template #default="{ row }">
            <template v-if="row.status === 'pending'">
              <el-button v-perm="'btn:withdrawal:audit'" size="small" type="success" @click="approve(row)">通过</el-button>
              <el-button v-perm="'btn:withdrawal:audit'" size="small" type="danger" plain @click="reject(row)">拒绝</el-button>
            </template>
            <span v-else class="cell-sub">已结案</span>
          </template>
        </el-table-column>
      </el-table>
      <div class="table-foot">
        <span class="cell-sub">共 {{ list.length }} 笔{{ STATUS_MAP[query.status]?.label || '' }}提现</span>
      </div>
    </el-card>
  </div>
</template>

<style scoped>
.toolbar { display: flex; gap: 10px; margin-bottom: 14px; }
</style>
