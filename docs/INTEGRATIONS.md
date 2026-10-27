# 应用原生接入

众妙原先只做承载：每个应用都塞进 `WKWebView`。原生接入把**有稳定 HTTP API 的应用**
升级为原生界面——首页点进去直接看到数据、能完成高频写操作、提醒由本地通知发出。

三条边界：

1. **不改任何后端**。全部走各应用已有的 HTTP 接口，不新增服务端契约。
2. **不重写业务**。原生只做高频只读与少数可逆写操作，低频、危险、需要复杂交互的功能留网页版。
3. **可随时退回网页**。每个应用都有「优先使用网页版」开关，切回去不影响凭据与缓存。

## 1. 接入矩阵

优先级含义：**P0** 深度读写 + 原生提醒，本次验收重点；**P1** 原生只读 + 轻写；
**P2** 只读看板；**网页** 保留 `WKWebView`。

| 应用 | id | 优先级 | 鉴权 | 原生可读 | 原生可写 | 提醒 |
| :-- | :-- | :-- | :-- | :-- | :-- | :-- |
| 货殖 | `huozhi` | P0 | 账号密码 → JWT | 资产、信用卡账单、分类、书籍、近期流水 | 支出、收入、转账、信用卡还款 | 关 |
| 牵丝 | `qiansi` | P0 | 可选 Bearer | 联系人、纪念日、提醒、约会、统计 | 新建纪念日/约会、完成提醒 | 开（09:00） |
| 青野集 | `qingye` | P0 | 无 | 房间、植物、养护任务、养护记录 | 完成/推迟任务、记浇水施肥 | 开（08:00） |
| 幕间 | `mujian` | P1 | 可选 Bearer | 未来演出、看板、近期记录 | — | 沿用 `ShowScheduler` |
| 吾身 | `diarum` | P1 | 账号密码 → JWT | 今日日记、最近日记、连续天数 | — | 开（21:00） |
| 慎始 | `shenshi` | P1 | 可选 Bearer | 今日/逾期任务、习惯、到期提醒、统计 | 完成任务、习惯打卡 | 开（09:00） |
| 蜂巢 | `qbhive` | P1 | 可选 Bearer | 统计、种子列表、RSS 状态 | 暂停/继续、校验、限速 | 关 |
| ntfy | `ntfy` | P1 | 可选 Bearer | 主题、时间线、搜索 | 标记已读、删除消息 | 关 |
| 月汐 | `yuexi` | P1 | 账号密码 → 会话 | 周期倒计时、异常、通知状态 | — | 开（09:00，脱敏） |
| 拾帧集 | `bili-history` | P2 | 无 | 今日观看、历史、月度统计、热力图 | — | 关 |
| 察新 | `chaxin` | P2 | 无 | 仓库、Release、未读计数 | — | 关 |
| 流霞 | `liuxia` | P2 | 无 | 今日/明日朝霞晚霞、排行 | — | 关 |
| whoami | `whoami` | 网页 | 无 | — | — | — |
| 图切 | `tuqie` | 网页 | 可选 Basic | — | — | — |

whoami 的结论依赖浏览器 JS 与 Client Hints，原生请求只能看到服务端头，结论会失真；
图切的核心是交互式切图且无持久数据。两者保留网页版。

矩阵事实来源是 `IntegrationCatalog.all`，与 `ServiceCatalog.all` 一对一（`validate()` 会拦住
缺项、重复、以及给网页版应用声明原生能力）。两者刻意分开：`ServiceCatalog` 描述「怎么访问」，
`IntegrationCatalog` 描述「原生能做什么」，所以 `zm-catalog` 与 Nginx 生成器都不受影响。

## 2. 分层与文件

```
SwiftUI
  NativeServiceScreen（路由壳）
    ├─ HuozhiScreen / QiansiScreen / QingyeScreen      P0，各自 Model
    ├─ MujianScreen … YuexiScreen                      P1，读屏 + 轻写
    └─ BiliHistoryScreen / ChaxinScreen / LiuxiaScreen P2，只读
  IntegrationSettingsView / SecretField / IntegrationStatusBanner
        │
IntegrationCenter（@MainActor @Observable，AppModel 持有）
  ├─ SecretStore（Keychain 同步读）
  ├─ IntegrationPreferencesStore（独立 UserDefaults key）
  ├─ IntegrationCache（actor，Application Support）
  └─ IntegrationReminderScheduler（UNUserNotificationCenter）
        │
IntegrationHTTP + 各应用 Client（struct，Sendable）
        │
ZhongmiaoCore（纯 Foundation，可单测）
  IntegrationCatalog / IntegrationRouter / IntegrationEnvelope
  IntegrationReminder / 各应用 Planner / QiansiLocalDate / HuozhiDraft
```

| 目录 | 内容 |
| :-- | :-- |
| `Packages/ZhongmiaoCore/Sources/ZhongmiaoCore/Integration/` | 注册表、分流、信封、提醒预算、业务纯逻辑 |
| `Sources/Shared/Integrations/` | 凭据、HTTP、缓存、中心、调度、各应用 Client 与 Model |
| `Sources/Shared/Features/Native/` | 12 个原生页、路由壳、横幅、菜单、刷新修饰器 |
| `Sources/Shared/Features/Settings/` | 接入配置列表与 `SecretField` |

关键约束：`ZhongmiaoCore` 仍只依赖 Foundation。所有易错逻辑（时间解析、提醒排程、
草稿状态机、信封解包）都在里面，`swift test` 不需要模拟器即可覆盖。

## 3. 分流规则

`IntegrationRouter.resolve(serviceID:hasExplicitURL:preferWeb:)` 是唯一入口：

1. 通知深链带明确页面地址 → **网页**（否则丢掉「打开某条记录」的语义）。
2. 该应用在设置里勾了「优先使用网页版」 → **网页**。
3. 已接入且未关闭原生 → **原生**。
4. 其余 → **网页**。

`IntegrationDestination` 的 `.unconfigured` 用于地址还没配好时给配置引导，不锁死页面。

## 4. 凭据

### 4.1 存储

- 钥匙串 service：`im.yufei.zhongmiao.integrations`；account 是应用 id（`huozhi`）或
  `legacy.mujian` / `legacy.ntfy` / `legacy.relay`。
- 值是 `IntegrationCredential` 的 JSON：`token` / `username` / `password` / `jwt` /
  `sessionCookie` / `expiresAt` / `updatedAt`。
- 可访问性 `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`，不同步 iCloud。
- macOS 先试数据保护钥匙串，遇 `errSecMissingEntitlement` / `errSecParam` 退回传统钥匙串。
- **任何钥匙串失败都直接报错，绝不回退明文**。

### 4.2 从明文迁移

`LegacySecretMigration.run()` 在 `AppModel.init` 里、读取设置之前执行：用 `JSONSerialization`
读 `zhongmiao.settings.v1` 原始 JSON，取出 `mujianToken` / `ntfyToken` / `relaySecret`，
写钥匙串 → 读回校验 → 从原始 JSON 删除 → 写回。单项失败只保留该项并记警告，不清空；
钥匙串已有值时跳过，因此天然幂等。

`AppSettings` 已删除这三个字段；`AppModel` 用计算属性 `mujianToken` / `ntfyToken` / `relaySecret`
读 `SecretStore`，`ShowStore.refresh(settings:token:)`、`buildTargets`、`pushReadStateToServer`、
`uploadPushToken` 都改读钥匙串。设置页与 ntfy 主题页的明文输入换成 `SecretField`
（SecureField + 已保存/未设置 + 保存/清除）。

### 4.3 状态机

`.noAuth` / `.unconfigured` / `.checking` / `.valid(checkedAt)` / `.expired(reason)` / `.invalid(reason)`。
`isUsable` 决定写操作是否可用，`needsAttention` 决定是否在原生页顶部挂「凭据已失效 · 重新授权」横幅。

### 4.4 校验端点

| 应用 | 校验方式 |
| :-- | :-- |
| 货殖 | `POST /api/auth/login` → `GET /api/auth/me`，`expire_in` 记过期时间 |
| 牵丝 | `GET /api/v1/health`（鉴权门内，401 即需要 Token） |
| 青野集 | `GET /healthz` |
| 幕间 | `GET /api/stats` |
| 吾身 | `POST /api/v1/auth/login` → `GET /api/v1/diaries/stats?tz=` |
| 慎始 | `GET /api/auth/status` → 需要口令则 `POST /api/auth/login`，再 `GET /api/bootstrap` |
| 蜂巢 | `GET /api/torrents/stats` |
| ntfy | 有令牌 `GET /v1/account`，无令牌 `GET /v1/topics` |
| 月汐 | `POST /login`（表单）→ 从 `Set-Cookie` 取会话 → `GET /api/records` |
| 拾帧集 / 察新 / 流霞 | `GET /api/health` |
| whoami / 图切 | `GET /api/whoami` / `GET /api/health`（仅用于连通性） |

保存策略是**先验证、后落库**：验证失败不会覆盖现有可用凭据。`credentialOptional` 为真的应用
（牵丝、幕间、慎始、蜂巢、ntfy）允许空令牌保存，因为服务端不校验时令牌本来就可以为空。

401 的处理：登录型应用先用钥匙串里的账号密码静默重登一次，仍失败才标 `.expired`。
密码只进钥匙串，不进日志、不进对话。

## 5. HTTP 与错误

`IntegrationHTTP` 只负责拼地址、带凭据、判状态、转错误；信封与 DTO 由各 Client 自己解。

- 基址来自 `ServiceURLResolver`（`AppModel.url(for:)`），三种地址模式与逐服务覆盖照旧。
- 15s 请求超时 / 30s 资源超时，UA `Zhongmiao/0.1`，强制 `Accept: application/json`，
  `requestCachePolicy = .reloadIgnoringLocalCacheData`。
- `httpShouldSetCookies = false`：月汐的会话 Cookie 手动从钥匙串取、写成 `Cookie: session=…`，
  不污染全局 Cookie 罐，也就不会和 WebView 的登录态互相踩。
- 写请求**不自动重试**。GET 只提供一次手动重试入口。
- 响应是 HTML 就抛 `.notJSON`（牵丝未知路径会回 SPA HTML，不识别会被误判成解析失败）。
- 错误统一为 `IntegrationAPIError`：`.unauthorized` / `.forbidden` / `.rateLimited(retryAfter:)` /
  `.http(status:message:)` / `.notJSON` / `.decoding` / `.transport` / `.notConfigured`。
  3xx 视为凭据失效（月汐 303 跳 `/login` 即此路径）。

信封各家不同，只做必要 helper、不做通用协议：牵丝裸 JSON；青野/货殖 `{code,message,data}`；
蜂巢 `{success,…}`；拾帧集 `{status,data}`；其余裸 JSON 或 `{error}`。

## 6. 缓存与降级

`IntegrationCache`（actor）每应用一个文件：
`Application Support/Zhongmiao/integrations/<id>.json`，包装 `IntegrationCache.Snapshot<Payload>`
（`fetchedAt` + `payload`）。原子写；解码失败把文件改名 `.corrupt-<ts>.json` 而不是静默覆盖；
文件标记 `isExcludedFromBackup`，保护级别 `completeUntilFirstUserAuthentication`。

刷新时机：进入页面 `.task`、下拉刷新、网络恢复、回前台且距上次超过 5 分钟。
集成数据不进 `BGAppRefreshTask`（时间片短且已被通知同步与演出刷新占用）；
本地提醒按最近一次前台快照排程，App 被杀后照常投递。

| 情况 | 表现 |
| :-- | :-- |
| 未配置凭据 | 横幅「需要连接」，保留网页版入口 |
| 401 / 403 | 横幅「凭据已失效」，写操作禁用，缓存仍可读，重授权后自动重试一次 |
| 429 | 显示「请求过于频繁」，按 `Retry-After` 提示，不自动重试 |
| 5xx / 超时 | 旧缓存 + 错误横幅 + 重试，**不清缓存** |
| HTML 冒充 JSON | `.notJSON`，提示接口不可用并给网页版入口 |
| 货殖写超时 | 进入「结果未知」，刷新流水核对，**绝不自动重发** |
| 服务不可达 | 离线横幅，恢复网络自动刷新 |
| 低频/危险操作 | 跳网页版 |

## 7. 原生提醒

`IntegrationReminderScheduler` 只注册一个类别 `im.yufei.zhongmiao.integration`，动作「查看」
（仅前台）；点击后带 `integrationServiceID` 交给 `NotificationDelegate` 路由到原生页。

- ID 形如 `integration.<service>.<kind>.<stableKey>.<yyyyMMdd>`，`stableKey` 只保留字母数字
  与 `-_`、截断 40 字符。清理按 `integration.<service>.` 前缀，绝不碰 `show.` 前缀的演出提醒。
- 预算：每应用 12 条、总计 48 条（系统单 App 上限 64），过期项先丢、按 id 去重、按时间取最近的。
- 开关与时刻存 `IntegrationPreferences`（`zhongmiao.integrations.v1`），不进 `AppSettings`；
  默认时刻：青野 08:00、吾身 21:00，其余 09:00。
- 不主动弹权限，设置里提供「开启提醒」，复用 `NotificationScheduler.requestAuthorization()`。

| 应用 | 规则 |
| :-- | :-- |
| 牵丝 | 纪念日按服务端 `remindDays` 逐档排（7/3/1/0）；约会按提前天数；自定义提醒按 `dueAt` 的钟点 |
| 青野集 | 按到期日汇总成每日一条养护摘要（最多列 3 项 + 总数），过期任务归到今天 |
| 吾身 | 当天没有日记时 21:00 提醒一次 |
| 慎始 | 取 `/api/reminders/due` 的 `fireAt`，无时刻的用全局时刻 |
| 月汐 | 下次周期倒计时，文案脱敏（只写「有新的周期提醒」） |
| 幕间 | 沿用现有 `ShowScheduler`，不重复排 |

## 8. 各应用数据流

### 货殖（P0，唯一有金额写入）

```
缓存 → /api/auth/me → /api/books（选默认书）
     → 并发 /api/accounts、/api/categories、/api/statistics/assets、/api/transactions?page_size=15
提交 → POST /api/transactions
  成功 → 刷新流水/账户/资产
  超时/断连 → draft = .unknown → GET /api/transactions?start_date=今天
            → 按金额+账户+日期+描述匹配：命中提示「已保存」，否则交用户决定，禁止再次提交
```

- `HuozhiDraft` 状态机在 Core，可单测：`draft → submitting → confirmed | unknown`。
- 金额 UI 用 `Decimal`，只在 JSON 边界转 `Double`；`book_id` 必须是具体书籍，不能用 0。
- API Key 只能读公开账单，原生记账必须走账号密码登录；信用卡余额符号相反（转入即减债）。
- 网页版仍负责：预算、分期、借贷、报销、导入导出、对账、账户与分类管理。

### 牵丝（P0）

```
缓存 → /api/v1/people?limit=50、/anniversaries、/reminders/upcoming?days=30、
       /events?from=今天&to=+30d&limit=50、/dashboard/stats
→ 按日期合并分组 → 渲染 + 生成提醒计划
完成提醒 → POST /api/v1/reminders/{id}/done；新建 → POST /anniversaries | /events
```

- 业务时间是**无时区的本地墙钟字符串**，用 `QiansiLocalDate` 解析
  （`yyyy-MM-dd'T'HH:mm:ss` / `yyyy-MM-dd'T'HH:mm` / `yyyy-MM-dd`），不要用带 offset 的 ISO8601，
  否则提醒会偏几个小时。
- 只创建、不编辑：`PUT` 是全量替换，容易清空字段，编辑走网页版。
- 派生提醒 id（`anniv:` / `promise:` / `contact:`）只允许 `POST /done`，不能 PUT/DELETE。

### 青野集（P0，无鉴权）

```
缓存 → /api/rooms、/api/plants、/api/tasks/upcoming?days=14、/api/care-logs?limit=20
完成 → POST /api/tasks/{id}/done {note}；推迟 → POST /api/tasks/{id}/postpone {days,note}
记养护 → POST /api/care-logs {plantId,type,title,note,at}
```

- 不用 `/api/tasks/today`：非工作日会返回空数组，原生按 `upcoming` 自行算逾期/今天/本周。
- 完成后的 `nextDue` 保留当前时刻，展示时归一化到日期。

### 其余应用

| 应用 | 读 | 写 |
| :-- | :-- | :-- |
| 幕间 | `/api/records/upcoming`、`/api/dashboard` | — |
| 吾身 | `/api/v1/diaries/recent`、`/diaries/stats?tz=` | —（写入会整段覆盖正文） |
| 慎始 | `/api/tasks?smart=`、`/habits`、`/reminders/due`、`/stats` | `POST /api/tasks/{id}/done {completed}`（幂等，不用 `/toggle`）、习惯打卡 |
| 蜂巢 | `/api/torrents/stats`、`/api/torrents`、`/api/rss/status` | `perform(action:hash:)`：暂停/继续/校验/限速 |
| ntfy | `/v1/topics`、`/{topic}/json?poll=1&since=7d`、`/v1/search` | `GET /{topic}/{ids}/read`（≤50/批，非法 id 先剔除）、删除消息 |
| 月汐 | `/api/notification/status`、`/api/anomaly` | —（只给倒计时，详情留网页版） |
| 拾帧集 | `view_at` 用 epoch 秒；`/api/history/all`、`/api/viewing/monthly-stats`、`/api/daily/daily-count` | — |
| 察新 | `/api/repos`、`/api/notifications`（limit 20）；`0001-01-01` 按「无」处理 | —（不调 `/api/settings`，会漏 GitHub Token） |
| 流霞 | `/api/today`、`/api/cities`、`/api/rankings` | —（不无界拉 `/api/data`） |

## 9. 设置与重授权

- 设置 → **应用接入**：按 P0/P1/P2/网页分组，行内给状态点、鉴权类型、优先级。
- 详情页：可读/可写清单、凭据表单（`SecretField` 或用户名+密码）、保存并验证、清除凭据、
  过期时间与最近验证时间、打开原生页/网页版、「优先使用网页版」开关、
  以及「哪些高级操作仍在网页版」的说明。
- 原生页在未配置或失效时只挂内联横幅，不锁死页面：下方仍可看缓存、可跳网页版。

## 10. 验证

### 自动化

```bash
cd Packages/ZhongmiaoCore && swift test          # 141 个用例，含接入注册表/路由/信封/提醒/时间解析/草稿
cd ../.. && xcodegen generate
xcodebuild -project Zhongmiao.xcodeproj -scheme Zhongmiao -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Zhongmiao.xcodeproj -scheme ZhongmiaoMac \
  -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

注册表描述改动后要重生成导出（Nginx 配置不受描述影响）：

```bash
swift run --package-path Packages/ZhongmiaoCore zm-catalog > deploy/catalog.json
```

### 本地端到端

用临时数据目录起服务，不碰真实数据：

```bash
cd ~/Git/qingye  && PORT=18081 DB_PATH=/tmp/zm-qingye.db go run ./cmd/qingye
cd ~/Git/qiansi  && QIANSI_ADDR=:18080 QIANSI_DATA_DIR=/tmp/zm-qiansi QIANSI_TOKEN=dev go run ./cmd/server
cd ~/Git/huozhi  && HZ_PORT=18082 go run ./cmd/huozhi-server
```

模拟器安装 Debug 包后，用 `IntegrationDebugSeed`（仅 DEBUG 编译）通过启动环境变量预置凭据并直达页面：

```bash
xcrun simctl launch --console booted im.yufei.zhongmiao \
  -ZM_PREVIEW_SERVICE qingye \
  -ZM_QIANSI_TOKEN dev \
  -ZM_HUOZHI_USERNAME test -ZM_HUOZHI_PASSWORD test
```

`ZM_PREVIEW_SERVICE` 会按内置的 `127.0.0.1:1808x` 映射直连对应服务并跳过地址配置；
配合 `xcrun simctl io booted screenshot` 可直接截图验收。

### 关键回归

- **迁移**：写入含三个旧密钥的设置 JSON → 启动 → 确认 `UserDefaults` 无明文、钥匙串有值、
  ntfy/中继/幕间仍正常。抽查：
  `security find-generic-password -s im.yufei.zhongmiao.integrations -a legacy.ntfy -w`
  （不要把值贴进日志）。
- **货殖超时**：本地反代转发 POST 后返回 504 → 只产生一条流水、界面进「结果未知」、
  核对后能找到、不会自动重发。
- **牵丝时间**：非当前时区/夏令时下验证 `QiansiLocalDate` 与提醒落点。
- **通知预算**：构造超过 12 条生日/任务，确认每应用上限与清理逻辑。
- **catalog 未被污染**：`swift run --package-path Packages/ZhongmiaoCore zm-catalog | diff - deploy/catalog.json`。

## 11. 已知风险

- **ATS**：原生请求不享受 `NSAllowsArbitraryLoadsInWebContent`，只有 `NSAllowsLocalNetworking`
  覆盖局域网；公网自签或纯 HTTP 会被拦。验证不过时不静默放行，提示改用 HTTPS 或内网地址。
- **macOS 钥匙串**：无付费账号时数据保护钥匙串可能因签名能力失败，退回传统钥匙串并提示一次。
- **货殖无幂等键**：超时绝不自动重发，`HuozhiDraft` 必须覆盖「未知—核对—重试」全流程。
- **牵丝失败形态**：未配置 Token 时未知 `/api` 路径可能回 SPA HTML，必须识别成 `.notJSON`。
- **月汐服务端越权**：`/record/edit`、`/api/daily/` 等存在 IDOR，原生只做脱敏只读；
  公开部署前需单独修后端。
- **ntfy 暴露面**：该 fork 的 `/v1/topics` 与 `/v1/search` 未做鉴权，建议在 Nginx 限制；
  原生不扩大暴露面。
- **破坏性操作**：蜂巢删文件、图切导出、月汐记录编辑一律留在网页版。
- **大响应**：拾帧集报告、流霞 `/api/data`、察新通知正文都可能很大，首屏只取小分页。
- **设置解码**：新增偏好一律独立存储并逐字段 `decodeIfPresent`；迁移必须先于首次保存。
