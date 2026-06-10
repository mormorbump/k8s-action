# DNS: nip.io とクラスタ内 DNS

## nip.io の仕組み

`nip.io` は「ホスト名に埋め込まれた IP をそのまま A レコードで返す」だけのパブリック DNS サービス。

```
hello.104.154.128.86.nip.io  →  104.154.128.86
pr-42.104.154.128.86.nip.io  →  104.154.128.86
```

- どんなサブドメインでも `<何か>.<IP>.nip.io` は `<IP>` に解決される
- **DNS 設定・ドメイン購入なしで Host ベースルーティングを試せる**のが利点
- Istio 側は Host ヘッダーだけ見て分岐するので、全ホストが同じ IP を指していて良い
  （= ワイルドカード DNS と同じ役割を無料で果たす）

### Phase 1-C で実際に使った形

```
curl http://hello.104.154.128.86.nip.io/
  → DNS: 104.154.128.86 (Ingress Gateway の External IP) に解決
  → Envoy が Host ヘッダー hello.104.154.128.86.nip.io を見て
  → Gateway/VirtualService の hosts にマッチ → hello Service へ
```

### 落とし穴

| 症状 | 原因 | 対策 |
|---|---|---|
| 名前解決できない | DNS over HTTPS / 社内 DNS が nip.io を遮断 | `/etc/hosts` に直接書く |
| 404 が返る | Gateway/VS の hosts と Host ヘッダー不一致 | `curl -v` で Host を確認 |
| たまに解決失敗 | nip.io はベストエフォート運用 | 本番では使わない（学習・デモ専用） |

## クラスタ内 DNS との関係

クラスタ内部は CoreDNS が `<svc>.<ns>.svc.cluster.local` を ClusterIP に解決する
（[[../k8s/03-networking]] 参照）。nip.io は**クラスタ外のクライアント**が
Ingress Gateway へ辿り着くための外部 DNS であり、層が違う:

```
[ブラウザ] --nip.io(外部DNS)--> [Ingress Gateway] --cluster.local(CoreDNS)--> [Service]
```

## AWS との比較

ECS + ALB 構成なら Route 53 にワイルドカード A レコード（`*.preview.example.com → ALB`）を
張るのが相当。nip.io はその「ワイルドカード DNS ゾーン」を即席で借りるイメージ。
