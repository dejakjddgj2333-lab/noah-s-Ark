// 聊天 WebSocket 单例客户端: JWT 鉴权 / 25s 心跳 / 指数退避重连 / 事件订阅
// 后端: /api/chat/ws?token=JWT, 服务端每 25s 推 {type:"ping"}, 入站仅中继通话信令, 其余帧忽略

let ws = null
let manualClose = false
let heartbeatTimer = null
let reconnectTimer = null
let reconnectDelay = 1000
const listeners = new Map() // type -> Set<cb>

function wsUrl() {
  const token = localStorage.getItem('mc_token') || ''
  if (import.meta.env.DEV) {
    // dev 走 vite 代理 (/api -> 后端, 已开 ws:true)
    const proto = location.protocol === 'https:' ? 'wss' : 'ws'
    return `${proto}://${location.host}/api/chat/ws?token=${encodeURIComponent(token)}`
  }
  return `wss://shipapi.bdxapi.com/api/chat/ws?token=${encodeURIComponent(token)}`
}

function stopHeartbeat() {
  if (heartbeatTimer) {
    clearInterval(heartbeatTimer)
    heartbeatTimer = null
  }
}

function scheduleReconnect() {
  if (reconnectTimer || manualClose) return
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null
    reconnectDelay = Math.min(reconnectDelay * 2, 30000) // 指数退避, 上限 30s
    connect()
  }, reconnectDelay)
}

function connect() {
  const token = localStorage.getItem('mc_token')
  if (!token) return
  if (ws && (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING)) return
  manualClose = false
  try {
    ws = new WebSocket(wsUrl())
  } catch {
    scheduleReconnect()
    return
  }
  ws.onopen = () => {
    reconnectDelay = 1000 // 连上后重置退避
    stopHeartbeat()
    heartbeatTimer = setInterval(() => {
      if (ws && ws.readyState === WebSocket.OPEN) ws.send('ping') // 服务端忽略非 JSON 帧
    }, 25000)
  }
  ws.onmessage = (ev) => {
    let data
    try {
      data = JSON.parse(ev.data)
    } catch {
      return
    }
    if (!data || typeof data.type !== 'string') return
    const cbs = listeners.get(data.type)
    if (cbs) {
      cbs.forEach((cb) => {
        try {
          cb(data)
        } catch {
          /* 单个订阅者异常不影响其他 */
        }
      })
    }
  }
  ws.onclose = () => {
    ws = null
    stopHeartbeat()
    if (!manualClose && localStorage.getItem('mc_token')) scheduleReconnect()
  }
  ws.onerror = () => {
    if (ws) ws.close()
  }
}

export const chatWs = {
  connect,
  disconnect() {
    manualClose = true
    if (reconnectTimer) {
      clearTimeout(reconnectTimer)
      reconnectTimer = null
    }
    stopHeartbeat()
    if (ws) {
      ws.close()
      ws = null
    }
  },
  // 订阅事件; 有订阅即确保连接已建立
  on(type, cb) {
    if (!listeners.has(type)) listeners.set(type, new Set())
    listeners.get(type).add(cb)
    connect()
  },
  off(type, cb) {
    const set = listeners.get(type)
    if (set) set.delete(cb)
  },
}
