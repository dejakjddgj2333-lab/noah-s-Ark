<script setup>
import { computed, onBeforeUnmount, onMounted, reactive, ref, shallowRef } from 'vue'
import { ElMessage } from 'element-plus'
import '@wangeditor/editor/dist/css/style.css'
import { Editor, Toolbar } from '@wangeditor/editor-for-vue'
import { getLegalDocs, updateLegalDoc } from '@/api/legal'

const loading = ref(false)
const saving = ref(false)
const active = ref('privacy')
const sourceMode = ref(false) // true=源码编辑

const docs = reactive({
  privacy: { title: '', content: '' },
  terms: { title: '', content: '' },
})

const tabs = [
  { key: 'privacy', label: '隐私政策' },
  { key: 'terms', label: '用户协议' },
]

const publicUrl = computed(() => `/api/legal/${active.value}`)

// 存量完整 HTML 文档提示 (富文本保存后自动转片段 + 标准外壳)
const isLegacyDoc = computed(
  () => docs[active.value].content.slice(0, 256).toLowerCase().includes('<html'),
)

// wangEditor 实例 (shallowRef 避免深度响应)
const editorRef = shallowRef()
const toolbarConfig = {
  excludeKeys: ['uploadImage', 'uploadVideo', 'insertVideo', 'group-video', 'fullScreen', 'emotion', 'codeBlock'],
}
const editorConfig = { placeholder: '在此编辑协议正文, 支持标题/列表/表格/链接...' }

function onEditorCreated(editor) {
  editorRef.value = editor
}

onBeforeUnmount(() => {
  editorRef.value?.destroy()
})

function switchMode(toSource) {
  if (!toSource && editorRef.value) {
    // 源码 -> 富文本: 重建编辑器加载最新内容 (v-if 重建即可)
  }
  sourceMode.value = toSource
}

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
    <div class="page-head ph-teal">
      <div class="ph-icon"><el-icon><Document /></el-icon></div>
      <div>
        <div class="ph-title">法务文档</div>
        <div class="ph-sub">协议内容维护 · 富文本编辑</div>
      </div>
      <div class="ph-right">
        <el-button
          v-perm="'btn:legal:edit'"
          type="primary"
          :loading="saving"
          @click="save"
        >
          <el-icon style="margin-right: 4px"><Check /></el-icon>保存发布
        </el-button>
      </div>
    </div>

    <el-card shadow="never">
      <div class="toolbar">
        <el-radio-group v-model="active">
          <el-radio-button v-for="t in tabs" :key="t.key" :value="t.key">{{ t.label }}</el-radio-button>
        </el-radio-group>
        <div style="margin-left: auto">
          <el-radio-group :model-value="sourceMode" size="small" @change="switchMode">
            <el-radio-button :value="false">富文本</el-radio-button>
            <el-radio-button :value="true">源码</el-radio-button>
          </el-radio-group>
        </div>
      </div>

      <div class="alert-bar">
        <el-icon><InfoFilled /></el-icon>
        公开地址: <el-link type="primary" :href="publicUrl" target="_blank" style="font-size: 12px">{{ publicUrl }}</el-link>
        (无需登录, 保存后即时生效; 正文片段会自动套用带暗色适配的标准页面外壳)
      </div>

      <div v-if="isLegacyDoc && !sourceMode" class="alert-bar" style="background: rgba(247,183,51,0.1); border-color: rgba(247,183,51,0.3)">
        <el-icon style="color: #b45309"><WarningFilled /></el-icon>
        当前内容是完整 HTML 文档, 富文本模式会提取正文部分, 保存后自动转为标准片段格式。
      </div>

      <el-form label-width="70px">
        <el-form-item label="标题">
          <el-input v-model="docs[active].title" placeholder="协议标题" style="max-width: 420px" />
        </el-form-item>
        <el-form-item label="内容">
          <div class="editor-wrap">
            <template v-if="!sourceMode">
              <Toolbar
                :key="'tb-' + active"
                :editor="editorRef"
                :default-config="toolbarConfig"
                mode="default"
                class="editor-toolbar"
              />
              <Editor
                :key="'ed-' + active"
                v-model="docs[active].content"
                :default-config="editorConfig"
                mode="default"
                class="editor-body"
                @on-created="onEditorCreated"
              />
            </template>
            <el-input
              v-else
              v-model="docs[active].content"
              type="textarea"
              :rows="22"
              placeholder="HTML 源码"
              style="width: 100%"
            />
          </div>
        </el-form-item>
      </el-form>
    </el-card>
  </div>
</template>

<style scoped>
.toolbar {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 14px;
  flex-wrap: wrap;
}

.editor-wrap {
  width: 100%;
  border: 1px solid var(--app-line);
  border-radius: 10px;
  overflow: hidden;
  background: #fff;
}

.editor-toolbar {
  border-bottom: 1px solid var(--app-line);
}

.editor-body {
  height: 520px !important;
  overflow-y: hidden;
}
</style>
