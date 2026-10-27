# 架构

## 目标与非目标

**目标**：给一批已经能独立运行的 Go + 前端应用，提供统一的 iOS 入口，在「离线」与「通知」这两件
PWA 在 iOS 上最弱的事情上补强；对有稳定 HTTP API 的应用，再补一层原生读屏与高频写操作。
全程不改动各应用的后端。

**非目标**：不做原生重写。每个应用的业务逻辑、页面、离线策略仍然属于它自己；
众妙只负责承载、路由、通知汇聚、原生读屏与配置。原生界面只覆盖高频只读与少数可逆写操作，
复杂交互（预算、分期、关系图谱、切图编辑器）留在网页版。这样任何一个应用单独升级都不会被壳拖住。

## 分层

```
┌──────────────────────────────────────────────────────────┐
│ SwiftUI 界面层                                            │
│   CatalogView / ServiceScreen / NotificationsView        │
│   NativeServiceScreen + 12 个 *Screen                     │
│   DiagnosticsView / SettingsView / IntegrationSettings   │
├──────────────────────────────────────────────────────────┤
│ AppModel（@MainActor，唯一状态中枢）                        │
│   设置 · 快照 · 体检 · 深链 · 推送令牌 · 日志               │
├───────────────────────────┬──────────────────────────────┤
│ NotificationEngine(actor) │ WebAppModel / WebCoordinator  │
│   拉取 → 去重 → 入库 → 投递 │   WKWebView 生命周期与导航策略   │
├───────────────────────────┼──────────────────────────────┤
│ IntegrationCenter         │ IntegrationCache(actor)      │
│   凭据状态 · 偏好 · 提醒计数 │   每应用一份快照，原子写        │
├───────────────────────────┴──────────────────────────────┤
│ FeedClients / 各应用 Client / NotificationScheduler        │
│   URLSession · UNUserNotificationCenter · 原子写文件        │
├──────────────────────────────────────────────────────────┤
│ SecretStore → KeychainStore（同步，失败即报错，绝不落明文）   │
├──────────────────────────────────────────────────────────┤
│ ZhongmiaoCore（纯 Foundation，可单测）                      │
│   服务注册表 · 地址解析 · 账本与游标 · ntfy/feed 解析         │
│   接入矩阵 · 分流规则 · 提醒预算 · 时间解析 · 记账草稿         │
│   退避策略 · 导航同源策略 · 健康分类                        │
└──────────────────────────────────────────────────────────┘
```

核心包刻意不依赖 UIKit/WebKit：所有易错的纯逻辑（去重、游标、解析、退避）都能用 `swift test` 覆盖，
不依赖模拟器运行时。界面与系统 API 留在 App target。

## 并发模型

- `AppModel` 是 **@MainActor**，所有 UI 可观察状态只在主线程改。
- `NotificationEngine` 是 **actor**，账本只允许它读写；磁盘写入串行，避免并发同步写乱 JSON。
- `IntegrationCenter` 是 **@MainActor @Observable**，由 `AppModel` 持有；`IntegrationCache` 是 actor，
  快照读写只在它内部发生。各应用 Client 是无状态 `struct Sendable`，凭据每次从 `SecretStore` 取。
- `FeedClients` / `NotificationScheduler` 是无状态或只读依赖，标 `Sendable`，可跨隔离域调用。
- WKWebView 的 KVO 回调在主线程触发，用 `MainActor.assumeIsolated` 就地更新，避免无意义的 hop。
- 后台任务里 `BGTask` 不是 `Sendable`，用受控包装 `TaskHandle` 跨域传递。

## 地址解析

```
用户覆盖 URL  >  服务内置绝对地址  >  全局模式解析
                                     ├─ 子域名：https://<sub>.<baseDomain><path>      ← 默认（Nginx + HTTPS）
                                     ├─ 子路径：https://<baseDomain>/<sub><path>      ← Nginx 按 location 分流
                                     └─ 端口：  http://<lanHost>:<hostPort><path>     ← 仅排障直连
```

输入会做清洗：粘贴完整 URL 也能用（去协议、去路径、去端口）。
`ServiceURLResolver.isResolvable` 在端口模式缺端口时返回 false，界面上直接标「未配置」，不猜。

`ServiceDefinition` 同时记录 **容器名** 与 **容器内部端口**（来自 `Dockerfile` 的 `EXPOSE`），
这两个值不是给客户端用的，而是给 `deploy/nginx/gen_nginx.py` 生成 upstream 用的——
所以「App 里的地址」和「服务器上的反代」共用同一份事实。

## 页面生命周期

| 场景 | 处理 |
| :-- | :-- |
| 首次进入 | `Coordinator.attach` → `load(URLRequest)`，只加载一次，避免 SwiftUI 重绘导致表单丢失 |
| 站内导航 | 留在同一 WebView；`target="_blank"` 也在同窗打开 |
| 站外链接 | 交给系统浏览器；OAuth 白名单（appleid / google / github / microsoft）留在应用内 |
| 非 HTML 响应 | `WKNavigationResponse.canShowMIMEType == false` → 下载，落到「下载」目录并提示 |
| 加载失败 | 按 `URLError` 分类成中文原因（离线 / 解析失败 / 连接失败 / 证书 / ATS），给重试与「浏览器打开」 |
| 网络恢复 | `NWPathMonitor` 触发 `reloadFromOrigin()`，绕过旧缓存拿新版本 |
| WebContent 进程被回收 | `webViewWebContentProcessDidTerminate` 立即重载，避免白屏 |
| 下拉刷新 | `UIRefreshControl` → 普通 `reload()`，优先命中 Service Worker 缓存 |
| JS 弹窗 | 用原生 `UIAlertController` / `NSAlert` 实现 alert / confirm / prompt（签名带 `@MainActor`，否则系统不会回调） |

## 原生接入

首页点一个应用，先经 `IntegrationRouter.resolve(serviceID:hasExplicitURL:preferWeb:)` 决定去处：

```
通知带具体地址 ──────────────→ 网页（保住「打开某条记录」的语义）
用户勾了「优先网页版」 ───────→ 网页
在 IntegrationCatalog 且未关原生 → 原生
其余 ───────────────────────→ 网页（whoami / 图切恒为网页）
```

原生页与网页版共用同一套地址解析、同一份设计系统（`ServiceGlyph` / `CapsuleTag` /
`EmptyStateView` / `LoadFailureView`），布局统一为「单页滚动 + 顶部指标卡 + 筛选 chips + 行内展开」，
不引入新的视觉语言。

数据通路的固定顺序是**缓存 → 网络 → 合并**：先渲染上次快照（带「更新于 X」），再拉新的；
失败不清缓存，只叠加错误横幅。写操作成功后只刷新受影响的几个接口，不做整页重建。
凭据失效（401/403）时保留缓存可读、禁用写入口，并在顶部挂「重新授权」横幅，不锁死页面。

货殖是唯一有金额写入的应用，且 `POST /api/transactions` 没有幂等键，所以草稿需要状态机：

```
draft → submitting → confirmed
                  ↘ unknown（超时/断连）→ 拉当天流水按金额+账户+日期+描述核对
                                          ├─ 命中：提示已保存
                                          └─ 未命中：交用户决定，禁止再次提交
```

原生提醒复用同一条本地通知链路，但用独立前缀 `integration.` 与独立预算（每应用 12 条、总计 48 条），
清理时按 `integration.<service>.` 前缀收窄范围，绝不误删 `show.` 开头的演出提醒。
详细矩阵、各应用数据流与降级规则见 [INTEGRATIONS.md](./INTEGRATIONS.md)。

## 通知链路

```
页面 JS                    原生                       远端
new Notification() ─┐
showNotification() ─┴→ WebBridgeHandler → Engine.ingest ─→ 账本 → Scheduler → 系统通知
                                                       ↑
ntfy /{topic}/json?poll=1&since=… ──→ FeedClients ─────┤
GET /api/notifications?since=…     ──→ FeedClients ─────┤
GET /v1/events?since=… (中继)       ──→ FeedClients ─────┘
APNs（App 被杀死时）────────────────────────────────→ 系统通知
```

关键点：

1. **统一账本**：三条通道的事件都进 `NotificationLedger`，用同一个键去重。
2. **游标按通道独立**：`服务|feed`、`服务|ntfy`、`服务|relay` 各自推进，互不影响。
3. **未投递 ≠ 丢失**：没有通知权限或离线时只入库不投递，`pendingDelivery` 保留，授权/重连后补发。
4. **投递标识符 = 事件键**：重复投递会替换同一条系统通知，而不是堆叠。

详细契约见 [NOTIFICATIONS.md](./NOTIFICATIONS.md)。

## 存储

| 内容 | 位置 | 说明 |
| :-- | :-- | :-- |
| 设置 | `UserDefaults`（key `zhongmiao.settings.v1`） | 整体 Codable，改即落盘；**不再含任何密钥字段** |
| 凭据 | 钥匙串（service `im.yufei.zhongmiao.integrations`） | `IntegrationCredential` 的 JSON，`AfterFirstUnlockThisDeviceOnly`，不同步 iCloud |
| 接入偏好 | `UserDefaults`（key `zhongmiao.integrations.v1`） | 逐应用的原生开关、优先网页版、提醒开关与时刻；逐字段 `decodeIfPresent` |
| 接入快照 | `Application Support/Zhongmiao/integrations/<id>.json` | `fetchedAt` + payload，原子写，损坏留档 `.corrupt-*.json`，排除备份 |
| ntfy 独立订阅 | `UserDefaults`（key `zhongmiao.ntfy.topics.v1`） | 字符串数组；与设置分开存，避免设置结构演进时整份解码失败 |
| 通知账本 | `Application Support/Zhongmiao/ledger.json` | 上限默认 500 条，原子写；损坏时留档 `ledger.corrupt-*.json` |
| 网页数据 | `WKWebsiteDataStore.default()` | Cookie、localStorage、Service Worker 缓存都在这；清除会退出登录 |
| 下载 | `Documents/下载` | 同名自动加序号，不覆盖 |

旧版的 `mujianToken` / `ntfyToken` / `relaySecret` 三个明文键由 `LegacySecretMigration` 在
读取设置之前迁进钥匙串，验证读回后从原始 JSON 删除；单项失败只保留该项，不清空，重复执行幂等。

## 网页视口

内嵌页面不要用 `viewport-fit=cover`：它会让页面视口延伸到状态栏和导航栏下面，
页面里 `position: fixed` 的顶栏（例如 ntfy 的汉堡菜单）会被系统导航栏压住、点不到。
注入脚本会把页面已有的 `cover` 改写成 `auto`，固定顶栏因此落在导航栏下方。

iOS 26 的悬浮 Tab 栏会占住底部，`.bottomBar` 工具栏不会顶替它、直接被丢掉。
服务页进入时用 `.toolbar(.hidden, for: .tabBar)` 收起 Tab 栏，自带的浏览器工具条才会出现，返回后自动恢复。

## macOS 适配

同一套 `Sources/Shared` 同时被两个 target 编译，差异集中在三处：

- `WebViewHost`：`UIViewRepresentable` / `NSViewRepresentable` 两套壳，共用同一个 `WebCoordinator`。
- `Platform`：打开外链、触觉反馈、下载目录、设备名。
- `WKUIDelegate`：iOS 用 `UIAlertController`（CocoaPods 风格的文件上传交给系统），macOS 用 `NSAlert` + `NSOpenPanel`。

需要 `#if os(...)` 的系统能力（BGTask、`ephemeral` 授权、`allowsInlineMediaPlayback`）都已隔离。
后续做原生 mac 形态时，只需要新增一个 `NavigationSplitView` 版本的外壳，下层无需改动。

分发 macOS 版本还需要补 App Sandbox 的 `com.apple.security.network.client` 权限；
当前为了本机直接跑，没有启用沙盒与签名 entitlements。

## 安全与隐私

- ATS 只对**网页内容**放开（`NSAllowsArbitraryLoadsInWebContent`），原生请求（含原生接入）
  仍受 ATS 约束，只额外放开局域网（`NSAllowsLocalNetworking`）。
- 凭据一律存钥匙串，可访问性 `AfterFirstUnlockThisDeviceOnly`、不同步 iCloud；钥匙串失败直接报错，
  **任何情况下都不回退明文**。密码只用于静默重登，不进日志、不进对话。
- 原生提醒与通知横幅不展示敏感明细：月汐只写「有新的周期提醒」，日志里只有状态与计数。
- 不实现「无条件信任证书」。自签证书请用受信任 CA 或系统描述文件，否则宁可报错也不静默放行。
- 中继用共享密钥（`X-Zhongmiao-Token`，常量时间比较）；未设置密钥会启动时告警。
- 隐私清单 `PrivacyInfo.xcprivacy` 声明了 UserDefaults 与文件时间戳两类 API 用途，不做跟踪、不收集数据。

## 为什么不用其他方案

| 方案 | 为什么没选 |
| :-- | :-- |
| 纯 Safari / 主屏 PWA | 无法解决 iOS 通知失效，也没有统一入口与离线补发 |
| `SFSafariViewController` 承载 | 无法注入 JS 桥、无法观测加载失败、每次都是独立会话，登录态与缓存不可控 |
| 每个应用都重写成完整原生界面 | 12 个应用全量重写成本极高，且会与现有 Web 迭代脱节；实际只做 12 个高频读屏 + 少量可逆写操作，复杂交互留在网页版 |
| 全量离线镜像（自建预缓存） | 需要改 12 个仓库的 SW 契约；现有契约已经统一，壳层不该重复实现 |
