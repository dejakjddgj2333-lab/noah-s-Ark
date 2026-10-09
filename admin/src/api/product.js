import request from './request'

// 产品后台管理接口
export function getAdminProducts(params) {
  return request.get('/admin/products', { params })
}

export function createProduct(data) {
  return request.post('/admin/products', data)
}

export function updateProduct(id, data) {
  return request.put(`/admin/products/${id}`, data)
}

export function publishProduct(id) {
  return request.post(`/admin/products/${id}/publish`)
}

export function offlineProduct(id) {
  return request.post(`/admin/products/${id}/offline`)
}

export function deleteProduct(id) {
  return request.delete(`/admin/products/${id}`)
}

// 用户档案查询 (管理员)
export function getAdminUsers(params) {
  return request.get('/admin/users', { params })
}

export function getAdminUserProfile(id) {
  return request.get(`/admin/users/${id}`)
}

export function deleteAdminUser(id) {
  return request.delete(`/admin/users/${id}`)
}

// 提现审核 (管理员)
export function getAdminWithdrawals(params) {
  return request.get('/admin/withdrawals', { params })
}

export function approveWithdrawal(id, data) {
  return request.post(`/admin/withdrawals/${id}/approve`, data)
}

export function rejectWithdrawal(id, data) {
  return request.post(`/admin/withdrawals/${id}/reject`, data)
}
