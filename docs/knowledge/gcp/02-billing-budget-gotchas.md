# Billing Budget の罠

`google_billing_budget` リソースで踏みやすい罠の整理。エラーメッセージが
不親切な API なので、原因を予測できる引き出しが要る。

## エラー「Error 400: Request contains an invalid argument.」

**詳細不明の 400** が返ってきたら、以下を順に疑う。

### 1. 通貨コードが Billing Account と一致しているか（最頻出）

`specified_amount.currency_code` は **Billing Account の通貨** と一致が必須。

```bash
# Billing Account の通貨を確認
gcloud billing accounts describe billingAccounts/<BILLING_ACCOUNT_ID>
# → currencyCode: JPY
```

```hcl
amount {
  specified_amount {
    currency_code = "JPY"             # ← Billing Account の通貨と同じ
    units         = tostring(7500)
  }
}
```

日本の個人 Billing Account はほぼ JPY。「USD で 50」と書きたくなるが
動かない。

### 2. `all_updates_rule` の `monitoring_notification_channels = []`

空配列を渡すと invalid argument になる場合がある。**通知不要なら
ブロックごと省略**するのが安全：

```hcl
# NG（空配列でエラー）
all_updates_rule {
  monitoring_notification_channels = []
}

# OK（省略すれば Billing Admin に自動 email 送信）
# all_updates_rule ブロック自体を書かない
```

省略すると、デフォルトで **Billing Account の Admin / Cost Manager IAM** を
持つユーザーに email 通知が飛ぶ。今回は `mormorbump@gmail.com` が Admin
なのでこれで十分。

### 3. ADC quota project の罠

```
Error 403: ... API requires a quota project, which is not set by default.
```

ADC を使う Terraform で billing API を呼ぶには、provider に
**`user_project_override = true`** が必須：

```hcl
provider "google" {
  user_project_override = true
  billing_project       = var.project_id
}
```

詳細: `terraform/03-google-provider.md`

### 4. `billing_account` フィールドの値

`google_billing_budget` の `billing_account` には「**ID 文字列だけ**」を渡す。
`billingAccounts/` プレフィックスは付けない：

```hcl
# NG
billing_account = "billingAccounts/01642F-CBD768-5F8412"

# OK
billing_account = "01642F-CBD768-5F8412"
```

## Threshold 設定

```hcl
threshold_rules {
  threshold_percent = 0.5    # 50% で警告
}
threshold_rules {
  threshold_percent = 0.8    # 80%
}
threshold_rules {
  threshold_percent = 1.0    # 100%
}
threshold_rules {
  threshold_percent = 1.5    # 150%（オーバー）
}
```

複数 `threshold_rules` ブロックを書けば段階的に通知。
`spend_basis` のデフォルトは `CURRENT_SPEND`（実支出）。`FORECASTED_SPEND`
にすると予測でアラート（GCP が機械学習で推定）。

## 通知の遅延

Budget Alert は**リアルタイムではない**：

- 通常 1〜2 時間遅延
- 場合によっては半日遅れることも
- 「使いすぎを即時止める」用途には不向き

→ コスト即時遮断は `disable_billing_on_budget_exceeded` パターン
（Cloud Functions + Pub/Sub）が必要。Phase 4 以降で検討。

## 通知の宛先を増やす場合（Phase 4 以降）

Cloud Monitoring の Notification Channel を作って、Budget に紐付ける：

```hcl
resource "google_monitoring_notification_channel" "email" {
  display_name = "Email mormorbump"
  type         = "email"
  labels = {
    email_address = "mormorbump@gmail.com"
  }
}

resource "google_billing_budget" "this" {
  # ...
  all_updates_rule {
    monitoring_notification_channels = [
      google_monitoring_notification_channel.email.id,
    ]
  }
}
```

Pub/Sub topic も同様に登録できる。これで「Cloud Functions に通知 → 自動
シャットダウン」のような自動化が組める。

## 確認方法

```bash
# 作成した Budget を確認
gcloud billing budgets list --billing-account=01642F-CBD768-5F8412

# 詳細
gcloud billing budgets describe \
  billingAccounts/01642F-CBD768-5F8412/budgets/<BUDGET_ID>
```

GCP コンソール: `https://console.cloud.google.com/billing/<ID>/budgets`

## 関連

- `terraform/03-google-provider.md` - user_project_override 設定
- GCP Budgets API: https://cloud.google.com/billing/docs/how-to/budget-api-overview
