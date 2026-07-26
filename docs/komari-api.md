# Komari API verification notes

Source snapshot: `Snapshot-2607241337` from `komari-monitor/komari`.

## Route verification

The server router binds these public endpoints directly:

| Endpoint | Handler / RPC binding | Aster usage |
| --- | --- | --- |
| `GET /api/version` | `public:getVersion` | Connection test |
| `GET /api/nodes` | `public:getNodesInformation` | Node metadata |
| `GET /api/records/load?uuid={uuid}&hours={hours}` | `public:getRecordsByUUID` | Detail history |
| `GET /api/clients` (WebSocket) | `api.GetClients` | Current metrics; client sends `get` |

The source comments in `web/router/router.go` explicitly describe `/api/clients` as a non-RPC WebSocket and document the `get` / `get <uuid>` handshake.

## Sanitized protocol examples

```http
GET /api/nodes
```

```json
{"status":"success","data":[{"uuid":"<uuid>","name":"node-a","os":"Debian","region":"🇯🇵","group":"edge","tags":"prod;api"}]}
```

```text
WebSocket /api/clients
client -> "get"
server -> {"status":"success","data":{"online":["<uuid>"],"data":{"<uuid>":{"cpu":{"usage":12.5},"ram":{"total":1024,"used":512},"network":{"up":1,"down":2}}}}}
```

## Unit mapping

- `cpu.usage` is a percentage.
- `ram`, `swap`, `disk`, and all network counters/speeds are bytes; network `up` / `down` are bytes per second.
- Aster converts used/total byte pairs to percentage and stores displayed network values as bytes per second.

## Local runtime status

The repository cloned successfully and route bindings were checked from source. The local Go build could not finish in this environment because dependency retrieval did not produce a server binary, so the examples above are source-verified rather than captured from a live node.
