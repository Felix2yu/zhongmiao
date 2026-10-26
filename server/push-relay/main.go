package main

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"math"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"
)

type Config struct {
	Addr      string
	DataDir   string
	Secret    string
	APNsKey   string
	APNsKeyID string
	APNsTeam  string
	APNsTopic string
	APNsEnv   string
}

func loadConfig() Config {
	cfg := Config{
		Addr:      envOr("ZM_ADDR", ":8099"),
		DataDir:   envOr("ZM_DATA_DIR", "./data"),
		Secret:    os.Getenv("ZM_SECRET"),
		APNsKey:   os.Getenv("ZM_APNS_KEY"),
		APNsKeyID: os.Getenv("ZM_APNS_KEY_ID"),
		APNsTeam:  os.Getenv("ZM_APNS_TEAM_ID"),
		APNsTopic: os.Getenv("ZM_APNS_TOPIC"),
		APNsEnv:   envOr("ZM_APNS_ENV", "production"),
	}
	return cfg
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

type Server struct {
	store  *Store
	apns   *APNsClient
	secret string
}

func main() {
	cfg := loadConfig()
	store, err := NewStore(cfg.DataDir)
	if err != nil {
		log.Fatalf("初始化存储失败: %v", err)
	}

	var apns *APNsClient
	if cfg.APNsKey != "" && cfg.APNsKeyID != "" && cfg.APNsTeam != "" && cfg.APNsTopic != "" {
		apns, err = NewAPNsClient(cfg.APNsKey, cfg.APNsKeyID, cfg.APNsTeam, cfg.APNsTopic, cfg.APNsEnv)
		if err != nil {
			log.Fatalf("初始化 APNs 失败: %v", err)
		}
		log.Printf("APNs 已启用：env=%s topic=%s", cfg.APNsEnv, cfg.APNsTopic)
	} else {
		log.Printf("未配置 APNs 凭据，仅提供设备注册与事件补发接口")
	}
	if cfg.Secret == "" {
		log.Printf("警告：未设置 ZM_SECRET，任何能访问该端口的程序都可以投递通知")
	}

	srv := &Server{store: store, apns: apns, secret: cfg.Secret}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", srv.handleHealth)

	mux.Handle("POST /v1/devices", srv.auth(http.HandlerFunc(srv.handleRegisterDevice)))
	mux.Handle("DELETE /v1/devices/{token}", srv.auth(http.HandlerFunc(srv.handleDeleteDevice)))
	mux.Handle("POST /v1/events", srv.auth(http.HandlerFunc(srv.handleCreateEvent)))
	mux.Handle("GET /v1/events", srv.auth(http.HandlerFunc(srv.handleListEvents)))
	mux.Handle("POST /v1/test", srv.auth(http.HandlerFunc(srv.handleTest)))

	httpServer := &http.Server{
		Addr:              cfg.Addr,
		Handler:           logRequests(mux),
		ReadHeaderTimeout: 10 * time.Second,
	}

	go func() {
		devices, events := store.Counts()
		log.Printf("众妙推送中继已启动 %s（设备 %d / 事件 %d）", cfg.Addr, devices, events)
		if err := httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("服务异常退出: %v", err)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop

	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()
	if err := httpServer.Shutdown(ctx); err != nil {
		log.Printf("关闭失败: %v", err)
	}
	log.Printf("已停止")
}

// MARK: - 中间件

func (s *Server) auth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if s.secret != "" {
			provided := r.Header.Get("X-Zhongmiao-Token")
			if subtle.ConstantTimeCompare([]byte(provided), []byte(s.secret)) != 1 {
				writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "无效的共享密钥"})
				return
			}
		}
		next.ServeHTTP(w, r)
	})
}

func logRequests(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		log.Printf("%s %s %s", r.Method, r.URL.Path, time.Since(start).Round(time.Millisecond))
	})
}

// MARK: - 设备

type registerRequest struct {
	Token      string `json:"token"`
	Platform   string `json:"platform"`
	DeviceName string `json:"deviceName"`
	Bundle     string `json:"bundle"`
}

func (s *Server) handleRegisterDevice(w http.ResponseWriter, r *http.Request) {
	var req registerRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8<<10)).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "请求体不是合法 JSON"})
		return
	}
	req.Token = strings.ToLower(strings.TrimSpace(req.Token))
	if len(req.Token) < 32 || len(req.Token) > 200 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "设备令牌长度异常"})
		return
	}
	if req.Platform == "" {
		req.Platform = "ios"
	}

	s.store.UpsertDevice(Device{
		Token:    req.Token,
		Platform: req.Platform,
		Name:     req.DeviceName,
		Bundle:   req.Bundle,
	})
	devices, _ := s.store.Counts()
	log.Printf("设备已注册：%s (%s)，共 %d 台", req.DeviceName, req.Platform, devices)
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "devices": devices})
}

func (s *Server) handleDeleteDevice(w http.ResponseWriter, r *http.Request) {
	token := strings.ToLower(strings.TrimSpace(r.PathValue("token")))
	if token == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "缺少令牌"})
		return
	}
	s.store.RemoveDevice(token)
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

// MARK: - 事件

func (s *Server) handleCreateEvent(w http.ResponseWriter, r *http.Request) {
	var e Event
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64<<10)).Decode(&e); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "请求体不是合法 JSON"})
		return
	}
	e.Service = strings.TrimSpace(e.Service)
	e.Title = strings.TrimSpace(e.Title)
	if e.Service == "" || e.Title == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "service 与 title 必填"})
		return
	}
	if e.CreatedAt.IsZero() {
		e.CreatedAt = time.Now().UTC()
	}
	if e.ID == "" {
		e.ID = fmt.Sprintf("evt_%d", time.Now().UnixNano())
	}

	if !s.store.AddEvent(e) {
		// 幂等：重复事件直接返回成功，客户端不必特殊处理。
		writeJSON(w, http.StatusOK, map[string]any{"ok": true, "duplicate": true, "id": e.ID})
		return
	}

	go s.fanout(e)
	writeJSON(w, http.StatusAccepted, map[string]any{"ok": true, "id": e.ID})
}

// fanout 向所有设备推送；失败按指数退避重试，最终由客户端轮询 /v1/events 补齐。
func (s *Server) fanout(e Event) {
	if s.apns == nil {
		return
	}
	for _, device := range s.store.Devices() {
		go s.pushWithRetry(device, e, 1)
	}
}

func (s *Server) pushWithRetry(device Device, e Event, attempt int) {
	ctx, cancel := context.WithTimeout(context.Background(), 25*time.Second)
	defer cancel()

	outcome := s.apns.Push(ctx, device.Token, e)
	if outcome.unregistered {
		log.Printf("令牌失效，移除设备：%s", device.Name)
		s.store.RemoveDevice(device.Token)
		return
	}
	if outcome.err == nil {
		return
	}
	log.Printf("推送失败（第 %d 次）：%s → %v", attempt, device.Name, outcome.err)
	if !outcome.retryable || attempt >= 5 {
		return
	}
	delay := time.Duration(math.Min(math.Pow(2, float64(attempt)), 60)) * time.Second
	time.AfterFunc(delay, func() {
		s.pushWithRetry(device, e, attempt+1)
	})
}

type feedItem struct {
	ID        string `json:"id"`
	Title     string `json:"title"`
	Body      string `json:"body,omitempty"`
	CreatedAt string `json:"createdAt"`
	URL       string `json:"url,omitempty"`
	Priority  string `json:"priority,omitempty"`
}

type feedPage struct {
	Items      []feedItem `json:"items"`
	NextCursor string     `json:"nextCursor,omitempty"`
}

// handleListEvents 是"重连后补发"的服务端半边：App 带 since 轮询即可拿到离线期间的事件。
func (s *Server) handleListEvents(w http.ResponseWriter, r *http.Request) {
	service := r.URL.Query().Get("service")
	since := parseSince(r.URL.Query().Get("since"))
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))

	events := s.store.Events(service, since, limit)
	items := make([]feedItem, 0, len(events))
	for _, e := range events {
		items = append(items, feedItem{
			ID:        e.ID,
			Title:     e.Title,
			Body:      e.Body,
			CreatedAt: e.CreatedAt.UTC().Format(time.RFC3339Nano),
			URL:       e.URL,
			Priority:  e.Priority,
		})
	}

	page := feedPage{Items: items}
	if len(items) > 0 {
		page.NextCursor = items[len(items)-1].CreatedAt
	} else if !since.IsZero() {
		page.NextCursor = since.UTC().Format(time.RFC3339Nano)
	}
	writeJSON(w, http.StatusOK, page)
}

func parseSince(raw string) time.Time {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return time.Time{}
	}
	if t, err := time.Parse(time.RFC3339Nano, raw); err == nil {
		return t
	}
	if t, err := time.Parse(time.RFC3339, raw); err == nil {
		return t
	}
	if seconds, err := strconv.ParseInt(raw, 10, 64); err == nil {
		return time.Unix(seconds, 0).UTC()
	}
	return time.Time{}
}

func (s *Server) handleTest(w http.ResponseWriter, r *http.Request) {
	e := Event{
		Service:   "zhongmiao",
		Title:     "中继连通正常",
		Body:      "这是一条来自推送中继的测试通知。",
		Priority:  "active",
		CreatedAt: time.Now().UTC(),
		ID:        fmt.Sprintf("test_%d", time.Now().UnixNano()),
	}
	s.store.AddEvent(e)
	go s.fanout(e)
	writeJSON(w, http.StatusAccepted, map[string]any{"ok": true, "event": e})
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	devices, events := s.store.Counts()
	writeJSON(w, http.StatusOK, map[string]any{
		"ok":      true,
		"devices": devices,
		"events":  events,
		"apns":    s.apns != nil,
		"time":    time.Now().UTC().Format(time.RFC3339),
	})
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(payload); err != nil {
		log.Printf("写响应失败: %v", err)
	}
}
