import { defineStore } from 'pinia'
import request from '@/api/request'

export const useUserStore = defineStore('user', {
  state: () => ({
    token: localStorage.getItem('admin_token') || '',
    info: JSON.parse(localStorage.getItem('admin_info') || 'null'),
    perms: JSON.parse(localStorage.getItem('admin_perms') || '[]'),
    role: JSON.parse(localStorage.getItem('admin_role') || 'null'),
  }),
  getters: {
    isLoggedIn: (state) => Boolean(state.token),
    /** 是否有权限码; ['*'] 超管全通 */
    hasPerm: (state) => (code) =>
      state.perms.includes('*') || state.perms.includes(code),
  },
  actions: {
    setToken(token) {
      this.token = token
      localStorage.setItem('admin_token', token)
    },
    setInfo(info) {
      this.info = info
      localStorage.setItem('admin_info', JSON.stringify(info))
    },
    /** 登录后拉取权限 (角色/权限码) 并缓存 */
    async fetchMe() {
      const res = await request.get('/admin/me')
      this.info = res.user
      this.perms = res.perms || []
      this.role = res.role
      localStorage.setItem('admin_info', JSON.stringify(res.user))
      localStorage.setItem('admin_perms', JSON.stringify(this.perms))
      localStorage.setItem('admin_role', JSON.stringify(res.role))
      return res
    },
    logout() {
      this.token = ''
      this.info = null
      this.perms = []
      this.role = null
      localStorage.removeItem('admin_token')
      localStorage.removeItem('admin_info')
      localStorage.removeItem('admin_perms')
      localStorage.removeItem('admin_role')
    },
  },
})
