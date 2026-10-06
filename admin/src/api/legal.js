import request from './request'

// 协议管理 (管理员): 隐私政策 / 用户协议
export function getLegalDocs() {
  return request.get('/admin/legal')
}

export function updateLegalDoc(key, data) {
  return request.put(`/admin/legal/${key}`, data)
}
