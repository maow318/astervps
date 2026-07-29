package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strconv"
	"testing"
)

const nginxDumpSample = `
# configuration file /etc/nginx/nginx.conf:
http {
    server {
        listen 80 default_server;
        server_name _;
    }
    server {
        listen 443 ssl http2;
        listen [::]:443 ssl;
        server_name blog.example.com www.example.com; # comment
        location / {
            proxy_pass http://127.0.0.1:3000;
        }
    }
    server {
        listen 8080;
        server_name internal.example.com;
    }
}
`

func TestParseNginxDump(t *testing.T) {
	websites := parseNginxDump(nginxDumpSample)
	expected := map[string]bool{
		"blog.example.com:443:true":       false,
		"www.example.com:443:true":        false,
		"internal.example.com:8080:false": false,
	}
	for _, site := range websites {
		key := site.Domain + ":" + itoa(site.Port) + ":" + boolString(site.TLS)
		if _, ok := expected[key]; !ok {
			t.Fatalf("unexpected website %+v", site)
		}
		expected[key] = true
		if site.Server != "nginx" {
			t.Fatalf("wrong server for %+v", site)
		}
	}
	for key, found := range expected {
		if !found {
			t.Fatalf("missing website %s in %+v", key, websites)
		}
	}
	// The catch-all "_" server must not leak in. 443 appears twice (v4+v6) but
	// dedupe happens later in dedupeWebsites; raw count is 2 names x 2 listens + 1.
	if len(websites) != 5 {
		t.Fatalf("expected 5 raw entries, got %d: %+v", len(websites), websites)
	}
	if len(dedupeWebsites(websites)) != 3 {
		t.Fatalf("dedupe failed: %+v", dedupeWebsites(websites))
	}
}

func TestListenPort(t *testing.T) {
	cases := map[string]int{
		"80": 80, "0.0.0.0:8080": 8080, "[::]:443": 443,
		"unix:/run/nginx.sock": 0, "ssl": 0, "localhost:3000": 3000,
	}
	for token, expected := range cases {
		if got := listenPort(token); got != expected {
			t.Fatalf("listenPort(%q) = %d, expected %d", token, got, expected)
		}
	}
}

func TestParseApacheVhosts(t *testing.T) {
	dump := `VirtualHost configuration:
*:443                  is a NameVirtualHost
         default server shop.example.com (/etc/apache2/sites-enabled/shop.conf:1)
         port 443 namevhost shop.example.com (/etc/apache2/sites-enabled/shop.conf:1)
         port 443 namevhost api.example.com (/etc/apache2/sites-enabled/api.conf:1)
*:80                   port 80 namevhost legacy.example.com (/etc/apache2/sites-enabled/legacy.conf:1)
`
	websites := parseApacheVhosts(dump)
	if len(websites) != 3 {
		t.Fatalf("expected 3 vhosts, got %+v", websites)
	}
	if websites[0].Domain != "shop.example.com" || !websites[0].TLS || websites[0].Port != 443 {
		t.Fatalf("bad first vhost: %+v", websites[0])
	}
	if websites[2].Domain != "legacy.example.com" || websites[2].TLS || websites[2].Port != 80 {
		t.Fatalf("bad last vhost: %+v", websites[2])
	}
}

func TestParseCaddyConfig(t *testing.T) {
	raw := `{"apps":{"http":{"servers":{"srv0":{"listen":[":443"],
		"routes":[{"match":[{"host":["caddy.example.com","alt.example.com"]}]}]},
		"srv1":{"listen":[":8081"],"routes":[{"match":[{"host":["plain.example.com"]}]}]}}}}}`
	var config map[string]any
	if err := json.Unmarshal([]byte(raw), &config); err != nil {
		t.Fatal(err)
	}
	websites := dedupeWebsites(parseCaddyConfig(config))
	if len(websites) != 3 {
		t.Fatalf("expected 3 sites, got %+v", websites)
	}
	for _, site := range websites {
		if site.Domain == "plain.example.com" && (site.Port != 8081 || !site.TLS) {
			// non-80 ports are assumed TLS-terminated by caddy's auto-https
			t.Fatalf("bad plain site: %+v", site)
		}
		if site.Domain == "caddy.example.com" && site.Port != 443 {
			t.Fatalf("bad caddy site: %+v", site)
		}
	}
}

func TestParseSystemdUnits(t *testing.T) {
	output := `nginx.service      loaded active running A high performance web server and a reverse proxy server
docker.service     loaded active running Docker Application Container Engine
not-a-service-line
ssh.service        loaded active running OpenBSD Secure Shell server
`
	units := parseSystemdUnits(output)
	if len(units) != 3 {
		t.Fatalf("expected 3 units, got %+v", units)
	}
	if units[0].Name != "nginx.service" ||
		units[0].Description != "A high performance web server and a reverse proxy server" {
		t.Fatalf("bad unit: %+v", units[0])
	}
}

func TestCPUPercent(t *testing.T) {
	stats := containerStats{}
	stats.CPUStats.CPUUsage.TotalUsage = 400_000_000
	stats.PreCPUStats.CPUUsage.TotalUsage = 300_000_000
	stats.CPUStats.SystemUsage = 10_000_000_000
	stats.PreCPUStats.SystemUsage = 8_000_000_000
	stats.CPUStats.OnlineCPUs = 4
	got := stats.cpuPercent()
	if got < 19.9 || got > 20.1 {
		t.Fatalf("cpu percent = %f, expected 20", got)
	}
	if (containerStats{}).cpuPercent() != 0 {
		t.Fatal("zero stats must yield 0")
	}
}

func TestMemory(t *testing.T) {
	stats := containerStats{}
	stats.MemoryStats.Usage = 1000
	stats.MemoryStats.Limit = 1 << 62
	stats.MemoryStats.Stats = map[string]uint64{"inactive_file": 300}
	used, limit := stats.memory()
	if used != 700 || limit != 0 {
		t.Fatalf("memory() = %d/%d, expected 700/0", used, limit)
	}
}

func TestParsePackageLines(t *testing.T) {
	output := "nginx\t1.24.0-2ubuntu7\ndpkg-query: no packages found matching caddy\nredis\t7.0.15\n"
	parsed := parsePackageLines(output)
	if len(parsed) != 2 || parsed["nginx"] != "1.24.0-2ubuntu7" || parsed["redis"] != "7.0.15" {
		t.Fatalf("bad parse: %+v", parsed)
	}
}

func TestVersionPattern(t *testing.T) {
	cases := map[string]string{
		"Docker version 27.1.1, build 6312585": "27.1.1",
		"nginx version: nginx/1.24.0":          "1.24.0",
		"go version go1.22.5 darwin/arm64":     "1.22.5",
		"v20.11.1":                             "20.11.1",
	}
	for input, expected := range cases {
		if got := versionPattern.FindString(input); got != expected {
			t.Fatalf("versionPattern(%q) = %q, expected %q", input, got, expected)
		}
	}
}

func TestScopeOf(t *testing.T) {
	if scopeOf("127.0.0.1") != "local" || scopeOf("::1") != "local" {
		t.Fatal("loopback must be local")
	}
	if scopeOf("0.0.0.0") != "public" || scopeOf("::") != "public" || scopeOf("10.0.0.5") != "public" {
		t.Fatal("non-loopback must be public")
	}
}

func TestAnnotateContainers(t *testing.T) {
	listeners := []Listener{
		{Port: 8080, Process: "docker-proxy"},
		{Port: 8081, Process: "nginx"},
		{Port: 9000, Process: ""},
	}
	containers := []Container{
		{Name: "blog", Ports: []ContainerPort{{Host: 8080, Container: 80}}},
		{Name: "api", Ports: []ContainerPort{{Host: 9000, Container: 3000}}},
	}
	annotateContainers(listeners, containers)
	if listeners[0].Container != "blog" {
		t.Fatalf("docker-proxy listener not annotated: %+v", listeners[0])
	}
	if listeners[1].Container != "" {
		t.Fatal("regular process must not be annotated")
	}
	if listeners[2].Container != "api" {
		t.Fatal("unresolved process on published port should be annotated")
	}
}

func itoa(value int) string {
	return strconv.Itoa(value)
}

func boolString(value bool) string {
	if value {
		return "true"
	}
	return "false"
}

func TestProbeOne(t *testing.T) {
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Host != "probe.example.com" {
			t.Errorf("expected vhost Host header, got %q", r.Host)
		}
		w.WriteHeader(http.StatusOK)
	}))
	defer server.Close()
	serverURL, _ := url.Parse(server.URL)
	port, _ := strconv.Atoi(serverURL.Port())

	site := Website{Domain: "probe.example.com", Server: "nginx", Port: port, TLS: true}
	probeOne(&site, serverURL.Hostname())
	if site.Status != 200 || !site.OK {
		t.Fatalf("probe failed: %+v", site)
	}
	if site.LatencyMS < 0 {
		t.Fatalf("bad latency: %+v", site)
	}
	if site.CertDaysLeft == nil || *site.CertDaysLeft < 1 {
		t.Fatalf("expected future cert expiry, got %+v", site.CertDaysLeft)
	}

	dead := Website{Domain: "probe.example.com", Server: "nginx", Port: 1, TLS: false}
	probeOne(&dead, "127.0.0.1")
	if dead.OK || dead.Status != 0 {
		t.Fatalf("dead port must fail: %+v", dead)
	}
}

func TestStatusHealthy(t *testing.T) {
	for status, expected := range map[int]bool{200: true, 301: true, 404: true, 500: false, 502: false, 0: false} {
		if statusHealthy(status) != expected {
			t.Fatalf("statusHealthy(%d) != %v", status, expected)
		}
	}
}
