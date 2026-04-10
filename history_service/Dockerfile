# Stage 1 — Build Go binary
FROM golang:1.22 AS builder

WORKDIR /app

# Copy dependency files first (layer caching)
COPY go.mod go.sum ./

# Download dependencies
RUN go mod download

# Copy source code
COPY main.go .

# Compile binary — CGO_ENABLED=0 makes it fully static
RUN CGO_ENABLED=0 GOOS=linux go build -o history_service .

# Stage 2 — Run with minimal image
FROM debian:bookworm-slim

WORKDIR /app

# Copy only the compiled binary
COPY --from=builder /app/history_service .

CMD ["./history_service"]
