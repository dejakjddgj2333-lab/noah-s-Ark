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
        <div class="ph-title">提现审核</div>
        <div class="ph-sub">提现申请 · 打款 · 拒绝</div>
      </div>
    </div>

    <el-card shadow="never">
      <div class="toolbar">
        <el-select v-model="query.status" placeholder="状态" clearable style="width: 130px" @change="fetchList">
          <el-option label="待审核" value="pending" />
          <el-option label="已打款" value="approved" />
          <el-option label="已拒绝" value="rejected" />
        </el-select>
        <el-button @click="fetchList">刷新</el-button>
      </div>

      <el-table :data="list" v-loading="loading" border stripe>
        <el-table-column prop="id" label="ID" width="60" />
        <el-table-column prop="user_id" label="用户ID" width="70" align="center" />
        <el-table-column label="账户" width="80" align="center">
          <template #default="{ row }">
            <el-tag :type="row.account === 'income' ? 'success' : 'primary'" effect="plain">
              {{ row.account === 'income' ? '收益' : '本金' }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column prop="amount" label="金额" width="100" align="right" />
        <el-table-column prop="service_fee" label="服务费" width="80" align="right" />
        <el-table-column prop="network_fee" label="网络费" width="80" align="right" />
        <el-table-column prop="arrive_amount" label="实际到账" width="100" align="right">
          <template #default="{ row }">
            <span style="color: #22c1a3; font-weight: 600">{{ row.arrive_amount }}</span>
          </template>
        </el-table-column>
        <el-table-column label="网络" width="90" align="center">
          <template #default="{ row }">{{ row.network?.toUpperCase() }}</template>
        </el-table-column>
        <el-table-column label="地址" min-width="220" show-overflow-tooltip>
          <template #default="{ row }">
            <el-tooltip :content="row.address"><span>{{ shortAddr(row.address) }}</span></el-tooltip>
          </template>
        </el-table-column>
        <el-table-column label="状态" width="90" align="center">
          <template #default="{ row }">
            <el-tag :type="STATUS_MAP[row.status]?.type">{{ STATUS_MAP[row.status]?.label }}</el-tag>
          </template>
        </el-table-column>
        <el-table-column prop="txid" label="TXID" min-width="150" show-overflow-tooltip />
        <el-table-column label="申请时间" width="160">
          <template #default="{ row }">{{ row.created_at?.replace('T', ' ')?.slice(0, 19) }}</template>
        </el-table-column>
        <el-table-column label="操作" width="160" fixed="right" align="center">
          <template #default="{ row }">
            <template v-if="row.status === 'pending'">
              <el-button v-perm="'btn:withdrawal:audit'" size="small" type="success" @click="approve(row)">通过</el-button>
              <el-button v-perm="'btn:withdrawal:audit'" size="small" type="danger" plain @click="reject(row)">拒绝</el-button>
            </template>
          </template>
        </el-table-column>
      </el-table>
    </el-card>
  </div>
</template>

<style scoped>
.toolbar { display: flex; gap: 10px; margin-bottom: 14px; }
</style>
