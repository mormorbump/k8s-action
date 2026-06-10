# Terraform helm provider

Phase 1-B で Istio を Terraform 経由の Helm chart で導入した際の知見。

## helm provider とは

Terraform から `helm install / upgrade` 相当の操作を宣言的に行う provider。
`helm_release` リソース 1 つが「クラスタにインストールされた chart 1 つ」に対応する。

```hcl
resource "helm_release" "istiod" {
  name       = "istiod"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "istiod"
  namespace  = "istio-system"
  version    = "1.27.0"

  set {
    name  = "pilot.replicaCount"
    value = "1"
  }
}
```

- `repository` + `chart` + `version` で chart を特定（`helm repo add` 相当は不要）
- `set {}` ブロックが `--set key=value` に対応。values.yaml を丸ごと渡すなら `values = [file("values.yaml")]`
- `terraform destroy` で `helm uninstall` 相当が走る

## GKE への認証: kubeconfig を使わない

ローカルの kubeconfig に依存すると CI や他メンバーの環境で再現しない。
data source で GKE の接続情報を動的に取得するのが定石。

```hcl
data "google_client_config" "default" {}

data "google_container_cluster" "this" {
  name     = var.cluster_name
  location = var.cluster_location
  project  = var.project_id
}

provider "helm" {
  kubernetes {
    host  = "https://${data.google_container_cluster.this.endpoint}"
    token = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(
      data.google_container_cluster.this.master_auth[0].cluster_ca_certificate
    )
  }
}
```

- `google_client_config.access_token`: いま ADC でログインしているユーザーの短命トークン
- `master_auth[0].cluster_ca_certificate`: クラスタの CA 証明書（TLS 検証用）
- つまり「gcloud にログインしてさえいれば kubeconfig なしで helm が打てる」

## ハマりどころ

### 1. chicken-and-egg 問題（最重要）

provider の初期化は **plan 時** に走る。同じ state に
「GKE クラスタの作成」と「そのクラスタへの helm_release」を入れると、
クラスタがまだ無い状態の plan で provider 初期化が失敗する。

→ 解決策は state 分割（[[04-multi-stage-apply]] 参照）。

### 2. リソース不足で Pending になっても apply は失敗しない場合がある

`helm_release` はデフォルトで `wait = true`（Pod Ready まで待つ）。
istiod のデフォルト requests (cpu 500m / mem 2Gi) は e2-medium × 2 に乗らず
Pending → timeout で失敗した。`set` で requests を縮小して解決:

```hcl
set { name = "pilot.resources.requests.cpu"    value = "100m" }
set { name = "pilot.resources.requests.memory" value = "256Mi" }
```

教訓: **chart のデフォルト値は本番想定**。学習用小型ノードでは
resources / replicaCount / autoscale を必ず確認する。

### 3. Istio は 3 chart 構成で順序依存がある

| chart | 役割 | 依存 |
|---|---|---|
| `base` | CRD（Gateway, VirtualService 等）と cluster-scoped リソース | なし |
| `istiod` | コントロールプレーン | base の CRD |
| `gateway` | Ingress Gateway（Envoy 単体 Pod） | istiod（sidecar 注入を受けるため）|

Terraform では `depends_on` で明示する。helm CLI なら人間が順番に打つところを
宣言的に固定できるのが利点。

## helm CLI との対応表

| helm CLI | Terraform |
|---|---|
| `helm repo add istio <url>` | `repository = "<url>"`（不要） |
| `helm install istiod istio/istiod -n istio-system --version 1.27.0` | `resource "helm_release"` |
| `--set pilot.replicaCount=1` | `set { name = "pilot.replicaCount" value = "1" }` |
| `-f values.yaml` | `values = [file("values.yaml")]` |
| `helm uninstall` | `terraform destroy` |
| `helm list -n istio-system` | `terraform state list` |
