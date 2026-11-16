# 众妙 macOS 平台适配设计方案

> 适用版本：iOS 27 / macOS 27 · 双 target 共享 `Sources/Shared`
> 文档性质：设计规范（含差异对照与组件映射），不含实现
> 界面参考稿：[`design/macos/index.html`](design/macos/index.html)
> 编写日期：2026-11-16

---

## 第 0 章　文档定位与边界声明

### 0.1 这份文档解决什么

众妙的 macOS target 已能编译、能启动，但界面实际上是 iOS 的 `TabView` 原样搬过去：`Sources/macOS/` 只有一个 `AppDelegateMac.swift`，全仓没有任何窗口尺寸约束、菜单栏命令、键盘快捷键或悬停态。本文件要回答的是：

1. iOS 那套视觉语言里，哪些部分在 macOS 上必须原样保留；
2. macOS 的屏幕尺寸、窗口缩放、鼠标与触控板、菜单栏、快捷键怎么落到这套语言上；
3. 两个平台之间到底有哪些差异，每条差异的依据在哪个文件的第几行；
4. 导航骨架可以走哪两条路，各自代价是什么（本文件不替你做选择）。

### 0.2 三条硬边界

| 边界 | 具体含义 |
| :-- | :-- |
| 只做设计 | 本文是规范，不是实现说明。`.swift` / `project.yml` / `Config/*.plist` / `Resources/*` 在本文范围内零改动。第 7 章只列「后续代码阶段要做什么」，不给可直接套用的补丁 |
| 骨架已定 | 第 5 章曾并列路线 A（保留 `TabView` 三页）与路线 B（改 `NavigationSplitView` 侧边栏），**现选定路线 A**；5.2–5.4 保留为决策记录，路线 B 不进入实施范围 |
| 视觉不新建 | 不引入新配色、新圆角体系、新字体、新图标语言。所有平台差异只能是同一套 token 的映射结果 |

### 0.3 为什么「参考现有 iOS 设计」需要先反推

仓库里**没有**独立的 iOS 设计文档、设计稿、Figma/Sketch/Ardot 文件，也没有 UI 截图。`docs/` 下六份文档全部是架构、契约、部署与实施计划；`README.md` 里的「四个关键设计」讲的是架构而非视觉。

真正的设计事实分布在三处：

- **代码**：`Sources/Shared/App/DesignSystem.swift`（语义色、`ServiceGlyph`、`CapsuleTag`、空态与错误态）、`RootView.swift`（三页骨架）、`CatalogView.swift`（栅格与卡片）、`Sources/Shared/Features/Native/*Screen.swift`（12 个原生页的统一范式）；
- **资产**：`Resources/Shared/Assets.xcassets` 的 `AccentColor` / `LaunchBackground` 双色变体、`Resources/Shared/Zhongmiao.icon` 的图标文档；
- **一段文字**：`docs/ARCHITECTURE.md:97-99` 写死了组件清单与布局范式——「原生页与网页版共用同一套地址解析、同一份设计系统（`ServiceGlyph` / `CapsuleTag` / `EmptyStateView` / `LoadFailureView`），布局统一为『单页滚动 + 顶部指标卡 + 筛选 chips + 行内展开』，不引入新的视觉语言」。

因此第 1 章是**从代码反推出来的规格**，不是对某份既有文档的改写。凡本文与代码冲突，以代码为准，冲突点集中记录在第 7.3 节。

### 0.4 阅读路径

- 只想知道两个平台差在哪 → 第 2 章
- 要决定导航骨架 → 第 0 章 + 第 5 章
- 要评审视觉是否走样 → 第 1 章 + 第 4 章
- 准备排后续实现 → 第 3 章 + 第 6 章 + 第 7 章
- 要核对某个数字的出处 → 附录 A

### 0.5 术语

| 标记 | 含义 |
| :-- | :-- |
| **EF** | 既有事实。代码或工程配置已经如此，本文只是转录，附文件行号 |
| **DD** | 设计决策。本文给出的设计规格，尚未落成代码 |
| **EF+DD** | 现状是事实，macOS 侧的做法待设计 |
| 平台化映射 | 同一个语义在两个平台上取各自系统的等价物（如 `zmCard` 在 iOS 取 `.secondarySystemGroupedBackground`、在 macOS 取 `.controlBackgroundColor`） |
| 下层共享视图 | `CatalogView` / `NotificationsView` / `SettingsView` / `ServiceConfigView` / 12 个 `Native/*Screen` 等被两个 target 共同编译的视图 |

---

## 第 1 章　iOS 设计基线摘要

> 本章是第 2、4、6 章与界面参考稿的唯一数值来源。所有数值均取自代码，附出处行号。

### 1.1 视觉 token

#### 颜色

| token | 值 | 出处 |
| :-- | :-- | :-- |
| 强调色 · 亮 | sRGB `0.235 / 0.278 / 0.376` ≈ `rgb(60, 71, 96)` 深石板蓝 | `AccentColor.colorset/Contents.json:4-13` |
| 强调色 · 暗 | sRGB `0.804 / 0.831 / 0.886` ≈ `rgb(205, 212, 226)` 浅蓝灰 | 同上 `:15-31` |
| 启动背景 · 亮 | sRGB `0.976` 三通道 ≈ `rgb(249, 249, 249)` | `LaunchBackground.colorset/Contents.json:3-13` |
| 启动背景 · 暗 | sRGB `0.063 / 0.067 / 0.071` ≈ `rgb(16, 17, 18)` | 同上 `:16-31` |
| `zmGrouped`（分组底） | iOS `.systemGroupedBackground` ↔ macOS `.windowBackgroundColor` | `DesignSystem.swift:30-37` |
| `zmCard`（卡片底） | iOS `.secondarySystemGroupedBackground` ↔ macOS `.controlBackgroundColor` | `DesignSystem.swift:39-46` |
| 语义色 | `.primary` / `.secondary` / `.tertiary` / `.separator` / `.tint` / `.bar` / `.accentColor`，未做任何自定义 | 全局 |
| 状态色 | `.green`（离线可用）/ `.orange`（未配置、凭据未知）/ `.red`（未读、凭据失效）/ `.purple`（开演倒计时）；macOS 首页行内只保留 `.orange` 与 `.red`，`.green` 改由 tooltip 承载（见 3.1） | `CatalogView.swift:320-329`、`IntegrationStatusBanner.swift:4-13` |
| 十六进制解析 | `Color(hex:)`，支持 3 位与 6 位，sRGB，无 `#` | `DesignSystem.swift:11-28` |

#### 服务色板（14 组，唯一事实来源）

| 服务 | id | tint | SF Symbol | 分类 |
| :-- | :-- | :-- | :-- | :-- |
| 慎始 | `shenshi` | `5B5BD6` | `checklist` | 效率与任务 |
| 幕间 | `mujian` | `8E5BD9` | `theatermasks` | 影像与媒体 |
| 拾帧集 | `bili-history` | `D9527A` | `play.square.stack` | 影像与媒体 |
| 流霞 | `liuxia` | `C96A9B` | `photo.stack` | 影像与媒体 |
| 图切 | `tuqie` | `6B7A8F` | `scissors` | 影像与媒体 |
| 货殖 | `huozhi` | `B8862F` | `chart.pie` | 财务 |
| 吾身 | `diarum` | `4C8DF6` | `book.closed` | 知识与阅读 |
| 青野集 | `qingye` | `3F9A6B` | `leaf` | 知识与阅读 |
| 察新 | `chaxin` | `4E8299` | `newspaper` | 知识与阅读 |
| 牵丝 | `qiansi` | `8F63C9` | `point.3.filled.connected.trianglepath.dotted` | 知识与阅读 |
| 月汐 | `yuexi` | `6E7BD4` | `moon.stars` | 生活 |
| ntfy | `ntfy` | `2A9D8F` | `bell.badge` | 基建与运维 |
| 蜂巢 | `qbhive` | `3B82C4` | `arrow.down.circle.fill` | 基建与运维 |
| whoami | `whoami` | `6B7280` | `network` | 基建与运维 |

出处：`Packages/ZhongmiaoCore/Sources/ZhongmiaoCore/ServiceCatalog.swift:16-175`。注册表自带校验，色值必须是 6 位十六进制（`:221`）。

#### 分类标题与图标（6 组）

| 分类 | 标题 | SF Symbol |
| :-- | :-- | :-- |
| `productivity` | 效率与任务 | `checklist` |
| `media` | 影像与媒体 | `photo.on.rectangle.angled` |
| `finance` | 财务 | `chart.line.uptrend.xyaxis` |
| `knowledge` | 知识与阅读 | `books.vertical` |
| `infrastructure` | 基建与运维 | `server.rack` |
| `life` | 生活 | `leaf` |

出处：`ServiceDefinition.swift:41-61`。

#### 形状

| 元素 | 值 | 出处 |
| :-- | :-- | :-- |
| 主卡片圆角 | 16，`.continuous` | `CatalogView.swift:340` |
| 指标卡圆角 | 12 | 各 `Native/*Screen.swift` 的 `metric` |
| 搜索框圆角 | 9 | `IntegrationSearchField.swift:55` |
| 服务图标圆角 | `size * 0.28`（44 → 12.32；40 → 11.2） | `DesignSystem.swift:58` |
| 胶囊 | 无数值，用 `Capsule()` | `DesignSystem.swift:99` |
| 进度条 | 3 | `MujianScreen.swift` 的 statBar |

#### 间距

| 位置 | 值 | 出处 |
| :-- | :-- | :-- |
| 页面水平内边距 | 16 | `CatalogView.swift:34` |
| 页面顶部 / 底部 | 8 / 24 | 同上 |
| 卡片内边距 | 12 | `CatalogView.swift:333` |
| 卡片主纵向间距 | 10 | `CatalogView.swift:283` |
| 卡片标题组间距 | 2 | `CatalogView.swift:304` |
| 标签行间距 | 4 | `CatalogView.swift:316` |
| 分组纵向间距 | 18 | `CatalogView.swift:34` 外层 `VStack` |
| 网格间距 | 12 | `CatalogView.swift:27` |
| 卡片最小高度 | 132（无障碍字号 160） | `CatalogView.swift:334-338` |
| 空态内边距 | 24 | `DesignSystem.swift:159` |
| 错误态内边距 / 最大宽 | 28 / 420 | `DesignSystem.swift:194-195` |

#### 阴影、描边、渐变

| 元素 | 值 | 出处 |
| :-- | :-- | :-- |
| 卡片阴影 | `black.opacity(暗色为 0，亮色 0.04)`，`radius 6`，`y 2` | `CatalogView.swift:342-346` |
| 卡片描边 | `.separator.opacity(0.35)`，`lineWidth 0.5` | `CatalogView.swift:350` |
| 图标渐变 | `tint.opacity(0.95) → tint.opacity(0.72)`，`.topLeading → .bottomTrailing` | `DesignSystem.swift:60-68` |
| 图标内符号 | 白色，`size * 0.44`，`weight .medium` | `DesignSystem.swift:70-72` |
| 横幅底色 | `.bar` | `DesignSystem.swift:126` |
| 胶囊标签底色 | `tint.opacity(0.16)` | `DesignSystem.swift:99` |

#### 字体

无自定义字体，全部使用系统语义字号，跟随 Dynamic Type。实际使用频次：`.caption` 82 处、`.caption2` 75 处、`.subheadline` 24 处、`.footnote.weight(.semibold)` 9 处、`.title3.weight(.semibold)` 9 处、`.headline` 8 处、`.body` 2 处。

固定字号仅 6 处：`ServiceGlyph` 的 `size*0.44`、空态图标 40/`.light`、错误态图标 38/`.light`、置顶图钉 9、概览条目图标 12。

#### 栅格

```
LazyVGrid(.adaptive(minimum: 158, maximum: 260), spacing: 12, alignment: .top)
无障碍大字号：minimum 300 / maximum .infinity（退化为单列）
```

出处：`CatalogView.swift:20-30`。

### 1.2 组件清单

| 组件 | 关键参数 | 出处 | 视觉描述 |
| :-- | :-- | :-- | :-- |
| `ServiceGlyph` | `size` 缺省 44；圆角 `size*0.28`；渐变 `0.95→0.72`；符号 `size*0.44` | `DesignSystem.swift:53-77` | 圆角方形色块 + 白色 SF Symbol，`accessibilityHidden` |
| `CapsuleTag` | `.caption2`；内距 h6/v2；底色 `tint.opacity(0.16)` | `DesignSystem.swift:81-101` | 小胶囊标签，图标与文字同色系 |
| `OfflineBanner` | `.footnote`；内距 h12/v7；底色 `.bar` | `DesignSystem.swift:105-129` | 整宽横幅，`wifi.slash` 或 `ProgressView(.mini)` |
| `EmptyStateView` | 图标 40/`.light`；内距 24；按钮 `.borderedProminent` | `DesignSystem.swift:133-162` | 居中空态：图标 + 标题 + 说明 + 可选操作 |
| `LoadFailureView` | 图标 38/`.light`；内距 28；最大宽 420 | `DesignSystem.swift:166-197` | 加载失败：图标 + 标题 + 详情 + 重试 / 在浏览器打开 |
| `RelativeTime` | `short` / `dayHeader` | `DesignSystem.swift:201-217` | 「刚刚 / N 分钟前 / 今天 / 昨天」 |
| `zmPlainTextInput` | iOS 关自动大写与自动纠错；macOS 仅关自动纠错 | `DesignSystem.swift:221-233` | 地址类输入的统一修饰 |
| `ServiceCard` | 见 1.1 全部形状与间距；`minHeight 132/160` | `CatalogView.swift:267-362` | 首页服务卡：Glyph 40 + 名称 + 摘要 + 标签行 + 置顶图钉 + 未读胶囊 |
| `Pasteboard` | iOS `UIPasteboard`；macOS `NSPasteboard` | `CatalogView.swift:364-373` | 复制地址 |
| toast 浮层 | `.regularMaterial, in: Capsule()`；描边 `.separator` 0.5；底部 76；2.6 秒 | `RootView.swift:89-111` | 底部居中胶囊提示，减弱动态效果时改为纯淡入 |

### 1.3 界面地图

```
RootView（TabView）
├── 应用 · square.grid.2x2 ── NavigationStack(catalogPath)
│   └── CatalogView
│       ├── 今日概览卡 HomeDigestCard
│       ├── 搜索命中卡 HomeSearchHitsCard（.searchable 时）
│       ├── 分类分组 × 6 → LazyVGrid → ServiceCard × 14
│       └── footer 统计与说明
├── 通知 · bell ── NavigationStack(inboxPath) · .badge(未读数)
│   └── NotificationsView（权限提示 / 按应用汇总 / 按天分组 / 空态）
└── 设置 · gearshape ── NavigationStack
    └── SettingsView（接入方式 / 服务 / 通知 / ntfy / 演出 / 中继 / 诊断 / 数据 / 关于）
         ├── ServiceSettingsListView → ServiceConfigView
         ├── NtfyTopicsView → ServiceConfigView(ntfy)
         └── DiagnosticsView → ServiceConfigView
```

| 层级 | 页面 | 容器 | 主要交互 |
| :-- | :-- | :-- | :-- |
| 一级 | 应用 | `ScrollView` + `LazyVGrid` | 搜索、同步、右键菜单、`.sheet` 配置 |
| 一级 | 通知 | `List` + `Section` | 筛选菜单、左滑、下拉刷新、点行直达 |
| 独立窗口 | 设置（`Settings` 场景） | `MacSettingsPage`（`ScrollView`）+ `MacSettingsGroup` × 10 | `Picker` / `Toggle` / `Stepper` / 跳转行 / 分组卡片 |
| 二级 | 服务与接入 | macOS：`MacSettingsPage` + 分类卡片；iOS：`List` | 进入单服务配置 |
| 二级 | 单服务配置 | macOS：`MacSettingsPage` + 9 组卡片；iOS：`Form` + 9 个 `Section` | 凭据、地址、通知、能力开关 |
| 二级 | ntfy 主题 / 诊断 | macOS：分组卡片；iOS：`Form` / `List` | 订阅、检测、日志 |
| 二级 | 网页版服务页 | `ZStack` + `WebView` + 进度条 | 浏览、更多菜单 |
| 二级 | 原生页 × 12 | `List` + 指标卡 + 筛选 chips | 刷新、搜索、行内展开、`.sheet` 表单 |

原生页统一范式（`docs/ARCHITECTURE.md:97-99`）：**单页滚动 + 顶部指标卡（圆角 12，`tint.opacity(0.08)` 底）+ 筛选 chips（`Capsule`，选中 `Color.accentColor` / 未选 `Color.secondary.opacity(0.12)`）+ 行内展开**。

---

## 第 2 章　iOS 与 macOS 差异点矩阵

> 每条都挂行号。分类见 0.5 节：EF 既有事实、DD 设计决策、EF+DD 现状是事实而 macOS 做法待设计。

### 2.1 窗口与尺寸

| 条目 | iOS 现状 | macOS 现状或目标 | 分类 |
| :-- | :-- | :-- | :-- |
| Scene 定义 | 裸 `WindowGroup { RootView() }`，无任何窗口修饰 | 同一个 `WindowGroup`，同样无修饰 | EF（`ZhongmiaoApp.swift:16-25`） |
| 初始 / 最小窗口尺寸 | 不适用（全屏或分屏） | 初始 1180×760，最小 720×480，内容最大宽 1180 居中 | DD（见 3.2） |
| 窗口缩放断点 | 不适用 | 620 / 940 两个内容宽断点，驱动分类分栏的栏数（1 / 2 / 3）；另设内容最大宽 1180 | DD（见 3.1） |
| 首页入口布局 | `LazyVGrid(.adaptive 158–260)` 卡片栅格，单卡 `minHeight 132` | 分类分栏（1–3 栏，按原顺序流式切分）+ 行条目（高 44）；16 圆角卡片层级上移到分类块 | DD（见 3.1） |
| toast 底部间距 | 76，为 iOS 26 悬浮 Tab 栏预留 | macOS 无底部 tab bar，间距应回落到 24 | EF+DD（`RootView.swift:101`） |
| 紧凑宽度收起 Tab 栏 | `horizontalSizeClass == .compact` 时 `.toolbar(.hidden, for: .tabBar)` | 无对应概念，整段跳过 | EF（`ServiceScreen.swift:16-18, 63-69`） |
| 部署目标 | iOS 27.0 | macOS 27.0 | EF（`project.yml:5-7`） |
| LaunchScreen | `UILaunchScreen.UIColorName = LaunchBackground` | 无启动屏概念，不适用 | EF（`project.yml:59-60`） |

### 2.2 导航与信息架构

| 条目 | iOS 现状 | macOS 现状或目标 | 分类 |
| :-- | :-- | :-- | :-- |
| 根骨架 | `TabView(selection:)` 三页 + 每页 `NavigationStack`，**全文件无 `#if`** | 原样共用同一份 `TabView`，渲染为窗口内顶部标签（路线 A，见第 5 章） | EF（`RootView.swift:16-42`） |
| Tab 图标与角标 | `square.grid.2x2` / `bell` / `gearshape`，通知页 `.badge(unreadCount)` | 同一套，但 macOS 的 TabView 渲染为窗口内标签，无底部栏 | EF（`RootView.swift:24-41`） |
| 深链消费 | `consumePendingRoute()` 强制 `tab = .catalog` 并 append 到 `catalogPath` | 同一逻辑原样复用，路线 A 下不需要改（无侧栏选中项要同步） | EF（`RootView.swift:56-61`） |
| 浏览器导航工具条 | `.bottomBar` 后退/前进/刷新停止/`ShareLink` | 整组被 `#if os(iOS)` 排除，macOS 无此工具条 | EF+DD（`ServiceScreen.swift:119-155`） |
| 服务页更多菜单 | `.primaryAction` `ellipsis.circle`：强制刷新、在浏览器打开、复制地址、通知开关、检测、服务设置 | 同一菜单在 macOS 落到窗口工具栏，功能完整 | EF（`ServiceScreen.swift:157-210`） |
| 设置入口 | 三页之一 | 独立 `Settings` 场景窗口，主窗口只剩「应用 / 通知」两页；`⌘,`、工具栏齿轮、`⌘3` 都能打开 | EF（`ZhongmiaoApp.swift:37-44`） |
| 侧边栏 | 无 | 无 `NavigationSplitView`；评估后搁置，不进入实施范围（第 5 章） | EF（全仓 0 处） |
| 多窗口 | 不适用 | `WindowGroup` 天然多开；每个窗口各自持有 `tab`，路线 A 下互不影响 | EF（`ZhongmiaoApp.swift:17`） |
| 菜单栏命令 | 不适用 | 无 `.commands` / `CommandGroup` / `CommandMenu` | EF（全仓 0 处） |
| 状态栏常驻 | 不适用 | 无 `MenuBarExtra` | EF（全仓 0 处） |

### 2.3 输入与交互

| 条目 | iOS 现状 | macOS 现状或目标 | 分类 |
| :-- | :-- | :-- | :-- |
| 右键菜单 | `.contextMenu`：在浏览器打开、复制地址、检测、置顶、隐藏、服务设置 | 同一个 `.contextMenu` 即 macOS 右键菜单，可直接用 | EF（`CatalogView.swift:199-250`） |
| 悬停反馈 | 不适用 | 全仓 0 处 `.onHover` / `pointerStyle`，需设计 | DD（见 3.3） |
| 左滑操作 | `.swipeActions(edge: .trailing, allowsFullSwipe: true)`：删除、标已读 | 无平台分支，靠触控板横向轻扫；需补右键与行内按钮替代 | EF+DD（`NotificationsView.swift:232-245`） |
| 触控板横扫前进后退 | 不适用 | `allowsBackForwardNavigationGestures = true` 双平台均已开启 | EF（`InAppBrowserSheet.swift:79, 122`） |
| 键盘类型 / 自动大写 | `.keyboardType`、`.textInputAutocapitalization(.never)` | 均被 `#if os(iOS)` 包裹；macOS 用 `.zmPlainTextInput()` 只关自动纠错 | EF（`DesignSystem.swift:221-233`） |
| 导航栏标题模式 | `.navigationBarTitleDisplayMode(.inline)` | 被 `#if os(iOS)` 包裹，macOS 跳过 | EF（`ServiceScreen.swift:63-69` 等） |
| 下拉刷新 | 网页容器 `.refreshable` 仅 iOS；列表类跨平台 | 列表类在 macOS 同样生效，网页容器需另设刷新入口 | EF（`WebViewHost.swift:12-19`） |
| 分享 | `ShareLink` 仅 iOS bottomBar | macOS 用「在浏览器打开 / 复制地址」替代 | EF+DD（`ServiceScreen.swift:150-153`） |
| 键盘快捷键 | 不适用 | 全仓 0 处 `.keyboardShortcut` | EF+DD（见 3.5） |
| 焦点 | `@FocusState` 仅搜索框 | macOS 需补焦点环与 ⌘F 聚焦 | EF+DD（`IntegrationSearchField.swift:16, 28`） |
| 触觉反馈 | `UINotificationFeedbackGenerator` / `UIImpactFeedbackGenerator` | `NSHapticFeedbackManager.defaultPerformer(.generic)` | EF（`Platform.swift:22-39`） |
| 点击目标尺寸 | 跟随行高，未约束 | macOS 需保证 ≥ 28×28 | DD（见 3.3） |

### 2.4 系统级集成

| 条目 | iOS 现状 | macOS 现状或目标 | 分类 |
| :-- | :-- | :-- | :-- |
| App 生命周期 | `UIApplicationDelegate`（`AppDelegate`） | `NSApplicationDelegate`（`MacAppDelegate`），`NSApp.setActivationPolicy(.regular)` | EF（`AppDelegateMac.swift:6-9`） |
| 前台回调 | SwiftUI Scene 下 `applicationDidBecomeActive` 不派发，改挂 `scenePhase` | `MacAppDelegate.applicationDidBecomeActive` 与 `scenePhase` 双路径 | EF（`ZhongmiaoApp.swift:26-43`、`AppDelegateMac.swift:11-13`） |
| 关窗行为 | 不适用 | SwiftUI 缺省「关窗不退出」，工程未配 `NSSupportsAutomaticTermination` | EF（`Info-macOS.plist` 无该键） |
| Dock 菜单 | 不适用 | 无 `applicationDockMenu`，无 `applicationShouldTerminateAfterLastWindowClosed` | EF（`AppDelegateMac.swift` 全 32 行） |
| 打开外链 | `UIApplication.shared.open` | `NSWorkspace.shared.open` | EF（`Platform.swift:13-19`） |
| 跳系统设置 | `UIApplication.openSettingsURLString` | `x-apple.systempreferences:com.apple.preference.notifications` | EF（`NotificationsView.swift:156-166`） |
| 下载目录 | `Documents/下载` | `~/Downloads/众妙` | EF（`Platform.swift:59-72`） |
| 设备名 | `UIDevice.current.name` | `Host.current().localizedName` | EF（`Platform.swift:42-48`） |
| 剪贴板 | `UIPasteboard.general.string` | `NSPasteboard.general.clearContents()` + `setString(_:forType:.string)` | EF（`CatalogView.swift:364-373`） |
| 深链 | `zhongmiao://`（免费账号无 Universal Links） | 同一 scheme，工程已配置 | EF（`project.yml:159-163`） |
| 后台刷新 | `BGAppRefreshTask`，标识 `im.yufei.zhongmiao.refresh` | macOS 无 BGTask；依赖进程存活轮询 | EF（`project.yml:89-90`、`Info-iOS.plist`） |
| 通知权限 | `UNAuthorizationOptions`，`.ephemeral` 视为允许 | `.ephemeral` 不参与判定 | EF（`NotificationScheduler.swift:31-36`） |

### 2.5 能力与生命周期

| 条目 | iOS 现状 | macOS 现状或目标 | 分类 |
| :-- | :-- | :-- | :-- |
| 灵动岛 / 实时活动 | ActivityKit + Widget Extension，`NSSupportsLiveActivities` | 无（macOS SDK 无该能力，Widget target 仅 iOS 依赖） | EF（`project.yml:41, 101-124`、`Show.swift:206-212`） |
| 开演闹钟 | AlarmKit（iOS 26+），`NSAlarmKitUsageDescription` | macOS SDK 无 AlarmKit | EF（`Sources/iOS/ShowAlarmSection.swift`、`project.yml:81-82`） |
| 日历 / 提醒事项写入 | EventKit，两种完整访问描述 | 无对应权限键，不实现 | EF（`project.yml:77-80`） |
| 相机 / 相册 / 麦克风 | 三项描述齐全 | 只有相机与相册，无麦克风 | EF（对比 `project.yml:83-85` 与 `:157-158`） |
| 网页容器 UA | `Zhongmiao/0.1`，`scriptVersion 4` | 同一 UA 与脚本版本 | EF（`WebViewFactory.swift:66, 76`） |
| 容器标记 | `data-zhongmiao-container="ios"`，**写死** | 同样注入 `ios`，需改为按平台取值 | EF+DD（`WebViewFactory.swift:224`） |
| 内联播放 | `mediaPlaybackBehavior = .allowsInlinePlayback` | 该配置仅 iOS | EF（`WebViewFactory.swift:78-81`） |
| 沙盒与签名 | 无 entitlements（本机直接跑） | 同样无 entitlements，分发需补 `com.apple.security.network.client` | EF（`project.yml` 无 `entitlements:`） |
| 开机自启 / 登录项 | 不适用 | `SMAppService` 需 Developer ID + 公证，免费账号不可用 | EF（能力边界，见 7.2） |
| Widget 依赖 | 主 App 依赖 `ZhongmiaoWidget` | 不依赖 | EF（`project.yml:39-41` 对比 `:135-136`） |

### 2.6 视觉与材质

| 条目 | iOS 现状 | macOS 现状或目标 | 分类 |
| :-- | :-- | :-- | :-- |
| 分组底色 | `.systemGroupedBackground` | `.windowBackgroundColor` | EF（`DesignSystem.swift:31-37`） |
| 卡片底色 | `.secondarySystemGroupedBackground` | `.controlBackgroundColor` | EF（`DesignSystem.swift:39-46`） |
| 强调色 | 亮 `rgb(60,71,96)` / 暗 `rgb(205,212,226)` | 同一 Asset Catalog，双端共用 | EF（`AccentColor.colorset`） |
| 卡片阴影 | 亮 0.04 / 暗 0 | 同一算式；macOS 窗口内阴影更淡，可保持不动 | EF（`CatalogView.swift:342-346`） |
| 首页入口形态 | 132pt 竖向卡片：Glyph 40 在上、名称/摘要/标签在下，6 个分类纵向堆叠 | 44pt 横向行条目：Glyph 28 在左、名称与摘要同一基线、状态在右；分类块横向分栏 | DD（见 3.1） |
| 材质 | `.regularMaterial`（toast）、`.bar`（横幅） | 落到 macOS 的 vibrancy，视觉强度略有差别 | EF+DD（`RootView.swift:96`、`DesignSystem.swift:126`） |
| 语义色呈现 | `.separator` / `.tertiary` / `.tint` 由系统解析 | 同一语义，两平台取值不同，属映射结果 | DD |
| 字体 | 全语义字号，支持 Dynamic Type | macOS 无 Dynamic Type，语义字号按 macOS 字号表渲染 | EF+DD |
| 无障碍 | Dynamic Type、VoiceOver、减弱动态效果 | VoiceOver 可用；减弱动态效果需单独读 `accessibilityReduceMotion` | EF |

---

## 第 3 章　macOS 平台特性逐项适配设计

> 每节按「现状 → 设计要点 → 沿用 / 映射 / 禁改 → 后续代码阶段项」组织。设计要点是 DD，落地在后续代码阶段。

### 3.1 宽屏信息架构：分类分栏 + 紧凑入口

**现状**：栅格是 `adaptive(minimum: 158, maximum: 260)`，间距 12（`CatalogView.swift:20-30`）。这是 iPhone 竖屏的最优解——单列宽度受屏幕限制，卡片要装下 44pt 命中区加三行文本，因此 `minHeight 132`、最小宽 158 是触控下限的自然结果。

**照搬到 macOS 会同时犯两个错**：

1. **竖屏思维**。iOS 是「单列分类从上往下滚」，macOS 窗口是横向的。若只把卡片多排几列、分类仍一段一段往下堆，宽屏的横向空间只用来把同一张卡片摊宽，信息结构本身没变：1180×760 下 14 个入口仍排不进一屏（核算见下）。
2. **触控尺寸**。132pt 高的卡片服务于手指。鼠标指针的命中精度是 1pt 量级，macOS HIG 的行基准是 22–28pt。132pt 在桌面上属于巨物，同屏能承载的入口数量被压掉约 3 倍。

**设计要点 1：分类块横向分栏（column flow）**

6 个分类不再纵向堆叠，而是按 `ServiceDefinition` 的原始枚举顺序**流式切分**成 N 栏，栏内纵向、栏间横向：

| 内容宽 W | 栏数 | 栏宽 | 落点 |
| :-- | :-- | :-- | :-- |
| ≥ 940 | 3 | ≥ 300 | 初始 1180 窗口（内容 1132 → 364） |
| 620 – 940 | 2 | 300 – 460 | 最小 720 窗口（内容 672 → 326）；横向被分屏削掉约 200 时也落这一档 |
| < 620 | 1 | ≤ 620 | 极窄分屏，退化回 iOS 的纵向顺序 |

阈值不是按窗口宽度拍的，而是按**栏宽下限 300** 反推：行内要同时放下 Glyph 28、名称、摘要与状态，栏宽低于 300 时摘要只剩 4–6 字，等于失去信息价值。因此判定条件是「栏宽够不够」，不是「窗口有多宽」。

分栏归属见下表——分类数与每类条目数都由注册表决定，切分时按公式估算高度即可，不需要测量实际渲染高度：

| 断点 | 第 1 栏 | 第 2 栏 | 第 3 栏 |
| :-- | :-- | :-- | :-- |
| 3 栏 | 效率与任务(1) + 影像与媒体(4) | 财务(1) + 知识与阅读(4) | 基建与运维(3) + 生活(1) |
| 2 栏 | 效率与任务(1) + 影像与媒体(4) + 财务(1) | 知识与阅读(4) + 基建与运维(3) + 生活(1) | — |

分栏后阅读顺序仍是「效率 → 影像 → 财务 → 知识 → 基建 → 生活」的注册表顺序，不重排分类。

**栏数由栏宽下限决定，与窗口总宽无关**：横向每被削掉约 200pt，栏宽就掉一档。这条约束最初由已搁置的路线 B 验证——侧栏占 226pt 后 detail 内容降到 922，若仍按 3 栏排，栏宽只剩 294，摘要会被截成 4–6 字（「B 站观看历史与统计」只剩「B…」）。同一约束现在作用于分屏与最小窗口：720 窗口内容 672，落进 2 栏。

**不强行等高**：各栏独立向下堆叠，栏底不平齐。3 栏时最高 338、最矮 294，差一个行高（44）；强行拉平会在矮栏底部留出空洞，比参差更难看。

**设计要点 2：入口从卡片降为行条目**

行条目高 44，横向排布：`[Glyph 28] 名称 · 摘要 …………… [标签 / 未读]`。

| 项 | 值 | 依据 |
| :-- | :-- | :-- |
| 行高 | 44（大字号 56） | ≥ macOS HIG 命中区 28，含上下各 8 呼吸 |
| 行内水平距 | 8 | 与分类卡 12 内距错开一级 |
| Glyph | 28，圆角 `28×0.28 = 7.84`，符号 `28×0.44 = 12.32` | 沿用 `ServiceGlyph` 的比例公式，不新增尺寸 token（`DesignSystem.swift:58, 70-72`） |
| 名称 | 13，`.semibold`，最小列宽 72 | 与 iOS 卡片标题同字号；最小列宽让摘要起点对齐成一列（见下） |
| 摘要 | 11.5，`secondary`，单行截断，起点对齐 | 宽屏一行放得下，不必换行 |
| 状态槽 | 右对齐，**只放信号**：未读数字 /「未配置」/「已隐藏」；能力标签不进列表 | 见下「状态槽只放信号」 |
| 行间分隔 | 0.5pt `separator.opacity(0.35)`，末行不画 | 与卡片描边同一档 |
| 悬停 | 行底 `separator.opacity(0.06)`（亮）/ `0.12`（暗），圆角 8 | 见 3.3 |

**状态槽只放信号，不放能力**

行条目右端不再出现「离线可用」「需要联网」。理由不是省一个标签的斤两：这个标签在 14 个入口里出现 12 次、形态与颜色完全相同，对「我该点哪个」零区分度，却每行吃掉右端 58–66pt。44pt 的行里没有这么多余量——iOS 的 132pt 竖卡是上下堆叠，横向随便占；macOS 的行是横向排布，Glyph、名称、摘要已经在抢同一根轴。

能力信息没有删，只是换了零空间成本的载体：

| 载体 | 呈现 | 空间成本 |
| :-- | :-- | :-- |
| 悬停 tooltip | `.help("离线可用 · 断网也能打开")`，指针停留后由系统气泡显示 | 0 |
| 右键菜单信息项 | 菜单顶部分隔出的只读行，与「打开原生页 / 打开网页版」同组 | 0 |
| 设置 → 服务与接入 | 「显示服务能力标签」开关，打开后行尾恢复标签 | 0 |

**语义边界**：能力 ≠ 状态。能力是恒定属性（自带 Service Worker，断网也能打开），状态是真告警（未配置、已隐藏、凭据失效）。前者随开关走，后者永远显示。`CatalogView.swift:320-329` 已经是这个结构——`showsCapabilityTag && isOfflineReady` 才出「离线可用」，而 `!isConfigured` 的「未配置」在 `:327` 独立判断，不受开关影响。macOS 侧只改开关的**平台初值**，判定逻辑一行不动。

**回收的宽度**：3 栏栏宽 364，扣卡片内距 24、行内水平距 16、Glyph 28 与前后间距 16，剩 280 分给名称与摘要。旧形态里名称取自然宽（最长 3 字 ≈ 39）、右端标签 ≈ 66 加 6 间距，摘要只剩 ≈ 169；去掉标签、名称改为 72 定宽后，摘要拿到 ≈ 208。净增约 39pt（≈ 3 个汉字），同时摘要起点从参差变成一条竖线。

**为什么名称要定宽**：去掉标签之后，行里只剩「名称 + 摘要」两段文字，摘要起点就会跟着名称长短浮动——「慎始」（26）与「拾帧集」（39）错开 13pt，读的时候眼睛每行都要重新找起点。给名称一个 72 的最小列宽，起点对齐成一列，代价是短名多占几 pt 空白。这不是新增 token：72 ≈ 3 个汉字加余量，`whoami` 这类拉丁名（≈ 52）也放得下。

**开关初值的实现边界**：`AppSettings.showServiceCapabilityTags` 现在的解码是 `decodeIfPresent(Bool.self, forKey:) ?? true`（`AppSettings.swift:173`）。macOS 上初值为关，需要把那个 `true` 换成按平台的常量，例如 `?? Self.defaultShowsCapabilityTags`，其中 iOS 分支是 `true`、macOS 分支是 `false`。iOS 与 macOS 是两个独立 App、各自一份 `UserDefaults`，改初值不会串到对方（且项目无 CloudKit 同步）。

**卡片层级上移**：16 圆角 + `zmCard` 底 + `separator 0.35 / 0.5pt` 描边 + 阴影 `r6 y2 0.04` 这一整套，从「每个入口一张」上移到「每个分类一张」。因此视觉上仍是同一套卡片语言（不是系统 `List` 分组样式），只是卡片承载的单位从「一个服务」变成「一个分类区段」。

**密度核算**（内容宽 1132、3 栏）：

- 分类块高 = `12(上内距) + 18(标题行) + 8(标题下距) + 44N + 12(下内距)`；
- 栏 1 = 94 + 18 + 226 = 338，栏 2 = 94 + 18 + 226 = 338，栏 3 = 182 + 18 + 94 = 294；
- 取最高 338。窗口 760 扣掉标题栏 38、工具栏约 60、上下留白 40，可用约 620，**14 个入口一屏可见且有余量**；
- 旧方案（5 列卡片栅格）同一窗口：6 组 `18+9` 标题 + 6 行 132 卡片 + 5 处 18 组间距 ≈ 1044，超出这一屏，必须滚动。纵向占用降到约 1/3。

**搜索命中与概览卡**：`HomeDigestCard` 与搜索命中保留在分栏之上、跨满内容宽。搜索命中改为**单栏行列表**——结果通常只有几条，分栏会把相关性割裂到不同列。

**无障碍退化**：macOS 无 Dynamic Type，但「辅助功能 → 显示 → 文本大小」会放大系统字号。放大后行高由 44 提到 56，名称与摘要改为纵向两行，栏数不变；不退回单列卡片。

**沿用 / 映射 / 禁改**：沿用 14 组 tint、Glyph 比例公式、`CapsuleTag`、语义字号；沿用 16/12/9 圆角阶梯与 0.5pt 描边；不新增栅格或尺寸 token；**不改 iOS 侧的 `LazyVGrid` 与 `ServiceCard`**。

**后续代码阶段项**：`Sources/macOS/` 新增分类分栏容器（外层 `HStack(alignment: .top)` + 每栏 `VStack`）；行条目作为 macOS 分支的入口视图，`ServiceCard` 的 iOS 路径不动。上表是当前 6 个分类下的结果，注册表增删分类后会失效——切分应实现为**顺序装箱**：按注册表顺序依次放入当前栏，累计高度超过「总高 ÷ 栏数 × 1.2」时换下一栏，累计高度用 `50 + 44N` 估算（N 为该分类的服务数）。现有数据下 3 栏目标 402、2 栏目标 604，得到的分栏与上表逐项一致；新增分类时不需要改表，也不会打乱分类顺序。

### 3.2 窗口自由缩放与最小尺寸

**现状**：`WindowGroup { RootView() }`，没有 `.defaultSize`、`.windowResizability`、`.windowStyle`（`ZhongmiaoApp.swift:16-25`）。macOS 会用一个内容驱动的最小尺寸开窗，`LazyVGrid` 在窄窗下可能只剩一列。

**设计要点**：

| 项 | 数值 | 理由 |
| :-- | :-- | :-- |
| 初始窗口 | 1180 × 760 | 3 栏（内容 1132 → 栏宽 364），6 个分类与 14 个入口一屏可见；再宽只增栏宽，不增到 4 栏 |
| 最小窗口 | 720 × 480 | 2 栏（内容 672 → 栏宽 326），纵向需滚动约 1.4 屏；工具栏与搜索保持单行 |
| 内容最大宽 | 窗口内容区 1180，减去左右各 24 页边距后可用 1132，水平居中 | 与 3.1 一致 |
| 缩放策略 | 内容最小尺寸（`.contentMinSize`） | 允许放大到任意尺寸，但拒绝小于最小窗口 |
| 工具栏 | 统一窗口工具栏，`.primaryAction` 放同步与更多菜单 | 与现有 `.toolbar` 结构对齐，不新造工具栏 |

**缩放时的行为**：

- 栏数按 3.1 的曲线变化（3 → 2 → 1），**不做横向滚动**；
- 行条目高度固定 44，不随栏宽拉伸；行内摘要单行截断，不因窗口变宽而展开；
- 窗口高度不足时垂直滚动，顶部工具栏固定。

**沿用 / 映射 / 禁改**：不引入新的窗口材质、不套 `NSVisualEffectView` 自定义背景；窗口背景即 `zmGrouped`。

**后续代码阶段项**：`WindowGroup` 上补 `defaultSize` / `windowResizability`；`RootView` 内补内容最大宽与居中。

### 3.3 鼠标与触控板

**现状**：全仓 0 处 `.onHover`、0 处 `pointerStyle`。右键菜单只有首页卡片有（`CatalogView.swift:199-250`），通知行靠 `.swipeActions`（`NotificationsView.swift:232`），触控板横扫已在应用内浏览器开启（`InAppBrowserSheet.swift:79, 122`）。

**设计要点**：

1. **悬停（hover）**。只做「可点击的确认」，不做形变：

| 元素 | 静止 | 悬停 |
| :-- | :-- | :-- |
| 服务行 | 无底色 + 0.5pt 行分隔 | 整行底色 `separator.opacity(0.06)`（亮）/ `0.12`（暗），圆角 8；无阴影、无位移 |
| 分类卡 | 描边 `separator 0.35` / 阴影 `r6 y2 0.04` | 不响应——它只承载分组，不承担点击 |
| 列表行 | 无底色 | 底色 `separator.opacity(0.06)`（亮）/ `0.12`（暗） |
| 工具栏按钮 | 无底色 | 系统按钮态（交给 SwiftUI，不自绘） |
| 服务行 tooltip | 无 | 指针停留后由系统气泡显示「离线可用 · 断网也能打开」；这是能力标签离开行内之后的落点（见 3.1） |

**不做**：行放大、位移、`scaleEffect`。文字在非整数倍缩放下会发虚，且与 iOS 的「轻点即开」语义不一致。

2. **指针精度与点击目标**。所有可点击行与按钮的命中区域 ≥ 28×28（macOS HIG 下限）。服务行高 44、列表行通常 ≥ 44，均满足；行内的告警胶囊与图钉不承担点击，保持不可交互。

3. **右键菜单**。首页服务行沿用现有 6 项（在浏览器打开 / 复制地址 / 检测 / 置顶 / 隐藏 / 服务设置）。补充两处：

- 通知行：右键菜单补「标为已读」「删除」「在该应用中打开」——这是 `.swipeActions` 在无触控板场景下的等价入口；
- 服务行：菜单顶部分隔出「打开原生页 / 打开网页版」，直接对应 `IntegrationRouter` 的两条去向；再上一行放只读的能力说明（「离线可用 · Service Worker 缓存」），承接从行内撤下的标签。

4. **拖拽**。服务行支持拖出 URL（`NSItemProvider`），可拖到浏览器或 Finder。属于增强项，不进入第一版设计范围。

5. **触控板**。横扫前进后退已具备；双指轻点等价右键，无需额外设计。通知的 `.swipeActions` 在触控板上可横向轻扫，但轨迹短、易误触，因此右键菜单与行内按钮是主入口，横扫是补充。

6. **滚动**。保持系统惯性滚动与边缘回弹，不接管 `NSEvent`。

**沿用 / 映射 / 禁改**：沿用 `.contextMenu` 的菜单项文案与图标；不新增手势识别器；不改行高与 Glyph 尺寸。

**后续代码阶段项**：`.onHover` 状态与行底色联动；通知行右键菜单；服务行拖拽（可选）。

### 3.4 菜单栏与命令组

**现状**：无 `.commands`、无 `Settings` scene、无 Dock 菜单（`ZhongmiaoApp.swift` 全 46 行、`AppDelegateMac.swift` 全 32 行）。

**设计要点**：菜单栏是 macOS 的「全局入口」，必须把 App 已有的动作映射进去，但不新增业务能力。

| 菜单 | 命令项 | 映射到现有动作 | 备注 |
| :-- | :-- | :-- | :-- |
| 众妙 | 关于众妙 | 标准 | 系统提供 |
| | 设置… | 打开设置窗口（`Settings` 场景，系统自动挂项） | `⌘,` |
| | 隐藏众妙 / 隐藏其他 / 全部显示 | 标准 | 系统提供 |
| | 退出众妙 | 标准 | `⌘Q` |
| 文件 | 新建窗口 | 新 `WindowGroup` 实例 | `⌘N`；受 3.6 约束 |
| | 关闭窗口 | 标准 | `⌘W` |
| | 同步全部 | `model.syncNow(reason:)` | `⌘R` |
| 编辑 | 撤销 / 重做 / 剪切 / 拷贝 / 粘贴 / 全选 | 标准 responder chain | 输入框内生效 |
| | 查找 | `.searchable` 聚焦 | `⌘F` |
| 视图 | 应用 / 通知 / 设置… | 前两项切页，设置打开独立窗口 | `⌘1` / `⌘2` / `⌘3` |
| | 刷新当前页 | 网页 `reload()`、原生页 refresh | `⌘R` 在服务页内优先 |
| | 显示已隐藏的服务 | 首页过滤开关 | 与 `AppSettings` 的隐藏标记联动 |
| | 显示服务能力标签 | 勾选项，绑定 `AppSettings.showServiceCapabilityTags` | 与设置页同一个开关；macOS 上初值为关（见 3.1），从菜单开启比进设置快 |
| | 进入全屏幕 | 标准 | `⌃⌘F` |
| 窗口 | 最小化 / 缩放 / 前置全部 | 标准 | 系统提供 |
| 帮助 | 诊断与日志 | `DiagnosticsView` | 无快捷键 |

> 上表有两处在实施时被调整（详见 7.4）：菜单项插进系统自带的「显示」菜单而不是新建同名的「视图」菜单；`⌘R` 只挂给「刷新当前页」并按当前页分派，「同步全部」不占快捷键。

**能力边界**：菜单里**不设**「开机自启」「后台常驻」「常驻状态栏」这类命令。`SMAppService` 需要 Developer ID 与公证，当前账号不具备（见 7.2）。

**沿用 / 映射 / 禁改**：命令文案与 App 内按钮文案保持一致（如「同步全部」不写成「全部同步」）；不新增菜单专属的业务逻辑。

**后续代码阶段项**：`.commands { CommandGroup / CommandMenu }`（已做）。`Settings` scene 也已落地——设置拆成独立窗口，App 菜单里的「设置…（⌘,）」由系统提供，不再手挂同义项。

### 3.5 键盘快捷键

**现状**：全仓 0 处 `.keyboardShortcut`。

**设计要点**：只给「高频且无歧义」的动作配快捷键，避免与系统保留键冲突。

| 快捷键 | 动作 | 作用域 | 与现有实现的关系 |
| :-- | :-- | :-- | :-- |
| `⌘1` | 切到「应用」 | 全局 | 对应 `tab = .catalog` |
| `⌘2` | 切到「通知」 | 全局 | 对应 `tab = .inbox` |
| `⌘3` | 打开「设置」窗口 | 全局 | 设置不再是主窗口的标签，见 3.7.1 |
| `⌘,` | 设置 | 全局 | `Settings` 场景由系统自动挂到 App 菜单 |
| `⌘N` | 新建窗口 | 全局 | 新 `WindowGroup` |
| `⌘R` | 刷新 | 当前页 | 网页 → `reload()`；列表 → `refreshable` 的同一入口 |
| `⇧⌘R` | 强制刷新（绕过缓存） | 网页页 | 对应菜单里的「强制刷新（绕过缓存）」 |
| `⌘F` | 聚焦搜索 | 首页 / 原生页 / 通知 | `@FocusState` 已有，接 `.focused($searchFocused)` |
| `⌘[` / `⌘]` | 后退 / 前进 | 网页页 | 与 `canGoBack` / `canGoForward` 联动 |
| `⌘L` | 复制当前地址 | 网页页 | 对应「复制地址」 |
| `⌘⇧O` | 在浏览器打开 | 网页页 | 对应 `openCurrentInBrowser()` |
| `Delete` | 删除选中通知 | 通知页 | `.swipeActions` 的删除等价 |
| `⇧⌘A` | 全部标为已读 | 通知页 | 对应通知工具栏菜单 |
| `⌘E` | 导出 / 分享当前页 | 网页页 | 替代 iOS 的 `ShareLink` |
| `⌘0` | 实际大小（缩放回 100%） | 网页页 | 后续增强，需网页缩放控制 |

**冲突处理**：`⌘R` 在「设置 / 通知」页为刷新数据，在「网页页」为重新加载，两者不共存，按当前页类型分派。

**沿用 / 映射 / 禁改**：不占用 `⌘Tab`、`⌘Space`、`⌘H`、`⌘M`、`⌘Q` 等系统保留键；不新增「一键同步单个服务」这类易冲突的组合。

**后续代码阶段项**：`.keyboardShortcut` 挂在对应 Button 或菜单命令上；`⌘F` 与 `@FocusState` 绑定。

### 3.6 多窗口、Dock 与状态栏

**现状**：唯一 `WindowGroup` 无 id、无 `openWindow`；`NSApp.setActivationPolicy(.regular)` 表明是有 Dock 图标的常规 App（`AppDelegateMac.swift:8`）；工程未配 `NSSupportsAutomaticTermination`，关窗后进程仍在。

**设计要点**：

1. **多窗口**。`WindowGroup` 天然支持 `⌘N` 多开，每个窗口持独立的 `NavigationPath` 与 `tab` 选中。深链（`zhongmiao://`）在**最前面的窗口**消费：`consumePendingRoute()` 已有「强制回首页」的语义，多窗口下需限定到 key window，避免所有窗口一起跳。
2. **Dock 菜单**。在 Dock 图标右键提供「新建窗口」「最近打开的服务（最多 5 个）」「诊断」。最近服务取 `ServiceCatalog` 与本地访问记录，不新增持久化结构。
3. **状态栏常驻**。`MenuBarExtra` 作为候选形态列出，但不作为设计承诺：它要「开机就在状态栏」，需要登录项；`SMAppService` 在免费账号下不可用（详见 7.2）。可实现的子集是「App 已启动时在状态栏显示入口，退出即消失」，价值有限，因此不进入第一版范围。
4. **关窗行为**。保持「关窗不退出」——通知轮询与 ntfy 订阅依赖进程存活（`docs/推送方案.md:109`）。若后续要加「关窗即退出」，必须同时提供「退出后不再收通知」的明确提示，不能静默改变语义。
5. **窗口恢复**。记录上次窗口尺寸与位置；「应用 / 通知」的选中项在会话内保留，跨启动回到「应用」；设置窗口按系统偏好设置窗口的习惯不参与恢复。

**沿用 / 映射 / 禁改**：不改 `scenePhase` 的回调语义；`persistOnBackground()` 在 macOS 的触发时机（失焦 vs 隐藏）需在代码阶段单独核对，设计上不假设它等同于 iOS 的后台。

**后续代码阶段项**：`WindowGroup(id:)` + `openWindow`；Dock 菜单（`applicationDockMenu`）；窗口尺寸持久化。

---

### 3.7 设置独立窗口与界面缩放

#### 3.7.1 设置拆成独立窗口

**理由**：macOS 的偏好设置从来是独立窗口（系统设置、Safari、Xcode 都如此）；主窗口顶部已被 `TabView` 的标签占着，设置再当第三页既挤又不像 macOS；`⌘,` 又是「设置」的固定约定。

**实现**：`Settings { SettingsView() }` 场景，窗口标题为 `"众妙"设置`、内容 820×720；`RootView` 的主窗口只剩「应用 / 通知」两页。入口三处对齐同一个目的地——App 菜单「设置…（`⌘,`）」（系统为 `Settings` 场景自动挂项，不再手写 `CommandGroup(replacing: .appSettings)`）、主窗口工具栏的齿轮、`视图` 菜单的 `⌘3`。二级页仍是 sheet + 右上「完成」。

**系统托管的部分**：`Settings` 窗口不进窗口列表、不参与状态恢复；关掉它不影响进程（通知轮询与 ntfy 订阅照常）。

#### 3.7.2 界面缩放（4K 屏）

**问题**：4K 显示器按原生分辨率用时，13pt 正文与 28pt 图标偏小；而 macOS 只有整屏缩放，App 内部没有「放大界面」的标准手段。

**为什么不用动态字体**：实测（Xcode 27.1 / macOS 27）`Text("中文示例 Abc").font(.body)` 与再追加 `.dynamicTypeSize(.accessibility3)` 的 `fittingSize` 都是 **79×16**，逐像素一致——SwiftUI 在 macOS 上不响应 Dynamic Type；系统「按 App 调字号」的能力也不在 App 控制范围内。系统控件的 `controlSize` 只放大控件本身（开关 24→36）而不改字号。倍数只能自己算。

**实现**（`Sources/Shared/App/InterfaceScale.swift`）：

| 层次 | 做法 |
| :-- | :-- |
| 设置项 | `AppSettings.interfaceScale`：100 / 115 / 130 / 145%，默认 100%，`decodeIfPresent` 兜底，旧存档不受影响 |
| 字号 | `View.zmFont(...)`：语义字号取 `NSFont.preferredFont(forTextStyle:)` 的基线乘倍数，再用 `Font.system(size:weight:)` 还原；309 处 `.font(...)` 全量换成 `.zmFont(...)`，1 倍时与原来逐像素一致（`fittingSize` 对照：caption2 83/83、headline 108/108、subheadline 90/90） |
| 度量 | `CGFloat.zmScaled(_:)` 取整，避免 50.6 这类半像素让 0.5pt 描边发虚：栏宽下限 300、行高 44、设置行高 32、行内留白 12/14 |
| 系统控件 | `ControlSize.zm(_:)`：≥112% 用 `.large`、≥135% 用 `.extraLarge`（开关、分段控件、步进器、按钮） |
| 断点 | 栏数判定用 `940 / 620 × 倍数`，放大后自然退到更少的栏，不硬塞 |

**范围与边界**：只放大原生壳层。窗口边框、标签栏、工具栏由系统绘制，字号固定（观感与浏览器缩放一致：chrome 不动、内容变大）；网页内容不跟随——各服务有自己的响应式排版，整页缩放会变成横向滚动，而 SwiftUI 的 `WebPage`（iOS 26 / macOS 26 接口）没有暴露 pageZoom。

**iOS 不参与**：iOS 有系统级动态字体，`zmFont` 在 iOS 走透传（`Font.system(style)`），像素与改造前一致。

**入口**：设置窗口「外观」分组里的「界面缩放」四档分段控件，改完三个窗口（主窗口、设置、诊断）立即重算。

---

## 第 4 章　视觉一致性约束

> 这是界面参考稿的硬输入。参考稿里任何一处与本章不符，即判定视觉走样。

### 4.1 原样沿用（禁改）

| 类别 | 具体项 |
| :-- | :-- |
| 颜色 | 14 组服务 tint 十六进制（`ServiceCatalog.swift` 为唯一来源）；强调色亮 `rgb(60,71,96)` / 暗 `rgb(205,212,226)`；启动背景双变体 |
| 形状 | 主卡圆角 16 `.continuous`（macOS 落在分类卡上）；指标卡 12；搜索框 9；Glyph `size*0.28` |
| 分类卡 | `padding 12`、圆角 16、阴影 `r6 y2 0.04`（暗色 0）、描边 `separator 0.35 / 0.5pt`；macOS 上承载一个分类区段，而非单个服务 |
| 服务行 | 高 44（大字号 56）、Glyph 28、名称列最小 72（摘要起点对齐）、行分隔 0.5pt `separator 0.35`、悬停底 `separator 0.06`（暗 `0.12`）、圆角 8 |
| 图标 | `ServiceGlyph` 的 `0.95→0.72` 渐变、`.topLeading→.bottomTrailing`、白色符号 `size*0.44`、`weight .medium`；首页行条目取 size 28 |
| 标签 | `CapsuleTag` 的字号 `.caption2`、内距 h6/v2、底色 `tint.opacity(0.16)`；「离线可用」用 `arrow.down.to.line` + 绿，「未配置」用 `exclamationmark` + 橙。macOS 首页行内只出现橙色一档（真告警），绿色能力标签改由 tooltip 承载 |
| 字体 | 全语义字号，不引入自定义字体、不引入固定 pt 字号（6 处固定字号例外见 1.1） |
| 无障碍 | Dynamic Type 的分列降级、VoiceOver 标签、减弱动态效果 |
| 文案 | 「离线可用」而非「离线」；「需要联网」而非「离线」的反义简写（`ServiceDefinition.swift:22-28` 有明确理由） |

### 4.2 平台化映射（已实现，EF）

| 语义 | iOS | macOS |
| :-- | :-- | :-- |
| 分组底 | `.systemGroupedBackground`（242） | 亮 `.underPageBackgroundColor`（246）/ 暗 `.windowBackgroundColor`（30） |
| 卡片底 | `.secondarySystemGroupedBackground`（255） | 亮 `.controlBackgroundColor`（255）/ 暗 `.underPageBackgroundColor`（40） |

**这两行在实施时被修正过，原因值得记下来**：macOS 的 `windowBackgroundColor` 与 `controlBackgroundColor`
亮态同为 255、暗态同为 30（用 `performAsCurrentDrawingAppearance` 实测），照直映射会让卡片与页面完全同色——
亮态白卡片落在白背景上、暗态 30 落在 30 上，只剩 0.5pt 描边可辨，「卡片」这一层视觉语言等于消失。
iOS 上一对是 242 / 255，卡片才立得起来。

修法不新造颜色，只在 AppKit 已有的中性阶里挑「页面偏暗一档、卡片偏亮一档」：亮 246 / 255，暗 30 / 40，
关系与 iOS 的 grouped / card 一致。实现见 `DesignSystem.swift` 的 `macGrouped` / `macCard` 两个动态色。

**设置页的容器另外处理（`Form` 在 macOS 上不可用）**：`Form` 在 macOS 的初值样式是 `ColumnsFormStyle`——
标签一列、控件一列，`Section` 只是几行灰字，没有分组卡片，整页看起来像没加载样式表的网页。换成
`.formStyle(.grouped)` 后卡片由系统绘制，但实测这层背景暗色下与页面只差 7 阶（页面 30 / 卡片 37）、
亮色下卡片反而比页面更深（238 / 246），分组立不起来；同时 `NavigationLink` 在 `Form` 里会被拆成
「标签 + 值」的两列，既没有箭头也点不动。因此 macOS 设置页改用 `MacSettingsPage` + `MacSettingsGroup`
自绘（`Sources/macOS/MacSettingsCards.swift`）：页面与卡片取 4.2 那一对动态色，行高 32、左右留白 14、
行间 0.5pt 分隔线，跳转行自带箭头与悬停反馈。二级页（服务与接入 / ntfy 主题 / 诊断）走 `sheet` + 右下「完成」，
`push` 只在 sheet 内部发生（列表 → 单服务页，靠系统返回箭头）；「完成」挂在 `NavigationStack` 上而不是目的地，
否则 push 一层就把它带走，用户得先退才能关 sheet。
iOS 侧仍是 `Form` + `Section`，两端共用同一份字段与文案。

**同一套卡片覆盖全部设置类页面**：服务与接入（分类卡片 + 服务行）、单服务配置（9 组）、ntfy 主题、诊断
四页在 macOS 上都改用 `MacSettingsPage` / `MacSettingsGroup` / `MacSettingsRow`。诊断原来用的是 `List`——
macOS 上 `List` 铺满整窗、行直接贴边，和设置页的卡片是两种语言，核对时能一眼看出不一致。

**操作按钮不用系统 `.bordered`**：macOS 26 的 `.bordered` / `.borderedProminent` 是液态玻璃，叠在深色卡片上
只剩一层几乎透明的底——实测「立即同步」「开启通知」看起来就是一行彩色文字，也就是反馈里的「按钮都是扁的」。
`ZMPushButtonStyle` 改自绘：`Color.primary.opacity(0.08)` 底 + 0.5pt `.separator` 描边，悬停 0.13、按下 0.20，
破坏性动作用红字，禁用时整体 0.45。按钮行（`MacSettingsButtonRow`）、密钥字段（`SecretField`）、
单服务页的维护按钮共用它；行本身（跳转行、服务行）仍是 `.plain` + 悬停，不套这层底色。

**自绘行的无障碍成本**：`.labelsHidden()` 在 macOS 上会把控件的 AX 名称一并去掉（实测 `AXCheckBox`
的 title/description 全空），`Button` 的 label 是自绘视图树时同样拿不到名称。因此每个行内控件都要显式补
`.accessibilityLabel`，跳转行的 label 拼上右侧摘要（读作「服务与接入，14/14 可访问」）。
校验手段：`AXUIElementCopyAttributeValue` 读 `AXDescription`，不要用 AppleScript 的 `description`
（那是 `AXRoleDescription`，恒为「按钮」）。

| 语义 | iOS | macOS |
| :-- | :-- | :-- |
| 触觉 | `UINotificationFeedbackGenerator` / `UIImpactFeedbackGenerator` | `NSHapticFeedbackManager.defaultPerformer(.generic)` |
| 外链 | `UIApplication.shared.open` | `NSWorkspace.shared.open` |
| 剪贴板 | `UIPasteboard.general.string` | `NSPasteboard.general` |
| 下载目录 | `Documents/下载` | `~/Downloads/众妙` |
| 设备名 | `UIDevice.current.name` | `Host.current().localizedName` |
| 跳系统设置 | `UIApplication.openSettingsURLString` | `x-apple.systempreferences:…notifications` |
| 输入修饰 | 关自动大写 + 关自动纠错 | 仅关自动纠错（`zmPlainTextInput`） |

### 4.3 绝对不许改

1. 视觉语言本身——不得为 macOS 引入新的色彩体系、圆角阶梯、字体或图标风格。
2. `ServiceCatalog.swift` 作为配色唯一来源的地位——不得在 macOS 侧硬编码另一份 tint。
3. 组件语义——`ServiceGlyph` 的「色块 + 白色符号」形态、`CapsuleTag` 的胶囊形态、`EmptyStateView` / `LoadFailureView` 的信息层级。**收窄使用面不等于删组件**：`CapsuleTag` 在 macOS 上仍承担告警、通知行与 12 个原生页的状态标注，形态、构造与配色逻辑不得改动。
4. 无障碍支持——不得因平台差异砍掉 VoiceOver 标签或 Dynamic Type 降级。
5. 下层共享视图的对外接口——macOS 壳只能包在外层，不能要求 `CatalogView` / `NotificationsView` / 12 个原生页改签名。

### 4.4 违反判定

出现以下任一情况即判为视觉走样：

- 分类卡圆角不是 16，或描边不是 0.5pt / `separator 0.35`；
- 内容宽 ≥ 940 时仍按单列纵向堆叠分类，或入口行高超过 56（退回 iOS 的 132pt 卡片）；
- 图标底色不是 tint 渐变（改成纯色、或换一套渐变方向）；
- 出现 iOS 与 macOS 两套不同的服务色；
- 为了「更像 mac」把分类卡换成系统 `List` 分组样式（视觉语言被替换）；
- 参考稿里出现 emoji 代替 SF Symbol。

---

## 第 5 章　导航骨架：选定路线 A

> **结论：保留 `TabView` 三页骨架（路线 A）**，macOS 侧只加外壳。5.2–5.4 保留两条路线的并列论证过程与对照表，作为决策记录；未选中的路线 B 不再进入后续实施范围。

### 5.1 共同前提

- 现状是 `RootView` 的 `TabView` 三页 + 每页 `NavigationStack`，全文件无 `#if`（`RootView.swift:16-42`），两个平台共同编译。
- 深链靠 `consumePendingRoute()` 消费 `AppModel.pendingRoute`，并强制 `tab = .catalog`（`RootView.swift:56-61`）。
- 路由分派在 `destination(for:)` 里，经 `IntegrationRouter.resolve` 决定原生页还是网页页（`RootView.swift:64-86`）。
- 12 个原生页、`CatalogView`、`NotificationsView`、`SettingsView` 均为下层共享视图，接口稳定。

### 5.2 路线 A：保留 TabView 三页骨架（选定）

**结构**：主窗口保留「应用 / 通知」两页切换，每页一个 `NavigationStack`；设置已拆为独立窗口（3.7.1）。macOS 上 `TabView` 渲染为窗口顶部的标签切换，没有底部栏；通知页的角标保留。

**改造方式**：`RootView` 内加 `#if os(macOS)` 分支，只在 macOS 侧补窗口修饰（尺寸、工具栏）、`tab` 的键盘切换与样式微调；iOS 路径不动。

**受影响文件**：`RootView.swift`（加分支）、`Sources/macOS/` 新增菜单与命令文件。`CatalogView` / `NotificationsView` / `SettingsView` / 12 个原生页全部不动。

**视觉一致性**：与 iOS 同一套视觉骨架，切页后的内容区与 iPhone 上逐像素同源。

### 5.3 路线 B：改为 NavigationSplitView 侧边栏（未选中，已搁置）

**结构**：左侧 `Sidebar` 常驻，一级为「应用 / 通知 / 设置」三个分区，二级在「应用」下展开 6 个服务分类；右侧 `detail` 区展示列表或详情。

**改造方式**：`Sources/macOS/` 新增 `MacRootView`，用 `NavigationSplitView` 承载；`tab` 状态映射为侧栏选中项；深链同时更新侧栏选中与 `detail` 的 `NavigationPath`。

**受影响文件**：`Sources/macOS/` 新增壳与菜单文件、`RootView.swift` 在 macOS 分支改为调用 `MacRootView`（或由 `ZhongmiaoApp` 按平台选择根视图）、少量状态桥接代码。`CatalogView` / `NotificationsView` / `SettingsView` / 12 个原生页仍不动接口，但导航语义从「页内 push」变为「detail 内 push」。

**视觉一致性**：侧栏是一个新视觉元素，需要定义选中态（`accentColor` 底 + 白字，或 `separator` 底 + 主色字）、分组标题样式、折叠箭头。这些仍取用同一套 token，但会新增 2–3 个未在 iOS 出现的局部样式。

### 5.4 并列对比

| 维度 | 路线 A：保留 TabView 三页（选定） | 路线 B：NavigationSplitView 侧边栏（搁置） |
| :-- | :-- | :-- |
| 结构 | 顶部标签切三页，每页 `NavigationStack`；内容区单列 | 左侧栏常驻（三入口 + 6 分类），右侧 detail |
| 屏幕横向占用 | 内容区占满窗口宽（内容 1132 → 3 栏，栏宽 364） | 侧栏占 226pt，detail 内容 922 → 按 3.1 判定降为 2 栏（栏宽 451）；横向并列度少一档，但摘要不再被截断 |
| 屏幕纵向占用 | 标签栏占约 36pt | 无标签栏，纵向多出约 36pt |
| 信息层级 | 三层：标签 → 列表 → 详情 | 三层：侧栏分区 → 侧栏条目 → 详情 |
| 鼠标操作成本 | 切页需点顶部标签，跨页对比要来回切 | 侧栏常驻，分类与入口一屏可见，切换为一次点击 |
| 键盘操作成本 | `⌘1/2/3` 语义直观，方向键在列表内导航 | `⌘1/2/3` 需映射到侧栏选中；方向键先在侧栏内移动，再进入 detail |
| 改造代价 · 文件面 | `RootView` 加分支 + 新增菜单文件（约 2 处） | 新增 `MacRootView` + 菜单文件 + 状态桥接（约 3–4 处） |
| 改造代价 · 深链 | `consumePendingRoute()` 不动 | 需同时更新侧栏选中与 detail path，逻辑更绕 |
| 改造代价 · 状态 | `tab` 状态直接复用 | `tab` 需映射为 sidebar selection，可能出现双源 |
| 视觉一致性冲击 | 无（同一骨架） | 中：需新增侧栏选中态、分组标题、折叠态 3 个局部样式 |
| 对下层共享视图侵入度 | 零（只加壳） | 低：接口不动，但导航容器语义改变 |
| 多窗口适配 | 每个窗口各自 `tab`，天然独立 | 每个窗口各自 sidebar 选中，天然独立 |
| 与 `docs/ARCHITECTURE.md:174` 的关系 | 文档描述了路线 B 的方向；路线 A 属于文档未提及的另一条 | 文档描述的方向与本路线一致（该表述仅说明文档现状，不构成选型结论） |

### 5.5 选定结果与回填

选定路线 A 后，按下列清单回填，全部已完成：

| 项 | 位置 | 回填结果 |
| :-- | :-- | :-- |
| 根骨架 | 2.2 | 保留同一份 `TabView`，macOS 渲染为窗口内顶部标签 |
| 侧边栏 | 2.2 | 评估过 `NavigationSplitView`，已搁置（理由见 5.4） |
| 多窗口 | 2.2 | 每个窗口各自持有 `tab`，互不影响 |
| `⌘1/2/3` 映射 | 3.4 | 切页（`tab = .catalog / .notifications / .settings`），不涉及侧栏选中 |
| `TabView` 行 | 第 6 章 | 窗口内顶部标签切换 |
| `NavigationStack` 行 | 第 6 章 | 不变，仍在每页内 push |
| 参考稿 01 | 参考稿 | 内容区占位改为「标签栏 + 3 栏」的框架示意，窗口比例对齐 1180×760 |
| 参考稿序列 | 参考稿 | 主序列重排为 01–05；路线 B 整屏收进页末折叠区，编号标「附表」 |

**路线 A 的落地要点**：

- `RootView` 内加 `#if os(macOS)` 分支，只补窗口修饰（容器尺寸交给 3.2、工具栏、toast 间距回落 24）与标签样式；iOS 路径逐行不动；
- `tab` 状态、`consumePendingRoute()`、`destination(for:)` 三处逻辑原样复用，深链不需要改；
- 附表中路线 B 的侧栏选中态、分组标题、折叠态三个局部样式**不再定义**，第 4 章无需为它们预留接口。

---

## 第 6 章　组件映射表（iOS → macOS）

| iOS 实现 | 出处 | macOS 呈现 | 分类 | 后续代码阶段 |
| :-- | :-- | :-- | :-- | :-- |
| `TabView(selection:)` + `.tabItem` | `RootView.swift:17-42` | 窗口内顶部标签切换（路线 A，已选定） | EF+DD | 是 |
| `NavigationStack(path:)` | `RootView.swift:18-32` | 不变，仍在每页内 push | EF | 否 |
| `NavigationLink(value:)` + `navigationDestination` | `RootView.swift:20-22` | 点击进详情；右键「在新窗口打开」为增强 | EF+DD | 可选 |
| `.badge(unreadCount)` | `RootView.swift:34` | 标签角标（路线 A 下不再有侧栏条目角标） | EF+DD | 是 |
| `.searchable` | `CatalogView.swift` | 顶部搜索框，`⌘F` 聚焦 | EF+DD | 是 |
| `LazyVGrid(.adaptive 158–260)` | `CatalogView.swift:20-30` | macOS 改为分类分栏：外层 `HStack` + 每栏 `VStack`，按 3.1 表切分，1–3 栏；iOS 侧不动 | EF+DD | 是 |
| `ServiceCard`（132pt 竖向卡片） | `CatalogView.swift:267-362` | macOS 改为服务行（44pt 横向：Glyph 28 + 名称/摘要 + 状态），卡片语言上移到分类块 | EF+DD | 是 |
| `CapsuleTag("离线可用")` | `CatalogView.swift:320-326` | 不进服务行：改 `.help()` tooltip + 右键菜单信息项，开关初值为关。告警类（「未配置」「已隐藏」）仍在行内右对齐 | EF+DD | 是 |
| `.onHover` | 全仓 0 处 | 服务行悬停底色 `separator 0.06` / 圆角 8 | DD | 是 |
| `.contextMenu` | `CatalogView.swift:199-250` | macOS 右键菜单，菜单项不变 | EF | 否 |
| `.swipeActions` | `NotificationsView.swift:232` | 右键菜单 + 行内按钮；触控板横扫保留 | EF+DD | 是 |
| `.refreshable` | 列表类多处；网页仅 iOS | 列表类不变；网页页改为工具栏刷新 + `⌘R` | EF | 是（网页） |
| `.sheet` | 多处 | macOS 呈现为 sheet / 独立窗口，尺寸需约束 | EF+DD | 是 |
| `ToolbarItemGroup(.bottomBar)` 浏览器工具条 | `ServiceScreen.swift:119-155` | macOS 无底部栏 → 移到窗口工具栏或右键菜单 | EF+DD | 是 |
| `.toolbar(.hidden, for: .tabBar)` | `ServiceScreen.swift:63-69` | 不适用，跳过 | EF | 否 |
| `.navigationBarTitleDisplayMode(.inline)` | 多处 `#if os(iOS)` | 不适用；macOS 用窗口标题/工具栏标题 | EF | 否 |
| `.keyboardType` / `.textInputAutocapitalization` | 多处 `#if os(iOS)` | 不适用；`.zmPlainTextInput()` 兜底 | EF | 否 |
| `ShareLink` | `ServiceScreen.swift:150-153` | `⌘E` 导出 / 右键「在浏览器打开」 | EF+DD | 是 |
| toast `.overlay(.bottom)` + `padding 76` | `RootView.swift:89-101` | 同一胶囊，底部间距回落 24 | EF+DD | 是 |
| `OfflineBanner` + `.safeAreaInset` | `DesignSystem.swift:105-129` | 不变；安全区改用窗口边距 | EF | 可选 |
| `ProgressView(.linear)` 2pt 进度条 | `ServiceScreen.swift` | 不变，置于工具栏下方 | EF | 否 |
| SwiftUI `WebView(WebPage)` | `WebViewHost.swift:11-20` | 同一套 API；`data-zhongmiao-container` 改平台值 | EF+DD | 是 |
| `Pasteboard` | `CatalogView.swift:364-373` | 已映射 `NSPasteboard` | EF | 否 |
| `Platform.haptic` | `Platform.swift:22-39` | 已映射 `NSHapticFeedbackManager` | EF | 否 |
| 跳系统设置 | `NotificationsView.swift:156-166` | 已映射 `x-apple.systempreferences:` | EF | 否 |
| `.confirmationDialog` | 多处 | macOS 呈现为 sheet 式确认，文案不变 | EF | 否 |
| `ContentUnavailableView` | `RootView.swift:80-84` | 不变 | EF | 否 |
| 灵动岛 / 锁屏卡片 | `Sources/Widget` | 不适用 | EF | 否 |
| 开演闹钟 Section | `Sources/iOS/ShowAlarmSection.swift` | 不适用 | EF | 否 |

---

## 第 7 章　落地边界与后续实施提示

### 7.1 后续代码阶段清单（只列，不在本阶段实施）

| 优先级 | 项 | 涉及位置 |
| :-- | :-- | :-- |
| P0 | 窗口尺寸与缩放：初始 1180×760、最小 720×480、内容最大宽 1180 | `ZhongmiaoApp.swift:17`、`RootView` 内容层 |
| P0 | 首页分类分栏 + 服务行（macOS 分支） | 新增 `Sources/macOS/CatalogBoard.swift`；`CatalogView` 仅加平台分支 |
| P0 | 能力标签退出行条目：macOS 初值为关 + `.help()` tooltip + 右键信息项 | `AppSettings.swift:173`（平台初值）、服务行视图 |
| P0 | 骨架外壳：路线 A（`RootView` 内加 macOS 分支） | `RootView.swift:16-42` |
| P0 | 菜单栏命令组 + `Settings` scene 评估 | `ZhongmiaoApp.swift`、新增 `MacCommands.swift` |
| P1 | 键盘快捷键 | 各 Button / 菜单命令 |
| P1 | 服务行悬停底色与点击目标 | 服务行视图、列表行 |
| P1 | macOS 浏览器导航工具条 | `ServiceScreen.swift:119-155` |
| P1 | `data-zhongmiao-container` 改平台值 | `WebViewFactory.swift:224` |
| P2 | 通知页右键菜单（标已读 / 删除） | `NotificationsView.swift:232` 邻域 |
| P2 | toast 底部间距平台化（76 → 24） | `RootView.swift:101` |
| P2 | Dock 菜单、窗口尺寸持久化 | `AppDelegateMac.swift` |
| P3 | 卡片拖出 URL | `ServiceCard` |
| P3 | 状态栏常驻（受 7.2 限制，暂不纳入） | — |

### 7.2 能力边界（免费个人账号）

| 能力 | 状态 | 依据 |
| :-- | :-- | :-- |
| App Sandbox / Hardened Runtime | 系统支持，但当前未启用（无 entitlements） | `project.yml:29-163` 无 `entitlements:` 键；`docs/ARCHITECTURE.md:176-177` |
| 网络客户端权限 | 分发前需补 `com.apple.security.network.client` | `docs/ARCHITECTURE.md:176` |
| APNs | 需付费账号；免费档只能用本地通知与轮询 | `README.md:142` |
| 登录项 / 开机自启 | `SMAppService` 需 Developer ID + 公证，不可用 | 免费账号限制 |
| 灵动岛 / 实时活动 | iOS 专属 | `Sources/Widget`、`project.yml:101-124` |
| 开演闹钟（AlarmKit） | iOS 26+ 专属，macOS SDK 无此框架 | `Sources/iOS/ShowAlarmSection.swift` |
| 后台刷新（BGTask） | iOS 专属；macOS 靠进程存活 | `project.yml:89-90`、`Info-iOS.plist` |
| 日历 / 提醒事项写入（EventKit） | iOS 专属 | `project.yml:77-80` |
| 钥匙串 | macOS 可能降级到传统钥匙串 | `README.md:145` |

### 7.3 文档与代码不一致备查

写实现或评审时以代码为准，不要照抄文档：

| 文档说法 | 实际情况 |
| :-- | :-- |
| `docs/ARCHITECTURE.md:169`：`WebViewHost` 是 `UIViewRepresentable` / `NSViewRepresentable` 两套壳 | `WebViewHost` 用的是共享的 SwiftUI `WebView(model.page)`；Representable 双壳在 `InAppBrowserSheet.swift:71-157` |
| `docs/ARCHITECTURE.md:171`：`WKUIDelegate` 用 `UIAlertController` / `NSAlert` + `NSOpenPanel` 处理 JS 弹窗与文件上传 | 代码中没有设置 `uiDelegate`，全仓 0 处 `WKUIDelegate` |
| `docs/ARCHITECTURE.md:174`：后续只需新增 `NavigationSplitView` 外壳 | 该段是文档记述的方向；第 5 章曾并列两条路线，**已选定路线 A（保留 `TabView`）**，与这段描述的实施方向不同 |
| `WebViewFactory.layoutScript` 注入容器标记 | 写死为 `ios`（`WebViewFactory.swift:224`），macOS 同样注入该值 |

### 7.4 实施记录（2026-11-16）

本轮已把 P0 / P1 与部分 P2 落到代码，落点如下：

| 项 | 落点 | 实测 |
| :-- | :-- | :-- |
| 窗口尺寸与缩放 | `ZhongmiaoApp.swift`（`defaultSize` / `windowResizability`）、`RootView` 的 `frame(minWidth:minHeight:)` | 开窗 1180×760；用 AX 把窗口压到 400×300 时宽度被夹在 720 |
| 首页分栏 + 行条目 | `Sources/macOS/CatalogBoard.swift`（含顺序装箱、44pt 行、悬停、tooltip、右键菜单） | 内容 1132 → 3 栏（338/338/294），672 → 2 栏，560 → 1 栏，摘要不截断 |
| 能力标签平台初值 | `AppSettings.defaultShowsCapabilityTags` | 解码与 `init()` 共用同一常量，判定逻辑未动 |
| 骨架 A | `RootView` 共用同一份 `TabView`，仅补平台修饰 | `⌘1/2/3` 实测切到 众妙 / 通知 / 设置 |
| 菜单命令 | `Sources/macOS/MacCommands.swift` | 菜单栏为 众妙 / 文件 / 编辑 / 显示 / 窗口 / 帮助 |
| 诊断独立窗口 | `Window("诊断与日志", id:)` | 点「帮助 → 诊断与日志」实测多出第二个窗口 |
| macOS 浏览器工具条 | `ServiceScreen` 的 `.navigation` + `.primaryAction` | 后退/前进/重载/复制地址/浏览器/分享 |
| 容器标记 | `WebViewFactory.containerName`（`ios` / `macos`） | 页面 `data-zhongmiao-container` 不再写死 |
| 卡片底 / 分组底修正 | `DesignSystem.swift` 的 `macGrouped` / `macCard` | 见 4.2；亮暗两态渲染均能分辨卡片 |

**与设计稿的偏差（均有意为之）**：

| 设计稿写的 | 实际做法 | 原因 |
| :-- | :-- | :-- |
| 新建「视图」菜单 | 菜单项插进系统自带的「显示」菜单 | 避免两个同义菜单并存 |
| 文件 →「同步全部」占 `⌘R`，视图 →「刷新当前页」也占 `⌘R` | 只留「刷新当前页」`⌘R`，按当前页分派（服务页重载、列表页同步）；「同步全部」不占快捷键 | 同一组合键不能挂两个菜单项 |
| 视图 →「显示已隐藏的服务」 | 未实施 | 需要新增一个设置项，超出「不新增业务能力」的边界 |
| `⌘F` 聚焦搜索 | 交给 `.searchable` 的系统实现，不额外绑定 | 系统已提供，重复绑定会互相抢键 |
| `Delete` 删除选中通知 | 未实施，删除走右键菜单与横扫 | 通知列表没有选中态，加选中态属于新交互 |
| 帮助 →「诊断与日志」在设置页内跳转 | 改为独立窗口 | 不打断当前页面；`DiagnosticsView` 自带 `NavigationStack` 可直接复用 |

**未做的部分**：无障碍大字号下的行高退化（44 → 56、名称与摘要改两行）——当前行是固定 13 / 11.5pt，
只做了 VoiceOver 标签；`⇧⌘A` 批量已读没有绑定（需要页内作用域，挂在工具栏菜单里不会注册成全局快捷键，
宁可空着也不留一个按下去没反应的手势）；`Delete` 删除选中通知；Dock 菜单与窗口尺寸持久化（P2）；卡片拖出 URL（P3）；
状态栏常驻（受 7.2 限制）。

**验证边界**：本机没有安装 iOS 模拟器 runtime，命令行也拿不到签名账号，因此 iOS 侧只做了 generic 构建验证；
iOS 路径的改动都落在 `#if os(macOS)` 之外为零、或平台取值保持原样（页边距仍 16、`zmGrouped` / `zmCard` 仍走 UIKit 语义色、
`data-zhongmiao-container` 仍为 `ios`）。macOS 侧的界面核对用离屏 `ImageRenderer` 出图（系统截图被当前会话拒绝），
校验完即删掉该调试入口。

---

## 附录 A　事实来源索引

| 结论 | 出处 |
| :-- | :-- |
| 强调色亮 `rgb(60,71,96)` / 暗 `rgb(205,212,226)` | `Resources/Shared/Assets.xcassets/AccentColor.colorset/Contents.json:4-31` |
| 启动背景亮 `rgb(249,249,249)` / 暗 `rgb(16,17,18)` | `Resources/Shared/Assets.xcassets/LaunchBackground.colorset/Contents.json:3-31` |
| 14 组 tint + SF Symbol | `Packages/ZhongmiaoCore/Sources/ZhongmiaoCore/ServiceCatalog.swift:16-175` |
| 6 个分类标题与图标 | `Packages/ZhongmiaoCore/Sources/ZhongmiaoCore/ServiceDefinition.swift:41-61` |
| 「离线可用 / 需要联网」的文案理由 | `ServiceDefinition.swift:22-28` |
| `Color(hex:)` 解析规则 | `Sources/Shared/App/DesignSystem.swift:11-28` |
| `zmGrouped` / `zmCard` 双平台映射 | `DesignSystem.swift:30-46` |
| `ServiceGlyph` 构造 | `DesignSystem.swift:53-77` |
| `CapsuleTag` 构造 | `DesignSystem.swift:81-101` |
| `OfflineBanner` / `EmptyStateView` / `LoadFailureView` | `DesignSystem.swift:105-197` |
| `RelativeTime` | `DesignSystem.swift:201-217` |
| `zmPlainTextInput` 分支 | `DesignSystem.swift:221-233` |
| 三页骨架与 Tab 图标 | `Sources/Shared/App/RootView.swift:16-42` |
| 深链消费 `consumePendingRoute()` | `RootView.swift:56-61` |
| 路由分派 | `RootView.swift:64-86` |
| toast 规格与底部 76 | `RootView.swift:89-111` |
| 栅格与无障碍降级 | `Sources/Shared/Features/CatalogView.swift:20-30` |
| 卡片尺寸、阴影、描边 | `CatalogView.swift:333-352` |
| 卡片内标签与置顶图钉 | `CatalogView.swift:283-331` |
| 首页右键菜单 | `CatalogView.swift:199-250` |
| `Pasteboard` 双平台 | `CatalogView.swift:364-373` |
| 浏览器 `.bottomBar` 被 iOS 门控 | `Sources/Shared/Features/ServiceScreen.swift:119-155` |
| 服务页 `.primaryAction` 菜单 | `ServiceScreen.swift:157-210` |
| 通知 `.swipeActions` 无平台分支 | `Sources/Shared/Features/NotificationsView.swift:232-245` |
| 跳系统设置的 macOS 分支 | `NotificationsView.swift:156-166` |
| 触控板横扫开关 | `Sources/Shared/Features/Native/InAppBrowserSheet.swift:79, 122` |
| Representable 双壳真实位置 | `InAppBrowserSheet.swift:71-157` |
| 搜索框 `@FocusState` | `Sources/Shared/Features/Native/IntegrationSearchField.swift:16, 28` |
| 网页容器 `.refreshable` 仅 iOS | `Sources/Shared/Web/WebViewHost.swift:12-19` |
| UA / 脚本版本 / 容器标记 | `Sources/Shared/Web/WebViewFactory.swift:66, 76, 224` |
| 唯一 Scene 与 `scenePhase` | `Sources/Shared/App/ZhongmiaoApp.swift:16-43` |
| macOS 激活策略与 APNs 回调 | `Sources/macOS/AppDelegateMac.swift:6-31` |
| 外链 / 触觉 / 设备名 / 下载目录 | `Sources/Shared/Core/Platform.swift:13-72` |
| 双 target 配置与能力键 | `project.yml:29-163` |
| 无 entitlements、沙盒未启用 | `project.yml`（无 `entitlements:` 键）、`docs/ARCHITECTURE.md:176-177` |
| 设计系统的文字规范 | `docs/ARCHITECTURE.md:97-99` |
| macOS 现状与后续方向 | `README.md:150, 154` |
| 文档与代码不一致三处 | `docs/ARCHITECTURE.md:169, 171, 174` |
| 关窗不退出与轮询依赖 | `docs/推送方案.md:109` |
| 免费账号能力边界 | `README.md:138-145` |

### 7.5 实施记录（2026-11-16 追加：设置独立窗口与界面缩放）

| 项 | 落点 | 实测 |
| :-- | :-- | :-- |
| 设置独立窗口 | `ZhongmiaoApp.swift` 的 `Settings` 场景；`RootView` 去掉设置标签、加工具栏齿轮；`MacCommands` 移除自挂的「设置…」 | `⌘,` 弹出标题 `"众妙"设置` 的 820×752 窗口；主窗口标签只剩「应用 / 通知」（AX 读到 `AXTabGroup` 两个 `AXRadioButton`） |
| 界面缩放 | `Sources/Shared/App/InterfaceScale.swift`（环境值 + `zmFont` + `zmScaled` + `ControlSize.zm`）、`AppSettings.interfaceScale`、各窗口根上的 `zmInterfaceScale` | 130% / 145% 逐档截图核对：设置页行高、分段控件、开关同步变大，无裁切；主窗口在 130% 退成两栏、145% 仍两栏且摘要完整 |
| 字体全量改造 | 309 处 `.font(...)` → `.zmFont(...)`，含 SF Symbol 图标 | 双端构建通过；1 倍渲染与改造前一致（`fittingSize` 逐项对照） |
| 系统 chrome 不缩放 | 标签栏、工具栏、窗口标题 | 与浏览器缩放观感一致，已在 3.7.2 记为边界 |

> 实测结论（macOS 27）：`dynamicTypeSize` 对 SwiftUI 文字**完全无效**，`.font(.body)` 在 `.accessibility3` 下仍是 79×16；所以界面缩放不能走动态字体，只能按倍数重算字号，再用 `NSFont.preferredFont` 保住基线值。

### 7.6 实施记录（2026-11-16 追加：设置类页面统一卡片与按钮）

| 项 | 落点 | 实测 |
| :-- | :-- | :-- |
| 服务与接入改卡片 | `ServiceSettingsListView` 的 macOS 分支：概览组 + 每个分类一张卡片，行是 `MacServiceLinkRow`（图标 / 名称 / 地址 / 优先级 / 状态 / 箭头），点行 `navigationDestination` 进单服务页 | 列表里 14 个服务分 5 张卡片，首行有键盘焦点时的蓝框正常；130% 下图标 34、行高 57，地址不截断 |
| 单服务配置改卡片 | `ServiceConfigView.formContent` 按平台分流，macOS 走 `macForm`：概览 / 地址 / 鉴权 / 原生能力 / 通知 / 提醒 / 首页显示 / 打开方式 / 诊断与维护 九组，绑定与文案与 iOS 共用 | 与设置页同一套行高与卡片色；「修改凭据」「开启通知权限」「清空收件箱」等按钮均为可见胶囊 |
| ntfy 主题改卡片 | `NtfyTopicsView` 分平台：服务器主题 / 已订阅 / 新建主题 / 服务器 四组 | 「订阅」是整行热区，「取消订阅」是行尾红字按钮，输入框吃满剩余宽度 |
| 诊断改卡片 | `DiagnosticsView` 分平台：连通性（图标 + 地址 + 状态 + `…` 菜单）/ 原生接入（图标 + 优先级·鉴权 + 提醒数 + 状态）/ 离线说明 / 运行状态 / 运行日志 | `…` 菜单用 `.menuStyle(.borderlessButton)` + `.menuIndicator(.hidden)`；日志行可选中复制 |
| 按钮立体化 | `MacSettingsCards.swift` 的 `ZMPushButtonStyle` + `.zmPushButton()`；`SecretField` 的 `secretActionStyle()` 在 macOS 走它 | 暗色下底白 8%（卡片 40 → 约 56），亮色下黑 8%（卡片 255 → 约 235），描边 0.5pt；悬停 / 按下 / 禁用三态逐张截图核对 |
| 「完成」留驻 | `SettingsView` 的 `.toolbar` 从目的地移到 `NavigationStack` 上 | push 进单服务页后右下「完成」仍在（此前会跟着目的地一起消失） |
| 密钥行对齐 | `SecretField` 的 `LabeledContent` 补 `.frame(maxWidth: .infinity)` | 「未设置」不再紧贴标题，与其他行的「标签左、值右」一致 |

> 实测结论（macOS 26/27）：`.bordered` 与 `.borderedProminent` 在深色卡片上都是液态玻璃，透明度低到接近「纯文字」；
> 离屏 `ImageRenderer` 里它们反而能画出底色——材质不在离屏渲染里生效，所以按钮观感只能按真机截图判断。
