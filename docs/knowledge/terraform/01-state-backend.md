# Terraform State Backend (GCS)

Terraform の state を GCS バケットに置く際の設定と落とし穴。

## なぜ Backend を使うか

state ファイル (`terraform.tfstate`) は「クラスタの現状」を持つ重要ファイル。
ローカルだけに置くと：
- マシン故障で消える
- 複数人での共有ができない
- state ロックが効かない（並列実行で破壊）

GCS backend を使うと：
- リモートに置かれ、versioning で過去版に戻せる
- state lock が GCS object メタデータで実現される（同時 apply 防止）
- 複数 PC・複数人で共有できる

## chicken-and-egg 問題

Terraform で **state バケット自体を Terraform で作ろうとすると**:
- バケットが無い → init できない
- init できない → バケットが作れない

→ **state バケットは手動 (`gcloud`) で先に作る**。これは原則。

```bash
gcloud storage buckets create gs://k8s-action-preview-26-tfstate \
  --project=k8s-action-preview-26 \
  --location=us-central1 \
  --uniform-bucket-level-access \
  --public-access-prevention

gcloud storage buckets update gs://k8s-action-preview-26-tfstate --versioning
```

## バケットのセキュリティガード

| 設定 | 目的 |
|---|---|
| `--uniform-bucket-level-access` | ACL 禁止、IAM のみで管理（漏洩経路を減らす） |
| `--public-access-prevention=enforced` | 公開化を恒久ブロック |
| versioning ON | state 過去版を復元できる |
| IAM を限定 (`roles/storage.objectAdmin` を 1 ユーザのみ) | state に Secret 相当が入る可能性に備える |

## backend.tf の書き方

```hcl
terraform {
  backend "gcs" {
    bucket = "k8s-action-preview-26-tfstate"
    prefix = "envs/dev/gcp"
  }
}
```

- `bucket`: 上で手動作成したバケット名
- `prefix`: 同じバケットを複数 root module で共有するための「フォルダ分け」

## prefix で state を分割する利点

1 バケットで複数 root module を運用するのが標準パターン：

```
gs://k8s-action-preview-26-tfstate/
├── envs/dev/gcp/default.tfstate     ← GKE などのインフラ層
└── envs/dev/istio/default.tfstate   ← Istio 層
```

→ それぞれ別 state なので「Istio だけ apply」「GKE は触らずに Istio だけ
変更」が可能。**helm provider の chicken-and-egg 問題回避**にも使う
（`terraform/04-multi-stage-apply.md` 参照、Phase 1-B で書く）。

## state lock の挙動

`terraform apply` を実行すると GCS に `<prefix>/default.tflock` ファイルが
作られる。これが lock：

- apply 中: lock が存在
- apply 終了: lock が削除される
- apply 失敗・kill: **lock が残る** → 次の apply が `Error 412` で落ちる

### state lock 残留の対処

```bash
# エラーメッセージから ID を取得
# Lock Info: ID: 1778751095632534

terraform force-unlock -force 1778751095632534
```

ただし「本当に他人が apply 中ではない」ことを確認してから force-unlock すること。
複数人で同じ state を触っているなら相談する。

## state ファイルに Secret が入る問題

Terraform は **provider が返した値を state に保存する**。例えば：
- `google_service_account_key`: 秘密鍵が state に入る
- `random_password`: 生成したパスワードが平文で state に入る
- `google_container_cluster.master_auth.password`（廃止予定）

→ state バケットは「Secret が漏れたら困るレベル」のセキュリティで管理する。
今回は uniform access + versioning + 1 ユーザ IAM で守っている。

## ADC quota project と Terraform

ADC (Application Default Credentials) を使う Terraform は、**quota project を
適切に設定しないと一部 API が落ちる**。特に billing 系。

```bash
gcloud auth application-default set-quota-project k8s-action-preview-26
```

これでも足りない場合（billing API 等）は、provider 側で
`user_project_override = true` を明示する：

```hcl
provider "google" {
  user_project_override = true
  billing_project       = var.project_id
}
```

→ `terraform/03-google-provider.md` に詳述。

## init / plan / apply の使い分け

```bash
terraform fmt -recursive    # フォーマット統一
terraform init              # provider と backend を初期化
terraform validate          # 構文チェック
terraform plan -out=plan.tfplan   # 何をするかを保存
terraform apply plan.tfplan       # plan を確実に再現
terraform destroy           # 全削除
```

**plan に -out を付けて保存** → apply で `plan.tfplan` を指定するのが安全。
plan 時と apply 時で差が出ない保証になる。

## `.terraform.lock.hcl` は commit する

provider バージョンの **lock file**。再現性のため Git で管理する。
`.gitignore` に入れがちだが**含めない**。

```
# .gitignore で除外しないファイル
!.terraform.lock.hcl   # （または gitignore 行から削除）
```

逆に絶対に commit しないファイル：
- `terraform.tfvars`（実値、Secret 含む可能性）
- `*.tfstate*`（state）
- `.terraform/`（プロバイダバイナリ等の作業ファイル）
- `*.tfplan`（plan の binary）
