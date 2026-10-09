import router from '@/router'
import { useUserStore } from '@/store/user'

const WHITE_LIST = ['/login']

router.beforeEach(async (to) => {
  const userStore = useUserStore()

  document.title = to.meta.title
    ? `${to.meta.title} - Noah's Ark 后台`
    : "Noah's Ark 后台"

  if (userStore.isLoggedIn) {
    if (to.path === '/login') return '/dashboard'
    // 未绑谷歌验证的管理员只许停留在绑定页
    if (userStore.needTotp && to.path !== '/bind-totp') return '/bind-totp'
    // 页面权限: 无权限码进不了 (菜单已过滤, 这里防手敲 URL)
    if (to.meta.perm && !userStore.hasPerm(to.meta.perm)) return '/404'
    return true
  }

  if (WHITE_LIST.includes(to.path)) return true
  return `/login?redirect=${encodeURIComponent(to.fullPath)}`
})
