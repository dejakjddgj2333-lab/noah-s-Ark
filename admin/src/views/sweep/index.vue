<script setup>
import { computed, onMounted, reactive, ref } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import {
  getSweepBalances,
  getSweepRecords,
  getSweepTargets,
  runSweep,
  setSweepTarget,
} from '@/api/admin'

const NETWORKS = [
  { key: 'trc20', label: 'TRC20', chain: 'Tron 主网', gas: 'TRX', scan: 'https://tronscan.org/#/address/', scanName: 'Tronscan' },
  { key: 'erc20', label: 'ERC20', chain: 'Ethereum', gas: 'ETH', scan: 'https://etherscan.io/address/', scanName: 'Etherscan' },
  { key: 'bep20', label: 'BEP20', chain: 'BNB Chain', gas: 'BNB', scan: 'https://bscscan.com/address/', scanName: 'BscScan' },
  { key: 'arbitrum', label: 'Arbitrum', chain: 'Arbitrum One', gas: 'ETH', scan: 'https://arbiscan.io/address/', scanName: 'Arbiscan' },
]

const targets = ref({})
const targetsLoading = ref(false)

const editVisible = ref(false)
const editForm = reactive({ network: '', target: '', threshold: '500' })

const activeNet = ref('trc20')
const balances = ref([])
const balLoading = ref(false)
const runLoading = ref(false)
const selected = ref([])
const page = ref(1)
const pageSize = 10

const records = ref([])
const recLoading = ref(false)
const recStatus = ref('all')

async function fetchTargets() {
  targetsLoading.value = true
  try {
    targets.value = await getSweepTargets()
  } finally {
    targetsLoading.value = false
  }
}

const configuredCount = computed(
  () => NETWORKS.filter((n) => targets.value[n.key]?.target).length,
)

function shortAddr(a) {
  if (!a) return '-'
  return a.length > 16 ? `${a.slice(0, 6)}...${a.slice(-4)}` : a
}

async function copyText(text) {
  try {
    await navigator.clipboard.writeText(text)
    ElMessage.success('已复制')
  } catch {
    ElMessage.warning('复制失败, 请手动选择复制')
  }
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
    page.value = 1
  } finally {
    balLoading.value = false
  }
}

const threshold = computed(() => Number(targets.value[activeNet.value]?.threshold || 500))

// 归集状态: ready=可归集 / gas=等待补Gas / low=低于阈值
function rowStatus(row) {
  if (Number(row.usdt) < threshold.value) return 'low'
  return row.gas_ok ? 'ready' : 'gas'
}

const pagedBalances = computed(() => {
  const start = (page.value - 1) * pageSize
  return balances.value.slice(start, start + pageSize)
})

async function fetchRecords() {
  recLoading.value = true
  try {
    records.value = await getSweepRecords({})
  } finally {
    recLoading.value = false
  }
}

const REC_TABS = [
  { key: 'all', label: '全部状态' },
  { key: 'success', label: '已成功' },
  { key: 'gas_needed', label: '缺 Gas' },
  { key: 'failed', label: '失败' },
]

const filteredRecords = computed(() =>
  recStatus.value === 'all'
    ? records.value
    : records.value.filter((r) => r.status === recStatus.value),
)

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

function refreshAll() {
  fetchTargets()
  fetchBalances()
  fetchRecords()
}

function exportRecords() {
  const header = '网络,来源地址,主钱包,金额(USDT),状态,TXID,操作人,时间\n'
  const body = filteredRecords.value
    .map((r) =>
      [r.network, r.from_address, r.to_address, r.amount, r.status, r.txid || '', r.operator || '', fmt(r.created_at)]
        .map((v) => `"${String(v ?? '').replaceAll('"', '""')}"`)
        .join(','),
    )
    .join('\n')
  const blob = new Blob(['﻿' + header + body], { type: 'text/csv;charset=utf-8' })
  const a = document.createElement('a')
  a.href = URL.createObjectURL(blob)
  a.download = `归集记录_${new Date().toISOString().slice(0, 10)}.csv`
  a.click()
  URL.revokeObjectURL(a.href)
}

function fmt(t) {
  return t && t !== 'None' ? String(t).replace('T', ' ').slice(0, 19) : '-'
}

function fmtNum(v, digits = 2) {
  const n = Number(v || 0)
  return n.toLocaleString('en-US', { minimumFractionDigits: digits, maximumFractionDigits: digits })
}

const statusTag = { success: 'success', gas_needed: 'warning', failed: 'danger' }
const statusText = { success: '归集成功', gas_needed: '缺 Gas', failed: '失败' }

onMounted(() => {
  fetchTargets()
  fetchBalances()
  fetchRecords()
})
</script>

<template>
  <div>
    <div class="page-head ph-gold">
      <div class="ph-icon"><el-icon><Coin /></el-icon></div>
      <div>
        <div class="ph-title">
          资金归集
          <span class="ph-chips">
            <span class="ph-chip ok"><i class="dot ok" />链上监测正常</span>
            <span class="ph-chip info">已配置主钱包 {{ configuredCount }}/{{ NETWORKS.length }}</span>
          </span>
        </div>
        <div class="ph-sub">主钱包统一设置 · 充值子地址批量归集 · 归集记录监控与 Gas 预估</div>
      </div>
      <div class="ph-right">
        <el-button :loading="targetsLoading || balLoading" @click="refreshAll">
          <el-icon style="margin-right: 4px"><Refresh /></el-icon>刷新链上数据
        </el-button>
      </div>
    </div>

    <!-- 主钱包设置卡 -->
    <el-row :gutter="16" v-loading="targetsLoading">
      <el-col v-for="n in NETWORKS" :key="n.key" :xs="24" :sm="12" :lg="6">
        <div class="net-card" :class="{ unconfigured: !targets[n.key]?.target }">
          <div class="net-head">
            <span class="net-tag" :class="n.key">{{ n.label }}</span>
            <span class="net-chain">{{ n.chain }}</span>
            <span v-if="targets[n.key]?.target" class="ph-chip ok" style="margin-left: auto">
              <i class="dot ok" />已配置主钱包
            </span>
            <span v-else class="ph-chip warn" style="margin-left: auto">
              <i class="dot warn" />待设置主钱包
            </span>
          </div>

          <template v-if="targets[n.key]?.target">
            <div class="addr-box">
              <div>
                <div class="addr-label">主钱包归集地址:</div>
                <div class="addr-value" :title="targets[n.key].target">{{ shortAddr(targets[n.key].target) }}</div>
              </div>
              <el-icon class="copy-ic" @click="copyText(targets[n.key].target)"><CopyDocument /></el-icon>
            </div>
            <div class="net-grid">
              <div>
                <div class="addr-label">触发归集阈值</div>
                <div class="net-num">{{ fmtNum(targets[n.key].threshold, 0) }} <span class="net-unit">USDT</span></div>
              </div>
              <div>
                <div class="addr-label">当前主钱包余额</div>
                <div class="net-num">
                  {{ targets[n.key].target_usdt === null || targets[n.key].target_usdt === undefined ? '-' : fmtNum(targets[n.key].target_usdt) }}
                  <span class="net-unit">USDT</span>
                </div>
              </div>
            </div>
            <div class="net-grid" style="margin-top: 10px">
              <div class="addr-label">Gas 储备池 ({{ n.gas }})</div>
              <span v-if="targets[n.key].target_native !== null && targets[n.key].target_native !== undefined" class="gas-pill" :class="targets[n.key].gas_ok ? 'ok' : 'warn'">
                {{ fmtNum(targets[n.key].target_native, 4) }} {{ n.gas }} ({{ targets[n.key].gas_ok ? '充足' : '不足' }})
              </span>
              <span v-else class="gas-pill mute">-</span>
            </div>
            <div class="net-foot">
              <el-button v-perm="'btn:sweep:target'" size="small" plain @click="openEdit(n.key)">设置 / 修改</el-button>
              <a class="scan-link" :href="n.scan + targets[n.key].target" target="_blank" rel="noopener">
                {{ n.scanName }} <el-icon><TopRight /></el-icon>
              </a>
            </div>
          </template>

          <template v-else>
            <div class="empty-box">
              <div class="empty-title">主钱包: 未设置</div>
              <div class="empty-sub">尚未指定 {{ n.label }} 归集目标地址, 请配置后启用 {{ n.chain }} 自动充值归集。</div>
            </div>
            <div class="net-grid" style="margin-top: 10px">
              <div>
                <div class="addr-label">预设阈值</div>
                <div class="net-num-sm">{{ fmtNum(targets[n.key]?.threshold || 500, 0) }} USDT</div>
              </div>
              <div>
                <div class="addr-label">Gas 类型</div>
                <div class="net-num-sm">{{ n.gas }} ({{ n.chain }})</div>
              </div>
            </div>
            <el-button v-perm="'btn:sweep:target'" type="warning" plain style="width: 100%" @click="openEdit(n.key)">
              <el-icon style="margin-right: 4px"><Plus /></el-icon>立即配置主钱包
            </el-button>
          </template>
        </div>
      </el-col>
    </el-row>

    <!-- 地址余额 -->
    <el-card shadow="never" style="margin-top: 4px">
      <div class="toolbar">
        <el-radio-group :model-value="activeNet" @change="switchNet">
          <el-radio-button v-for="n in NETWORKS" :key="n.key" :value="n.key">{{ n.label }}</el-radio-button>
        </el-radio-group>
        <div style="margin-left: auto; display: flex; gap: 10px">
          <el-button @click="fetchBalances"><el-icon style="margin-right: 4px"><Refresh /></el-icon>刷新</el-button>
          <el-button
            v-perm="'btn:sweep:run'"
            type="primary"
            :loading="runLoading"
            @click="sweepAll"
          ><el-icon style="margin-right: 4px"><Lightning /></el-icon>一键归集达阈值地址</el-button>
        </div>
      </div>
      <div class="alert-bar">
        <el-icon><InfoFilled /></el-icon>
        只显示有余额的地址; 缺 Gas 的地址归集时会自动标记, 手动补 Gas 后可单独或批量一键归集。
      </div>
      <el-table
        :data="pagedBalances"
        v-loading="balLoading"
        @selection-change="(rows) => (selected = rows)"
      >
        <el-table-column type="selection" width="42" />
        <el-table-column label="充值地址" min-width="230">
          <template #default="{ row }">
            <div class="cell-main" style="font-family: monospace; display: flex; align-items: center; gap: 6px">
              {{ row.address }}
              <el-icon class="copy-ic" @click="copyText(row.address)"><CopyDocument /></el-icon>
            </div>
            <div class="cell-sub">生成于: {{ fmt(row.created_at) }}</div>
          </template>
        </el-table-column>
        <el-table-column label="用户ID / 归属" min-width="170">
          <template #default="{ row }">
            <div class="cell-main" style="font-weight: 600">UID: {{ row.user_id }}</div>
            <div class="cell-sub">{{ row.user_email || row.user_name || '-' }}</div>
          </template>
        </el-table-column>
        <el-table-column label="网络" width="90" align="center">
          <template #default="{ row }">
            <span class="net-tag" :class="activeNet">{{ activeNet.toUpperCase() }}</span>
          </template>
        </el-table-column>
        <el-table-column label="USDT 待归集余额" min-width="130" align="right">
          <template #default="{ row }">
            <div class="amt">{{ fmtNum(row.usdt) }} <span style="font-size: 12px; font-weight: 500; color: var(--app-text-2)">USDT</span></div>
            <div class="amt-sub" :style="Number(row.usdt) < threshold ? 'color: var(--app-text-2)' : ''">
              {{ Number(row.usdt) >= threshold ? `高于阈值 ${fmtNum(threshold, 0)}` : `低于阈值 ${fmtNum(threshold, 0)}` }}
            </div>
          </template>
        </el-table-column>
        <el-table-column label="GAS 余额状态" min-width="140" align="center">
          <template #default="{ row }">
            <span class="gas-cell">
              <i class="dot" :class="row.gas_ok ? 'ok' : Number(row.native) > 0 ? 'warn' : 'err'" />
              {{ fmtNum(row.native, 4) }} {{ row.native_symbol }}
              <el-tag v-if="!row.gas_ok" type="warning" size="small" effect="plain">需补充 Gas</el-tag>
              <span v-else class="cell-sub" style="display: inline; margin-left: 4px">充足</span>
            </span>
          </template>
        </el-table-column>
        <el-table-column label="归集状态" width="110" align="center">
          <template #default="{ row }">
            <el-tag v-if="rowStatus(row) === 'ready'" type="success" size="small" effect="light">可归集</el-tag>
            <el-tag v-else-if="rowStatus(row) === 'gas'" type="warning" size="small" effect="light">等待补 Gas</el-tag>
            <el-tag v-else type="info" size="small" effect="light">低于阈值</el-tag>
          </template>
        </el-table-column>
        <el-table-column label="操作" width="130" fixed="right" align="center">
          <template #default="{ row }">
            <el-button
              v-perm="'btn:sweep:run'"
              size="small"
              :type="rowStatus(row) === 'ready' ? 'primary' : 'info'"
              plain
              :loading="runLoading"
              @click="sweepOne(row)"
            >{{ rowStatus(row) === 'low' ? '强制归集' : '归集' }}</el-button>
            <el-button size="small" text @click="copyText(row.address)">明细</el-button>
          </template>
        </el-table-column>
      </el-table>
      <div class="table-foot">
        <span class="cell-sub">共 {{ balances.length }} 个充值地址有余额 · 已选 {{ selected.length }} 个</span>
        <el-pagination
          v-model:current-page="page"
          :page-size="pageSize"
          :total="balances.length"
          layout="prev, pager, next"
          background
          hide-on-single-page
        />
      </div>
    </el-card>

    <!-- 归集记录 -->
    <el-card shadow="never" style="margin-top: 16px">
      <div class="toolbar">
        <div>
          <div style="font-weight: 700; font-size: 15px; color: var(--app-text)">归集记录</div>
          <div class="cell-sub">实时链上打包状态跟踪</div>
        </div>
        <div style="margin-left: auto; display: flex; gap: 10px; align-items: center">
          <el-radio-group v-model="recStatus" size="small">
            <el-radio-button v-for="t in REC_TABS" :key="t.key" :value="t.key">{{ t.label }}</el-radio-button>
          </el-radio-group>
          <el-button size="small" @click="exportRecords">
            <el-icon style="margin-right: 4px"><Download /></el-icon>导出记录
          </el-button>
        </div>
      </div>
      <el-table :data="filteredRecords" v-loading="recLoading">
        <el-table-column label="网络" width="90" align="center">
          <template #default="{ row }">
            <span class="net-tag" :class="row.network">{{ row.network.toUpperCase() }}</span>
          </template>
        </el-table-column>
        <el-table-column label="来源地址" min-width="120">
          <template #default="{ row }">
            <span class="cell-main" style="font-family: monospace" :title="row.from_address">{{ shortAddr(row.from_address) }}</span>
          </template>
        </el-table-column>
        <el-table-column label="主钱包 (目标)" min-width="130">
          <template #default="{ row }">
            <span class="cell-main" style="font-family: monospace" :title="row.to_address">{{ shortAddr(row.to_address) }}</span>
          </template>
        </el-table-column>
        <el-table-column label="金额 (USDT)" width="120" align="right">
          <template #default="{ row }">
            <span class="amt" style="color: #16a34a">+ {{ fmtNum(row.amount) }}</span>
          </template>
        </el-table-column>
        <el-table-column label="状态" width="100" align="center">
          <template #default="{ row }">
            <el-tag :type="statusTag[row.status] || 'info'" size="small" effect="light">{{ statusText[row.status] || row.status }}</el-tag>
          </template>
        </el-table-column>
        <el-table-column label="TXID (哈希)" min-width="130">
          <template #default="{ row }">
            <span class="cell-main" style="font-family: monospace" :title="row.txid || row.error">
              {{ row.txid ? shortAddr(row.txid) : (row.error || '-') }}
            </span>
          </template>
        </el-table-column>
        <el-table-column prop="operator" label="操作人" width="130" show-overflow-tooltip>
          <template #default="{ row }">
            <el-tag v-if="row.operator" size="small" effect="plain" type="primary">{{ row.operator }}</el-tag>
            <span v-else class="cell-sub">-</span>
          </template>
        </el-table-column>
        <el-table-column label="时间" width="160" align="right">
          <template #default="{ row }"><span class="cell-sub">{{ fmt(row.created_at) }}</span></template>
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
/* 网络主钱包卡 */
.net-card {
  display: flex;
  flex-direction: column;
  width: 100%;
  height: 100%;
  border: 1px solid var(--app-line);
  border-radius: 14px;
  background: var(--app-surface);
  padding: 16px 18px;
  margin-bottom: 16px;
  box-shadow: 0 1px 3px rgba(16, 24, 64, 0.05);
}

.net-card > .net-foot,
.net-card > .el-button:last-child {
  margin-top: auto;
}

.net-card > .empty-box + .net-grid {
  margin-bottom: 14px;
}

html.dark .net-card {
  box-shadow: 0 4px 16px rgba(0, 0, 0, 0.25);
}

.net-card.unconfigured {
  border: 1.5px dashed rgba(247, 183, 51, 0.6);
  background: color-mix(in srgb, #f7b733 5%, var(--app-surface));
}

.net-head {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 12px;
}

.net-chain {
  color: var(--app-text-2);
  font-size: 12px;
}

.addr-box {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  padding: 9px 12px;
  border-radius: 8px;
  background: var(--app-surface-2);
  border: 1px solid var(--app-line);
}

.addr-label {
  color: var(--app-text-2);
  font-size: 12px;
}

.addr-value {
  margin-top: 3px;
  font-family: monospace;
  font-size: 13px;
  color: var(--app-text);
}

.copy-ic {
  color: var(--app-text-2);
  cursor: pointer;
  flex: none;
}

.copy-ic:hover {
  color: #4c6fff;
}

.net-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  align-items: end;
  margin-top: 12px;
}

.net-num {
  margin-top: 3px;
  font-size: 17px;
  font-weight: 700;
  color: var(--app-text);
  font-variant-numeric: tabular-nums;
}

.net-num-sm {
  margin-top: 3px;
  font-size: 13px;
  color: var(--app-text);
}

.net-unit {
  font-size: 11px;
  font-weight: 500;
  color: var(--app-text-2);
}

.gas-pill {
  justify-self: end;
  padding: 3px 10px;
  border-radius: 10px;
  font-size: 12px;
  font-weight: 600;
}

.gas-pill.ok { color: #16a34a; background: rgba(34, 193, 163, 0.12); }
.gas-pill.warn { color: #b45309; background: rgba(247, 183, 51, 0.16); }
.gas-pill.mute { color: var(--app-text-2); background: var(--app-surface-2); }

html.dark .gas-pill.ok { color: #34d399; }
html.dark .gas-pill.warn { color: #fbbf24; }

.net-foot {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-top: 14px;
}

.scan-link {
  display: inline-flex;
  align-items: center;
  gap: 3px;
  font-size: 12px;
  color: var(--app-text-2);
  text-decoration: none;
}

.scan-link:hover {
  color: #4c6fff;
}

.empty-box {
  padding: 12px;
  border-radius: 8px;
  background: rgba(247, 183, 51, 0.1);
  border: 1px solid rgba(247, 183, 51, 0.25);
}

.empty-title {
  font-size: 13px;
  font-weight: 600;
  color: #b45309;
}

html.dark .empty-title { color: #fbbf24; }

.empty-sub {
  margin-top: 4px;
  font-size: 12px;
  color: var(--app-text-2);
  line-height: 1.5;
}

/* 表格 */
.toolbar {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 14px;
  flex-wrap: wrap;
}

.gas-cell {
  display: inline-flex;
  align-items: center;
  gap: 2px;
  font-size: 12px;
  color: var(--app-text);
}

.table-foot {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-top: 14px;
  flex-wrap: wrap;
  gap: 10px;
}
</style>
