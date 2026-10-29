import api from './request'

// ---------- 认证 ----------
export const authApi = {
  login: (username, password) =>
    api.post('/auth/login', { username, password, device_name: 'Web 终端', platform: 'web' }),
  register: (data) => api.post('/auth/register', data),
  sendEmailCode: (email, purpose = 'register') => api.post('/auth/send-email-code', { email, purpose }),
  resetPassword: (email, code, new_password) =>
    api.post('/auth/reset-password', { email, code, new_password }),
  me: () => api.get('/auth/me'),
  changePassword: (old_password, new_password) =>
    api.post('/auth/change-password', { old_password, new_password }),
  devices: () => api.get('/auth/devices'),
}

// ---------- 行情 (OKX 代理, 透传 {code, data}) ----------
export const marketApi = {
  tickers: (instType = 'SPOT') => api.get('/market/tickers', { params: { inst_type: instType } }),
  ticker: (instId) => api.get(`/market/ticker/${instId}`),
  candles: (instId, bar = '1H', limit = 100) =>
    api.get(`/market/candles/${instId}`, { params: { bar, limit } }),
  books: (instId, sz = 20) => api.get(`/market/books/${instId}`, { params: { sz } }),
  trades: (instId, limit = 60) => api.get(`/market/trades/${instId}`, { params: { limit } }),
  fundingRate: (instId) => api.get(`/market/funding-rate/${instId}`),
}

// ---------- 市场总览 ----------
export const overviewApi = {
  source: () => api.get('/market-overview/source'),
  globalStats: () => api.get('/market-overview/global-stats'),
  sentiment: () => api.get('/market-overview/sentiment'),
  liquidity: () => api.get('/market-overview/liquidity'),
  longShortRatio: (symbol = 'BTC') =>
    api.get('/market-overview/long-short-ratio', { params: { symbol } }),
  indicators: () => api.get('/market-overview/indicators'),
  openInterest: () => api.get('/market-overview/open-interest'),
  liqExchangeList: (range = '24h') =>
    api.get('/market-overview/liquidations/exchange-list', { params: { range } }),
  liqRecent: (limit = 50) =>
    api.get('/market-overview/liquidations/recent', { params: { limit } }),
  liqOrders: (minAmount = 100000, limit = 50) =>
    api.get('/market-overview/liquidations/orders', { params: { min_amount: minAmount, limit } }),
  liqCoinList: () => api.get('/market-overview/liquidations/coin-list'),
  fundingExchangeRates: (symbol = 'BTC') =>
    api.get('/market-overview/funding/exchange-rates', { params: { symbol } }),
  fundingHistory: (symbol = 'BTC') =>
    api.get('/market-overview/funding/history', { params: { symbol } }),
  whaleAlerts: () => api.get('/market-overview/whale-alerts'),
  whaleStatus: () => api.get('/market-overview/whale-status'),
}

// ---------- 资讯 ----------
export const newsApi = {
  list: (params = {}) => api.get('/news', { params }),
  detail: (id) => api.get(`/news/${id}`),
  macroCalendar: (params = {}) => api.get('/news/macro-calendar', { params }),
}

// ---------- 互动 (点赞/收藏/评论) ----------
export const interactionApi = {
  like: (target_type, target_id) => api.post('/interaction/like', { target_type, target_id }),
  favorite: (target_type, target_id) => api.post('/interaction/favorite', { target_type, target_id }),
  state: (target_type, target_ids) => api.get('/interaction/state', { params: { target_type, target_ids } }),
  comments: (target_type, target_id) => api.get('/interaction/comments', { params: { target_type, target_id } }),
  addComment: (data) => api.post('/interaction/comments', data),
}

// ---------- 聊天 ----------
export const chatApi = {
  conversations: () => api.get('/chat/conversations'),
  messages: (conversationId, params = {}) =>
    api.get(`/chat/conversations/${conversationId}/messages`, { params }),
  sendMessage: (conversationId, data) =>
    api.post(`/chat/conversations/${conversationId}/messages`, data),
  // 已读游标只增不减, 必须传 message_id
  markRead: (conversationId, messageId) =>
    api.post(`/chat/conversations/${conversationId}/read`, { message_id: messageId }),
  // 单聊对方已读游标; 群聊返回 {peer_last_read_message_id: null}
  peerReadState: (conversationId) =>
    api.get(`/chat/conversations/${conversationId}/read-state`),
  members: (conversationId) => api.get(`/chat/conversations/${conversationId}/members`),
  friendsOnline: () => api.get('/chat/friends/online'),
}

// ---------- 理财产品 ----------
export const productApi = {
  list: () => api.get('/products'),
  detail: (id) => api.get(`/products/${id}`),
}

// ---------- 订单 (申购) ----------
export const orderApi = {
  list: (params = {}) => api.get('/orders', { params }),
  create: (data) => api.post('/orders', data),
}

// ---------- 邀请 / 结算 ----------
export const inviteApi = {
  me: () => api.get('/invite/me'),
}
export const settlementApi = {
  // settlements router 无 prefix, 真实路径如下 (旧 /settlements/... 全 404)
  commissionsSummary: () => api.get('/commissions/summary'),
  commissions: (params = {}) => api.get('/commissions', { params }),
  accountLogs: (params = {}) => api.get('/account/logs', { params }),
}

// ---------- 账户 (双账户余额 / 收益转本金) ----------
export const accountApi = {
  depositAccount: () => api.get('/deposit/account'),
  convertQuote: (params) => api.get('/account/convert/quote', { params }),
  convert: (data) => api.post('/account/convert', data),
}

// ---------- VIP ----------
export const vipApi = {
  me: () => api.get('/vip/me'),
}
