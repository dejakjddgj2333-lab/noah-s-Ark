<script setup>
import { computed, onMounted, ref } from 'vue'
import { ElMessage } from 'element-plus'
import { getConfigs, updateConfig } from '@/api/moderation'

const loading = ref(false)
const saving = ref('')
const list = ref([])

const enabledCount = computed(() => list.value.filter((r) => r.value === '1').length)

// App 端充值/理财显隐已改编译期常量 (--dart-define), 这两个键不再生效
const DEPRECATED_KEYS = ['wallet_enabled', 'finance_enabled']

async function fetchAll() {
  loading.value = true
  try {
    list.value = await getConfigs()
  } finally {
    loading.value = false
  }
}

async function toggle(row) {
  if (DEPRECATED_KEYS.includes(row.key)) {
    ElMessage.warning('该功能已改为编译期开关 (--dart-define), 此处切换不会生效')
    return
  }
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
    <div class="page-head ph-gold">
      <div class="ph-icon"><el-icon><Switch /></el-icon></div>
      <div>
        <div class="ph-title">
          功能开关
          <span class="ph-chips">
            <span class="ph-chip ok"><i class="dot ok" />开启 {{ enabledCount }}</span>
            <span class="ph-chip info">共 {{ list.length }} 项</span>
          </span>
        </div>
        <div class="ph-sub">充值 / 提现入口开关</div>
      </div>
      <div class="ph-right">
        <el-button :loading="loading" @click="fetchAll">
          <el-icon style="margin-right: 4px"><Refresh /></el-icon>刷新数据
        </el-button>
      </div>
    </div>

    <el-card shadow="never" style="max-width: 920px">
      <div class="alert-bar" style="background: rgba(247,183,51,0.1); border-color: rgba(247,183,51,0.3)">
        <el-icon style="color: #b45309"><WarningFilled /></el-icon>
        充值/提现涉及资金合规资质, 开启前请确认已取得相应资质; 未开启时 App 内隐藏对应入口。
        充值/理财显隐已改为编译期开关 (--dart-define), 对应行已标记「编译期」, 此处切换不生效。
      </div>
      <el-table :data="list" stripe>
        <el-table-column label="功能" min-width="220">
          <template #default="{ row }">
            <div class="cell-main" style="font-weight: 600">{{ row.label }}</div>
            <div class="cell-sub" style="font-family: monospace">{{ row.key }}</div>
          </template>
        </el-table-column>
        <el-table-column label="状态" width="130" align="center">
          <template #default="{ row }">
            <el-tag v-if="DEPRECATED_KEYS.includes(row.key)" type="info" size="small" effect="plain">编译期控制</el-tag>
            <el-tag v-else :type="row.value === '1' ? 'success' : 'info'" size="small" effect="light">
              {{ row.value === '1' ? '已开启' : '已关闭' }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column label="开关" width="100" align="center">
          <template #default="{ row }">
            <el-switch
              v-perm="'btn:feature:edit'"
              :model-value="row.value === '1'"
              :loading="saving === row.key"
              :disabled="DEPRECATED_KEYS.includes(row.key)"
              @change="toggle(row)"
            />
          </template>
        </el-table-column>
      </el-table>
      <div class="table-foot">
        <span class="cell-sub">共 {{ list.length }} 个开关 · 开启 {{ enabledCount }} 个</span>
      </div>
    </el-card>
  </div>
</template>
