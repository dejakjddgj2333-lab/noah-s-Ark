<script setup>
import { onMounted, onBeforeUnmount, ref, watch } from 'vue'
import * as echarts from 'echarts'

const props = defineProps({
  option: { type: Object, required: true },
  height: { type: String, default: '240px' },
})

const el = ref(null)
let chart = null
let ro = null

defineExpose({ getChart: () => chart })

onMounted(() => {
  chart = echarts.init(el.value, null, { renderer: 'canvas' })
  chart.setOption(props.option)
  ro = new ResizeObserver(() => chart && chart.resize())
  ro.observe(el.value)
})

watch(
  () => props.option,
  (opt) => chart && chart.setOption(opt, { notMerge: true }),
  { deep: true }
)

onBeforeUnmount(() => {
  ro && ro.disconnect()
  chart && chart.dispose()
})
</script>

<template>
  <div ref="el" :style="{ height, width: '100%' }"></div>
</template>
