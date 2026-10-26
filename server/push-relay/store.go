package main

import (
	"encoding/json"
	"errors"
	"log"
	"os"
	"path/filepath"
	"sort"
	"sync"
	"time"
)

// Event 是众妙各应用投递的一条通知事件。
type Event struct {
	ID        string    `json:"id"`
	Service   string    `json:"service"`
	Title     string    `json:"title"`
	Body      string    `json:"body"`
	URL       string    `json:"url,omitempty"`
	Priority  string    `json:"priority,omitempty"`
	CreatedAt time.Time `json:"createdAt"`
	DedupeKey string    `json:"dedupeKey,omitempty"`
}

// Key 用于去重：优先 dedupeKey，其次 id，最后内容指纹。
func (e Event) Key() string {
	if e.DedupeKey != "" {
		return e.Service + "|" + e.DedupeKey
	}
	if e.ID != "" {
		return e.Service + "|id:" + e.ID
	}
	return e.Service + "|" + e.CreatedAt.UTC().Format(time.RFC3339Nano) + "|" + e.Title
}

type Device struct {
	Token     string    `json:"token"`
	Platform  string    `json:"platform"`
	Name      string    `json:"deviceName"`
	Bundle    string    `json:"bundle"`
	UpdatedAt time.Time `json:"updatedAt"`
}

type persisted struct {
	Devices map[string]Device    `json:"devices"`
	Events  []Event              `json:"events"`
	Dedupe  map[string]time.Time `json:"dedupe"`
}

// Store 是进程内的持久化存储：JSON 落盘，简单可审计。
// 事件量级很小（个人自托管），不需要引入数据库。
type Store struct {
	mu   sync.Mutex
	path string
	data persisted
}

const (
	maxEvents     = 2000
	dedupeTTL     = 7 * 24 * time.Hour
	saveMinGap    = 200 * time.Millisecond
	eventPageSize = 100
)

func NewStore(dir string) (*Store, error) {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, err
	}
	s := &Store{
		path: filepath.Join(dir, "relay.json"),
		data: persisted{
			Devices: map[string]Device{},
			Events:  []Event{},
			Dedupe:  map[string]time.Time{},
		},
	}
	raw, err := os.ReadFile(s.path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return s, nil
		}
		return nil, err
	}
	if err := json.Unmarshal(raw, &s.data); err != nil {
		// 损坏时留档，不静默丢数据。
		backup := s.path + ".corrupt-" + time.Now().Format("20060102-150405")
		_ = os.Rename(s.path, backup)
		log.Printf("store: 解析失败，已备份到 %s", backup)
		s.data = persisted{Devices: map[string]Device{}, Events: []Event{}, Dedupe: map[string]time.Time{}}
	}
	if s.data.Devices == nil {
		s.data.Devices = map[string]Device{}
	}
	if s.data.Dedupe == nil {
		s.data.Dedupe = map[string]time.Time{}
	}
	return s, nil
}

func (s *Store) saveLocked() {
	raw, err := json.MarshalIndent(s.data, "", "  ")
	if err != nil {
		log.Printf("store: 编码失败: %v", err)
		return
	}
	tmp := s.path + ".tmp"
	if err := os.WriteFile(tmp, raw, 0o600); err != nil {
		log.Printf("store: 写入失败: %v", err)
		return
	}
	if err := os.Rename(tmp, s.path); err != nil {
		log.Printf("store: 替换失败: %v", err)
	}
}

func (s *Store) UpsertDevice(d Device) {
	s.mu.Lock()
	defer s.mu.Unlock()
	d.UpdatedAt = time.Now().UTC()
	s.data.Devices[d.Token] = d
	s.saveLocked()
}

func (s *Store) RemoveDevice(token string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.data.Devices, token)
	s.saveLocked()
}

func (s *Store) Devices() []Device {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := make([]Device, 0, len(s.data.Devices))
	for _, d := range s.data.Devices {
		out = append(out, d)
	}
	return out
}

// AddEvent 入库；若命中去重键则返回 false。
func (s *Store) AddEvent(e Event) bool {
	s.mu.Lock()
	defer s.mu.Unlock()

	now := time.Now().UTC()
	s.pruneLocked(now)

	key := e.Key()
	if seenAt, ok := s.data.Dedupe[key]; ok && now.Sub(seenAt) < dedupeTTL {
		return false
	}
	s.data.Dedupe[key] = now
	s.data.Events = append(s.data.Events, e)
	if len(s.data.Events) > maxEvents {
		s.data.Events = s.data.Events[len(s.data.Events)-maxEvents:]
	}
	s.saveLocked()
	return true
}

func (s *Store) pruneLocked(now time.Time) {
	for key, at := range s.data.Dedupe {
		if now.Sub(at) > dedupeTTL {
			delete(s.data.Dedupe, key)
		}
	}
}

// Events 返回某服务在 since 之后的事件（按时间升序），最多 limit 条。
func (s *Store) Events(service string, since time.Time, limit int) []Event {
	s.mu.Lock()
	defer s.mu.Unlock()

	if limit <= 0 || limit > eventPageSize {
		limit = eventPageSize
	}
	matched := make([]Event, 0, 16)
	for _, e := range s.data.Events {
		if service != "" && e.Service != service {
			continue
		}
		if !since.IsZero() && !e.CreatedAt.After(since) {
			continue
		}
		matched = append(matched, e)
	}
	sort.Slice(matched, func(i, j int) bool { return matched[i].CreatedAt.Before(matched[j].CreatedAt) })
	if len(matched) > limit {
		matched = matched[:limit]
	}
	return matched
}

func (s *Store) Counts() (devices, events int) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return len(s.data.Devices), len(s.data.Events)
}
