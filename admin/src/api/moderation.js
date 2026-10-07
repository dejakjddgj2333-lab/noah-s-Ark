import request from './request'

// 功能开关
export function getConfigs() { return request.get('/admin/config') }
export function updateConfig(key, value) { return request.put(`/admin/config/${key}`, { value }) }

// 举报管理
export function getReports(params) { return request.get('/admin/reports', { params }) }
export function handleReport(id, data) { return request.post(`/admin/reports/${id}/handle`, data) }
