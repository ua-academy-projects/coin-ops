# BUILDER STAGE

FROM golang:1.22-alpine AS builder

WORKDIR /app

# copy go.mod and go.sum to the working directory (/app/go.mod and /app/go.sum)
COPY go.mod go.sum .

# download dependencies based on go.mod and go.sum, this will create a cache layer for dependencies, 
# so if there are no changes in go.mod and go.sum, the dependencies will not be downloaded again in the next build, which can speed up the build process
RUN go mod download

COPY . .

# go build -o history_service main.go: Build the Go application and output the binary as history_service
# -ldflags="-s -w": This flag is used to reduce the size of the binary file
RUN go build -ldflags="-s -w" -o history_service main.go


# RUNTIME STAGE

# a very small linux distribution, used commonly for lightweight docker images/containers
FROM alpine:3.20

WORKDIR /app

# copy from the builder stage, the history_service binary from /app/history_service in the builder stage to the current working directory (/app) in this stage
#  copy built app from build stage into final runtime image.
COPY --from=builder /app/history_service .

EXPOSE 5002

CMD ["./history_service"]