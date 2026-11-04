// 服务器时间为 UTC 裸值 (无时区后缀), 统一按 UTC 解析并转东八区显示
// 例: "2026-11-04T04:56:39" -> "2026-11-04 12:56:39"
export function fmtTime(t) {
  if (!t || t === 'None') return '-'
  const s = String(t).trim()
  if (!s) return '-'
  const iso = s.replace(' ', 'T')
  const hasTz = /(Z|[+-]\d{2}:?\d{2})$/.test(iso)
  const d = new Date(hasTz ? iso : iso + 'Z') // 无时区后缀按 UTC 处理
  if (Number.isNaN(d.getTime())) return s.slice(0, 19) // 解析失败回退原串
  const bj = new Date(d.getTime() + 8 * 3600e3)
  const p = (n) => String(n).padStart(2, '0')
  return `${bj.getUTCFullYear()}-${p(bj.getUTCMonth() + 1)}-${p(bj.getUTCDate())} ${p(bj.getUTCHours())}:${p(bj.getUTCMinutes())}:${p(bj.getUTCSeconds())}`
}
