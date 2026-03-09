# TakeCharge

A simple fasting tracker with a Go + SQLite backend and a single-page frontend, packaged in one Docker container.

## Features

- Start/stop fasting sessions with a single button
- Adjust start time with a rotary dial (drag, scroll, or touch)
- View fasting history with duration, timestamps, and estimates for water weight and fat loss
- Data persists across container restarts via SQLite

## Quick Start

```bash
docker build --network host -t takecharge .
docker run -d --network host -v takecharge-data:/data takecharge
```

Open http://localhost:8080

## API

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/sessions` | List all sessions (newest first) |
| `POST` | `/api/sessions` | Create a session `{start, end}` |
| `DELETE` | `/api/sessions/:id` | Delete a session |
| `GET` | `/api/active` | Get active fast (404 if none) |
| `POST` | `/api/active` | Start a fast `{start}` |
| `PUT` | `/api/active` | Update start time `{start}` |
| `DELETE` | `/api/active` | Stop fast (auto-creates session) |

## Stack

- **Backend:** Go, net/http, mattn/go-sqlite3
- **Frontend:** Vanilla HTML/CSS/JS (single file)
- **Database:** SQLite with WAL mode
- **Container:** Multi-stage Docker build (golang:1.23-alpine → alpine:3.20)
