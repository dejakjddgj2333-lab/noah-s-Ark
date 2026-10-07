import { createRouter, createWebHistory } from 'vue-router'
import Layout from '@/layout/index.vue'

// meta.perm = 页面权限码 (page:*), 守卫按此拦截, 菜单按此过滤
// meta.group = 侧边栏分组 (layout 按此归类)
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
        meta: { title: '仪表盘', icon: 'Odometer', perm: 'page:dashboard', group: '概览' },
      },
      {
        path: 'users',
        name: 'UserList',
        component: () => import('@/views/manage/users.vue'),
        meta: { title: '用户管理', icon: 'User', perm: 'page:users', group: '用户' },
      },
      {
        path: 'deposit/records',
        name: 'DepositRecords',
        component: () => import('@/views/deposit/records.vue'),
        meta: { title: '充值记录', icon: 'Money', perm: 'page:deposit-records', group: '资金' },
      },
      {
        path: 'deposit/addresses',
        name: 'DepositAddresses',
        component: () => import('@/views/deposit/addresses.vue'),
        meta: { title: '充值地址池', icon: 'Key', perm: 'page:deposit-pool', group: '资金' },
      },
      {
        path: 'sweep',
        name: 'Sweep',
        component: () => import('@/views/sweep/index.vue'),
        meta: { title: '资金归集', icon: 'Coin', perm: 'page:sweep', group: '资金' },
      },
      {
        path: 'withdrawal/list',
        name: 'WithdrawalList',
        component: () => import('@/views/withdrawal/list.vue'),
        meta: { title: '提现审核', icon: 'Wallet', perm: 'page:withdrawals', group: '资金' },
      },
      {
        path: 'product/list',
        name: 'ProductList',
        component: () => import('@/views/product/list.vue'),
        meta: { title: '产品管理', icon: 'Goods', perm: 'page:products', group: '运营' },
      },
      {
        path: 'order/list',
        name: 'OrderList',
        component: () => import('@/views/order/list.vue'),
        meta: { title: '购买订单', icon: 'Tickets', perm: 'page:orders', group: '运营' },
      },
      {
        path: 'admins',
        name: 'Admins',
        component: () => import('@/views/admin/admins.vue'),
        meta: { title: '管理员管理', icon: 'UserFilled', perm: 'page:admins', group: '系统' },
      },
      {
        path: 'roles',
        name: 'Roles',
        component: () => import('@/views/admin/roles.vue'),
        meta: { title: '角色权限', icon: 'Lock', perm: 'page:roles', group: '系统' },
      },
      {
        path: 'legal',
        name: 'Legal',
        component: () => import('@/views/legal/index.vue'),
        meta: { title: '协议管理', icon: 'Document', perm: 'page:legal', group: '系统' },
      },
      {
        path: 'reports',
        name: 'Reports',
        component: () => import('@/views/report/index.vue'),
        meta: { title: '举报管理', icon: 'Warning', perm: 'page:report', group: '运营' },
      },
      {
        path: 'features',
        name: 'Features',
        component: () => import('@/views/feature/index.vue'),
        meta: { title: '功能开关', icon: 'Switch', perm: 'page:feature', group: '系统' },
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
