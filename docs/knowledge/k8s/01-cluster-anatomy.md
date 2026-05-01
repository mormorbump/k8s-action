# k8s クラスタの解剖学

Kubernetes クラスタが何でできているか、各部品が何を担当するかを把握する。
GKE は control plane を Google が隠蔽するので、ここでは「概念上の構成」と
「GKE での実際」を併記する。

## 階層構造（まずこれを腹落ちさせる）

```
GKE Cluster
│
├── Control Plane（Google 管理、見えない）
│     ├── apiserver Pod
│     ├── etcd Pod
│     ├── scheduler Pod
│     └── controller-manager Pod
│
└── Node Pools（ユーザー管理）
      │
      ├── Node Pool "default" (e2-medium × 2)
      │     │
      │     ├── Node 1 (= GCE VM)
      │     │     ├── kubelet (systemd デーモン)
      │     │     ├── kube-proxy Pod (DaemonSet)
      │     │     ├── containerd (systemd デーモン)
      │     │     │
      │     │     ├── ユーザー Pod: frontend
      │     │     │     ├── Container: frontend (主役)
      │     │     │     └── Container: istio-proxy (Envoy sidecar)
      │     │     │
      │     │     └── ユーザー Pod: backend
      │     │           ├── Container: backend
      │     │           └── Container: istio-proxy
      │     │
      │     └── Node 2 (= GCE VM)
      │           └── ...
      │
      └── Node Pool "highmem" (n1-highmem-4 × 1)  ← 別 Pool も持てる
            └── Node 3
                  └── ...
```

### 階層をひと言で

| 層 | 中身 | 個数の目安 |
|---|---|---|
| Cluster | k8s 環境全体 | 通常 1 環境 1 個 |
| Control Plane | 司令塔の Pod 群 | 1 セット（GKE では隠蔽） |
| Node Pool | 同仕様 Node の集合 | 1〜複数（用途別に分ける） |
| Node | GCE VM = 物理的な実行環境 | Pool あたり 1〜N 台 |
| Pod | 最小デプロイ単位 = 1 マイクロサービス | Node あたり 〜110 個 |
| Container | 実際のプロセス | Pod あたり 1〜複数 |

### Pod の役割の使い分け

Pod には大きく 2 種類ある（用途で区別、概念は同じ）：

```
[システム Pod]                          [ユーザー Pod]
- apiserver, etcd, scheduler 等         - frontend, backend
- kube-proxy, CoreDNS                   - 自分のアプリ
- istiod, istio-ingressgateway          - Istio sidecar (注入される)
- ArgoCD, cert-manager
↓                                       ↓
kube-system / istio-system              baseline / preview-pr-N
等の管理 namespace                       等のユーザー namespace
```

## 全体像

```
┌─────────────── Kubernetes Cluster ───────────────┐
│                                                  │
│  ┌─ Control Plane ─────────────────────────┐     │
│  │  - kube-apiserver  (REST 受口)          │     │
│  │  - etcd            (状態の保管庫)         │     │
│  │  - kube-scheduler  (Pod の配置決定)      │     │
│  │  - kube-controller-manager (調整役)      │     │
│  └────────────────────────────────────────┘     │
│              ↑ ↓ (gRPC over TLS)                 │
│  ┌─ Worker Node 1 ─────┐  ┌─ Worker Node 2 ─┐   │
│  │ kubelet             │  │ kubelet         │   │
│  │ kube-proxy          │  │ kube-proxy      │   │
│  │ container runtime   │  │ container runt..│   │
│  │ (containerd)        │  │ (containerd)    │   │
│  │ ┌─Pod─┐ ┌─Pod─┐    │  │ ┌─Pod─┐ ┌─Pod─┐│   │
│  └─────────────────────┘  └─────────────────┘   │
└──────────────────────────────────────────────────┘
```

## 各コンポーネントの「実体」

「component」と聞くと抽象的だが、すべて**プロセス**として動いている。
k8s 自体が「プロセスの集合体」と言える。

| コンポーネント | 実体 | 居場所 |
|---|---|---|
| kube-apiserver | **Pod** (kube-system namespace) | control plane |
| etcd | **Pod** | control plane |
| kube-scheduler | **Pod** | control plane |
| kube-controller-manager | **Pod** | control plane |
| kubelet | **systemd デーモン**（ホスト OS 直下） | 各 Worker Node |
| kube-proxy | **DaemonSet**（各ノードに 1 Pod） | 各 Worker Node |
| container runtime (containerd) | **systemd デーモン** | 各 Worker Node |

GKE Standard だと control plane の Pod は Google 管理の隠れた VM で動いて
いて、ユーザーには見えない。Worker Node 側のコンポーネントは GCE インスタンス
に SSH すれば確認できる。

### kubelet の立ち位置

「ノードの一機能」というより **「ノードに常駐する k8s エージェント」**。
kubelet が居ないとそのノードは k8s クラスタに参加できない。

```
ノード (GCE VM) = OS + kubelet (常駐デーモン) + container runtime
               = 「k8s ノード」として機能する条件
```

## Control Plane の各コンポーネント

### kube-apiserver
- すべての操作（kubectl, Argo CD, Pod 内のサービスアカウント）の入口
- REST API として動作。`kubectl get pods` は実体としてこのサーバーへの GET
- 認証・認可（RBAC）・admission controller を通してから etcd に書く

### etcd
- クラスタの**全状態**を持つ **分散 Key-Value データベース**
- ⚠ 「設定ファイル」とは別物。動的に変化する DB
- 「Pod があるべき状態」「Service の定義」「Secret」など全てここ
- 複数台でレプリカを持つ（Raft プロトコルで合意形成）
- バックアップ対象として最重要

```
[設定ファイル]                 [etcd]
  YAML/JSON ファイル              分散 KV ストア（DB）
  静的、変更は手動                動的、API 経由で更新
  単一サーバーに置く              複数台でレプリカ
```

PostgreSQL の k8s 専用版だと思って良い。`kubectl apply` で書く先 = etcd、
`kubectl get` で読む先 = etcd（実際は apiserver 経由）。

### kube-scheduler
- 「新しい Pod をどのノードに置くか」を決める
- ノードの空き CPU/メモリ、taints/tolerations、affinity/anti-affinity を見る
- 配置先を決めて apiserver に書き戻すだけ。実際の起動は kubelet 担当

### kube-controller-manager
- 様々な Controller を内包（Deployment Controller, ReplicaSet Controller…）
- 「あるべき状態」と「実際の状態」を比較し、差分を埋める動作を続ける
- 例: Deployment が `replicas: 3` で Pod が 2 個 → 1 個追加するよう指示

### GKE での扱い
- **Control plane は Google が完全に管理**。ユーザーは触れない
- 課金は zonal クラスタなら無料枠あり、regional は時間単価が発生
- `kubectl` で叩く先はパブリック or プライベートエンドポイント

## Worker Node のコンポーネント

### kubelet
- ノード上で動くエージェント
- apiserver から「このノードで動かすべき Pod」を受け取る
- container runtime に「このコンテナを起動しろ」と指示
- 死活監視・liveness/readiness probe 実行・ステータス報告

### kube-proxy
- Service の ClusterIP を実現するコンポーネント
- iptables（または IPVS）ルールを書き換えて、Service 宛のパケットを
  実 Pod の IP にルーティングする
- 注: Istio sidecar mode では Envoy が L7 ルーティングを上書きするため
  kube-proxy の役割は「初期ルーティング」止まり

### container runtime
- 実際にコンテナを起動するプロセス（containerd、CRI-O 等）
- Docker は GKE 1.24 以降では非対応、containerd が標準

### GKE での扱い
- ノードは GCE VM。`gcloud compute instances list` で見える
- `e2-medium` × 2 などのマシンタイプを Terraform で指定
- auto-repair / auto-upgrade で自動メンテ

## 重要な用語

### Pod
- スケジュール単位。1 つ以上のコンテナをまとめた最小デプロイ単位
- Pod 内のコンテナは **network namespace と volume を共有**
- これが sidecar パターンの基盤

### Namespace
- 仮想的なクラスタ分割の境界
- 同じ Service 名を別 namespace に作れる
- RBAC や Network Policy の単位
- 今回の構成では `baseline`、`preview-pr-<N>` を namespace で分離

### Node Pool（GKE 固有）
- **同じ仕様の Worker Node の集まり**
- マシンタイプ・ラベル・taint が同じノードをグループ化
- 1 クラスタに複数の Node Pool を持てる

```
GKE Cluster
  ├ Node Pool "default": e2-medium × 2 ノード      ← 通常 Pod 用
  ├ Node Pool "highmem": n1-highmem-4 × 1 ノード   ← 重い処理用
  └ Node Pool "gpu":     n1-standard-8 + GPU × 1   ← GPU 用
```

CIDR とは別軸。CIDR = ネットワーク IP 範囲、Node Pool = コンピュートリソース
のグルーピング。Node Pool を増やしても CIDR は同じものを共有する。

### Service
- Pod の集合に **安定した仮想 IP（ClusterIP）と DNS 名**を提供
- Pod は壊れたら IP が変わるので、直接呼ばずに Service 経由で呼ぶ
- 種類: ClusterIP / NodePort / LoadBalancer / ExternalName

### Deployment
- Pod の「あるべき数」と「テンプレート」を宣言
- ローリングアップデート、ロールバックを管理
- 内部的に ReplicaSet を生成し、ReplicaSet が Pod を生成する

## kubectl で見る方法

```bash
# クラスタ情報
kubectl cluster-info
kubectl get nodes -o wide
kubectl get componentstatuses          # GKE では一部隠蔽

# 名前空間とリソース
kubectl get ns
kubectl get pods --all-namespaces

# 特定ノードに居る Pod
kubectl get pods -A --field-selector spec.nodeName=<node-name>

# 状態の細部
kubectl describe node <node-name>
kubectl describe pod <pod> -n <ns>
```

## 関連リンク

- Kubernetes 公式 Concepts: https://kubernetes.io/docs/concepts/
- GKE アーキテクチャ: https://cloud.google.com/kubernetes-engine/docs/concepts/cluster-architecture
