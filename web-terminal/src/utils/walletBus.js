import { ref } from 'vue'

// 钱包数据刷新信号: 服务端 deposit_credited 推送后 bump,
// 资产/充值页 watch 重拉余额与记录 (对齐 app 侧 WalletRefresh).
export const walletRefreshTick = ref(0)

export function bumpWalletRefresh() {
  walletRefreshTick.value++
}
