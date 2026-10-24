# Bottle Mail — Phase 8A

WarawaraPet 的「漂流瓶来信」：发送者通过私人网页写信，远方朋友 Mac 上的
WarawaraPet 收到后会出现漂流瓶。本目录只包含**云端与发送端**；macOS 接收端
（`BottleMailService` 等模块）属于 Phase 8B，尚未开发。

## 目录结构

```text
Services/BottleMail/
  worker/                 Cloudflare Worker（TypeScript）
    src/                  路由、鉴权、校验、限流、D1 仓储
    migrations/           D1 schema 迁移
    test/                 Vitest 自动化测试（无需 Cloudflare 账号）
    scripts/              本地生成密码哈希的工具
    wrangler.jsonc        Worker + D1 配置
    .env.example          本地开发环境变量模板（不含真实值）
  docs/
    SETUP.md              Windows 上的完整初始化 / 部署 / Secrets / 测试步骤
    API.md                API 契约
    PHASE-8B-PLAN.md      Phase 8B（macOS 接收端）的具体计划
```

## 快速开始（本地测试，不需要 Cloudflare 账号）

```powershell
cd Services/BottleMail/worker
npm install
npm test          # 39 个测试，覆盖登录/CSRF/激活码/去重/分页/已读幂等/限流
npm run typecheck
```

## 关键安全设计

- 发送者密码用 PBKDF2-SHA256（310000 轮）哈希存储，仅存在于 Cloudflare
  Secrets；登录后发 HMAC 签名的 HttpOnly SameSite=Strict Cookie。
- 所有 Cookie 鉴权的 POST 接口都有 CSRF 双重防护（Origin 同源检查 +
  double-submit token）。
- 设备激活码一次性、30 分钟过期、只存哈希；兑换后得到设备令牌，服务端
  只存令牌的 SHA-256 哈希，可随时撤销。
- 设备令牌只读：只能拉取与确认打开，不能发信。
- 日志不输出正文、密码、令牌、激活码。
