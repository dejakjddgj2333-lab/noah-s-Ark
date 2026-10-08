<script setup>
import { computed, onMounted, ref } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { getAdminConfig, updateAdminConfig } from '@/api/config'

const loading = ref(false)
const saving = ref(false)
const items = ref([])
// 编辑中的值 (key → 字符串), 保存时只提交被改过的
const edits = ref({})

const GROUPS = [
  { key: 'convert', label: '收益转本金' },
  { key: 'withdraw', label: '提现' },
  { key: 'ratelimit', label: '限流' },
]

const dirtyCount = computed(() => Object.keys(edits.value).length)

function grouped(g) {
  return items.value.filter(i => i.group === g)
}

function val(item) {
  return edits.value[item.key] ?? item.value
}

function onInput(item, v) {
  const s = String(v ?? '').trim()
  if (s === item.value) {
    delete edits.value[item.key]
  } else {
    edits.value[item.key] = s
  }
  edits.value = { ...edits.value }
}

async function fetchAll() {
  loading.value = true
  try {
    const r = await getAdminConfig()
    items.value = r.items || []
    edits.value = {}
  } finally {
    loading.value = false
  }
}

async function save() {
  if (!dirtyCount.value) return
  const names = items.value
    .filter(i => edits.value[i.key] !== undefined)
    .map(i => `${i.name}: ${i.value} → ${edits.value[i.key]}`)
  await ElMessageBox.confirm(
    names.join('\n'),
    `确认保存 ${dirtyCount.value} 项参数? 保存后立即生效`,
    { type: 'warning', confirmButtonText: '保存', cancelButtonText: '取消' },
  )
  saving.value = true
  try {
    await updateAdminConfig({ ...edits.value })
    ElMessage.success('已保存, 即时生效')
    await fetchAll()
  } finally {
    saving.value = false
  }
}

onMounted(fetchAll)
</script>

<template>
  <div v-loading="loading">
    <el-alert type="info" :closable="false" show-icon style="margin-bottom: 14px">
      <template #title>
        保存后立即生效, 无需重启。标「改」的为后台覆盖值, 其余为环境变量默认值。
      </template>
    </el-alert>

    <el-card v-for="g in GROUPS" :key="g.key" shadow="never" style="margin-bottom: 14px">
      <template #header>{{ g.label }}</template>
      <el-form label-width="170px">
        <el-form-item v-for="item in grouped(g.key)" :key="item.key">
          <template #label>
            {{ item.name }}
            <el-tag v-if="item.overridden" type="warning" size="small" effect="plain">改</el-tag>
          </template>
          <div style="display: flex; align-items: center; gap: 10px; width: 100%">
            <el-input
              :model-value="val(item)"
              style="max-width: 220px"
              @input="v => onInput(item, v)"
            />
            <span class="cfg-desc">
              {{ item.desc }} (范围 {{ item.min }} ~ {{ item.max }}, 默认 {{ item.default }})
            </span>
          </div>
        </el-form-item>
      </el-form>
    </el-card>

    <el-button
      v-perm="'btn:config:edit'"
      type="primary"
      :loading="saving"
      :disabled="!dirtyCount"
      @click="save"
    >保存修改 ({{ dirtyCount }})</el-button>
  </div>
</template>

<style scoped>
.cfg-desc {
  color: var(--el-text-color-secondary);
  font-size: 12px;
  line-height: 1.4;
}
</style>
