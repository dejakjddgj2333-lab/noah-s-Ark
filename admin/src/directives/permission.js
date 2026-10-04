import { useUserStore } from '@/store/user'

/** v-perm="'btn:user:freeze'": 无权限直接移除元素 (按钮级权限). */
export default {
  mounted(el, binding) {
    const userStore = useUserStore()
    if (binding.value && !userStore.hasPerm(binding.value)) {
      el.parentNode?.removeChild(el)
    }
  },
}
