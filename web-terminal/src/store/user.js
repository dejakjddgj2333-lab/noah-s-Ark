import { defineStore } from 'pinia'
import { authApi } from '../api'

export const useUserStore = defineStore('user', {
  state: () => ({
    token: localStorage.getItem('mc_token') || '',
    user: JSON.parse(localStorage.getItem('mc_user') || 'null'),
  }),
  getters: {
    isLogin: (s) => !!s.token,
  },
  actions: {
    _save(token, user) {
      this.token = token
      this.user = user
      localStorage.setItem('mc_token', token)
      localStorage.setItem('mc_user', JSON.stringify(user))
    },
    async login(username, password) {
      const res = await authApi.login(username, password)
      this._save(res.token, res.user)
    },
    async register(data) {
      const res = await authApi.register(data)
      this._save(res.token, res.user)
    },
    async fetchMe() {
      this.user = await authApi.me()
      localStorage.setItem('mc_user', JSON.stringify(this.user))
    },
    logout() {
      this.token = ''
      this.user = null
      localStorage.removeItem('mc_token')
      localStorage.removeItem('mc_user')
    },
  },
})
