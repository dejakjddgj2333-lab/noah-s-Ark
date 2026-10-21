<script setup>
import { computed, ref } from 'vue'
import { useRouter } from 'vue-router'
import { useUserStore } from '../store/user'
import { authApi } from '../api'

const router = useRouter()
const store = useUserStore()

const form = ref({ username: '', email: '', code: '', password: '', confirm: '', invite_code: '' })
const loading = ref(false)
const sending = ref(false)
const agreed = ref(true)
const showPassword = ref(false)
const error = ref('')
const codeSent = ref(false)

const inviteFromUrl = new URLSearchParams(location.search).get('invite')
if (inviteFromUrl) form.value.invite_code = inviteFromUrl

// 密码强度: 0-3 段
const pwdStrength = computed(() => {
  const p = form.value.password
  if (!p) return 0
  let s = 0
  if (p.length >= 8) s++
  if (/[A-Z]/.test(p) && /[a-z]/.test(p)) s++
  if (/[^A-Za-z0-9]/.test(p) || /\d/.test(p)) s++
  return s
})
const strengthLabel = computed(() => ['强度: 弱', '强度: 弱', '强度: 中强', '强度: 强'][pwdStrength.value])

async function sendCode() {
  if (!form.value.email) { error.value = '请先填写邮箱'; return }
  sending.value = true
  error.value = ''
  try {
    await authApi.sendEmailCode(form.value.email.trim(), 'register')
    codeSent.value = true
  } catch (e) {
    error.value = e.message
  } finally {
    sending.value = false
  }
}

async function submit() {
  const f = form.value
  if (!f.username || !f.email || !f.password) { error.value = '请填写完整信息'; return }
  if (f.password !== f.confirm) { error.value = '两次密码不一致'; return }
  if (!agreed.value) { error.value = '请先阅读并同意终端访问协议'; return }
  loading.value = true
  error.value = ''
  try {
    await store.register({
      username: f.username.trim(),
      email: f.email.trim(),
      password: f.password,
      code: f.code.trim(),
      invite_code: f.invite_code.trim() || undefined,
    })
    router.push('/overview')
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="bg-canvas-obsidian text-ink-white min-h-screen flex flex-col font-body-md select-none antialiased">
    <!-- TOP APP BAR -->
    <header class="w-full h-12 px-6 flex justify-between items-center border-b border-hairline bg-canvas-obsidian shrink-0 z-50">
      <div class="flex items-center space-x-6">
        <div class="flex items-center space-x-2">
          <span class="text-headline-md font-headline-md tracking-wider text-ink-white font-bold">MINGCE</span>
          <span class="px-1.5 py-0.5 text-label-sm font-label-sm bg-primary-container/20 text-primary border border-primary/30 rounded">TERMINAL</span>
        </div>
        <div class="h-4 w-px bg-hairline"></div>
        <div class="flex items-center space-x-2">
          <span class="inline-block w-2 h-2 rounded-full bg-bull-green animate-pulse"></span>
          <span class="text-label-sm font-label-sm text-steel-muted">系统状态: 正常 (14ms)</span>
        </div>
      </div>
      <div class="flex items-center space-x-4">
        <div class="flex items-center space-x-1.5 text-steel-muted hover:text-ink-white cursor-pointer px-2 py-1 rounded hover:bg-card-navy/50 transition-colors">
          <span class="material-symbols-outlined text-bull-green">security</span>
          <span class="text-label-sm font-label-sm">SSL 256-BIT</span>
        </div>
        <div class="flex items-center space-x-1 text-steel-muted hover:text-ink-white cursor-pointer px-2 py-1 rounded hover:bg-card-navy/50 transition-colors">
          <span class="material-symbols-outlined">language</span>
          <span class="text-label-sm font-label-sm">ZH-CN</span>
        </div>
        <button class="text-steel-muted hover:text-ink-white p-1 rounded hover:bg-card-navy/50 transition-colors">
          <span class="material-symbols-outlined">help</span>
        </button>
      </div>
    </header>

    <!-- MAIN CANVAS (Split Left/Right Layout) -->
    <main class="flex-1 w-full grid-bg flex items-center justify-center py-8 px-6 lg:px-12">
      <div class="w-full max-w-[1360px] grid grid-cols-1 lg:grid-cols-12 gap-8 lg:gap-12 items-center">
        <!-- LEFT BRAND & INTELLIGENCE HUD PANEL -->
        <section class="lg:col-span-6 flex flex-col justify-between space-y-8 pr-0 lg:pr-6">
          <div>
            <div class="inline-flex items-center space-x-2 px-2.5 py-1 rounded bg-card-navy border border-hairline mb-5">
              <span class="w-2 h-2 rounded-full bg-bull-green"></span>
              <span class="text-label-sm font-label-sm text-bull-green font-semibold tracking-wider">MINGCE [PRO]</span>
              <span class="text-steel-muted text-label-sm font-label-sm">|</span>
              <span class="text-label-sm font-label-sm text-steel-muted tracking-wider">MARKET INTELLIGENCE TERMINAL</span>
            </div>
            <h1 class="text-headline-lg font-headline-lg text-ink-white tracking-tight leading-snug mb-4">
              多维行情洞察 <span class="text-primary">/</span> 机构巨鲸动向
            </h1>
            <p class="text-body-lg font-body-lg text-steel-muted leading-relaxed max-w-xl">
              专为高净值买方、宏观对冲基金和量化策略师打造的高密行情情报中枢，毫秒级解析全球流动性异动与结构性信号。
            </p>
          </div>
          <!-- Technical Telemetry Cards -->
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div class="bg-card-navy p-4 rounded-xl border border-hairline">
              <div class="flex items-center justify-between mb-3">
                <span class="text-label-sm font-label-sm text-steel-muted uppercase">深度流解析源</span>
                <span class="px-1.5 py-0.5 rounded text-[10px] font-mono-data bg-bull-green/10 text-bull-green border border-bull-green/20">SYNCED</span>
              </div>
              <div class="text-headline-sm font-headline-sm text-ink-white mb-1">L3 ORDERBOOK</div>
              <div class="text-label-sm font-label-sm text-steel-muted flex items-center space-x-2">
                <span class="material-symbols-outlined text-primary text-xs">hub</span>
                <span>48 EXCHANGES · 620K TICK/S</span>
              </div>
            </div>
            <div class="bg-card-navy p-4 rounded-xl border border-hairline">
              <div class="flex items-center justify-between mb-3">
                <span class="text-label-sm font-label-sm text-steel-muted uppercase">安全硬件网关</span>
                <span class="px-1.5 py-0.5 rounded text-[10px] font-mono-data bg-primary-container/20 text-primary border border-primary/30">CERTIFIED</span>
              </div>
              <div class="text-headline-sm font-headline-sm text-ink-white mb-1">HSM VAULT / TPM 2.0</div>
              <div class="text-label-sm font-label-sm text-steel-muted flex items-center space-x-2">
                <span class="material-symbols-outlined text-primary text-xs">verified_user</span>
                <span>ISMS ISO-27001 COMPLIANT</span>
              </div>
            </div>
          </div>
          <!-- Telemetry Data Stream -->
          <div class="bg-surface-slate/80 border border-hairline p-3 rounded-lg flex items-center justify-between text-mono-data font-mono-data text-steel-muted">
            <div class="flex items-center space-x-2">
              <span class="text-bull-green text-[10px]">●</span>
              <span class="text-label-sm font-label-sm text-steel-muted">NODE LATENCY:</span>
              <span class="text-ink-white font-semibold">14ms</span>
            </div>
            <div class="h-3 w-px bg-hairline"></div>
            <div class="flex items-center space-x-2">
              <span class="text-label-sm font-label-sm text-steel-muted">MONITORED:</span>
              <span class="text-ink-white font-semibold">38,420</span>
            </div>
            <div class="h-3 w-px bg-hairline"></div>
            <div class="flex items-center space-x-2">
              <span class="text-label-sm font-label-sm text-steel-muted">CIPHER:</span>
              <span class="text-primary font-semibold">AES-256 GCM</span>
            </div>
          </div>
        </section>

        <!-- RIGHT REGISTRATION CARD -->
        <section class="lg:col-span-6 flex justify-center lg:justify-end">
          <div class="w-full max-w-[500px] bg-card-navy border border-hairline rounded-xl p-6 sm:p-8 backdrop-blur shadow-2xl relative">
            <!-- Top Card Meta -->
            <div class="flex items-center justify-between mb-4">
              <div class="inline-flex items-center space-x-1.5 px-2 py-0.5 rounded bg-surface-slate border border-hairline">
                <span class="w-1.5 h-1.5 rounded-full bg-bull-green animate-ping"></span>
                <span class="w-1.5 h-1.5 rounded-full bg-bull-green -ml-3"></span>
                <span class="text-label-sm font-label-sm text-primary tracking-wider">NEW TERMINAL ACCESS</span>
              </div>
              <span class="text-label-sm font-label-sm text-steel-muted">SEC-ID: REG-092</span>
            </div>
            <!-- Header -->
            <h2 class="text-headline-lg font-headline-lg text-ink-white font-bold mb-1">创建账户</h2>
            <p class="text-body-md font-body-md text-steel-muted mb-6">
              邀请制终端权限开启 · 请录入操作员凭证
            </p>
            <!-- Registration Form -->
            <form class="space-y-4" @submit.prevent="submit">
              <!-- 1. Username Field -->
              <div>
                <label class="block text-label-sm font-label-sm text-steel-muted uppercase mb-1.5">
                  操作员用户名
                </label>
                <div class="relative flex items-center">
                  <span class="material-symbols-outlined absolute left-3 text-steel-muted">badge</span>
                  <input
                    v-model="form.username"
                    class="w-full bg-surface-slate text-ink-white text-body-md font-body-md border border-hairline rounded pl-9 pr-3 py-2 focus:outline-none focus:border-primary-container focus:ring-1 focus:ring-primary-container transition-all"
                    placeholder="例如: quant_trader_01"
                    type="text"
                  />
                </div>
              </div>
              <!-- 2. Email Field -->
              <div>
                <label class="block text-label-sm font-label-sm text-steel-muted uppercase mb-1.5">
                  机构 / 工作邮箱
                </label>
                <div class="relative flex items-center">
                  <span class="material-symbols-outlined absolute left-3 text-steel-muted">alternate_email</span>
                  <input
                    v-model="form.email"
                    class="w-full bg-surface-slate text-ink-white text-body-md font-body-md border border-hairline rounded pl-9 pr-3 py-2 focus:outline-none focus:border-primary-container focus:ring-1 focus:ring-primary-container transition-all"
                    placeholder="name@institution.com"
                    type="email"
                  />
                </div>
              </div>
              <!-- 2.5 Email Code Field -->
              <div>
                <label class="block text-label-sm font-label-sm text-steel-muted uppercase mb-1.5">
                  邮箱验证码
                </label>
                <div class="flex space-x-2">
                  <div class="relative flex-1">
                    <span class="material-symbols-outlined absolute left-3 top-2.5 text-steel-muted">mark_email_read</span>
                    <input
                      v-model="form.code"
                      class="w-full bg-surface-slate text-ink-white text-mono-data font-mono-data border border-hairline rounded pl-9 pr-3 py-2 tracking-widest focus:outline-none focus:border-primary-container focus:ring-1 focus:ring-primary-container transition-all"
                      maxlength="6"
                      placeholder="6 位验证码"
                      type="text"
                    />
                  </div>
                  <button
                    class="px-3 py-2 bg-card-navy-high hover:bg-surface-variant text-ink-white text-label-sm font-label-sm rounded border border-hairline transition-colors flex items-center space-x-1 disabled:opacity-60"
                    :disabled="sending"
                    type="button"
                    @click="sendCode"
                  >
                    <span class="material-symbols-outlined text-bull-green text-sm">{{ codeSent ? 'check' : 'send' }}</span>
                    <span>{{ sending ? '发送中…' : codeSent ? '重新发送' : '获取验证码' }}</span>
                  </button>
                </div>
              </div>
              <!-- 3. Password Field -->
              <div>
                <div class="flex items-center justify-between mb-1.5">
                  <label class="block text-label-sm font-label-sm text-steel-muted uppercase">
                    终端访问密码
                  </label>
                  <span class="text-label-sm font-label-sm" :class="pwdStrength >= 2 ? 'text-bull-green' : 'text-steel-muted'">{{ form.password ? strengthLabel : '' }}</span>
                </div>
                <div class="relative flex items-center">
                  <span class="material-symbols-outlined absolute left-3 text-steel-muted">lock</span>
                  <input
                    v-model="form.password"
                    class="w-full bg-surface-slate text-ink-white text-body-md font-body-md border border-hairline rounded pl-9 pr-10 py-2 focus:outline-none focus:border-primary-container focus:ring-1 focus:ring-primary-container transition-all"
                    placeholder="••••••••••••"
                    :type="showPassword ? 'text' : 'password'"
                  />
                  <button
                    class="absolute right-3 text-steel-muted hover:text-ink-white"
                    type="button"
                    @click="showPassword = !showPassword"
                  >
                    <span class="material-symbols-outlined">{{ showPassword ? 'visibility_off' : 'visibility' }}</span>
                  </button>
                </div>
                <!-- Password Strength Bar (3 Segments) -->
                <div class="grid grid-cols-3 gap-1.5 mt-2">
                  <div class="h-1 rounded" :class="pwdStrength >= 1 ? 'bg-bull-green' : 'bg-outline-variant'"></div>
                  <div class="h-1 rounded" :class="pwdStrength >= 2 ? 'bg-bull-green' : 'bg-outline-variant'"></div>
                  <div class="h-1 rounded" :class="pwdStrength >= 3 ? 'bg-bull-green' : 'bg-outline-variant'"></div>
                </div>
                <p class="text-label-sm font-label-sm text-steel-muted mt-1.5 flex items-center space-x-1">
                  <span class="material-symbols-outlined text-xs text-primary">check_circle</span>
                  <span>至少8位，包含大写字母与特殊字符</span>
                </p>
              </div>
              <!-- 4. Confirm Password Field -->
              <div>
                <label class="block text-label-sm font-label-sm text-steel-muted uppercase mb-1.5">
                  确认终端密码
                </label>
                <div class="relative flex items-center">
                  <span class="material-symbols-outlined absolute left-3 text-steel-muted">lock_reset</span>
                  <input
                    v-model="form.confirm"
                    class="w-full bg-surface-slate text-ink-white text-body-md font-body-md border border-hairline rounded pl-9 pr-3 py-2 focus:outline-none focus:border-primary-container focus:ring-1 focus:ring-primary-container transition-all"
                    placeholder="再次输入以确认"
                    type="password"
                  />
                </div>
              </div>
              <!-- 5. Invite Code Field -->
              <div class="p-3 rounded-lg bg-surface-slate/70 border border-hairline/80">
                <div class="flex items-center justify-between mb-1.5">
                  <label class="text-label-sm font-label-sm text-ink-white uppercase font-semibold flex items-center space-x-1">
                    <span>专属邀请码</span>
                    <span class="px-1.5 py-0.2 rounded text-[10px] font-mono-data bg-amber-warn/20 text-amber-warn border border-amber-warn/30">选填</span>
                  </label>
                  <span v-if="form.invite_code" class="text-label-sm font-label-sm text-bull-green">代码有效</span>
                </div>
                <div class="relative">
                  <span class="material-symbols-outlined absolute left-3 top-2.5 text-steel-muted">key</span>
                  <input
                    v-model="form.invite_code"
                    class="w-full bg-canvas-obsidian text-ink-white text-mono-data font-mono-data border border-hairline rounded pl-9 pr-3 py-2 uppercase tracking-wide focus:outline-none focus:border-primary-container"
                    placeholder="MGC-XXXX-XXXX"
                    type="text"
                  />
                </div>
                <p class="text-[11px] font-mono-data text-amber-warn mt-1.5 flex items-center space-x-1">
                  <span class="material-symbols-outlined text-xs">info</span>
                  <span>填写好友邀请码，双方享返佣</span>
                </p>
              </div>
              <!-- Agreement Checkbox -->
              <div class="flex items-start space-x-2.5 pt-1">
                <input
                  id="compliance-agree"
                  v-model="agreed"
                  class="mt-1 w-4 h-4 rounded bg-surface-slate border-hairline text-primary-container focus:ring-0 focus:ring-offset-0 cursor-pointer"
                  type="checkbox"
                />
                <label class="text-body-md font-body-md text-steel-muted cursor-pointer leading-tight" for="compliance-agree">
                  我已阅读并知悉机构合规接入要求及交易终端访问协议
                </label>
              </div>
              <!-- Error -->
              <div v-if="error" class="text-bear-red text-label-sm font-label-sm flex items-center space-x-1.5">
                <span class="material-symbols-outlined text-[15px]">error</span>
                <span>{{ error }}</span>
              </div>
              <!-- Submit Primary CTA -->
              <button
                class="w-full h-10 mt-2 bg-primary-container hover:bg-primary-container/90 text-on-primary-container font-headline-sm text-headline-sm rounded-lg flex items-center justify-center space-x-2 transition-all shadow-lg shadow-primary-container/20 active:opacity-80 disabled:opacity-60"
                :disabled="loading"
                type="submit"
              >
                <span>{{ loading ? '创建中…' : '注册并进入终端' }}</span>
                <span class="material-symbols-outlined text-sm">arrow_forward</span>
              </button>
            </form>
            <!-- Secondary Link to Login -->
            <div class="mt-4 pt-4 border-t border-hairline/60 flex items-center justify-between text-body-md">
              <span class="text-steel-muted">已有终端账号？</span>
              <router-link class="text-primary hover:text-ink-white flex items-center space-x-1 transition-colors text-headline-sm font-headline-sm" to="/login">
                <span>去登录</span>
                <span class="material-symbols-outlined text-sm">login</span>
              </router-link>
            </div>
            <!-- Bottom Micro Details -->
            <div class="mt-4 text-center">
              <p class="text-[11px] text-steel-muted">
                注册即代表同意 <router-link class="underline hover:text-ink-white" to="/terms">用户协议</router-link> 与 <router-link class="underline hover:text-ink-white" to="/privacy">隐私政策</router-link>
              </p>
              <div class="mt-1 text-[10px] font-mono-data text-steel-muted flex items-center justify-center space-x-1">
                <span class="material-symbols-outlined text-[12px] text-bull-green">lan</span>
                <span>安全接入节点: NODE: HK-CENTRAL-01</span>
              </div>
            </div>
          </div>
        </section>
      </div>
    </main>

    <!-- FOOTER -->
    <footer class="w-full h-10 px-6 flex justify-between items-center text-label-sm font-label-sm text-steel-muted border-t border-hairline bg-canvas-obsidian shrink-0">
      <div class="flex items-center space-x-3">
        <span class="text-headline-sm font-headline-sm text-steel-muted">MINGCE</span>
        <span>© 2025 MINGCE Terminal Inc. All rights reserved. AES-256 GCM 机构级端到端加密传输</span>
      </div>
      <div class="flex items-center space-x-4">
        <router-link class="text-steel-muted hover:text-ink-white transition-colors duration-150" to="/terms">服务条款</router-link>
        <router-link class="text-steel-muted hover:text-ink-white transition-colors duration-150" to="/privacy">隐私合规</router-link>
        <router-link class="text-steel-muted hover:text-ink-white transition-colors duration-150" to="/disclosure">监管披露</router-link>
        <span class="text-steel-muted flex items-center space-x-1">
          <span class="w-1.5 h-1.5 rounded-full bg-bull-green"></span>
          <span>节点状态</span>
        </span>
      </div>
    </footer>
  </div>
</template>

<style scoped>
.grid-bg {
  background-size: 32px 32px;
  background-image:
    linear-gradient(to right, rgba(52, 65, 94, 0.15) 1px, transparent 1px),
    linear-gradient(to bottom, rgba(52, 65, 94, 0.15) 1px, transparent 1px);
}
input::placeholder {
  color: #9EA0B2;
  opacity: 0.6;
}
</style>
