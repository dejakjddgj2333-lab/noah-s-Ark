<script setup>
import { onMounted, reactive, ref } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { getReports, handleReport } from '@/api/moderation'

const loading = ref(false)
const list = ref([])
const total = ref(0)
const query = reactive({ status: '', limit: 100, offset: 0 })

const REASONS = {
  spam: '垃圾信息', abuse: '辱骂骚扰', fraud: '诈骗', porn: '色情内容', other: '其他',
}
const STATUS = { pending: '待处理', resolved: '已处理', dismissed: '已驳回' }

async function fetchList() {
  loading.value = true
  try {
    const params = { limit: query.limit, offset: query.offset }
    if (query.status) params.status = query.status
    const r = await getReports(params)
    list.value = r.items || []
    total.value = r.total || 0
  } finally {
    loading.value = false
  }
}

async function handle(row, action, ban = false) {
  const tip = {
    delete_message: '删除该消息' + (ban ? '并封禁该用户' : '') + '?',
    ban_user: '封禁该用户?',
    dismiss: '驳回该举报?',
  }[action]
  await ElMessageBox.confirm(tip, '确认', { type: 'warning' })
  await handleReport(row.id, { action, ban })
  ElMessage.success('已处理')
  fetchList()
}

onMounted(fetchList)
</script>

<template>
  <div v-loading="loading">
    <el-card shadow="never">
      <div class="toolbar" style="margin-bottom: 14px; display: flex; gap: 10px">
        <el-select v-model="query.status" placeholder="全部状态" clearable style="width: 140px" @change="fetchList">
          <el-option label="待处理" value="pending" />
          <el-option label="已处理" value="resolved" />
          <el-option label="已驳回" value="dismissed" />
        </el-select>
        <el-button type="primary" @click="fetchList">刷新</el-button>
      </div>

      <el-table :data="list" border stripe>
        <el-table-column prop="id" label="ID" width="70" />
        <el-table-column prop="reporter" label="举报人" min-width="110" />
        <el-table-column prop="target" label="被举报人" min-width="110" />
        <el-table-column label="原因" width="110">
          <template #default="{ row }">{{ REASONS[row.reason] || row.reason }}</template>
        </el-table-column>
        <el-table-column prop="message_content" label="相关消息" min-width="160" show-overflow-tooltip>
          <template #default="{ row }">{{ row.message_content || '—' }}</template>
        </el-table-column>
        <el-table-column prop="detail" label="补充说明" min-width="140" show-overflow-tooltip>
          <template #default="{ row }">{{ row.detail || '—' }}</template>
        </el-table-column>
        <el-table-column label="状态" width="100" align="center">
          <template #default="{ row }">
            <el-tag :type="row.status === 'pending' ? 'warning' : (row.status === 'resolved' ? 'success' : 'info')">
              {{ STATUS[row.status] || row.status }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column label="操作" width="240" align="center">
          <template #default="{ row }">
            <template v-if="row.status === 'pending'">
              <el-button v-if="row.message_id" v-perm="'btn:report:handle'" size="small" type="danger" plain
                @click="handle(row, 'delete_message')">删消息</el-button>
              <el-button v-perm="'btn:report:handle'" size="small" type="danger" plain
                @click="handle(row, 'ban_user')">封号</el-button>
              <el-button v-perm="'btn:report:handle'" size="small" plain
                @click="handle(row, 'dismiss')">驳回</el-button>
            </template>
            <span v-else style="color: #909399">已结案</span>
          </template>
        </el-table-column>
      </el-table>
      <div style="margin-top: 12px; color: #909399; font-size: 12px">共 {{ total }} 条</div>
    </el-card>
  </div>
</template>
