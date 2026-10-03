<script setup>
import { onMounted, ref } from 'vue'
import { getAdminUsers, getAdminUserProfile } from '@/api/product'

const loading = ref(false)
const list = ref([])
const keyword = ref('')

const drawerVisible = ref(false)
const profileLoading = ref(false)
const p = ref(null)

async function fetchList() {
  loading.value = true
  try {
    list.value = await getAdminUsers(keyword.value ? { q: keyword.value } : {})
  } finally {
    loading.value = false
  }
}

async function openProfile(row) {
  drawerVisible.value = true
  profileLoading.value = true
  p.value = null
  try {
    p.value = await getAdminUserProfile(row.id)
  } finally {
    profileLoading.value = false
  }
}

function fmt(t) {
  return t && t !== 'None' ? String(t).replace('T', ' ').slice(0, 19) : '-'
}

onMounted(fetchList)
</script>

<template>
  <div>
    <el-card shadow="never">
      <div class="toolbar">
        <el-input v-model="keyword" placeholder="用户名 / 邮箱" clearable style="width: 240px" @keyup.enter="fetchList" />
        <el-button type="primary" @click="fetchList">搜索</el-button>
        <el-button @click="keyword = ''; fetchList()">重置</el-button>
      </div>

      <el-table :data="list" v-loading="loading" border stripe>
        <el-table-column prop="id" label="ID" width="60" />
        <el-table-column prop="username" label="用户名" min-width="100" />
        <el-table-column prop="email" label="邮箱" min-width="160" />
        <el-table-column label="VIP" width="70" align="center">
          <template #default="{ row }">
            <el-tag type="primary" effect="plain">VIP{{ row.vip_level }}</el-tag>
          </template>
        </el-table-column>
        <el-table-column label="团队等级" width="80" align="center">
          <template #default="{ row }">
            <el-tag type="success" effect="plain">{{ row.team_level }} 级</el-tag>
          </template>
        </el-table-column>
        <el-table-column label="本金余额" width="110" align="right">
          <template #default="{ row }">{{ row.principal_balance }}</template>
        </el-table-column>
        <el-table-column label="收益余额" width="110" align="right">
          <template #default="{ row }">{{ row.income_balance }}</template>
        </el-table-column>
        <el-table-column label="处理中" width="100" align="right">
          <template #default="{ row }">{{ Number(row.principal_pending) + Number(row.income_pending) }}</template>
        </el-table-column>
        <el-table-column prop="created_at" label="注册时间" width="160">
          <template #default="{ row }">{{ fmt(row.created_at) }}</template>
        </el-table-column>
        <el-table-column label="操作" width="90" fixed="right">
          <template #default="{ row }">
            <el-button size="small" type="primary" plain @click="openProfile(row)">档案</el-button>
          </template>
        </el-table-column>
      </el-table>
    </el-card>

    <el-drawer v-model="drawerVisible" title="用户全量档案（只读）" size="72%">
      <div v-loading="profileLoading">
        <template v-if="p">
          <el-descriptions :column="3" border size="small" class="block">
            <el-descriptions-item label="用户名">{{ p.user.username }}</el-descriptions-item>
            <el-descriptions-item label="邮箱">{{ p.user.email }}</el-descriptions-item>
            <el-descriptions-item label="状态">{{ p.user.status }}</el-descriptions-item>
            <el-descriptions-item label="邀请码">{{ p.invite.invite_code || '-' }}</el-descriptions-item>
            <el-descriptions-item label="上级">{{ p.invite.inviter || '未绑定' }}</el-descriptions-item>
            <el-descriptions-item label="绑定时间">{{ fmt(p.invite.bound_at) }}</el-descriptions-item>
            <el-descriptions-item label="VIP / 有效持仓">VIP{{ p.levels.vip_level }} / {{ p.levels.effective_holding }}</el-descriptions-item>
            <el-descriptions-item label="团队 / 人数 / 持仓">{{ p.levels.team_level }} 级 / {{ p.levels.team_members }} 人 / {{ p.levels.team_holding }}</el-descriptions-item>
            <el-descriptions-item label="本金 / 收益">{{ p.account.principal_balance }} / {{ p.account.income_balance }}</el-descriptions-item>
          </el-descriptions>

          <el-tabs class="block">
            <el-tab-pane :label="`订单 (${p.orders.length})`">
              <el-table :data="p.orders" size="small" border>
                <el-table-column prop="id" label="ID" width="60" />
                <el-table-column prop="product_name" label="产品" min-width="110" />
                <el-table-column prop="amount" label="金额" width="90" align="right" />
                <el-table-column prop="status" label="状态" width="80" />
                <el-table-column label="锁定VIP/加成" width="110" align="center">
                  <template #default="{ row }">VIP{{ row.vip_level }} / {{ row.lock_bonus_rate }}</template>
                </el-table-column>
                <el-table-column label="生效" width="150"><template #default="{ row }">{{ fmt(row.effective_at) }}</template></el-table-column>
                <el-table-column label="到期" width="150"><template #default="{ row }">{{ fmt(row.expires_at) }}</template></el-table-column>
              </el-table>
            </el-tab-pane>
            <el-tab-pane :label="`充值 (${p.deposits.length})`">
              <el-table :data="p.deposits" size="small" border>
                <el-table-column prop="network" label="网络" width="70" />
                <el-table-column prop="amount" label="金额" width="100" align="right" />
                <el-table-column prop="txid" label="TXID" min-width="160" show-overflow-tooltip />
                <el-table-column prop="confirmations" label="确认数" width="70" align="center" />
                <el-table-column prop="status" label="状态" width="80" />
                <el-table-column label="入账时间" width="150"><template #default="{ row }">{{ fmt(row.credited_at) }}</template></el-table-column>
              </el-table>
            </el-tab-pane>
            <el-tab-pane :label="`收益结算 (${p.settlements.length})`">
              <el-table :data="p.settlements" size="small" border>
                <el-table-column prop="order_id" label="订单" width="70" />
                <el-table-column prop="period_no" label="期数" width="60" align="center" />
                <el-table-column prop="income_amount" label="收益" width="100" align="right" />
                <el-table-column prop="principal_amount" label="返本" width="100" align="right" />
                <el-table-column label="时间" width="160"><template #default="{ row }">{{ fmt(row.created_at) }}</template></el-table-column>
              </el-table>
            </el-tab-pane>
            <el-tab-pane :label="`佣金 (${p.commissions.length})`">
              <el-table :data="p.commissions" size="small" border>
                <el-table-column prop="order_id" label="订单" width="70" />
                <el-table-column prop="gen" label="代数" width="60" align="center" />
                <el-table-column prop="receiver_team_level" label="当时团队等级" width="100" align="center" />
                <el-table-column prop="rate" label="比例" width="80" align="center" />
                <el-table-column prop="amount" label="金额" width="100" align="right" />
                <el-table-column label="时间" width="160"><template #default="{ row }">{{ fmt(row.created_at) }}</template></el-table-column>
              </el-table>
            </el-tab-pane>
            <el-tab-pane :label="`提现 (${p.withdrawals.length})`">
              <el-table :data="p.withdrawals" size="small" border>
                <el-table-column prop="account" label="账户" width="80" />
                <el-table-column prop="amount" label="金额" width="90" align="right" />
                <el-table-column prop="service_fee" label="服务费" width="80" align="right" />
                <el-table-column prop="network_fee" label="网络费" width="80" align="right" />
                <el-table-column prop="address" label="地址" min-width="140" show-overflow-tooltip />
                <el-table-column prop="status" label="状态" width="80" />
                <el-table-column prop="txid" label="TXID" width="120" show-overflow-tooltip />
              </el-table>
            </el-tab-pane>
            <el-tab-pane :label="`资金明细 (${p.balance_logs.length})`">
              <el-table :data="p.balance_logs" size="small" border>
                <el-table-column prop="account" label="账户" width="80" />
                <el-table-column prop="change_type" label="类型" width="130" />
                <el-table-column prop="amount" label="金额" width="100" align="right" />
                <el-table-column prop="balance_after" label="变动后余额" width="110" align="right" />
                <el-table-column label="关联" width="120" align="center">
                  <template #default="{ row }">{{ row.ref_type }}#{{ row.ref_id }}</template>
                </el-table-column>
                <el-table-column label="时间" width="160"><template #default="{ row }">{{ fmt(row.created_at) }}</template></el-table-column>
              </el-table>
            </el-tab-pane>
            <el-tab-pane :label="`等级变动 (${p.level_logs.length})`">
              <el-table :data="p.level_logs" size="small" border>
                <el-table-column prop="kind" label="类型" width="70" />
                <el-table-column prop="level" label="等级" width="60" align="center" />
                <el-table-column prop="holding" label="依据持仓" width="100" align="right" />
                <el-table-column prop="member_count" label="人数" width="70" align="center" />
                <el-table-column prop="source" label="来源" width="90" />
                <el-table-column label="时间" width="160"><template #default="{ row }">{{ fmt(row.created_at) }}</template></el-table-column>
              </el-table>
            </el-tab-pane>
          </el-tabs>
        </template>
      </div>
    </el-drawer>
  </div>
</template>

<style scoped>
.toolbar { display: flex; gap: 10px; margin-bottom: 14px; }
.block { margin-bottom: 18px; }
</style>
