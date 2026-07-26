package main

import (
	"runtime"
	"sort"
	"sync"
	"time"

	"github.com/shirou/gopsutil/v4/cpu"
	"github.com/shirou/gopsutil/v4/disk"
	"github.com/shirou/gopsutil/v4/host"
	"github.com/shirou/gopsutil/v4/load"
	"github.com/shirou/gopsutil/v4/mem"
	psnet "github.com/shirou/gopsutil/v4/net"
	"github.com/shirou/gopsutil/v4/process"
)

const (
	// fastInterval drives cheap metrics: CPU, memory, disk usage, network rates.
	fastInterval = 2 * time.Second
	// slowInterval drives connection and process enumeration, which walk the
	// whole socket/process table and get expensive on busy servers.
	slowInterval = 10 * time.Second
	// historyInterval is the sampling resolution served by /v1/history.
	historyInterval = 30 * time.Second
)

// Meta describes the host itself; it never changes while the agent runs.
type Meta struct {
	Hostname               string `json:"hostname"`
	OS                     string `json:"os"`
	Kernel                 string `json:"kernel"`
	Architecture           string `json:"architecture"`
	CPUModel               string `json:"cpu_model"`
	CPUCores               int    `json:"cpu_cores"`
	AgentVersion           string `json:"agent_version"`
	CollectIntervalSeconds int    `json:"collect_interval_seconds"`
}

type Memory struct {
	Used  uint64 `json:"used"`
	Total uint64 `json:"total"`
}

type Network struct {
	Up        float64 `json:"up"`
	Down      float64 `json:"down"`
	TotalUp   uint64  `json:"total_up"`
	TotalDown uint64  `json:"total_down"`
}

type Connections struct {
	TCP int `json:"tcp"`
	UDP int `json:"udp"`
}

type Load struct {
	Load1  float64 `json:"load1"`
	Load5  float64 `json:"load5"`
	Load15 float64 `json:"load15"`
}

type Metrics struct {
	Timestamp    int64       `json:"timestamp"`
	CPUUsage     float64     `json:"cpu_usage"`
	Memory       Memory      `json:"memory"`
	Swap         Memory      `json:"swap"`
	Disk         Memory      `json:"disk"`
	Network      Network     `json:"network"`
	Connections  Connections `json:"connections"`
	ProcessCount int         `json:"process_count"`
	Load         Load        `json:"load"`
	Uptime       uint64      `json:"uptime"`
}

type Snapshot struct {
	Timestamp int64   `json:"timestamp"`
	Metrics   Metrics `json:"metrics"`
}

type collector struct {
	meta           Meta
	historyMinutes int

	mu      sync.RWMutex
	latest  Metrics
	history []Snapshot

	lastHistoryAt time.Time
	previousIO    psnet.IOCountersStat
	previousIOAt  time.Time

	// Cached values refreshed on the slow cadence.
	lastSlowAt   time.Time
	connections  Connections
	processCount int
}

func newCollector(historyMinutes int) *collector {
	return &collector{
		meta:           collectMeta(),
		historyMinutes: historyMinutes,
	}
}

func (c *collector) start() {
	c.collect()
	go func() {
		ticker := time.NewTicker(fastInterval)
		defer ticker.Stop()
		for range ticker.C {
			c.collect()
		}
	}()
}

func (c *collector) currentMeta() Meta {
	return c.meta
}

func (c *collector) currentMetrics() Metrics {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.latest
}

// historySince returns samples strictly newer than the given unix timestamp.
func (c *collector) historySince(since int64) []Snapshot {
	c.mu.RLock()
	defer c.mu.RUnlock()
	out := make([]Snapshot, 0)
	for _, item := range c.history {
		if item.Timestamp > since {
			out = append(out, item)
		}
	}
	return out
}

func collectMeta() Meta {
	hostInfo, _ := host.Info()
	cpuInfos, _ := cpu.Info()
	model := "unknown"
	if len(cpuInfos) > 0 {
		model = cpuInfos[0].ModelName
	}
	return Meta{
		Hostname:               hostInfo.Hostname,
		OS:                     hostInfo.Platform,
		Kernel:                 hostInfo.KernelVersion,
		Architecture:           runtime.GOARCH,
		CPUModel:               model,
		CPUCores:               runtime.NumCPU(),
		AgentVersion:           version,
		CollectIntervalSeconds: int(fastInterval / time.Second),
	}
}

func (c *collector) collect() {
	now := time.Now()

	cpuPercents, _ := cpu.Percent(0, false)
	virtualMemory, _ := mem.VirtualMemory()
	swapMemory, _ := mem.SwapMemory()
	diskUsage, _ := disk.Usage("/")
	ioCounters, _ := psnet.IOCounters(false)
	loadAverages, _ := load.Avg()
	hostInfo, _ := host.Info()

	if now.Sub(c.lastSlowAt) >= slowInterval {
		c.collectSlow()
		c.lastSlowAt = now
	}

	var up, down float64
	var totalUp, totalDown uint64
	if len(ioCounters) > 0 {
		totalUp = ioCounters[0].BytesSent
		totalDown = ioCounters[0].BytesRecv
		if !c.previousIOAt.IsZero() {
			seconds := now.Sub(c.previousIOAt).Seconds()
			if seconds > 0 {
				up = float64(ioCounters[0].BytesSent-c.previousIO.BytesSent) / seconds
				down = float64(ioCounters[0].BytesRecv-c.previousIO.BytesRecv) / seconds
			}
		}
		c.previousIO = ioCounters[0]
		c.previousIOAt = now
	}

	cpuUsage := 0.0
	if len(cpuPercents) > 0 {
		cpuUsage = cpuPercents[0]
	}

	metrics := Metrics{
		Timestamp:    now.Unix(),
		CPUUsage:     cpuUsage,
		Memory:       Memory{Used: virtualMemory.Used, Total: virtualMemory.Total},
		Swap:         Memory{Used: swapMemory.Used, Total: swapMemory.Total},
		Disk:         Memory{Used: diskUsage.Used, Total: diskUsage.Total},
		Network:      Network{Up: up, Down: down, TotalUp: totalUp, TotalDown: totalDown},
		Connections:  c.connections,
		ProcessCount: c.processCount,
		Load:         Load{Load1: loadAverages.Load1, Load5: loadAverages.Load5, Load15: loadAverages.Load15},
		Uptime:       hostInfo.Uptime,
	}

	c.mu.Lock()
	defer c.mu.Unlock()
	c.latest = metrics
	if now.Sub(c.lastHistoryAt) >= historyInterval {
		c.history = append(c.history, Snapshot{Timestamp: now.Unix(), Metrics: metrics})
		c.lastHistoryAt = now
	}
	cutoff := now.Add(-time.Duration(c.historyMinutes) * time.Minute).Unix()
	firstKept := sort.Search(len(c.history), func(i int) bool {
		return c.history[i].Timestamp >= cutoff
	})
	c.history = c.history[firstKept:]
}

func (c *collector) collectSlow() {
	tcpConnections, _ := psnet.Connections("tcp")
	udpConnections, _ := psnet.Connections("udp")
	pids, _ := process.Pids()
	c.connections = Connections{TCP: len(tcpConnections), UDP: len(udpConnections)}
	c.processCount = len(pids)
}
