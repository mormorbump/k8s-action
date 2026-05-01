# k8s ネットワークの基本（Service / Ingress と Istio の住み分け）

k8s が標準で持つネットワーク機能と、Istio が補う L7 機能の境界を整理する。

## レイヤーの全体像

```
┌─ 外部からのリクエスト ──────────────────────────┐
│                                                │
│  L7 (HTTP) Gateway / Ingress                   │
│    ├ k8s 標準: Ingress リソース                │
│    └ Istio:    Gateway + VirtualService       │ ← 今回採用
│                                                │
│  L4 (TCP/UDP) Service                          │
│    ├ ClusterIP    (クラスタ内専用)              │
│    ├ NodePort     (ノードのポート公開)           │
│    ├ LoadBalancer (クラウド LB を作る)          │
│    └ ExternalName (DNS CNAME 相当)             │
│                                                │
│  L3 Pod IP (CNI plugin が割当)                  │
│                                                │
└────────────────────────────────────────────────┘
```

## Service の役割

### なぜ Service が必要か

- Pod は「使い捨て」: スケール、再起動、再スケジュールで IP が変わる
- アプリは「呼び先の IP」を持っていられない
- → **安定した仮想 IP と DNS 名**が要る = Service

### Service の種類

| 種類 | 用途 | 動作 |
|---|---|---|
| **ClusterIP**（デフォルト） | クラスタ内通信 | 仮想 IP を割当、kube-proxy が iptables で Pod に分散 |
| **NodePort** | 開発・デバッグ | 全ノードの 30000-32767 のポートを開ける |
| **LoadBalancer** | 本番外部公開 | クラウド LB を自動作成（GCP なら Forwarding Rule） |
| **ExternalName** | 外部 DNS 参照 | DNS CNAME を返すだけ |

### kube-proxy の挙動（ClusterIP）

```
[Pod A: frontend]
   │
   │ ① app.go が "http://backend:8080" を呼ぶ
   ↓
[Pod A の libc + DNS resolver]
   │
   │ ② "backend.<ns>.svc.cluster.local" を CoreDNS に問い合わせ
   ↓
[CoreDNS (cluster の DNS)]
   │
   │ ③ ClusterIP を返す  例: 10.8.0.42
   ↓
[Pod A の OS]
   │
   │ ④ 10.8.0.42:8080 宛にパケット送出
   ↓
[Worker Node のカーネル: iptables ルールにヒット]
   │
   │ ⑤ 「dst=10.8.0.42:8080」にマッチ
   │    → ランダムに 1 つ選ぶ:
   │       - 10.4.1.5:8080  (Pod B-1)
   │       - 10.4.1.6:8080  (Pod B-2)
   │       - 10.4.2.3:8080  (Pod B-3)
   │    → DNAT (宛先 IP/Port を書き換え)
   ↓
[実 Pod B に届く]
```

つまり Service 自体は「IP の対応表」、実体のロードバランシングは
**iptables ルール + ランダム選択**。L7 機能（ヘッダー分岐等）は持てない。

### iptables とは（補足）

**Linux カーネル組込みのパケットフィルタ・NAT 機構**。カーネル内のネット
ワーク処理フックポイントに「ルールチェーン」を仕込めるツール。

| 機能 | 説明 | 用途例 |
|---|---|---|
| ファイアウォール | パケットを通す / 捨てる | セキュリティ |
| **NAT** | 宛先 IP を別の IP に書き換え | **kube-proxy はこれ** |
| マスカレード | 送信元 IP を書き換え | 外部接続時 |

kube-proxy が起動時に「Service ごとに 1 ルール」を書き込む。Service が
増えれば iptables ルールも増える（IPVS モードに切り替えると O(1) で
スケールする）。

**重要**: iptables は **L3/L4（IP / TCP）レベル**で動く。**L7（HTTP
ヘッダー）は見えない**。だから「ヘッダーで分岐」は iptables だけでは
不可能。Istio (Envoy) はこの上のレイヤーで動いている。

## Ingress（k8s 標準）

L7 ルーティングを行う標準リソース。Host / Path で振り分け。

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app
spec:
  rules:
    - host: app.example.com
      http:
        paths:
          - path: /api
            backend:
              service:
                name: backend
                port: { number: 8080 }
```

実装は **Ingress Controller**（nginx-ingress、GCE ingress、Contour 等）。
Ingress リソースを読んで、各実装が独自にプロキシ設定する。

### k8s Ingress の限界

- ヘッダーベースのルーティングは標準仕様にない（実装拡張で実現することは多い）
- リトライ・タイムアウト・サーキットブレーカー・mTLS 等は対象外
- annotation に依存して仕様が controller ごとに異なる
- → 本格的な L7 制御には不十分。**サービスメッシュへ**

## Istio の Gateway / VirtualService（k8s Ingress の置き換え）

Istio は「k8s Ingress ではなく Gateway + VirtualService を使え」と主張する。
詳細は `istio/02-traffic-management.md` に書くが、要点だけ：

- **Gateway**: Ingress 用 Envoy が「どのホスト/ポートを受けるか」
- **VirtualService**: 「ホスト/パスをどう backend に振り分けるか」
- **DestinationRule**: 「backend の subset（version 別グループ）の定義」

ヘッダーベースの分岐、トラフィック分割、リトライ、タイムアウト、すべて
標準で書ける。

## DNS（クラスタ内）

CoreDNS が `cluster.local` ドメインを管理。

```
<service>.<namespace>.svc.cluster.local
```

短縮形:
- 同 namespace なら `<service>` だけ
- 別 namespace なら `<service>.<namespace>`

例: `baseline` ns の `backend` Service →
`backend.baseline.svc.cluster.local` でアクセス可能。

`/etc/resolv.conf` に search path が入っているので短縮形でも引ける：

```
search <ns>.svc.cluster.local svc.cluster.local cluster.local
nameserver <CoreDNS の ClusterIP>
```

## CNI と Pod IP

- CNI = Container Network Interface
- Pod に IP を割り当て、ノード間で通信できるようにするプラグイン規格
- GKE は VPC-native モードで GKE 専用 CNI を使う（Pod IP も VPC の IP）

### VPC-native (IP alias)
- Pod が VPC のセカンダリ IP 範囲から IP をもらう
- VPC 内の他リソースから Pod に直接到達可能
- 今回はこれを採用

### 関連 knowledge
- `networking/01-cni-overlay.md`: CNI と overlay の概念詳細
- `networking/05-cidr-design.md`: GKE の CIDR サイジング

## まとめ：k8s と Istio の住み分け

| 機能 | k8s 標準 | Istio |
|---|---|---|
| Pod IP 割当 | CNI（GKE 内蔵） | - |
| L4 ロードバランシング | Service (kube-proxy + iptables) | - |
| 外部公開 | Service type=LoadBalancer + Ingress | Gateway |
| L7 ルーティング | Ingress（限定的） | VirtualService（豊富） |
| **ヘッダーベース分岐** | × | ✅ |
| リトライ・タイムアウト | × | ✅ |
| mTLS | × | ✅ |
| 観測（メトリクス・トレース） | △ | ✅ |

→ Istio は **「k8s の足りない L7 を補う層」**。

## 関連リンク

- k8s Service: https://kubernetes.io/docs/concepts/services-networking/service/
- k8s Ingress: https://kubernetes.io/docs/concepts/services-networking/ingress/
- GKE VPC-native: https://cloud.google.com/kubernetes-engine/docs/concepts/alias-ips
