<script setup>
import { onMounted, reactive, ref } from 'vue'
import { useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { totpSetup, totpConfirm } from '@/api/user'
import { useUserStore } from '@/store/user'

const router = useRouter()
const userStore = useUserStore()

const loading = ref(false)
const confirming = ref(false)
const setup = reactive({ secret: '', uri: '' })
const code = ref('')

onMounted(async () => {
  if (!userStore.isLoggedIn) {
    router.push('/login')
    return
  }
  loading.value = true
  try {
    const res = await totpSetup()
    setup.secret = res.secret
    setup.uri = res.uri
  } catch {
    ElMessage.error('获取绑定密钥失败, 请重新登录')
  } finally {
    loading.value = false
  }
})

async function confirm() {
  if (!code.value || code.value.length < 6) {
    ElMessage.warning('请输入 6 位动态码')
    return
  }
  confirming.value = true
  try {
    await totpConfirm(code.value)
    ElMessage.success('绑定成功')
    userStore.setNeedTotp(false)
    await userStore.fetchMe()
    router.push('/dashboard')
  } finally {
    confirming.value = false
  }
}

function qrUrl(uri) {
  return `https://api.qrserver.com/v1/create-qr-code/?size=180x180&data=${encodeURIComponent(uri)}`
}
</script>

<template>
  <div class="bind-page">
    <div class="bind-card">
      <h2 class="bind-title">绑定谷歌验证器</h2>
      <p class="bind-sub">安全要求: 所有管理员必须绑定谷歌验证才能进入后台</p>

      <div v-loading="loading" class="bind-body">
        <template v-if="setup.uri">
          <div class="qr-box">
            <img :src="qrUrl(setup.uri)" alt="TOTP QR" class="qr-img" />
          </div>
          <ol class="steps">
            <li>打开 Google Authenticator (或任意 TOTP 应用)</li>
            <li>扫码上方二维码, 或手动输入密钥</li>
            <li>输入 App 显示的 6 位动态码完成绑定</li>
          </ol>
          <div class="secret-row">
            <span class="secret-label">手动密钥</span>
            <code class="secret-code">{{ setup.secret }}</code>
          </div>
          <el-input
            v-model="code"
            placeholder="输入 6 位动态码"
            maxlength="8"
            size="large"
            class="code-input"
            @keyup.enter="confirm"
          />
          <el-button
            type="primary"
            class="bind-btn"
            size="large"
            :loading="confirming"
            @click="confirm"
          >完成绑定并进入后台</el-button>
        </template>
      </div>
    </div>
  </div>
</template>

<style scoped>
.bind-page {
  height: 100%;
  display: flex;
  align-items: center;
  justify-content: center;
  background: radial-gradient(1200px 600px at 20% 10%, #1b2452 0%, #0b1026 55%, #070b1c 100%);
}

.bind-card {
  width: 420px;
  padding: 36px 32px;
  border-radius: 18px;
  background: rgba(255, 255, 255, 0.06);
  border: 1px solid rgba(255, 255, 255, 0.12);
  backdrop-filter: blur(20px);
  box-shadow: 0 24px 64px rgba(4, 8, 28, 0.6);
}

.bind-title {
  color: #fff;
  font-size: 20px;
  font-weight: 600;
  text-align: center;
}

.bind-sub {
  margin-top: 6px;
  color: rgba(255, 255, 255, 0.45);
  font-size: 12px;
  text-align: center;
  margin-bottom: 22px;
}

.qr-box {
  display: flex;
  justify-content: center;
  margin-bottom: 16px;
}

.qr-img {
  width: 180px;
  height: 180px;
  border-radius: 10px;
  background: #fff;
  padding: 8px;
}

.steps {
  margin: 0 0 14px;
  padding-left: 20px;
  color: rgba(255, 255, 255, 0.7);
  font-size: 13px;
  line-height: 1.9;
}

.secret-row {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 16px;
  padding: 10px 12px;
  border-radius: 8px;
  background: rgba(255, 255, 255, 0.05);
}

.secret-label {
  color: rgba(255, 255, 255, 0.5);
  font-size: 12px;
  white-space: nowrap;
}

.secret-code {
  color: #8ab4ff;
  font-size: 13px;
  letter-spacing: 1px;
  word-break: break-all;
  user-select: all;
}

.code-input {
  margin-bottom: 16px;
}

.code-input :deep(.el-input__wrapper) {
  background: rgba(255, 255, 255, 0.08);
  box-shadow: 0 0 0 1px rgba(255, 255, 255, 0.14) inset;
}

.code-input :deep(.el-input__inner) {
  color: #fff;
}

.bind-btn {
  width: 100%;
  letter-spacing: 2px;
}
</style>
