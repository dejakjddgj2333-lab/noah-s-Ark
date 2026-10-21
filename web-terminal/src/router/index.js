import { createRouter, createWebHistory } from 'vue-router'

const routes = [
  { path: '/login', component: () => import('../views/Login.vue'), meta: { public: true, title: '登录' } },
  { path: '/register', component: () => import('../views/Register.vue'), meta: { public: true, title: '注册' } },
  {
    path: '/',
    component: () => import('../layout/TerminalLayout.vue'),
    children: [
      { path: '', redirect: '/overview' },
      { path: 'overview', component: () => import('../views/Overview.vue'), meta: { title: '概览' } },
      { path: 'market', component: () => import('../views/Market.vue'), meta: { title: '行情' } },
      { path: 'market/:instId', component: () => import('../views/MarketDetail.vue'), meta: { title: '行情详情' } },
      { path: 'multi', component: () => import('../views/MultiDim.vue'), meta: { title: '多维数据' } },
      { path: 'liquidation', component: () => import('../views/Liquidation.vue'), meta: { title: '爆仓监控' } },
      { path: 'whale', component: () => import('../views/Whale.vue'), meta: { title: '巨鲸动向' } },
      { path: 'funding', component: () => import('../views/Funding.vue'), meta: { title: '资金费率' } },
      { path: 'news', component: () => import('../views/News.vue'), meta: { title: '资讯' } },
      { path: 'news/:id', component: () => import('../views/NewsDetail.vue'), meta: { title: '资讯详情' } },
      { path: 'chat', component: () => import('../views/Chat.vue'), meta: { title: '聊天室' } },
      { path: 'assets', component: () => import('../views/Assets.vue'), meta: { title: '资产理财' } },
      { path: 'profile', component: () => import('../views/Profile.vue'), meta: { title: '个人中心' } },
    ],
  },
  { path: '/:pathMatch(.*)*', redirect: '/overview' },
]

const router = createRouter({
  history: createWebHistory(),
  routes,
})

router.beforeEach((to) => {
  document.title = to.meta.title ? `${to.meta.title} · 明策终端` : '明策 MINGCE 终端'
  const token = localStorage.getItem('mc_token')
  if (!to.meta.public && !token) return { path: '/login', query: { r: to.fullPath } }
  if (to.meta.public && token) return { path: '/overview' }
})

export default router
