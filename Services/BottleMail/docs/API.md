# Bottle Mail — API 契约

基础地址：Worker 部署地址（HTTPS）。所有响应为 JSON；时间一律 UTC ISO 8601
字符串。除 `/health`、`/api/session`、`/api/devices/activate` 与网页本身外，
其余接口都需要身份：

- **发送者**：`Cookie: bottlemail_session=<签名会话>`；所有 POST 还需
  `X-CSRF-Token`（等于 `bottlemail_csrf` cookie）且 Origin 同源。
- **接收设备**：`Authorization: Bearer <device_token>`。

## 数据模型

```text
letters:            seq(自增游标) id(UUID) body created_at opened_at client_request_id
devices:            id label created_at revoked_at token_hash(仅存 SHA-256)
activation_codes:   code_hash(仅存 SHA-256) created_at expires_at used_at device_id
```

## 接口一览

| 方法 | 路径 | 身份 | 说明 |
|---|---|---|---|
| GET | `/health` | 无 | `{ok:true, service:"bottlemail"}`，无任何私密信息 |
| GET | `/` | 无 | 私人发信网页（同源，带 CSRF cookie） |
| POST | `/api/session` | 无（限流 10/15min） | `{password}` → 200 设置会话 Cookie；401 密码错误；429 限流 |
| POST | `/api/session/logout` | 发送者 | 清除会话 Cookie |
| POST | `/api/letters` | 发送者 | `{body, client_request_id?}` → 201 新建；同 `client_request_id` 重试返回 200 + 原信件（`duplicate:true`） |
| GET | `/api/letters?after=<seq>&limit<=50` | 设备 | 按 seq 升序分页，返回 `{letters, next_after}`；拉取不删除、不标记已读 |
| POST | `/api/letters/:id/open` | 设备 | 幂等：首次设置 `opened_at`，重复调用返回 200 + `already_opened:true` |
| POST | `/api/devices/activate` | 无（限流 10/10min） | `{code, label?}` → 201 `{device_id, device_token}`；401 无效码 / 409 已用 / 410 过期 |
| POST | `/api/admin/activation-codes` | 发送者 | 生成一次性激活码，明文**仅此一次**返回 |
| GET | `/api/admin/activation-codes` | 发送者 | 码列表（只有哈希，无明文） |
| GET | `/api/admin/devices` | 发送者 | 设备列表 |
| POST | `/api/admin/devices/:id/revoke` | 发送者 | 撤销设备令牌（立即失效） |
| GET | `/api/admin/letters` | 发送者 | 最近 100 封 + opened_at 状态 |

## 正文校验

- UTF-8 文本，支持中文 / 英文 / 换行 / Emoji；长度 1–2000（去首尾空白后）。
- `client_request_id` 必须为 UUID（防网络重试重复发信）；缺省则不参与去重。

## 激活码规则

- 10 位、字符集 `ABCDEFGHJKMNPQRSTUVWXYZ23456789`（排除易混淆字符），
  由 CSPRNG 生成；仅存 SHA-256 哈希；30 分钟过期；兑换一次即作废。

## 错误响应

统一形如 `{"error":"code"}`：`bad_json` / `password_required` /
`invalid_password` / `too_many_attempts` / `too_many_requests` / `csrf` /
`unauthorized` / `invalid_code` / `code_used` / `code_expired` /
`invalid_cursor` / `invalid_limit` / `not_found` / `misconfigured` /
`internal_error`。
