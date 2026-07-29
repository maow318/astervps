package main

// Service inspection: what is actually running on this host. Everything here
// is strictly read-only — the agent never executes anything derived from
// network input; every exec below is a fixed argv with a hard timeout.

import (
	"strings"
	"sync"
	"time"

	psnet "github.com/shirou/gopsutil/v4/net"
	"github.com/shirou/gopsutil/v4/process"
)

const (
	// Service data changes rarely; the collector refreshes on its own slow
	// cadence and /v1/services serves the cached blob.
	defaultServicesInterval = 60 * time.Second
	// forceRefreshCooldown rate-limits ?refresh=1 so a hostile client holding
	// a stolen token still cannot turn the agent into a load generator.
	forceRefreshCooldown = 10 * time.Second
	maxListeners         = 400
	cmdlineLimit         = 120
	execTimeout          = 3 * time.Second
	nginxDumpTimeout     = 5 * time.Second
)

type Listener struct {
	Port      uint32 `json:"port"`
	Protocol  string `json:"protocol"`
	Address   string `json:"address"`
	Scope     string `json:"scope"` // "public" or "local"
	PID       int32  `json:"pid"`
	Process   string `json:"process"`
	Cmdline   string `json:"cmdline"`
	User      string `json:"user"`
	Container string `json:"container,omitempty"`
}

type Website struct {
	Domain string `json:"domain"`
	Server string `json:"server"` // nginx / caddy / apache
	Port   int    `json:"port"`
	TLS    bool   `json:"tls"`
}

type ContainerPort struct {
	Host      uint16 `json:"host"`
	Container uint16 `json:"container"`
	Protocol  string `json:"protocol"`
}

type Container struct {
	ID             string          `json:"id"`
	Name           string          `json:"name"`
	Image          string          `json:"image"`
	State          string          `json:"state"`
	Status         string          `json:"status"`
	ComposeProject string          `json:"compose_project,omitempty"`
	ComposeService string          `json:"compose_service,omitempty"`
	Ports          []ContainerPort `json:"ports"`
	CPUPercent     float64         `json:"cpu_percent"`
	MemUsed        uint64          `json:"mem_used"`
	MemLimit       uint64          `json:"mem_limit"`
	Restarts       int             `json:"restarts"`
}

type SwarmService struct {
	Name     string `json:"name"`
	Replicas string `json:"replicas"` // "3" for replicated, "global" otherwise
}

type Swarm struct {
	Active   bool           `json:"active"`
	Role     string         `json:"role,omitempty"` // manager / worker
	Nodes    int            `json:"nodes,omitempty"`
	Services []SwarmService `json:"services,omitempty"`
}

type Docker struct {
	Available  bool        `json:"available"`
	Reason     string      `json:"reason,omitempty"`
	Version    string      `json:"version,omitempty"`
	Swarm      Swarm       `json:"swarm"`
	Containers []Container `json:"containers,omitempty"`
}

type SystemdUnit struct {
	Name        string `json:"name"`
	Description string `json:"description"`
}

type Systemd struct {
	Running []SystemdUnit `json:"running"`
	Failed  []string      `json:"failed"`
}

type Package struct {
	Name    string `json:"name"`
	Version string `json:"version"`
	Source  string `json:"source"` // "pkg" or "bin"
}

type Services struct {
	CollectedAt int64      `json:"collected_at"`
	Restricted  bool       `json:"restricted"`
	Listeners   []Listener `json:"listeners"`
	Websites    []Website  `json:"websites"`
	Docker      Docker     `json:"docker"`
	Systemd     *Systemd   `json:"systemd,omitempty"`
	Packages    []Package  `json:"packages"`
}

type serviceCollector struct {
	interval   time.Duration
	dockerSock string

	mu          sync.RWMutex
	latest      Services
	lastCollect time.Time
}

func newServiceCollector(intervalSeconds int, dockerSock string) *serviceCollector {
	interval := defaultServicesInterval
	if intervalSeconds > 0 {
		interval = time.Duration(intervalSeconds) * time.Second
	}
	return &serviceCollector{interval: interval, dockerSock: dockerSock}
}

func (s *serviceCollector) start() {
	go func() {
		s.collect()
		ticker := time.NewTicker(s.interval)
		defer ticker.Stop()
		for range ticker.C {
			s.collect()
		}
	}()
}

// current returns the cached blob; force triggers a synchronous re-collect
// unless one ran within the cooldown window.
func (s *serviceCollector) current(force bool) Services {
	if force {
		s.mu.RLock()
		stale := time.Since(s.lastCollect) >= forceRefreshCooldown
		s.mu.RUnlock()
		if stale {
			s.collect()
		}
	}
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.latest
}

func (s *serviceCollector) collect() {
	listeners, restricted := collectListeners()
	docker := collectDocker(s.dockerSock)
	annotateContainers(listeners, docker.Containers)
	result := Services{
		CollectedAt: time.Now().Unix(),
		Restricted:  restricted,
		Listeners:   listeners,
		Websites:    collectWebsites(),
		Docker:      docker,
		Systemd:     collectSystemd(),
		Packages:    collectPackages(),
	}
	s.mu.Lock()
	s.latest = result
	s.lastCollect = time.Now()
	s.mu.Unlock()
}

// collectListeners walks the socket table for listening endpoints. UDP sockets
// carry no state, so every bound UDP socket counts as a listener.
func collectListeners() ([]Listener, bool) {
	connections, err := psnet.Connections("inet")
	if err != nil {
		return []Listener{}, false
	}
	type key struct {
		port  uint32
		proto string
		pid   int32
	}
	seen := map[key]int{}
	out := make([]Listener, 0)
	unresolved := 0
	total := 0
	for _, conn := range connections {
		proto := protocolName(conn)
		if proto == "tcp" && conn.Status != "LISTEN" {
			continue
		}
		if proto == "udp" && conn.Raddr.Port != 0 {
			continue
		}
		if proto == "" || conn.Laddr.Port == 0 {
			continue
		}
		total++
		k := key{port: conn.Laddr.Port, proto: proto, pid: conn.Pid}
		if index, ok := seen[k]; ok {
			// IPv4+IPv6 twins of one socket: keep the wildcard-looking address.
			if isWildcard(conn.Laddr.IP) && !isWildcard(out[index].Address) {
				out[index].Address = conn.Laddr.IP
				out[index].Scope = scopeOf(conn.Laddr.IP)
			}
			continue
		}
		listener := Listener{
			Port:     conn.Laddr.Port,
			Protocol: proto,
			Address:  conn.Laddr.IP,
			Scope:    scopeOf(conn.Laddr.IP),
			PID:      conn.Pid,
		}
		if conn.Pid > 0 {
			fillProcess(&listener)
		}
		if listener.Process == "" {
			unresolved++
		}
		seen[k] = len(out)
		out = append(out, listener)
		if len(out) >= maxListeners {
			break
		}
	}
	restricted := total > 0 && unresolved*2 > total
	return out, restricted
}

func fillProcess(listener *Listener) {
	proc, err := process.NewProcess(listener.PID)
	if err != nil {
		return
	}
	if name, err := proc.Name(); err == nil {
		listener.Process = name
	}
	if cmdline, err := proc.Cmdline(); err == nil {
		listener.Cmdline = truncate(cmdline, cmdlineLimit)
	}
	if user, err := proc.Username(); err == nil {
		listener.User = user
	}
}

func protocolName(conn psnet.ConnectionStat) string {
	switch conn.Type {
	case 1: // SOCK_STREAM
		return "tcp"
	case 2: // SOCK_DGRAM
		return "udp"
	default:
		return ""
	}
}

func isWildcard(address string) bool {
	return address == "0.0.0.0" || address == "::" || address == "*" || address == ""
}

func scopeOf(address string) string {
	if address == "::1" || address == "localhost" || strings.HasPrefix(address, "127.") {
		return "local"
	}
	return "public"
}

// annotateContainers labels docker-proxy listeners (and published ports that
// match) with their container name so the UI can cross-link them.
func annotateContainers(listeners []Listener, containers []Container) {
	byHostPort := map[uint16]string{}
	for _, container := range containers {
		for _, port := range container.Ports {
			if port.Host > 0 {
				byHostPort[port.Host] = container.Name
			}
		}
	}
	for i := range listeners {
		name, published := byHostPort[uint16(listeners[i].Port)]
		if !published {
			continue
		}
		if listeners[i].Process == "docker-proxy" || listeners[i].Process == "" {
			listeners[i].Container = name
		}
	}
}

func truncate(value string, limit int) string {
	if len(value) <= limit {
		return value
	}
	return value[:limit] + "…"
}
