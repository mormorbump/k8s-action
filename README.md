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
