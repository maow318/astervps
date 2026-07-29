# Aster Agent Protocol v1

All endpoints require `Authorization: Bearer <token>` and are available only over HTTPS.
Values are JSON `snake_case`; byte quantities are bytes and percentages use `0…100`.

| Endpoint | Response |
| --- | --- |
| `GET /v1/meta` | Host static metadata, agent version and collection interval. |
| `GET /v1/metrics` | The latest complete metric frame. |
| `GET /v1/history?since=<unix_ts>` | History frames strictly newer than `since`. |
| `GET /v1/services` | Cached service inspection: listening ports, websites, Docker, systemd, software inventory. `?refresh=1` forces a synchronous re-collect (rate-limited to one per 10 s). |

```json
{"timestamp":1710000000,"cpu_usage":12.5,"memory":{"used":123,"total":456},"network":{"up":42,"down":81,"total_up":1000,"total_down":2000},"load":{"load1":0.5,"load5":0.4,"load15":0.3}}
```

`401 {"error":"unauthorized"}` indicates a missing or incorrect bearer token. An unparsable `since` parameter returns `400 {"error":"invalid since"}`.

Collection cadence: CPU/memory/disk/network refresh every 2 s; connection and process counts refresh every 10 s (socket/process table walks are expensive on busy servers), so those two fields may lag by up to 10 s. History samples are recorded every 30 s and retained for `--history-minutes`.

## /v1/services

Refreshed every `--services-interval` seconds (default 60) by a dedicated collector; the endpoint always serves the cached blob so responses stay fast. Agents older than 0.2.0 do not have this endpoint (404) — clients must degrade gracefully.

```json
{"collected_at":1710000000,"restricted":false,
 "listeners":[{"port":443,"protocol":"tcp","address":"0.0.0.0","scope":"public","pid":612,
               "process":"nginx","cmdline":"nginx: master process","user":"root","container":"web"}],
 "websites":[{"domain":"blog.example.com","server":"nginx","port":443,"tls":true}],
 "docker":{"available":true,"version":"27.1.1",
           "swarm":{"active":true,"role":"manager","nodes":3,
                    "services":[{"name":"web","replicas":"2"}]},
           "containers":[{"id":"ab12cd34ef56","name":"blog","image":"nginx:1.27","state":"running",
                          "status":"Up 3 days","compose_project":"blog","compose_service":"web",
                          "ports":[{"host":8080,"container":80,"protocol":"tcp"}],
                          "cpu_percent":1.8,"mem_used":104857600,"mem_limit":0,"restarts":0}]},
 "systemd":{"running":[{"name":"nginx.service","description":"A high performance web server"}],
            "failed":["foo.service"]},
 "packages":[{"name":"docker","version":"27.1.1","source":"bin"}]}
```

Degradation semantics: `scope` is `local` for loopback binds and `public` otherwise; `restricted` is true when most listener PIDs could not be resolved (agent running without root). `docker.available=false` carries a `reason` (`socket not found` / `permission denied` / `unreachable`). `systemd` is omitted entirely on hosts without systemctl (e.g. macOS). `websites` is empty when no supported web server (nginx / Caddy admin API / Apache) is detected. `mem_limit` 0 means "no limit". The agent is strictly read-only: no endpoint executes anything derived from request input; all inspection commands are fixed argv with hard timeouts.

## Security

The agent creates an ECDSA P-256 self-signed certificate when no paths are supplied, stores it under a reboot-stable state directory (`/var/lib/aster-agent` for root, the user config dir otherwise, overridable with `--state-dir`), and prints its DER SHA-256 fingerprint. Clients must use TOFU: show this fingerprint on first connection, store the accepted value for that machine, and reject future certificate changes. A bearer token remains required; TLS protects it only in transit.
