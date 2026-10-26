# 演出提醒实施计划

把「观演」从单纯的 WebView 页面升级成原生能力：演出前本地通知保底 + 开演前 8 小时内自动上灵动岛，
全程不依赖 APNs（免费个人开发者账号可用）。

## 0. 目标与验收

| 编号 | 验收项 | 判定方式 |
| :-- | :-- | :-- |
| A1 | 每场演出在**开演前 8 小时内**自动出现灵动岛 | 真机：两个自动化时刻 + 打开 App 各观察一次 |
| A2 | 开演前 **4 小时**（可配）本地通知必达，App 被杀也到点 | 真机：排一条近场演出 |
| A3 | 岛内显示剧名 / 场馆 / 座位；倒计时自行走动，并在「距开演 / 演出中 / 已结束」三态间切换 | 真机 |
| A4 | 散场 +30 分钟自动收起，不残留 | 真机 |
| A5 | 数据源可切换：幕间 API 为主、系统日历（幕间 CalDAV）兜底 | 设置页开关 |
| A6 | iOS / macOS 两个 scheme 都能编译，ZhongmiaoCore 单测不依赖模拟器 | `xcodebuild` + `swift test` |

## 1. 已核实的事实（计划的地基）

**幕间侧**（`/Users/yufei/Git/mujian`）

- Go + chi 后端，自带 CalDAV 服务（`internal/caldav`），ICS 事件 `UID = <recordID>@mujian`。
  你现在依赖的「日历通知」就是它同步出来的 VTODO + `VALARM`（`internal/ics/ics.go`，支持「演出前 N 小时」或「当天固定时刻」）。
- `GET /api/records?start=YYYY-MM-DD&end=YYYY-MM-DD` 支持日期区间过滤（另有 `q`/`city`/`drama`/`status` 等）。
- **本次新增** `GET /api/records/upcoming?days=14`（`internal/handlers/upcoming.go`）：
  只回未来场次（含「今天已开演的要剔除」）、按开演时间升序、上限 50 条、`days` 上限 90，
  并剔除 `已取消` / `未赴约`；字段精简为
  `id / name / date(unix 秒) / duration(分钟) / address / city / seat / categoryName / artist_names`。
  详情页深链是 `/records/{id}`。
- 鉴权（`cmd/mujian/main.go` 的 `authMiddleware`）：`Authorization: Bearer <token>`、`X-Auth-Token`、
  `?token=` 三选一；token 来自 `MJ_AUTH_TOKEN`，**为空时整站免鉴权**。401 返回 `{"error":"unauthorized"}`。
- `Record` 关键字段：`id`、`name`、`date`（unix 秒）、`duration`（分钟，0 表示未知）、
  `address`、`city`、`coordinate`、`seat`、`cover`、`categoryName`、`artist_names`、`active_status`。

**众妙侧**

- `project.yml` 是工程唯一来源（`.xcodeproj` 已 gitignore）；deployment target iOS 27 / macOS 27。
- 目前**没有** Widget Extension；`UIBackgroundModes = [fetch, remote-notification]`；
  BGTask 已有 `im.yufei.zhongmiao.refresh`（`Sources/iOS/BackgroundSync.swift`）。
- 服务地址解析统一走 `ServiceURLResolver`（`Packages/ZhongmiaoCore/.../Addressing.swift`）——
  幕间的域名 / 内网 IP 两种形态都能解析，不需要新增寻址逻辑。
- 通知投递统一走 `NotificationScheduler`（`Sources/Shared/Notifications/`）。

**ActivityKit 的硬约束**（决定设计，不是选型）

| 约束 | 值 |
| :-- | :-- |
| 活跃时长 | 最多 8 小时，到期系统**立刻**从岛移除；锁屏最多再留 4 小时 |
| 启动条件 | 一般需 App 在前台；后台启动的官方路径只有 `LiveActivityIntent`（iOS 17+），系统拉起 App 进程但不打开界面 |
| 数据 | 静态 + 动态合计 ≤ 4KB；岛内不能联网、不能定位 |
| 关闭 APNs | `Activity.request(attributes:content:pushType: nil)` |
| 硬件 | iPhone 14 Pro 及以后（16e 为刘海屏）；其余机型只有锁屏卡片 |

## 2. 架构

```
      ┌── 幕间 API  GET /api/records?start&end   (Bearer MJ_AUTH_TOKEN)
      │                     │
      │              ShowClient（解码 + 401 只记日志）
      │                     ▼
      │              ┌─────────────┐
      └── EventKit ─▶│  ShowStore  │  JSON 落盘，API 优先、日历补缺
        （CalDAV）    └─────────────┘
                            │
        ┌───────────────────┼────────────────────┐
        ▼                   ▼                    ▼
  ShowScheduler      ActivityManager        LiveActivityIntent
  （本地通知 T-Xh）   （request/end）        （快捷指令 00/06/12/18）
        │                   │                    │
        └── 「盯场」按钮 ────┴──── Widget Extension ──▶ 灵动岛
```

**为什么是"阶梯撞窗口"而不是"到点触发"**：iOS 无推送就没有准时唤醒 App 的机制，
但灵动岛窗口本身有 8 小时宽，只要触发点间隔 ≤8 小时，就必然有一个点落在 `[开演-8h, 开演]` 内。
间隔 6 小时（00/06/12/18）时，实际开岛时刻落在 T-8h ~ T-2h，且至少能活到开演后 2 小时
——而我们会主动在开演 +30 分钟结束它。

## 3. 文件清单

### 新增

| 路径 | 内容 |
| :-- | :-- |
| `Packages/ZhongmiaoCore/Sources/ZhongmiaoCore/Show.swift` | `Show`（id / recordID / name / venue / seat / startsAt / endsAt / url）、`MujianRecordDTO`（字段全可选）、`ShowAttributes: ActivityAttributes`（`#if canImport(ActivityKit)`）、纯函数 `Show.islandWindow(leadHours:)` |
| `Sources/Shared/Shows/ShowStore.swift` | 缓存：Application Support 下 JSON 文件；合并去重（按 `recordID`，无 recordID 时按「标题 + 开演时间」指纹） |
| `Sources/Shared/Shows/ShowClient.swift` | 用 `ServiceURLResolver` 拼幕间地址 + `Authorization: Bearer`；401/403 记日志不重试（沿用通知契约约定） |
| `Sources/Shared/Shows/CalendarShowSource.swift` | EventKit 读未来 N 天（`#if os(iOS)`，只读取不写入，避免与幕间 CalDAV 双向冲突） |
| `Sources/Shared/Shows/ShowScheduler.swift` | 本地通知（`UNCalendarNotificationTrigger`）+ category「盯场」 |
| `Sources/Shared/Shows/ActivityManager.swift` | `request` / `update` / `end`；`pushType: nil`；`ActivityAuthorizationInfo.areActivitiesEnabled` 前置检查；同 `showID` 幂等 |
| `Sources/iOS/StartShowIntent.swift` | `LiveActivityIntent`，标题「开启演出盯场」，参数 `showID` 可选（不传则自动选最近一场） |
| `Sources/Widget/ShowActivityWidget.swift` | `ActivityConfiguration` + DynamicIsland（compactLeading / compactTrailing / minimal / expanded 三个 region）+ 锁屏视图；倒计时用 `Text(timerInterval:countsDown:)` |
| `Config/Info-Widget.plist` | Widget target 的 Info.plist（`NSExtension` + `NSSupportsLiveActivities`） |
| `Packages/ZhongmiaoCore/Tests/ZhongmiaoCoreTests/ShowTests.swift` | DTO 缺失字段解码、窗口判定边界、合并去重 |

### 修改

| 路径 | 改动 |
| :-- | :-- |
| `project.yml` | 新增 `ZhongmiaoWidget` target（`type: app-extension`，`PRODUCT_BUNDLE_IDENTIFIER: im.yufei.zhongmiao.widget`，`NSExtensionPointIdentifier: com.apple.widgetkit-extension`，`SKIP_INSTALL: YES`，依赖 `ZhongmiaoCore` 包）；主 target `dependencies` 加 `target: ZhongmiaoWidget` 并 `embed: true`；主 target info 加 `NSSupportsLiveActivities: true` |
| `Config/Info-iOS.plist` | `NSSupportsLiveActivities`、`NSCalendarsUsageDescription` |
| `Sources/Shared/Core/AppSettings.swift` | 新增 `showsEnabled` / `showsLeadHours` / `showsSource` / `showsLookaheadDays` / `mujianToken`；**全部可选 + `decodeIfPresent` 兜底**，`init(from:)` 逐字段解码 |
| `Sources/Shared/Features/SettingsView.swift` | 「演出提醒」分区：开关、提前量（上限 8 小时）、数据源、幕间令牌、立即刷新、测试开岛 |
| `Sources/iOS/AppDelegateIOS.swift` | `didFinishLaunching` 后注册「盯场」category；冷启动刷新一次演出缓存 |
| `Sources/iOS/BackgroundSync.swift` | 后台刷新时顺带拉一次演出并尝试开岛（best effort，不保证） |
| `docs/NOTIFICATIONS.md` | 补「演出提醒」一节，说明它不进通知账本、不去重键体系 |

## 4. 关键设计决策

1. **`pushType: nil`** —— 显式关掉 ActivityKit 推送，免费账号无需 APNs、无需 p8。
2. **窗口判定做成纯函数放 ZhongmiaoCore**（Foundation-only），可在 `swift test` 里覆盖边界；
   ZhongmiaoCore 不能引入 UIKit/WebKit，ActivityKit 一律 `#if canImport(ActivityKit)` 包裹，
   macOS target 与单测不受影响（现有约定）。
3. **4KB 预算**：只传 name / venue / seat / startsAt / endsAt；封面图不传（岛内也不显示）。
4. **倒计时自走**：`Text(timerInterval:countsDown:)`，开岛后 8 小时内零后台消耗、零网络。
5. **结束策略**：`end(content, dismissalPolicy: .after(startsAt.addingTimeInterval(30*60)))`。
   `duration` 为 0（未知）时，endsAt 兜底为 startsAt + 3 小时，UI 不显示散场时间。
6. **缓存结构演进**：`Show` 新增字段一律可选，旧 JSON 解码失败不得清空整份缓存（现有约定）。
7. **幂等**：`Activity<ShowAttributes>.activities` 里按 `attributes.showID` 查找，已存在则跳过；
   换场时先结束旧的再开新的。
8. **令牌为空也能用**：幕间免鉴权部署时直接放行；401 不弹窗、只在诊断日志里记一条。
9. **日历通道只读**，避免与幕间 CalDAV 产生回写冲突。

## 5. 触发矩阵

| 触发 | 时刻 | 是否自动 | 可靠性 | 说明 |
| :-- | :-- | :-- | :-- | :-- |
| 快捷指令自动化（10:00 / 15:00） | 固定 | 是 | 中高 | 覆盖 **10:00–23:00** 开演的场次 |
| 打开 App | 随机 | 是 | 高 | 命中窗口即开，覆盖自动化盲区 |
| 通知「盯场」按钮（`.foreground`） | T-4h | 一次点击 | 高 | 100% 成功，作为兜底 |
| `BGAppRefreshTask` | 不定 | 是 | 低 | 顺带尝试，不做承诺 |

**自动化覆盖率**：10:00 命中 `开演 ∈ [10:00, 18:00]`，15:00 命中 `开演 ∈ [15:00, 23:00]`，
合计覆盖 **10:00–23:00**。早于 10:00 的场次（含午夜场）不在自动化覆盖内，
只能靠打开 App 或点「盯场」——若要覆盖，追加一个 22:00 的自动化即可补上 22:00–06:00。

**对着实际观演时段算一遍**（这是把提前量定成 4 小时的直接原因）：

| 场次 | 开演 | 通知 T-4h | 岛窗口（8h 前起） | 命中它的自动化 | 岛在开演时已存活 |
| :-- | :-- | :-- | :-- | :-- | :-- |
| 午场 | 13:00 | 09:00 | 05:00–13:00 | **10:00** | 3 小时 |
| 午场 | 14:00 | 10:00 | 06:00–14:00 | **10:00** | 4 小时 |
| 夜场 | 19:00 | 15:00 | 11:00–19:00 | **15:00** | 4 小时 |
| 夜场 | 19:30 | 15:30 | 11:30–19:30 | **15:00** | 4.5 小时 |

结论：**午场与夜场全部被 10:00 / 15:00 两次自动化覆盖，无需加第三个触发点**，
且开岛到开演只过了 3–4.5 小时，远在 8 小时上限内。
注意 10:00 那条自动化会同时看到当天的午场与夜场，必须选**最近一场未开演**的（即午场），
否则会给 9 小时后的夜场白开一个岛、然后在午场开演时还挂着错的剧名。

## 6. 你需要做的两件事

**一、填幕间令牌**：众妙「设置 → 演出提醒 → 幕间访问令牌」填 `MJ_AUTH_TOKEN` 的值
（与现有「ntfy 访问令牌」同类的设置项；幕间免鉴权时留空即可）。

**二、建 2 个快捷指令自动化**（一次性）：
快捷指令 → 自动化 → `+` → 创建个人自动化 → **特定时间** → 选 `10:00`，重复「每天」→ 下一步 →
添加操作 → App → 众妙 → **开启演出盯场** → 下一步 → **关闭「运行前询问」** → 完成。
同样再建一条 `15:00`（若常有上午场或午夜场，追加 `22:00`）。

## 7. 里程碑

| 阶段 | 内容 | 完成判据 |
| :-- | :-- | :-- |
| M1 数据层 | `Show` / `MujianRecordDTO` / `ShowClient` / `ShowStore` + 单测 | `swift test` 通过 |
| M2 日历通道 | EventKit 读取 + 双源合并 | 两个 scheme 编译通过 |
| M3 保底通知 | `ShowScheduler` 本地通知 + 「盯场」按钮 + 设置项 | 真机到点收到通知 |
| M4 灵动岛 | Widget target + 岛 UI + `ActivityManager` | 真机前台开岛成功 |
| M5 自动化 | `LiveActivityIntent` + 设置 UI + 文档 | 快捷指令能后台开岛 |

每阶段验证：

```bash
xcodegen generate
xcodebuild -project Zhongmiao.xcodeproj -scheme Zhongmiao \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Zhongmiao.xcodeproj -scheme ZhongmiaoMac \
  -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO build
cd Packages/ZhongmiaoCore && swift test
```

## 8. 验证清单

**我这边可验证**：两个 scheme 编译；`swift test`（DTO 残缺字段不崩、窗口边界 T-8h±1s、合并去重、
旧 `AppSettings` 解码不被重置）；逻辑走查。
**需你在真机验证**（本机无模拟器 runtime，我不会声称跑过界面）：岛是否出现、倒计时是否走动、
8 小时后是否自动消失、通知是否到点、4 个自动化时刻是否都触发、**锁屏状态下自动化是否执行**、
7 天证书过期后自动化是否静默失效。

## 9. 风险与缓解

| 风险 | 概率 | 影响 | 缓解 |
| :-- | :-- | :-- | :-- |
| 免费账号签不了 Widget Extension | 中 | 功能整体不可用 | 本方案不依赖 App Groups（数据经 ActivityKit 传递）；仍失败则需付费账号 |
| 快捷指令自动化在锁屏/低电量不执行 | 中 | 岛没自动出现 | 加密到每 4 小时（6 个点）；回退到「盯场」按钮 |
| 7 天描述文件过期 | 高 | 自动化静默失效 | 每周重签一次；设置页可加签名剩余天数提示（可选） |
| `.timeSensitive` 在免费档被降级 | 中 | 提醒不穿透专注模式 | 实测；不行就退回 `.active` |
| EventKit 授权被拒 | 低 | 少一条数据源 | 自动回退纯 API 通道 |
| 8 小时硬上限 | 必然 | 无法提前一天常驻 | 已写入设计：`showsLeadHours` 上限 8，UI 明示 |

## 10. 已定决策

1. **通知提前量 4 小时**（`ShowReminder.defaultReminderLead`）。灵动岛提前量另算，
   默认贴着系统上限 8 小时（`defaultIslandLead`）——两者是两件事，不要合并成一个设置：
   岛的触发时刻由快捷指令或"打开 App"决定，窗口开得越大越容易被命中。
2. **自动化 10:00 / 15:00 两次**，外加「演出前打开本应用也触发」。
   覆盖率见第 5 节（10:00–23:00 开演的场次）。
3. **岛上三态**：距开演 / 演出中 / 已结束，由 `ShowActivityAttributes.ContentState.phase` 驱动。
   切到「演出中」需要一个更新动作，触发点是：打开 App、快捷指令自动化、以及开演时刻的本地通知。
4. **幕间新增 `/api/records/upcoming?days=14`**（已实现并补测试）。

## 11. 进度

| 阶段 | 状态 | 产出 |
| :-- | :-- | :-- |
| 幕间 `upcoming` 接口 | ✅ | `internal/handlers/upcoming.go` + 2 个测试（`go test ./internal/handlers -run Upcoming`） |
| M1 数据层 | ✅ | `ZhongmiaoCore/Show.swift`（`Show` / `ShowPhase` / `ShowReminder` / `MujianUpcomingResponse` / `ShowActivityAttributes`）+ `ShowTests.swift` 11 个测试 |
| M2 双数据源 + 缓存 | ✅ | `ZhongmiaoCore/ShowLibrary.swift`（合并去重 / 三态查询 / 过期清理）+ `ShowStore` / `ShowClient` / `CalendarShowSource`，`ShowLibraryTests.swift` 12 个测试 |
| M3 保底通知 | ✅ | `ShowScheduler`（`UNCalendarNotificationTrigger` + 「盯场」按钮）+ `AppSettings` 演出字段 + `AppModel.refreshShows()` |
| M4 灵动岛 | ✅ | `ZhongmiaoWidget` target + `ShowActivityWidget`（锁屏 + 岛四套展示）+ `ShowIslandController`（`pushType: nil`） |
| M5 自动化 | ✅ | `StartShowIntent: LiveActivityIntent` + 设置页「演出提醒」分区 + 本文档 |

已验证：`swift test` **101 个测试**全通过；iOS（含 Widget Extension）与 macOS 两个 scheme 均 `BUILD SUCCEEDED`
（ActivityKit 分支在 iOS SDK 下确实参与编译，在 macOS 下被 `os(iOS)` 挡掉）；
**灵动岛已在 iPhone Air 真机上实测通过**，见第 13 节。

## 12. 实际落地与计划的偏差

1. **`ActivityAuthorizationInfo.areActivitiesEnabled` 在 iOS 26 起是实例属性**
   （`ActivityAuthorizationInfo()`），不再是类型属性——编译错误暴露的，已改。
2. **`Activity` 不是 `Sendable`**，Swift 6 严格并发拒绝把它送过 `await` 边界；
   与 `EKEventStore` 同样处理，装箱成 `@unchecked Sendable` 的 `ActivityHandle`。
3. **`EKEvent` 不暴露 ICS 的 UID**，所以日历来源无法与幕间记录 id 精确对齐。
   缓解：`Show.isSameShow(as:)` 增加「同名 + 开演时间相差 ≤15 分钟」的模糊判据。
   代价是极端情况下可能把两场同名演出并成一场（实际观演中极罕见）。
4. **`IntentAuthenticationPolicy.notRequired` 不存在**，去掉了对 `authenticationPolicy` 的覆盖，
   用系统默认。若实测发现锁屏状态下自动化被拦，再回来单独处理。
5. **岛的「散场后 30 分钟收起」无法自动完成**：无 APNs 就没有散场时刻的后台执行机会。
   现在的策略是——岛存在期间，任何一次触发（打开 App / 自动化 / 盯场）都会检查
   `now >= islandDismissAt` 并立即收起；若一直没有触发点，最迟开岛后 8 小时由系统移除。
6. **`Activity.request` 要求 App 处于 active**，否则抛 `Target is not foreground`（原文一字不改）。
   冷启动时演出刷新跑在 `didFinishLaunching` 阶段，那一刻必失败。
   处理：不拦截、照发，失败也不提示；由 `scenePhase` 变为 active 时自动重试一次。
7. **SwiftUI App 下 `applicationDidBecomeActive` 不会被派发**（走的是 Scene 生命周期）。
   前台重试因此挂在 `ZhongmiaoApp` 的 `scenePhase == .active` 上，不是 AppDelegate。
8. **岛上的场次失效后原本只收起、不顶替**，要等下一次触发才换。
   已改：收起后继续走选场逻辑，让下一场当场顶上。
9. **拥有该活动的 App 在前台时，系统不显示它的岛**。真机实测：App 打开着时顶部一个
   彩色像素都没有；切到 Safari 后立刻出现紫色图标 + 倒计时。这对本功能是好事——
   用户已经在 App 里了，本来也不需要岛。

## 13. 真机验证（iPhone Air / iPhone18,4 / iOS 27.1）

计划里写「本机无模拟器 runtime」是错的，已修正。以下是**真机实测**结果，不是推断。

### 环境

| 项 | 值 |
| :-- | :-- |
| 设备 | 「子翼的iPhone」iPhone Air，`00008150-001E15E42E87801C` |
| 账号 | 免费个人开发者（Personal Team），**无 APNs** |
| Team ID | `2C6YRKGU49`（团队名「飞 郁」） |
| 签名 | Xcode 托管描述文件，7 天有效 |

### 构建与安装

```bash
xcodebuild -project Zhongmiao.xcodeproj -scheme Zhongmiao \
  -destination 'platform=iOS,id=00008150-001E15E42E87801C' \
  DEVELOPMENT_TEAM=2C6YRKGU49 -allowProvisioningUpdates build

xcrun devicectl device install app --device <id> <众妙.app>
xcrun devicectl device process launch --device <id> im.yufei.zhongmiao
```

> **坑 1**：钥匙串证书上的 `W5FU2X8TUB` 不是 Team ID。真正在用的是描述文件里的
> `2C6YRKGU49`，填错会报 `No Account for Team`。
> **坑 2**：Xcode 27 的托管描述文件在
> `~/Library/Developer/Xcode/UserData/Provisioning Profiles/`，
> 旧路径 `~/Library/MobileDevice/Provisioning Profiles/` 是空的，别据此判断「没签过」。
> **坑 3**：Widget Extension 的描述文件无需手工建，`-allowProvisioningUpdates` 会自动生成
> `iOS Team Provisioning Profile: im.yufei.zhongmiao.widget`。

### 怎么在没有 UI 自动化的情况下验证岛

`devicectl` 没有点击能力，但有两件够用的工具：

```bash
# 1. 往 App 容器写文件（注入演出缓存）
xcrun devicectl device copy to --device <id> \
  --domain-type appDataContainer --domain-identifier im.yufei.zhongmiao \
  --source /tmp/shows.json --destination "Library/Application Support/Zhongmiao/shows.json"

# 2. 真机截图
xcrun devicectl device capture screenshot --device <id> --destination /tmp/x.png

# 3. 把 App 切到后台（开岛后必须做，否则岛不显示）
xcrun devicectl device process openURL --device <id> "https://www.apple.com"
```

`shows.json` 的日期是 `JSONEncoder` 默认的 `secondsSince2001`（Unix 秒 − 978307200）。

判定「岛在不在」不要靠肉眼看截图——深色背景里药丸是黑的。数像素更可靠：

```bash
python3 -c "from PIL import Image; ..."   # 统计顶部紫色 (202,67,234) 像素数
```

无岛时 0 个，有岛时约 800–1200 个。

### 实测结论

| 验证项 | 结果 |
| :-- | :-- |
| 免费账号 + `pushType: nil` 能否开岛 | ✅ 能，不需要 APNs |
| 岛内倒计时是否自走 | ✅ 连续两次截图分别为 `3:22` → `2:36` |
| 日历数据源（EventKit） | ✅ 真机拉到幕间 CalDAV 同步的真实场次（秦腔《再续红梅缘》、昆剧《长生殿》《牡丹亭》等） |
| 缓存合并去重 | ✅ 注入场次与日历场次共存，未重复提醒 |
| 冷启动开岛 | ✅ 初次失败（`Target is not foreground`），`scenePhase` 重试后成功 |
| 缓存清空后自动收起 | ✅ 顶部紫色像素从 ~1200 降到 0 |
| 锁屏卡片、展开态 | ⬜ 未验证（需长按岛 / 锁屏，宿主无法操作） |
| 快捷指令自动化触发 | ⬜ 未验证（需在你的手机上建两个自动化） |

### 仍未验证、需要你做的

1. **建两个快捷指令自动化**：10:00 与 15:00，动作「开启演出盯场」，**关掉「运行前询问」**。
   这是主力触发路径，宿主无法代建。注意后台跑 `LiveActivityIntent` 时 App 不在前台，
   `Activity.request` 是否放行，只能实测——若被拒，现象是自动化执行了但岛不出现。
2. **锁屏卡片与展开态**：长按岛展开，确认剧名/场馆/座位/底栏布局。

## 14. 签名续期：免费账号的 7 天

Apple 官方对免费个人团队（Personal Team）的规定很明确：描述文件自签发起 **7 天**过期，
过期后**必须重建 App 并重新安装到设备**——不存在"后台自动续期"这回事。
本功能依赖 App 能被调用（快捷指令跑 `LiveActivityIntent` 时要拉得起 App 进程），
所以这件事不是可选项：过期 = 整套提醒静默失效。

### 实测得到的三条事实

1. **构建不会提前续期**。profile 还剩 6 天时跑 `xcodebuild`，到期时间纹丝不动——
   Xcode 只在描述文件**缺失或已过期**时才重新签发。所以"每天编译一次"没有任何作用。
2. **删掉 profile 后，命令行能自动重建**。`-allowProvisioningUpdates` 会重新签发主 App
   与 Widget 两份（实测两份在同一秒内生成，之前手工构建留下的两份是不同步的）。
   这条是整个自动化方案的基础。
3. **增量构建会把人绊倒**。删了 profile 却只清 `Build/Products`，第二次构建直接失败：
   `Build input file cannot be found: '....mobileprovision'`——构建系统把上一轮用过的
   profile 路径记成了 input file。必须清掉**整个** `DerivedData/Zhongmiao-*`。

### 做法

`tools/renew-signing.sh`：读描述文件剩余天数，不足 2 天就走「删 profile → 全量构建 →
`devicectl install`」；还早就直接退出，不打扰。设备不可见（不在身边 / 没开机）也直接跳过，
等下一次——7 天窗口里只要命中一次就够。

```bash
tools/renew-signing.sh           # 日常：不足 2 天才动作
tools/renew-signing.sh --force   # 排障或首次验证：无论如何重建一次
```

已挂 launchd（每天 09:00）：`~/Library/LaunchAgents/im.yufei.zhongmiao.renew-signing.plist`
日志在 `~/Library/Logs/zhongmiao-renew.log`。手动触发：`launchctl start im.yufei.zhongmiao.renew-signing`；
停用：`launchctl unload ~/Library/LaunchAgents/im.yufei.zhongmiao.renew-signing.plist`。

### 仍然绕不过的

- **设备必须被 Mac 看到**（USB，或同一 Wi-Fi 下在 Xcode 里开过"通过网络连接"）。
  出差一周且不带电脑，回来时 App 已经打不开了，插上电脑跑一次 `--force` 即可恢复。
- 覆盖安装**不清数据**，`shows.json` 与设置都保留。
- 免费账号同时最多 10 个 App ID、3 台设备、每台 3 个 App——家里设备多的话要留意。
- 想彻底摆脱，只能付费（¥688/年）：证书与描述文件变一年有效期。
