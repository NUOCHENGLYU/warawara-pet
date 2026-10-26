# Phase 8C — 本体变身漂流瓶（真机验收问题修复）

Branch `phase8/bottle-mail` · 基于真机（M1 MacBook Air）验收反馈修复：关闭信纸崩溃、瓶子仍执行宠物动作、阅读界面为邮箱分栏。

## P0：关闭信纸导致进程退出（已修复）

- 根因（源码调用链）：`BottleVisualCoordinator.evaluate()` 在 `.reading` 且 `unread == 0` 时调用 `onReadingFinished` → AppDelegate 回调 `readingWindow.closeReadingWindow()` → `window.close()` 触发 `windowWillClose()` → 又调用 `visual.readingWindowClosed()` → 若此时仍为 `.reading` 且 `lastUnread == 0` 再次 `evaluate()` → 无限递归、栈溢出、进程崩溃。
- 修复（新设计）：
  - 删除 `.reading` 状态下因 `unread == 0` 自动关闭窗口的路径与 `onReadingFinished` 回调；**窗口关闭事件是唯一的阅读完成入口**（`windowWillClose` → `visual.readingWindowClosed()`）。
  - `readingWindowClosed()` 先离开 `.reading`（阻断一切重入），再提交本地优先已读（`markOpened`，异步服务器对账不变），然后由 mailbox 发布驱动：`unread > 0` 保持瓶子；`unread == 0` 走 `.bottleIdle` 规则开始反向 Poof。
  - 幂等：重复 `windowWillClose` 因状态守卫变成 no-op；`markOpened` 本身有未读守卫，同一封信绝不重复标记（测试断言 `/open` 恰好一次）。
  - 快速关→再开：`recentlyClosedID` 排除窗口（1.5s 或已读发布后退役），同一封信绝不立即重复打开。
  - 菜单栏退出（`NSApp.terminate`）路径未动；关闭信纸不再触发任何退出/terminate/exit。
- 验证：`BottleReadingWindowIntegrationTests`（真实 NSWindow/NSHostingView 集成）：完整闭环事件顺序 reading→bottleIdle→transformingBack→normal、宠物窗口仍存在、20 次连续开/关（含重复 close）不崩溃；`testWindowCloseIsIdempotentAndNeverReentrant`、`testRapidCloseReopenNeverPresentsTheSameLetter`。

## 静止漂流瓶（已修复）

- `PetController.setBottleModeActive(_:)`：进入瓶子形态时取消全部自主定时器（hop/float 调度、awareness、curiosity、点击回弹、拖拽衰减）并在**所有调度入口加 guard**；不产生 Hop/Float/Curious/Sleep/点击压扁/软体拖拽形变/睡眠 Z/待机 bob/漂浮摇摆；拖拽只改位置（`handleDragMoved` 跳过形变，松手直接落地 idle）。
- 视觉层：`PetView.bobOffset` 在瓶子形态恒 0；`BottleVisualCoordinator.swayEnabled` 恒 false；仅 Poof 时间线保留跳跃/落地惯性；睡眠 Z 双保险屏蔽。
- 来信时正在 Hop/Float：忙碌门新增 `isPetInTransientMotion`，变身等待动作落地，不硬取消。
- 离开瓶子后单调度器恢复（cancel-first 保证不重复注册）。
- 验证：`PetBottleModeTests`（模拟数分钟无动作、各入口 guard、点击无压扁、拖拽无形变、退出后恢复单调度器）。

## 单张信纸阅读界面（已替换邮箱分栏）

- 移除左侧历史列表、HSplitView、工具栏、“收好这封信”按钮与“关闭不标记已读”提示。
- `BottleReadingPaperView`：整窗手绘信纸（`letter_paper_blank.png` 铺满 + 文字动态渲染、安全边距 72pt），隐藏标题 + 透明标题栏 + 保留红绿灯关闭入口 + 右上角关闭按钮，支持 Escape / Cmd+W / 关闭按钮；窗口可获键盘焦点（复用生日信生命周期），中文/英文/Emoji/换行/滚动/文本选择均正常；撤销授权时本地已读且不调用 `/open`。
- **关闭信纸 = 读完当前这封信**：多封逐封点击瓶子阅读；最后一封关闭后自动反向变身并恢复 Warawara 自主行为；已读邮件数据永久保留（不强制展示列表）。
- 验证：`BottleReadingWindowRenderTests` 与预览均改为真实窗口快照逐像素校验（信纸/墨迹/Emoji/无禁止占位符）。

## 历史（前轮基线 `63e7e10`）

> 注意：以下历史记录中「收好这封信按钮 / 关窗不读完」的阅读语义已被上面「单张信纸阅读界面」取代（关闭即读完）；其余（时间线、遮挡、音效、预览）仍有效。

跳跃烟雾变身时间线、遮挡不变式、方向感知音效、正反向 GIF 预览等全部保留。

Branch `phase8/bottle-mail` · 有未读信时 Warawara 本体以「起跳 → 烟雾“嘭” → 烟雾中完成变身 → 漂流瓶轻轻落地」连续变成漂流瓶；读完并收好全部信件后反向（瓶子跃起 → 烟雾中换回 → 落地）变回。

## 动画时间线（1.35s，纯函数驱动，正反向同一参数）

| 时间 | 动作 |
|---|---|
| 0–0.15s | 压扁蓄力（1.07x 宽 × 0.88y 高） |
| 0.15–0.43s | 向上跳跃 30pt（Reduce Motion 14pt），滞空微拉伸 |
| 0.43s | 轻柔“嘭”音效（`soft_poof.wav`，音量 0.25，尊重系统静音与 `warawarapet.sound.enabled`），烟雾迅速出现 |
| 0.43–0.57s | 烟雾膨胀至**完全遮挡**（核心烟层不透明区覆盖两个造型的外轮廓并集——有机器校验） |
| 0.57s | 烟雾后切换素材（Warawara ↔ `bottle_unread.png`），用户不可见 |
| 0.57–1.03s | 烟雾扩散淡去，瓶子从烟云中下降 |
| 1.03–1.35s | 瓶子柔和落地、轻微惯性晃动、稳定 |

反向：瓶子小幅跃起 → 烟雾遮挡时换回 Warawara → 落地，同一 `BottlePoofTimeline` 函数反向求值，天然镜像。

## 关键实现

- `BottlePoofTimeline`（纯函数）：跳跃弧线（蓄力/上升/峰值/隐藏下落切换点/缓降/落地晃动）、压扁-拉伸-落地挤压曲线、核心烟雾透明度/缩放、装饰层扩散、落地尘。**统一时间参数 `t ∈ 0...1`，正反向同式**，无两张 PNG 轮播。
- **遮挡不变式**：`occludedRect(t) ⊇ envelopeRect(t)`（烟雾不透明区覆盖 Warawara 与瓶子外轮廓的并集，含 Reduce Motion 两种设置），由 `BottlePoofTimelineTests.testOcclusionCoversBothSilhouettesAtTheSwitch` 机器校验；底层素材只在 t=0.57 切换（`formProgress` 阶跃），面部/身体交接为**瞬时通道**（不做平滑淡入淡出，杜绝半透明重叠）。
- 烟雾分层：`smoke_core`（不透明遮挡主团）+ `smoke_soft`/`smoke_small`/`smoke_wisps`（扩散装饰）+ `landing_dust`（落地尘），连续缩放/位移/透明度；**全部在现有透明桌宠窗口内渲染**，无独立特效窗口；窗口包络经测试保证瓶颈不越界、落地位置与身体基线一致（切换瞬间的 18pt 高度差发生在满烟雾之后，不可见）。
- 音效：`BottlePoofSound` 每段变身仅触发一次（`onPoofMoment` 回调，正反向各一次）。**触发点按方向区分**：正向在 `poofPoint`（烟雾爆开瞬间），反向在 `smokeFadeEnd`（倒放消散尾的镜像起点，即反向烟雾出现的瞬间）——绝不在烟雾已散尽后迟响。低音量、系统静音自动生效、可关（`warawarapet.sound.enabled`）。
- **邮件语义全部保留**：多封只变一次、阅读中来新信入队不重播变身、投递 ACK ≠ 已读、本地优先离线可读、联网对账、重启恢复；生日/Meteor/拖拽/睡眠冲突期间延迟或冻结。
- Reduce Motion：跳跃 30→14pt、装饰烟雾扩散缩小；核心遮挡烟不变（仍保证无突变切换）。
- 回退链：完整素材 → poof 模式；缺烟雾包 → 几何揭示回退（原 BottleMorphGeometry，仅内部回退）；缺 v3 美术 → 程序化占位瓶。缺音效仅静音跳过。

## 测试

- 新增 `BottlePoofTimelineTests`：相位边界、跳跃弧线（26–32pt/Reduce 14pt）、正反向切换点、**遮挡完整性机器校验**、包络不越窗、落地晃动衰减、烟雾可见窗口。
- 新增视觉测试：`testPoofMomentFiresExactlyOncePerTransition`（正反向各一次、按各自烟雾出现时刻触发、新信不重播）、`testPoofFreezeResumeNeverDuplicatesTheSound`（冻结在音效点前后均不重响）、`testFormProgressStepsOnlyAtTheSmokeCoveredSwitch`。
- 阅读窗口渲染：`BottleReadingWindowRenderTests` 以**真实 NSHostingView + 离屏 NSWindow**（生产宿主路径）渲染完整阅读界面并逐像素校验：信纸背景、正文墨迹（中文/英文/换行）、Emoji 彩色字形、无渲染失败“禁止”占位符。`ImageRenderer` 无法栅格化 AppKit 版 List/HSplitView（会产出 nosign 占位符），预览与校验均改用真实窗口快照——非伪造截图。
- 更新：`BottleExpressionBlendTests`（阶跃语义 + 动画器瞬时交接）、`BottleMailArtStoreTests`（11 项素材、poof/reveal/procedural 三级回退解析）、视觉测试 formProgress 断言。
- 预览：`200-poof-forward.gif` / `201-poof-reverse.gif`（各 30 帧真实连续渲染）+ `210-poof-occlusion.png`（满烟雾遮挡瞬间）+ `211-poof-landing.png` + 阅读窗口。
- 打包 App 内 `--verify-bottle-art` 校验全部 11 项素材（5 张 v3 + 4 张烟雾 + 落地尘 + wav）。

## Mac 真机验收步骤

1. 安装最新 zip；右键 → Bottle Mail 绑定设备；发一封信。
2. 观察变身：压扁蓄力 → 跳起 → “嘭”一声轻响 + 白色烟雾迅速充满宠物区域 → 完全遮挡的瞬间切换（看不到瓶子与本体重叠）→ 烟雾散去，瓶子缓缓降下、轻轻落地、微晃后稳定。全程约 1.35s。
3. 关键检查：烟雾最浓时是否完全盖住两个造型（无半透明重叠/无轮廓闪烁）；消散后瓶子位置与原来桌宠位置一致、无突然跳位；瓶颈/瓶塞不被窗口顶部裁切（多显示器各试）。
4. 读完并收好最后一封信：反向变身（小跃起 + 烟雾换回 + 落地），音效再响一次。
5. 多封来信只变一次；阅读中来新信不重播；拖拽/睡眠/生日/Meteor 冲突期间延迟或冻结。
6. 系统「减少动态效果」：跳跃变小、烟雾扩散收敛，仍完整遮挡切换。
7. 关闭音效（`defaults write …` 或后续偏好开关）：无声但动画完整。
8. 断网读信、重启恢复、右键邮箱、菜单栏退出等原有行为回归。

## 已知问题 / 未完成

- 开封动画（unread→opening 同轮廓过渡）与卷信飞出瓶口动画维持此前限制（`bottle_opening.png` 自带卷信，未做内容感知拆分）。
- 烟雾为固定遮挡尺寸（核心烟层充满宠物窗口），观感如需更“云团状”可再调 `BottlePoofTimeline` 常数与装饰层参数（真机调参）。
- 程序化占位与几何揭示仅作缺素材回退，非正式视觉。
- 音效音量/时机以真机听感为准微调（当前 0.25 / 0.43s）。
