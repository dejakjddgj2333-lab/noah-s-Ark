<script setup>
// 专业 K 线 (lightweight-charts): 蜡烛 + MA5/10/20 + 成交量 + 最新价线 + 高低点标记 + OHLC 悬浮读数
// props.candles: OKX 行升序 [ts, o, h, l, c, vol]; 轴时间按东八区显示 (+8h 平移)
import { onMounted, onBeforeUnmount, ref, watch } from 'vue'
import {
  createChart,
  CandlestickSeries,
  LineSeries,
  HistogramSeries,
  CrosshairMode,
  LineStyle,
  ColorType,
  createSeriesMarkers,
} from 'lightweight-charts'

const props = defineProps({
  candles: { type: Array, default: () => [] },
  magnet: { type: Boolean, default: false }, // 十字光标磁吸模式
})

const el = ref(null)
const legend = ref(null) // { o,h,l,c,vol,chg,up }

let chart = null
let cs = null // 蜡烛
let volS = null
let ma5S = null
let ma10S = null
let ma20S = null
let markersApi = null
let priceLine = null

const TZ = 8 * 3600 // 东八区平移秒数

function pxDec(v) {
  const n = Math.abs(Number(v) || 0)
  if (n >= 1000) return 2
  if (n >= 1) return n >= 100 ? 2 : 4
  return 6
}
const lastDec = ref(2)
function fmtP(v) {
  return Number(v).toLocaleString('en-US', {
    minimumFractionDigits: lastDec.value,
    maximumFractionDigits: lastDec.value,
  })
}

function dataSets() {
  const candleData = []
  const volData = []
  const closes = []
  for (const c of props.candles) {
    const t = Math.floor(+c[0] / 1000) + TZ
    const o = +c[1]
    const h = +c[2]
    const l = +c[3]
    const cl = +c[4]
    candleData.push({ time: t, open: o, high: h, low: l, close: cl })
    volData.push({
      time: t,
      value: +c[5],
      color: cl >= o ? 'rgba(0,227,136,0.5)' : 'rgba(255,95,109,0.5)',
    })
    closes.push({ time: t, value: cl })
  }
  return { candleData, volData, closes }
}

function maData(n, closes) {
  const out = []
  for (let i = n - 1; i < closes.length; i++) {
    let s = 0
    for (let j = 0; j < n; j++) s += closes[i - j].value
    out.push({ time: closes[i].time, value: s / n })
  }
  return out
}

function mkLegend(d) {
  const chg = d.open ? ((d.close - d.open) / d.open) * 100 : 0
  return { ...d, chg, up: chg >= 0 }
}

function apply() {
  if (!chart) return
  const { candleData, volData, closes } = dataSets()
  if (!candleData.length) return
  lastDec.value = pxDec(candleData[candleData.length - 1].close)

  cs.setData(candleData)
  volS.setData(volData)
  ma5S.setData(maData(5, closes))
  ma10S.setData(maData(10, closes))
  ma20S.setData(maData(20, closes))

  // 最新价虚线
  if (priceLine) {
    try { cs.removePriceLine(priceLine) } catch { /* 已移除 */ }
    priceLine = null
  }
  const last = candleData[candleData.length - 1]
  const lastColor = last.close >= last.open ? '#00E388' : '#FF5F6D'
  priceLine = cs.createPriceLine({
    price: last.close,
    color: lastColor,
    lineWidth: 1,
    lineStyle: LineStyle.Dashed,
    axisLabelVisible: true,
    title: '',
  })

  // 最高/最低标记
  let hi = candleData[0]
  let lo = candleData[0]
  for (const d of candleData) {
    if (d.high > hi.high) hi = d
    if (d.low < lo.low) lo = d
  }
  markersApi.setMarkers([
    { time: hi.time, position: 'aboveBar', color: '#9EA0B2', shape: 'arrowDown', text: `高 ${fmtP(hi.high)}` },
    { time: lo.time, position: 'belowBar', color: '#9EA0B2', shape: 'arrowUp', text: `低 ${fmtP(lo.low)}` },
  ])

  legend.value = mkLegend(last)
}

function reset() {
  chart?.timeScale().fitContent()
}
defineExpose({ reset })

watch(() => props.candles, apply, { deep: false })
watch(
  () => props.magnet,
  (m) => chart?.applyOptions({ crosshair: { mode: m ? CrosshairMode.Magnet : CrosshairMode.Normal } }),
)

onMounted(() => {
  chart = createChart(el.value, {
    autoSize: true,
    layout: {
      background: { type: ColorType.Solid, color: 'transparent' },
      textColor: '#9EA0B2',
      fontSize: 10,
      fontFamily: 'JetBrains Mono, monospace',
      attributionLogo: false,
    },
    grid: {
      vertLines: { color: 'rgba(52,65,94,0.25)' },
      horzLines: { color: 'rgba(52,65,94,0.25)' },
    },
    rightPriceScale: { borderColor: '#34415E' },
    timeScale: { borderColor: '#34415E', timeVisible: true, secondsVisible: false, rightOffset: 4 },
    crosshair: { mode: props.magnet ? CrosshairMode.Magnet : CrosshairMode.Normal },
  })

  volS = chart.addSeries(HistogramSeries, {
    priceScaleId: 'vol',
    priceFormat: { type: 'volume' },
  })
  chart.priceScale('vol').applyOptions({ scaleMargins: { top: 0.82, bottom: 0 } })

  cs = chart.addSeries(CandlestickSeries, {
    upColor: '#00E388',
    downColor: '#FF5F6D',
    borderUpColor: '#00E388',
    borderDownColor: '#FF5F6D',
    wickUpColor: '#00E388',
    wickDownColor: '#FF5F6D',
    priceScaleId: 'right',
  })
  chart.priceScale('right').applyOptions({ scaleMargins: { top: 0.08, bottom: 0.22 } })

  const maOpts = { priceLineVisible: false, lastValueVisible: false, crosshairMarkerVisible: false, lineWidth: 1 }
  ma5S = chart.addSeries(LineSeries, { ...maOpts, color: '#F7B733' })
  ma10S = chart.addSeries(LineSeries, { ...maOpts, color: '#B8C3FF' })
  ma20S = chart.addSeries(LineSeries, { ...maOpts, color: '#C26BFF' })

  markersApi = createSeriesMarkers(cs, [])

  // 十字悬浮读数
  chart.subscribeCrosshairMove((param) => {
    const d = param?.seriesData?.get(cs)
    if (d) {
      const v = param.seriesData.get(volS)?.value
      legend.value = { ...mkLegend(d), vol: v }
    } else {
      const { candleData } = dataSets()
      const last = candleData[candleData.length - 1]
      legend.value = last ? mkLegend(last) : null
    }
  })

  apply()
})

onBeforeUnmount(() => {
  chart?.remove()
  chart = null
})
</script>

<template>
  <div class="relative w-full h-full">
    <div ref="el" class="absolute inset-0"></div>
    <!-- OHLC 悬浮读数 -->
    <div
      v-if="legend"
      class="absolute top-2 left-2 z-10 pointer-events-none flex items-center gap-3 px-2.5 py-1 rounded bg-canvas-obsidian/80 border border-hairline font-mono-data text-[11px]"
    >
      <span class="text-steel-muted">开 <span class="text-ink-white">{{ fmtP(legend.open) }}</span></span>
      <span class="text-steel-muted">高 <span class="text-bull-green">{{ fmtP(legend.high) }}</span></span>
      <span class="text-steel-muted">低 <span class="text-bear-red">{{ fmtP(legend.low) }}</span></span>
      <span class="text-steel-muted">收 <span :class="legend.up ? 'text-bull-green' : 'text-bear-red'">{{ fmtP(legend.close) }}</span></span>
      <span :class="legend.up ? 'text-bull-green' : 'text-bear-red'">{{ legend.up ? '+' : '' }}{{ legend.chg.toFixed(2) }}%</span>
      <span v-if="legend.vol != null" class="text-steel-muted">量 <span class="text-ink-white">{{ Number(legend.vol).toLocaleString('en-US') }}</span></span>
    </div>
  </div>
</template>
