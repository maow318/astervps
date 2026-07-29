package main

// Local vhost health probes: each detected website gets one loopback request
// with the proper Host/SNI so name-based vhosts answer as they would for real
// traffic. Captures HTTP status, latency and certificate expiry. Loopback
// only — the agent never probes remote addresses.

import (
	"crypto/tls"
	"fmt"
	"net"
	"net/http"
	"sync"
	"time"
)

const (
	probeTimeout  = 3 * time.Second
	probeParallel = 4
	maxProbes     = 20
)

func probeWebsites(websites []Website) []Website {
	semaphore := make(chan struct{}, probeParallel)
	var waitGroup sync.WaitGroup
	budget := maxProbes
	for i := range websites {
		if budget == 0 {
			break
		}
		budget--
		waitGroup.Add(1)
		go func(site *Website) {
			defer waitGroup.Done()
			semaphore <- struct{}{}
			defer func() { <-semaphore }()
			probeOne(site, "127.0.0.1")
		}(&websites[i])
	}
	waitGroup.Wait()
	return websites
}

// probeOne dials the local port with the site's hostname as Host header and
// SNI, records status/latency, and reads certificate expiry for TLS sites.
// Certificate verification is intentionally skipped: the probe measures expiry
// and liveness of a server we are colocated with, not trust.
func probeOne(site *Website, dialHost string) {
	address := net.JoinHostPort(dialHost, fmt.Sprintf("%d", site.Port))
	transport := &http.Transport{
		DialContext: (&net.Dialer{Timeout: probeTimeout}).DialContext,
		TLSClientConfig: &tls.Config{
			ServerName:         site.Domain,
			InsecureSkipVerify: true,
		},
		DisableKeepAlives: true,
	}
	client := &http.Client{
		Timeout:   probeTimeout,
		Transport: transport,
		CheckRedirect: func(*http.Request, []*http.Request) error {
			// A redirect answer already proves the vhost is alive.
			return http.ErrUseLastResponse
		},
	}
	scheme := "http"
	if site.TLS {
		scheme = "https"
	}
	request, err := http.NewRequest(http.MethodGet, scheme+"://"+address+"/", nil)
	if err != nil {
		return
	}
	request.Host = site.Domain

	started := time.Now()
	response, err := client.Do(request)
	if err != nil {
		site.Status = 0
		site.OK = false
		return
	}
	defer response.Body.Close()
	site.LatencyMS = time.Since(started).Milliseconds()
	site.Status = response.StatusCode
	site.OK = statusHealthy(response.StatusCode)
	if response.TLS != nil && len(response.TLS.PeerCertificates) > 0 {
		days := daysUntil(response.TLS.PeerCertificates[0].NotAfter)
		site.CertDaysLeft = &days
	}
}

// statusHealthy treats anything the server answered deliberately as alive;
// only 5xx (and unreachable, status 0) count as unhealthy.
func statusHealthy(status int) bool {
	return status >= 200 && status < 500
}

func daysUntil(deadline time.Time) int {
	return int(time.Until(deadline).Hours() / 24)
}
