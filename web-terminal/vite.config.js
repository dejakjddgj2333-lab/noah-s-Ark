import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  plugins: [vue()],
  server: {
    port: 5520,
    proxy: {
      '/api': {
        target: 'http://shipapi.bdxapi.com',
        changeOrigin: true,
        ws: true, // 聊天 WebSocket 走同一代理
      },
    },
  },
})
