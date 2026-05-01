# GKE の CIDR 設計

GKE クラスタで使う 3 種類の CIDR と、サイジングの考え方を整理する。

## CIDR とは（前提）

`10.0.0.0/20` のように「IP アドレスの範囲」を表す記法。`/数字` の数字を
**プレフィックス長**と呼び、**小さいほど範囲が広い**。

| プレフィックス | IP 数 | 例 |
|---|---|---|
| `/8` | 16,777,216 | プライベートクラス A 全部 |
| `/16` | 65,536 | プライベートクラス B 全部 |
| `/20` | 4,096 | サブネット小 |
| `/22` | 1,024 | 中規模 |
| `/24` | 256 | 小規模 LAN 1 つ分 |
| `/27` | 32 | 個人ネット |

計算: `2^(32 - プレフィックス長) = IP 数`。
`/22` なら `2^(32-22) = 2^10 = 1024`。

## GKE で使う 3 つの CIDR

GKE は VPC-native モードで動かすのが標準。Pod / Service / Node に
**それぞれ別の IP 範囲**が必要。

| 種類 | 用途 | 採用 |
|---|---|---|
| **Subnet primary** | ノード（VM）の IP | `10.0.0.0/20`（4096 IP） |
| **Pods Secondary IP Range** | Pod 1 個 1 個に割当 | `10.4.0.0/22`（1024 IP） |
| **Services Secondary IP Range** | Service の ClusterIP 用 | `10.8.0.0/22`（1024 IP） |

```
VPC: preview-vpc
└─ Subnet: preview-subnet (region us-central1)
   ├─ primary: 10.0.0.0/20  ← Node の IP（4096 個）
   ├─ secondary "pods":     10.4.0.0/22  ← Pod の IP（1024 個）
   └─ secondary "services": 10.8.0.0/22  ← ClusterIP（1024 個）
```

**重要**: 3 つの範囲が**互いに重複しない**ことを必ず確認。

## Pod CIDR のサイジング（重要な誤解ポイント）

GKE は「Pod 1 個 = 1 IP 消費」ではなく、**「ノード 1 台に Pod 用の小さな
CIDR ブロックを丸ごと予約」** するモデル。

| max-pods-per-node | ノード 1 台に予約される CIDR | IP 数 |
|---|---|---|
| 110（デフォルト） | `/24` | 256 |
| 64 | `/25` | 128 |
| 32 | `/26` | 64 |

→ Pod が 1 個しか動いていなくても、そのノードは **256 IP を占有**する。
スケジューリング高速化と IP 衝突回避のため。

### 必要量の計算

```
必要な Pod CIDR = max-pods-per-node に応じた per-node 範囲 × ノード数
```

学習用（max-pods=110、ノード 2 台）の場合：
- 2 ノード × `/24` = 最低 `/23`（512 IP）
- 余裕を見て `/22`（1024 IP、4 ノード分まで対応）← **採用**
- 旧案 `/14`（26 万 IP）= **明らかに過剰**、将来の VPC 拡張で衝突リスク

## Service CIDR のサイジング

Service の ClusterIP 用。Service 数 = 必要 IP 数。

学習用なら 100 個を超える Service は作らないので **`/22`（1024 個）で十分**。
将来 cert-manager や Argo CD 等が増えても余裕。

## VPC-native（IP alias）vs Routes-based

| モード | 説明 | 採用 |
|---|---|---|
| VPC-native | Pod IP が VPC のセカンダリ IP 範囲から払い出される。VPC 内から Pod に直接到達可能 | ✅ |
| Routes-based | Pod CIDR が VPC ルートテーブルに登録される。レガシー | × |

**今は VPC-native が標準**。GKE 1.21 以降の新規クラスタはデフォルトで
VPC-native になる。

## CIDR 設計の注意点

### 1. 既存ネットワークと衝突しない範囲を選ぶ

社内 VPN や AWS VPC とピアリングする可能性があるなら、`10.0.0.0/8`
全体の中で重複しない範囲を確保する。学習用だが**癖を付ける**意味で
分かりやすい範囲を選ぶ。

### 2. 連続帯にしない（可読性）

`10.0.0.0/20` の直後を `10.1.0.0/22` にすると「primary が広がったか
secondary か」紛らわしい。`10.0` / `10.4` / `10.8` のように**少し離す**と
区別しやすい。

### 3. プレフィックス値が境界に整合しているか

`10.4.0.0/22` は OK。`10.4.1.0/22` は不正（`/22` の境界は `10.4.0.0`,
`10.4.4.0`, `10.4.8.0` …）。

CIDR 計算は `ipcalc` コマンドや https://cidr.xyz で検算できる。

### 4. 確認コマンド

```bash
# subnet の IP range 確認
gcloud compute networks subnets describe preview-subnet \
  --region=us-central1 \
  --format="value(ipCidrRange,secondaryIpRanges)"

# クラスタが使っている範囲を確認
gcloud container clusters describe preview \
  --zone=us-central1-a \
  --format="yaml(ipAllocationPolicy)"
```

## 関連リンク

- GKE VPC-native: https://cloud.google.com/kubernetes-engine/docs/concepts/alias-ips
- GKE IP address ranges: https://cloud.google.com/kubernetes-engine/docs/concepts/network-overview#cluster_networking
- CIDR 計算: https://cidr.xyz
