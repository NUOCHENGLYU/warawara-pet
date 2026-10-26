# Phase 8C — 本体变身漂流瓶（正式美术接入 v3）

Branch `phase8/bottle-mail` · 有未读信时 Warawara 本体连续变成漂流瓶（普通、非拟人化：无眼睛嘴巴表情），读完并收好全部信件后连续变回。

## 美术

正式采用 `art_handoff/Warawara_BottleMail_Phase8C_Ghibli_Minimal_v3`（v1/v2 全部弃用）：
- 素材随包分发：`Resources/BottleMail/`（SwiftPM `.copy`，打包后经 `Bundle.module` / main bundle 解析，`--verify-bottle-art` 在打包 App 内验证）。
- `BottleMailArtStore`：加载 + 缺失诊断（`ART_MISSING` 事件）+ 透明内容测量；素材缺失时**回退到程序化占位瓶**，桌宠不会消失。
- 状态映射：未读/待读 → `bottle_unread.png`；开封/阅读 → `bottle_opening.png`；反向变身 → `bottle_idle.png` 在回收过程中交叉过渡（信已收好=空瓶）；阅读窗口信纸 → `letter_paper_blank.png`（文字由 SwiftUI 动态渲染，不烘焙）；`scroll_sealed.png` 用于阅读窗口的信封徽标。
- `bottle_opening.png` 为整张状态参考图：开封动画 = 同轮廓下 unread→opening 的短交叉过渡 + 整体轻微下沉复位，**不在瓶上叠加卷信**（避免双卷信/双瓶塞）。若未来需要卷信飞出动画，需先对整图做内容感知拆分——记为已知限制。

## 连续变身（非两张 PNG 硬切/淡入淡出）

- 单一可逆参数 `morphProgress`（时间 + smoothstep），状态机与 8C 一致（`normal/transformingToBottle/bottleIdle/bottleOpening/reading/transformingBack/suspended`）。
- `BottleMorphGeometry` 揭示几何：瓶子始终被「底部锚定的圆角矩形揭示区」遮罩，其宽/高/圆角半径/内部图像缩放随进度插值——从 Warawara 身体轮廓（胶囊=身体剪影，起点尺寸取自真实 Rig 体宽）**生长**为完整瓶形；瓶塞随顶部生长出现。
- 表达系统配合（`bottleMorphProgress` 混入 mapper）：身体先收缩再拉伸；`bodyOpacity` 把身体栅格交接给瓶绘；**`faceOpacity` 让眼睛嘴巴在变形中溶解**——瓶子全程无表情；反向完全相同参数反向播放。
- 时长 1.5s（1.2–1.8s 范围内）；冲突（睡眠/拖拽/生日/Meteor/群体/生日信）延迟或冻结，恢复后无缝续接；尊重「减少动态效果」（关闭漂浮倾斜，变身保留）。

## 邮件语义（沿用并保持）

- `已接收/已呈现/已读完` 分离：投递 ACK ≠ 已读；只有「收好这封信」完成阅读（本地优先持久化，服务器 `/open` 异步幂等对账，断网不卡视觉）；多封只变一次、逐封收好；阅读中来新信追加队列、不二次变身；关窗不读完保持未读；重启恢复投递/阅读状态。
- 阅读窗口：信纸背景 + 完整正文（中/英/Emoji/换行/滚动/可选）、逐封浏览、收藏重看、撤销授权离线可读。

## 测试

- 新增：`BottleMailArtStoreTests`（素材加载/1024 尺寸/内容测量/缺失回退/art-vs-procedural 解析）、`BottleMorphGeometryTests`（揭示几何端点/单调/遮罩边界/窗口包络）、`BottleExpressionBlendTests`（面部溶解、身体交接、先压后伸、睡眠下同样无表情、进度连续）、`BottlePreviewGeneratorTests`（真实素材连续变形 **GIF** + 状态单帧 + 阅读窗口）。
- 更新：`BottleMorphMathTests` 窗口包络断言（art + procedural 双路径）。
- 保留全绿：`BottleVisualCoordinatorTests`（状态机/ACK/离线/重启/冲突）与 8B 全部回归。
- CI：打包 App 新增 `--verify-bottle-art` 校验；预览产物 `WarawaraPet-Bottle-Preview`（含 `200-morph.gif`）。

## Mac 真机验收步骤

1. 安装最新 zip；右键宠物 → Bottle Mail → 绑定设备；发信网页发一封信。
2. 桌宠空闲时变瓶（~1.5s）：身体先收缩→拉伸生长出瓶身，眼睛嘴巴溶解，瓶塞随顶部出现，全程无跳帧、无脸残留。
3. 单击瓶身：unread→opening 短过渡 + 轻微下沉，阅读窗口弹出（信纸背景 + 正文）。
4. 「收好这封信」→ 变回 Warawara（反向同参数，回收过程中空瓶替换带信瓶）。
5. 多封：只变一次、逐封收好；中途关窗→保持瓶子未读；阅读中来新信→队列追加。
6. 冲突：拖拽冻结、睡眠不抢醒、`--replay-birthday`/`--replay-meteor` 期间延迟。
7. 断网读完→本地完成并变回，联网自动对账（`--bottle-diagnose`）。
8. 开启「减少动态效果」→ 漂浮消失、变身保留。
9. 多显示器/多分辨率：瓶颈不被窗口顶部裁切。
10. 菜单栏退出、生日双击、右键邮箱、拖拽、睡眠全部照旧。

## 已知问题 / 未完成

- 开封动画目前为同轮廓状态过渡，未做卷信飞出瓶口至阅读窗口的跨窗口动画（`bottle_opening.png` 自带卷信，叠加 `scroll_sealed.png` 会重影；需内容感知拆分——待 ChatGPT 美术提供分层或授权拆分）。
- 变身前后的瓶绘锚定基于 v3 画布内容测量与固定包络常量，真机多分辨率下请以观感为准微调 `BottleMetrics`。
- 程序化占位瓶仅在素材缺失时出现（回退路径，非正式视觉）。
- 真机观感（时长/幅度/饱和）待最终调参。
