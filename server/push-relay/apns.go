package main

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"
)

// APNs 使用 token（.p8）认证：JWT 用 ES256 签名，有效期最长 1 小时。
type APNsClient struct {
	keyID  string
	teamID string
	topic  string
	env    string
	key    *ecdsa.PrivateKey

	mu          sync.Mutex
	cachedToken string
	expiresAt   time.Time

	client *http.Client
}

func NewAPNsClient(keyPath, keyID, teamID, topic, env string) (*APNsClient, error) {
	raw, err := os.ReadFile(keyPath)
	if err != nil {
		return nil, fmt.Errorf("读取 .p8 失败: %w", err)
	}
	key, err := parseP8(raw)
	if err != nil {
		return nil, err
	}
	if env == "" {
		env = "production"
	}
	return &APNsClient{
		keyID:  keyID,
		teamID: teamID,
		topic:  topic,
		env:    env,
		key:    key,
		client: &http.Client{Timeout: 20 * time.Second},
	}, nil
}

func parseP8(raw []byte) (*ecdsa.PrivateKey, error) {
	block, _ := pem.Decode(raw)
	if block == nil {
		return nil, errors.New(".p8 不是合法的 PEM 文件")
	}
	if key, err := x509.ParsePKCS8PrivateKey(block.Bytes); err == nil {
		if ec, ok := key.(*ecdsa.PrivateKey); ok {
			return ec, nil
		}
		return nil, errors.New(".p8 不是 EC 私钥")
	}
	if key, err := x509.ParseECPrivateKey(block.Bytes); err == nil {
		return key, nil
	}
	return nil, errors.New(".p8 解析失败")
}

func (c *APNsClient) authorizationToken() (string, error) {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.cachedToken != "" && time.Now().Before(c.expiresAt) {
		return c.cachedToken, nil
	}

	header := base64.RawURLEncoding.EncodeToString([]byte(fmt.Sprintf(`{"alg":"ES256","kid":"%s"}`, c.keyID)))
	claims := base64.RawURLEncoding.EncodeToString([]byte(fmt.Sprintf(`{"iss":"%s","iat":%d}`, c.teamID, time.Now().Unix())))
	signingInput := header + "." + claims

	digest := sha256.Sum256([]byte(signingInput))
	r, s, err := ecdsa.Sign(rand.Reader, c.key, digest[:])
	if err != nil {
		return "", err
	}
	// JWT 的 ES256 签名是 R||S 各 32 字节，不是 ASN.1。
	sig := make([]byte, 64)
	r.FillBytes(sig[:32])
	s.FillBytes(sig[32:])

	c.cachedToken = signingInput + "." + base64.RawURLEncoding.EncodeToString(sig)
	c.expiresAt = time.Now().Add(50 * time.Minute)
	return c.cachedToken, nil
}

type pushOutcome struct {
	unregistered bool
	retryable    bool
	err          error
}

func (c *APNsClient) Push(ctx context.Context, token string, e Event) pushOutcome {
	jwt, err := c.authorizationToken()
	if err != nil {
		return pushOutcome{retryable: true, err: err}
	}

	interruption := "active"
	priority := "5"
	switch strings.ToLower(e.Priority) {
	case "passive":
		interruption = "passive"
		priority = "5"
	case "time-sensitive", "timesensitive", "urgent", "high":
		interruption = "time-sensitive"
		priority = "10"
	}

	payload := map[string]any{
		"aps": map[string]any{
			"alert":              map[string]string{"title": e.Title, "body": e.Body},
			"sound":              "default",
			"thread-id":          e.Service,
			"interruption-level": interruption,
			"mutable-content":    0,
		},
		"service": e.Service,
		"url":     e.URL,
		"eventID": e.ID,
	}
	body, err := json.Marshal(payload)
	if err != nil {
		return pushOutcome{err: err}
	}

	host := "https://api.push.apple.com"
	if c.env == "sandbox" {
		host = "https://api.sandbox.push.apple.com"
	}
	url := fmt.Sprintf("%s/3/device/%s", host, token)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return pushOutcome{err: err}
	}
	req.Header.Set("authorization", "bearer "+jwt)
	req.Header.Set("apns-topic", c.topic)
	req.Header.Set("apns-push-type", "alert")
	req.Header.Set("apns-priority", priority)
	req.Header.Set("content-type", "application/json")

	resp, err := c.client.Do(req)
	if err != nil {
		return pushOutcome{retryable: true, err: err}
	}
	defer resp.Body.Close()

	raw, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
	if resp.StatusCode == http.StatusOK {
		return pushOutcome{}
	}
	if resp.StatusCode == http.StatusGone {
		// 410: 设备令牌失效，应删除。
		return pushOutcome{unregistered: true, err: fmt.Errorf("token 已失效")}
	}
	if resp.StatusCode == http.StatusTooManyRequests || resp.StatusCode >= 500 {
		return pushOutcome{retryable: true, err: fmt.Errorf("APNs %d: %s", resp.StatusCode, strings.TrimSpace(string(raw)))}
	}
	return pushOutcome{err: fmt.Errorf("APNs %d: %s", resp.StatusCode, strings.TrimSpace(string(raw)))}
}
