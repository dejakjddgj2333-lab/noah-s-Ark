import request from './request'

// 购买订单 (管理员): 列表带每单已产生收益聚合
export function getAdminOrders(params) {
  return request.get('/admin/orders', { params })
}

// 某订单逐期收益结算明细 + 触发的佣金流水
export function getAdminOrderSettlements(id) {
  return request.get(`/admin/orders/${id}/settlements`)
}
