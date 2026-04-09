FROM golang:1.22-bookworm AS builder

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o proxy .

FROM gcr.io/distroless/static-debian12:nonroot

WORKDIR /
COPY --from=builder /app/proxy /proxy

EXPOSE 8080
USER nonroot:nonroot

ENTRYPOINT ["/proxy"]
