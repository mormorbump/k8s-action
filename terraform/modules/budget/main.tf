variable "project_id" {
  type        = string
  description = "GCP project ID to scope the budget"
}

variable "billing_account" {
  type        = string
  description = "Billing account ID (e.g., 01642F-CBD768-5F8412)"
}

variable "display_name" {
  type        = string
  description = "Budget display name"
  default     = "k8s-action-preview monthly budget"
}

variable "monthly_amount" {
  type        = number
  description = "Budget amount in currency units"
  default     = 50
}

variable "currency_code" {
  type        = string
  description = "Currency code"
  default     = "USD"
}

resource "google_billing_budget" "this" {
  billing_account = var.billing_account
  display_name    = var.display_name

  budget_filter {
    projects = ["projects/${var.project_id}"]
  }

  amount {
    specified_amount {
      currency_code = var.currency_code
      units         = tostring(var.monthly_amount)
    }
  }

  # 50%, 80%, 100%, 150% で通知
  threshold_rules {
    threshold_percent = 0.5
  }
  threshold_rules {
    threshold_percent = 0.8
  }
  threshold_rules {
    threshold_percent = 1.0
  }
  threshold_rules {
    threshold_percent = 1.5
  }

  # all_updates_rule を省略すると、Billing Account の Admin / Cost Manager
  # IAM ロールを持つユーザー（= mormorbump@gmail.com）に email が自動送信される。
  # Pub/Sub 通知や Notification Channel を使う場合に all_updates_rule を追加する。
}

output "budget_id" {
  value       = google_billing_budget.this.name
  description = "Budget resource ID"
}
