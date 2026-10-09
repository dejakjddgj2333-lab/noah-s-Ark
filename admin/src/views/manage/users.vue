<script setup>
import { onMounted, reactive, ref } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { getAdminUsers, getAdminUserProfile, deleteAdminUser } from '@/api/product'
import {
  adjustBalance,
  freezeUser,
  resetUserPassword,
  unfreezeUser,
  updateUser,
} from '@/api/admin'

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

// ── 冻结/解冻 ──
async function toggleFreeze(row) {
  const banned = row.status === 'banned'
  await ElMessageBox.confirm(
    banned ? `确认解冻 ${row.username}?` : `确认冻结 ${row.username}? 冻结后无法登录/交易。`,
    '操作确认',
    { type: 'warning' },
  )
  if (banned) {
    await unfreezeUser(row.id)
    ElMessage.success('已解冻')
  } else {
    await freezeUser(row.id)
    ElMessage.success('已冻结')
  }
  fetchList()
}

// ── 删除空账户 (服务端逐项校验: 有资金/订单/记录会 409 拒绝) ──
function isEmptyAccount(row) {
  return !Number(row.principal_balance) && !Number(row.income_balance)
    && !Number(row.principal_pending) && !Number(row.income_pending)
}

async function removeUser(row) {
  await ElMessageBox.confirm(
    `删除用户 ${row.username}? 连同其个人数据物理删除, 不可恢复 (仅空账户可删, 服务端会二次校验)。`,
    '确认删除',
    { type: 'error', confirmButtonText: '删除', cancelButtonText: '取消' },
  )
  await deleteAdminUser(row.id)
  ElMessage.success('已删除')
  fetchList()
}

// ── 余额调整 ──
const adjustVisible = ref(false)
const adjustForm = reactive({ id: null, username: '', account: 'principal', amount: '', remark: '' })

function openAdjust(row) {
  Object.assign(adjustForm, { id: row.id, username: row.username, account: 'principal', amount: '', remark: '' })
  adjustVisible.value = true
}

async function submitAdjust() {
  if (!adjustForm.amount || Number(adjustForm.amount) === 0) {
    ElMessage.warning('金额不能为 0 (负数=扣减)')
    return
  }
  if (!adjustForm.remark.trim()) {
    ElMessage.warning('必须填写调整原因')
    return
  }
  await ElMessageBox.confirm(
    `确认将 ${adjustForm.username} 的${adjustForm.account === 'principal' ? '本金' : '收益'}账户调整 ${adjustForm.amount} USDT?`,
    '二次确认',
    { type: 'warning' },
  )
  await adjustBalance(adjustForm.id, {
    account: adjustForm.account,
    amount: String(adjustForm.amount),
    remark: adjustForm.remark,
  })
  ElMessage.success('调整成功')
  adjustVisible.value = false
  fetchList()
}

// ── 重置密码 ──
async function openReset(row) {
  const { value } = await ElMessageBox.prompt(
    `为 ${row.username} 设置新密码 (至少 6 位):`,
    '重置密码',
    { inputPattern: /^.{6,}$/, inputErrorMessage: '至少 6 位', inputType: 'password' },
  )
  await resetUserPassword(row.id, { new_password: value })
  ElMessage.success('密码已重置')
}

// ── 改绑 ──
const updateVisible = ref(false)
const updateForm = reactive({ id: null, username: '', email: '', inviter_code: '' })

function openUpdate(row) {
  Object.assign(updateForm, { id: row.id, username: row.username, email: row.email, inviter_code: '' })
  updateVisible.value = true
}

async function submitUpdate() {
  const body = {}
  if (updateForm.email) body.email = updateForm.email
  if (updateForm.inviter_code) body.inviter_code = updateForm.inviter_code
  await updateUser(updateForm.id, body)
  ElMessage.success('已更新')
  updateVisible.value = false
  fetchList()
}

function fmt(t) {
  return t && t !== 'None' ? String(t).replace('T', ' ').slice(0, 19) : '-'
}

// 资金明细: 枚举值 -> 中文 (与 server balance_log 写入值对应)
const ACCOUNT_LABEL = { principal: '本金', income: '收益' }
const CHANGE_TYPE_LABEL = {
  deposit_credited: '充值入账',
  purchase: '申购扣款',
  income_settled: '收益结算',
  principal_returned: '本金返还',
  commission: '返佣入账',
  withdraw_request: '提现申请',
  withdraw_approve: '提现审核通过',
  withdraw_reject: '提现驳回退款',
  convert_in: '闪兑转入',
  convert_out: '闪兑转出',
  admin_adjust: '人工调整',
}
const accountLabel = (v) => ACCOUNT_LABEL[v] || v
const changeTypeLabel = (v) => CHANGE_TYPE_LABEL[v] || v
const REF_TYPE_LABEL = {
  deposit: '充值', order: '订单', settlement: '结算',
  withdrawal: '提现', convert: '闪兑', admin: '后台',
}
const refLabel = (row) => `${REF_TYPE_LABEL[row.ref_type] || row.ref_type}#${row.ref_id}`
// 等级变动日志
const LEVEL_KIND_LABEL = { vip: 'VIP', team: '团队' }
const LEVEL_SOURCE_LABEL = { purchase: '申购', settle: '结算' }
const levelKindLabel = (v) => LEVEL_KIND_LABEL[v] || v
const levelSourceLabel = (v) => LEVEL_SOURCE_LABEL[v] || v
// 订单/充值/提现状态 + 网络
const ORDER_STATUS_LABEL = { effective: '生效中', finished: '已完成' }
const DEPOSIT_STATUS_LABEL = { confirming: '确认中', credited: '已入账', failed: '失败' }
const WITHDRAW_STATUS_LABEL = { pending: '待审核', approved: '已打款', rejected: '已拒绝' }
const WITHDRAW_STATUS_TYPE = { pending: 'warning', approved: 'success', rejected: 'danger' }
const netLabel = (v) => (v || '').toUpperCase()

onMounted(fetchList)
</script>

<template>
  <div>
    <div class="page-head ph-blue">
      <div class="ph-icon"><el-icon><User /></el-icon></div>
      <div>
        <div class="ph-title">用户管理</div>
        <div class="ph-sub">用户查询 · 冻结 · 调账 · 档案</div>
      </div>
    </div>

    <el-card shadow="never">
      <div class="toolbar">
        <el-input v-model="keyword" placeholder="用户名 / 邮箱" clearable style="width: 240px" @keyup.enter="fetchList" />
        <el-button type="primary" @click="fetchList">搜索</el-button>
        <el-button @click="keyword = ''; fetchList()">重置</el-button>
      </div>

      <el-table :data="list" v-loading="loading" border stripe>
        <el-table-column prop="id" label="ID" width="60" />
        <el-table-column prop="username" label="用户名" min-width="110" show-overflow-tooltip />
        <el-table-column prop="email" label="邮箱" min-width="180" show-overflow-tooltip />
        <el-table-column label="状态" width="80" align="center">
          <template #default="{ row }">
            <el-tag :type="row.status === 'banned' ? 'danger' : 'success'" effect="dark" size="small">
              {{ row.status === 'banned' ? '已冻结' : '正常' }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column label="VIP" width="80" align="center">
          <template #default="{ row }">
            <el-tag v-if="row.vip_level > 0" type="primary" effect="dark" size="small">VIP{{ row.vip_level }}</el-tag>
            <span v-else class="cell-muted">—</span>
          </template>
        </el-table-column>
        <el-table-column label="团队等级" width="90" align="center">
          <template #default="{ row }">
            <el-tag v-if="row.team_level > 0" type="success" effect="plain" size="small">{{ row.team_level }} 级</el-tag>
            <span v-else class="cell-muted">—</span>
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
        <el-table-column prop="created_at" label="注册时间" width="165">
          <template #default="{ row }">{{ fmt(row.created_at) }}</template>
        </el-table-column>
        <el-table-column label="操作" width="290" fixed="right" align="center">
          <template #default="{ row }">
            <el-button size="small" type="primary" plain @click="openProfile(row)">档案</el-button>
            <el-button
              v-perm="'btn:user:freeze'"
              size="small"
              :type="row.status === 'banned' ? 'success' : 'warning'"
              plain
              @click="toggleFreeze(row)"
            >{{ row.status === 'banned' ? '解冻' : '冻结' }}</el-button>
            <el-button v-perm="'btn:user:adjust'" size="small" type="danger" plain @click="openAdjust(row)">调账</el-button>
            <el-dropdown trigger="click" style="margin-left: 8px; vertical-align: middle">
              <el-button size="small" plain>更多</el-button>
              <template #dropdown>
                <el-dropdown-menu>
                  <el-dropdown-item v-perm="'btn:user:reset'" @click="openReset(row)">重置密码</el-dropdown-item>
                  <el-dropdown-item v-perm="'btn:user:update'" @click="openUpdate(row)">改绑邮箱/上级</el-dropdown-item>
                  <el-dropdown-item
                    v-if="isEmptyAccount(row)"
                    v-perm="'btn:user:delete'"
                    divided
                    @click="removeUser(row)"
                  ><span style="color: var(--el-color-danger)">删除空账户</span></el-dropdown-item>
                </el-dropdown-menu>
              </template>
            </el-dropdown>
          </template>
        </el-table-column>
      </el-table>
    </el-card>

    <!-- 余额调整 -->
    <el-dialog v-model="adjustVisible" title="余额调整" width="420px">
      <el-form label-width="80px">
        <el-form-item label="用户">{{ adjustForm.username }}</el-form-item>
        <el-form-item label="账户">
          <el-radio-group v-model="adjustForm.account">
            <el-radio value="principal">本金</el-radio>
            <el-radio value="income">收益</el-radio>
          </el-radio-group>
        </el-form-item>
        <el-form-item label="金额">
          <el-input v-model="adjustForm.amount" placeholder="正数=加, 负数=减 (如 -50)" />
        </el-form-item>
        <el-form-item label="原因">
          <el-input v-model="adjustForm.remark" type="textarea" placeholder="必填, 记入审计日志" />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="adjustVisible = false">取消</el-button>
        <el-button type="primary" @click="submitAdjust">确认调整</el-button>
      </template>
    </el-dialog>

    <!-- 改绑 -->
    <el-dialog v-model="updateVisible" title="改绑信息" width="420px">
      <el-form label-width="80px">
        <el-form-item label="用户">{{ updateForm.username }}</el-form-item>
        <el-form-item label="邮箱">
          <el-input v-model="updateForm.email" />
        </el-form-item>
        <el-form-item label="上级">
          <el-input v-model="updateForm.inviter_code" placeholder="新上级邀请码, 留空不改" />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="updateVisible = false">取消</el-button>
        <el-button type="primary" @click="submitUpdate">保存</el-button>
      </template>
    </el-dialog>

    <el-drawer v-model="drawerVisible" title="用户全量档案（只读）" size="880px">
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
                <el-table-column label="状态" width="90" align="center">
                  <template #default="{ row }">
                    <el-tag :type="row.status === 'effective' ? 'success' : 'info'" size="small">
                      {{ ORDER_STATUS_LABEL[row.status] || row.status }}
                    </el-tag>
                  </template>
                </el-table-column>
                <el-table-column label="锁定VIP/加成" width="110" align="center">
                  <template #default="{ row }">VIP{{ row.vip_level }} / {{ row.lock_bonus_rate }}</template>
                </el-table-column>
                <el-table-column label="生效" width="150"><template #default="{ row }">{{ fmt(row.effective_at) }}</template></el-table-column>
                <el-table-column label="到期" width="150"><template #default="{ row }">{{ fmt(row.expires_at) }}</template></el-table-column>
              </el-table>
            </el-tab-pane>
            <el-tab-pane :label="`充值 (${p.deposits.length})`">
              <el-table :data="p.deposits" size="small" border>
                <el-table-column label="网络" width="90" align="center">
                  <template #default="{ row }">
                    <el-tag effect="plain" size="small">{{ netLabel(row.network) }}</el-tag>
                  </template>
                </el-table-column>
                <el-table-column prop="amount" label="金额" width="100" align="right" />
                <el-table-column prop="txid" label="TXID" min-width="160" show-overflow-tooltip />
                <el-table-column prop="confirmations" label="确认数" width="70" align="center" />
                <el-table-column label="状态" width="90" align="center">
                  <template #default="{ row }">
                    <el-tag :type="row.status === 'credited' ? 'success' : 'warning'" size="small">
                      {{ DEPOSIT_STATUS_LABEL[row.status] || row.status }}
                    </el-tag>
                  </template>
                </el-table-column>
                <el-table-column label="入账时间" width="150"><template #default="{ row }">{{ fmt(row.credited_at) }}</template></el-table-column>
              </el-table>
            </el-tab-pane>
            <el-tab-pane :label="`收益结算 (${p.settlements.length})`">
              <el-table :data="p.settlements" size="small" border>
                <el-table-column prop="order_id" label="订单" width="70" />
                <el-table-column prop="period_no" label="期数" width="60" align="center" />
                <el-table-column prop="income_amount" label="收益" width="100" align="right" />
                <el-table-column prop="principal_amount" label="返本" width="100" align="right" />
                <el-table-column label="时间" min-width="160"><template #default="{ row }">{{ fmt(row.created_at) }}</template></el-table-column>
              </el-table>
            </el-tab-pane>
            <el-tab-pane :label="`佣金 (${p.commissions.length})`">
              <el-table :data="p.commissions" size="small" border>
                <el-table-column prop="order_id" label="订单" width="70" />
                <el-table-column prop="gen" label="代数" width="60" align="center" />
                <el-table-column prop="receiver_team_level" label="当时团队等级" width="100" align="center" />
                <el-table-column prop="rate" label="比例" width="80" align="center" />
                <el-table-column prop="amount" label="金额" width="100" align="right" />
                <el-table-column label="时间" min-width="160"><template #default="{ row }">{{ fmt(row.created_at) }}</template></el-table-column>
              </el-table>
            </el-tab-pane>
            <el-tab-pane :label="`提现 (${p.withdrawals.length})`">
              <el-table :data="p.withdrawals" size="small" border>
                <el-table-column label="账户" width="70" align="center">
                  <template #default="{ row }">
                    <el-tag :type="row.account === 'principal' ? 'primary' : 'success'" effect="plain" size="small">
                      {{ accountLabel(row.account) }}
                    </el-tag>
                  </template>
                </el-table-column>
                <el-table-column prop="amount" label="金额" width="90" align="right" />
                <el-table-column prop="service_fee" label="服务费" width="80" align="right" />
                <el-table-column prop="network_fee" label="网络费" width="80" align="right" />
                <el-table-column prop="address" label="地址" min-width="140" show-overflow-tooltip />
                <el-table-column label="状态" width="90" align="center">
                  <template #default="{ row }">
                    <el-tag :type="WITHDRAW_STATUS_TYPE[row.status] || 'info'" size="small">
                      {{ WITHDRAW_STATUS_LABEL[row.status] || row.status }}
                    </el-tag>
                  </template>
                </el-table-column>
                <el-table-column prop="txid" label="TXID" width="120" show-overflow-tooltip />
              </el-table>
            </el-tab-pane>
            <el-tab-pane :label="`资金明细 (${p.balance_logs.length})`">
              <el-table :data="p.balance_logs" size="small" border>
                <el-table-column label="账户" width="70" align="center">
                  <template #default="{ row }">
                    <el-tag :type="row.account === 'principal' ? 'primary' : 'success'" effect="plain" size="small">
                      {{ accountLabel(row.account) }}
                    </el-tag>
                  </template>
                </el-table-column>
                <el-table-column label="类型" min-width="110" show-overflow-tooltip>
                  <template #default="{ row }">{{ changeTypeLabel(row.change_type) }}</template>
                </el-table-column>
                <el-table-column label="金额" width="110" align="right">
                  <template #default="{ row }">
                    <span :style="{ color: Number(row.amount) >= 0 ? '#22c1a3' : '#ff5f6d', fontWeight: 600 }">
                      {{ Number(row.amount) >= 0 ? '+' : '' }}{{ row.amount }}
                    </span>
                  </template>
                </el-table-column>
                <el-table-column prop="balance_after" label="变动后余额" width="110" align="right" />
                <el-table-column label="关联" min-width="100" align="center">
                  <template #default="{ row }">{{ refLabel(row) }}</template>
                </el-table-column>
                <el-table-column label="时间" width="160"><template #default="{ row }">{{ fmt(row.created_at) }}</template></el-table-column>
              </el-table>
            </el-tab-pane>
            <el-tab-pane :label="`等级变动 (${p.level_logs.length})`">
              <el-table :data="p.level_logs" size="small" border>
                <el-table-column label="类型" width="80" align="center">
                  <template #default="{ row }">
                    <el-tag :type="row.kind === 'vip' ? 'primary' : 'success'" effect="plain" size="small">
                      {{ levelKindLabel(row.kind) }}
                    </el-tag>
                  </template>
                </el-table-column>
                <el-table-column prop="level" label="等级" width="60" align="center" />
                <el-table-column prop="holding" label="依据持仓" width="100" align="right" />
                <el-table-column prop="member_count" label="人数" width="70" align="center" />
                <el-table-column label="来源" min-width="90">
                  <template #default="{ row }">{{ levelSourceLabel(row.source) }}</template>
                </el-table-column>
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
.cell-muted { color: #5a607f; }
</style>
