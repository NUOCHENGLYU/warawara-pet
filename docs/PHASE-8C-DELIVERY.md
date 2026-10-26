# Phase 8C — 本体变身漂流瓶（跳跃烟雾变身 · 正式版）

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
- 音效：`BottlePoofSound` 每段变身仅触发一次（`onPoofMoment` 回调，正反向各一次），低音量、系统静音自动生效、可关（`warawarapet.sound.enabled`）。
- **邮件语义全部保留**：多封只变一次、阅读中来新信入队不重播变身、投递 ACK ≠ 已读、本地优先离线可读、联网对账、重启恢复；生日/Meteor/拖拽/睡眠冲突期间延迟或冻结。
- Reduce Motion：跳跃 30→14pt、装饰烟雾扩散缩小；核心遮挡烟不变（仍保证无突变切换）。
- 回退链：完整素材 → poof 模式；缺烟雾包 → 几何揭示回退（原 BottleMorphGeometry，仅内部回退）；缺 v3 美术 → 程序化占位瓶。缺音效仅静音跳过。

## 测试

- 新增 `BottlePoofTimelineTests`：相位边界、跳跃弧线（26–32pt/Reduce 14pt）、正反向切换点、**遮挡完整性机器校验**、包络不越窗、落地晃动衰减、烟雾可见窗口。
- 新增视觉测试：`testPoofMomentFiresExactlyOncePerTransition`（正反向各一次、新信不重播）、`testFormProgressStepsOnlyAtTheSmokeCoveredSwitch`。
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
