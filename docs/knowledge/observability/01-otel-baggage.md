# OpenTelemetry baggage と分散トレース

マイクロサービス間で「文脈」を引き継ぐ仕組み。スイムレーン方式で
`x-pr-id` を全サービスに伝播させるための基盤。

## 分散トレーシングとは

マイクロサービスでは 1 リクエストが複数サービスを通過する：

```
ユーザー → frontend → backend → DB
                  ↘ cache
```

各サービスのログだけ見ても「**どのリクエストがどのログに対応してるか**」
が分からない。

### 仕組み

リクエストに `Trace ID` を発行し、各サービスがその ID を引き継いでログに
記録 + 各処理の所要時間（**span**）を計測する。

```
[trace_id=abc123]
  frontend       50ms     ← 1 つの span
    └ backend    30ms     ← 子 span（親が frontend）
        └ DB     25ms     ← 孫 span
    └ cache      5ms      ← 別の子 span
```

これが**分散トレース**。span のツリー構造が「リクエストの旅」を表現する。

### ツール例

| ツール | 種類 |
|---|---|
| Jaeger | OSS、UI 同梱 |
| Zipkin | OSS、Twitter 発祥 |
| Tempo | Grafana Labs 製 |
| Cloud Trace | GCP マネージド |

## OpenTelemetry (OTel) とは

**分散トレース・メトリクス・ログを統一する業界標準の仕様**。

歴史:
- OpenTracing と OpenCensus が合流して 2019 年に誕生
- CNCF プロジェクト
- W3C Trace Context が伝播フォーマットの標準

### コアコンセプト

| 概念 | 内容 |
|---|---|
| **Trace** | 1 リクエストの全体（複数 span を含む木構造） |
| **Span** | 1 サービスでの 1 処理（開始時刻、終了時刻、属性を持つ） |
| **Context** | trace ID と span ID をプロセス内で持ち回るもの |
| **Propagator** | プロセス間で context を伝播する仕組み（HTTP ヘッダー等） |

## W3C Trace Context（HTTP 伝播フォーマット）

W3C 標準のヘッダー：

```
traceparent: 00-<trace-id>-<parent-span-id>-<flags>
tracestate:  vendor1=opaqueValue,vendor2=opaqueValue
```

例:
```
traceparent: 00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01
```

- `00`: バージョン
- `0af7...`: 16 バイトの trace ID
- `b7ad...`: 8 バイトの span ID
- `01`: flag（sampled 等）

各サービスは受け取った `traceparent` から trace ID を継承し、自分の
span を作って下流に新しい `traceparent` を送る。

## Baggage（任意のキー値伝播）

OTel の baggage は **「アプリ用の任意のキー・値をリクエストに添付して
全サービスに伝播」** できる機能。

```
baggage: pr-id=123,user-tier=premium,region=jp
```

- W3C Baggage 仕様で標準化
- HTTP ヘッダー `baggage` で運ばれる
- アプリ側 SDK が context に出し入れする
- **trace ID とは別物**だが、伝播の仕組みは似ている

### スイムレーン方式での使い方

`x-pr-id` を baggage に乗せて全サービスに伝播させる：

```
ユーザー → Gateway: x-pr-id: 123 を付与
  ↓
Gateway → frontend: x-pr-id: 123 もしくは baggage: pr-id=123
  ↓ (frontend 内で OTel SDK が baggage に変換)
frontend → backend: baggage: pr-id=123 が自動付与される
  ↓
backend が baggage を読んで処理を分岐
```

## 設計書の方針（design.md §6.3, §6.6）

今回は「**`x-pr-id` を主、内部的に baggage にも入れる**」ハイブリッド：

| 場所 | 使うもの | 理由 |
|---|---|---|
| Istio の match | `x-pr-id` ヘッダー直接 | Istio VirtualService の match は素のヘッダーを見る方が単純 |
| アプリ間伝播 | OTel baggage | SDK で自動伝播するので実装が楽 |
| 共通ミドルウェア | `x-pr-id` ↔ baggage 変換 | Istio が見るのは `x-pr-id`、OTel が運ぶのは baggage、両方を相互変換 |

## Go での最小実装イメージ

```go
import (
    "go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
    "go.opentelemetry.io/otel"
    "go.opentelemetry.io/otel/propagation"
)

func init() {
    // TraceContext と Baggage の両方を伝播
    otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
        propagation.TraceContext{},
        propagation.Baggage{},
    ))
}

// 受信: net/http に otelhttp.NewHandler を被せる
http.Handle("/", otelhttp.NewHandler(myHandler, "frontend"))

// 送信: http.Client の Transport に otelhttp.NewTransport を被せる
client := &http.Client{
    Transport: otelhttp.NewTransport(http.DefaultTransport),
}
```

これだけで「受け取った trace ID と baggage を保持し、下流に送る」が成立。

## 共通ミドルウェアでやること（Phase 3 で実装）

```
受信時:
  - x-pr-id ヘッダーを読む
  - baggage に pr-id=N を入れる
  - context に保存

送信時:
  - context から pr-id を取り出す
  - x-pr-id ヘッダーをセット (Istio 用)
  - baggage に pr-id=N を入れる (OTel 用)
```

## ハマりポイント（design.md §6.7）

| 症状 | 対策 |
|---|---|
| 1 ホップ目は PR 版に行くが、2 ホップ目から baseline に逃げる | OTel Composite propagator + 共通 middleware で `x-pr-id` を必ず引き回す |
| trace ID が途切れる | propagator の設定漏れ、HTTP client が otelhttp transport を使っていない |
| baggage が「特殊なキャラ」で壊れる | URL エンコードが必要、SDK は自動でやってくれる |

## 関連リンク

- OpenTelemetry: https://opentelemetry.io/docs/
- W3C Trace Context: https://www.w3.org/TR/trace-context/
- W3C Baggage: https://www.w3.org/TR/baggage/
- otelhttp (Go): https://pkg.go.dev/go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp
