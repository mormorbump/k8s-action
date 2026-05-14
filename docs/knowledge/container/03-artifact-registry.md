# Artifact Registry (GAR)

GCP のコンテナイメージ + パッケージリポジトリ。古い Container Registry (GCR) の後継。

## GCR との違い

| | GCR | Artifact Registry |
|---|---|---|
| 状態 | deprecated（新規利用非推奨） | 推奨 |
| ホスト | `gcr.io`, `<region>.gcr.io` | `<region>-docker.pkg.dev` |
| ストレージ | GCS バケットベース | 専用 |
| 対応形式 | Docker のみ | Docker, Maven, npm, Python, Apt, Yum, Helm 等 |
| IAM | バケット単位 | リポジトリ単位（細かく管理可能） |

新規プロジェクトはすべて **Artifact Registry を使う**。

## リポジトリの URL 規約

```
<region>-docker.pkg.dev/<project_id>/<repository_id>/<image>:<tag>
```

例:
```
us-central1-docker.pkg.dev/k8s-action-preview-26/preview/frontend:abc1234
```

- `<region>-docker.pkg.dev`: グローバルではなく**リージョン別ホスト**
- `<repository_id>`: GAR で作成したリポジトリ名（今回は `preview`）
- `<image>:<tag>`: 任意のイメージ名とタグ

リージョンを誤ると pull が遠回りになって遅い。

## Terraform での作成

```hcl
resource "google_artifact_registry_repository" "this" {
  project       = var.project_id
  location      = var.location          # "us-central1"
  repository_id = "preview"
  format        = "DOCKER"
  description   = "Container images for preview environments"
}
```

- `format` には `DOCKER`, `MAVEN`, `NPM`, `PYTHON`, `APT`, `YUM`, `HELM` 等が選べる
- Helm chart も GAR にホストできる（Phase 2 以降で検討）

## docker push できるようにする手順

```bash
# 1. 一度だけ: gcloud が docker の credential helper を仕込む
gcloud auth configure-docker us-central1-docker.pkg.dev

# 2. ビルド
docker build -t us-central1-docker.pkg.dev/k8s-action-preview-26/preview/hello:v1 .

# 3. push
docker push us-central1-docker.pkg.dev/k8s-action-preview-26/preview/hello:v1
```

## IAM 権限

| Role | 用途 |
|---|---|
| `roles/artifactregistry.reader` | pull のみ。GKE node が image を取るときに必要 |
| `roles/artifactregistry.writer` | push 可。CI/CD 用 SA に付ける |
| `roles/artifactregistry.admin` | リポジトリ管理（削除等） |

### GKE Node の image pull

GKE の **default node service account** はデフォルトで GAR の reader を
持つので、特に設定なしで pull できる（同じプロジェクト内なら）。

別プロジェクトの GAR を使う場合は、その GAR に対して GKE の node SA を
明示的に reader として追加する。

## タグ戦略

```
# 推奨
- frontend:<git-sha>            ← 不変、追跡可能
- frontend:pr-123-abc1234       ← PR ごと
- frontend:baseline-2026-05-14  ← 日付付きベースライン

# 非推奨
- frontend:latest               ← 不変性がない、CI/CD で問題になる
```

今回は **`<git-sha>` 戦略** を採用（ApplicationSet が `{{head_sha}}` を使う）。

## イメージのライフサイクル

GAR は自動削除しない。放置するとストレージ課金が膨らむので、定期的に
古いイメージを削除する：

```bash
# 10 個より古いものを削除
gcloud artifacts docker images list \
  us-central1-docker.pkg.dev/k8s-action-preview-26/preview/frontend \
  --include-tags --format="value(IMAGE,TAGS)" \
  | tail -n +11 | awk '{print $1}' \
  | xargs -I{} gcloud artifacts docker images delete {} --quiet
```

Terraform で `cleanup_policies` を定義することも可能：

```hcl
resource "google_artifact_registry_repository" "this" {
  # ...
  cleanup_policies {
    id     = "delete-old"
    action = "DELETE"
    condition {
      tag_state  = "ANY"
      older_than = "2592000s"   # 30 日
    }
  }
}
```

Phase 3 以降で大量に PR イメージが溜まる前に検討。

## デバッグ

```bash
# リポジトリ一覧
gcloud artifacts repositories list

# 特定リポジトリ内のイメージ一覧
gcloud artifacts docker images list \
  us-central1-docker.pkg.dev/k8s-action-preview-26/preview

# 特定イメージのタグ一覧
gcloud artifacts docker tags list \
  us-central1-docker.pkg.dev/k8s-action-preview-26/preview/frontend
```

## ECR との対応

| ECR | Artifact Registry |
|---|---|
| Repository | Repository |
| `<account>.dkr.ecr.<region>.amazonaws.com/<repo>` | `<region>-docker.pkg.dev/<project>/<repo>` |
| IAM ポリシー (resource-based) | IAM ロール (resource-based も可) |
| Lifecycle Policy | Cleanup Policies |
| Replication | Remote/Virtual Repositories |
| Pull Through Cache | Remote Repositories（プロキシ的に外部 registry を中継） |

GAR の方が形式が多い（Docker 以外も）。一方 ECR の方がライフサイクル
ポリシーが古くからあって洗練されている。

## 関連

- `ci-cd/01-workload-identity-federation.md` - CI から push する SA の権限
- GAR 公式: https://cloud.google.com/artifact-registry/docs
