// 自选列表 (localStorage, key: watchlist, 存 instId 数组)
const KEY = 'watchlist'

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

// 切换并返回最新数组
export function toggleWatchlist(instId) {
  const list = getWatchlist()
  const i = list.indexOf(instId)
  if (i >= 0) list.splice(i, 1)
  else list.push(instId)
  try {
    localStorage.setItem(KEY, JSON.stringify(list))
  } catch { /* 静默降级 */ }
  return list
}
