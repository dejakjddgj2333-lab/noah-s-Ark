<script setup>
// 币种图标: 自有服务端缓存图 (服务端代取 OKX 并落盘, 国内直连 OKX CDN 不稳)
// → 加载失败回退首字母圆
import { computed, ref } from 'vue'
import { coinOf } from '../utils/format'

// 与 api/request.js 同一套 base 判定: dev 走 vite 代理, 生产直连后端
const API_BASE =
  import.meta.env.VITE_API_BASE ||
  (import.meta.env.DEV ? '/api' : 'https://shipapi.bdxapi.com/api')

const props = defineProps({
  instId: { type: String, required: true },
  size: { type: Number, default: 24 },
})

const base = computed(() => coinOf(props.instId).toUpperCase())
const url = computed(() =>
  `${API_BASE}/coin-icon/${base.value.toLowerCase()}.png`
)

const loaded = ref(false)
const broken = ref(false)
</script>

<template>
  <span
    class="relative inline-block rounded-full overflow-hidden bg-surface-slate border border-hairline shrink-0 select-none"
    :style="{ width: size + 'px', height: size + 'px' }"
  >
    <!-- 字母占位: 图加载成功后盖住 -->
    <span
      class="absolute inset-0 flex items-center justify-center font-bold text-steel-muted uppercase"
      :style="{ fontSize: Math.round(size * 0.42) + 'px' }"
    >{{ base.slice(0, 1) }}</span>
    <img
      v-if="!broken"
      :src="url"
      :alt="base"
      loading="lazy"
      class="absolute inset-0 w-full h-full transition-opacity duration-150"
      :style="{ opacity: loaded ? 1 : 0 }"
      @load="loaded = true"
      @error="broken = true"
    />
  </span>
</template>
