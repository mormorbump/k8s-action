# Terraform google provider の設定と罠

## 基本

```hcl
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}
```

- `~> 6.0` は「6.x の中で最新のパッチを使う」の意味（major upgrade はしない）
- `version` を指定しないと `terraform init` が最新を取って lock file に固定する

## google vs google-beta

GCP の機能には「GA」と「beta」がある。beta だけにある機能を使うときは
`google-beta` provider を使う：

```hcl
required_providers {
  google      = { source = "hashicorp/google",      version = "~> 6.0" }
  google-beta = { source = "hashicorp/google-beta", version = "~> 6.0" }
}

# 使うリソースで provider を指定
resource "google_container_cluster" "beta_feature" {
  provider = google-beta
  # ...
}
```

学習用なら google だけで足りる。

## 認証の選択肢

| 方法 | 説明 | いつ使う |
|---|---|---|
| ADC (Application Default Credentials) | `gcloud auth application-default login` でブラウザ認証 | 個人開発・ローカル |
| Service Account key (JSON) | `GOOGLE_APPLICATION_CREDENTIALS` env で JSON ファイルを指定 | CI/CD（古典的） |
| Workload Identity Federation | OIDC 経由で短命トークン取得 | CI/CD（推奨） |
| `gcloud` 認証伝播 | gcloud にログイン済みなら ADC として使われる | 個人開発 |

今回はローカルでは ADC、CI では WIF を使う。

## ADC の quota project

ADC を使うと、API リクエストの「課金/クオータ対象プロジェクト」が
**自動では決まらない**。明示する必要がある：

```bash
gcloud auth application-default set-quota-project k8s-action-preview-26
```

これは `~/.config/gcloud/application_default_credentials.json` の
`quota_project_id` を更新する。

ただし**一部の API はこの設定だけでは不十分**。特に Billing API：

```
Error 403: ... API requires a quota project, which is not set by default.
```

これは ADC user credentials の特殊な挙動。解決策↓

## user_project_override = true（重要）

```hcl
provider "google" {
  project               = var.project_id
  region                = var.region
  zone                  = var.zone

  user_project_override = true
  billing_project       = var.project_id
}
```

- `user_project_override = true`: API リクエストヘッダーに `x-goog-user-project` を付ける
- `billing_project`: そのヘッダーに入るプロジェクト ID

これで Billing API などが正しいプロジェクトをクオータ消費先として認識する。

**ハマりどころ**: ADC で apply するときだけ必要。SA key 認証だと不要。
学習用 ADC でつまずいたらこれを疑う。

## google_billing_budget の通貨マッチ

`google_billing_budget` の `specified_amount.currency_code` は
**Billing Account の通貨と一致させる必要**がある：

```bash
# 自分の Billing Account の通貨を確認
gcloud billing accounts describe billingAccounts/01642F-CBD768-5F8412
# → currencyCode: JPY
```

一致しないと **400 Bad Request（詳細不明）** で失敗する。エラーメッセージが
分かりにくいので注意：

```
Error 400: Request contains an invalid argument.
```

→ 「invalid argument」と出たら通貨を疑う。

```hcl
resource "google_billing_budget" "this" {
  amount {
    specified_amount {
      currency_code = "JPY"        # ← 必ず Billing Account の通貨
      units         = tostring(7500)
    }
  }
}
```

## `disable_on_destroy` の罠

`google_project_service` には `disable_on_destroy` がある：

```hcl
resource "google_project_service" "this" {
  service            = "container.googleapis.com"
  disable_on_destroy = false   # ← 推奨
}
```

`true` だと `terraform destroy` 時に API そのものを無効化する。
これは**他のリソースを巻き込んで壊す**可能性がある。

→ 学習用も本番も **`false`** が安全。API は有効のまま残しておく。

## デフォルトリージョン・ゾーンの優先順位

```hcl
provider "google" {
  project = var.project_id
  region  = "us-central1"
  zone    = "us-central1-a"
}

resource "google_compute_subnetwork" "subnet" {
  # region を書かない → provider のデフォルト "us-central1" が使われる
}

resource "google_compute_subnetwork" "another" {
  region = "us-east1"   # 個別指定が優先
}
```

複数リージョン使う場合は明示が分かりやすい。

## ハマったときのデバッグ

```bash
# 詳細ログを出す
TF_LOG=DEBUG terraform apply 2>&1 | tee /tmp/tf-debug.log

# API リクエストだけ見たい
TF_LOG=DEBUG terraform apply 2>&1 | grep -A 20 "POST.*googleapis"

# provider 単位のログ
TF_LOG_PROVIDER=DEBUG terraform apply
```

ログレベル: `TRACE` > `DEBUG` > `INFO` > `WARN` > `ERROR`。
ふだんは `DEBUG` で十分。

## 関連

- `terraform/01-state-backend.md` - GCS backend と state lock
- `gcp/02-billing-budget-gotchas.md` - Budget API の罠（通貨、IAM）
- 公式: https://registry.terraform.io/providers/hashicorp/google/latest/docs
