# ADR-0004: プラットフォーム / アプリリポジトリの分離

- 状態: 置換済み（ADR-0006 により方針を更新。マニフェストはアプリ側 deploy/ へ移管）
- 日付: 2026-06-10
- 関連: ADR-0001, ADR-0003, ADR-0006

## 文脈

Phase 3 までの PR プレビューは、プラットフォーム（k8s-action）リポジトリ自身の
PR を対象としていた。これは学習用のショートカットであり、本来のユースケースは
「**任意のアプリリポジトリ**に PR を出すとプレビュー環境が立つ」こと。
最初の対象として mormorbump/clipmind（FastAPI 製 RAG アプリ）を組み込む。

## 決定

### 1. 責務の分離

| | アプリリポジトリ (clipmind) | プラットフォームリポジトリ (k8s-action) |
|---|---|---|
| 持つもの | ソースコード, Dockerfile, pr-build / auto-preview-label ワークフロー | k8s マニフェストのテンプレート, ApplicationSet, インフラ |
| 供給するもの | head SHA タグ付きイメージ | プレビュー環境の形（Deployment/Service/VS） |

### 2. Generator とマニフェストソースの分離を利用する

ApplicationSet PullRequest Generator の「PR を監視するリポジトリ」と
Application の「マニフェスト取得元 (source.repoURL)」は独立に指定できる。

```yaml
generators:
  - pullRequest:
      github: { owner: mormorbump, repo: clipmind }   # PR の監視先
template:
  spec:
    source:
      repoURL: https://github.com/mormorbump/k8s-action.git  # マニフェストはこちら
      targetRevision: main
      kustomize:
        images: [".../clipmind:{{head_sha}}"]          # PR 由来なのはタグだけ
```

これによりアプリリポジトリに k8s マニフェストを持ち込まずに済む
（アプリ開発者は k8s を知らなくてよい）。
代償として「マニフェスト自体を PR で変えるプレビュー」はできないが、
それはプラットフォーム側（k8s-action の PR プレビュー）の領分。

### 3. WIF は owner 単位に緩和

`assertion.repository == "mormorbump/k8s-action"` →
`assertion.repository_owner == "mormorbump"`。
mormorbump 配下のどのリポジトリの Actions も GAR に push できる。
SA の権限は Artifact Registry writer のみで据え置き（最小権限は維持）。

### 4. 単一サービスアプリは「丸ごとプレビュー」方式

clipmind はマイクロサービスではないため x-pr-id スイムレーンは使わず、
app + 依存ストア（qdrant / redis / postgres）を PR namespace に丸ごと立てる。

- ストアは使い捨て（PVC なし）。PR クローズで全消去
- ストアには sidecar を注入しない（CPU 節約、TCP 通信にメッシュ機能不要）
- LLM API キーは注入しない（ヘルスチェックと非 LLM 機能のプレビューが目的）

スイムレーン方式（ADR-0003）と丸ごと方式は共存し、アプリの形で選ぶ:

| アプリの形 | 方式 |
|---|---|
| マイクロサービス群の一部を変更 | スイムレーン（変更サービスだけ PR 版） |
| 単一サービス + 専用ストア | 丸ごとプレビュー |

### 5. ホスト命名規約

`pr-<N>.<アプリ名>.<INGRESS-IP>.nip.io`。アプリ名ラベルで複数アプリの
プレビューが同一 Gateway（ワイルドカード）に共存できる。
nip.io の IP 誤パース対策（ADR-0003 の knowledge 参照）も兼ねる。

## 結果

- アプリリポジトリの導入コスト: Dockerfile + ワークフロー 2 ファイルのコピーのみ
- プラットフォーム側の導入コスト: テンプレート overlay 1 ディレクトリ + ApplicationSet 1 ファイル
- 制約: クラスタ容量（e2-medium × 2）により同時プレビューは 2〜3 環境まで
