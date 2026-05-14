# GKE 固有のハマりどころと Tips

GKE Standard を Terraform で扱うときに踏みやすい罠と、検証時の注意点。

## クラスタ作成時間

- **約 14〜15 分**かかる（リージョナルだとさらに長い）
- node pool 追加は約 1〜2 分
- destroy も同程度時間がかかるので「ちょっと試して消す」が重い

## `deletion_protection` の罠（重要）

google provider 5.x 以降、`google_container_cluster` の
**`deletion_protection` がデフォルト `true`**。

```hcl
resource "google_container_cluster" "this" {
  # ...
  deletion_protection = false   # 学習用・検証用は明示的に false
}
```

これを書かないと:
- `terraform destroy` が失敗する（Resource is protected）
- 手動で `gcloud container clusters update --no-deletion-protection`
  しないと消せない

本番では `true` のままにすべき。学習用途・短命クラスタでは `false`。

## kubectl 認証: `gke-gcloud-auth-plugin` 必須

GKE 1.26 以降、`kubectl` 用に専用のクレデンシャルプラグインが必要。
brew で gcloud をインストールしている場合、追加で：

```bash
gcloud components install gke-gcloud-auth-plugin
```

ただし **homebrew 経由の gcloud は実体が `/opt/homebrew/share/google-cloud-sdk/bin/`** に
あって、ここがデフォルト PATH に入っていない。シンボリックリンクが必要：

```bash
ln -sf /opt/homebrew/share/google-cloud-sdk/bin/gke-gcloud-auth-plugin \
       /opt/homebrew/bin/gke-gcloud-auth-plugin
```

## 認証アカウントの食い違いに注意

`gcloud container clusters get-credentials` は **`gcloud config` の active
account** を kubeconfig に書き込む。複数アカウントを切り替えて使っている場合：

```bash
# まず active account を意図したものに切り替える
gcloud config set account mormorbump@gmail.com

# その上で credentials を取り直す
gcloud container clusters get-credentials preview --zone=us-central1-a \
  --project=k8s-action-preview-26

# 確認
kubectl config current-context
kubectl auth can-i get pods --all-namespaces
```

`gcloud container clusters get-credentials --account=...` を指定しても、
**kubeconfig には active account が入る**。後で kubectl が動かないときは
ここを疑う。

## VPC-native と Secondary IP Range の対応

GKE クラスタ作成時、`ip_allocation_policy` ブロックで Pod / Service の
セカンダリ IP 範囲を指定する：

```hcl
ip_allocation_policy {
  cluster_secondary_range_name  = "pods"      # subnet 側で定義した名前
  services_secondary_range_name = "services"
}
```

→ Subnet 側で `secondary_ip_range { range_name = "pods" ... }` と同じ名前
を使う必要がある。名前が一致しないと apply 失敗。

## ノードの External IP の有無

`google_container_node_pool` の `node_config` で `network_config.enable_private_nodes`
を指定しないと、デフォルトでノードに **External IP が付く**。

学習用なら付いていて OK（ノードから外部に出るのが楽）。
本番では private nodes + Cloud NAT を使うことが多い。

## Release Channel

`release_channel.channel` の選択肢：

| channel | 内容 |
|---|---|
| RAPID | 最新版（不安定だがアーリーアダプタ向け） |
| REGULAR | 標準。本番でも使われる |
| STABLE | 保守的。古いが安定 |
| UNSPECIFIED | 手動指定（バージョンを `min_master_version` で固定） |

今回は `REGULAR` を採用。GKE が自動でマイナーアップグレードしてくれる。

## Workload Identity の有効化

```hcl
resource "google_container_cluster" "this" {
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
}

resource "google_container_node_pool" "default" {
  node_config {
    workload_metadata_config {
      mode = "GKE_METADATA"   # WI 用にメタデータサーバーを GKE 版に置き換え
    }
  }
}
```

両方必須。クラスタ側だけ有効化しても、ノードプール側で `GKE_METADATA` モード
にしないと Pod から GCP API を叩くと「権限がない」エラーになる。

## ログ・モニタリングの最小化

```hcl
logging_config {
  enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
}
monitoring_config {
  enable_components = ["SYSTEM_COMPONENTS"]
}
```

`WORKLOADS` を含めるとアプリログも Cloud Logging に流れる。学習用には
便利だが、量が増えると課金される。

## destroy 時の余韻

`terraform destroy` してから完全にリソースが消えるまで GCP コンソールに
残ることがある。特に：
- External IP の forwarding rule（LB）が 5〜10 分残る
- Disk が削除されないことがある（PVC 由来）

→ Phase 1 で destroy するときはコンソールでも確認すること。
