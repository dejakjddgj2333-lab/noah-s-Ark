<script setup>
import { computed, onUnmounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { authApi } from '../api'

const router = useRouter()

const form = ref({ email: '', code: '', password: '', confirm: '' })
const loading = ref(false)
const sending = ref(false)
const codeSent = ref(false)
const showPassword = ref(false)
const error = ref('')
const done = ref(false)
const countdown = ref(0)
let timer = null

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

onUnmounted(() => { if (timer) clearInterval(timer) })

function startCountdown() {
  countdown.value = 60
  if (timer) clearInterval(timer)
  timer = setInterval(() => {
    countdown.value--
    if (countdown.value <= 0) clearInterval(timer)
  }, 1000)
}

async function sendCode() {
  if (!form.value.email) { error.value = '请先填写邮箱'; return }
  sending.value = true
  error.value = ''
  try {
    // 后端模糊提示: 邮箱未注册也返回 ok, 恒提示已发送, 不泄露注册状态
    const res = await authApi.sendEmailCode(form.value.email.trim(), 'reset')
    codeSent.value = true
    startCountdown()
    // dev 模式: SMTP 未配置时后端回显验证码, 直接回填
    if (res?.debug_code) form.value.code = res.debug_code
  } catch (e) {
    error.value = e.message
  } finally {
    sending.value = false
  }
}

async function submit() {
  const f = form.value
  if (!f.email || !f.code || !f.password) { error.value = '请填写完整信息'; return }
  if (f.password.length < 8) { error.value = '新密码至少 8 位'; return }
  if (f.password !== f.confirm) { error.value = '两次密码不一致'; return }
  loading.value = true
  error.value = ''
  try {
    await authApi.resetPassword(f.email.trim(), f.code.trim(), f.password)
    done.value = true
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="bg-canvas-obsidian text-ink-white font-body-md min-h-screen flex flex-col overflow-hidden selection:bg-primary-container selection:text-ink-white">
    <!-- Top Global Header -->
    <header class="w-full h-12 px-6 flex justify-between items-center border-b border-hairline bg-canvas-obsidian shrink-0 z-50">
      <div class="flex items-center space-x-3">
        <div class="w-6 h-6 rounded bg-card-navy border border-hairline flex items-center justify-center">
          <div class="w-2.5 h-2.5 rounded-full border border-primary-container bg-primary-container/20"></div>
        </div>
        <span class="text-headline-md font-headline-md tracking-wider text-ink-white font-bold">MINGCE</span>
        <span class="text-hairline">|</span>
        <span class="text-label-sm font-label-sm text-steel-muted tracking-widest uppercase">TERMINAL.V4</span>
      </div>
      <div class="flex items-center space-x-2 text-label-sm font-label-sm text-steel-muted">
        <span class="w-1.5 h-1.5 rounded-full bg-bull-green"></span>
        <span class="font-mono-data text-mono-data text-ink-white">系统状态: 正常 (14ms)</span>
      </div>
    </header>

    <!-- Main -->
    <main class="flex-1 w-full bg-terminal-grid flex items-center justify-center py-8 px-6 overflow-y-auto">
      <div class="w-full max-w-[420px] bg-card-navy border border-hairline rounded-xl p-7 sm:p-8 relative shadow-2xl">
        <div class="absolute top-4 right-4 flex items-center space-x-1.5 px-2 py-0.5 rounded bg-surface-slate border border-hairline text-label-sm font-label-sm text-steel-muted">
          <span class="w-1.5 h-1.5 rounded-full bg-primary-container"></span>
          <span class="font-mono-data">SECURE PORT</span>
        </div>

        <!-- 成功态 -->
        <template v-if="done">
          <div class="flex flex-col items-center text-center py-6">
            <div class="w-14 h-14 rounded-full bg-bull-green/10 border border-bull-green/30 flex items-center justify-center mb-4">
              <span class="material-symbols-outlined text-bull-green text-[28px]">check_circle</span>
            </div>
            <h2 class="text-headline-lg font-headline-lg text-ink-white tracking-tight">密码已重置</h2>
            <p class="text-body-md font-body-md text-steel-muted mt-2">请使用新密码重新登录终端</p>
            <button
              class="w-full h-[42px] mt-6 bg-primary-container hover:bg-primary-container/90 active:opacity-85 text-ink-white font-headline-sm font-semibold rounded-xl flex items-center justify-center space-x-2 transition-all duration-150 shadow-sm"
              type="button"
              @click="router.push('/login')"
            >
              <span>返 回 登 录</span>
              <span class="material-symbols-outlined text-[18px]">arrow_forward</span>
            </button>
          </div>
        </template>

        <!-- 表单态 -->
        <template v-else>
          <!-- Header -->
          <div class="mb-6">
            <div class="text-label-sm font-label-sm text-primary tracking-wider uppercase font-mono-data mb-1">
              PASSWORD RECOVERY
            </div>
            <h2 class="text-headline-lg font-headline-lg text-ink-white tracking-tight">找回密码</h2>
            <p class="text-body-md font-body-md text-steel-muted mt-1">通过注册邮箱验证身份后重置终端访问密钥</p>
          </div>
          <!-- Form -->
          <form class="space-y-4" @submit.prevent="submit">
            <!-- Email -->
            <div class="space-y-1.5">
              <label class="block text-label-sm font-label-sm text-steel-muted uppercase tracking-wider" for="fp-email">
                注册邮箱
              </label>
              <div class="relative">
                <div class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none text-steel-muted">
                  <span class="material-symbols-outlined text-[18px]">alternate_email</span>
                </div>
                <input
                  id="fp-email"
                  v-model="form.email"
                  autocomplete="email"
                  class="w-full h-10 pl-9 pr-3 bg-surface border border-hairline rounded-lg text-ink-white placeholder-steel-muted/60 text-body-md font-body-md focus:border-primary-container focus:ring-1 focus:ring-primary-container focus:outline-none transition-all duration-150"
                  name="email"
                  placeholder="name@institution.com"
                  required
                  type="email"
                />
              </div>
            </div>
            <!-- Email Code -->
            <div class="space-y-1.5">
              <label class="block text-label-sm font-label-sm text-steel-muted uppercase tracking-wider" for="fp-code">
                邮箱验证码
              </label>
              <div class="flex space-x-2">
                <div class="relative flex-1">
                  <div class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none text-steel-muted">
                    <span class="material-symbols-outlined text-[18px]">mark_email_read</span>
                  </div>
                  <input
                    id="fp-code"
                    v-model="form.code"
                    class="w-full h-10 pl-9 pr-3 bg-surface border border-hairline rounded-lg text-ink-white placeholder-steel-muted/60 text-mono-data font-mono-data tracking-widest focus:border-primary-container focus:ring-1 focus:ring-primary-container focus:outline-none transition-all duration-150"
                    maxlength="6"
                    placeholder="6 位验证码"
                    required
                    type="text"
                  />
                </div>
                <button
                  class="px-3 h-10 bg-card-navy-high hover:bg-surface-variant text-ink-white text-label-sm font-label-sm rounded-lg border border-hairline transition-colors flex items-center space-x-1 disabled:opacity-60"
                  :disabled="sending || countdown > 0"
                  type="button"
                  @click="sendCode"
                >
                  <span class="material-symbols-outlined text-bull-green text-sm">{{ codeSent ? 'check' : 'send' }}</span>
                  <span>{{ countdown > 0 ? `${countdown}s` : sending ? '发送中…' : codeSent ? '重新发送' : '获取验证码' }}</span>
                </button>
              </div>
            </div>
            <!-- New Password -->
            <div class="space-y-1.5">
              <div class="flex items-center justify-between">
                <label class="block text-label-sm font-label-sm text-steel-muted uppercase tracking-wider" for="fp-password">
                  新访问密钥
                </label>
                <span class="text-label-sm font-label-sm" :class="pwdStrength >= 2 ? 'text-bull-green' : 'text-steel-muted'">{{ form.password ? strengthLabel : '' }}</span>
              </div>
              <div class="relative">
                <div class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none text-steel-muted">
                  <span class="material-symbols-outlined text-[18px]">lock</span>
                </div>
                <input
                  id="fp-password"
                  v-model="form.password"
                  autocomplete="new-password"
                  class="w-full h-10 pl-9 pr-10 bg-surface border border-hairline rounded-lg text-ink-white placeholder-steel-muted/60 text-body-md font-body-md focus:border-primary-container focus:ring-1 focus:ring-primary-container focus:outline-none transition-all duration-150"
                  name="new-password"
                  placeholder="至少8位，包含大写字母与特殊字符"
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
              <div class="grid grid-cols-3 gap-1.5 pt-1">
                <div class="h-1 rounded" :class="pwdStrength >= 1 ? 'bg-bull-green' : 'bg-outline-variant'"></div>
                <div class="h-1 rounded" :class="pwdStrength >= 2 ? 'bg-bull-green' : 'bg-outline-variant'"></div>
                <div class="h-1 rounded" :class="pwdStrength >= 3 ? 'bg-bull-green' : 'bg-outline-variant'"></div>
              </div>
            </div>
            <!-- Confirm Password -->
            <div class="space-y-1.5">
              <label class="block text-label-sm font-label-sm text-steel-muted uppercase tracking-wider" for="fp-confirm">
                确认新密钥
              </label>
              <div class="relative">
                <div class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none text-steel-muted">
                  <span class="material-symbols-outlined text-[18px]">lock_reset</span>
                </div>
                <input
                  id="fp-confirm"
                  v-model="form.confirm"
                  autocomplete="new-password"
                  class="w-full h-10 pl-9 pr-3 bg-surface border border-hairline rounded-lg text-ink-white placeholder-steel-muted/60 text-body-md font-body-md focus:border-primary-container focus:ring-1 focus:ring-primary-container focus:outline-none transition-all duration-150"
                  placeholder="再次输入以确认"
                  required
                  type="password"
                />
              </div>
            </div>
            <!-- Error -->
            <div v-if="error" class="text-bear-red text-label-sm font-label-sm flex items-center space-x-1.5">
              <span class="material-symbols-outlined text-[15px]">error</span>
              <span>{{ error }}</span>
            </div>
            <!-- Submit -->
            <div class="pt-2">
              <button
                class="w-full h-[42px] bg-primary-container hover:bg-primary-container/90 active:opacity-85 text-ink-white font-headline-sm font-semibold rounded-xl flex items-center justify-center space-x-2 transition-all duration-150 shadow-sm disabled:opacity-60"
                :disabled="loading"
                type="submit"
              >
                <span>{{ loading ? '重 置 中 …' : '重 置 密 码' }}</span>
                <span class="material-symbols-outlined text-[18px]">arrow_forward</span>
              </button>
            </div>
            <!-- Back to login -->
            <div class="pt-4 border-t border-hairline text-center">
              <span class="text-label-sm font-label-sm text-steel-muted">想起密码了？</span>
              <router-link class="text-label-sm font-label-sm text-primary hover:text-ink-white font-medium ml-1 transition-colors duration-150" to="/login">
                返回登录
              </router-link>
            </div>
          </form>
        </template>
      </div>
    </main>

    <!-- Global Footer Bar -->
    <footer class="w-full h-10 px-6 flex justify-between items-center text-label-sm font-label-sm text-steel-muted border-t border-hairline bg-canvas-obsidian shrink-0 z-50">
      <div class="flex items-center space-x-3">
        <span class="text-headline-sm font-headline-sm text-steel-muted">MINGCE</span>
        <span>© 2025 MINGCE Terminal Inc. All rights reserved.</span>
      </div>
      <div class="flex items-center space-x-4">
        <router-link class="hover:text-ink-white transition-colors duration-150" to="/terms">服务条款</router-link>
        <span class="text-hairline">·</span>
        <router-link class="hover:text-ink-white transition-colors duration-150" to="/privacy">隐私合规</router-link>
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
.bg-terminal-grid {
  background-image:
    linear-gradient(to right, rgba(52, 65, 94, 0.22) 1px, transparent 1px),
    linear-gradient(to bottom, rgba(52, 65, 94, 0.22) 1px, transparent 1px);
  background-size: 32px 32px;
}
</style>
