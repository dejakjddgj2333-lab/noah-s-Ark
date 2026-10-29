import axios from 'axios'

// 真实后端; 开发环境走 vite 代理 /api -> shipapi.bdxapi.com; 生产直连后端 (同 admin)
const api = axios.create({
  baseURL: import.meta.env.VITE_API_BASE || (import.meta.env.DEV ? '/api' : 'https://shipapi.bdxapi.com/api'),
  timeout: 15000,
})

api.interceptors.request.use((cfg) => {
  const t = localStorage.getItem('mc_token')
  if (t) cfg.headers.Authorization = `Bearer ${t}`
  return cfg
})

api.interceptors.response.use(
  (res) => res.data,
  (err) => {
    if (err.response?.status === 401) {
      localStorage.removeItem('mc_token')
      localStorage.removeItem('mc_user')
      if (location.pathname !== '/login') location.href = '/login'
    }
    const msg = err.response?.data?.detail || err.message || '网络错误'
    return Promise.reject(new Error(typeof msg === 'string' ? msg : JSON.stringify(msg)))
  }
)

export default api
