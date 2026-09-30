# hk 自动部署（仿照 okx 那套）

push 到 `master` → Actions 检测改动范围 → SSH 上服务器 → git pull → `deploy/deploy.sh` →
后端 rsync + `docker compose up -d --build`；后台 npm build + rsync dist。

## 文件

- `.github/workflows/deploy.yml` — Actions 流程（paths-filter 按目录增量部署）
- `deploy/deploy.sh` — 服务器端脚本，顶部三个路径按需改
- `docker-compose.yml` — 容器 `mingce-app`，host 网络，端口 **8001**（okx 占了 8000）
- `server/Dockerfile` / `server/.dockerignore`
- `server/.env.example` — 环境变量模板
- `.env.prod` — 生产配置（私有仓库直接入库, 改完 push 即生效）

## 服务器一次性准备

```bash
# 1. clone 仓库（部署脚本的 REPO 路径）
mkdir -p /www/wwwroot/hk
git clone <github-repo-url> /www/wwwroot/hk/repo

# 2. 建后端运行目录（.env.prod 已入库, 部署时自动同步, 无需手动建）
mkdir -p /www/wwwroot/shipapi.bdxapi.com

# 3. 服务器装过 docker + rsync + node 即可（okx 已装过的话直接复用）
```

## GitHub 仓库设置

Settings → Secrets and variables → Actions，加三个 secret（和 okx 相同）：

| Secret | 内容 |
|---|---|
| `SERVER_HOST` | 服务器 IP/域名 |
| `SERVER_USER` | SSH 用户名 |
| `SSH_PRIVATE_KEY` | 能登录服务器的私钥（对应公钥在服务器 authorized_keys） |

## 后台管理系统（暂未开发）

后台还不存在，已留好坑：`deploy.yml` 有 `admin/**` 过滤器，`deploy.sh` 的 `deploy_admin`
在 `admin/` 目录出现前自动跳过。以后照 okx 的 admin（Vue3+Vite）建 `admin/` 目录，
push 即自动 build 发布到 `ADMIN_WEB` 目录，无需再改流程。
