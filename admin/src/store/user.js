import { defineStore } from 'pinia'
import request from '@/api/request'

export const useUserStore = defineStore('user', {
  state: () => ({
    token: localStorage.getItem('admin_token') || '',
    info: JSON.parse(localStorage.getItem('admin_info') || 'null'),
    perms: JSON.parse(localStorage.getItem('admin_perms') || '[]'),
    role: JSON.parse(localStorage.getItem('admin_role') || 'null'),
    needTotpFlag: localStorage.getItem('admin_need_totp') === '1',
  }),
  getters: {
    isLoggedIn: (state) => Boolean(state.token),
    /** 是否有权限码; ['*'] 超管全通 */
    hasPerm: (state) => (code) =>
      state.perms.includes('*') || state.perms.includes(code),
    /** 是否需要先绑谷歌验证 (登录响应/管理员 me 返回 need_totp) */
    needTotp: (state) => state.needTotpFlag,
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
      this.needTotpFlag = Boolean(res.need_totp)
      localStorage.setItem('admin_info', JSON.stringify(res.user))
      localStorage.setItem('admin_perms', JSON.stringify(this.perms))
      localStorage.setItem('admin_role', JSON.stringify(res.role))
      localStorage.setItem('admin_need_totp', this.needTotpFlag ? '1' : '0')
      return res
    },
    setNeedTotp(v) {
      this.needTotpFlag = v
      localStorage.setItem('admin_need_totp', v ? '1' : '0')
    },
    logout() {
      this.token = ''
      this.info = null
      this.perms = []
      this.role = null
      this.needTotpFlag = false
      localStorage.removeItem('admin_token')
      localStorage.removeItem('admin_info')
      localStorage.removeItem('admin_perms')
      localStorage.removeItem('admin_role')
      localStorage.removeItem('admin_need_totp')
    },
  },
})
