# 部署：Docker + Nginx + HTTPS

你的所有应用都跑在 Docker 里、外面套 Nginx + HTTPS，这个前提解决了众妙最怕的两件事：

- **Service Worker 能注册**（需要安全上下文）→ 各应用自带的离线缓存真的生效；
- **地址有稳定语义**（子域名）→ 不用把内部 8080 端口写进客户端。

所以 App 里只需要配一个「基础域名」，剩下的由这份目录里的脚本生成。

## 一、把注册表变成 Nginx 配置

服务清单的唯一事实来源是 Swift 里的 `ServiceCatalog`，不要两头手写。

```bash
cd ~/Git/zhongmiao

# 1) 导出注册表（改了注册表就重跑这一步）
swift run --package-path Packages/ZhongmiaoCore zm-catalog > deploy/catalog.json

# 2) 生成 Nginx 配置
python3 deploy/nginx/gen_nginx.py --domain example.com      # 换成你的域名

# 3) 校验 + 重载（先测再 reload，别直接重启）
docker exec nginx nginx -t && docker exec nginx nginx -s reload
```

产物：`deploy/nginx/zhongmiao.conf`，包含 14 个服务的「HTTP→HTTPS 跳转 + HTTPS 反代」以及一段可选的中继配置。

## 二、Nginx 在哪，决定用哪种模式

| Nginx 位置 | 用哪个模式 | upstream 指向 |
| :-- | :-- | :-- |
| Docker 里，与应用同一 network | `--mode docker`（默认） | `容器名:内部端口`，如 `shenshi:8787` |
| 宿主机直接装 | `--mode host` | `127.0.0.1:内部端口` |

```bash
# 宿主机 nginx
python3 deploy/nginx/gen_nginx.py --domain example.com --mode host
```

**为什么不用宿主机映射端口**：`mujian / liuxia / huozhi / chaxin / qiansi` 容器内部都是 8080，
宿主机不可能把它们都映射到 8080。走容器名 + 内部端口就没有这个冲突。

容器名取自各仓库 compose 的 `container_name`，缺失时用 compose 服务名或 id。
`diarum / yuexi / whoami` 仓库里没有 compose 文件，容器名按 id 假定——如果你起名不同，
改 `ServiceCatalog` 里的 `container:` 再重跑脚本即可。

## 三、证书

配置里默认读这两个路径，按你的实际证书改 `--cert` / `--key`：

```
/etc/nginx/certs/fullchain.pem
/etc/nginx/certs/privkey.pem
```

14 个服务对应 14 个子域名，建议直接用**通配符证书**（`*.example.com`）：

```bash
# acme.sh + DNS API（无需 80 端口验证，适合内网）
acme.sh --issue --dns dns_ali -d example.com -d '*.example.com'
```

用 certbot 逐个签也可以，只是要 14 次验证，续期容易漏。

## 四、中继（可选，但推荐）

没有它也能用：页面内通知、ntfy、通知流轮询都不依赖服务器。
它的价值是「App 被杀掉时也能立刻收到」，以及在 `/v1/events` 里保留 7 天供补发。

```yaml
# 追加到你的 compose
services:
  zm-push:
    build: ./zhongmiao/server/push-relay
    container_name: zm-push
    restart: unless-stopped
    environment:
      ZM_ADDR: ":8099"
      ZM_DATA_DIR: /data
      ZM_SECRET: ${ZM_SECRET:?至少 32 位随机串}
      ZM_APNS_KEY: /run/secrets/apns.p8
      ZM_APNS_KEY_ID: ${ZM_APNS_KEY_ID}
      ZM_APNS_TEAM_ID: ${ZM_APNS_TEAM_ID}
      ZM_APNS_TOPIC: im.yufei.zhongmiao
      ZM_APNS_ENV: production
    volumes:
      - zm-push-data:/data                     # 命名卷：容器以 uid 10001 运行，宿主目录要先 chown
      - ./secrets/apns.p8:/run/secrets/apns.p8:ro
    networks: [default]

volumes:
  zm-push-data:
```

生成配置时中继的 server 块默认按 `zm-push:8099` 反代到 `zm-push.example.com`；
不打算用就加 `--no-relay`，或在 App 里把「推送中继」留空。

镜像约 14 MB，构建期不跑 `apk`（CA 证书由基础镜像自带），内网也能构建：

```bash
docker build -t zm-push ./server/push-relay
docker run -d --name zm-push -v zm-push-data:/data -e ZM_SECRET=... zm-push
```

如果坚持挂宿主机目录，记得先 `sudo chown -R 10001:10001 ./data/zm-push`，否则会因权限写不进 `relay.json`。

然后在 App 的「设置 → 推送中继」填 `https://zm-push.example.com` 和同一个 `ZM_SECRET`。

## 五、验证

```bash
# 配置语法
docker exec nginx nginx -t

# 逐个域名探活（HTTP 应 301，HTTPS 应 200/302/401）
for h in shenshi mujian bili liuxia tuqie huozhi diarum qingye chaxin qiansi yuexi ntfy qbhive whoami; do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 6 "https://$h.example.com/")
  echo "$h.example.com -> $code"
done
```

也可以直接在 App 的「设置 → 诊断」页点「全部检测」，它会对每个服务发一次 GET，
并把失败原因分成「解析失败 / 连接失败 / 证书 / ATS 拦截」四类——比看 Nginx 日志快。

## 六、常见坑

| 现象 | 原因 | 处理 |
| :-- | :-- | :-- |
| 改了 compose 后 502 | 容器重建后 IP 变了，Nginx 缓存了旧解析 | `docker exec nginx nginx -s reload` |
| 某个应用 404 / 白屏 | 用了子路径反代，但 SPA 把资源写成根绝对路径 | 改用子域名模式 |
| 上传图片 413 | 请求体超过 `client_max_body_size` | 配置里已设 64m，仍不够就改大 |
| 实时功能不工作 | 少了 WebSocket 升级头 | 已配 `Upgrade` + `map $connection_upgrade` |
| ntfy 流式响应被截断 | 代理缓冲 | 已对 ntfy 关掉 `proxy_buffering` |
| 改了配置但页面还是旧的 | Service Worker 命中旧缓存 | App 内下拉刷新 / 「强制刷新」，或清站点数据 |
| 证书告警 | 自签或链不全 | 用完整链 `fullchain.pem`，别只给域名证书 |

## 七、新增一个服务

```bash
# 1) 改 Packages/ZhongmiaoCore/Sources/ZhongmiaoCore/ServiceCatalog.swift
# 2) 导出 + 生成 + 校验
swift run --package-path Packages/ZhongmiaoCore zm-catalog > deploy/catalog.json
python3 deploy/nginx/gen_nginx.py --domain example.com
docker exec nginx nginx -t && docker exec nginx nginx -s reload
# 3) App 里「设置 → 诊断 → 全部检测」确认可达
```

`gen_nginx.py --check` 会先查子域名冲突，冲突时直接报错退出，不会写出半份配置。
