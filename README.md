# TakeCharge

A simple self hosted habit tracker with a Go + SQLite backend and a single-page frontend, packaged in one Docker container.

## Features

- Start/stop fasting sessions with a single button
- Adjust start time with a rotary dial (drag, scroll, or touch)
- View fasting history with duration, timestamps, and estimates for water weight and fat loss
- Data persists across container restarts via SQLite

## Quick Start

Create a `docker-compose.yml`:

```yaml
services:
  app:
    image: takecharge/takecharge:0.9.0
    ports:
      - "8080:8080"
    volumes:
      - takecharge-data:/data
    restart: unless-stopped

volumes:
  takecharge-data:
```

Then run:

```bash
docker compose up -d
```

Open http://localhost:8080

## Build from Source

```bash
docker build -t takecharge .
docker run -d -p 8080:8080 -v takecharge-data:/data takecharge
```

## API

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/habits` | List all habit types |
| `GET` | `/api/habits/:habit/sessions` | List sessions (newest first) |
| `POST` | `/api/habits/:habit/sessions` | Create a session `{start, end}` |
| `PUT` | `/api/habits/:habit/sessions/:id` | Edit a session |
| `DELETE` | `/api/habits/:habit/sessions/:id` | Delete a session |
| `GET` | `/api/habits/:habit/active` | Get active session (404 if none) |
| `POST` | `/api/habits/:habit/active` | Start a session `{start}` |
| `PUT` | `/api/habits/:habit/active` | Update start time `{start}` |
| `DELETE` | `/api/habits/:habit/active` | Stop session (auto-creates session) |

## Stack

- **Backend:** Go, net/http, mattn/go-sqlite3
- **Frontend:** Vanilla HTML/CSS/JS (single file)
- **Database:** SQLite with WAL mode
- **Container:** Multi-stage Docker build (golang:1.23-alpine → alpine:3.20)
