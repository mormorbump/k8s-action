# k8s の Workload リソース（Pod / Deployment / 他）

「どのコンテナを、何個、どう動かすか」を宣言するリソース群。

## マイクロサービスと k8s の関係（前提）

**マイクロサービスは k8s の概念ではない**。ソフトウェアアーキテクチャの
設計思想で、k8s 登場前（2000 年代後半）から Netflix, Amazon が実践していた。

| 概念 | 抽象度 | 役割 |
|---|---|---|
| マイクロサービス | 設計思想 | サービスを小さく分割し独立デプロイ |
| k8s | 実行プラットフォーム | コンテナを起動・配置・スケール |
| containerd / Docker | コンテナランタイム | コンテナを実際に動かす |

k8s はマイクロサービスを動かすのに**便利**だが**専用ではない**。モノリスを
k8s で動かしてもよい。

## Pod = 最小デプロイ単位 = 1 マイクロサービス

```
1 Pod = 1 マイクロサービス
  ├ メインコンテナ: 主役 (frontend, backend, etc.)
  └ sidecar(s):    補助 (Envoy proxy, log collector, ...)
```

Pod 内のコンテナは：
- **同じ network namespace**: localhost で互いに通信
- **同じ volume をマウント**可能
- **同じライフサイクル**: 一緒に起動・終了

「Pod 内に複数コンテナ」は**「複数のマイクロサービス」ではなく、
「1 つのマイクロサービスを支える補助役」を一緒に動かす**という意味。
別のマイクロサービス（frontend と backend）は別 Pod になる。

```
Pod 1: frontend + Envoy sidecar    ← 1 microservice
Pod 2: backend  + Envoy sidecar    ← 別の 1 microservice
Pod 3: fluentd                     ← さらに別のサービス
```

ECS のタスク定義 ≒ k8s Pod、と理解して大体合っている。

## Workload リソースの階層

```
Deployment ─→ ReplicaSet ─→ Pod (× replicas 個)
   │              │             │
   │              │             └ コンテナを実行
   │              └ Pod を「指定数だけ維持」する
   └ ローリングアップデート / ロールバックを管理
```

### Deployment

「**何個の Pod を、どのテンプレートで動かすか**」を宣言する最も一般的な
リソース。ローリングアップデート時は内部で ReplicaSet を新旧切り替え：

```
旧 ReplicaSet (Pod × 3) → 旧 (Pod × 2) → 旧 (Pod × 1) → 旧 (Pod × 0)
新 ReplicaSet (Pod × 0) → 新 (Pod × 1) → 新 (Pod × 2) → 新 (Pod × 3)
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
        - name: frontend
          image: hello:v1
          ports:
            - containerPort: 8080
```

### ReplicaSet

「**指定数の Pod を維持**」する。Pod が落ちたら自動補充。
普段は Deployment を介して扱うので直接書くことは少ない。

### StatefulSet

DB やキューのような **ステートフルなアプリ** 用。

| Deployment と違う点 | 内容 |
|---|---|
| Pod 名 | `frontend-abc123-xyz` (ランダム) → `db-0`, `db-1` (連番) |
| 起動順 | 並列 → 順番（0 → 1 → 2） |
| ストレージ | 共有 → Pod ごとに専用 PVC |

### DaemonSet

「**全ノードに 1 つずつ Pod を立てる**」。kube-proxy、ログ収集 agent
（fluentd）、監視 agent（node-exporter）などで使う。

### Job / CronJob

- Job: 「1 回完走したら終わり」のバッチ処理
- CronJob: スケジュール起動の Job

## Pod の生成フロー（参考）

```
1. ユーザー: kubectl apply -f deployment.yaml
2. apiserver: 検証 → etcd に保存
3. Deployment Controller: ReplicaSet が無いので作る
4. ReplicaSet Controller: Pod が足りないので作る (PodSpec を etcd へ)
5. Scheduler: 各 Pod に node を割り当て (etcd 更新)
6. kubelet (該当 node): 自分宛の Pod がある → containerd に起動指示
7. containerd: イメージを pull してコンテナ起動
8. kubelet: liveness/readiness probe で死活監視
```

## ラベルとセレクタ

Pod を「グループ化」するための仕組み。Deployment や Service が
このラベルで対象 Pod を絞り込む。

```yaml
metadata:
  labels:
    app: frontend
    version: v1
    pr-id: "123"
```

Service / Istio DestinationRule の subset / NetworkPolicy がすべて
ラベルベースで動く。**今回のスイムレーン方式の鍵**でもある。

## requests / limits（リソース管理）

```yaml
resources:
  requests:    # 最低保証 (scheduling の判断材料)
    cpu: 100m      # 0.1 CPU
    memory: 128Mi
  limits:      # 上限
    cpu: 500m
    memory: 256Mi
```

- `requests` を満たせない node には Pod が置かれない
- `limits` を超えると CPU は throttling、memory は OOMKilled
- Phase 3 でマイクロサービス複数 + Envoy sidecar が乗ると逼迫しやすい

## 関連リンク

- Kubernetes Workloads: https://kubernetes.io/docs/concepts/workloads/
- Pod 概念: https://kubernetes.io/docs/concepts/workloads/pods/
- Deployment: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/
