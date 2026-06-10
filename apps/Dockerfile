# frontend / backend 共用の multi-stage Dockerfile。
#   docker build --build-arg SERVICE=frontend -t .../frontend:TAG apps/
FROM golang:1.26 AS build
ARG SERVICE
WORKDIR /src
COPY go.mod ./
COPY . .
# 静的リンク（CGO 無効）にして distroless static で動かす
RUN CGO_ENABLED=0 go build -o /bin/app ./cmd/${SERVICE}

# distroless: シェルもパッケージマネージャも無い最小イメージ（攻撃面と容量の削減）
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /bin/app /app
EXPOSE 8080
ENTRYPOINT ["/app"]
