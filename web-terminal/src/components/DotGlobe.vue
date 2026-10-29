<script setup>
// 3D 点阵地球背景: canvas 手绘, 无依赖
// 点阵球体 + 经纬网格 + 轨道环 + 弧光连线(带数据包) + 脉冲节点 + 星空 + 大气辉光
import { onMounted, onBeforeUnmount, ref } from 'vue'

const el = ref(null)
let raf = 0
let ro = null

onMounted(() => {
  const canvas = el.value
  const ctx = canvas.getContext('2d')
  const dpr = Math.min(window.devicePixelRatio || 1, 2)

  // 斐波那契球面均匀布点
  const N = 1500
  const pts = []
  const golden = Math.PI * (3 - Math.sqrt(5))
  for (let i = 0; i < N; i++) {
    const y = 1 - (i / (N - 1)) * 2
    const r = Math.sqrt(1 - y * y)
    const th = golden * i
    pts.push({ x: Math.cos(th) * r, y, z: Math.sin(th) * r, cyan: Math.random() < 0.18 })
  }
  // 弧光连线 (随机点对, 沿球面抬高)
  const ARCS = 16
  const arcs = []
  for (let i = 0; i < ARCS; i++) {
    arcs.push({
      a: Math.floor(Math.random() * N),
      b: Math.floor(Math.random() * N),
      t: Math.random(), // 数据包进度
      speed: 0.25 + Math.random() * 0.35,
    })
  }
  // 脉冲节点
  const pulses = []
  for (let i = 0; i < 10; i++) pulses.push({ idx: Math.floor(Math.random() * N), t: Math.random() * Math.PI * 2 })
  // 星空 (屏幕固定)
  const stars = []
  for (let i = 0; i < 90; i++) {
    stars.push({ x: Math.random(), y: Math.random(), r: 0.4 + Math.random() * 0.9, tw: Math.random() * Math.PI * 2 })
  }
  // 经纬网格 (单位球采样点列)
  const SEG = 72
  const grat = []
  for (let lon = 0; lon < 12; lon++) {
    // 经线
    const phi = (lon / 12) * Math.PI * 2
    const line = []
    for (let s = 0; s <= SEG; s++) {
      const th = (s / SEG) * Math.PI * 2
      line.push({ x: Math.cos(phi) * Math.sin(th), y: Math.cos(th), z: Math.sin(phi) * Math.sin(th) })
    }
    grat.push(line)
  }
  for (let lat = -2; lat <= 2; lat++) {
    // 纬线
    const y = Math.sin((lat / 6) * Math.PI)
    const r = Math.sqrt(1 - y * y)
    const line = []
    for (let s = 0; s <= SEG; s++) {
      const phi = (s / SEG) * Math.PI * 2
      line.push({ x: r * Math.cos(phi), y, z: r * Math.sin(phi) })
    }
    grat.push(line)
  }

  let w = 0
  let h = 0
  function resize() {
    const rect = canvas.parentElement.getBoundingClientRect()
    w = rect.width
    h = rect.height
    canvas.width = w * dpr
    canvas.height = h * dpr
    canvas.style.width = `${w}px`
    canvas.style.height = `${h}px`
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
  }
  resize()
  ro = new ResizeObserver(resize)
  ro.observe(canvas.parentElement)

  const tilt = -0.35 // 自转轴倾角
  let rot = 0
  let last = performance.now()

  function project(p, R, cx, cy) {
    // 绕 Y 轴自转
    const cosR = Math.cos(rot)
    const sinR = Math.sin(rot)
    const x1 = p.x * cosR - p.z * sinR
    const z1 = p.x * sinR + p.z * cosR
    // 绕 X 轴倾斜
    const cosT = Math.cos(tilt)
    const sinT = Math.sin(tilt)
    const y2 = p.y * cosT - z1 * sinT
    const z2 = p.y * sinT + z1 * cosT
    return { sx: cx + x1 * R, sy: cy + y2 * R, z: z2 }
  }

  function frame(now) {
    const dt = Math.min((now - last) / 1000, 0.05)
    last = now
    rot += dt * 0.25 // 转速
    ctx.clearRect(0, 0, w, h)

    const R = Math.min(w, h) * 0.42
    const cx = w / 2
    const cy = h / 2
    const time = now / 1000

    // 星空
    for (const st of stars) {
      const a = 0.10 + 0.12 * (Math.sin(time * 0.8 + st.tw) + 1) / 2
      ctx.beginPath()
      ctx.arc(st.x * w, st.y * h, st.r, 0, Math.PI * 2)
      ctx.fillStyle = `rgba(150, 175, 255, ${a})`
      ctx.fill()
    }

    // 大气辉光
    const glow = ctx.createRadialGradient(cx, cy, R * 0.55, cx, cy, R * 1.45)
    glow.addColorStop(0, 'rgba(46, 92, 255, 0.10)')
    glow.addColorStop(0.75, 'rgba(46, 92, 255, 0.05)')
    glow.addColorStop(1, 'rgba(46, 92, 255, 0)')
    ctx.fillStyle = glow
    ctx.fillRect(cx - R * 1.5, cy - R * 1.5, R * 3, R * 3)

    // 轨道环
    ctx.save()
    ctx.strokeStyle = 'rgba(46, 92, 255, 0.16)'
    ctx.lineWidth = 1
    ctx.beginPath()
    ctx.ellipse(cx, cy, R * 1.35, R * 0.42, -0.4, 0, Math.PI * 2)
    ctx.stroke()
    ctx.beginPath()
    ctx.ellipse(cx, cy, R * 1.5, R * 0.5, 0.35, 0, Math.PI * 2)
    ctx.stroke()
    ctx.restore()

    // 经纬网格
    for (const line of grat) {
      ctx.beginPath()
      let started = false
      let zSum = 0
      for (const p of line) {
        const s = project(p, R, cx, cy)
        zSum += s.z
        if (s.z < -0.05) {
          started = false
          continue
        }
        if (started) ctx.lineTo(s.sx, s.sy)
        else ctx.moveTo(s.sx, s.sy)
        started = true
      }
      const depth = (zSum / line.length + 1) / 2
      ctx.strokeStyle = `rgba(46, 92, 255, ${0.05 + depth * 0.10})`
      ctx.lineWidth = 0.6
      ctx.stroke()
    }

    // 弧光 + 数据包
    for (const arc of arcs) {
      const pa = project(pts[arc.a], R, cx, cy)
      const pb = project(pts[arc.b], R, cx, cy)
      const mx = (pa.sx + pb.sx) / 2
      const my = (pa.sy + pb.sy) / 2
      const qx = cx + (mx - cx) * 1.18
      const qy = cy + (my - cy) * 1.18
      const visible = pa.z > -0.2 || pb.z > -0.2
      if (visible) {
        ctx.beginPath()
        ctx.moveTo(pa.sx, pa.sy)
        ctx.quadraticCurveTo(qx, qy, pb.sx, pb.sy)
        ctx.strokeStyle = 'rgba(34, 211, 238, 0.16)'
        ctx.lineWidth = 0.8
        ctx.stroke()
      }
      // 数据包沿弧线跑
      arc.t = (arc.t + dt * arc.speed) % 1
      const t = arc.t
      const u = 1 - t
      const bx = u * u * pa.sx + 2 * u * t * qx + t * t * pb.sx
      const by = u * u * pa.sy + 2 * u * t * qy + t * t * pb.sy
      ctx.beginPath()
      ctx.arc(bx, by, 1.6, 0, Math.PI * 2)
      ctx.fillStyle = 'rgba(34, 211, 238, 0.85)'
      ctx.fill()
      ctx.beginPath()
      ctx.arc(bx, by, 4, 0, Math.PI * 2)
      ctx.fillStyle = 'rgba(34, 211, 238, 0.18)'
      ctx.fill()
    }

    // 点阵
    for (const p of pts) {
      const s = project(p, R, cx, cy)
      const depth = (s.z + 1) / 2 // 0 背面 -> 1 正面
      const alpha = 0.14 + depth * 0.8
      const size = 0.7 + depth * 1.4
      ctx.beginPath()
      ctx.arc(s.sx, s.sy, size, 0, Math.PI * 2)
      ctx.fillStyle = p.cyan ? `rgba(34, 211, 238, ${alpha})` : `rgba(110, 152, 255, ${alpha})`
      ctx.fill()
    }

    // 脉冲节点
    for (const pu of pulses) {
      pu.t += dt * 2.2
      const s = project(pts[pu.idx], R, cx, cy)
      if (s.z < 0) continue
      const k = (Math.sin(pu.t) + 1) / 2
      ctx.beginPath()
      ctx.arc(s.sx, s.sy, 2 + k * 2.2, 0, Math.PI * 2)
      ctx.fillStyle = `rgba(0, 227, 136, ${0.25 + k * 0.55})`
      ctx.fill()
      ctx.beginPath()
      ctx.arc(s.sx, s.sy, 5 + k * 7, 0, Math.PI * 2)
      ctx.strokeStyle = `rgba(0, 227, 136, ${0.25 * (1 - k)})`
      ctx.lineWidth = 1
      ctx.stroke()
    }

    raf = requestAnimationFrame(frame)
  }
  raf = requestAnimationFrame(frame)
})

onBeforeUnmount(() => {
  cancelAnimationFrame(raf)
  ro && ro.disconnect()
})
</script>

<template>
  <canvas ref="el" class="absolute inset-0 pointer-events-none"></canvas>
</template>
