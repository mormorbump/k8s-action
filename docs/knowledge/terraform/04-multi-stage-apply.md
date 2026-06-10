# State 分割と多段 apply

Phase 1 で「GCP インフラ」と「Istio (helm)」を別 state に分けた理由と手法。

## なぜ分けるのか: provider 初期化の chicken-and-egg

Terraform の provider 初期化は plan 時に走る。helm provider は
「接続先クラスタの endpoint / CA / token」を初期化時に要求するため、

- 同一 state に `google_container_cluster`（クラスタ作成）と `helm_release` を同居させると
- 初回 plan の時点ではクラスタが存在せず、helm provider の初期化が失敗する

`depends_on` はリソース間の順序制御であって **provider の初期化順は制御できない**。

## 採用した構成

```
terraform/
├── modules/
│   ├── network/  gke/  artifact_registry/  workload_identity/  budget/
│   └── istio/                  # helm_release × 3
└── envs/dev/
    ├── gcp/                    # state: gs://<bucket>/terraform/dev/gcp
    │   └── (VPC, GKE, GAR, WIF, Budget)
    └── istio/                  # state: gs://<bucket>/terraform/dev/istio
        └── (istio module。GKE は data source で参照)
```

apply は 2 段階:

```sh
cd terraform/envs/dev/gcp   && terraform apply   # 1段目: クラスタを作る
cd terraform/envs/dev/istio && terraform apply   # 2段目: クラスタに helm を打つ
```

## state 間の参照方法は 2 通り

### 1. data source 参照（今回採用）

```hcl
data "google_container_cluster" "this" {
  name     = var.cluster_name      # 実在リソースを名前で引く
  location = var.cluster_location
}
```

- メリット: 上流 state の内部構造に依存しない。GCP API が真実の源
- デメリット: 名前をハードコード（tfvars 経由）する必要がある

### 2. terraform_remote_state

```hcl
data "terraform_remote_state" "gcp" {
  backend = "gcs"
  config = {
    bucket = "<state-bucket>"
    prefix = "terraform/dev/gcp"
  }
}
# data.terraform_remote_state.gcp.outputs.cluster_name で参照
```

- メリット: 上流の output を型安全に参照、名前変更に追従
- デメリット: 上流 state への read 権限が必要、state 構造への結合が生まれる

今回は「GKE クラスタ名は安定している」「学習用に仕組みを単純に保つ」ことから
data source 参照を採用した。

## GCS backend の prefix 分割

同一バケットを prefix で分けることで、state ファイルの管理は 1 バケットに集約:

```hcl
backend "gcs" {
  bucket = "k8s-action-preview-26-tfstate"
  prefix = "terraform/dev/gcp"     # 環境/レイヤごとに変える
}
```

## destroy は逆順

依存の向きと逆に壊す。istio (helm) → gcp の順:

```sh
cd terraform/envs/dev/istio && terraform destroy
cd terraform/envs/dev/gcp   && terraform destroy
```

GKE クラスタを先に消すと istio state が「接続先のないゴミ state」として残り、
`terraform state rm` での手作業掃除が必要になる。

## AWS との比較

ECS で言うと「VPC + ECS Cluster の CFn スタック」と「Service/TaskDef のスタック」を
分けるのと同じ発想。クロススタック参照（Export/ImportValue）に相当するのが
terraform_remote_state。レイヤ分割の粒度は
「ライフサイクルが違うものは別 state」が原則（クラスタは月単位、アプリは日単位で変わる）。
