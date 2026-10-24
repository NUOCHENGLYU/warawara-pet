# Bottle Mail — Phase 8B 计划（macOS 接收端）

> 本计划基于对当前代码库的实际审查（`0661011`，分支 `phase7/final-gift`）。
> Phase 8A 只交付云端与发送端；本文件是 8B/8C 的实施方案，供验收后执行。

## 现状核查（与计划的连接点）

| 现有模块 | 关键事实 | 对漂流瓶的影响 |
|---|---|---|
| `AppDelegate` | 4 Hz `birthdayTick()` 已驱动 birthday + meteor；`wire*` 组装各事件 | 新增 `wireBottleMail()`，把 bottle tick 挂进同一轻量循环，不新增高频定时器 |
| `StatusItemController` | 左键=立即退出；**刻意无 NSMenu**（菜单跟踪会让非激活桌宠面板消失，见 KNOWN_ISSUES） | 邮箱入口**不能**放菜单栏菜单；退出功能不动 |
| `PetHostingView` / `PetInteractionController` | 宠物**右键目前完全未用**（有注释），双击已保留给生日信件 | 宠物右键 = 打开本地信箱（备用入口，不破坏退出） |
| `PetState` 状态机 | idle/hop/float/curious/clicked/dragged/settling/sleepy/sleeping；`sleeping→idle` 已是合法轻柔唤醒 | 瓶子事件排队等待 idle；宠物睡觉/拖拽/生日/Meteor 期间不打断 |
| `BirthdayEventCoordinator` + `BirthdayPresenter` + `LetterWindowController` | 生日信件是独立事件、独立内容、双击入口 | 漂流瓶信件 = 新事件、新内容、新入口，绝不混用 |
| `MeteorEventController` | `isPetBusy`/`isBirthdayBlocking` 门控 + presenter 模式 + 90s 宽限 | BottleMailCoordinator 采用同款「冲突门控 + 延迟补投」模式 |
| `WindowLifecycleMonitor` | wake 后延迟检查 + 非激活恢复 | 唤醒/网络恢复时触发一次主动拉取 |
| `PetWindowController` | `setEventAttention`、`performCelebrationHop`、companion panel 池（`BirthdayPropPanel`） | 瓶子借用 prop-panel 池技术渲染（分层、可替换素材） |
| 持久化 | UserDefaults 轻量键 + Keychain 尚未引入 | 信件正文存 **Application Support/JSON 文件**（有界，保 200 封）；设备令牌进 **Keychain** |
| CI | macos-14/15 三 job；后端测试独立 job（Phase 8A 已加） | Swift 单测注入 mock 网络层，CI 不依赖 Cloudflare |

## 新增 Swift 模块（放在 `Sources/WarawaraPet/BottleMail/`）

1. **`BottleMailAPI`**（网络层，URLSession async/await）
   - `activate(code:label:) -> DeviceCredential`、`fetchLetters(after:)`、`markOpened(id:)`
   - 端点、超时（10s）、指数退避（5s→60s，最大抖动）、`isReachable` 检查；
   - 协议化 `BottleMailAPITransport`，测试用 mock。
2. **`BottleMailCredentialStore`**（Keychain 包装，注入式）
   - 保存/读取/清除设备令牌与已激活状态；测试用内存实现。
3. **`BottleMailStore`**（本地信件持久化）
   - Application Support 下 JSON 文件：按 `seq` 去重 upsert、未读集合、`lastSeq` 游标、已读集合；
   - **先持久化再进 UI 队列**；崩溃/重启不丢；有界裁剪。
4. **`BottleMailCoordinator`**（事件状态机，`PetState` 同风格）
   - 状态：`idle → polling → bottleDelivered → opened → done`；未读队列先进先出；
   - 冲突门控：`isPetBusy`（拖拽/睡眠/生日/Meteor/群组）时挂起，转空闲后按序补投；
   - 唤醒（`NSWorkspace.didWake`）、网络恢复（`NWPathMonitor` 或可达性回调）、启动时主动拉取；
   - 拉取间隔 20–30s；失败静默退避；永不让 UI 卡顿（全部后台队列）。
5. **`BottleMailPresenter` / `BottlePropPanel`**（8C 动画）
   - 瓶子 = 分层 prop（瓶身/瓶塞/纸条/信纸四层，占位程序化图形 + 素材可替换）；
   - 连续参数驱动（位移/旋转/缩放/弹簧），尊重「减少动态效果」；
   - 信纸 = 独立可聚焦阅读窗口（正常键盘交互），关闭后回信箱。
6. **入口**
   - 主入口：宠物身边的可点击瓶子（未读时）；
   - 备用入口：宠物右键 → 打开信箱（新窗口列全部信件，只读重看）；
   - 退出路径保持菜单栏状态项不变。

## 集成改动点（明确、最小）

- `AppDelegate.wireBottleMail()`：组装 API/Store/Coordinator/Presenter；在
  `birthdayTick()` 里加 `bottleMailCoordinator?.tick()`；挂 wake/网络恢复钩子。
- `PetWindowController`：暴露 `isPetBusy` 给 bottle 门控；瓶子面板用现有
  prop 面板层级；`reassertLayering` 纳入瓶子。
- `PetInteractionController`/`PetHostingView`：右键回调
  `onPetRightClick`（当前为空实现，直接复用）。
- `--bottle-activate <code>`、`--bottle-diagnose` 调试参数（仿
  `--diagnose-first-launch` 模式），最终礼物不暴露 UI 调试入口。

## 测试清单（8B/8C 完成时）

- mock 网络：激活成功/码失效/过期/重复兑换/令牌被撤销；超时/断网/500/重试退避；
- 去重：轮询重复返回同 `seq`/`id` 不重复生成瓶子；
- 持久化：未读跨重启保留；先持久化后入队；打开确认失败重试幂等；
- 状态机：睡眠/拖拽/生日/Meteor 期间排队、恢复后按序补投、多封不并排轰炸；
- 睡眠/唤醒恢复收信；普通桌宠交互与生日事件回归测试不破坏；
- Sonoma 14 + Tahoe 26 真机清单（窗口层级、焦点不抢、右键入口、退出路径）。

## 明确不做（8B 阶段）

- 不改生日信件、Meteor、睡眠动画、窗口恢复逻辑；
- 不实现图片/语音/回复/多用户；
- 不在没有验收前替换任何现有美术素材。
