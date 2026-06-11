# ADR-0006: デプロイ定義をアプリリポジトリへ移管（プラットフォーム完全汎用化）

- 状態: 採用
- 日付: 2026-06-11
- 関連: ADR-0004（本 ADR が方針を置き換える）, ADR-0003

## 文脈

ADR-0004 では「マニフェストはプラットフォーム（k8s-action）側、アプリ側は
Dockerfile + CI だけ」とした。しかし運用すると、アプリを 1 つ足すたびに
k8s-action 側に専用の overlay（`clipmind-template/`）と専用 ApplicationSet
（`clipmind-pr-preview.yaml`）を書く必要があり、さらに「Streamlit が /static を使う」
「postgres/redis/qdrant が要る」「API のパスはどれか」といった**アプリ固有の事情を
プラットフォーム側に書き込んでいた**。これは「プラットフォームはアプリに依存しない」
という本来の要件と矛盾していた。

## 決定

デプロイ定義（k8s マニフェスト）を**アプリリポジトリの `deploy/`** に移し、
k8s-action は「リポジトリ名のリストを受け取り、各リポジトリの `deploy/` を
PR ごとにデプロイする**汎用 ApplicationSet を 1 個**」だけ持つ。

### 責務

| | アプリリポジトリ | k8s-action（プラットフォーム） |
|---|---|---|
| 持つもの | `deploy/`（namespace/app/stores/VS/kustomization）, Dockerfile, CI | 汎用 ApplicationSet 1 個 + アプリ登録簿(registry) |
| アプリ固有知識 | 全てここ | **持たない**（registry の repo 名 + イメージ名だけ） |

### プラットフォームが定める「規約」（アプリ非依存に保つための最小の約束）

アプリの `deploy/` はこれらに従う。k8s-action はこれ以外アプリを知らない。

1. **入口 VirtualService の名前は `preview-entry`**
   （k8s-action が host を PR ごとに patch するため）
2. **namespace は kustomize が `preview-<repo>-<N>` で上書き**
   （`deploy/` の namespace.yaml の name は任意。kustomize の namespace 設定で書き換わる）
3. **ホストは `pr-<N>.<repo>.<INGRESS-IP>.nip.io`**
   （k8s-action が VS の hosts[0] を patch）
4. **イメージは registry のイメージ名リストから `:{{head_sha}}` で差し替え**
   （k8s-action の kustomize.images）

### ブラウザ向け URL は相対パスにする（env patch を不要にする鍵）

UI がブラウザに渡す URL（画像の `<img src>` 等）を**絶対 URL ではなく相対パス
（`/media/...`）**にすると、ブラウザは現在のホストで解決し、同一ホストの
VirtualService が API に振り分ける。これにより「PR ごとの外部ホストを env に注入」
という**アプリ固有の patch が不要**になり、k8s-action の patch は VS host だけで済む。

### registry（k8s-action が持つ唯一のアプリ知識）

```yaml
# 汎用 ApplicationSet の list generator に埋め込む。アプリ追加 = ここに 1 エントリ
- repo: clipmind
  images: [clipmind, clipmind-ui]   # CI がビルドするイメージ名
```

`repo` 名とビルド成果物の `images` 名のみ。これは「k8s 構成」ではなく
「どのリポジトリの何というイメージか」という最小メタデータなので、依存度は低い。

## 新しいアプリを足す手順

1. アプリリポジトリに `deploy/`（規約に従う kustomize）と Dockerfile, CI を置く
2. k8s-action の registry に `{repo, images}` を 1 エントリ追加

## スイムレーン方式（ADR-0003）との関係

ADR-0003 の x-pr-id スイムレーン（baseline 共有 + 一部サービスだけ PR 版）は、
「独立 namespace に丸ごと立てる」本 ADR の汎用方式とは別パターン。
k8s-action 自身の frontend/backend デモ（`pr-preview.yaml` + `_template`）は
学習用に維持し、汎用 ApplicationSet（`preview.yaml`）は外部アプリの丸ごと
プレビューを担う。2 つのパターンが共存する。

## 結果

- 新アプリ追加で k8s-action のマニフェストを**書かない**（registry に 1 行のみ）
- アプリ固有の事情（ストア・パス・env・UI 衝突対応）は全てアプリの `deploy/` に閉じる
- `clipmind-template/` と `clipmind-pr-preview.yaml` は削除
