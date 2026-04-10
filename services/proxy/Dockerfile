# Stage 1: Build
FROM golang:1.21-alpine AS builder

# Add ca-certificates та upx for compressing the binary
RUN apk --no-cache add ca-certificates upx

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download

COPY . .
# Compile with ldflags and compress with UPX
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o proxy.bin . && \
    upx --best --lzma proxy.bin

# Stage 2: Runtime
FROM scratch

# Copy ca-certificates from the builder stage
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

WORKDIR /app
COPY --from=builder /app/proxy.bin .

EXPOSE 8080
ENTRYPOINT ["./proxy.bin"]
