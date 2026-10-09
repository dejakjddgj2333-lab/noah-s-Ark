<script setup>
import { reactive, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { login } from '@/api/user'
import { useUserStore } from '@/store/user'

const route = useRoute()
const router = useRouter()
const userStore = useUserStore()

const formRef = ref()
const loading = ref(false)

const form = reactive({
  username: '',
  password: '',
  totp_code: '',
})

const rules = {
  username: [{ required: true, message: '请输入用户名', trigger: 'blur' }],
  password: [{ required: true, message: '请输入密码', trigger: 'blur' }],
}

async function handleSubmit() {
  await formRef.value.validate()
  loading.value = true
  try {
    const res = await login(form)
    userStore.setToken(res.token)
    if (res.need_totp) {
      // 未绑谷歌验证: 先去绑定, 绑完才能进后台
      userStore.setNeedTotp(true)
      ElMessage.warning('首次登录请绑定谷歌验证器')
      router.push('/bind-totp')
      return
    }
    userStore.setNeedTotp(false)
    try {
      await userStore.fetchMe()
    } catch {
      userStore.logout()
      ElMessage.error('该账号无后台管理权限')
      return
    }
    ElMessage.success('登录成功')
    router.push(route.query.redirect || '/dashboard')
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <div class="login-page">
    <div class="login-glow glow-a" />
    <div class="login-glow glow-b" />
    <div class="login-card">
      <div class="login-brand">
        <div class="brand-mark">NA</div>
        <h2 class="login-title">Noah's Ark 运营后台</h2>
        <p class="login-sub">链上资产 · 邀请返佣 · 运营管理平台</p>
      </div>
      <el-form ref="formRef" :model="form" :rules="rules" size="large" @keyup.enter="handleSubmit">
        <el-form-item prop="username">
          <el-input v-model="form.username" placeholder="用户名" :prefix-icon="'User'" />
        </el-form-item>
        <el-form-item prop="password">
          <el-input
            v-model="form.password"
            type="password"
            placeholder="密码"
            show-password
            :prefix-icon="'Lock'"
          />
        </el-form-item>
        <el-form-item prop="totp_code">
          <el-input
            v-model="form.totp_code"
            placeholder="谷歌验证码 (已绑定验证器的管理员必填)"
            maxlength="8"
            :prefix-icon="'Key'"
          />
        </el-form-item>
        <el-button type="primary" class="login-btn" :loading="loading" @click="handleSubmit">
          登 录
        </el-button>
      </el-form>
    </div>
  </div>
</template>

<style scoped>
.login-page {
  position: relative;
  height: 100%;
  display: flex;
  align-items: center;
  justify-content: center;
  background: radial-gradient(1200px 600px at 20% 10%, #1b2452 0%, #0b1026 55%, #070b1c 100%);
  overflow: hidden;
}

.login-glow {
  position: absolute;
  border-radius: 50%;
  filter: blur(90px);
  opacity: 0.5;
}

.glow-a {
  width: 420px;
  height: 420px;
  background: #4c6fff;
  top: -120px;
  right: -80px;
}

.glow-b {
  width: 360px;
  height: 360px;
  background: #8a5cff;
  bottom: -140px;
  left: -60px;
}

.login-card {
  position: relative;
  width: 400px;
  padding: 40px 36px;
  border-radius: 18px;
  background: rgba(255, 255, 255, 0.06);
  border: 1px solid rgba(255, 255, 255, 0.12);
  backdrop-filter: blur(20px);
  box-shadow: 0 24px 64px rgba(4, 8, 28, 0.6);
}

.login-brand {
  text-align: center;
  margin-bottom: 28px;
}

.brand-mark {
  width: 52px;
  height: 52px;
  margin: 0 auto 14px;
  border-radius: 14px;
  background: linear-gradient(135deg, #4c6fff, #8a5cff);
  color: #fff;
  font-size: 20px;
  font-weight: 700;
  display: flex;
  align-items: center;
  justify-content: center;
  box-shadow: 0 8px 24px rgba(76, 111, 255, 0.5);
}

.login-title {
  color: #fff;
  font-size: 20px;
  font-weight: 600;
  letter-spacing: 0.5px;
}

.login-sub {
  margin-top: 6px;
  color: rgba(255, 255, 255, 0.45);
  font-size: 12px;
  letter-spacing: 2px;
}

.login-card :deep(.el-input__wrapper) {
  background: rgba(255, 255, 255, 0.08);
  box-shadow: 0 0 0 1px rgba(255, 255, 255, 0.14) inset;
}

.login-card :deep(.el-input__inner) {
  color: #fff;
}

.login-card :deep(.el-input__inner::placeholder) {
  color: rgba(255, 255, 255, 0.4);
}

.login-btn {
  width: 100%;
  height: 44px;
  font-size: 15px;
  letter-spacing: 6px;
}
</style>
