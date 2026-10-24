# Bottle Mail — Windows 初始化与部署（需要你本人执行）

以下步骤需要 **Cloudflare 账号（免费额度即可）**。这些步骤我没有也不能替你
执行：登录、创建数据库、配置 Secrets、部署都是账号持有者的操作。完成后请
把 Worker 的访问地址（例如 `https://bottlemail.<你的子域>.workers.dev`）发给
我，Phase 8B 会用到。

## 0. 前置条件

- Windows + Node.js ≥ 18（本仓库验证过 Node 24）
- 一个 Cloudflare 账号（dash.cloudflare.com）
- 本目录：`Services/BottleMail/worker`

`wrangler` 已作为 devDependency 锁定在 `package.json` / `package-lock.json`
中，**不需要全局安装**：下面的 `npx wrangler ...` 会自动使用本地版本。

## 1. 全新克隆后的自检（不需要 Cloudflare 账号）

```powershell
cd Services/BottleMail/worker
npm ci
npm run typecheck
npm test          # 52 个测试：含 Miniflare 真实 D1(SQLite) 集成测试与 XSS 测试
```

## 2. 登录 Wrangler（需要浏览器授权）

```powershell
npx wrangler login
```

## 3. 生成发送者密码哈希（在本机完成，密码不出本机）

```powershell
node scripts/hash-password.mjs
```

输入你想用的发送密码——**输入过程不会在终端回显**（脚本使用 raw 模式直接
读取按键），密码也不会写入任何文件或日志。脚本输出
`SENDER_PASSWORD_SALT` 和 `SENDER_PASSWORD_HASH` 两个十六进制值。请妥善
保存——它们只会在第 5 步配置 Secrets 时用到。

## 4. 创建 D1 数据库

```powershell
npx wrangler d1 create bottlemail-db
```

输出中会有一个 `database_id`。把它填进 `wrangler.jsonc` 的
`"database_id": "REPLACE_WITH_DATABASE_ID"`。

> 注意：必须先完成这一步，再进行第 5、6 步。`wrangler secret put`
> 可能触发一次发布；先填好 `wrangler.jsonc`（含 D1 绑定）可以保证任何
> 一次自动发布都是完整配置。

## 5. 配置 Secrets（生产）

```powershell
npx wrangler secret put SESSION_SECRET        # 任意 64 位随机十六进制
npx wrangler secret put SENDER_PASSWORD_SALT  # 第 3 步生成的值
npx wrangler secret put SENDER_PASSWORD_HASH  # 第 3 步生成的值
```

（可以顺手执行 `node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"`
生成 SESSION_SECRET。）

## 6. 应用数据库迁移（生产必须显式 --remote）

```powershell
npx wrangler d1 migrations apply bottlemail-db --remote
```

> 当前 wrangler 版本**不会**在省略参数时自动选择远端：不加 `--remote`
> 时可能落到本地模拟环境或直接报错。请始终显式指定。本地联调使用：
> `npx wrangler d1 migrations apply bottlemail-db --local`

## 7. 部署

```powershell
npm run deploy        # 等价于 npx wrangler deploy（本地二进制）
```

部署完成后会打印 Worker 的访问地址。浏览器打开该地址即是发信网页。

> 首次部署顺序总结：**填 database_id → 配置全部 Secrets → 迁移 --remote
> → 首次 deploy**。不要在 Secrets 配齐前让服务处于可访问状态；如果
> 服务在 Secrets 缺失时收到请求，登录接口会返回 500 `misconfigured`
> 而不是泄露任何信息。

## 8. 本地联调（可选）

```powershell
Copy-Item .env.example .dev.vars   # 填入本地测试用的假 Secret
npm run dev                        # http://127.0.0.1:8787
npx wrangler d1 migrations apply bottlemail-db --local
```

`.dev.vars` 已被 .gitignore 排除，不会提交。

## 9. 端到端验证方法

1. 浏览器打开 Worker 地址 → 出现登录页 → 用第 3 步的密码登录。
2. 写一封信（试试中文、换行、Emoji）→ 点击「装进漂流瓶」→ 提示已送达。
3. 在「设备激活码」里生成一个码（只显示一次）。
4. 用 curl 模拟接收设备（macOS 端 Phase 8B 的行为）：

```powershell
$code = "刚刚生成的激活码"

# 4a. 兑换激活码，得到设备令牌
$activate = Invoke-RestMethod -Method Post -Uri "https://<worker>/api/devices/activate" `
  -ContentType "application/json" -Body (@{ code = $code } | ConvertTo-Json)
$token = $activate.device_token

# 4b. 拉取消息（轮询）
$headers = @{ Authorization = "Bearer $token" }
$letters = Invoke-RestMethod -Uri "https://<worker>/api/letters?after=0" -Headers $headers
$letters.letters | Format-Table seq, body, opened_at

# 4c. 幂等标记已读
Invoke-RestMethod -Method Post -Uri "https://<worker>/api/letters/$($letters.letters[0].id)/open" -Headers $headers

# 4d. 用同一令牌重复 4b：消息仍在、opened_at 已填——拉取永不删除、不误标已读
Invoke-RestMethod -Uri "https://<worker>/api/letters?after=0" -Headers $headers

# 4e. 用同一激活码再次兑换 → 应返回 409 code_used
Invoke-RestMethod -Method Post -Uri "https://<worker>/api/devices/activate" `
  -ContentType "application/json" -Body (@{ code = $code } | ConvertTo-Json)

# 4f. 设备令牌尝试发信 → 应返回 401（设备是只读身份）
Invoke-RestMethod -Method Post -Uri "https://<worker>/api/letters" -Headers $headers `
  -ContentType "application/json" -Body (@{ body = "冒充发送者" } | ConvertTo-Json)

# 4g. 健康检查（不含任何私密信息）
Invoke-RestMethod -Uri "https://<worker>/health"
```

在管理页「已绑定设备」里点「撤销」后，4b 应返回 401——设备令牌可随时作废。

## 10. 常见问题

- **部署报错 database 不存在**：第 4 步的 `database_id` 没填进
  `wrangler.jsonc`。
- **迁移没有生效**：检查命令是否带 `--remote`（生产）。
- **登录后 403**：网页会自己带 CSRF cookie；只有脚本调用才需要手动带上
  `X-CSRF-Token`（与 `bottlemail_csrf` cookie 一致）。
- **收不到信**：先确认 4b 返回 200 且 `letters` 非空；若为空，用管理页
  「已发出的信」确认发送成功。
- **限流**：登录 15 分钟 10 次 / 发信 10 分钟 30 次 / 激活 10 分钟 10 次
  / 激活码生成 10 分钟 20 次，超限返回 429。登录、激活、发信这三个敏感
  接口使用 **D1 持久化限流**（跨 isolate 生效），其余只读接口使用
  单 isolate 内存限流。
