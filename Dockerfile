# Stage 1: Build Go binary
FROM golang:1.23-alpine AS go-builder

RUN apk add --no-cache gcc musl-dev

WORKDIR /build
COPY go.mod main.go ./
RUN go mod tidy && CGO_ENABLED=1 go build -o fasting-tracker .

# Stage 2: Build Flutter web
FROM ghcr.io/cirruslabs/flutter:stable AS flutter-builder

WORKDIR /flutter_build
COPY flutter_app/ .
RUN flutter pub get && flutter build web --release

# Stage 3: Runtime
FROM alpine:3.20

RUN apk add --no-cache ca-certificates

WORKDIR /app
COPY --from=go-builder /build/fasting-tracker .
# Flutter web output replaces the old frontend/
COPY --from=flutter-builder /flutter_build/build/web/ frontend/

RUN mkdir -p /data
VOLUME /data

EXPOSE 8080
CMD ["./fasting-tracker"]
