# 服务注册表

内置 14 个服务，事实来源四份：

1. `~/Git/PWA支持现状审计.md`（PWA 成熟度、图标契约、2026-10-10 整改记录）
2. 各仓库 `Dockerfile` 的 `EXPOSE` → **容器内部端口**
3. 各仓库 `docker-compose.yml` 的 `container_name` / 服务名 → **Docker DNS 名**
4. 部署形态已确认为 **Docker + Nginx + HTTPS** → 默认子域名模式

## 现状

| 应用 | id | 分类 | 容器 | 内部端口 | 子域 | PWA / 离线 |
| :-- | :-- | :-- | :-- | --: | :-- | :-- |
| 慎始 | `shenshi` | 效率与任务 | `shenshi` | 8787 | `shenshi` | ✅ 手写 `sw.js` + Web Push |
| 幕间 | `mujian` | 影像与媒体 | `mujian` | 8080 | `mujian` | ✅ 手写 `sw.js` + push |
| 拾帧集 | `bili-history` | 影像与媒体 | `bili-history` | 8899 | `bili` | ✅ Workbox |
| 流霞 | `liuxia` | 影像与媒体 | `liuxia` | 8080 | `liuxia` | ✅ Go 动态生成 SW |
| 图切 | `tuqie` | 影像与媒体 | `tuqie` | 7423 | `tuqie` | ✅ 手写 `sw.js` |
| 货殖 | `huozhi` | 财务 | `huozhi` | 8080 | `huozhi` | ✅ Workbox |
| 吾身 | `diarum` | 知识与阅读 | `diarum`* | 8090 | `diarum` | ✅ 最规范 PWA |
| 青野集 | `qingye` | 知识与阅读 | `qingye` | 8081 | `qingye` | ✅ Workbox |
| 察新 | `chaxin` | 知识与阅读 | `chaxin` | 8080 | `chaxin` | ✅ 整改后补全 manifest + SW |
| 牵丝 | `qiansi` | 知识与阅读 | `qiansi` | 8080 | `qiansi` | ✅ 整改后引入 `vite-plugin-pwa` |
| 月汐 | `yuexi` | 生活 | `yuexi`* | 8080 | `yuexi` | ✅ Go 动态生成 SW |
| ntfy | `ntfy` | 基建与运维 | `ntfy` | 80 | `ntfy` | ✅ 官方 PWA |
| 蜂巢 | `qbhive` | 基建与运维 | `qbhive` | 8088 | `qbhive` | ❌ 明确不做 PWA |
| whoami | `whoami` | 基建与运维 | `whoami`* | 8080 | `whoami` | ❌ 明确不做 PWA |

\* 仓库里没有 compose 文件，容器名按 id 假定。起名不同就改 `ServiceCatalog` 的 `container:`。

12 个 Web 应用全部达到 PWA 契约，所以「离线」对绝大多数入口可用——前提是 HTTPS，而你的部署正好满足。

## 原生接入分层

这张表只描述访问方式。**原生能做什么**记在另一份注册表 `IntegrationCatalog` 里，两者一一对应
（`IntegrationCatalog.validate()` 会拦住缺项、重复、以及给网页版应用声明原生能力）：

| 分层 | 应用 |
| :-- | :-- |
| P0 深度接入（读写 + 提醒） | 货殖、牵丝、青野集 |
| P1 原生看板（只读 + 轻写） | 幕间、吾身、慎始、蜂巢、ntfy、月汐 |
| P2 只读看板 | 拾帧集、察新、流霞 |
| 保留网页版 | whoami（依赖浏览器 JS/Client Hints）、图切（交互式切图，无持久数据） |

刻意分成两份而不是塞进 `ServiceDefinition`：`zm-catalog` 与 `deploy/nginx/gen_nginx.py` 只消费
访问属性，加原生界面不该让部署链路跟着动结构。

原生实现的接口矩阵、凭据与降级规则见 [INTEGRATIONS.md](./INTEGRATIONS.md)。

## 内部端口 ≠ 宿主机端口

`mujian / liuxia / huozhi / chaxin / qiansi` 内部都监听 **8080**。宿主机不可能把它们都映射到 8080，
所以正解是让 Nginx 反代到 **容器名:内部端口**，而不是 `127.0.0.1:映射端口`。

App 里的「内网端口」模式填的是**宿主机映射端口**，只用于排障直连；
日常请用「子域名」模式（`https://<子域>.<你的域名>`）。

## 三种地址模式

| 模式 | 形态 | 何时用 |
| :-- | :-- | :-- |
| 子域名 | `https://shenshi.example.com/` | 默认。一个应用一个 server 块，与现有反代一致 |
| 子路径 | `https://example.com/shenshi/` | Nginx 用 `location /shenshi/` 分流时。注意 SPA 根路径资源会 404 |
| 内网端口 | `http://192.168.1.10:8787/` | 只用于排障。会失去 Service Worker 离线能力 |

解析优先级：**逐服务覆盖 > 服务内置绝对地址 > 全局模式**。

## 与部署配置保持同步

`ServiceCatalog` 是唯一事实来源，Nginx 配置由它生成：

```bash
swift run --package-path Packages/ZhongmiaoCore zm-catalog > deploy/catalog.json
python3 deploy/nginx/gen_nginx.py --domain example.com
docker exec nginx nginx -t && docker exec nginx nginx -s reload
```

详见 [deploy/README.md](../deploy/README.md)。

## 新增一个服务

1. 在 `ServiceCatalog.all` 里加一条：

```swift
ServiceDefinition(
    id: "myservice",
    name: "我的服务",
    summary: "一句话说明",
    symbol: "shippingbox",          // SF Symbol
    tint: "4C8DF6",                 // 6 位十六进制
    category: .productivity,
    kind: .pwa,                     // pwa / web / utility
    path: "/",                      // 落地路径
    defaultPort: 8080,              // Dockerfile 的 EXPOSE
    container: "myservice",         // compose 的 container_name
    notificationFeedPath: "/api/notifications"   // 仅在该应用真的实现了这个接口时才填
)
```

2. 在 `IntegrationCatalog.all` 里加一条说明（要不要原生界面、什么鉴权、能读能写什么、
   哪些操作留网页版）。`.web` 优先级必须留空 `capabilities`，`.login` 不允许可选凭据
3. `swift test`（两份注册表都会自检：重复 id、非法色值、同名容器端口冲突、接入矩阵缺项）
4. 重新生成 `catalog.json` 与 Nginx 配置，`nginx -t` 后 reload
5. App 里「体检 → 全部检测」；若要原生界面，再补 Client/Model/Screen 与提醒 planner

## 逐服务覆盖

用户级覆盖存在 `UserDefaults`，不写回代码：

- 自定义地址（完整 URL，粘贴时自动清洗协议/端口/路径）
- 通知开关、通知流路径、ntfy 主题
- 置顶与首页隐藏：置顶只改分组内顺序（同优先级保持注册表顺序），隐藏只从首页撤下卡片，
  不影响通知同步与地址解析；隐藏项在「设置 → 服务 → 逐服务配置」里始终可见，是恢复入口
- 恢复默认：删除该服务的覆盖项

体检页展示「实际解析出的地址 + 可达性」，与 Nginx 不一致时一眼能看出。
