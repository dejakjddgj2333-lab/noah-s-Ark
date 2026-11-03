<script setup>
// 币种图标: OKX CDN 网络图 → 加载失败回退首字母圆 (与 okx 项目一致)
import { computed, ref } from 'vue'
import { coinOf } from '../utils/format'

const props = defineProps({
  instId: { type: String, required: true },
  size: { type: Number, default: 24 },
})

const base = computed(() => coinOf(props.instId).toUpperCase())
const url = computed(() =>
  `https://static.okx.com/cdn/oksupport/asset/currency/icon/${base.value.toLowerCase()}.png`
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
