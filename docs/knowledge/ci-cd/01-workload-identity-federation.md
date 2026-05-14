# Workload Identity Federation (WIF)

GitHub Actions など外部サービスから、SA キーを使わずに GCP API を叩く仕組み。

## なぜ WIF が必要か

**Service Account の JSON キー**を使う旧方式の問題：

- 鍵が GitHub Secrets に保存され、漏洩リスクがある
- ローテーションを定期的にやる必要がある
- 鍵が長命で、漏れたら被害が大きい

WIF を使うと:
- 鍵不要（OIDC トークンが短命）
- GitHub Actions の OIDC トークンを GCP が検証して SA に impersonate
- 漏洩耐性が高い

## 三段構造

```
GitHub Actions (実行環境)
   │ ① OIDC トークン発行
   ↓
Workload Identity Pool (識別の入口)
   ├ Workload Identity Provider (どの OIDC を受けるか定義)
   │     - issuer_uri: https://token.actions.githubusercontent.com
   │     - attribute_mapping: assertion → attribute
   │     - attribute_condition: CEL で絞り込み
   ↓
Pool の principalSet が SA に impersonate
   │ ② SA の短命トークン取得
   ↓
Service Account (実際の権限を持つ)
   │ ③ GCP API 呼び出し
   ↓
GCP リソース (GAR, GCS, etc.)
```

## Terraform での実装

```hcl
# 1. Pool: 識別空間
resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = "github-pool"
  display_name              = "GitHub Actions"
}

# 2. Provider: どの OIDC を信用するか
resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"

  # assertion(IdP の主張) → attribute(GCP 側の属性) のマップ
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
    "attribute.actor"      = "assertion.actor"
  }

  # CEL: 許可条件（指定リポジトリのみ）
  attribute_condition = "assertion.repository == \"mormorbump/k8s-action\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# 3. Service Account: 実際の権限を持つ
resource "google_service_account" "deployer" {
  project    = var.project_id
  account_id = "gha-deployer"
}

# 4. SA に「外部 ID が impersonate できる」権限を付与
resource "google_service_account_iam_member" "wif_binding" {
  service_account_id = google_service_account.deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/mormorbump/k8s-action"
}

# 5. SA に「やりたいこと」の最小権限を付与
resource "google_project_iam_member" "deployer_gar_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.deployer.email}"
}
```

## attribute_mapping と attribute_condition の関係（要注意）

`attribute_condition` で使える属性は、**`attribute_mapping` に含まれている
ものだけ**。

```hcl
# NG: mapping に "ref" がないので condition で使えない
attribute_mapping = {
  "google.subject"       = "assertion.sub"
  "attribute.repository" = "assertion.repository"
}
attribute_condition = "assertion.ref == \"refs/heads/main\""    # ← 効かない

# OK: mapping に追加する
attribute_mapping = {
  "google.subject"       = "assertion.sub"
  "attribute.repository" = "assertion.repository"
  "attribute.ref"        = "assertion.ref"        # ← 追加
}
attribute_condition = "assertion.ref == \"refs/heads/main\""    # ← OK
```

## CEL での絞り込みパターン

```hcl
# 単一リポジトリのみ
attribute_condition = "assertion.repository == \"mormorbump/k8s-action\""

# 特定 org の全 repo
attribute_condition = "assertion.repository_owner == \"mormorbump\""

# main ブランチのみ
attribute_condition = "assertion.repository == \"mormorbump/k8s-action\" && assertion.ref == \"refs/heads/main\""

# PR からも許可（preview デプロイ用）
attribute_condition = "assertion.repository == \"mormorbump/k8s-action\" && (assertion.ref == \"refs/heads/main\" || assertion.ref.startsWith(\"refs/pull/\"))"
```

## principalSet の書き方

SA に impersonate を許す `member` の書式：

```
principalSet://iam.googleapis.com/<POOL_NAME>/attribute.<ATTR>/<VALUE>
```

実例:
```
principalSet://iam.googleapis.com/projects/1045675327208/locations/global/workloadIdentityPools/github-pool/attribute.repository/mormorbump/k8s-action
```

- `attribute.repository/mormorbump/k8s-action`: そのリポジトリからのトークンを許可
- `attribute.repository_owner/mormorbump`: そのオーナーの全リポジトリ

絞り方は **attribute_condition + principalSet の両方**で重ねがけ可能。
過剰防御だが学習プロジェクトでも attribute_condition は必須にすべき。

## GitHub Actions 側の書き方（Phase 2 で使う）

```yaml
name: build-and-push
on:
  pull_request:

permissions:
  contents: read
  id-token: write          # OIDC トークン発行に必要

jobs:
  push:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - id: auth
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: projects/1045675327208/locations/global/workloadIdentityPools/github-pool/providers/github-provider
          service_account: gha-deployer@k8s-action-preview-26.iam.gserviceaccount.com

      - uses: google-github-actions/setup-gcloud@v2

      - run: gcloud auth configure-docker us-central1-docker.pkg.dev
      - run: docker build -t us-central1-docker.pkg.dev/k8s-action-preview-26/preview/frontend:${{ github.sha }} .
      - run: docker push us-central1-docker.pkg.dev/k8s-action-preview-26/preview/frontend:${{ github.sha }}
```

`workload_identity_provider` の値は Terraform の output から取れる：

```bash
terraform output workload_identity_provider
```

## デバッグ

```bash
# Pool の状態
gcloud iam workload-identity-pools describe github-pool \
  --location=global --project=k8s-action-preview-26

# Provider の状態
gcloud iam workload-identity-pools providers describe github-provider \
  --location=global \
  --workload-identity-pool=github-pool \
  --project=k8s-action-preview-26

# SA の IAM
gcloud iam service-accounts get-iam-policy \
  gha-deployer@k8s-action-preview-26.iam.gserviceaccount.com
```

## なぜ SA キー (JSON) を使ってはいけないか

| リスク | WIF での解決 |
|---|---|
| GitHub Secrets が漏れたら鍵が漏れる | 鍵が存在しない |
| ローテーション忘れで長命化 | OIDC トークンは数分で失効 |
| 鍵を持っているだけで永続的に impersonate 可能 | 毎回 OIDC 検証してから発行 |
| 監査でいつ使われたか追えない | OIDC トークンに actor 情報が入る |

**新規プロジェクトで SA キーを使う合理的理由はほぼ無い**。レガシー互換でだけ使う。

## 関連

- `gcp/01-iam-fundamentals.md` - IAM の基本概念
- 公式: https://cloud.google.com/iam/docs/workload-identity-federation
- google-github-actions/auth: https://github.com/google-github-actions/auth
