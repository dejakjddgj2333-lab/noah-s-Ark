<script setup>
import { onMounted, reactive, ref } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import {
  getAdminProducts, createProduct, updateProduct, publishProduct, offlineProduct,
  deleteProduct,
} from '@/api/product'

const loading = ref(false)
const list = ref([])
const query = reactive({ status: '' })

const STATUS_MAP = {
  draft: { label: '草稿', type: 'info' },
  published: { label: '已上架', type: 'success' },
  offline: { label: '已下架', type: 'warning' },
}
const METHOD_MAP = { daily: '每日', period_7d: '每7天', period_30d: '每30天', expiry: '到期一次性', period_1h: '每小时' }

const dialogVisible = ref(false)
const saving = ref(false)
const editId = ref(null)
const form = reactive({
  name: '', description: '', base_daily_rate: null, duration_days: null,
  return_method: 'daily', min_amount: null, max_amount: null,
  vip_level_req: null, team_level_req: null,
})

async function fetchList() {
  loading.value = true
  try {
    list.value = await getAdminProducts(query.status ? { status_filter: query.status } : {})
  } finally {
    loading.value = false
  }
}

function openCreate() {
  editId.value = null
  Object.assign(form, {
    name: '', description: '', base_daily_rate: null, duration_days: null,
    return_method: 'daily', min_amount: null, max_amount: null,
    vip_level_req: null, team_level_req: null,
  })
  dialogVisible.value = true
}

function openEdit(row) {
  editId.value = row.id
  Object.assign(form, {
    name: row.name, description: row.description, base_daily_rate: Number(row.base_daily_rate),
    duration_days: row.duration_days, return_method: row.return_method,
    min_amount: Number(row.min_amount), max_amount: Number(row.max_amount),
    vip_level_req: row.vip_level_req, team_level_req: row.team_level_req,
  })
  dialogVisible.value = true
}

async function save() {
  saving.value = true
  try {
    const payload = { ...form }
    if (editId.value) {
      await updateProduct(editId.value, payload)
      ElMessage.success('已保存')
    } else {
      await createProduct(payload)
      ElMessage.success('已创建（草稿），上架后 APP 可见')
    }
    dialogVisible.value = false
    fetchList()
  } catch (e) {
    ElMessage.error(e?.response?.data?.detail || '保存失败')
  } finally {
    saving.value = false
  }
}

async function publish(row) {
  try {
    await ElMessageBox.confirm(`上架「${row.name}」？上架前将执行完整参数校验。`, '确认上架')
  } catch { return }
  try {
    await publishProduct(row.id)
    ElMessage.success('已上架')
    fetchList()
  } catch (e) {
    ElMessage.error(e?.response?.data?.detail || '上架校验未通过')
  }
}

async function offline(row) {
  try {
    await ElMessageBox.confirm(`下架「${row.name}」？下架后 APP 不可再购买，存量订单继续结算。`, '确认下架')
  } catch { return }
  await offlineProduct(row.id)
  ElMessage.success('已下架')
  fetchList()
}

async function remove(row) {
  try {
    await ElMessageBox.confirm(
      `删除「${row.name}」？物理删除不可恢复 (有订单的产品服务端会拒绝)。`,
      '确认删除',
      { type: 'error', confirmButtonText: '删除', cancelButtonText: '取消' },
    )
  } catch { return }
  await deleteProduct(row.id)
  ElMessage.success('已删除')
  fetchList()
}

onMounted(fetchList)
</script>

<template>
  <div>
    <div class="page-head ph-violet">
      <div class="ph-icon"><el-icon><Goods /></el-icon></div>
      <div>
        <div class="ph-title">
          产品管理
          <span class="ph-chips">
            <span class="ph-chip ok"><i class="dot ok" />在售 {{ list.filter((p) => p.status === 'published').length }}</span>
            <span class="ph-chip info">共 {{ list.length }} 个产品</span>
          </span>
        </div>
        <div class="ph-sub">理财产品配置 · 上下架</div>
      </div>
      <div class="ph-right">
        <el-button :loading="loading" @click="fetchList">
          <el-icon style="margin-right: 4px"><Refresh /></el-icon>刷新数据
        </el-button>
        <el-button v-perm="'btn:product:edit'" type="primary" @click="openCreate">
          <el-icon style="margin-right: 4px"><Plus /></el-icon>新建产品
        </el-button>
      </div>
    </div>

    <el-card shadow="never">
      <div class="toolbar">
        <el-radio-group :model-value="query.status" @change="(v) => { query.status = v; fetchList() }">
          <el-radio-button value="">全部</el-radio-button>
          <el-radio-button value="published">已上架</el-radio-button>
          <el-radio-button value="draft">草稿</el-radio-button>
          <el-radio-button value="offline">已下架</el-radio-button>
        </el-radio-group>
      </div>
      <div class="alert-bar">
        <el-icon><InfoFilled /></el-icon>
        上架前会执行完整参数校验; 下架后 APP 不可再购买, 存量订单继续结算; 有订单的产品不可删除。
      </div>

      <el-table :data="list" v-loading="loading" stripe>
        <el-table-column label="产品" min-width="180">
          <template #default="{ row }">
            <div class="cell-main" style="font-weight: 600">{{ row.name }}</div>
            <div class="cell-sub">#{{ row.id }} · {{ row.min_amount }} ~ {{ row.max_amount }} USDT</div>
          </template>
        </el-table-column>
        <el-table-column label="基础日收益率" width="110" align="center">
          <template #default="{ row }">
            <span class="amt" style="color: #16a34a">{{ (Number(row.base_daily_rate) * 100).toFixed(2) }}%</span>
          </template>
        </el-table-column>
        <el-table-column label="周期/返还" min-width="110" align="center">
          <template #default="{ row }">
            <div class="cell-main">{{ row.duration_days }} 天</div>
            <div class="cell-sub">{{ METHOD_MAP[row.return_method] }}</div>
          </template>
        </el-table-column>
        <el-table-column label="VIP门槛" width="90" align="center">
          <template #default="{ row }">
            <el-tag v-if="row.vip_level_req" size="small" type="primary" effect="plain">VIP{{ row.vip_level_req }}</el-tag>
            <span v-else class="cell-sub">不限</span>
          </template>
        </el-table-column>
        <el-table-column label="团队门槛" width="90" align="center">
          <template #default="{ row }">
            <el-tag v-if="row.team_level_req" size="small" type="success" effect="plain">{{ row.team_level_req }} 级</el-tag>
            <span v-else class="cell-sub">不限</span>
          </template>
        </el-table-column>
        <el-table-column label="状态" width="90" align="center">
          <template #default="{ row }">
            <el-tag :type="STATUS_MAP[row.status]?.type" size="small" effect="light">{{ STATUS_MAP[row.status]?.label }}</el-tag>
          </template>
        </el-table-column>
        <el-table-column label="操作" width="250" fixed="right" align="center">
          <template #default="{ row }">
            <el-button v-perm="'btn:product:edit'" v-if="row.status !== 'published'" size="small" plain @click="openEdit(row)">编辑</el-button>
            <el-button v-perm="'btn:product:edit'" v-if="row.status !== 'published'" size="small" type="success" plain @click="publish(row)">上架</el-button>
            <el-button v-perm="'btn:product:edit'" v-if="row.status === 'published'" size="small" type="warning" plain @click="offline(row)">下架</el-button>
            <el-button v-perm="'btn:product:delete'" v-if="row.status !== 'published'" size="small" type="danger" plain @click="remove(row)">删除</el-button>
          </template>
        </el-table-column>
      </el-table>
      <div class="table-foot">
        <span class="cell-sub">共 {{ list.length }} 个产品</span>
      </div>
    </el-card>

    <el-dialog v-model="dialogVisible" :title="editId ? '编辑产品' : '新建产品'" width="520px">
      <el-form :model="form" label-width="120px">
        <el-form-item label="产品名称" required>
          <el-input v-model="form.name" />
        </el-form-item>
        <el-form-item label="描述">
          <el-input v-model="form.description" type="textarea" :rows="2" />
        </el-form-item>
        <el-form-item label="基础日收益率" required>
          <el-input-number v-model="form.base_daily_rate" :min="0.000001" :max="1" :precision="6" :step="0.001" />
          <span class="tip">小数, 如 0.02 = 2%/日</span>
        </el-form-item>
        <el-form-item label="周期(天)" required>
          <el-input-number v-model="form.duration_days" :min="1" :max="3650" />
        </el-form-item>
        <el-form-item label="返还方式" required>
          <el-select v-model="form.return_method">
            <el-option label="每满24小时" value="daily" />
            <el-option label="每隔7天" value="period_7d" />
            <el-option label="每隔30天" value="period_30d" />
            <el-option label="到期一次性" value="expiry" />
            <el-option label="每小时(测试)" value="period_1h" />
          </el-select>
        </el-form-item>
        <el-form-item label="最低购买金额" required>
          <el-input-number v-model="form.min_amount" :min="0.01" :precision="2" />
        </el-form-item>
        <el-form-item label="最高购买金额" required>
          <el-input-number v-model="form.max_amount" :min="0.01" :precision="2" />
        </el-form-item>
        <el-form-item label="个人VIP门槛">
          <el-input-number v-model="form.vip_level_req" :min="0" :max="10" :precision="0" placeholder="不限" />
        </el-form-item>
        <el-form-item label="团队等级门槛">
          <el-input-number v-model="form.team_level_req" :min="0" :max="10" :precision="0" placeholder="不限" />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="dialogVisible = false">取消</el-button>
        <el-button type="primary" :loading="saving" @click="save">保存</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<style scoped>
.toolbar { display: flex; gap: 10px; margin-bottom: 14px; }
.tip { margin-left: 8px; color: #909399; font-size: 12px; }
</style>
