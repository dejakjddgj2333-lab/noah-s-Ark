<script setup>
import { computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useUserStore } from '@/store/user'

const route = useRoute()
const router = useRouter()
const userStore = useUserStore()

const activeMenu = computed(() => route.path)

const menuRoutes = computed(() => {
  const root = router.options.routes.find((r) => r.path === '/')
  return (root?.children || []).filter((r) => r.meta?.title)
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
      <div class="layout-logo">Noah's Ark 后台</div>
      <el-menu
        :default-active="activeMenu"
        background-color="#001529"
        text-color="#a6adb4"
        active-text-color="#ffffff"
        router
      >
        <el-menu-item v-for="item in menuRoutes" :key="item.path" :index="'/' + item.path">
          <el-icon><component :is="item.meta.icon" /></el-icon>
          <span>{{ item.meta.title }}</span>
        </el-menu-item>
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
            <el-icon><Avatar /></el-icon>
            {{ userStore.info?.username || '管理员' }}
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
        <router-view />
      </el-main>
    </el-container>
  </el-container>
</template>

<style scoped>
.layout-container {
  height: 100%;
}

.layout-sidebar {
  background-color: #001529;
}

.layout-logo {
  height: var(--app-header-height);
  line-height: var(--app-header-height);
  text-align: center;
  color: #fff;
  font-size: 16px;
  font-weight: 600;
}

.layout-sidebar .el-menu {
  border-right: none;
}

.layout-header {
  height: var(--app-header-height);
  display: flex;
  align-items: center;
  justify-content: space-between;
  background: #fff;
  border-bottom: 1px solid #e4e7ed;
}

.layout-user {
  display: flex;
  align-items: center;
  gap: 4px;
  cursor: pointer;
  color: #303133;
}
</style>
