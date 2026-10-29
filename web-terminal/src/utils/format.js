// 数字与时间格式化工具

export function fmtNum(v, digits = 2) {
  if (v === null || v === undefined || isNaN(Number(v))) return '--'
  return Number(v).toLocaleString('en-US', {
    minimumFractionDigits: digits,
    maximumFractionDigits: digits,
  })
}

// 大额缩写: 1.24B / 284.6M / 38.4K
export function fmtBig(v, digits = 2) {
  if (v === null || v === undefined || isNaN(Number(v))) return '--'
  const n = Number(v)
  const abs = Math.abs(n)
  if (abs >= 1e12) return (n / 1e12).toFixed(digits) + 'T'
  if (abs >= 1e9) return (n / 1e9).toFixed(digits) + 'B'
  if (abs >= 1e6) return (n / 1e6).toFixed(digits) + 'M'
  if (abs >= 1e3) return (n / 1e3).toFixed(digits) + 'K'
  return n.toFixed(digits)
}

export function fmtUsd(v, digits = 2) {
  if (v === null || v === undefined || isNaN(Number(v))) return '--'
  return '$' + fmtBig(v, digits)
}

export function fmtPct(v, digits = 2, sign = true) {
  if (v === null || v === undefined || isNaN(Number(v))) return '--'
  const n = Number(v)
  const s = sign && n > 0 ? '+' : ''
  return `${s}${n.toFixed(digits)}%`
}

// 自适应价格位数
export function fmtPrice(v) {
  if (v === null || v === undefined || isNaN(Number(v))) return '--'
  const n = Number(v)
  if (n >= 1000) return fmtNum(n, 2)
  if (n >= 1) return fmtNum(n, 4)
  if (n >= 0.01) return fmtNum(n, 5)
  return n.toPrecision(4)
}

export function cls(v) {
  const n = Number(v)
  if (isNaN(n) || n === 0) return ''
  return n > 0 ? 'up' : 'down'
}

export function fmtTime(ts) {
  if (!ts) return '--'
  const d = new Date(Number(ts))
  const p = (x) => String(x).padStart(2, '0')
  return `${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`
}

export function fmtDateTime(ts) {
  if (!ts) return '--'
  const d = new Date(Number(ts))
  const p = (x) => String(x).padStart(2, '0')
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`
}

export function fmtAgo(ts) {
  if (!ts) return '--'
  const diff = Date.now() - Number(ts)
  const m = Math.floor(diff / 60000)
  if (m < 1) return '刚刚'
  if (m < 60) return `${m} 分钟前`
  const h = Math.floor(m / 60)
  if (h < 24) return `${h} 小时前`
  return `${Math.floor(h / 24)} 天前`
}

// 兼容 "YYYY-MM-DD HH:mm:ss" 裸值 (后端北京时间) 与毫秒时间戳
export function ts(v) {
  if (!v) return null
  if (typeof v === 'number') return v
  const t = new Date(String(v).replace(' ', 'T')).getTime()
  return isNaN(t) ? null : t
}

// BTC-USDT / BTCUSDT -> BTC
export function coinOf(instId = '') {
  return instId.replace(/-USDT?/i, '').replace(/USDT?$/i, '')
}
