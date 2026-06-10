# ヘッダーベースルーティング（スイムレーン実装）

Phase 3 で実装した x-pr-id スイムレーンの仕組み。設計判断は [[../../adr/0003-swimlane-routing]]。

## 全体の流れ

```
ブラウザ → pr-42.<IP>.nip.io
  ↓ ① Ingress Gateway: preview-entry VS が Host にマッチ
  ↓    → x-pr-id: 42 をリクエストヘッダーに静的注入
  ↓    → frontend.preview-pr-42 へルーティング
frontend (PR 版)
  ↓ ② アプリの swimlane ミドルウェアが x-pr-id を伝播しつつ
  ↓    BACKEND_URL = backend.baseline.svc.cluster.local を呼ぶ
  ↓ ③ frontend の sidecar: backend-swimlane VS (exportTo ".") が
  ↓    x-pr-id == "42" にマッチ → backend.preview-pr-42 へ振り替え
backend (PR 版)
```

baseline (`app.<IP>.nip.io`) は ① で何も注入されないため、
③ のフォールバック route で baseline の backend に落ちる。

## 使った Istio の機能

### 1. VS でのリクエストヘッダー注入（静的）

```yaml
http:
  - headers:
      request:
        set:
          x-pr-id: "42"
    route: [...]
```

- **VS は Host から値を抽出してヘッダーに変換することはできない**
  （正規表現キャプチャ → ヘッダー生成は EnvoyFilter + Lua の領域）。
- そのため「PR ごとに静的な値を埋めた VS を生成する」方式を取る。
  生成は ApplicationSet の kustomize patch が担う。

### 2. ヘッダーマッチでの分岐

```yaml
http:
  - match:
      - headers:
          x-pr-id:
            exact: "42"     # ほかに prefix / regex がある
    route: [PR 版へ]
  - route: [baseline へ]     # match なし = デフォルト
```

ルールは**上から順に評価**され最初にマッチした route が使われる。
デフォルト route（match なし）を必ず最後に置く。

### 3. exportTo によるスコープ制御

```yaml
spec:
  hosts: ["backend.baseline.svc.cluster.local"]
  exportTo: ["."]   # 自 namespace の sidecar からのみ見える
```

「baseline 宛て通信の乗っ取り」を PR namespace 内に閉じる要。
これが無いと全 namespace の sidecar にこの VS が配られ、
同一 host に複数 VS が定義されて優先順位が不定になる。

### 4. destination 短縮名の namespace 相対解決

VS の `destination.host: backend`（短縮名）は **VS が置かれた namespace** を
基準に FQDN 化される。テンプレート overlay を namespace 差し替えだけで
使い回すのに利用した。意図しない解決を避けるため、
「明示的に baseline に送る」route は必ず FQDN で書くこと。

## ハマりポイント（実際に設計で対処したもの）

| 問題 | 対処 |
|---|---|
| 2 ホップ目から baseline に逃げる | アプリの伝播ミドルウェア必須（Envoy はヘッダーを自動転送しない） |
| 他レーンへの影響 | exportTo "." で VS のスコープを閉じる |
| Gateway の hosts 不一致で 404 | 共有 Gateway は `*.<IP>.nip.io` ワイルドカードで受ける |

## なぜ Envoy はヘッダーを自動転送しないのか

sidecar は「リクエスト単位」で動くが、アプリ内で受信→送信の間の
対応関係（このレスポンスのためにどの送信をしたか）は HTTP からは見えない。
トレースコンテキストの伝播がアプリ責務なのと同じ理屈で、
x-pr-id もアプリ（共通ミドルウェア）が引き回すしかない。
OpenTelemetry の baggage 伝播はこれを標準化したもの（[[../observability/01-otel-baggage]]）。
