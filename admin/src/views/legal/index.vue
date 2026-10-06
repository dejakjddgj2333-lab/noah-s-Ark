<script setup>
import { computed, onMounted, reactive, ref } from 'vue'
import { ElMessage } from 'element-plus'
import { getLegalDocs, updateLegalDoc } from '@/api/legal'

const loading = ref(false)
const saving = ref(false)
const active = ref('privacy')

const docs = reactive({
  privacy: { title: '', content: '' },
  terms: { title: '', content: '' },
})

const tabs = [
  { key: 'privacy', label: '隐私政策' },
  { key: 'terms', label: '用户协议' },
]

const publicUrl = computed(() => `/api/legal/${active.value}`)

async function fetchAll() {
  loading.value = true
  try {
    const r = await getLegalDocs()
    for (const { key } of tabs) {
      if (r && r[key]) {
        docs[key].title = r[key].title || ''
        docs[key].content = r[key].content || ''
      }
    }
  } finally {
    loading.value = false
  }
}

async function save() {
  saving.value = true
  try {
    await updateLegalDoc(active.value, {
      title: docs[active.value].title,
      content: docs[active.value].content,
    })
    ElMessage.success('已保存')
  } finally {
    saving.value = false
  }
}

onMounted(fetchAll)
</script>

<template>
  <div v-loading="loading">
    <el-card shadow="never">
      <el-tabs v-model="active">
        <el-tab-pane
          v-for="t in tabs"
          :key="t.key"
          :label="t.label"
          :name="t.key"
        />
      </el-tabs>

      <el-alert
        type="info"
        :closable="false"
        show-icon
        style="margin-bottom: 14px"
      >
        <template #title>
          公开地址: <el-link type="primary" :href="publicUrl" target="_blank">{{ publicUrl }}</el-link>
          (无需登录, 可直接复制访问)
        </template>
      </el-alert>

      <el-form label-width="80px">
        <el-form-item label="标题">
          <el-input v-model="docs[active].title" placeholder="协议标题" />
        </el-form-item>
        <el-form-item label="内容">
          <el-input
            v-model="docs[active].content"
            type="textarea"
            :rows="22"
            placeholder="完整 HTML 内容"
          />
        </el-form-item>
        <el-form-item>
          <el-button
            v-perm="'btn:legal:edit'"
            type="primary"
            :loading="saving"
            @click="save"
          >保存</el-button>
        </el-form-item>
      </el-form>
    </el-card>
  </div>
</template>
