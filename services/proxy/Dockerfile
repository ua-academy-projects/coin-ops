# Stage 1: Build
FROM golang:1.21-alpine AS builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download

COPY . .
# Збираємо статичний бінарник без залежностей C (CGO_ENABLED=0)
RUN CGO_ENABLED=0 GOOS=linux go build -o proxy.bin .

# Stage 2: Runtime (Мікро-образ)
FROM alpine:3.19

# Додаємо кореневі сертифікати (потрібні для HTTPS запитів до NBU/CoinGecko)
RUN apk --no-cache add ca-certificates

WORKDIR /app
COPY --from=builder /app/proxy.bin .

EXPOSE 8080
CMD ["./proxy.bin"]
