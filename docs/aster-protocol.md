# Aster Agent Protocol v1

All endpoints require `Authorization: Bearer <token>` and are available only over HTTPS.
Values are JSON `snake_case`; byte quantities are bytes and percentages use `0…100`.

| Endpoint | Response |
| --- | --- |
| `GET /v1/meta` | Host static metadata, agent version and collection interval. |
| `GET /v1/metrics` | The latest complete metric frame. |
| `GET /v1/history?since=<unix_ts>` | History frames strictly newer than `since`. |

```json
{"timestamp":1710000000,"cpu_usage":12.5,"memory":{"used":123,"total":456},"network":{"up":42,"down":81,"total_up":1000,"total_down":2000},"load":{"load1":0.5,"load5":0.4,"load15":0.3}}
```

`401 {"error":"unauthorized"}` indicates a missing or incorrect bearer token. An unparsable `since` parameter returns `400 {"error":"invalid since"}`.

Collection cadence: CPU/memory/disk/network refresh every 2 s; connection and process counts refresh every 10 s (socket/process table walks are expensive on busy servers), so those two fields may lag by up to 10 s. History samples are recorded every 30 s and retained for `--history-minutes`.

## Security

The agent creates an ECDSA P-256 self-signed certificate when no paths are supplied, stores it under a reboot-stable state directory (`/var/lib/aster-agent` for root, the user config dir otherwise, overridable with `--state-dir`), and prints its DER SHA-256 fingerprint. Clients must use TOFU: show this fingerprint on first connection, store the accepted value for that machine, and reject future certificate changes. A bearer token remains required; TLS protects it only in transit.
