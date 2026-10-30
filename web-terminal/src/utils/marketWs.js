// 行情 WS 客户端 (免鉴权): 单连接复用, 断线指数退避重连, 重连后自动重订阅
// 后端: /api/market/ws -> OKX 公共频道中转 (tickers / books5 / trades)

let ws = null
let reconnectTimer = null
let reconnectDelay = 1000
const subs = new Map() // "channel:instId" -> Set<cb>

function wsUrl() {
  if (import.meta.env.DEV) {
    // dev 走 vite 代理 (/api -> 后端, 已开 ws:true)
    const proto = location.protocol === 'https:' ? 'wss' : 'ws'
    return `${proto}://${location.host}/api/market/ws`
  }
  return 'wss://shipapi.bdxapi.com/api/market/ws'
}

export function marketWsAlive() {
  return !!ws && ws.readyState === WebSocket.OPEN
}

function send(obj) {
  if (marketWsAlive()) ws.send(JSON.stringify(obj))
}

function connect() {
  if (!subs.size) return
  if (ws && (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING)) return
  ws = new WebSocket(wsUrl())
  ws.onopen = () => {
    reconnectDelay = 1000
    // 重连后全量重订阅
    const args = [...subs.keys()].map((k) => {
      const [channel, instId] = k.split(':')
      return { channel, instId }
    })
    for (let i = 0; i < args.length; i += 10) {
      send({ op: 'subscribe', args: args.slice(i, i + 10) })
    }
  }
  ws.onmessage = (e) => {
    let frame
    try { frame = JSON.parse(e.data) } catch { return }
    const arg = frame?.arg
    if (!arg?.channel || !arg?.instId) return
    const cbs = subs.get(`${arg.channel}:${arg.instId}`)
    if (!cbs) return
    cbs.forEach((cb) => {
      try { cb(frame) } catch { /* 单回调异常不影响其他 */ }
    })
  }
  ws.onclose = () => {
    ws = null
    if (!subs.size || reconnectTimer) return
    reconnectTimer = setTimeout(() => {
      reconnectTimer = null
      reconnectDelay = Math.min(reconnectDelay * 2, 30000)
      connect()
    }, reconnectDelay)
  }
  ws.onerror = () => { /* onclose 统一处理重连 */ }
}

// 订阅 OKX 公共频道, 返回退订函数
export function subscribeMarket(channel, instId, cb) {
  const key = `${channel}:${instId}`
  let set = subs.get(key)
  if (!set) {
    set = new Set()
    subs.set(key, set)
    connect()
    send({ op: 'subscribe', args: [{ channel, instId }] })
  }
  set.add(cb)
  return () => {
    const s = subs.get(key)
    if (!s) return
    s.delete(cb)
    if (!s.size) {
      subs.delete(key)
      send({ op: 'unsubscribe', args: [{ channel, instId }] })
    }
  }
}
