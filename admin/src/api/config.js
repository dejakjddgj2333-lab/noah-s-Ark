import request from './request'

// 参数配置 (管理员): 运营参数查看/保存, 保存即生效
export function getAdminConfig() {
  return request.get('/admin/params')
}

export function updateAdminConfig(updates) {
  return request.put('/admin/params', { updates })
}
