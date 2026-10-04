import { createRouter, createWebHistory } from 'vue-router'
import Layout from '@/layout/index.vue'

// meta.perm = 页面权限码 (page:*), 守卫按此拦截, 菜单按此过滤
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
        meta: { title: '仪表盘', icon: 'Odometer', perm: 'page:dashboard' },
      },
      {
        path: 'users',
        name: 'UserList',
        component: () => import('@/views/manage/users.vue'),
        meta: { title: '用户管理', icon: 'User', perm: 'page:users' },
      },
      {
        path: 'deposit/records',
        name: 'DepositRecords',
        component: () => import('@/views/deposit/records.vue'),
        meta: { title: '充值记录', icon: 'Money', perm: 'page:deposit-records' },
      },
      {
        path: 'deposit/addresses',
        name: 'DepositAddresses',
        component: () => import('@/views/deposit/addresses.vue'),
        meta: { title: '充值地址池', icon: 'Key', perm: 'page:deposit-pool' },
      },
      {
        path: 'sweep',
        name: 'Sweep',
        component: () => import('@/views/sweep/index.vue'),
        meta: { title: '资金归集', icon: 'Coin', perm: 'page:sweep' },
      },
      {
        path: 'product/list',
        name: 'ProductList',
        component: () => import('@/views/product/list.vue'),
        meta: { title: '产品管理', icon: 'Goods', perm: 'page:products' },
      },
      {
        path: 'withdrawal/list',
        name: 'WithdrawalList',
        component: () => import('@/views/withdrawal/list.vue'),
        meta: { title: '提现审核', icon: 'Wallet', perm: 'page:withdrawals' },
      },
      {
        path: 'admins',
        name: 'Admins',
        component: () => import('@/views/admin/admins.vue'),
        meta: { title: '管理员管理', icon: 'UserFilled', perm: 'page:admins' },
      },
      {
        path: 'roles',
        name: 'Roles',
        component: () => import('@/views/admin/roles.vue'),
        meta: { title: '角色权限', icon: 'Lock', perm: 'page:roles' },
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
