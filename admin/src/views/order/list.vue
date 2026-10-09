<script setup>
import { onMounted, reactive, ref } from 'vue'
import { getAdminOrders, getAdminOrderSettlements } from '@/api/order'

const loading = ref(false)
const list = ref([])
const total = ref(0)
const query = reactive({ username: '', status: '' })

const STATUS_MAP = {
  effective: { label: '生效中', type: 'success' },
  finished: { label: '已完成', type: 'info' },
}

async function fetchList() {
  loading.value = true
  try {
    const params = { limit: 200 }
    if (query.username) params.username = query.username
    if (query.status) params.status = query.status
    const res = await getAdminOrders(params)
    list.value = res.items
    total.value = res.total
  } finally {
    loading.value = false
  }
}

// ── 收益明细弹窗 ──
const detailVisible = ref(false)
const detailLoading = ref(false)
const detail = ref({ settlements: [], commissions: [] })
const detailOrder = ref(null)

async function openDetail(row) {
  detailOrder.value = row
  detailVisible.value = true
  detailLoading.value = true
  try {
    detail.value = await getAdminOrderSettlements(row.id)
  } finally {
    detailLoading.value = false
  }
}

function fmt(t) {
  return t ? t.replace('T', ' ').slice(0, 19) : '-'
}

function pct(v) {
  return v == null ? '-' : `${(Number(v) * 100).toFixed(2)}%`
}

onMounted(fetchList)
</script>

<template>
  <div>
    <div class="page-head ph-blue">
      <div class="ph-icon"><el-icon><ShoppingCart /></el-icon></div>
      <div>
        <div class="ph-title">订单管理</div>
        <div class="ph-sub">申购订单 · 结算 · 佣金</div>
      </div>
    </div>

    <el-card shadow="never">
      <div class="toolbar">
        <el-input
          v-model="query.username"
          placeholder="用户名"
          clearable
          style="width: 160px"
          @keyup.enter="fetchList"
        />
        <el-select v-model="query.status" placeholder="状态" clearable style="width: 120px" @change="fetchList">
          <el-option label="生效中" value="effective" />
          <el-option label="已完成" value="finished" />
        </el-select>
        <el-button type="primary" @click="fetchList">查询</el-button>
        <span class="tip">共 {{ total }} 单 · 收益为已结算入账口径</span>
      </div>

      <el-table :data="list" v-loading="loading" border stripe>
        <el-table-column prop="id" label="ID" width="56" align="center" />
        <el-table-column label="用户" min-width="110">
          <template #default="{ row }">
            <div>{{ row.username }}</div>
            <div style="color: #909399; font-size: 12px">ID {{ row.user_id }}</div>
          </template>
        </el-table-column>
        <el-table-column prop="product_name" label="产品" min-width="140" show-overflow-tooltip />
        <el-table-column prop="amount" label="金额" min-width="90" align="right" />
        <el-table-column label="日化率" min-width="90" align="right">
          <template #default="{ row }">
            <div>{{ pct(row.actual_daily_rate) }}</div>
            <div v-if="row.lock_bonus_rate && Number(row.lock_bonus_rate) > 0" style="color: #909399; font-size: 12px">
              基础{{ pct(row.base_daily_rate) }}+加成
            </div>
          </template>
        </el-table-column>
        <el-table-column label="周期/返还" min-width="110" align="center">
          <template #default="{ row }">
            <div>{{ row.duration_days }} 天</div>
            <div style="color: #909399; font-size: 12px">{{ row.return_method_label }}</div>
          </template>
        </el-table-column>
        <el-table-column label="结算进度" min-width="85" align="center">
          <template #default="{ row }">{{ row.settled_periods }}/{{ row.total_periods }}</template>
        </el-table-column>
        <el-table-column label="已产生收益" min-width="95" align="right">
          <template #default="{ row }">
            <span style="color: #22c1a3; font-weight: 600">{{ row.settled_income }}</span>
          </template>
        </el-table-column>
        <el-table-column prop="principal_returned" label="已返本金" min-width="90" align="right" />
        <el-table-column prop="commission_paid" label="佣金支出" min-width="90" align="right" />
        <el-table-column label="状态" width="80" align="center">
          <template #default="{ row }">
            <el-tag :type="STATUS_MAP[row.status]?.type">{{ STATUS_MAP[row.status]?.label || row.status }}</el-tag>
          </template>
        </el-table-column>
        <el-table-column label="购买时间" min-width="150" align="center">
          <template #default="{ row }">{{ fmt(row.created_at) }}</template>
        </el-table-column>
        <el-table-column label="操作" width="96" fixed="right" align="center">
          <template #default="{ row }">
            <el-button size="small" type="primary" plain @click="openDetail(row)">收益明细</el-button>
          </template>
        </el-table-column>
      </el-table>
    </el-card>

    <!-- 收益明细 -->
    <el-dialog v-model="detailVisible" width="760px"
      :title="`订单 #${detailOrder?.id} ${detailOrder?.product_name || ''} · 收益明细`">
      <div v-loading="detailLoading">
        <el-table :data="detail.settlements" border size="small" max-height="320">
          <el-table-column prop="period_no" label="期数" width="70" align="center" />
          <el-table-column label="收益" width="110" align="right">
            <template #default="{ row }">
              <span style="color: #22c1a3; font-weight: 600">{{ row.income_amount }}</span>
            </template>
          </el-table-column>
          <el-table-column prop="principal_amount" label="返本" width="100" align="right" />
          <el-table-column label="应结算时点" width="160">
            <template #default="{ row }">{{ fmt(row.due_at) }}</template>
          </el-table-column>
          <el-table-column label="实际入账" min-width="160">
            <template #default="{ row }">{{ fmt(row.created_at) }}</template>
          </el-table-column>
        </el-table>

        <template v-if="detail.commissions.length">
          <div style="margin: 16px 0 8px; font-weight: 600">触发的佣金 (平台额外支出)</div>
          <el-table :data="detail.commissions" border size="small" max-height="240">
            <el-table-column label="接收人" min-width="120" show-overflow-tooltip>
              <template #default="{ row }">
                {{ row.receiver_username }}
                <span style="color: #909399; font-size: 12px">({{ row.gen }}代)</span>
              </template>
            </el-table-column>
            <el-table-column label="比例" width="80" align="right">
              <template #default="{ row }">{{ pct(row.rate) }}</template>
            </el-table-column>
            <el-table-column prop="base_amount" label="佣金基数" width="100" align="right" />
            <el-table-column label="佣金" width="100" align="right">
              <template #default="{ row }">
                <span style="color: #e6a23c; font-weight: 600">{{ row.amount }}</span>
              </template>
            </el-table-column>
            <el-table-column label="入账时间" min-width="160">
              <template #default="{ row }">{{ fmt(row.created_at) }}</template>
            </el-table-column>
          </el-table>
        </template>
        <el-empty v-if="!detail.settlements.length && !detailLoading" description="尚未到首个结算时点" />
      </div>
    </el-dialog>
  </div>
</template>

<style scoped>
.toolbar {
  display: flex;
  gap: 10px;
  margin-bottom: 14px;
  align-items: center;
}
.tip {
  color: #909399;
  font-size: 12px;
}
</style>
