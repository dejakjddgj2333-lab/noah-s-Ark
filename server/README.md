# 明策 MINGCE 后端 (hk/server)

FastAPI + SQLAlchemy 2.0 (async)。参考 `okx/backend` 精简，只含认证、资讯、行情。

## 与 okx 项目的关系

- **共用数据库**: `DATABASE_URL` 指向同一 PostgreSQL。hk **只读** okx 的资讯/行情表
  (`news_articles` 等), 采集与迁移归 okx 后端管。
- **hk 自有表**带 `hk_` 前缀 (`hk_users`, `hk_email_codes`), 迁服拆分时
  只导出 hk_* 表 + 切库即可。
- 资讯/行情采集 (APITube / OKX / CoinGlass) 仍由 okx 后端跑, hk 不重复采集。

## 启动

```bash
pip install -r requirements.txt
cp .env.example .env   # 填 SECRET_KEY / SMTP / COINGLASS_API_KEY
python -m uvicorn app:app --port 8000
```

## API

认证:
- `POST /api/auth/send-email-code` — 注册验证码 (SMTP 未配置时 dev 回显 `debug_code`)
- `POST /api/auth/register` — 用户名+密码+邮箱+验证码, 验证通过自动绑定邮箱
- `POST /api/auth/login` — 用户名+密码 → JWT
- `GET /api/auth/me`

资讯 (共享库只读):
- `GET /api/news?category=&lang=&page=&page_size=`
- `GET /api/news/{id}`

行情 (OKX 公共 REST 代理):
- `GET /api/market/tickers?inst_type=SPOT|SWAP`
- `GET /api/market/ticker/{inst_id}` / `candles/{inst_id}` / `funding-rate/{inst_id}`

大盘指标 (CoinGlass 透传 + TTL 缓存):
- `GET /api/market-overview/sentiment` / `liquidations/exchange-list` /
  `funding/exchange-rates` / `whale-alerts`
