import request from './request'

// 充值后台管理接口
export function getDepositStats() {
  return request.get('/admin/deposit/stats')
}

export function getDepositRecords(params) {
  return request.get('/admin/deposit/records', { params })
}

export function getDepositAddresses(params) {
  return request.get('/admin/deposit/addresses', { params })
}

export function generateDepositAddresses(data) {
  return request.post('/admin/deposit/addresses/generate', data)
}
