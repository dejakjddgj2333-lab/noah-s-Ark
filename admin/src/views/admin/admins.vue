<script setup>
import { onMounted, reactive, ref } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import {
  createAdmin,
  getAdmins,
  getRoles,
  removeAdmin,
  resetAdminTotp,
  updateAdmin,
} from '@/api/admin'
import { useUserStore } from '@/store/user'

const userStore = useUserStore()
const loading = ref(false)
const admins = ref([])
const roles = ref([])

const dialogVisible = ref(false)
const dialogMode = ref('create') // create | edit | password
const current = ref(null)
const form = reactive({ username: '', password: '', role_id: null })

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

function openCreate() {
  dialogMode.value = 'create'
  current.value = null
  Object.assign(form, { username: '', password: '', role_id: null })
  dialogVisible.value = true
}

function openEdit(row) {
  dialogMode.value = 'edit'
  current.value = row
  Object.assign(form, { username: row.username, password: '', role_id: row.role?.id || null })
  dialogVisible.value = true
}

function openPassword(row) {
  dialogMode.value = 'password'
  current.value = row
  Object.assign(form, { username: row.username, password: '', role_id: null })
  dialogVisible.value = true
}

async function submit() {
  if (dialogMode.value === 'create') {
    if (!form.username.trim() || form.username.trim().length < 3) {
      ElMessage.warning('用户名至少 3 位')
      return
    }
    if (!form.password || form.password.length < 8) {
      ElMessage.warning('密码至少 8 位')
      return
    }
    if (!form.role_id) {
      ElMessage.warning('请选择角色')
      return
    }
    await createAdmin({
      username: form.username.trim(),
      password: form.password,
      role_id: form.role_id,
    })
    ElMessage.success('管理员已创建, 首次登录需绑定谷歌验证')
  } else if (dialogMode.value === 'edit') {
    if (!form.role_id) {
      ElMessage.warning('请选择角色')
      return
    }
    await updateAdmin(current.value.id, { role_id: form.role_id })
    ElMessage.success('角色已更新')
  } else {
    if (!form.password || form.password.length < 8) {
      ElMessage.warning('密码至少 8 位')
      return
    }
    await updateAdmin(current.value.id, { password: form.password })
    ElMessage.success('密码已重置')
  }
  dialogVisible.value = false
  fetchAll()
}

async function toggleStatus(row) {
  const target = row.status === 'active' ? 'disabled' : 'active'
  await ElMessageBox.confirm(
    `确认${target === 'disabled' ? '禁用' : '启用'} ${row.username}?`,
    '操作确认',
    { type: 'warning' },
  )
  await updateAdmin(row.id, { status: target })
  ElMessage.success(target === 'disabled' ? '已禁用' : '已启用')
  fetchAll()
}

async function resetTotp(row) {
  await ElMessageBox.confirm(
    `重置 ${row.username} 的谷歌验证? 重置后下次登录需重新绑定`,
    '重置确认',
    { type: 'warning' },
  )
  await resetAdminTotp(row.id)
  ElMessage.success('已重置')
  fetchAll()
}

async function remove(row) {
  await ElMessageBox.confirm(
    `确认删除管理员 ${row.username}? 删除后无法登录后台`,
    '删除确认',
    { type: 'warning' },
  )
  await removeAdmin(row.id)
  ElMessage.success('已删除')
  fetchAll()
}

onMounted(fetchAll)
</script>

<template>
  <div v-loading="loading">
    <div class="page-head ph-violet">
      <div class="ph-icon"><el-icon><Avatar /></el-icon></div>
      <div>
        <div class="ph-title">管理员</div>
        <div class="ph-sub">独立后台账号 · 与 App 注册用户隔离 · 谷歌验证强制</div>
      </div>
    </div>

    <el-card shadow="never">
      <div class="toolbar">
        <el-button v-perm="'btn:admin:manage'" type="primary" @click="openCreate">新建管理员</el-button>
        <span class="tip">独立账号体系, 不使用 App 注册信息; 非超管首次登录必须绑定谷歌验证器</span>
      </div>
      <el-table :data="admins" border stripe>
        <el-table-column prop="id" label="ID" width="60" />
        <el-table-column prop="username" label="用户名" min-width="120" show-overflow-tooltip />
        <el-table-column label="角色" min-width="110">
          <template #default="{ row }">
            <el-tag :type="row.role?.code === 'superadmin' ? 'danger' : 'primary'" effect="dark" size="small">
              {{ row.role?.name || '-' }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column label="谷歌验证" width="100" align="center">
          <template #default="{ row }">
            <el-tag v-if="row.totp_bound" type="success" size="small" effect="plain">已绑定</el-tag>
            <el-tag v-else type="warning" size="small" effect="plain">未绑定</el-tag>
          </template>
        </el-table-column>
        <el-table-column label="状态" width="90" align="center">
          <template #default="{ row }">
            <el-tag :type="row.status === 'active' ? 'success' : 'info'" size="small">
              {{ row.status === 'active' ? '正常' : '已禁用' }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column prop="created_at" label="创建时间" width="160">
          <template #default="{ row }">{{ String(row.created_at).replace('T', ' ').slice(0, 19) }}</template>
        </el-table-column>
        <el-table-column label="操作" width="330" fixed="right" align="center">
          <template #default="{ row }">
            <template v-if="row.role?.code !== 'superadmin'">
              <el-button v-perm="'btn:admin:manage'" size="small" type="primary" plain @click="openEdit(row)">改角色</el-button>
              <el-button v-perm="'btn:admin:manage'" size="small" plain @click="openPassword(row)">重置密码</el-button>
              <el-button v-perm="'btn:admin:manage'" size="small" type="warning" plain :disabled="!row.totp_bound" @click="resetTotp(row)">重置验证</el-button>
              <el-button
                v-perm="'btn:admin:manage'"
                size="small"
                :type="row.status === 'active' ? 'info' : 'success'"
                plain
                :disabled="row.id === userStore.info?.id"
                @click="toggleStatus(row)"
              >{{ row.status === 'active' ? '禁用' : '启用' }}</el-button>
              <el-button
                v-perm="'btn:admin:manage'"
                size="small"
                type="danger"
                plain
                :disabled="row.id === userStore.info?.id"
                @click="remove(row)"
              >删除</el-button>
            </template>
            <span v-else style="color: #909399; font-size: 12px">超级管理员</span>
          </template>
        </el-table-column>
      </el-table>
    </el-card>

    <el-dialog
      v-model="dialogVisible"
      :title="dialogMode === 'create' ? '新建管理员' : dialogMode === 'edit' ? '修改角色' : '重置密码'"
      width="420px"
    >
      <el-form label-width="80px">
        <el-form-item v-if="dialogMode === 'create'" label="用户名">
          <el-input v-model="form.username" placeholder="登录用户名 (字母/数字/下划线)" maxlength="32" />
        </el-form-item>
        <el-form-item v-if="dialogMode !== 'edit'" label="密码">
          <el-input
            v-model="form.password"
            type="password"
            show-password
            :placeholder="dialogMode === 'create' ? '初始密码 (至少 8 位)' : '新密码 (至少 8 位)'"
            maxlength="64"
          />
        </el-form-item>
        <el-form-item v-if="dialogMode !== 'password'" label="角色">
          <el-select v-model="form.role_id" placeholder="选择角色" style="width: 100%">
            <el-option v-for="r in roles" :key="r.id" :value="r.id" :label="r.name" />
          </el-select>
        </el-form-item>
        <el-alert
          v-if="dialogMode === 'create'"
          type="info"
          :closable="false"
          title="创建后该管理员首次登录需绑定谷歌验证器, 之后每次登录都需动态码"
        />
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
