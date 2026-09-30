<script setup>
const stats = [
  { title: '总用户数', value: '1,280', icon: 'User', color: '#409eff' },
  { title: '今日新增', value: '36', icon: 'TrendCharts', color: '#67c23a' },
  { title: '订单总数', value: '8,542', icon: 'ShoppingCart', color: '#e6a23c' },
  { title: '邀请返佣总额', value: '¥ 12,300', icon: 'Money', color: '#f56c6c' },
]
</script>

<template>
  <el-row :gutter="16">
    <el-col v-for="item in stats" :key="item.title" :xs="24" :sm="12" :md="6">
      <el-card shadow="hover" class="stat-card">
        <div class="stat-body">
          <el-icon :size="36" :color="item.color"><component :is="item.icon" /></el-icon>
          <div>
            <div class="stat-value">{{ item.value }}</div>
            <div class="stat-title">{{ item.title }}</div>
          </div>
        </div>
      </el-card>
    </el-col>
  </el-row>
</template>

<style scoped>
.stat-card {
  margin-bottom: 16px;
}

.stat-body {
  display: flex;
  align-items: center;
  gap: 16px;
}

.stat-value {
  font-size: 24px;
  font-weight: 600;
  color: #303133;
}

.stat-title {
  font-size: 13px;
  color: #909399;
  margin-top: 4px;
}
</style>
