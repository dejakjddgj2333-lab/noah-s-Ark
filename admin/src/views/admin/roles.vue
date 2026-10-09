<script setup>
import { onMounted, reactive, ref } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import {
  createRole,
  deleteRole,
  getPermissionTree,
  getRoles,
  updateRole,
} from '@/api/admin'

const loading = ref(false)
const roles = ref([])
const tree = ref([])

const dialogVisible = ref(false)
const editing = ref(null) // null=新建
const form = reactive({ name: '', perms: [] })
const treeRef = ref()

async function fetchAll() {
  loading.value = true
  try {
    const [r, t] = await Promise.all([getRoles(), getPermissionTree()])
    roles.value = r
    tree.value = t.tree
  } finally {
    loading.value = false
  }
}

function openCreate() {
  editing.value = null
  Object.assign(form, { name: '', perms: [] })
  dialogVisible.value = true
  // 等树渲染后清空勾选
  setTimeout(() => treeRef.value?.setCheckedKeys([]))
}

function openEdit(row) {
  editing.value = row
  Object.assign(form, { name: row.name, perms: row.perms })
  dialogVisible.value = true
  // 只回显叶子勾选 (父节点由半选推导); '*' 超管不回显
  setTimeout(() => {
    const leaf = new Set()
    for (const p of tree.value) for (const c of p.children || []) leaf.add(c.code)
    const keys = (row.perms || []).filter((k) => leaf.has(k) || !tree.value.some((p) => p.code === k))
    treeRef.value?.setCheckedKeys([...keys, ...(row.perms || []).filter((k) => !leaf.has(k))])
  })
}

async function submit() {
  const checked = treeRef.value.getCheckedKeys()
  const half = treeRef.value.getHalfCheckedKeys()
  const perms = [...new Set([...checked, ...half])]
  if (!form.name.trim()) {
    ElMessage.warning('角色名必填')
    return
  }
  if (editing.value) {
    await updateRole(editing.value.id, { name: form.name, perms })
    ElMessage.success('角色已更新')
  } else {
    await createRole({ name: form.name, perms })
    ElMessage.success('角色已创建')
  }
  dialogVisible.value = false
  fetchAll()
}

async function remove(row) {
  await ElMessageBox.confirm(`确认删除角色「${row.name}」?`, '删除确认', { type: 'warning' })
  await deleteRole(row.id)
  ElMessage.success('已删除')
  fetchAll()
}

const treeProps = { label: 'name', children: 'children' }

// 权限码 → 中文名映射 (权限树接口返回的 name 拍平)
const permName = (code) => {
  for (const p of tree.value) {
    if (p.code === code) return p.name
    for (const c of p.children || []) {
      if (c.code === code) return `${p.name} · ${c.name}`
    }
  }
  return code
}

onMounted(fetchAll)
</script>

<template>
  <div v-loading="loading">
    <div class="page-head ph-pink">
      <div class="ph-icon"><el-icon><Lock /></el-icon></div>
      <div>
        <div class="ph-title">角色权限</div>
        <div class="ph-sub">角色定义 · 权限分配</div>
      </div>
    </div>

    <el-card shadow="never">
      <div class="toolbar">
        <el-button v-perm="'btn:role:manage'" type="primary" @click="openCreate">新建角色</el-button>
      </div>
      <el-table :data="roles" border stripe>
        <el-table-column prop="name" label="角色名" min-width="120">
          <template #default="{ row }">
            {{ row.name }}
            <el-tag v-if="row.builtin" size="small" effect="plain" style="margin-left: 6px">内置</el-tag>
          </template>
        </el-table-column>
        <el-table-column prop="code" label="编码" width="140" />
        <el-table-column label="权限" min-width="320">
          <template #default="{ row }">
            <el-tag v-if="row.perms.includes('*')" type="danger" effect="dark" size="small">全部权限</el-tag>
            <template v-else>
              <el-tag
                v-for="perm in row.perms.filter((x) => x.startsWith('page:'))"
                :key="perm"
                size="small"
                effect="plain"
                style="margin: 2px 4px 2px 0"
              >{{ permName(perm) }}</el-tag>
            </template>
          </template>
        </el-table-column>
        <el-table-column label="操作" width="160" fixed="right">
          <template #default="{ row }">
            <el-button
              v-perm="'btn:role:manage'"
              size="small"
              type="primary"
              plain
              :disabled="row.code === 'superadmin'"
              @click="openEdit(row)"
            >编辑</el-button>
            <el-button
              v-perm="'btn:role:manage'"
              size="small"
              type="danger"
              plain
              :disabled="row.code === 'superadmin'"
              @click="remove(row)"
            >删除</el-button>
          </template>
        </el-table-column>
      </el-table>
    </el-card>

    <el-dialog v-model="dialogVisible" :title="editing ? '编辑角色' : '新建角色'" width="480px">
      <el-form label-width="80px">
        <el-form-item label="角色名">
          <el-input v-model="form.name" placeholder="如: 财务主管" />
        </el-form-item>
        <el-form-item label="权限">
          <el-tree
            ref="treeRef"
            :data="tree"
            :props="treeProps"
            node-key="code"
            show-checkbox
            default-expand-all
            style="width: 100%"
          />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="dialogVisible = false">取消</el-button>
        <el-button type="primary" @click="submit">保存</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<style scoped>
.toolbar { display: flex; gap: 10px; margin-bottom: 14px; }
</style>
