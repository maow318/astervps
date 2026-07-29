package main

// Docker inspection over the local unix socket. Uses the plain HTTP API so no
// SDK dependency is pulled in; every request shares one short-lived client
// with hard timeouts. Read-only endpoints exclusively.

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"os"
	"sort"
	"strings"
	"sync"
	"time"
)

const (
	dockerTimeout   = 5 * time.Second
	maxStatsTargets = 20
	statsParallel   = 4
)

type dockerAPI struct {
	client *http.Client
}

func newDockerAPI(socketPath string) *dockerAPI {
	return &dockerAPI{client: &http.Client{
		Timeout: dockerTimeout,
		Transport: &http.Transport{
			DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
				var dialer net.Dialer
				return dialer.DialContext(ctx, "unix", socketPath)
			},
		},
	}}
}

func (d *dockerAPI) get(path string, target any) error {
	response, err := d.client.Get("http://docker" + path)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return fmt.Errorf("docker API %s: HTTP %d", path, response.StatusCode)
	}
	return json.NewDecoder(response.Body).Decode(target)
}

func collectDocker(socketPath string) Docker {
	if _, err := os.Stat(socketPath); err != nil {
		return Docker{Available: false, Reason: "socket not found"}
	}
	api := newDockerAPI(socketPath)

	var version struct {
		Version string `json:"Version"`
	}
	if err := api.get("/version", &version); err != nil {
		reason := "unreachable"
		if os.IsPermission(err) || strings.Contains(err.Error(), "permission denied") {
			reason = "permission denied"
		}
		return Docker{Available: false, Reason: reason}
	}

	result := Docker{Available: true, Version: version.Version}
	result.Swarm = collectSwarm(api)
	result.Containers = collectContainers(api)
	return result
}

type apiContainer struct {
	ID     string            `json:"Id"`
	Names  []string          `json:"Names"`
	Image  string            `json:"Image"`
	State  string            `json:"State"`
	Status string            `json:"Status"`
	Labels map[string]string `json:"Labels"`
	Ports  []struct {
		PrivatePort uint16 `json:"PrivatePort"`
		PublicPort  uint16 `json:"PublicPort"`
		Type        string `json:"Type"`
	} `json:"Ports"`
}

func collectContainers(api *dockerAPI) []Container {
	var listed []apiContainer
	if err := api.get("/containers/json?all=true", &listed); err != nil {
		return nil
	}
	containers := make([]Container, 0, len(listed))
	for _, item := range listed {
		container := Container{
			ID:             shortID(item.ID),
			Name:           containerName(item.Names),
			Image:          item.Image,
			State:          item.State,
			Status:         item.Status,
			ComposeProject: item.Labels["com.docker.compose.project"],
			ComposeService: item.Labels["com.docker.compose.service"],
			Ports:          make([]ContainerPort, 0, len(item.Ports)),
		}
		portSeen := map[ContainerPort]bool{}
		for _, port := range item.Ports {
			mapped := ContainerPort{Host: port.PublicPort, Container: port.PrivatePort, Protocol: port.Type}
			if !portSeen[mapped] {
				portSeen[mapped] = true
				container.Ports = append(container.Ports, mapped)
			}
		}
		containers = append(containers, container)
	}
	sort.Slice(containers, func(i, j int) bool { return containers[i].Name < containers[j].Name })
	enrichContainers(api, containers)
	return containers
}

// enrichContainers adds restart counts for all containers and live CPU/memory
// for running ones, bounded so a machine with dozens of containers cannot make
// the collector slow: at most maxStatsTargets stats calls, statsParallel wide.
func enrichContainers(api *dockerAPI, containers []Container) {
	semaphore := make(chan struct{}, statsParallel)
	var waitGroup sync.WaitGroup
	statsBudget := maxStatsTargets
	for i := range containers {
		fetchStats := containers[i].State == "running" && statsBudget > 0
		if fetchStats {
			statsBudget--
		}
		waitGroup.Add(1)
		go func(container *Container, withStats bool) {
			defer waitGroup.Done()
			semaphore <- struct{}{}
			defer func() { <-semaphore }()

			var inspect struct {
				RestartCount int `json:"RestartCount"`
			}
			if err := api.get("/containers/"+container.ID+"/json", &inspect); err == nil {
				container.Restarts = inspect.RestartCount
			}
			if !withStats {
				return
			}
			var stats containerStats
			if err := api.get("/containers/"+container.ID+"/stats?stream=false&one-shot=true", &stats); err == nil {
				container.CPUPercent = stats.cpuPercent()
				container.MemUsed, container.MemLimit = stats.memory()
			}
		}(&containers[i], fetchStats)
	}
	waitGroup.Wait()
}

type containerStats struct {
	CPUStats    cpuStats `json:"cpu_stats"`
	PreCPUStats cpuStats `json:"precpu_stats"`
	MemoryStats struct {
		Usage uint64            `json:"usage"`
		Limit uint64            `json:"limit"`
		Stats map[string]uint64 `json:"stats"`
	} `json:"memory_stats"`
}

type cpuStats struct {
	CPUUsage struct {
		TotalUsage uint64 `json:"total_usage"`
	} `json:"cpu_usage"`
	SystemUsage uint64 `json:"system_cpu_usage"`
	OnlineCPUs  uint64 `json:"online_cpus"`
}

// cpuPercent implements Docker's documented stats formula.
func (s containerStats) cpuPercent() float64 {
	cpuDelta := float64(s.CPUStats.CPUUsage.TotalUsage) - float64(s.PreCPUStats.CPUUsage.TotalUsage)
	systemDelta := float64(s.CPUStats.SystemUsage) - float64(s.PreCPUStats.SystemUsage)
	if cpuDelta <= 0 || systemDelta <= 0 {
		return 0
	}
	cpus := float64(s.CPUStats.OnlineCPUs)
	if cpus == 0 {
		cpus = 1
	}
	return cpuDelta / systemDelta * cpus * 100
}

// memory mirrors `docker stats`: usage minus inactive file cache; a limit that
// is effectively "no limit" is reported as 0 so clients can hide it.
func (s containerStats) memory() (used, limit uint64) {
	used = s.MemoryStats.Usage
	if inactive, ok := s.MemoryStats.Stats["inactive_file"]; ok && inactive < used {
		used -= inactive
	}
	limit = s.MemoryStats.Limit
	if limit >= 1<<60 {
		limit = 0
	}
	return used, limit
}

func collectSwarm(api *dockerAPI) Swarm {
	var info struct {
		Swarm struct {
			LocalNodeState   string `json:"LocalNodeState"`
			ControlAvailable bool   `json:"ControlAvailable"`
			Nodes            int    `json:"Nodes"`
		} `json:"Swarm"`
	}
	if err := api.get("/info", &info); err != nil || info.Swarm.LocalNodeState != "active" {
		return Swarm{Active: false}
	}
	swarm := Swarm{Active: true, Role: "worker", Nodes: info.Swarm.Nodes}
	if !info.Swarm.ControlAvailable {
		return swarm
	}
	swarm.Role = "manager"
	var services []struct {
		Spec struct {
			Name string `json:"Name"`
			Mode struct {
				Replicated *struct {
					Replicas uint64 `json:"Replicas"`
				} `json:"Replicated"`
			} `json:"Mode"`
		} `json:"Spec"`
	}
	if err := api.get("/services", &services); err == nil {
		for _, service := range services {
			replicas := "global"
			if service.Spec.Mode.Replicated != nil {
				replicas = fmt.Sprintf("%d", service.Spec.Mode.Replicated.Replicas)
			}
			swarm.Services = append(swarm.Services, SwarmService{
				Name: service.Spec.Name, Replicas: replicas,
			})
		}
		sort.Slice(swarm.Services, func(i, j int) bool {
			return swarm.Services[i].Name < swarm.Services[j].Name
		})
	}
	return swarm
}

func shortID(id string) string {
	if len(id) > 12 {
		return id[:12]
	}
	return id
}

func containerName(names []string) string {
	if len(names) == 0 {
		return ""
	}
	return strings.TrimPrefix(names[0], "/")
}
