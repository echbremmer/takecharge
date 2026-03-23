# TakeCharge — Flutter App

Mobile app for [TakeCharge](../README.md), a personal habit tracker. Supports timer habits, daily targets, and todo lists. The app communicates with the Go backend over HTTP — the Docker container must be running before you launch the app.

## Prerequisites

- [Flutter](https://docs.flutter.dev/get-started/install) SDK (stable channel)
- Android emulator / device, or iOS device (iOS requires macOS + Xcode)
- TakeCharge Docker container running on the same network

## 1. Start the backend

From the repo root:

```bash
docker build --network host -t takecharge .
docker run -d --network host -v takecharge-data:/data --name takecharge takecharge
```

The backend listens on port `8080`. On an Android emulator, `localhost:8080` reaches the host machine directly. On a physical device, replace `localhost` with your machine's local IP (see below).

## 2. Install dependencies

```bash
flutter pub get
```

## 3. Run the app

**Android emulator (default):**
```bash
flutter run
```

**Specific device:**
```bash
flutter devices          # list available devices
flutter run -d <device-id>
```

**Physical device on a local network:**

Pass your machine's local IP as the API base URL:

```bash
flutter run --dart-define=API_BASE=http://192.168.x.x:8080
```

## Project structure

```
lib/
  api/          # HTTP client (Dio) and API methods
  providers/    # Riverpod state providers
  screens/      # One file per screen
  widgets/      # Shared UI components
  main.dart     # App entry, theme, startup auth check
  router.dart   # go_router navigation
```

## Key packages

| Package | Purpose |
|---|---|
| `flutter_riverpod` | State management |
| `go_router` | Navigation |
| `dio` + `dio_cookie_manager` | HTTP requests + cookie-based auth |
| `google_fonts` | Manrope + Plus Jakarta Sans fonts |
