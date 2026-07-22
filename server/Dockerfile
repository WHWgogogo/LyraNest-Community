FROM golang:1.22-alpine AS build

ARG GOPROXY=https://proxy.golang.org,direct
ENV GOPROXY=${GOPROXY}

WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /out/music-player-server ./cmd/server

FROM alpine:3.20

LABEL org.opencontainers.image.title="LyraNest Community Server" \
      org.opencontainers.image.version="1.0.0"

WORKDIR /app
RUN apk add --no-cache ca-certificates tzdata \
    && adduser -D -H -u 10001 appuser
COPY --from=build /out/music-player-server /usr/local/bin/music-player-server
USER appuser

ENV SERVER_ADDR=:8080 \
    GOMEMLIMIT=192MiB \
    GOGC=100
EXPOSE 8080

ENTRYPOINT ["music-player-server"]
