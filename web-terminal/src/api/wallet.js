import api from './request'

// 充值 / 提现 / 账户余额
export const walletApi = {
  // 双账户余额 (principal / income)
  account: () => api.get('/deposit/account'),
  // 充值地址
  address: (network) => api.get('/deposit/address', { params: { network } }),
  // 充值记录
  depositRecords: () => api.get('/deposit/records'),
  // 链上已转未到账补单
  claim: (txid, network) => api.post('/deposit/claim', { txid, network }),
  // 提现网络列表
  withdrawNetworks: () => api.get('/withdrawals/networks'),
  // 提现费用试算
  quote: (params) => api.get('/withdrawals/quote', { params }),
  // 发起提现
  withdraw: (data) => api.post('/withdrawals', data),
  // 提现记录
  withdrawalRecords: () => api.get('/withdrawals'),
}
