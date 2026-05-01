# Istio Traffic Management (Gateway / VirtualService / DestinationRule)

Istio で **L7 ルーティングを制御する 3 つの主要 CRD** を理解する。

## CRD とは（前提）

- **CRD = Custom Resource Definition**
- k8s に **新しいリソース型を追加する仕組み**
- VirtualService や DestinationRule は k8s 標準ではなく、Istio が CRD として
  追加した「拡張リソース」
- ユーザーから見れば普通の k8s リソースと同じく `kubectl apply -f` できる
- istiod がこれを監視し、xDS 経由で Envoy に翻訳・配布する

```
ユーザー: kubectl apply -f vs.yaml
  ↓
k8s apiserver が VirtualService リソースとして etcd に保存
  ↓
istiod が変化を監視し、内容を Envoy 設定 (xDS) に変換
  ↓
影響範囲の各 Envoy にストリームで配信
  ↓
Envoy がルーティングルールを更新
```

## 3 つの CRD の役割分担

```
[外部リクエスト]
        ↓
   ┌─ Gateway ──────────────────┐
   │ どのホスト/ポートで受けるか    │ ← Ingress 担当
   └────────┬────────────────────┘
            ↓
   ┌─ VirtualService ───────────┐
   │ どこに振り分けるか           │ ← ルーティングルール
   │ (host, path, header で分岐) │
   └────────┬────────────────────┘
            ↓
   ┌─ DestinationRule ──────────┐
   │ 振り分け先の定義             │ ← サービスのバリエーション
   │ (subset = version 別グループ)│
   └─────────────────────────────┘
            ↓
   [実 Pod (Envoy 経由)]
```

## Gateway

「**Istio Ingress Gateway という特殊な Envoy が、どのホスト/ポートで
受けるか**」を宣言する。

```yaml
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: preview-gateway
  namespace: istio-ingress
spec:
  selector:
    istio: ingressgateway   # どの ingress gateway pod に適用するか
  servers:
    - port:
        number: 80
        name: http
        protocol: HTTP
      hosts:
        - "*.<INGRESS-IP>.nip.io"   # 受ける hostname のパターン
```

ポイント:
- `selector` で「どの ingress gateway Pod に適用するか」を指定
- `hosts` でワイルドカード可
- TLS 終端も Gateway で書く（Phase 4 で扱う）

## VirtualService

「**どのリクエストをどの Service に振り分けるか**」を書く。

### 基本例

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: hello
  namespace: hello
spec:
  hosts:
    - "hello.<IP>.nip.io"   # 対象 host
  gateways:
    - istio-ingress/preview-gateway   # どの Gateway 経由
  http:
    - route:
        - destination:
            host: hello   # Service 名
            port:
              number: 80
```

### ヘッダーで分岐（スイムレーンの肝）

```yaml
spec:
  hosts:
    - frontend.baseline.svc.cluster.local
  http:
    - match:
        - headers:
            x-pr-id:
              exact: "123"
      route:
        - destination:
            host: frontend.preview-pr-123.svc.cluster.local   # PR 用
    - route:   # match に当たらないリクエスト
        - destination:
            host: frontend.baseline.svc.cluster.local        # baseline
```

ポイント:
- `match` の順序が優先順位
- `match` のないルートが「フォールバック」
- ヘッダー以外にも path、queryParams、URI、HTTP method で分岐可

### 重み付け分割（カナリア・段階リリース）

```yaml
http:
  - route:
      - destination:
          host: frontend
          subset: v1
        weight: 90
      - destination:
          host: frontend
          subset: v2
        weight: 10
```

→ 10% を v2 に流す。これが **DestinationRule の subset と組み合わさる**。

## DestinationRule

「**サービス内の Pod を subset（バリエーション）に分類**」する。
VirtualService の `subset:` で参照される。

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: frontend
  namespace: baseline
spec:
  host: frontend.baseline.svc.cluster.local
  subsets:
    - name: v1
      labels:
        version: v1     # この label を持つ Pod を subset v1 とする
    - name: v2
      labels:
        version: v2
```

ポイント:
- `labels` で Pod を絞り込む（k8s の Service と同じ仕組み）
- subset を定義しただけでは何も起きない、**VirtualService が参照して初めて使われる**
- mTLS、connection pool、circuit breaker もここで設定

## スイムレーン方式での使い分け

PR ごとのプレビュー環境（design.md §6.5）では：

```
[Ingress Gateway]
  Gateway:        host "*.<IP>.nip.io" を受ける
  VirtualService: Host から PR 番号を抽出し x-pr-id ヘッダーを付与

[各サービスの VirtualService]
  match: x-pr-id=N → preview-pr-N namespace
  fallback: baseline namespace

[各 namespace の DestinationRule]
  baseline 用: subset=baseline (label version=baseline)
  PR 用: subset=pr-N (label version=pr-N)
```

ApplicationSet が PR ごとに「VirtualService の match セクション + 該当 PR
の DestinationRule」を生成・削除することで、スイムレーンが動的に増減する。

## VirtualService の「動的ヘッダー操作」の限界

VirtualService 単体でできること:
- ヘッダーで **match**（読む）
- ヘッダーを **set / add / remove**（書く、ただし**静的な値**）
- host / path の **rewrite**

VirtualService 単体では難しいこと:
- 「**別のヘッダー値から正規表現抽出して動的に新しいヘッダーに代入**」

→ こういう「動的なヘッダー生成」が必要な場面では **EnvoyFilter + Lua**
（または Wasm Plugin）を使う。

### 例: Host から PR 番号を抽出して x-pr-id を注入

```yaml
apiVersion: networking.istio.io/v1alpha3
kind: EnvoyFilter
metadata:
  name: inject-pr-id
  namespace: istio-ingress
spec:
  configPatches:
    - applyTo: HTTP_FILTER
      match:
        context: GATEWAY
      patch:
        operation: INSERT_BEFORE
        value:
          name: envoy.lua
          typed_config:
            "@type": type.googleapis.com/envoy.extensions.filters.http.lua.v3.Lua
            inline_code: |
              function envoy_on_request(request_handle)
                local host = request_handle:headers():get(":authority")
                local pr = string.match(host, "pr%-(%d+)%.")
                if pr then
                  request_handle:headers():add("x-pr-id", pr)
                end
              end
```

EnvoyFilter は **Envoy の生 API を直接叩く**ので強力だが、Istio の
バージョンアップで API 互換性が変わる可能性がある。Phase 3 で実装する。

## デバッグ Tips

### Envoy に実際に配布された設定を見る
```bash
istioctl proxy-config routes <pod-name>.<namespace>
istioctl proxy-config clusters <pod-name>.<namespace>
istioctl proxy-config endpoints <pod-name>.<namespace>
```

### マニフェストの妥当性チェック
```bash
istioctl analyze -n <namespace>
```

### よくあるハマり
- `Gateway` と `VirtualService` が **異なる namespace** にあって `gateways:` の参照ミス
- `match` の順序が逆で fallback が常に勝つ
- `host:` を FQDN で書くべきところを短縮形にして DR と一致しない

## 関連リンク

- Istio Traffic Management: https://istio.io/latest/docs/concepts/traffic-management/
- VirtualService API: https://istio.io/latest/docs/reference/config/networking/virtual-service/
- DestinationRule API: https://istio.io/latest/docs/reference/config/networking/destination-rule/
