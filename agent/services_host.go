package main

// Host-level service discovery: web server vhosts, systemd units and a curated
// software inventory. All external commands run with fixed argv (never through
// a shell), a hard timeout and capped output; parse failures degrade to empty
// sections. Parsers are pure functions over captured output so they unit-test
// without the underlying tools installed.

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"os/exec"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
)

const execOutputLimit = 1 << 20 // 1 MiB

// runCommand executes a fixed argv with a timeout, returning combined output.
func runCommand(timeout time.Duration, name string, args ...string) (string, error) {
	if _, err := exec.LookPath(name); err != nil {
		return "", err
	}
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	command := exec.CommandContext(ctx, name, args...)
	var buffer bytes.Buffer
	command.Stdout = &buffer
	command.Stderr = &buffer
	err := command.Run()
	output := buffer.String()
	if len(output) > execOutputLimit {
		output = output[:execOutputLimit]
	}
	return output, err
}

// MARK: websites

func collectWebsites() []Website {
	out := make([]Website, 0)
	if dump, err := runCommand(nginxDumpTimeout, "nginx", "-T"); err == nil {
		out = append(out, parseNginxDump(dump)...)
	}
	if dump, err := runCommand(execTimeout, "apachectl", "-S"); err == nil {
		out = append(out, parseApacheVhosts(dump)...)
	} else if dump, err := runCommand(execTimeout, "httpd", "-S"); err == nil {
		out = append(out, parseApacheVhosts(dump)...)
	}
	out = append(out, collectCaddySites()...)
	return dedupeWebsites(out)
}

// parseNginxDump extracts server blocks from `nginx -T` output with a small
// brace-depth scanner: a server block's server_name and listen directives are
// combined into website entries.
func parseNginxDump(dump string) []Website {
	type serverBlock struct {
		names []string
		ports []int
		tls   bool
	}
	websites := make([]Website, 0)
	var current *serverBlock
	depth := 0
	serverDepth := 0
	flush := func() {
		if current == nil {
			return
		}
		if len(current.ports) == 0 {
			current.ports = []int{80}
		}
		for _, name := range current.names {
			if name == "_" || name == "" {
				continue
			}
			for _, port := range current.ports {
				websites = append(websites, Website{
					Domain: name, Server: "nginx", Port: port,
					TLS: current.tls || port == 443,
				})
			}
		}
		current = nil
	}
	for _, rawLine := range strings.Split(dump, "\n") {
		line := strings.TrimSpace(rawLine)
		if index := strings.Index(line, "#"); index >= 0 {
			line = strings.TrimSpace(line[:index])
		}
		if line == "" {
			continue
		}
		fields := strings.Fields(strings.TrimSuffix(line, ";"))
		if current != nil && len(fields) > 0 {
			switch fields[0] {
			case "server_name":
				current.names = append(current.names, fields[1:]...)
			case "listen":
				for _, field := range fields[1:] {
					if field == "ssl" {
						current.tls = true
					}
					if port := listenPort(field); port > 0 {
						current.ports = append(current.ports, port)
					}
				}
			}
		}
		if strings.HasPrefix(line, "server") && strings.HasSuffix(line, "{") &&
			(line == "server {" || strings.HasPrefix(line, "server {")) {
			current = &serverBlock{}
			serverDepth = depth
		}
		depth += strings.Count(line, "{") - strings.Count(line, "}")
		if current != nil && depth <= serverDepth {
			flush()
		}
	}
	flush()
	return websites
}

// listenPort pulls the port from nginx listen tokens: "80", "0.0.0.0:8080",
// "[::]:443", "unix:/run/x.sock" (ignored).
func listenPort(token string) int {
	if strings.HasPrefix(token, "unix:") {
		return 0
	}
	candidate := token
	if index := strings.LastIndex(token, ":"); index >= 0 {
		candidate = token[index+1:]
	}
	port, err := strconv.Atoi(candidate)
	if err != nil || port <= 0 || port > 65535 {
		return 0
	}
	return port
}

var apacheVhostPattern = regexp.MustCompile(`port (\d+) namevhost (\S+)`)

func parseApacheVhosts(dump string) []Website {
	websites := make([]Website, 0)
	for _, match := range apacheVhostPattern.FindAllStringSubmatch(dump, -1) {
		port, _ := strconv.Atoi(match[1])
		websites = append(websites, Website{
			Domain: match[2], Server: "apache", Port: port, TLS: port == 443,
		})
	}
	return websites
}

// collectCaddySites reads the local Caddy admin API when it is listening.
func collectCaddySites() []Website {
	client := &http.Client{Timeout: 2 * time.Second}
	response, err := client.Get("http://127.0.0.1:2019/config/")
	if err != nil {
		return nil
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return nil
	}
	var config map[string]any
	if err := json.NewDecoder(response.Body).Decode(&config); err != nil {
		return nil
	}
	return parseCaddyConfig(config)
}

func parseCaddyConfig(config map[string]any) []Website {
	websites := make([]Website, 0)
	apps, _ := config["apps"].(map[string]any)
	httpApp, _ := apps["http"].(map[string]any)
	servers, _ := httpApp["servers"].(map[string]any)
	for _, rawServer := range servers {
		server, _ := rawServer.(map[string]any)
		port := 443
		if listens, _ := server["listen"].([]any); len(listens) > 0 {
			if listen, _ := listens[0].(string); listen != "" {
				if parsed := listenPort(listen); parsed > 0 {
					port = parsed
				}
			}
		}
		routes, _ := server["routes"].([]any)
		for _, rawRoute := range routes {
			route, _ := rawRoute.(map[string]any)
			matchers, _ := route["match"].([]any)
			for _, rawMatcher := range matchers {
				matcher, _ := rawMatcher.(map[string]any)
				hosts, _ := matcher["host"].([]any)
				for _, rawHost := range hosts {
					if host, _ := rawHost.(string); host != "" {
						websites = append(websites, Website{
							Domain: host, Server: "caddy", Port: port, TLS: port != 80,
						})
					}
				}
			}
		}
	}
	return websites
}

func dedupeWebsites(websites []Website) []Website {
	seen := map[Website]bool{}
	out := make([]Website, 0, len(websites))
	for _, website := range websites {
		if !seen[website] {
			seen[website] = true
			out = append(out, website)
		}
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Domain != out[j].Domain {
			return out[i].Domain < out[j].Domain
		}
		return out[i].Port < out[j].Port
	})
	return out
}

// MARK: systemd

func collectSystemd() *Systemd {
	running, err := runCommand(execTimeout, "systemctl",
		"list-units", "--type=service", "--state=running", "--no-legend", "--no-pager", "--plain")
	if err != nil {
		return nil
	}
	result := &Systemd{Running: parseSystemdUnits(running), Failed: []string{}}
	if failed, err := runCommand(execTimeout, "systemctl",
		"list-units", "--type=service", "--state=failed", "--no-legend", "--no-pager", "--plain"); err == nil {
		for _, unit := range parseSystemdUnits(failed) {
			result.Failed = append(result.Failed, unit.Name)
		}
	}
	return result
}

// parseSystemdUnits reads `--no-legend --plain` output: NAME LOAD ACTIVE SUB
// DESCRIPTION…, one unit per line.
func parseSystemdUnits(output string) []SystemdUnit {
	units := make([]SystemdUnit, 0)
	for _, line := range strings.Split(output, "\n") {
		fields := strings.Fields(line)
		if len(fields) < 4 || !strings.HasSuffix(fields[0], ".service") {
			continue
		}
		units = append(units, SystemdUnit{
			Name:        fields[0],
			Description: strings.Join(fields[4:], " "),
		})
	}
	return units
}

// MARK: packages

var versionPattern = regexp.MustCompile(`\d+(?:\.\d+)+[0-9A-Za-z.+~-]*`)

// packageNames is the curated package-manager query list.
var packageNames = []string{
	"nginx", "caddy", "apache2", "httpd", "mysql-server", "mariadb-server",
	"postgresql", "redis", "redis-server", "mongodb-org", "docker-ce",
	"fail2ban", "ufw", "wireguard-tools", "tailscale",
}

// binaryProbes are version probes for software often installed outside the
// package manager. Fixed argv only.
var binaryProbes = []struct {
	display string
	command string
	args    []string
}{
	{"docker", "docker", []string{"--version"}},
	{"node", "node", []string{"--version"}},
	{"go", "go", []string{"version"}},
	{"python3", "python3", []string{"--version"}},
	{"php", "php", []string{"--version"}},
	{"java", "java", []string{"-version"}},
	{"git", "git", []string{"--version"}},
	{"rustc", "rustc", []string{"--version"}},
	{"nginx", "nginx", []string{"-v"}},
	{"caddy", "caddy", []string{"version"}},
}

func collectPackages() []Package {
	found := map[string]Package{}
	for name, version := range queryPackageManager() {
		found[name] = Package{Name: name, Version: version, Source: "pkg"}
	}
	for _, probe := range binaryProbes {
		if _, exists := found[probe.display]; exists {
			continue
		}
		output, err := runCommand(execTimeout, probe.command, probe.args...)
		if err != nil && output == "" {
			continue
		}
		if version := versionPattern.FindString(output); version != "" {
			found[probe.display] = Package{Name: probe.display, Version: version, Source: "bin"}
		}
	}
	out := make([]Package, 0, len(found))
	for _, item := range found {
		out = append(out, item)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out
}

func queryPackageManager() map[string]string {
	if output, err := runCommand(execTimeout, "dpkg-query", append(
		[]string{"-W", "-f", "${Package}\t${Version}\n"}, packageNames...)...); output != "" || err == nil {
		if parsed := parsePackageLines(output); len(parsed) > 0 {
			return parsed
		}
	}
	if output, _ := runCommand(execTimeout, "rpm", append(
		[]string{"-q", "--qf", "%{NAME}\t%{VERSION}\n"}, packageNames...)...); output != "" {
		return parsePackageLines(output)
	}
	return nil
}

// parsePackageLines reads "name<TAB>version" lines, skipping error lines from
// packages that are not installed (dpkg prints them to the same stream).
func parsePackageLines(output string) map[string]string {
	result := map[string]string{}
	for _, line := range strings.Split(output, "\n") {
		parts := strings.Split(line, "\t")
		if len(parts) != 2 {
			continue
		}
		name, version := strings.TrimSpace(parts[0]), strings.TrimSpace(parts[1])
		if name == "" || version == "" || strings.Contains(name, " ") {
			continue
		}
		result[name] = version
	}
	return result
}
