# AWS ECS と k8s / Istio の概念対応表

「ECS の経験はあるが k8s は初」のときに使う対訳辞書。
どこが対応していて、どこが「隠蔽 vs 露出」で違うかを整理する。

## 用語の対応（コアコンセプト）

| AWS (ECS / Fargate 中心) | k8s + Istio | 補足 |
|---|---|---|
| ECS Cluster | k8s Cluster | クラスタという単位は同じ |
| ECS Task | k8s **Pod** | 最小実行単位、複数コンテナを同居可 |
| ECS Task Definition | k8s **Deployment** + **PodTemplate** | 「どう動かすか」のテンプレ |
| ECS Service | k8s **Deployment** + **Service** | Task の数を維持、ALB に登録 |
| ECS Container | k8s **Container** | 同じ |
| Container Instance (EC2 backed) | k8s **Node** | ECS on EC2 の VM、k8s の Worker Node に相当 |
| Capacity Provider | k8s **Node Pool** | スケール元になるグループ |
| ECS Service Discovery (Cloud Map) | k8s **Service + CoreDNS** | DNS ベースの仲介 |
| ALB / NLB (target group) | k8s **Service type=LoadBalancer** + **Ingress** / **Istio Gateway** | 外部公開 |
| ALB のリスナールール (path, host) | k8s **Ingress** rules / Istio **VirtualService** | L7 ルーティング |
| AWS App Mesh | **Istio** | サービスメッシュ |
| Envoy (App Mesh のデータプレーン) | **Envoy (Istio sidecar)** | 同じ Envoy |
| App Mesh Controller | **istiod** | コントロールプレーン |
| ECR (Elastic Container Registry) | **Artifact Registry** / GCR | コンテナイメージリポジトリ |
| IAM Roles for Tasks (ECS task role) | **Workload Identity** (KSA ↔ GSA) | Pod から AWS/GCP API への認証 |
| Secrets Manager / Parameter Store | k8s **Secret** + External Secrets Operator | 機密情報の注入 |
| CloudWatch Logs | k8s **container stdout** + log collector (Fluentd 等) | ログ収集 |
| CloudWatch Metrics | **Prometheus** / Cloud Monitoring | メトリクス |
| X-Ray | **Jaeger / Tempo** (OTel) | 分散トレース |
| Application Auto Scaling | **HPA / VPA / Cluster Autoscaler** | スケーリング |
| CodeDeploy (Blue/Green for ECS) | **Argo Rollouts** / VS の重み付け | カナリア・B/G デプロイ |
| ECS Exec | `kubectl exec` | コンテナにシェル接続 |
| AWS Copilot / CDK | **Helm** / **Kustomize** / **Argo CD** | デプロイメント管理 |

## 概念粒度の違い（重要）

ECS は「**Task = 1 デプロイ単位 + 1 リソース割当単位**」と粒度が一致している
が、k8s は **Pod / Deployment / Service** に分かれている。

```
ECS:
   Task Definition (CPU/mem も書く)
        ↓ 起動
   Task (= Container 群)
        ↓ Service が数を維持
   Service (ALB target group に登録)

k8s:
   Deployment (replicas, RollingUpdate 戦略)
        ↓ 管理
   ReplicaSet
        ↓ 管理
   Pod (CPU/mem, Container 定義)
        ↓ ラベルで紐付き
   Service (ClusterIP、LB を作る)
        ↓ さらに
   Ingress / Istio Gateway (L7 ルーティング)
```

→ **k8s は責務が細かく分かれているので、組み合わせの自由度が高い**。
そのぶん概念を覚える必要がある。

## ECS で「自動・隠蔽」されているもの、k8s で「露出・柔軟」なもの

### スケジューラ（タスクの配置決定）

| ECS | k8s |
|---|---|
| AWS が自動で配置（戦略は `binpack`, `spread` 等の簡単な指定のみ） | **kube-scheduler** が露出。NodeSelector, NodeAffinity, PodAffinity, Taints/Tolerations で詳細に制御可 |

**k8s が柔軟な例**:
- 「特定ラベルのノードにだけ置く」（GPU ノード等）
- 「Pod 同士が同じ Zone に来ないようにする」（HA）
- 「特定 namespace は特定ノードプールにのみ」（マルチテナント）

### ネットワーク（Pod 間通信）

| ECS | k8s |
|---|---|
| awsvpc モードで Task に ENI 直接（1 Task = 1 IP）。ALB ターゲットグループ経由でしか他 Task を呼べないことが多い | **Pod IP が VPC のアドレスから払い出される**。Pod 間は直接 IP / DNS で通信可。L7 制御は Istio で被せる |

**k8s が柔軟な例**:
- Pod 間で直接 HTTP / gRPC（ALB を経由しない）
- DNS で `<service>.<namespace>.svc.cluster.local` 一発で名前解決
- NetworkPolicy で「namespace A から namespace B への通信を遮断」など細粒度制御

### サービス検出

| ECS | k8s |
|---|---|
| Cloud Map (AWS Cloud Map)、Service Connect、ALB ターゲットグループ | CoreDNS が標準内蔵。Service リソースを作っただけで `service.namespace.svc.cluster.local` が引ける |

### ロードバランシング

| ECS | k8s |
|---|---|
| ALB / NLB が必須（または Service Connect） | クラスタ内: Service (kube-proxy + iptables)。外部公開: Ingress / Gateway。**内部だけなら LB 不要** |

→ k8s は「内部通信に LB を挟まなくていい」ので、small services 多数構成で**コストとレイテンシが有利**。

### 設定の宣言

| ECS | k8s |
|---|---|
| Task Definition JSON（1 ファイル、リビジョン管理は ARN ベース） | YAML（複数ファイル、kustomize / Helm で合成、Git で管理） |

→ k8s は**設定の合成と再利用が強い**（base + overlay）。

### デプロイ戦略

| ECS | k8s |
|---|---|
| Rolling / Blue-Green（CodeDeploy 経由）| Deployment 標準で Rolling、より高度には **Argo Rollouts** で B/G・カナリア・ヘッダー分割など |

**Istio との組合せで k8s が柔軟な例**:
- 「v2 に **10% のトラフィック**だけ流す」VS の weight で完結
- 「**ヘッダー `x-canary: true` を持つリクエストだけ v2 へ**」VS の match
- ALB のリスナールールでもできるが、k8s + Istio は宣言が一段シンプル

### サービスメッシュ（App Mesh ↔ Istio）

| App Mesh | Istio |
|---|---|
| AWS 純正、Envoy データプレーン | OSS、Envoy データプレーン（同じ Envoy） |
| Mesh / VirtualNode / VirtualService / VirtualRouter | Gateway / VirtualService / DestinationRule |
| GUI / CloudFormation で管理 | k8s manifest (kubectl apply) で管理 |
| ECS / EKS / EC2 / Fargate に対応 | k8s 専用が基本（VM 対応もある） |
| 機能セットは控えめ | mTLS, リトライ, タイムアウト, fault injection, mirroring 等フル装備 |

→ Istio の方が**多機能だが学習コスト大**。App Mesh は「シンプル・統合・限定機能」。

### Pod 内 sidecar の扱い

| ECS | k8s |
|---|---|
| Task Definition に**明示的**に複数コンテナを書く（依存関係も `dependsOn` で明示） | Deployment manifest にメインだけ書けば、**Istio sidecar は admission webhook が自動注入** |

→ k8s は「インフラ要件（プロキシ・ログ collector）の追加がアプリ manifest を汚さない」のが強み。

### 鍵レス認証

| ECS | k8s |
|---|---|
| **IAM Roles for Tasks**（task role） | **Workload Identity**（KSA を GSA にバインド） |
| Task に role を割り当て、SDK が自動取得 | Pod の SA を GSA にバインド、SDK が自動取得 |

→ 仕組みはほぼ同じ。AWS の方が古くから整っている。GCP の Workload Identity
は GKE 限定の機能だが、最近は他クラウドの k8s でも類似機能あり。

## ECS Fargate ↔ GKE Autopilot

| ECS Fargate | GKE Autopilot |
|---|---|
| AWS が Node 完全管理（タスク単位課金） | Google が Node 完全管理（Pod 単位課金） |
| ECS on EC2 と比べてノード操作不可 | GKE Standard と比べてノード操作不可 |
| L7 制御は App Mesh も可だが Fargate との組合せは設計考慮要 | Istio との組合せでコスト爆発（OSS Istio + Autopilot は sidecar 課金が重い）|

→ 今回 **GKE Autopilot を避けた理由**: OSS Istio の sidecar が大量に Pod
あたり立つことで Autopilot の「Pod 単位課金」が膨らむため。

## ECS から k8s に来るときのカルチャーショック

1. **「ALB を必ず通る」感覚を捨てる**: k8s は内部 LB 不要
2. **「タスク = 1 リソース定義」を捨てる**: Deployment + Service + (Ingress or VS) の 3 つに分ける
3. **「インフラ変更はコンソール」を捨てる**: 全部 YAML、Git で管理
4. **「sidecar は明示」を捨てる**: 自動注入を活用
5. **「ロール = タスク」の単純さを捨てる**: KSA / GSA の二段構造で考える
6. **「ALB ルール拡張で全部やる」を捨てる**: L7 ルーティングは k8s 側 (Istio) の責務

## 逆に AWS の方が楽な点

| 項目 | AWS が楽 |
|---|---|
| マネージドサービスとの統合 | RDS / SQS / SNS / S3 とのアクセス制御が一貫 |
| 単純構成での運用負荷 | Fargate + ALB なら考えることが少ない |
| ECR の権限管理 | IAM だけで完結（GAR は IAM + namespace 別など複雑） |
| ログ集約 | CloudWatch が標準、迷わない |
| 公式ドキュメントの整合性 | AWS は 1 ベンダー、k8s は OSS + ベンダー固有 |

## 今回の構成における対応

設計書 `docs/design.md` の構成を ECS で再現するならこうなる、という想像図：

```
[ECS 構成での再現]
  - ECS Cluster
    - Service "frontend" (Task × 2)
    - Service "backend" (Task × 2)
  - ALB (path / host で振り分け)
  - App Mesh
    - VirtualRouter (header で振り分けは限定的)
  - CodeDeploy (Blue/Green)

[今回の k8s 構成]
  - GKE Cluster
    - Deployment "frontend" + Service
    - Deployment "backend" + Service
  - Istio Ingress Gateway + Gateway + VirtualService
    - x-pr-id ヘッダーで namespace 切替
  - Argo CD ApplicationSet (PR ごとに動的に環境生成)
```

→ k8s + Istio の方が「**動的なリソース生成 + ヘッダーベース L7 制御**」が
強い。逆に AWS は「**マネージド統合と一貫運用**」が強い。

## 関連リンク

- AWS App Mesh: https://aws.amazon.com/app-mesh/
- ECS Service Connect: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-connect.html
- Kubernetes Concepts: https://kubernetes.io/docs/concepts/
- Istio vs App Mesh 比較 (HashiCorp): https://www.hashicorp.com/resources/intro-to-service-mesh
