# k8s-action

GitHub Pull Request ごとに、変更されたマイクロサービスを baseline 環境に
重ねてデプロイし、HTTP ヘッダー経由で PR 専用の通信経路を作る
**スイムレーン型のプレビュー環境**を、GCP + GKE + Istio で構築する学習プロジェクト。

## 全体構成

- **クラウド**: GCP（GKE Standard, ゾーナル, `us-central1`）
- **Service Mesh**: OSS Istio (Sidecar mode)
- **GitOps**: Argo CD ApplicationSet (PullRequest Generator)
- **CI**: GitHub Actions × Workload Identity Federation
- **IaC**: Terraform（GCP リソース + Istio まで管理）
- **ドメイン**: nip.io

詳細は `docs/design.md` を参照。

## ドキュメント

| パス | 内容 |
|---|---|
| `docs/design.md` | 全体設計書 |
| `docs/adr/` | Architecture Decision Records |
| `docs/knowledge/` | 学習メモ（k8s, istio, networking, gitops, observability 等） |

## フェーズ

| Phase | ゴール |
|---|---|
| 1. 最小構成 | GKE + Istio が動き、サンプル 1 個に外部からアクセスできる |
| 2. GitOps 化 | Argo CD で baseline をデプロイ管理 |
| 3. PR プレビュー | PR ごとに環境が立ち、ヘッダーで分岐する |
| 4. 仕上げ | TLS 化、可観測性、ドキュメント整備 |

## 注意

- 学習目的のため、ノード稼働中はコストが発生します（24h で約 $53/月）
- 利用後は `terraform destroy` でリソースを削除する運用です
- 個人用 GCP プロジェクト `k8s-action-preview-26` で運用
