# 多阶段构建：静态二进制 + 最小运行镜像
FROM golang:1.22-alpine AS build

WORKDIR /src
COPY go.mod ./
COPY *.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/push-relay .

FROM alpine:3.20

# 刻意不跑 apk：alpine 基础镜像自带 CA 证书（APNs 走 TLS 必需），
# adduser 是 busybox 内置命令。这样构建期不依赖外网包源，内网/受限网络也能构建。
RUN adduser -D -u 10001 -h /data zhongmiao \
    && mkdir -p /data \
    && chown -R 10001:10001 /data

COPY --from=build /out/push-relay /usr/local/bin/push-relay

ENV ZM_ADDR=:8099 \
    ZM_DATA_DIR=/data

WORKDIR /data
USER zhongmiao
EXPOSE 8099

ENTRYPOINT ["/usr/local/bin/push-relay"]
