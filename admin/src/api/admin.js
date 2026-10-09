import request from './request'

// ── 当前管理员 / 仪表盘 ──
export function getAdminMe() {
  return request.get('/admin/me')
}

export function getAdminStats() {
  return request.get('/admin/stats')
}

// ── 权限树 / 角色 ──
export function getPermissionTree() {
  return request.get('/admin/permissions')
}

export function getRoles() {
  return request.get('/admin/roles')
}

export function createRole(data) {
  return request.post('/admin/roles', data)
}

export function updateRole(id, data) {
  return request.put(`/admin/roles/${id}`, data)
}

export function deleteRole(id) {
  return request.delete(`/admin/roles/${id}`)
}

// ── 管理员管理 (独立账号体系) ──
export function getAdmins() {
  return request.get('/admin/admins')
}

export function createAdmin(data) {
  return request.post('/admin/admins', data)
}

export function updateAdmin(adminId, data) {
  return request.put(`/admin/admins/${adminId}`, data)
}

export function resetAdminTotp(adminId) {
  return request.post(`/admin/admins/${adminId}/reset-totp`)
}

export function removeAdmin(adminId) {
  return request.delete(`/admin/admins/${adminId}`)
}

// ── 用户操作 ──
export function freezeUser(id) {
  return request.post(`/admin/users/${id}/freeze`)
}

export function unfreezeUser(id) {
  return request.post(`/admin/users/${id}/unfreeze`)
}

export function adjustBalance(id, data) {
  return request.post(`/admin/users/${id}/adjust-balance`, data)
}

export function resetUserPassword(id, data) {
  return request.post(`/admin/users/${id}/reset-password`, data)
}

export function updateUser(id, data) {
  return request.post(`/admin/users/${id}/update`, data)
}

// ── 资金归集 ──
export function getSweepTargets() {
  return request.get('/admin/sweep/targets')
}

export function setSweepTarget(data) {
  return request.put('/admin/sweep/targets', data)
}

export function getSweepBalances(params) {
  return request.get('/admin/sweep/balances', { params })
}

export function runSweep(data) {
  return request.post('/admin/sweep/run', data)
}

export function getSweepRecords(params) {
  return request.get('/admin/sweep/records', { params })
}
