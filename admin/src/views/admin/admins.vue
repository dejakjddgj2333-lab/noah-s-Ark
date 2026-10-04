<script setup>
import { onMounted, reactive, ref } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import {
  bindAdmin,
  changeAdminRole,
  getAdmins,
  getRoles,
  removeAdmin,
} from '@/api/admin'
import { useUserStore } from '@/store/user'

const userStore = useUserStore()
const loading = ref(false)
const admins = ref([])
const roles = ref([])

const dialogVisible = ref(false)
const editing = ref(null) // null=添加
const form = reactive({ username: '', role_id: null })

async function fetchAll() {
  loading.value = true
  try {
    const [a, r] = await Promise.all([getAdmins(), getRoles()])
    admins.value = a
    roles.value = r
  } finally {
    loading.value = false
  }
}

function openAdd() {
  editing.value = null
  Object.assign(form, { username: '', role_id: null })
  dialogVisible.value = true
}

function openEdit(row) {
  editing.value = row
  Object.assign(form, { username: row.username, role_id: row.role?.id || null })
  dialogVisible.value = true
}

async function submit() {
  if (!form.role_id) {
    ElMessage.warning('请选择角色')
    return
  }
  if (editing.value) {
    await changeAdminRole(editing.value.id, { username: editing.value.username, role_id: form.role_id })
    ElMessage.success('角色已更新')
  } else {
    if (!form.username.trim()) {
      ElMessage.warning('请输入用户名')
      return
    }
    await bindAdmin({ username: form.username.trim(), role_id: form.role_id })
    ElMessage.success('管理员已添加')
  }
  dialogVisible.value = false
  fetchAll()
}

async function remove(row) {
  await ElMessageBox.confirm(
    `确认移除 ${row.username} 的管理员身份? (账号保留, 失去后台权限)`,
    '移除确认',
    { type: 'warning' },
  )
  await removeAdmin(row.id)
  ElMessage.success('已移除')
  fetchAll()
}

onMounted(fetchAll)
</script>

<template>
  <div v-loading="loading">
    <el-card shadow="never">
      <div class="toolbar">
        <el-button v-perm="'btn:admin:manage'" type="primary" @click="openAdd">添加管理员</el-button>
        <span class="tip">添加的是已注册用户, 绑定角色后即可登录后台</span>
      </div>
      <el-table :data="admins" border stripe>
        <el-table-column prop="id" label="ID" width="60" />
        <el-table-column prop="username" label="用户名" min-width="110" />
        <el-table-column prop="nickname" label="昵称" min-width="100">
          <template #default="{ row }">{{ row.nickname || '-' }}</template>
        </el-table-column>
        <el-table-column prop="email" label="邮箱" min-width="170" />
        <el-table-column label="角色" min-width="120">
          <template #default="{ row }">
            <el-tag :type="row.role?.code === 'superadmin' ? 'danger' : 'primary'" effect="dark" size="small">
              {{ row.role?.name || '-' }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column label="状态" width="80" align="center">
          <template #default="{ row }">
            <el-tag :type="row.status === 'banned' ? 'info' : 'success'" size="small">
              {{ row.status === 'banned' ? '冻结' : '正常' }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column prop="created_at" label="注册时间" width="160">
          <template #default="{ row }">{{ String(row.created_at).replace('T', ' ').slice(0, 19) }}</template>
        </el-table-column>
        <el-table-column label="操作" width="170" fixed="right">
          <template #default="{ row }">
            <el-button v-perm="'btn:admin:manage'" size="small" type="primary" plain @click="openEdit(row)">改角色</el-button>
            <el-button
              v-perm="'btn:admin:manage'"
              size="small"
              type="danger"
              plain
              :disabled="row.id === userStore.info?.id"
              @click="remove(row)"
            >移除</el-button>
          </template>
        </el-table-column>
      </el-table>
    </el-card>

    <el-dialog v-model="dialogVisible" :title="editing ? '修改角色' : '添加管理员'" width="420px">
      <el-form label-width="80px">
        <el-form-item label="用户名">
          <el-input v-model="form.username" :disabled="!!editing" placeholder="已注册的用户名" />
        </el-form-item>
        <el-form-item label="角色">
          <el-select v-model="form.role_id" placeholder="选择角色" style="width: 100%">
            <el-option v-for="r in roles" :key="r.id" :value="r.id" :label="r.name" />
          </el-select>
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
.toolbar { display: flex; align-items: center; gap: 10px; margin-bottom: 14px; }
.tip { color: #909399; font-size: 12px; }
</style>
