<script setup>
// 法务文档页: 服务条款 / 隐私政策 / 监管披露, 按路由 meta.kind 切换
import { computed } from 'vue'
import { useRoute } from 'vue-router'

const route = useRoute()

const DOCS = {
  terms: {
    title: '服务条款',
    en: 'TERMS OF SERVICE',
    updated: '2025-01-01',
    sections: [
      { h: '1. 服务说明', p: '明策 MINGCE 终端（下称"本终端"）为机构级行情情报工具，提供多维行情数据、巨鲸动向监测、爆仓预警、资金费率分析及行业资讯聚合服务。本终端仅提供信息展示与分析工具，不构成任何投资建议。' },
      { h: '2. 账号与访问', p: '账号仅限本人使用，不得转让、共享或出借。您对账号下的一切操作负责。发现未授权访问应立即通知平台。平台有权对异常账号采取限制、冻结或注销措施。' },
      { h: '3. 数据与免责', p: '行情数据来源于第三方交易所及公开数据渠道，平台尽力保证数据及时性与准确性，但不对因数据延迟、错误或中断造成的任何损失承担责任。数字资产交易风险极高，据此操作，风险自担。' },
      { h: '4. 禁止行为', p: '禁止利用本终端从事任何违法违规活动，包括但不限于：爬取或转售平台数据、干扰服务正常运行、发布违法信息、洗钱及其他金融犯罪行为。' },
      { h: '5. 条款变更', p: '平台保留随时修订本条款的权利，修订后将在终端内公示。继续使用本终端即视为接受修订后的条款。' },
    ],
  },
  privacy: {
    title: '隐私政策',
    en: 'PRIVACY POLICY',
    updated: '2025-01-01',
    sections: [
      { h: '1. 信息收集', p: '我们收集您注册时提供的账号信息（用户名、邮箱）、登录日志及终端使用偏好设置（如自选列表、界面偏好），偏好类数据仅存储于您的本地浏览器。' },
      { h: '2. 信息使用', p: '收集的信息仅用于：账号身份验证、服务安全保障、产品功能改进。我们不会向任何第三方出售您的个人信息。' },
      { h: '3. 信息保护', p: '传输层采用 AES-256 GCM 加密协议，凭据经哈希处理后存储。平台部署访问控制、入侵检测等安全措施保护您的数据。' },
      { h: '4. Cookie 与本地存储', p: '本终端使用浏览器本地存储（localStorage）保存登录凭据与界面偏好，不用于跨站追踪。清除浏览器数据将同时清除这些信息。' },
      { h: '5. 您的权利', p: '您有权查询、更正、删除您的个人信息，或注销账号。相关操作可在"个人中心"发起，或联系客服协助处理。' },
    ],
  },
  disclosure: {
    title: '监管披露',
    en: 'REGULATORY DISCLOSURE',
    updated: '2025-01-01',
    sections: [
      { h: '1. 风险提示', p: '数字资产价格波动剧烈，存在极高的投资风险。过往表现不代表未来收益。您可能在短时间内损失全部本金。请在充分了解风险后审慎决策。' },
      { h: '2. 非投资建议', p: '本终端提供的所有行情数据、分析指标、资讯内容仅供参考，不构成任何形式的投资要约、要约邀请或交易建议。' },
      { h: '3. 司法辖区限制', p: '本终端服务不面向禁止数字资产相关服务的司法辖区用户。您有责任确认在所在辖区使用本服务合法合规。' },
      { h: '4. 数据合规', p: '平台遵循适用数据保护法规处理用户数据，详情见《隐私政策》。监管机构依法调取时，平台将按法律要求配合。' },
    ],
  },
}

const doc = computed(() => DOCS[route.meta.kind] || DOCS.terms)
</script>

<template>
  <div class="min-h-screen bg-canvas-obsidian text-ink-white font-body-md terminal-grid-bg">
    <!-- 顶栏: 品牌 + 返回 -->
    <header class="w-full h-12 px-6 flex justify-between items-center border-b border-hairline bg-canvas-obsidian/90 backdrop-blur fixed top-0 left-0 right-0 z-50">
      <div class="flex items-center space-x-3">
        <div class="w-6 h-6 rounded bg-card-navy border border-hairline flex items-center justify-center">
          <span class="material-symbols-outlined text-primary-container text-[14px]">radar</span>
        </div>
        <span class="text-headline-sm font-headline-sm text-ink-white tracking-tight">MINGCE</span>
        <span class="text-label-sm font-label-sm text-steel-muted">| TERMINAL.V4</span>
      </div>
      <router-link class="text-label-sm font-label-sm text-primary hover:text-ink-white flex items-center space-x-1 transition-colors duration-150" to="/login">
        <span class="material-symbols-outlined text-[15px]">arrow_back</span>
        <span>返回登录</span>
      </router-link>
    </header>

    <main class="max-w-3xl mx-auto pt-24 pb-16 px-6">
      <div class="mb-8">
        <p class="text-label-sm font-label-sm text-steel-muted tracking-widest uppercase font-mono-data">{{ doc.en }}</p>
        <h1 class="text-headline-lg font-headline-lg text-ink-white tracking-tight mt-2">{{ doc.title }}</h1>
        <p class="text-label-sm font-label-sm text-steel-muted mt-2 font-mono-data">更新日期: {{ doc.updated }}</p>
      </div>

      <div class="space-y-6">
        <section v-for="s in doc.sections" :key="s.h" class="bg-surface-slate border border-hairline rounded-xl p-6">
          <h2 class="text-headline-sm font-headline-sm text-ink-white mb-2">{{ s.h }}</h2>
          <p class="text-body-md font-body-md text-steel-muted leading-relaxed">{{ s.p }}</p>
        </section>
      </div>

      <!-- 文档互链 -->
      <div class="mt-10 pt-6 border-t border-hairline flex flex-wrap gap-6 text-label-sm font-label-sm">
        <router-link v-if="route.meta.kind !== 'terms'" class="text-primary hover:text-ink-white transition-colors duration-150" to="/terms">服务条款</router-link>
        <router-link v-if="route.meta.kind !== 'privacy'" class="text-primary hover:text-ink-white transition-colors duration-150" to="/privacy">隐私政策</router-link>
        <router-link v-if="route.meta.kind !== 'disclosure'" class="text-primary hover:text-ink-white transition-colors duration-150" to="/disclosure">监管披露</router-link>
      </div>
    </main>
  </div>
</template>
