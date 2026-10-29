<script setup>
import { ref } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useUserStore } from '../store/user'
import DotGlobe from '../components/DotGlobe.vue'

const router = useRouter()
const route = useRoute()
const store = useUserStore()

const username = ref('')
const password = ref('')
const showPassword = ref(false)
const remember = ref(false)
const loading = ref(false)
const error = ref('')

async function submit() {
  if (!username.value || !password.value) {
    error.value = '请输入用户名和密码'
    return
  }
  loading.value = true
  error.value = ''
  try {
    await store.login(username.value.trim(), password.value)
    router.push(route.query.r || '/overview')
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="bg-canvas-obsidian text-ink-white font-body-md min-h-screen overflow-hidden selection:bg-primary-container selection:text-ink-white">
    <!-- Top Global Header -->
    <header class="w-full h-12 px-6 flex justify-between items-center border-b border-hairline bg-canvas-obsidian fixed top-0 left-0 right-0 z-50">
      <div class="flex items-center space-x-3">
        <div class="w-6 h-6 rounded bg-card-navy border border-hairline flex items-center justify-center">
          <div class="w-2.5 h-2.5 rounded-full border border-primary-container bg-primary-container/20"></div>
        </div>
        <span class="text-headline-md font-headline-md tracking-wider text-ink-white font-bold">MINGCE</span>
        <span class="text-hairline">|</span>
        <span class="text-label-sm font-label-sm text-steel-muted tracking-widest uppercase">TERMINAL.V4</span>
      </div>
      <div class="flex items-center space-x-6 text-label-sm font-label-sm">
        <div class="flex items-center space-x-2 text-steel-muted">
          <span class="w-1.5 h-1.5 rounded-full bg-bull-green animate-indicator"></span>
          <span class="font-mono-data text-mono-data text-ink-white">系统状态: 正常 (14ms)</span>
        </div>
        <div class="h-3.5 w-px bg-hairline"></div>
        <div class="flex items-center space-x-4 text-steel-muted">
          <button aria-label="安全状态" class="flex items-center space-x-1 hover:text-ink-white transition-colors duration-150" title="安全协议" type="button">
            <span class="material-symbols-outlined text-[16px]">security</span>
            <span class="text-label-sm font-label-sm uppercase">SSL 256</span>
          </button>
          <button aria-label="语言切换" class="flex items-center space-x-1 hover:text-ink-white transition-colors duration-150" title="切换语言" type="button">
            <span class="material-symbols-outlined text-[16px]">language</span>
            <span class="text-label-sm font-label-sm">ZH-CN</span>
          </button>
          <button aria-label="帮助" class="flex items-center space-x-1 hover:text-ink-white transition-colors duration-150" title="接入帮助" type="button">
            <span class="material-symbols-outlined text-[16px]">help</span>
            <span class="text-label-sm font-label-sm">支持</span>
          </button>
        </div>
      </div>
    </header>

    <!-- Main Split Layout -->
    <main class="w-full h-screen pt-12 pb-10 flex flex-col md:flex-row">
      <!-- LEFT PANEL: Brand & 3D 点阵地球背景 (55%) -->
      <section class="relative w-full md:w-[55%] h-full bg-canvas-obsidian p-6 lg:p-8 xl:p-12 flex flex-col overflow-hidden">
        <div class="absolute inset-0 radial-cobalt-glow pointer-events-none"></div>
        <DotGlobe />
        <div class="relative z-10 flex-1 flex flex-col justify-center min-h-0 space-y-4 xl:space-y-5">
          <!-- Brand Block -->
          <div class="space-y-2.5">
            <div class="flex items-center space-x-3">
              <span class="inline-flex items-center space-x-1.5 px-2 py-0.5 rounded bg-primary-container/15 border border-primary-container/40 text-label-sm font-label-sm text-primary-fixed-dim font-mono-data">
                <span class="w-1.5 h-1.5 rounded-full bg-primary-container"></span>
                <span>INSTITUTIONAL CORE</span>
              </span>
            </div>
            <div class="flex items-baseline space-x-2.5">
              <h1 class="text-headline-lg font-headline-lg text-ink-white tracking-tight">明策 MINGCE</h1>
              <span class="text-label-sm font-label-sm text-steel-muted px-1.5 py-0.5 rounded bg-card-navy border border-hairline font-mono-data">PRO</span>
            </div>
            <p class="text-body-md font-body-md text-steel-muted font-mono-data text-[12px] tracking-wide">
              全球高密行情洞察与机构级巨鲸流动性中枢
            </p>
          </div>

          <!-- 能力小卡 -->
          <div class="grid grid-cols-2 lg:grid-cols-4 gap-3">
            <div class="bg-card-navy/90 border border-hairline rounded-lg p-3">
              <div class="text-[9px] font-label-sm text-steel-muted tracking-wider">L3 ORDERBOOK</div>
              <div class="font-mono-data text-[13px] text-ink-white mt-0.5">48 EXCHANGES</div>
              <div class="font-mono-data text-[10px] text-bull-green mt-0.5">629K TICK/S</div>
            </div>
            <div class="bg-card-navy/90 border border-hairline rounded-lg p-3">
              <div class="text-[9px] font-label-sm text-steel-muted tracking-wider">HSM VAULT</div>
              <div class="font-mono-data text-[13px] text-ink-white mt-0.5">TPM 2.0</div>
              <div class="font-mono-data text-[10px] text-bull-green mt-0.5">ISMS CERTIFIED</div>
            </div>
            <div class="bg-card-navy/90 border border-hairline rounded-lg p-3">
              <div class="text-[9px] font-label-sm text-steel-muted tracking-wider">LATENCY</div>
              <div class="font-mono-data text-[13px] text-ink-white mt-0.5">14ms HK-CENTRAL</div>
              <div class="font-mono-data text-[10px] text-bull-green mt-0.5">0 PACKET DROP</div>
            </div>
            <div class="bg-card-navy/90 border border-hairline rounded-lg p-3">
              <div class="text-[9px] font-label-sm text-steel-muted tracking-wider">WHALE DETECTION</div>
              <div class="font-mono-data text-[13px] text-ink-white mt-0.5">38,420 WALLETS</div>
              <div class="font-mono-data text-[10px] text-amber-warn mt-0.5">REALTIME FLOW</div>
            </div>
          </div>
        </div>

        <!-- Left Bottom Stat Pills -->
        <div class="relative z-10 pt-4 grid grid-cols-2 lg:grid-cols-4 gap-2.5">
          <div class="flex items-center space-x-2 px-3 py-2 bg-card-navy/80 border border-hairline rounded-lg text-label-sm font-label-sm text-steel-muted">
            <span class="material-symbols-outlined text-[14px] text-bull-green">speed</span>
            <span>延迟: <span class="text-ink-white font-mono-data">14ms (HK)</span></span>
          </div>
          <div class="flex items-center space-x-2 px-3 py-2 bg-card-navy/80 border border-hairline rounded-lg text-label-sm font-label-sm text-steel-muted">
            <span class="material-symbols-outlined text-[14px] text-steel-muted">query_stats</span>
            <span>监控实体: <span class="text-ink-white font-mono-data">38,420</span></span>
          </div>
          <div class="flex items-center space-x-2 px-3 py-2 bg-card-navy/80 border border-hairline rounded-lg text-label-sm font-label-sm text-steel-muted">
            <span class="material-symbols-outlined text-[14px] text-primary-fixed-dim">lock</span>
            <span class="font-mono-data text-ink-white">AES-256 GCM</span>
          </div>
          <div class="flex items-center space-x-2 px-3 py-2 bg-card-navy/80 border border-hairline rounded-lg text-label-sm font-label-sm text-steel-muted">
            <span class="material-symbols-outlined text-[14px] text-primary-fixed-dim">verified_user</span>
            <span class="font-mono-data text-ink-white">HSM TPM 2.0</span>
          </div>
        </div>
      </section>

      <!-- RIGHT PANEL: Authentication Terminal (45%) -->
      <section class="relative w-full md:w-[45%] h-full bg-surface-slate bg-terminal-grid border-t md:border-t-0 md:border-l border-hairline flex flex-col justify-center items-center px-6 py-8 sm:px-12 xl:px-16 overflow-y-auto">
        <div class="w-full max-w-[420px] bg-card-navy border border-hairline rounded-xl p-7 sm:p-8 relative shadow-2xl">
          <div class="absolute top-4 right-4 flex items-center space-x-1.5 px-2 py-0.5 rounded bg-surface-slate border border-hairline text-label-sm font-label-sm text-steel-muted">
            <span class="w-1.5 h-1.5 rounded-full bg-primary-container"></span>
            <span class="font-mono-data">SECURE PORT</span>
          </div>
          <!-- Header -->
          <div class="mb-6">
            <div class="text-label-sm font-label-sm text-primary tracking-wider uppercase font-mono-data mb-1">
              AUTHORIZED ACCESS ONLY
            </div>
            <h2 class="text-headline-lg font-headline-lg text-ink-white tracking-tight">登录终端</h2>
            <p class="text-body-md font-body-md text-steel-muted mt-1">请输入分配的机构操作员凭据以解锁行情会话</p>
          </div>
          <!-- Form -->
          <form class="space-y-4" @submit.prevent="submit">
            <!-- Field 1: Account -->
            <div class="space-y-1.5">
              <label class="block text-label-sm font-label-sm text-steel-muted uppercase tracking-wider" for="username">
                账号
              </label>
              <div class="relative">
                <div class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none text-steel-muted">
                  <span class="material-symbols-outlined text-[18px]">account_circle</span>
                </div>
                <input
                  id="username"
                  v-model="username"
                  autocomplete="username"
                  class="w-full h-10 pl-9 pr-3 bg-surface border border-hairline rounded-lg text-ink-white placeholder-steel-muted/60 text-body-md font-body-md focus:border-primary-container focus:ring-1 focus:ring-primary-container focus:outline-none transition-all duration-150"
                  name="username"
                  placeholder="请输入账号"
                  required
                  type="text"
                />
              </div>
            </div>
            <!-- Field 2: Password -->
            <div class="space-y-1.5">
              <label class="block text-label-sm font-label-sm text-steel-muted uppercase tracking-wider" for="password">
                终端访问密钥
              </label>
              <div class="relative">
                <div class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none text-steel-muted">
                  <span class="material-symbols-outlined text-[18px]">lock</span>
                </div>
                <input
                  id="password"
                  v-model="password"
                  autocomplete="current-password"
                  class="w-full h-10 pl-9 pr-10 bg-surface border border-hairline rounded-lg text-ink-white placeholder-steel-muted/60 text-body-md font-body-md focus:border-primary-container focus:ring-1 focus:ring-primary-container focus:outline-none transition-all duration-150"
                  name="password"
                  placeholder="••••••••••••"
                  required
                  :type="showPassword ? 'text' : 'password'"
                />
                <button
                  aria-label="切换密码明文"
                  class="absolute inset-y-0 right-0 pr-3 flex items-center text-steel-muted hover:text-ink-white focus:outline-none"
                  type="button"
                  @click="showPassword = !showPassword"
                >
                  <span class="material-symbols-outlined text-[18px]">{{ showPassword ? 'visibility_off' : 'visibility' }}</span>
                </button>
              </div>
            </div>
            <!-- Auxiliary Options -->
            <div class="flex items-center justify-between pt-1">
              <label class="flex items-center space-x-2 cursor-pointer select-none">
                <input v-model="remember" class="w-4 h-4 rounded bg-surface border-hairline text-primary-container focus:ring-primary-container focus:ring-offset-0 focus:ring-1 bg-clip-border cursor-pointer" type="checkbox" />
                <span class="text-label-sm font-label-sm text-steel-muted">记住当前终端 (30天)</span>
              </label>
              <router-link class="text-label-sm font-label-sm text-primary hover:underline hover:text-ink-white transition-colors duration-150" to="/forgot-password">
                忘记密码?
              </router-link>
            </div>
            <!-- Error -->
            <div v-if="error" class="text-bear-red text-label-sm font-label-sm flex items-center space-x-1.5">
              <span class="material-symbols-outlined text-[15px]">error</span>
              <span>{{ error }}</span>
            </div>
            <!-- Submit Button -->
            <div class="pt-2">
              <button
                class="w-full h-[42px] bg-primary-container hover:bg-primary-container/90 active:opacity-85 text-ink-white font-headline-sm font-semibold rounded-xl flex items-center justify-center space-x-2 transition-all duration-150 shadow-sm disabled:opacity-60"
                :disabled="loading"
                type="submit"
              >
                <span>{{ loading ? '登 录 中 …' : '登 录 终 端' }}</span>
                <span class="material-symbols-outlined text-[18px]">arrow_forward</span>
              </button>
            </div>
            <!-- Secondary Actions -->
            <div class="pt-4 border-t border-hairline text-center">
              <span class="text-label-sm font-label-sm text-steel-muted">没有账号？</span>
              <router-link class="text-label-sm font-label-sm text-primary hover:text-ink-white font-medium ml-1 transition-colors duration-150" to="/register">
                申请接入 / 注册
              </router-link>
            </div>
          </form>
        </div>
        <!-- Bottom Compliance Disclaimer -->
        <div class="mt-6 text-center space-y-1">
          <p class="text-label-sm font-label-sm text-steel-muted">
            登录即代表同意 <router-link class="underline hover:text-ink-white" to="/terms">用户协议</router-link> 与 <router-link class="underline hover:text-ink-white" to="/privacy">隐私政策</router-link>
          </p>
          <div class="flex items-center justify-center space-x-2 text-label-sm font-label-sm text-steel-muted font-mono-data">
            <span>安全接入节点:</span>
            <span class="text-ink-white">NODE: HK-CENTRAL-01</span>
          </div>
        </div>
      </section>
    </main>

    <!-- Global Footer Bar -->
    <footer class="w-full h-10 px-6 flex justify-between items-center text-label-sm font-label-sm text-steel-muted border-t border-hairline bg-canvas-obsidian fixed bottom-0 left-0 right-0 z-50">
      <div class="flex items-center space-x-3">
        <span class="text-headline-sm font-headline-sm text-steel-muted">MINGCE</span>
        <span>© 2025 MINGCE Terminal Inc. All rights reserved. AES-256 GCM 机构级端到端加密传输</span>
      </div>
      <div class="flex items-center space-x-4">
        <router-link class="hover:text-ink-white transition-colors duration-150" to="/terms">服务条款</router-link>
        <span class="text-hairline">·</span>
        <router-link class="hover:text-ink-white transition-colors duration-150" to="/privacy">隐私合规</router-link>
        <span class="text-hairline">·</span>
        <router-link class="hover:text-ink-white transition-colors duration-150" to="/disclosure">监管披露</router-link>
        <span class="text-hairline">·</span>
        <span class="flex items-center space-x-1">
          <span class="w-1.5 h-1.5 rounded-full bg-bull-green"></span>
          <span>节点状态</span>
        </span>
      </div>
    </footer>
  </div>
</template>

<style scoped>
/* Engineering Hairline Grid Pattern */
.bg-terminal-grid {
  background-image:
    linear-gradient(to right, rgba(52, 65, 94, 0.22) 1px, transparent 1px),
    linear-gradient(to bottom, rgba(52, 65, 94, 0.22) 1px, transparent 1px);
  background-size: 32px 32px;
}
.radial-cobalt-glow {
  background: radial-gradient(circle 650px at 0% 0%, rgba(46, 92, 255, 0.14) 0%, transparent 75%);
}
/* Subtle ticker pulse */
@keyframes pulse-subtle {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.4; }
}
.animate-indicator {
  animation: pulse-subtle 2.2s cubic-bezier(0.4, 0, 0.6, 1) infinite;
}
</style>
