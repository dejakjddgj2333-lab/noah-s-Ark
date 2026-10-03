import { createRouter, createWebHistory } from 'vue-router'
import Layout from '@/layout/index.vue'

const routes = [
  {
    path: '/login',
    name: 'Login',
    component: () => import('@/views/login/index.vue'),
    meta: { title: '登录' },
  },
  {
    path: '/',
    component: Layout,
    redirect: '/dashboard',
    children: [
      {
        path: 'dashboard',
        name: 'Dashboard',
        component: () => import('@/views/dashboard/index.vue'),
        meta: { title: '仪表盘', icon: 'Odometer' },
      },
      {
        path: 'users',
        name: 'UserList',
        component: () => import('@/views/user/list.vue'),
        meta: { title: '用户管理', icon: 'User' },
      },
      {
        path: 'deposit/records',
        name: 'DepositRecords',
        component: () => import('@/views/deposit/records.vue'),
        meta: { title: '充值记录', icon: 'Money' },
      },
      {
        path: 'deposit/addresses',
        name: 'DepositAddresses',
        component: () => import('@/views/deposit/addresses.vue'),
        meta: { title: '充值地址池', icon: 'Key' },
      },
      {
        path: 'product/list',
        name: 'ProductList',
        component: () => import('@/views/product/list.vue'),
        meta: { title: '产品管理', icon: 'Goods' },
      },
      {
        path: 'manage/users',
        name: 'ManageUsers',
        component: () => import('@/views/manage/users.vue'),
        meta: { title: '用户档案', icon: 'Files' },
      },
      {
        path: 'withdrawal/list',
        name: 'WithdrawalList',
        component: () => import('@/views/withdrawal/list.vue'),
        meta: { title: '提现审核', icon: 'Wallet' },
      },
      {
        path: 'settings',
        name: 'Settings',
        component: () => import('@/views/settings/index.vue'),
        meta: { title: '系统设置', icon: 'Setting' },
      },
    ],
  },
  {
    path: '/:pathMatch(.*)*',
    name: 'NotFound',
    component: () => import('@/views/error/404.vue'),
    meta: { title: '页面不存在' },
  },
]

const router = createRouter({
  history: createWebHistory(),
  routes,
})

export default router
