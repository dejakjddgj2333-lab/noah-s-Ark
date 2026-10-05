import axios from 'axios'
import { ElMessage } from 'element-plus'
import router from '@/router'
import { useUserStore } from '@/store/user'

const request = axios.create({
  // 本地开发走 vite 代理 (/api → localhost:8000); 打包部署显式指向正式 API
  baseURL: import.meta.env.DEV ? '/api' : 'http://shipapi.bdxapi.com/api',
  timeout: 10000,
})

// 请求拦截：自动带上 token
request.interceptors.request.use(
  (config) => {
    const userStore = useUserStore()
    if (userStore.token) {
      config.headers.Authorization = `Bearer ${userStore.token}`
    }
    return config
  },
  (error) => Promise.reject(error),
)

// 响应拦截：统一处理错误与 401
request.interceptors.response.use(
  (response) => response.data,
  (error) => {
    const status = error.response?.status
    const message = error.response?.data?.message || error.message || '请求失败'

    if (status === 401) {
      const userStore = useUserStore()
      userStore.logout()
      router.push('/login')
    }
    ElMessage.error(message)
    return Promise.reject(error)
  },
)

export default request
