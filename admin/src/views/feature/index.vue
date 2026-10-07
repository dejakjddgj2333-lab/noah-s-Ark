<script setup>
import { onMounted, ref } from 'vue'
import { ElMessage } from 'element-plus'
import { getConfigs, updateConfig } from '@/api/moderation'

const loading = ref(false)
const saving = ref('')
const list = ref([])

async function fetchAll() {
  loading.value = true
  try {
    list.value = await getConfigs()
  } finally {
    loading.value = false
  }
}

async function toggle(row) {
  const next = row.value === '1' ? '0' : '1'
  saving.value = row.key
  try {
    await updateConfig(row.key, next)
    row.value = next
    ElMessage.success(next === '1' ? '已开启' : '已关闭')
  } finally {
    saving.value = ''
  }
}

onMounted(fetchAll)
</script>

<template>
  <div v-loading="loading">
    <el-card shadow="never">
      <el-alert type="warning" :closable="false" show-icon style="margin-bottom: 14px">
        <template #title>
          充值/提现涉及资金合规资质。开启前请确认已取得相应资质; 未开启时 App 内隐藏充值/提现入口。
        </template>
      </el-alert>
      <el-table :data="list" border stripe>
        <el-table-column prop="label" label="功能" min-width="200" />
        <el-table-column prop="key" label="标识" min-width="160" />
        <el-table-column label="状态" width="120" align="center">
          <template #default="{ row }">
            <el-tag :type="row.value === '1' ? 'success' : 'info'">
              {{ row.value === '1' ? '已开启' : '已关闭' }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column label="操作" width="140" align="center">
          <template #default="{ row }">
            <el-button
              v-perm="'btn:feature:edit'"
              size="small"
              :type="row.value === '1' ? 'warning' : 'primary'"
              plain
              :loading="saving === row.key"
              @click="toggle(row)"
            >{{ row.value === '1' ? '关闭' : '开启' }}</el-button>
          </template>
        </el-table-column>
      </el-table>
    </el-card>
  </div>
</template>
