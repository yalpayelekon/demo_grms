# testcomm_go

Go implementation of TestComm bridge for legacy bridge compatibility.

## Demo RCU configuration

Environment variables:

- `TESTCOMM_DEMO_RCU_HOST` (default: `192.168.1.114`)
- `TESTCOMM_DEMO_RCU_PORT` (default: `5556`)
- `TESTCOMM_DB_PATH` (optional SQLite path for service events)
- `TESTCOMM_PORT` (default: `8082`)
- `TESTCOMM_KILL_PREVIOUS` - when port is in use, the server attempts to terminate the process using the port and then retries (Windows only). Set to `0` or `false` to disable.
- `TESTCOMM_LOG_FILE` (optional): log file path. The file is recreated with truncate mode on every startup.
- `TESTCOMM_DISABLE_REFRESH` (optional, `1`/`true`): disables refresh paths temporarily so only command sends (for example scene trigger) are active.
- `TESTCOMM_SCENE_REQUIRE_RESPONSE` (optional, default `0`/`false`): when enabled, scene calls wait for device response (`status=confirmed`). Default fast mode sends write-only and returns `status=accepted`.

Runtime override:

- `GET /testcomm/settings/demo-rcu` returns the active Demo 101 host/port.
- `PUT /testcomm/settings/demo-rcu` updates and persists the Demo 101 host/port to `<config>/demo-rcu.json`.
- A saved config file takes precedence over the environment defaults on next startup.

## Run

```powershell
cd testcomm_go
go run .
```

If port 8082 is already in use, either set `TESTCOMM_KILL_PREVIOUS=1` and run again, or use the helper script (kills any process on the port then starts the server):

```powershell
.\run.ps1
```

Server default URL:

- `http://localhost:8082`

Main endpoints:

- `GET /testcomm/rooms/Demo%20101`
- `GET /testcomm/rooms/Demo%20101/stream` (SSE snapshots)
- `GET /testcomm/rooms/Demo%20101/lighting/devices`
- `POST /testcomm/rooms/Demo%20101/lighting/level`
- `GET|PUT /testcomm/rooms/Demo%20101/hvac`

## Expected startup logs

- `startup.room_config room=Demo 101 host=... port=...`
- `rcu.client.created room=Demo 101 ...`
- `rcu.connect room=Demo 101 ...`
- `rcu.initialized room=Demo 101 outputs=...`

If the RCU is temporarily unavailable, snapshot handlers return cached stale payloads when available; control handlers return explicit 502 errors.
