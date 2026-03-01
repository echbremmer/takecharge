# Stage 1: Build Go binary
FROM golang:1.23-alpine AS builder

RUN apk add --no-cache gcc musl-dev

WORKDIR /build
COPY go.mod main.go ./
RUN go mod tidy && CGO_ENABLED=1 go build -o fasting-tracker .

# Stage 2: Runtime
FROM alpine:3.20

RUN apk add --no-cache ca-certificates

WORKDIR /app
COPY --from=builder /build/fasting-tracker .
COPY frontend/ frontend/

RUN mkdir -p /data
VOLUME /data

EXPOSE 8080
CMD ["./fasting-tracker"]
