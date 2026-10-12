<script setup>
import { computed, onMounted, reactive, ref } from 'vue'
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

const pendingCount = computed(() => list.value.filter((r) => r.status === 'pending').length)

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
  const noun = row.comment_id ? '评论' : '消息'
  const tip = {
    delete_message: `删除该${noun}` + (ban ? '并封禁该用户' : '') + '?',
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
    <div class="page-head ph-pink">
      <div class="ph-icon"><el-icon><Warning /></el-icon></div>
      <div>
        <div class="ph-title">
          举报处理
          <span class="ph-chips">
            <span v-if="pendingCount" class="ph-chip warn"><i class="dot warn" />待处理 {{ pendingCount }}</span>
            <span v-else class="ph-chip ok"><i class="dot ok" />队列清空</span>
          </span>
        </div>
        <div class="ph-sub">用户举报审核 · 结案</div>
      </div>
      <div class="ph-right">
        <el-button :loading="loading" @click="fetchList">
          <el-icon style="margin-right: 4px"><Refresh /></el-icon>刷新数据
        </el-button>
      </div>
    </div>

    <el-card shadow="never">
      <div class="toolbar" style="margin-bottom: 14px; display: flex; gap: 10px">
        <el-radio-group :model-value="query.status" @change="(v) => { query.status = v; fetchList() }">
          <el-radio-button value="">全部</el-radio-button>
          <el-radio-button value="pending">待处理</el-radio-button>
          <el-radio-button value="resolved">已处理</el-radio-button>
          <el-radio-button value="dismissed">已驳回</el-radio-button>
        </el-radio-group>
      </div>
      <div class="alert-bar">
        <el-icon><InfoFilled /></el-icon>
        删消息/删评论会立即移除违规内容; 封号后用户无法登录; 驳回表示举报不成立。
      </div>

      <el-table :data="list" stripe>
        <el-table-column label="举报" min-width="180">
          <template #default="{ row }">
            <div class="cell-main" style="font-weight: 600">{{ row.reporter }} <span style="font-weight: 400; color: var(--app-text-2)">举报</span> {{ row.target }}</div>
            <div class="cell-sub">#{{ row.id }} · {{ REASONS[row.reason] || row.reason }}</div>
          </template>
        </el-table-column>
        <el-table-column label="类型" width="90" align="center">
          <template #default="{ row }">
            <el-tag size="small" :type="row.comment_id ? 'primary' : 'info'" effect="plain">
              {{ row.comment_id ? '评论' : (row.message_id ? '消息' : '用户') }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column prop="message_content" label="相关内容" min-width="180" show-overflow-tooltip>
          <template #default="{ row }"><span class="cell-main">{{ row.message_content || '—' }}</span></template>
        </el-table-column>
        <el-table-column prop="detail" label="补充说明" min-width="140" show-overflow-tooltip>
          <template #default="{ row }"><span class="cell-sub">{{ row.detail || '—' }}</span></template>
        </el-table-column>
        <el-table-column label="状态" width="100" align="center">
          <template #default="{ row }">
            <el-tag :type="row.status === 'pending' ? 'warning' : (row.status === 'resolved' ? 'success' : 'info')" size="small" effect="light">
              {{ STATUS[row.status] || row.status }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column label="操作" width="250" align="center" fixed="right">
          <template #default="{ row }">
            <template v-if="row.status === 'pending'">
              <el-button v-if="row.message_id || row.comment_id" v-perm="'btn:report:handle'" size="small" type="danger" plain
                @click="handle(row, 'delete_message')">{{ row.comment_id ? '删评论' : '删消息' }}</el-button>
              <el-button v-perm="'btn:report:handle'" size="small" type="danger" plain
                @click="handle(row, 'ban_user')">封号</el-button>
              <el-button v-perm="'btn:report:handle'" size="small" plain
                @click="handle(row, 'dismiss')">驳回</el-button>
            </template>
            <span v-else class="cell-sub">已结案</span>
          </template>
        </el-table-column>
      </el-table>
      <div class="table-foot">
        <span class="cell-sub">共 {{ total }} 条举报</span>
      </div>
    </el-card>
  </div>
</template>
