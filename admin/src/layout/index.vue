<script setup>
import { computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useUserStore } from '@/store/user'

const route = useRoute()
const router = useRouter()
const userStore = useUserStore()

const activeMenu = computed(() => route.path)

const GROUP_ORDER = ['概览', '用户', '资金', '运营', '系统']

const menuGroups = computed(() => {
  const root = router.options.routes.find((r) => r.path === '/')
  const items = (root?.children || []).filter(
    (r) => r.meta?.title && (!r.meta.perm || userStore.hasPerm(r.meta.perm)),
  )
  const groups = new Map()
  for (const item of items) {
    const g = item.meta?.group || '其他'
    if (!groups.has(g)) groups.set(g, [])
    groups.get(g).push(item)
  }
  return GROUP_ORDER.filter((g) => groups.has(g)).map((g) => ({
    title: g,
    items: groups.get(g),
  }))
})

function handleLogout() {
  userStore.logout()
  router.push('/login')
}
</script>

<template>
  <el-container class="layout-container">
    <!-- 侧边栏 -->
    <el-aside :width="'var(--app-sidebar-width)'" class="layout-sidebar">
      <div class="layout-logo">
        <div class="logo-mark">NA</div>
        <div class="logo-text">
          <div class="logo-name">Noah's Ark</div>
          <div class="logo-sub">运营后台</div>
        </div>
      </div>
      <el-menu
        :default-active="activeMenu"
        class="sidebar-menu"
        background-color="transparent"
        text-color="rgba(255, 255, 255, 0.65)"
        active-text-color="#ffffff"
        router
      >
        <el-menu-item-group v-for="group in menuGroups" :key="group.title">
          <template #title>
            <span class="menu-group-title">{{ group.title }}</span>
          </template>
          <el-menu-item v-for="item in group.items" :key="item.path" :index="'/' + item.path">
            <el-icon><component :is="item.meta.icon" /></el-icon>
            <span>{{ item.meta.title }}</span>
          </el-menu-item>
        </el-menu-item-group>
      </el-menu>
    </el-aside>

    <el-container>
      <!-- 顶栏 -->
      <el-header class="layout-header">
        <el-breadcrumb separator="/">
          <el-breadcrumb-item :to="{ path: '/dashboard' }">首页</el-breadcrumb-item>
          <el-breadcrumb-item v-if="route.meta.title && route.path !== '/dashboard'">
            {{ route.meta.title }}
          </el-breadcrumb-item>
        </el-breadcrumb>

        <el-dropdown @command="handleLogout">
          <span class="layout-user">
            <span class="user-avatar">{{ (userStore.info?.username || 'A')[0].toUpperCase() }}</span>
            {{ userStore.info?.nickname || userStore.info?.username || '管理员' }}
            <el-tag v-if="userStore.role" size="small" effect="dark" class="role-tag">
              {{ userStore.role.name }}
            </el-tag>
            <el-icon><ArrowDown /></el-icon>
          </span>
          <template #dropdown>
            <el-dropdown-menu>
              <el-dropdown-item command="logout">退出登录</el-dropdown-item>
            </el-dropdown-menu>
          </template>
        </el-dropdown>
      </el-header>

      <!-- 主内容 -->
      <el-main class="app-main">
        <router-view v-slot="{ Component }">
          <transition name="fade-slide" mode="out-in">
            <component :is="Component" />
          </transition>
        </router-view>
      </el-main>
    </el-container>
  </el-container>
</template>

<style scoped>
.layout-container {
  height: 100%;
}

.layout-sidebar {
  background: linear-gradient(180deg, #0d1220 0%, #080b14 100%);
  border-right: 1px solid rgba(255, 255, 255, 0.06);
}

.layout-logo {
  height: var(--app-header-height);
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 0 16px;
}

.logo-mark {
  width: 32px;
  height: 32px;
  border-radius: 8px;
  background: linear-gradient(135deg, #4c6fff, #8a5cff);
  color: #fff;
  font-size: 13px;
  font-weight: 700;
  display: flex;
  align-items: center;
  justify-content: center;
  box-shadow: 0 4px 12px rgba(76, 111, 255, 0.45);
}

.logo-text .logo-name {
  color: #fff;
  font-size: 14px;
  font-weight: 600;
  line-height: 1.2;
}

.logo-text .logo-sub {
  color: rgba(255, 255, 255, 0.45);
  font-size: 11px;
}

.sidebar-menu {
  border-right: none;
  padding: 8px;
}

.sidebar-menu :deep(.el-menu-item) {
  border-radius: 8px;
  margin-bottom: 4px;
  height: 42px;
  line-height: 42px;
}

.sidebar-menu :deep(.el-menu-item:hover) {
  background: rgba(255, 255, 255, 0.06);
}

.sidebar-menu :deep(.el-menu-item.is-active) {
  background: linear-gradient(90deg, rgba(76, 111, 255, 0.85), rgba(138, 92, 255, 0.65));
  box-shadow: 0 4px 12px rgba(76, 111, 255, 0.35);
}

.sidebar-menu :deep(.el-menu-item-group__title) {
  padding: 14px 8px 4px;
}

.menu-group-title {
  font-size: 11px;
  letter-spacing: 2px;
  color: rgba(255, 255, 255, 0.35);
}

.layout-header {
  height: var(--app-header-height);
  display: flex;
  align-items: center;
  justify-content: space-between;
  background: rgba(11, 14, 20, 0.85);
  backdrop-filter: blur(12px);
  border-bottom: 1px solid rgba(255, 255, 255, 0.07);
  position: sticky;
  top: 0;
  z-index: 10;
}

.layout-user {
  display: flex;
  align-items: center;
  gap: 8px;
  cursor: pointer;
  color: #e8eaf0;
}

.user-avatar {
  width: 28px;
  height: 28px;
  border-radius: 50%;
  background: linear-gradient(135deg, #4c6fff, #8a5cff);
  color: #fff;
  font-size: 13px;
  font-weight: 600;
  display: flex;
  align-items: center;
  justify-content: center;
}

.role-tag {
  background: linear-gradient(90deg, #4c6fff, #8a5cff);
  border: none;
}
</style>
