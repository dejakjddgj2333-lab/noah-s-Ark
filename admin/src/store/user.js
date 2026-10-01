import { defineStore } from 'pinia'

export const useUserStore = defineStore('user', {
  state: () => ({
    token: localStorage.getItem('admin_token') || '',
    info: JSON.parse(localStorage.getItem('admin_info') || 'null'),
  }),
  getters: {
    isLoggedIn: (state) => Boolean(state.token),
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
    logout() {
      this.token = ''
      this.info = null
      localStorage.removeItem('admin_token')
      localStorage.removeItem('admin_info')
    },
  },
})
