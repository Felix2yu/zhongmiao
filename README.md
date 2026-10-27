# 众妙

把 `~/Git` 下那批 Go 后端 + 前端页面的自建应用，收进一个原生 iOS 壳里：
一个入口、一套地址配置、一条不丢消息的通知链路，以及**能直接读写数据的原生界面**。

- **部署形态**：所有应用跑在 Docker 里，外层 Nginx + HTTPS（子域名反代）
- **平台**：iOS 27+（主），macOS 27+（同源码编译，能力预留）
- **技术栈**：SwiftUI + WebKit `WebPage`/`WebView`（iOS 26+ 原生 API）+ Swift 6 并发 + SwiftPM 核心包
- **依赖**：零第三方库。工程用 XcodeGen 生成。

## 现在能做什么

| 能力 | 实现方式 |
| :-- | :-- |
| 14 个应用的统一入口 | 服务网格 + 分类 + 搜索，每张卡片显示离线能力与未读数；能力标签可在设置里一键隐藏 |
| 原生接入 12 个应用 | 走各应用已有 HTTP API，原生界面直接看数据、记账、完成任务，不依赖网页加载 |
| 内嵌承载，功能可用 | WKWebView 持久化数据存储，保留各应用的 Cookie / localStorage / Service Worker 缓存 |
| 离线可用 | 沿用各应用自己的 `sw.js` 缓存；断网时给原生错误页与重试，恢复网络自动 `reloadFromOrigin` |
| 站内/站外分流 | 同站（含子域）留在应用内，外链交给系统浏览器，OAuth 域名白名单放行 |
| 通知不丢 | 页面内 `Notification` 桥接 + ntfy / JSON 流轮询 + APNs 中继，三者共用一份去重账本 |
| 原生提醒 | 生日/纪念日、植物养护、今日任务、日记与周期倒计时排成本地通知，不依赖各应用推送 |
| 凭据集中管理 | 全部 Token 与账号密码存钥匙串（`AfterFirstUnlockThisDeviceOnly`），旧版明文自动迁移，日志不落令牌 |
| ntfy 主题浏览 | 读服务器 `/v1/topics`，点一下就订阅多个主题，不必进 ntfy 网页版 |
| 已读状态同步 | 收服务端 `message_clear` 广播（别处读过这边也变已读），本地标已读再经 `/read` 推回服务端 |
| 断线补发 | 每条通知带游标与去重键；离线排队，重连/回前台/授权后原地补投 |
| 服务诊断 | 并发探测 14 个服务的可达性，给出需登录/证书/解析失败等具体原因；入口在「设置 → 诊断」 |
| 下载与分享 | 非 HTML 响应自动走下载，落到「下载」目录；工具栏系统分享 |

原生接入的能力矩阵、数据流与降级规则见 [docs/INTEGRATIONS.md](./docs/INTEGRATIONS.md)：
3 个 P0（货殖记账、牵丝提醒、青野养护）读写皆有，6 个 P1 看板加少量可逆操作，
3 个 P2 只读，whoami 与图切按设计保留网页版。

## 快速开始

```bash
brew install xcodegen        # 只需一次
cd ~/Git/zhongmiao
xcodegen generate
open Zhongmiao.xcodeproj
```

命令行验证：

```bash
# 1) 核心逻辑单测（141 个用例，不需要模拟器）
cd Packages/ZhongmiaoCore && swift test

# 2) 双端编译
cd ../..
xcodebuild -project Zhongmiao.xcodeproj -scheme Zhongmiao \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build

xcodebuild -project Zhongmiao.xcodeproj -scheme ZhongmiaoMac \
  -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

模拟器默认没有设备，需要先建一台（Pro 机型与现有 runtime 不兼容，用非 Pro）：

```bash
xcrun simctl create "众妙测试" "iPhone 17" com.apple.CoreSimulator.SimRuntime.iOS-27-0
xcrun simctl boot <UDID> && open -a Simulator
```

## 首次运行必做四件事

1. **设置 → 接入方式**：选「子域名」并填你的基础域名（默认 `qfpqhyl.top` 是从仓库 README 推断的，
   只是占位）。改完所有服务地址立即重算。
2. **设置 → 服务与接入**：一个服务一页，填它的自定义地址、令牌或账号密码，点「保存并验证」。
   无鉴权的青野集、拾帧集、察新、流霞只需点一次「测试连接」。
3. **设置 → 诊断 → 全部检测**：一眼看出域名/证书哪个不对，再逐条修。
4. **通知授权**：在「通知」页按需开启（不在冷启动时弹窗）；各应用的原生提醒还要在
   它的服务配置页里单独开关。

服务器侧的反代配置不用手写，从同一份注册表生成：

```bash
swift run --package-path Packages/ZhongmiaoCore zm-catalog > deploy/catalog.json
python3 deploy/nginx/gen_nginx.py --domain 你的域名
docker exec nginx nginx -t && docker exec nginx nginx -s reload
```

详见 [deploy/README.md](./deploy/README.md)。

## 目录

```
project.yml                      XcodeGen 工程定义（iOS + macOS 双 target 共享源码）
Packages/ZhongmiaoCore/          纯 Foundation 核心包：注册表、账本、去重、协议解析、退避、接入纯逻辑
  Sources/ZhongmiaoCore/
    Integration/                 接入矩阵、分流规则、信封、提醒预算、时间解析、记账草稿
  Tests/ZhongmiaoCoreTests/      141 个用例
deploy/
  catalog.json                   注册表导出（由 zm-catalog 生成）
  nginx/gen_nginx.py             从注册表生成 Nginx 反代配置
  nginx/zhongmiao.conf           生成产物（14 个 server 块 + 可选中继）
  README.md                      Docker + Nginx + HTTPS 部署流程与常见坑
Sources/
  Shared/App/                    入口、RootView、AppModel、设计系统、设置模型
  Shared/Features/               服务网格、承载页、收件箱、诊断、设置、服务配置
  Shared/Features/Native/        12 个原生接入页、路由壳、失效横幅
  Shared/Features/Settings/      密钥输入框（中继共享密钥）
  Shared/Integrations/           钥匙串、HTTP、缓存、接入中心、提醒调度、各应用 Client
  Shared/Notifications/          账本落盘、引擎、调度器、代理、HTTP 客户端
  Shared/Web/                    WebPage 配置、JS 桥、导航决策、承载视图
  iOS/                           AppDelegate、BGTask
  macOS/                         AppDelegate
Resources/Shared/                Assets、Info.plist（双端各一份）、隐私清单
server/push-relay/               可选 Go 中继：设备注册 + APNs + 补发接口（仅标准库，含 Dockerfile）
docs/                            架构、通知契约、服务注册表、原生接入
```

## 四个关键设计

**1. 地址必须可切换，不能写死端口。**
`mujian / liuxia / huozhi / chaxin / qiansi` 容器内部都监听 8080——说明真实访问走反向代理子域名。
所以注册表同时支持「子域名模式」与「内网端口模式」，并允许逐服务覆盖。诊断页会立刻暴露写错的地址。

**2. 通知在 iOS 上必须由原生接管。**
WKWebView 不支持 Web Push，`ServiceWorkerRegistration.showNotification` 也不会进系统通知中心。
于是注入脚本把页面里的 `Notification` 与 `showNotification` 拦下来交给原生；再叠加 ntfy 轮询与 APNs 中继，
三条通道最终写进同一份账本，按去重键合并、按游标补发。

**3. 地址只写一份，反代从注册表生成。**
服务清单在 `ServiceCatalog` 里，`deploy/nginx/gen_nginx.py` 用它生成 Nginx 配置——
容器名、内部端口、子域名三处不会各写一遍再漂移。新增服务只需改注册表 + 重跑脚本。

**4. 原生接入不重写业务，只做壳层该做的事。**
`ServiceCatalog`（怎么访问）与 `IntegrationCatalog`（原生能做什么）刻意分开，所以加原生界面
不需要动部署链路。写操作只挑高频、可逆的；预算、分期、关系图谱这类复杂交互留网页版。
凭据一律进钥匙串，任何钥匙串失败都直接报错，不会退回明文。

顺带解决了离线的前提：Service Worker 只在安全上下文注册，而你的 Nginx + HTTPS 正好满足，
所以各应用自带的 `sw.js` 缓存真的生效。只有在临时改成 `http://IP:端口` 排障时才会失去离线能力。

## 已知限制

- **后台刷新是尽力而为**：`BGAppRefreshTask` 受系统调度，不能保证时间。真正兜底的是「回前台/重连全量补发」。
  原生接入的快照也只在进入页面/回前台时刷新，不做后台补拉。
- **原生请求受 ATS 约束**：`NSAllowsArbitraryLoadsInWebContent` 只放开网页内容，
  纯 HTTP 或自签证书的公网地址会被拦，只有 `NSAllowsLocalNetworking` 覆盖局域网。
- **APNs 需要付费开发者账号**：不配中继也能用全部本地通知与轮询能力，只是没有「App 被杀死时立即送达」。
  免费账号的签名描述文件 7 天过期，过期后 App 打不开、快捷指令拉不起灵动岛，需重新签名安装
  （`tools/renew-signing.sh` 已每天自动检查）。
- **macOS 钥匙串可能降级**：无付费账号时数据保护钥匙串可能因签名能力失败，会退回传统钥匙串并提示一次。
- **首次离线需要预热**：应用必须先在线打开过一次，`sw.js` 才会缓存外壳（HTTPS 下已具备条件）。
- **容器重建后需 reload Nginx**：upstream 用容器名解析，IP 变化后不 reload 会 502。
- **第三方 OAuth 可能拒绝 WebView**：Google 等对 WebView UA 有限制，必要时用「在浏览器打开」完成授权。
- **自签证书不豁免**：默认走系统信任链，没有做「无条件信任」开关（避免把安全口子开成默认行为）。
- **macOS 目前是共享同一套 TabView 界面**，还没有做侧边栏/多窗口的原生形态。

## 后续可以接着做

- macOS 原生形态：`NavigationSplitView` 侧边栏 + 多窗口 + 菜单栏命令
- 反代配置直接下发：注册表变更后自动更新 Nginx（含 `nginx -t` 校验与回滚）
- App Intents / 快捷指令：一句话打开某个应用或跳到某条任务
- 可选的自签证书信任（按域名指纹固定，需用户显式确认）
- 通知分组与免打扰时段；按服务的静音规则
- 服务注册表改为可远程下发的 JSON，新增应用不必重新编译
- 原生接入扩展到后台补拉：给接入快照单独开一个刷新任务，让提醒在长时间不打开 App 时也保持准确
