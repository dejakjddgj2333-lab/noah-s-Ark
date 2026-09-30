#!/bin/bash
# 服务器端部署脚本:GitHub Actions SSH 进来执行
# 用法: bash deploy/deploy.sh [backend|admin|all...]
# 不传参或传 all = 全量;否则只部署指定目标
set -e

# ---- 服务器路径（按需修改）----
REPO=/www/wwwroot/hk/repo        # 仓库 clone 位置
APP_DIR=/www/wwwroot/hk/mingce   # 后端运行目录
ADMIN_WEB=/www/wwwroot/hk/admin  # 后台静态站点发布目录（宝塔站点根）

echo "==> git pull"
cd "$REPO"
git pull origin master

deploy_backend() {
  echo "==> 后端:同步代码 + 重建容器"
  rsync -a --delete "$REPO/server/" "$APP_DIR/server/"
  rsync -a "$REPO/docker-compose.yml" "$REPO/.env.prod" "$APP_DIR/"
  cd "$APP_DIR"
  docker compose up -d --build
  docker image prune -f
}

deploy_admin() {
  if [ ! -d "$REPO/admin" ]; then
    echo "==> 后台:admin/ 尚不存在,跳过"
    return
  fi
  echo "==> 后台:build + 发布"
  cd "$REPO/admin"
  npm ci
  npm run build
  rsync -a --delete --exclude='.user.ini' --exclude='.htaccess' "$REPO/admin/dist/" "$ADMIN_WEB/"
}

TARGETS="$*"
if [ -z "$TARGETS" ] || [ "$TARGETS" = "all" ]; then
  TARGETS="backend admin"
fi

for t in $TARGETS; do
  case "$t" in
    backend)  deploy_backend ;;
    admin)    deploy_admin ;;
    *) echo "未知目标: $t" >&2; exit 1 ;;
  esac
done

echo "==> 完成: $TARGETS"
