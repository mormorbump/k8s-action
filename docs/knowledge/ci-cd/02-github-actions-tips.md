# GitHub Actions tips（Phase 2-C / 3 で実際に使ったもの）

## ラベルでゲートする PR ワークフロー

```yaml
on:
  pull_request:
    types: [opened, synchronize, reopened, labeled]

jobs:
  build-push:
    if: contains(github.event.pull_request.labels.*.name, 'preview')
```

- `types` に `labeled` を含めることで「後からラベルを付けた」ときも発火する
- `if:` は **job レベル**に置く（workflow レベルの if は存在しない）
- ApplicationSet 側の `labels: [preview]` フィルタと対にして、
  「ラベルを付けた PR だけイメージが作られ、環境が立つ」を実現

## 二重トリガーと concurrency

PR 作成と同時にラベルを付けると `opened` と `labeled` の 2 イベントで
ワークフローが 2 本走る。`concurrency` で古い方を自動キャンセル:

```yaml
concurrency:
  group: pr-build-${{ github.event.pull_request.number }}
  cancel-in-progress: true
```

実際に Phase 3-G で 2 本走り、片方が `cancelled` になるのを確認した。

## matrix で複数サービスを並列ビルド

```yaml
strategy:
  matrix:
    service: [frontend, backend]
steps:
  - run: docker build --build-arg SERVICE=${{ matrix.service }} ...
```

モノレポ + 共用 Dockerfile（`ARG SERVICE`）と相性が良い。

## WIF 認証の決まり文句

```yaml
permissions:
  id-token: write   # OIDC トークン発行に必須。忘れると auth が即失敗
steps:
  - uses: google-github-actions/auth@v2
    with:
      workload_identity_provider: projects/<番号>/locations/global/workloadIdentityPools/github-pool/providers/github-provider
      service_account: gha-deployer@<project>.iam.gserviceaccount.com
```

仕組みの詳細は [[01-workload-identity-federation]]。

## イメージタグは head SHA で受け渡す

PR ビルドのタグに `github.event.pull_request.head.sha` を使うと、
Argo CD ApplicationSet 側の `{{head_sha}}` と**同じ値**になるため、
「CI が push したイメージを GitOps 側が一意に特定できる」。
`latest` 運用だと sync とビルドの競合で何が動いているか分からなくなる。

## CI と GitOps の競合（仕様として許容した点）

ApplicationSet の sync がイメージ push より先に走ると、
Pod は一時的に ImagePullBackOff になる。push 完了後に kubelet の
リトライで自然回復するため、学習用途では対策不要と判断。
本番では「CI 完了を待って label を付ける」「Image Updater を使う」等で解消する。

## GITHUB_TOKEN の再帰防止（実際に踏んだ）

**ワークフローが `GITHUB_TOKEN` で行った操作のイベントは、他のワークフローを
トリガーしない**（無限ループ防止の仕様）。

実例: auto-preview-label が `gh pr edit --add-label preview` でラベルを付けても、
`labeled` をトリガーに持つ pr-build は起動しなかった。

対処の選択肢:

| 方法 | 備考 |
|---|---|
| PAT / GitHub App トークンでラベル付与 | イベントが発火するが、トークン管理が増える |
| トリガーをイベント連鎖に依存させない（採用） | pr-build を `author_association == 'OWNER'` でも通す |
| ポーリング型の消費者は影響なし | Argo CD ApplicationSet は API ポーリングなのでラベルを普通に見える |

## author_association によるオーナー判定

```yaml
if: github.event.pull_request.author_association == 'OWNER'
```

public リポジトリで「本人の PR は全自動、第三者のフォーク PR は手動ゲート」を
実現する定番。値は OWNER / MEMBER / COLLABORATOR / CONTRIBUTOR / NONE 等。
フォーク PR はそもそも `pull_request` イベントでは secrets / id-token に
アクセスできないため、WIF 認証も構造的に通らない（二重の防御になる）。

## pull_request_target の注意

auto-preview-label は `pull_request_target` を使う（base ブランチの定義で実行され、
ラベル付与に必要な write 権限を持つ）。**PR のコードを checkout しない限り安全**。
checkout してビルドするのは典型的な脆弱性パターンなので pr-build 側は
通常の `pull_request` のまま。
