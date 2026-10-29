<script setup>
defineProps({
  label: String,
  en: String,
  value: { type: [String, Number], default: '--' },
  tone: { type: String, default: '' }, // up | down | warn | ''
  sub: String,
})
</script>

<template>
  <div class="card stat">
    <div class="stat-label">
      {{ label }}
      <span v-if="en" class="en">{{ en }}</span>
    </div>
    <div class="stat-value mono" :class="tone">{{ value }}</div>
    <div v-if="sub" class="stat-sub muted">{{ sub }}</div>
  </div>
</template>

<style scoped>
.stat { padding: 14px 18px; }
.stat-label { font-size: 12px; color: var(--muted); display: flex; gap: 8px; align-items: baseline; }
.stat-label .en { font-family: var(--font-mono); font-size: 10px; letter-spacing: 0.1em; text-transform: uppercase; }
.stat-value { font-size: 24px; font-weight: 600; margin-top: 6px; }
.stat-sub { font-size: 11px; margin-top: 4px; font-family: var(--font-mono); }
</style>
