# Istio の可観測性（Kiali + Prometheus）

## 仕組み: sidecar が「無料で」メトリクスを吐く

アプリに一切手を入れなくても、各 sidecar (Envoy) が通過トラフィックから
標準メトリクス（istio_requests_total 等）を生成して :15090/stats/prometheus で公開する。

```
[アプリ] ←→ [istio-proxy] --15090--> [Prometheus] ←-- [Kiali]
```

- Prometheus が全 sidecar を scrape して集約
- Kiali は Prometheus に問い合わせて**サービストポロジグラフ**を描く
- つまり Kiali 自体はトラフィックを見ていない（メトリクスの可視化レイヤ）

## 導入（学習用は Istio 公式サンプル addon が最楽）

```bash
kubectl apply -f gitops/observability/prometheus.yaml  # samples/addons から取得
kubectl apply -f gitops/observability/kiali.yaml
kubectl -n istio-system port-forward svc/kiali 20001:20001
# → http://localhost:20001/kiali
```

- サンプル addon はデモ用に resources requests が軽い／無い（小型クラスタ向き）
- 本番は kube-prometheus-stack + Kiali operator で永続化・認証を整える

## アクセスログは Telemetry API で有効化

デフォルトでは Envoy のアクセスログは無効。Phase 3 のデバッグで使った:

```yaml
apiVersion: telemetry.istio.io/v1
kind: Telemetry
metadata:
  name: mesh-default
  namespace: istio-system   # root namespace 配置で全メッシュに適用
spec:
  accessLogging:
    - providers:
        - name: envoy        # 標準出力に出る → kubectl logs で見える
```

ログの読み方（1 行に上下流の情報が全部入る）:

```
"GET / HTTP/1.1" 200 ... "app.104.…" "10.4.2.21:8080" outbound|80||frontend.baseline.svc.cluster.local
                 ↑status   ↑Host      ↑実際の宛先 Pod    ↑選ばれた Envoy cluster（ルーティング結果）
```

「どの VirtualService 判定でどこに飛んだか」は
`istioctl proxy-config routes/endpoints` と組み合わせて追う。

## デバッグの定石（Phase 3 で実際に使った手順）

1. `istioctl proxy-config routes deploy/istio-ingressgateway -n istio-ingress`
   → VS が Envoy のルートに反映されているか
2. `istioctl proxy-config endpoints ...` → 宛先クラスタに HEALTHY な endpoint がいるか
3. Telemetry でアクセスログを有効化 → リクエストがどこまで届いたか
4. ここまで全部正常なら**クラスタの外**（DNS 等）を疑う
   （実際 nip.io の誤パースが原因だった: [[../networking/02-dns]]）
