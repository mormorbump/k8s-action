# ADR-0001: 全体アーキテクチャの採択

- ステータス: Accepted
- 日付: 2026-04-29
- 関連: docs/design.md §1.3, §4.4, §5.3, §6.4

## コンテキスト

GitHub Pull Request ごとに変更されたマイクロサービスのみを baseline 環境に
重ねてデプロイし、HTTP ヘッダーでスイムレーン分離するプレビュー環境を
GCP 上に学習目的で構築する。学習効果とコストのバランスを取りつつ、
不可逆な技術選択を本 ADR で固定する。

複数の選択肢があり、いずれも「動かすことはできる」が、後から差し替える
コストが高いため、着手前に明文化しておく。

## 決定

| 項目 | 採択 |
|---|---|
| クラウド | GCP |
| GCP プロジェクト | 新規作成 `k8s-action-preview-26` |
| リージョン | `us-central1`（Iowa） |
| GKE モード | Standard（ゾーナル） |
| ノード | `e2-medium` × 2 |
| Service Mesh | OSS Istio（Sidecar mode） |
| Istio profile | `default` 相当（Helm: base + istiod + gateway） |
| Istio インストール手段 | Terraform helm provider |
| ドメイン | nip.io（独自ドメイン取得しない） |
| IaC 範囲 | C: GCP + Istio まで Terraform 管理 |
| GitOps | Argo CD（kubectl + Helm で導入、Terraform 範囲外） |
| PR 環境生成 | Argo CD ApplicationSet PullRequest Generator |
| CI 認証 | GitHub Actions × Workload Identity Federation |
| リポジトリ構成 | モノレポ `mormorbump/k8s-action`（新規作成予定） |
| アプリ言語 | Go |
| PR 識別ヘッダー | `x-pr-id`（OTel baggage と併用） |
| 予算管理 | Budget Alert を Terraform で作成（50/80 USD） |

## 代替案

### クラウド・クラスタ

| 案 | メリット | デメリット | 不採用理由 |
|---|---|---|---|
| GKE Autopilot | 運用負荷低 | OSS Istio との組合せでコスト爆発 | OSS Istio を学びたい意図と矛盾 |
| GKE Standard リージョナル | 高可用性 | コスト高 | 学習用途に SLA 不要 |
| GKE Standard ゾーナル | 安価 | SLA 99.5% | **採用**（学習用途で十分） |

### Service Mesh

| 案 | メリット | デメリット | 不採用理由 |
|---|---|---|---|
| OSS Istio Sidecar | 教材多、機能安定 | リソース消費 | **採用** |
| OSS Istio Ambient | 軽量、Pod 改変なし | 教材少、機能差 | Phase 4 以降に検討 |
| Anthos Service Mesh | マネージド | 抽象化が学習目的に逆行 | 学習意図と不整合 |
| Linkerd | 軽量、シンプル | スイムレーン教材が薄い | スイムレーン題材として情報不足 |

### IaC 範囲

| 案 | 範囲 | 不採用理由 |
|---|---|---|
| A: GCP のみ | クラスタまで | Istio をクリック作業させたくない |
| B: GCP + Istio + Argo CD | 全部 Terraform | Argo CD はアプリ側ツールとして分離したい |
| C: GCP + Istio | **採用**。メッシュは土台、アプリは GitOps |

### リージョン

| 案 | 月額（最小構成） | 不採用理由 |
|---|---|---|
| asia-northeast1 (Tokyo) | ~$70 | レイテンシ良いが学習用途なので不要 |
| us-central1 (Iowa) | ~$53 | **採用**（コスト約 24% 安） |

### リポジトリ構成

| 案 | 不採用理由 |
|---|---|
| モノレポ | **採用**。個人作業で往復コストを避ける |
| 2 リポジトリ分離 | 公式ベストプラクティスだが個人には過剰 |

### PR 環境生成

| 案 | 不採用理由 |
|---|---|
| Argo CD ApplicationSet PR Generator | **採用**。GitOps の旨味を学べる |
| GitHub Actions が直接 kubectl apply | GitOps の利点を活かせない |
| GitHub Actions が GitOps repo へ commit | リポジトリにノイズ commit |

## 結果

### 採用によって縛られる選択肢
- Istio の主要バージョン互換性（GKE バージョンとセットで管理）
- Argo CD は kubectl 管理。Terraform で再現性を担保するならドキュメントで補う
- nip.io 経由のため DNS レコード管理は不要だが、TLS は HTTP-01 で取得する前提

### 後続フェーズで決めるべき残課題
- TLS 化方式の最終決定（cert-manager + Let's Encrypt or 自己署名）→ Phase 4 で
- Istio バージョンの具体値固定 → Phase 1-B で別 ADR or terraform variable のデフォルトで
- ApplicationSet PR Generator のテンプレート構造詳細 → Phase 3-D で別 ADR
- 可観測性ツール（Kiali / Prometheus / Jaeger）の採否 → Phase 4-B で

### 想定リスク
- クラスタ消し忘れによる課金 → Budget Alert + 利用後 destroy 習慣
- Istio バージョンと GKE バージョン非互換 → 公式 Supported Releases を Terraform variable で固定
- 個人 GitHub の API レート制限 → ApplicationSet の requeueAfterSeconds 緩和、PAT 認証
