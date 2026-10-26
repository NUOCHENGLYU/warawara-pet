# Phase 8C — 本体变身漂流瓶（交付说明）

Branch `phase8/bottle-mail` · 本阶段实现「有未读信时 Warawara 本体连续变成漂流瓶，读完最后一封后连续变回」。

## 架构

- `BottleMail/BottleVisualCoordinator.swift`
  - 独立视觉状态机 `BottleVisualState`：`normal / transformingToBottle / bottleIdle / bottleOpening / reading / transformingBack / suspended`。不与 `PetState` 合并，只与现有姿态系统组合。
  - 统一变形参数 `morphProgress`（0=本体，1=瓶子），由时间 + 平滑缓动（smoothstep）驱动；反向变身复用同一参数，方向切换时按当前进度反推起始时间——**中断/反向/继续均无跳帧**。
  - 冲突门：睡眠/拖拽/生日/Meteor/群体/生日信打开期间延迟变身；变形中途被打断则冻结进度、空闲后无缝继续。
  - 投递语义：一次变身承载多封未读信；变形完成即按 `deliveryQueue` 协议 ACK（`acknowledgeDelivery`，持久化、重启不重复投递）；瓶子已成形期间新来信立即 ACK 并追加阅读队列，不二次变身。
  - 阅读语义：`已接收/已呈现/已阅读/已读完` 分离。只有明确「收好这封信」才完成阅读；关窗不读完保持未读；最后一封收好后开始反向变身。**不因 `unreadCount == 0` 单独触发视觉切换**——必须走收好流程。
  - 尊重 macOS「减少动态效果」：仅关闭装饰性漂浮倾斜，变身本体保留。
- `BottleMail/BottleReadingWindowController.swift`
  - 信纸式阅读界面：收藏列表 + 完整正文（中文/英文/Emoji/换行/滚动/可选中）、「收好这封信」明确操作、关闭不标记已读、撤销授权后仍可离线读完（本地完成，不发网络）。
  - 阅读窗口可成为 key（用户主动操作）；桌宠面板本身依旧永不抢焦点。
- `Art/BottleVisuals.swift`
  - 程序化占位瓶子（玻璃瓶身/瓶颈/瓶塞/卷纸），参数即接口：`morphProgress`、`openingProgress`。
  - **美术接入点**：收到 `Warawara_BottleMail_Phase8C_Art_v1.zip` 后按此文件头部注释的分层规范替换，参数与图层顺序（玻璃在角色之后、瓶颈/瓶塞/卷纸在前、脸在瓶面上）为约定，占位并非最终设计。
  - `BottleMetrics.fitsInWindow()` 保证瓶颈+瓶塞+漂浮余量不超过窗口顶部（有单测守护）。
- `BottleMail/BottleMailCoordinator.swift`（8C 语义改动）
  - `markOpened` 改为**本地优先**：立即持久化本地已读（离线不卡视觉），服务器 `/open` 保留 8B 的异步/幂等/可重试机制，恢复联网后自动对账并把服务器 `opened_at` 写回。
- 渲染管线接入（`PetView` / `WarawaraExpressionSystem` / `WarawaraLayeredCharacterView`）
  - `bottleMorphProgress` 进入表达式输入，映射器把瓶子姿态混合进现有参数（本体轮廓交接给玻璃，眼睛/嘴巴保留身份连续性）；新增 `bodyOpacity` 参数让身体 PNG 与玻璃连续交叉淡化。原有 Rig 与美术零改动。
  - 单击瓶身 → 开瓶 → 阅读窗口；拖拽照旧；双击在瓶子形态下被消费，不与生日信双击叠触发；右键仍是信箱。

## 测试

- `BottleMorphMathTests`：缓动端点/单调、双向可逆连续（反转瞬间值不变）、瓶子包络不越窗。
- `BottleVisualCoordinatorTests`（接真实 `BottleMailCoordinator` + mock 传输 + 临时文件存储）：
  一封来信完整流程（变身→呈现→ACK→开瓶→读完→恢复）；多封只变一次、按序读；关窗不读完不提前恢复；阅读中来新信保持瓶子；忙时延迟、变形中冻结/续接；带未读信重启直接进入瓶子且不重复投递；离线读完本地完成、联网后对账；减少动态效果关闭漂浮；点击消费规则。
- `BottleMailCoordinatorTests` 更新为本地优先语义（离线立即读完 + 自动对账 + 服务器时间戳写回 + 重启重交）。
- CI 新增 `BottlePreviewGeneratorTests`：真实 Rig + 瓶子层的连续变形帧（00–06）、封口/开瓶两态、阅读窗口，产物 `WarawaraPet-Bottle-Preview`。

## Mac 真机验收操作

1. 安装 zip 里的 app（右键打开）；先用右键 → Bottle Mail → 绑定设备（激活码）。
2. 发信网页发一封信 → 桌宠空闲时自动变瓶（约 1.5 秒，无跳帧）；变完瓶颈+瓶塞可见、轻微漂浮。
3. 单击瓶身 → 开瓶 → 阅读窗口出现；滚动/选中正文；点「收好这封信」→ 变回 Warawara（约 1.5 秒）。
4. 多封一起发 → 只变一次；逐封收好；中途关闭阅读窗口 → 保持瓶子、信件仍未读；再次点瓶身继续。
5. 拖拽瓶子（变形中拖拽 → 冻结；松手继续）；睡眠中来信 → 不抢醒、醒来后变形；生日（10 月 17 或 `--replay-birthday`）、Meteor（22:17 或 `--replay-meteor`）期间延迟变身。
6. 断网发信/读信 → 本地完成阅读并变回；恢复网络后自动对账（`--bottle-diagnose` 可看 unread 数）。
7. 系统设置开启「减少动态效果」→ 漂浮倾斜消失、变形仍播放。
8. 瓶颈顶部不被窗口裁切（多显示器、不同分辨率各试一次）。

## 已知问题 / 未完成

- 瓶子为**程序化占位**；最终视觉等 `Warawara_BottleMail_Phase8C_Art_v1.zip` 交付后按 `Art/BottleVisuals.swift` 分层规范接入（本阶段未做视觉打磨）。
- 旧版单图 sprite/占位渲染分支不参与身体淡化（生产路径为已验收的 Rig，不受影响）。
- 睡眠中的瓶子形态沿用现有状态机（闭眼瓶 + Z），未做专门瓶形睡眠姿态。
- 真实 Mac 上的观感（时长、幅度、低饱和配色）待真机调参。
