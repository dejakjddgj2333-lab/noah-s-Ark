// 自选列表: localStorage 即时读写 + 服务器同步 (登录态下多端一致)
// 页面 onMounted 调一次 syncWatchlist() 拉服务器数据合并; 星标切换先改本地再后台同步
import { watchlistApi } from '../api'

const KEY = 'watchlist'
let syncing = null // 进行中的同步 Promise, 防并发重复拉

function save(list) {
  try {
    localStorage.setItem(KEY, JSON.stringify(list))
  } catch { /* 静默降级 */ }
}

export function getWatchlist() {
  try {
    const v = JSON.parse(localStorage.getItem(KEY) || '[]')
    return Array.isArray(v) ? v.filter((x) => typeof x === 'string') : []
  } catch {
    return []
  }
}

export function inWatchlist(instId) {
  return getWatchlist().includes(instId)
}

// 切换并返回最新数组 (本地先行, 服务器后台同步, 失败下轮 sync 会修正)
export function toggleWatchlist(instId) {
  const list = getWatchlist()
  const i = list.indexOf(instId)
  if (i >= 0) list.splice(i, 1)
  else list.push(instId)
  save(list)
  const call = i >= 0 ? watchlistApi.remove(instId) : watchlistApi.add(instId)
  call.catch(() => { /* 离线/未登录静默, 下次 sync 对齐 */ })
  return list
}

// 服务器为准合并: 服务器有 -> 覆盖本地; 本地多出的补传服务器 (历史本地数据迁移)
export function syncWatchlist() {
  if (syncing) return syncing
  syncing = (async () => {
    try {
      const res = await watchlistApi.list()
      const server = Array.isArray(res?.items) ? res.items : []
      const local = getWatchlist()
      const missing = local.filter((x) => !server.includes(x))
      if (missing.length) {
        await Promise.allSettled(missing.map((x) => watchlistApi.add(x)))
      }
      const merged = [...server, ...missing]
      save(merged)
      return merged
    } catch {
      return getWatchlist()
    } finally {
      syncing = null
    }
  })()
  return syncing
}
