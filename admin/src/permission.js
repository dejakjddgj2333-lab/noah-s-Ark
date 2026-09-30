import router from '@/router'
import { useUserStore } from '@/store/user'

const WHITE_LIST = ['/login']

router.beforeEach((to) => {
  const userStore = useUserStore()

  document.title = to.meta.title ? `${to.meta.title} - Noah's Ark 后台` : "Noah's Ark 后台"

  if (userStore.isLoggedIn) {
    if (to.path === '/login') return '/dashboard'
    return true
  }

  if (WHITE_LIST.includes(to.path)) return true
  return `/login?redirect=${encodeURIComponent(to.fullPath)}`
})
