#!/usr/bin/env python3
"""从众妙的服务注册表生成 Nginx 反代配置。

单一事实来源：`deploy/catalog.json`（由 `swift run zm-catalog` 从 Swift 注册表导出）。
这样应用里看到的地址与服务器上的反代永远一致，不会出现「加了服务忘了改 Nginx」。

典型用法：

    # 1) 导出注册表（服务变化后重跑）
    swift run --package-path Packages/ZhongmiaoCore zm-catalog > deploy/catalog.json

    # 2) 生成配置（Docker 网络内，按容器名反代）
    python3 deploy/nginx/gen_nginx.py --domain example.com

    # 3) 校验并重载
    docker exec nginx nginx -t && docker exec nginx nginx -s reload

局域网排障（不经过 Docker DNS）：
    python3 deploy/nginx/gen_nginx.py --domain example.com --mode host
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

DEFAULT_CATALOG = Path(__file__).resolve().parent.parent / "catalog.json"
DEFAULT_OUT = Path(__file__).resolve().parent / "zhongmiao.conf"

PROXY_HEADERS = """\
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-Port $server_port;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $connection_upgrade;"""

TLS_BLOCK = """\
    ssl_certificate     {cert};
    ssl_certificate_key {key};
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_cache shared:zm_tls:10m;
    ssl_session_timeout 1d;"""


def load_catalog(path: Path) -> list[dict]:
    if not path.exists():
        sys.exit(
            f"找不到 {path}。先运行：\n"
            f"  swift run --package-path Packages/ZhongmiaoCore zm-catalog > {path}"
        )
    with path.open(encoding="utf-8") as handle:
        data = json.load(handle)
    if not isinstance(data, list) or not data:
        sys.exit(f"{path} 内容不是非空数组")
    return data


def upstream_for(service: dict, mode: str) -> str:
    if mode == "docker":
        return f"{service['container']}:{service['port']}"
    return f"127.0.0.1:{service['port']}"


def render_service(service: dict, domain: str, mode: str, cert: str, key: str) -> str:
    host = f"{service['subdomain']}.{domain}"
    upstream = f"zm_{service['id'].replace('-', '_')}"
    target = upstream_for(service, mode)

    offline_mark = "支持离线" if service.get("offline") else "无离线缓存"
    lines = [
        f"# ── {service['name']} {service['id']}"
        f"（{target}，{offline_mark}） ──",
        f"upstream {upstream} {{",
        f"    server {target};",
        "}",
        "",
        "server {",
        "    listen 80;",
        "    listen [::]:80;",
        f"    server_name {host};",
        "    return 301 https://$host$request_uri;",
        "}",
        "",
        "server {",
        "    listen 443 ssl;",
        "    listen [::]:443 ssl;",
        "    http2 on;   # nginx < 1.25.1 改成 listen 443 ssl http2;",
        f"    server_name {host};",
        "",
        TLS_BLOCK.format(cert=cert, key=key),
        "",
        f"    client_max_body_size {service.get('max_body', '64m')};",
        PROXY_HEADERS,
    ]

    # 用字典拼装，保证同一指令只出现一次（nginx 对重复指令直接报错）。
    settings: dict[str, str] = {
        "proxy_read_timeout": "3600s" if service["id"] == "ntfy" else "300s",
        "proxy_send_timeout": "300s",
        "proxy_request_buffering": "off",
    }
    if service["id"] == "ntfy":
        # ntfy 有长连接（SSE / WebSocket）场景，关掉缓冲与缓存。
        settings["proxy_buffering"] = "off"
        settings["proxy_cache"] = "off"

    for directive, value in settings.items():
        lines.append(f"    {directive} {value};")

    lines += [
        "",
        "    location / {",
        f"        proxy_pass http://{upstream};",
        "    }",
        "}",
        "",
    ]
    return "\n".join(lines)


def render_relay(domain: str, upstream: str, cert: str, key: str) -> str:
    host = f"zm-push.{domain}"
    return "\n".join(
        [
            f"# ── 推送中继 push-relay（{upstream}） ──",
            "# 仅当启用了 server/push-relay 时保留；不启用可整段删除。",
            "server {",
            "    listen 80;",
            "    listen [::]:80;",
            f"    server_name {host};",
            "    return 301 https://$host$request_uri;",
            "}",
            "",
            "server {",
            "    listen 443 ssl;",
            "    listen [::]:443 ssl;",
            "    http2 on;",
            f"    server_name {host};",
            "",
            TLS_BLOCK.format(cert=cert, key=key),
            "",
            "    client_max_body_size 1m;",
            PROXY_HEADERS,
            "    proxy_read_timeout 60s;",
            "",
            "    location / {",
            f"        proxy_pass http://{upstream};",
            "    }",
            "}",
            "",
        ]
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="从服务注册表生成 Nginx 反代配置")
    parser.add_argument("--domain", required=True, help="基础域名，例如 example.com")
    parser.add_argument("--catalog", type=Path, default=DEFAULT_CATALOG)
    parser.add_argument(
        "--mode",
        choices=["docker", "host"],
        default="docker",
        help="docker：按容器名反代（默认）；host：反代到宿主机 127.0.0.1:<内部端口>",
    )
    parser.add_argument("--cert", default="/etc/nginx/certs/fullchain.pem")
    parser.add_argument("--key", default="/etc/nginx/certs/privkey.pem")
    parser.add_argument("--relay-upstream", default=None, help="默认随 --mode：zm-push:8099 / 127.0.0.1:8099")
    parser.add_argument("--no-relay", action="store_true", help="不生成推送中继的 server 块")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help="输出文件，- 表示 stdout")
    parser.add_argument("--check", action="store_true", help="只做一致性检查，不写文件")
    args = parser.parse_args()

    services = load_catalog(args.catalog)
    domain = args.domain.strip().strip(".")

    seen_hosts: dict[str, str] = {}
    missing_port = [s["id"] for s in services if not s.get("port")]
    for service in services:
        host = f"{service['subdomain']}.{domain}"
        if host in seen_hosts:
            sys.exit(f"子域名冲突：{host} 同时属于 {seen_hosts[host]} 与 {service['id']}")
        seen_hosts[host] = service["id"]

    if args.check:
        print(f"服务 {len(services)} 个，子域名 {len(seen_hosts)} 个，无冲突。")
        if missing_port:
            print(f"缺少内部端口（会被跳过）：{', '.join(missing_port)}")
        return 0

    relay_upstream = args.relay_upstream or (
        "zm-push:8099" if args.mode == "docker" else "127.0.0.1:8099"
    )

    chunks = [
        "# 由 deploy/nginx/gen_nginx.py 自动生成，请勿手改。",
        f"# 生成时间：{time.strftime('%Y-%m-%d %H:%M:%S')}",
        f"# 基础域名：{domain} · 模式：{args.mode} · 服务：{len(services)}",
        "#",
        "# 改完记得：docker exec nginx nginx -t && docker exec nginx nginx -s reload",
        "",
        "map $http_upgrade $connection_upgrade {",
        "    default upgrade;",
        "    ''      close;",
        "}",
        "",
    ]

    skipped = []
    for service in services:
        if not service.get("port"):
            skipped.append(service["id"])
            continue
        chunks.append(render_service(service, domain, args.mode, args.cert, args.key))

    if not args.no_relay:
        chunks.append(render_relay(domain, relay_upstream, args.cert, args.key))

    if skipped:
        chunks.append(f"# 以下服务缺少内部端口，未生成（补 Dockerfile EXPOSE 后重跑）：{', '.join(skipped)}")
        chunks.append("")

    output = "\n".join(chunks)

    if str(args.out) == "-":
        sys.stdout.write(output)
    else:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(output, encoding="utf-8")
        print(f"已写入 {args.out}（{len(output.splitlines())} 行）")
        if skipped:
            print(f"跳过（缺端口）：{', '.join(skipped)}")
        print("下一步：docker exec nginx nginx -t && docker exec nginx nginx -s reload")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
