# ADR-0005: プレビュー環境のクリーンアップとキャパシティ

- 状態: 採用
- 日付: 2026-06-10
- 関連: ADR-0003, ADR-0004

## 文脈

PR プレビューを繰り返すうちに、2 種類の「残骸」と 1 つの容量制約が見えた。

### 1. namespace の殻が残る

ApplicationSet の `CreateNamespace=true` で自動作成された namespace は、
PR クローズで Application が prune されても**削除されない**
（Argo CD は自分が「自動作成」した namespace を管理リソースとして追跡しないため）。
結果、`preview-clipmind-8` のような空の namespace が溜まっていた。
中の Pod は消えるので CPU は食わないが、運用上のゴミになる。

### 2. GAR イメージが溜まる

PR ごとに head SHA タグのイメージ（clipmind / clipmind-ui 等）が push され、
PR クローズ後も Artifact Registry に残り続ける。GitOps の prune 対象外。
ストレージ課金とイメージ一覧の肥大化につながる。

### 3. CPU キャパシティ（容量不足の正体）

「容量不足」は**クリーンアップ不足が主因ではない**。実測の CPU requests:

| namespace | CPU requests |
|---|---|
| kube-system（GKE 管理） | 1412m |
| baseline / istio-system | 各 60m |
| istio-ingress | 50m |
| cert-manager | 30m |
| その他 | ~20m |

e2-medium × 2 = allocatable **1880m** に対し常駐で約 1650m を消費し、
空きは 1 ノードに ~190m 程度。clipmind プレビュー 1 環境
（app+ui+sidecar+stores ≒ 190m）でほぼ埋まる。
**根本原因はノードが小さいこと**であり、同時プレビューは実質 1〜2 環境が上限。

## 決定

### namespace をマニフェスト管理にする

各 overlay に `namespace.yaml`（istio-injection ラベル付き）を置き、
ApplicationSet を `CreateNamespace=false` にする。namespace が Application の
管理リソースになり、prune + finalizer のカスケード削除で殻ごと消える。

- kustomize の `namespace:` 設定は **Namespace リソース自身の name も書き換える**ため、
  ApplicationSet が渡す `preview-<app>-<N>` がそのまま name になる（patch 不要）
- 既存の稼働中環境も、再 sync 時に同名 namespace を adopt できる（無停止で移行）

### GAR に cleanup policy を設定する

Terraform の `google_artifact_registry_repository.cleanup_policies` で
「最新 20 バージョンは KEEP、それ以外で 14 日より古いものは DELETE」。
KEEP は DELETE より優先されるため、活発な PR のイメージは保護される。

### 容量はノード増設で対応する（必要時）

クリーンアップでは CPU は空かない。同時に多数のプレビューが必要になったら、
ノードプールの台数増・マシンタイプ変更・Spot ノードプール追加で対応する
（コスト判断はオーナー）。現状は「同時 1〜2 環境」の制約を許容し、
不要なプレビューは PR クローズで自然に解放する運用。

## 結果

- PR クローズ → Pod・VirtualService・**namespace** がすべて自動削除（殻が残らない）
- GAR イメージは上限付きで自動回収され、ストレージが無限に増えない
- 容量の限界（同時 1〜2 環境）が明文化され、超える場合の打ち手も整理された
