# ADR-0002: Istio バージョンの採択

- ステータス: Accepted
- 日付: 2026-05-14
- 関連: docs/design.md §4.4.3, ADR-0001

## コンテキスト

Phase 1-B で Istio を Terraform helm provider 経由でインストールする。
バージョン互換性問題（Istio 公式 Supported Releases）を避けるため、
具体的なバージョン番号を ADR で固定する。

GKE クラスタの現在の k8s バージョン: `v1.35.3-gke.1389000`

## 決定

- **Istio バージョン: `1.27.0`**
- 3 チャート (`base`, `istiod`, `gateway`) すべて同じバージョンで揃える
- Terraform variable `var.istio_version` に default を設定し、必要時に
  tfvars で override 可能にする

## 代替案

| バージョン | 状態 | k8s 1.35 互換 | 不採用理由 |
|---|---|---|---|
| 1.27.x | 安定版（最新の一つ前） | ✅ | **採用**。教材も揃ってきている |
| 1.28.x | 最新版 | ✅ | 比較的新しく、報告事例が少ない |
| 1.26.x | 1 つ前の安定版 | ✅ | やや古い、Ambient mode の機能が弱い |
| 1.25.x 以下 | サポート切れ間近 | △ | サポート終了の懸念 |

## 結果

### 採用によって縛られる選択肢

- アップグレード時は **N → N+1** のステップを踏む必要がある
  （Istio は基本 1 マイナーアップしかサポートしない）
- 後述の helm chart 名・values の API 互換性は 1.27 系で固定

### 後続フェーズで決める残課題

- Ambient mode の評価（Phase 4 以降）
- TLS（cert-manager）導入時の証明書連携 → Phase 4

### Helm Chart 構成

| Chart | namespace | 役割 |
|---|---|---|
| `base` | `istio-system` | CRD インストール、cluster role 等の前提条件 |
| `istiod` | `istio-system` | コントロールプレーン本体 |
| `gateway` | `istio-ingress` | Istio Ingress Gateway（外部公開の入口） |

順序は `base → istiod → gateway`（依存関係）。Terraform 側では `depends_on`
で明示する。

### Helm Chart のリポジトリ

`https://istio-release.storage.googleapis.com/charts`

公式 GCS バケットでホストされている。`helm repo add` 相当を Terraform
helm provider が internal に行うので、こちらで repo add は不要。
