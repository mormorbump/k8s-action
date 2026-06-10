# k8s-action

GitHub Pull Request ごとに、変更されたマイクロサービスを baseline 環境に
重ねてデプロイし、HTTP ヘッダー経由で PR 専用の通信経路を作る
**スイムレーン型のプレビュー環境**を、GCP + GKE + Istio で構築する学習プロジェクト。

## 全体構成

- **クラウド**: GCP（GKE Standard, ゾーナル, `us-central1`）
- **Service Mesh**: OSS Istio 1.27 (Sidecar mode)
- **GitOps**: Argo CD ApplicationSet (PullRequest Generator)
- **CI**: GitHub Actions × Workload Identity Federation（鍵レス）
- **IaC**: Terraform（GCP リソース + Istio まで管理）
- **ドメイン**: nip.io

```
ブラウザ
  │ app.<IP>.nip.io               (baseline)
  │ pr-<N>.preview.<IP>.nip.io    (PR プレビュー)
  ▼
Istio Ingress Gateway ── preview-entry VS が x-pr-id: <N> を注入
  ▼
frontend (PR ns) ── x-pr-id を伝播しつつ backend.baseline を呼ぶ
  ▼
backend-swimlane VS ── x-pr-id 一致 → PR の backend / 不一致 → baseline
```

## 動かし方

### PR プレビューを立てる

**オーナー本人の PR は作るだけで全自動**:

1. PR を作る → `preview` ラベルが自動付与され（auto-preview-label）、
   pr-build が head SHA タグでイメージを GAR に push
2. Argo CD ApplicationSet（5 分間隔のポーリング）が `preview-pr-<N>` namespace に環境を生成
3. `http://pr-<N>.preview.<INGRESS-IP>.nip.io/` でアクセス
4. PR クローズ or ラベル除去で自動削除（namespace の殻のみ手動削除）

第三者（フォーク）の PR は安全のため自動実行されない。
オーナーが内容を確認して `preview` ラベルを手動で付けたときだけ環境が立つ。

## 任意のアプリリポジトリを組み込む手順（ADR-0004）

この基盤は、**mormorbump 配下の任意のアプリリポジトリ**の PR にプレビュー環境を
提供できる。実装済みの例: [clipmind](https://github.com/mormorbump/clipmind)
（FastAPI + postgres/redis/qdrant の「丸ごとプレビュー」）。

### 前提条件（アプリ側が満たすべきこと）

- HTTP でリッスンする（ポートは任意。Service で 80 にマップする）
- ヘルスチェック用エンドポイントがある（`/health` 等。readinessProbe に使う）
- 設定を**環境変数**で受け取れる（DB の URL 等。プレビューごとに差し替えるため）
- DB スキーマが必要なら、マイグレーションをコマンド一発で実行できる
  （initContainer で叩く。例: `alembic upgrade head`）

### STEP 1: アプリリポジトリに Dockerfile を置く

- イメージは `linux/amd64`・CPU のみで動くこと（ノードに GPU はない）
- ML 系依存がある場合は CUDA 同梱 wheel に注意
  （clipmind では pytorch-cpu index 指定で 6.3GB → 2.4GB。
  `docs/knowledge/container/01-image-build.md` 参照）

### STEP 2: アプリリポジトリに CI を置く

`preview` ラベルを作成し、このリポジトリからワークフロー 2 本をコピーする
（**変更箇所はイメージ名のみ**）:

```bash
gh label create preview --repo mormorbump/<app> --color 0E8A16
# clipmind の実物をコピーして <app> に書き換えるのが早い
#   .github/workflows/pr-build.yaml          … head SHA タグで GAR に push
#   .github/workflows/auto-preview-label.yaml … オーナー PR に preview ラベル自動付与
```

- pr-build 内のイメージ名を `…/preview/<app>:${{ github.event.pull_request.head.sha }}` にする
- pr-build にはビルド後に**プレビュー URL を PR にコメントする job** が含まれる。
  コメント内の URL のアプリ名ラベル（`pr-<N>.<app>.…`）も書き換えること
- WIF はオーナー単位（`repository_owner == mormorbump`）で許可済みのため、
  GCP 側の追加設定は不要

### STEP 3: このリポジトリにマニフェストのテンプレートを作る

`gitops/overlays/<app>-template/` を作成（`clipmind-template/` をコピーして調整）:

| ファイル | 内容 | 調整ポイント |
|---|---|---|
| `app.yaml` | API の Deployment + Service | イメージ名, ポート, env, readinessProbe, initContainer（マイグレーション） |
| `ui.yaml` | Web UI の Deployment + Service（UI が無ければ不要） | API 接続 env 2 系統（下記） |
| `stores.yaml` | 依存ストア（不要なら削除） | ストアには `sidecar.istio.io/inject: "false"` を付けて CPU 節約 |
| `preview-istio.yaml` | 入口 VirtualService | hosts のアプリ名ラベル（`pr-0.<app>.…`）と API パスの列挙 |
| `kustomization.yaml` | 上記をまとめる | namespace プレースホルダ |

**front + API 構成の標準パターン**（clipmind-template が実例）:

- 入口 VS は「**API のパスプレフィックスを列挙し、デフォルトは UI**」の path 分岐にする。
  UI フレームワーク内部のパス（websocket 等）を列挙せずに済み、
  アプリごとの差分は「API パスの一覧」だけになる
- UI には API 接続の env を 2 系統渡す:
  - `<APP>_API_URL` … UI サーバプロセス → API（クラスタ内 DNS `http://<api-service>`）
  - `<APP>_PUBLIC_API_URL` … ブラウザが `<img src>` 等で参照する URL
    （外部ホスト。ApplicationSet が PR ごとにパッチ）

確認: `kubectl kustomize gitops/overlays/<app>-template` が通ること。

注意点:

- VS の destination は**短縮名**（例: `host: clipmind`）にする。
  ApplicationSet が namespace を差し替えるだけで行き先が PR 環境に追従する
- ストアは PVC なしの使い捨て（PR クローズで全消去）
- Secret（API キー等）はテンプレートに入れない。必要なら手動で
  PR namespace に作るか、SealedSecret 等を導入する

### STEP 4: ApplicationSet を追加して apply

`gitops/argocd/applicationsets/<app>-pr-preview.yaml`
（`clipmind-pr-preview.yaml` をコピーして `<app>` を置換）:

```yaml
generators:
  - pullRequest:
      github:
        owner: mormorbump
        repo: <app>            # ← アプリリポジトリの PR を監視
        labels: [preview]
      requeueAfterSeconds: 300
template:
  spec:
    source:
      repoURL: https://github.com/mormorbump/k8s-action.git  # ← マニフェストは本リポジトリ
      targetRevision: main
      path: gitops/overlays/<app>-template
      kustomize:
        namespace: "preview-<app>-{{number}}"
        images:
          - "us-central1-docker.pkg.dev/k8s-action-preview-26/preview/<app>:{{head_sha}}"
        patches:
          - target: { kind: VirtualService, name: preview-entry }
            patch: |-
              - op: replace
                path: /spec/hosts/0
                value: pr-{{number}}.<app>.104.154.128.86.nip.io
```

```bash
kubectl apply -f gitops/argocd/applicationsets/<app>-pr-preview.yaml
git add . && git commit && git push   # テンプレートは main から読まれるため push 必須
```

### STEP 5: 動作確認

アプリリポジトリに PR を出す（オーナーならラベル自動付与）。

```bash
gh run list --repo mormorbump/<app> --workflow pr-build   # ビルド確認
kubectl -n argocd get applications                         # <app>-pr-<N> が生える（最大5分）
curl http://pr-<N>.<app>.104.154.128.86.nip.io/health      # 200 で完成
```

### よくあるハマりどころ

| 症状 | 原因 | 対処 |
|---|---|---|
| Pod が ImagePullBackOff | sync がビルド完了より先行 | push 完了後に自動回復するので待つ |
| Pod が Pending | ノード CPU requests 満杯 | 他のプレビューを閉じる（同時 2〜3 環境が上限） |
| ホストにアクセスできない | nip.io の IP 誤パース | ホスト形式は `pr-<N>.<app>.<IP>.nip.io` を守る（`<app>` ラベル必須） |
| Application が生えない | ApplicationSet のポーリング間隔 | 最大 5 分待つ。ラベルの有無も確認 |
| 環境は消えたが namespace が残る | Argo CD は作成した namespace を消さない | `kubectl delete ns preview-<app>-<N>` |

### インフラの構築（初回）

```bash
cd terraform/envs/dev/gcp   && terraform apply   # VPC, GKE, GAR, WIF, Budget
cd terraform/envs/dev/istio && terraform apply   # Istio (base/istiod/gateway)
gcloud container clusters get-credentials preview --zone us-central1-a

# アプリレイヤ（Terraform 範囲外）
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd -n argocd --create-namespace -f gitops/argocd/values.yaml
kubectl apply -f gitops/argocd/applications/baseline.yaml
kubectl apply -f gitops/argocd/applicationsets/pr-preview.yaml

# TLS（自己署名 CA）と可観測性
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager -n cert-manager --create-namespace -f gitops/cert-manager/values.yaml
kubectl apply -f gitops/cert-manager/cluster-issuer.yaml -f gitops/cert-manager/gateway-cert.yaml
kubectl apply -f gitops/observability/prometheus.yaml -f gitops/observability/kiali.yaml
```

### Kiali（サービストポロジ）

```bash
kubectl -n istio-system port-forward svc/kiali 20001:20001
# → http://localhost:20001/kiali
```

## リポジトリ構成

| パス | 内容 |
|---|---|
| `apps/` | Go 製 frontend / backend（x-pr-id 伝播ミドルウェア込み） |
| `gitops/base/` | 環境非依存の k8s マニフェスト |
| `gitops/overlays/baseline/` | baseline 環境（共有 Gateway 含む） |
| `gitops/overlays/_template/` | PR プレビュー用テンプレート（ApplicationSet が展開） |
| `gitops/argocd/` | Argo CD 本体 values / Application / ApplicationSet |
| `terraform/` | GCP + Istio の IaC（state は 2 段に分割） |
| `docs/design.md` | 全体設計書 |
| `docs/adr/` | Architecture Decision Records（採用理由と代替案） |
| `docs/knowledge/` | 学習メモ（概念別: k8s, istio, networking, gitops 等） |

## 注意

- 学習目的のため、ノード稼働中はコストが発生します（24h で約 $55/月 + LB）
- 月次予算アラート ¥7,500 を設定済み
- 利用後は `terraform destroy`（istio → gcp の順）でリソースを削除する運用です
- 個人用 GCP プロジェクト `k8s-action-preview-26` で運用
