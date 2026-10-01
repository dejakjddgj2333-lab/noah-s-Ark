<script setup>
import { onMounted, reactive, ref } from 'vue'
import { getUserList } from '@/api/user'

const loading = ref(false)
const list = ref([])
const query = reactive({ page: 1, pageSize: 10, keyword: '' })

// 演示数据，后端接口就绪后删除
const demoList = [
  { id: 1, username: 'zhangsan', nickname: '张三', phone: '138****0001', level: 'VIP1', status: '正常', createdAt: '2026-09-01' },
  { id: 2, username: 'lisi', nickname: '李四', phone: '138****0002', level: 'VIP2', status: '正常', createdAt: '2026-09-02' },
]

async function fetchList() {
  loading.value = true
  try {
    // TODO: 对接后端接口
    // const res = await getUserList(query)
    // list.value = res.list
    list.value = demoList
  } finally {
    loading.value = false
  }
}

onMounted(fetchList)
</script>

<template>
  <el-card>
    <div class="toolbar">
      <el-input
        v-model="query.keyword"
        placeholder="搜索用户名 / 手机号"
        clearable
        style="width: 260px"
        :prefix-icon="'Search'"
        @keyup.enter="fetchList"
      />
      <el-button type="primary" :icon="'Search'" @click="fetchList">查询</el-button>
    </div>

    <el-table v-loading="loading" :data="list" border stripe>
      <el-table-column prop="id" label="ID" width="80" />
      <el-table-column prop="username" label="用户名" />
      <el-table-column prop="nickname" label="昵称" />
      <el-table-column prop="phone" label="手机号" />
      <el-table-column prop="level" label="等级" />
      <el-table-column prop="status" label="状态">
        <template #default="{ row }">
          <el-tag :type="row.status === '正常' ? 'success' : 'danger'">{{ row.status }}</el-tag>
        </template>
      </el-table-column>
      <el-table-column prop="createdAt" label="注册时间" />
      <el-table-column label="操作" width="160">
        <template #default>
          <el-button link type="primary">详情</el-button>
          <el-button link type="warning">编辑</el-button>
        </template>
      </el-table-column>
    </el-table>

    <el-pagination
      v-model:current-page="query.page"
      v-model:page-size="query.pageSize"
      class="pagination"
      layout="total, prev, pager, next"
      :total="list.length"
    />
  </el-card>
</template>

<style scoped>
.toolbar {
  display: flex;
  gap: 12px;
  margin-bottom: 16px;
}

.pagination {
  margin-top: 16px;
  justify-content: flex-end;
}
</style>
