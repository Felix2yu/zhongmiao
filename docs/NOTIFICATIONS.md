# 通知契约

众妙把三件不同的事收敛成一条链路：**页面里的提醒**、**服务端事件**、**远端推送**。
它们最终都进入同一份账本，用同一套去重键合并。

## 三条通道

| 通道 | 适用 | 是否改后端 | 实时性 |
| :-- | :-- | :-- | :-- |
| 页面桥接 | 页面里调用 `new Notification()` / `showNotification()` 的提醒 | 否，壳层自动接管 | 立即（页面存活时） |
| ntfy 轮询 | 已经在往 ntfy 主题投递的告警 | 否，配主题名即可 | 前台秒级，后台按刷新周期 |
| JSON 通知流 | 应用自己实现事件接口 | 是（约 20 行） | 同上 |
| APNs 中继 | App 被杀死也要立刻收到 | 是（部署中继 + 投递事件） | 秒级 |

前三条不需要 Apple 开发者账号；APNs 需要付费账号，且必须部署 `server/push-relay`。

## 页面桥接

注入脚本在 `documentStart` 覆盖两处 API，并在所有自有页面生效：

```js
// 页面主动调用（可选）
window.__zhongmiao.notify("构建完成", "shenshi v1.2.3", "/builds/42");
window.__zhongmiao.haptic("success");
window.__zhongmiao.open("https://example.com");

// 自动接管，页面代码不用改
new Notification("标题", { body: "正文", tag: "task-42", data: { url: "/tasks/42" } });
registration.showNotification("标题", { body: "正文", tag: "build-1" });
```

- `tag` 会作为去重键的一部分：`<service>#web#<tag>`。
- `data.url` 或 `tag` 若像 URL，点击通知会直接打开那一页。
- `Notification.permission` 被报告为 `granted`，`requestPermission()` 返回已授权——
  权限实际由系统通知授权决定，页面无需也不应再问一次。

**注意**：Service Worker 里的 `push` 事件不会经过页面，因此 Web Push 仍然不可用。
需要在 App 被杀时送达，只有 APNs 中继这一条路。

## JSON 通知流（可选实现）

```
GET /api/notifications?since=2026-10-24T05:00:00.000Z&limit=50
```

```json
{
  "items": [
    {
      "id": "evt_123",
      "title": "任务到期",
      "body": "今天有 3 个任务未完成",
      "createdAt": "2026-10-24T05:00:00Z",
      "url": "/tasks?due=today",
      "priority": "active"
    }
  ],
  "nextCursor": "2026-10-24T05:00:00Z"
}
```

约定：

- 按 `createdAt` **升序**返回；`since` 为开区间（严格大于）。
- `id` 稳定且唯一。没有 `id` 时壳层用「时间 + 标题/正文指纹（FNV-1a）」兜底。
- `url` 可为相对路径，壳层会拼到服务地址上。
- `priority`：`passive` / `active` / `time-sensitive`（也接受 `high`、`urgent`）。
- 401/403 视为「需要登录」，记入日志但不重试。

## ntfy 轮询

```
GET <ntfy 地址>/<topic>/json?poll=1&since=<unix 秒>
```

用 `poll=1` 而不是长连接：后台被系统挂起时 SSE 会断，而 poll 每次都能拿到「自游标以来」的全部消息，
天然支持断线补发。`open` / `keepalive` 事件会被过滤；`priority` 1–2 → 静默，3 → 常规，4–5 → 时效。

### 独立订阅（App 内一键订阅）

「设置 → ntfy 主题」直接读 `GET <ntfy 地址>/v1/topics`（不要求鉴权）列出服务器上已有消息的主题，
点一下即订阅；也可以手填主题名（ntfy 按需创建，第一次发布才会出现在列表里）。
这条路径不依赖 ntfy 网页版——网页版的订阅菜单位于固定顶栏的抽屉里，嵌进众妙时容易被系统导航栏压住。

独立订阅用伪服务 id `ntfy:<topic>` 参与同步：

- 游标键是 `ntfy:<topic>|ntfy`，多个主题各自推进，互不覆盖；
- 去重键是 `ntfy:<topic>#<eventID>`，不同主题不会互吞；
- 收件箱与通知副标题显示主题名，点击落到 ntfy 页面；
- 订阅列表单独存 UserDefaults（`zhongmiao.ntfy.topics.v1`），不进 `AppSettings`，
  避免设置结构演进时把整份配置解码失败重置掉。

### 已读状态同步

收件箱的已读状态默认只存在本机。服务端（自建 ntfy fork）本身支持把「已读」广播出去，
众妙据此做双向同步：

**服务端 → 本机**：轮询回来的流里可能夹着 `message_clear` 事件——那是服务端把某条消息
标记成已读的广播。事件把目标消息的 id 写在 `sequence_id` 里（动作消息自己的 `id` 是新生成的、
不能当目标）。众妙按「序列 id 或消息 id」匹配本地条目并把它标成已读，
于是别的设备上读过的消息，这边也变已读，未读角标随之一致。

**本机 → 服务端**：在众妙里把消息标为已读时，会发

```
GET <ntfy 地址>/<topic>/<id1,id2,…>/read
```

服务端把它转成一条 `message_clear` 广播，网页版和其它设备跟着变成已读；众妙自己下一轮
轮询也会收到这条回声（幂等，不会重复计数）。

约定与限制：

- 目标 id 用 `sequence_id`，没有就用消息 `id`（普通消息的 `sequence_id` 与 id 相同、被服务端省略）；
- 一次最多 50 个 id（服务端对 `[-_A-Za-z0-9]{1,64}` 逐个校验，一个不合规整条请求就被拒，
  所以不合规的 id 会在发请求前被剔除）；
- 上游 ntfy 只认单个 id 的路由，批量形态 404 时会自动降级为逐个标记；
- `/read` 需要该主题的**写权限**。服务端开了访问控制（`auth-file`）时，要到
  「设置 → ntfy 主题 → 访问令牌」填一个对该主题有写权限的令牌，否则已读状态只留在本机；
- 推送是尽力而为：本地状态先落库，推送失败只让服务端暂时落后，不会丢已读。

## 推送中继 API（`server/push-relay`）

鉴权：请求头 `X-Zhongmiao-Token: <ZM_SECRET>`（未配置密钥则不校验，启动时会告警）。

| 方法 | 路径 | 用途 |
| :-- | :-- | :-- |
| POST | `/v1/devices` | 注册设备令牌 `{token, platform, deviceName, bundle}` |
| DELETE | `/v1/devices/{token}` | 注销设备 |
| POST | `/v1/events` | 投递事件 `{service, title, body, url, priority, dedupeKey}`，重复投递返回 `duplicate: true` |
| GET | `/v1/events?service=&since=&limit=` | 补发接口，返回与「JSON 通知流」相同的结构 |
| POST | `/v1/test` | 发一条测试通知 |
| GET | `/healthz` | 设备数、事件数、APNs 是否启用 |

部署（推荐容器化，与其它应用同一 network）：

```bash
# 镜像
docker build -t zm-push ./server/push-relay
# 反代：生成配置时中继会作为 zm-push.<域名> 一起产出（不想要就 --no-relay）
python3 deploy/nginx/gen_nginx.py --domain 你的域名
```

环境变量保持一致即可；本地裸跑也可以：

```bash
cd server/push-relay
go build -o push-relay .

ZM_ADDR=:8099 \
ZM_DATA_DIR=./data \
ZM_SECRET='换成随机串' \
ZM_APNS_KEY=/path/AuthKey_ABC123.p8 \
ZM_APNS_KEY_ID=ABC123 \
ZM_APNS_TEAM_ID=TEAM123456 \
ZM_APNS_TOPIC=im.yufei.zhongmiao \
ZM_APNS_ENV=production \
./push-relay
```

事件投递示例（任何 Go 应用里几行 `http.Post` 即可）：

```bash
curl -X POST http://192.168.1.10:8099/v1/events \
  -H "X-Zhongmiao-Token: $SECRET" \
  -H "Content-Type: application/json" \
  -d '{"service":"shenshi","title":"任务到期","body":"今天有 3 个任务","url":"/tasks","priority":"time-sensitive","dedupeKey":"task-42"}'
```

App 侧在「设置 → 推送中继」填 `https://zm-push.<你的域名>` 和同一个 `ZM_SECRET`，点「重新注册推送」。
中继跑在容器里时数据卷挂到 `/data`（`ZM_DATA_DIR=/data`），事件与设备列表都在那里。

推送失败按指数退避重试 5 次（2s→60s 封顶）；`410 Gone` 会删除失效令牌。
即使推送最终失败，事件仍在 `/v1/events` 里保留 7 天，App 下次同步会补上。

## 去重与游标

**去重键**（跨进程稳定，不能用 `String.hashValue`——Swift 哈希随机化会让重启后重复弹窗）：

```
有事件 id：  <serviceID>#<eventID>
无事件 id：  <serviceID>#<unix 秒>#<FNV-1a(title + U+001F + body)>
页面 tag：   <serviceID>#web#<tag>
```

**游标**按通道独立：`shenshi|feed`、`shenshi|ntfy`、`shenshi|relay`。
游标只前进不后退，且不超过当前时间。冷启动没有游标时回看 `设置 → 冷启动回看`（默认 24 小时），
避免第一次打开就被历史消息淹没。

## 投递与补发时序

```
离线时：
  页面通知 / 拉取到的事件 → 入库（deliveredAt = nil）
  → 尝试投递：无网络或未授权 → 保留在 pendingDelivery

恢复时（任一触发）：
  NWPathMonitor 重连 / 回到前台 / 用户授权 / 手动同步 / BGAppRefreshTask
  → 按通道拉取 since=游标
  → merge 去重
  → pendingDelivery 按时间升序逐条投递
  → 标记 deliveredAt，推进游标，更新角标
```

`pendingDelivery` 先投递**旧**的，保证用户看到的顺序与服务端一致；
系统通知标识符就是事件键，所以重复投递不会产生重复条目。

## 怎么验证

1. 不配任何通道，进入任一应用，在 WebView 控制台执行：
   `new Notification("测试", {body: "来自页面的通知"})` → 应弹出系统通知，收件箱出现一条 `source = web`。
2. 授权前先触发几条，再授权 → 应一次性补发，且提示「补发 N 条历史通知」。
3. 打开飞行模式，杀进程重进，收件箱条目应显示「待补发」标签；关闭飞行模式 → 自动补发。
4. 配好 ntfy 主题，往该主题发一条消息 → 前台同步后入库；`open`/`keepalive` 不应产生条目。
5. 配好中继后 `POST /v1/test` → 设备收到推送；再 `GET /v1/events?since=...` 应能取回同一条。

## 演出提醒（本地通知 + 灵动岛）

与上面三条通道并列的第四条，但性质不同：**它不是"把服务端事件搬进收件箱"，
而是按时间主动排程**。完整设计与决策见 `SHOWS.md`，这里只记接入点。

| 环节 | 位置 |
| :-- | :-- |
| 数据源 | 幕间 `GET /api/records/upcoming`（Bearer `MJ_AUTH_TOKEN`）+ 系统日历（幕间 CalDAV） |
| 缓存 | `ShowStore` → `~/Library/Application Support/Zhongmiao/shows.json` |
| 排程 | `ShowScheduler` → `UNCalendarNotificationTrigger`，标识符 `show.<showID>` |
| 灵动岛 | `ShowIslandController`，`pushType: nil`（完全不碰 APNs） |
| 后台触发 | `StartShowIntent: LiveActivityIntent`，供快捷指令自动化调用 |

**去重启用另一套命名空间**：演出通知的标识符带 `show.` 前缀，与事件键
（`<serviceID>#<eventID>`）不会撞车，`ShowScheduler.sync` 也是靠这个前缀来回收失效排程的。

**通知上的按钮**：`UNNotificationCategory` 为 `im.yufei.zhongmiao.show`，
两个 action 都带 `.foreground`——不带的话系统在后台直接吞掉，开岛代码根本不会执行。
`NotificationDelegate.didReceive` 先判断 `userInfo["showID"]`，命中就走演出分支，
否则按老规矩当作服务通知处理。

**与灵动岛的分工**：通知是保底（App 被杀也到点），岛是增强（最多常驻 8 小时、何时开由触发点决定）。
两者可以取不同的提前量，默认通知 4 小时、岛 8 小时。
