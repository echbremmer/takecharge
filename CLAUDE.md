# TakeCharge

Dockerized Go + SQLite backend with a static HTML/JS frontend, all served from one container.

## Project Structure

- `main.go` — Go HTTP server (net/http + mattn/go-sqlite3), REST API + static file server on `:8080`
- `frontend/index.html` — Single-file frontend (vanilla HTML/CSS/JS, no build step)
- `Dockerfile` — Multi-stage build: golang:1.23-alpine → alpine:3.20
- `data/` — SQLite DB volume mount point (`/data/fasting.db` inside container)

## API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | /api/sessions | List all sessions (newest first) |
| POST | /api/sessions | Create a session `{start, end}` |
| DELETE | /api/sessions/:id | Delete a session |
| GET | /api/active | Get active fast (404 if none) |
| POST | /api/active | Start a fast `{start}` |
| PUT | /api/active | Update start time (dial adjust) `{start}` |
| DELETE | /api/active | Stop fast (auto-creates session) |

## Database

SQLite with WAL mode. Two tables:
- `sessions` (id, start_ms, end_ms, duration_ms)
- `active_fast` (singleton row, id=1, start_ms)

All timestamps are Unix milliseconds to match JS `Date.now()`.

## Build & Run

```bash
docker build --network host -t takecharge .
docker run -d --network host -v takecharge-data:/data takecharge
```

`--network host` is required because Docker bridge networking is disabled in `/etc/docker/daemon.json` (kernel 6.18 nftables incompatibility).

## Dev Notes

- No Go installed locally — all Go compilation happens inside the Docker build stage
- CGO is required for mattn/go-sqlite3 (gcc + musl-dev installed in build stage)
- `go.sum` is generated via `go mod tidy` during Docker build
- Frontend uses `fetch()` to `/api/*` endpoints; active fast start time cached in JS memory for timer ticking
