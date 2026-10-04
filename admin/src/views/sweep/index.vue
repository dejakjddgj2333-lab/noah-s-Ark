<script setup>
import { onMounted, reactive, ref } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import {
  getSweepBalances,
  getSweepRecords,
  getSweepTargets,
  runSweep,
  setSweepTarget,
} from '@/api/admin'

const NETWORKS = [
  { key: 'trc20', label: 'TRC20', chain: 'Tron 主网', gas: 'TRX' },
  { key: 'erc20', label: 'ERC20', chain: 'Ethereum', gas: 'ETH' },
  { key: 'bep20', label: 'BEP20', chain: 'BNB Chain', gas: 'BNB' },
  { key: 'arbitrum', label: 'Arbitrum', chain: 'Arbitrum One', gas: 'ETH' },
]

const targets = ref({})
const editVisible = ref(false)
const editForm = reactive({ network: '', target: '', threshold: '500' })

const activeNet = ref('trc20')
const balances = ref([])
const balLoading = ref(false)
const runLoading = ref(false)

const records = ref([])
const recLoading = ref(false)

async function fetchTargets() {
  targets.value = await getSweepTargets()
}

function openEdit(net) {
  const t = targets.value[net] || {}
  Object.assign(editForm, { network: net, target: t.target || '', threshold: t.threshold || '500' })
  editVisible.value = true
}

async function submitEdit() {
  await setSweepTarget({
    network: editForm.network,
    target: editForm.target.trim(),
    threshold: String(editForm.threshold),
  })
  ElMessage.success('归集设置已保存')
  editVisible.value = false
  fetchTargets()
}

async function fetchBalances() {
  balLoading.value = true
  try {
    balances.value = await getSweepBalances({ network: activeNet.value })
  } finally {
    balLoading.value = false
  }
}

async function fetchRecords() {
  recLoading.value = true
  try {
    records.value = await getSweepRecords({})
  } finally {
    recLoading.value = false
  }
}

async function sweepAll() {
  const t = targets.value[activeNet.value]
  if (!t?.target) {
    ElMessage.warning('先设置该网络主钱包地址')
    return
  }
  await ElMessageBox.confirm(
    `确认归集 ${activeNet.value.toUpperCase()} 网络所有达阈值地址的 USDT 到主钱包 ${t.target}? 缺 gas 的地址会自动跳过并标记。`,
    '归集确认',
    { type: 'warning' },
  )
  runLoading.value = true
  try {
    const r = await runSweep({ network: activeNet.value })
    ElMessage.success(`归集完成: 成功 ${r.swept}, 缺gas ${r.gas_needed}, 失败 ${r.failed}, 跳过 ${r.skipped}`)
    fetchBalances()
    fetchRecords()
  } finally {
    runLoading.value = false
  }
}

async function sweepOne(row) {
  const t = targets.value[activeNet.value]
  if (!t?.target) {
    ElMessage.warning('先设置该网络主钱包地址')
    return
  }
  runLoading.value = true
  try {
    const r = await runSweep({ network: activeNet.value, address: row.address })
    if (r.gas_needed) ElMessage.warning(`该地址缺 ${row.native_symbol}, 请先手动补 gas`)
    else if (r.swept) ElMessage.success('归集成功')
    else if (r.skipped) ElMessage.info('低于归集阈值, 已跳过')
    else ElMessage.error('归集失败, 见记录')
    fetchBalances()
    fetchRecords()
  } finally {
    runLoading.value = false
  }
}

function switchNet(net) {
  activeNet.value = net
  fetchBalances()
}

function fmt(t) {
  return t && t !== 'None' ? String(t).replace('T', ' ').slice(0, 19) : '-'
}

const statusTag = { success: 'success', gas_needed: 'warning', failed: 'danger' }
const statusText = { success: '成功', gas_needed: '缺 gas', failed: '失败' }

onMounted(() => {
  fetchTargets()
  fetchBalances()
  fetchRecords()
})
</script>

<template>
  <div>
    <!-- 主钱包设置 -->
    <el-row :gutter="16">
      <el-col v-for="n in NETWORKS" :key="n.key" :xs="24" :sm="12" :md="6">
        <el-card shadow="never" class="net-card">
          <div class="net-head">
            <el-tag effect="dark" type="primary">{{ n.label }}</el-tag>
            <span class="net-chain">{{ n.chain }}</span>
          </div>
          <div class="net-target">
            <div class="net-label">主钱包</div>
            <div class="net-addr" :title="targets[n.key]?.target">
              {{ targets[n.key]?.target || '未设置' }}
            </div>
            <div class="net-label">阈值: {{ targets[n.key]?.threshold || '500' }} USDT · gas: {{ n.gas }}</div>
          </div>
          <el-button v-perm="'btn:sweep:run'" size="small" type="primary" plain @click="openEdit(n.key)">
            设置
          </el-button>
        </el-card>
      </el-col>
    </el-row>

    <!-- 地址余额 -->
    <el-card shadow="never" style="margin-top: 16px">
      <div class="toolbar">
        <el-radio-group :model-value="activeNet" @change="switchNet">
          <el-radio-button v-for="n in NETWORKS" :key="n.key" :value="n.key">{{ n.label }}</el-radio-button>
        </el-radio-group>
        <el-button @click="fetchBalances">刷新</el-button>
        <el-button
          v-perm="'btn:sweep:run'"
          type="primary"
          :loading="runLoading"
          @click="sweepAll"
        >一键归集达阈值地址</el-button>
        <span class="tip">只显示有余额的地址; 缺 gas 的地址归集时会标记, 手动补 gas 后可单独归集</span>
      </div>
      <el-table :data="balances" v-loading="balLoading" border stripe>
        <el-table-column prop="address" label="充值地址" min-width="300" show-overflow-tooltip />
        <el-table-column prop="user_id" label="用户ID" width="80" align="center" />
        <el-table-column label="USDT 余额" width="130" align="right">
          <template #default="{ row }">
            <span :style="{ fontWeight: 600, color: Number(row.usdt) > 0 ? '#22c1a3' : '#909399' }">
              {{ row.usdt }}
            </span>
          </template>
        </el-table-column>
        <el-table-column label="gas 余额" width="130" align="right">
          <template #default="{ row }">{{ row.native }} {{ row.native_symbol }}</template>
        </el-table-column>
        <el-table-column label="操作" width="110" fixed="right">
          <template #default="{ row }">
            <el-button
              v-perm="'btn:sweep:run'"
              size="small"
              type="primary"
              plain
              :disabled="Number(row.usdt) <= 0"
              :loading="runLoading"
              @click="sweepOne(row)"
            >归集</el-button>
          </template>
        </el-table-column>
      </el-table>
    </el-card>

    <!-- 归集记录 -->
    <el-card shadow="never" style="margin-top: 16px">
      <div class="toolbar"><span class="card-title">归集记录</span></div>
      <el-table :data="records" v-loading="recLoading" border stripe>
        <el-table-column prop="network" label="网络" width="90" />
        <el-table-column prop="from_address" label="来源地址" min-width="180" show-overflow-tooltip />
        <el-table-column prop="to_address" label="主钱包" min-width="180" show-overflow-tooltip />
        <el-table-column prop="amount" label="金额 (USDT)" width="110" align="right" />
        <el-table-column label="状态" width="90" align="center">
          <template #default="{ row }">
            <el-tag :type="statusTag[row.status] || 'info'" size="small">{{ statusText[row.status] || row.status }}</el-tag>
          </template>
        </el-table-column>
        <el-table-column prop="txid" label="TXID" min-width="140" show-overflow-tooltip>
          <template #default="{ row }">{{ row.txid || row.error || '-' }}</template>
        </el-table-column>
        <el-table-column prop="operator" label="操作人" width="90" />
        <el-table-column label="时间" width="160">
          <template #default="{ row }">{{ fmt(row.created_at) }}</template>
        </el-table-column>
      </el-table>
    </el-card>

    <!-- 设置弹窗 -->
    <el-dialog v-model="editVisible" title="归集设置" width="460px">
      <el-form label-width="90px">
        <el-form-item label="网络">{{ editForm.network.toUpperCase() }}</el-form-item>
        <el-form-item label="主钱包地址">
          <el-input v-model="editForm.target" placeholder="归集收款地址 (平台主钱包)" />
        </el-form-item>
        <el-form-item label="归集阈值">
          <el-input v-model="editForm.threshold" placeholder="地址余额达到该值才归集 (USDT)" />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="editVisible = false">取消</el-button>
        <el-button type="primary" @click="submitEdit">保存</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<style scoped>
.net-card { margin-bottom: 16px; }
.net-head { display: flex; align-items: center; gap: 8px; margin-bottom: 10px; }
.net-chain { color: #909399; font-size: 12px; }
.net-target { margin-bottom: 10px; }
.net-label { color: #909399; font-size: 12px; margin-top: 6px; }
.net-addr {
  font-family: monospace;
  font-size: 12px;
  color: #303133;
  word-break: break-all;
  margin-top: 2px;
}
.toolbar { display: flex; align-items: center; gap: 10px; margin-bottom: 14px; flex-wrap: wrap; }
.tip { color: #909399; font-size: 12px; }
.card-title { font-weight: 600; }
</style>
