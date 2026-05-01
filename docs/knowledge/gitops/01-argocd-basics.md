# GitOps と Argo CD の基礎

「Git に書かれた状態 = クラスタの状態」を継続的に保証する運用思想と、
それを実装する Argo CD の使い方。

## GitOps の考え方（ツールではなく思想）

> Git に書いた状態をクラスタが継続的に追従するように同期する。
> 手作業 kubectl apply は禁止、変更は必ず Git PR 経由。

### 4 原則（Weaveworks 提唱、CNCF GitOps Working Group）

| 原則 | 意味 |
|---|---|
| Declarative | 「あるべき状態」を宣言的に書く（YAML） |
| Versioned & Immutable | Git で履歴管理、過去の状態に戻せる |
| Pulled Automatically | エージェントが Git を pull して同期 |
| Continuously Reconciled | 差分があれば自動で埋める |

### メリット

- 監査性: 誰が何をいつ変えたかが Git ログで追える
- ロールバック: 過去の commit に戻せば過去の状態に戻る
- レビュー: 変更が PR を通る
- 自動化: クラスタ操作が「Git push」に統一される

### デメリット・注意点

- Git にない設定はドリフトとして消される（手動 kubectl apply を排除）
- Secret の扱いに工夫がいる（暗号化 or external secret store）
- 緊急時の手動対応がやりづらい

## Argo CD は「k8s 上で動く Pod」

Argo CD は GitOps を実装したツール。**クラスタ内で常駐 Pod として動く**。

```
[GitHub Repo]                        [k8s Cluster]
    │                                       │
    │ ① pull                                │
    │ ←──────────── Argo CD Pod ──────────  │
    │                  │                    │
    │ ② 比較          │ ③ apply            │
    │ ←─differ─→     ↓                     │
    │              [user resources]         │
    │              (Deployment, Service,    │
    │               Istio CRD など)         │
    └───────────────────────────────────────┘
```

### Argo CD の主要コンポーネント

| Pod | 役割 |
|---|---|
| `argocd-server` | UI / API サーバー |
| `argocd-repo-server` | Git リポジトリ操作（clone, kustomize, helm） |
| `argocd-application-controller` | リソースの sync 担当（k8s に apply） |
| `argocd-redis` | キャッシュ |
| `argocd-dex-server` | OIDC SSO |
| `argocd-applicationset-controller` | ApplicationSet 専用 |

ユーザーから見ると **Web UI** と **CLI (`argocd`)** で操作する。

## 主要リソース（CRD）

Argo CD は k8s に **新しい CRD** を追加する。

### Application

「**ある Git のパス**」を「**クラスタのある場所**」に同期する単位。

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: hello-baseline
  namespace: argocd
spec:
  source:
    repoURL: https://github.com/mormorbump/k8s-action.git
    targetRevision: main
    path: gitops/overlays/baseline
  destination:
    server: https://kubernetes.default.svc
    namespace: baseline
  syncPolicy:
    automated:
      prune: true       # Git にないリソースは削除
      selfHeal: true    # ドリフトを自動修正
    syncOptions:
      - CreateNamespace=true
```

### AppProject

複数 Application をグループ化。アクセス制御単位。普段は default で OK。

### ApplicationSet（次ファイルで詳述）

「Application を**動的に複数生成**する」テンプレート機能。
PR ごとに環境を作るのに使う。

## Argo CD の動作モデル

```
1. Argo CD は Application で指定された Git を定期 pull
2. その時点の manifest を生成（kustomize build / helm template 等）
3. クラスタ内の現状とマニフェストを比較（diff）
4. 差分があれば自動 sync (automated.selfHeal=true なら)
5. ドリフト（手で kubectl edit したもの）を上書き戻す
```

ポイント:
- **Pull 型**（agent がクラスタ内から外へ pull、外部から push されない）
- **継続的に reconcile**（一度 sync して終わりではない）

## Sync の状態

Application はステータスを 2 軸で持つ:

| 状態 | 意味 |
|---|---|
| Sync Status | `Synced` / `OutOfSync` |
| Health Status | `Healthy` / `Progressing` / `Degraded` / `Missing` |

## Argo CD と他コンポーネントの関係

| 関係 | 説明 |
|---|---|
| Argo CD ↔ k8s | k8s 上で動く Pod。kubectl の代わりに apply する側 |
| Argo CD ↔ Istio | Argo CD は Istio CRD（VirtualService 等）も apply できる「運び屋」。Istio の存在は意識しない |
| Argo CD ↔ Helm | Argo CD が Helm chart を直接扱える（`source.helm`） |
| Argo CD ↔ Kustomize | 同様にネイティブ対応 |

## インストール方法

| 候補 | 採用 |
|---|---|
| Helm chart で kubectl install | ✅ Phase 2 で採用 |
| Terraform helm provider | × Terraform 範囲は GCP+Istio までと決めた |
| Argo CD Operator | × オーバーキル |

```bash
# Phase 2 で実行する想定
kubectl create namespace argocd
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd -n argocd
```

## 関連リンク

- Argo CD 公式: https://argo-cd.readthedocs.io/
- GitOps 原則: https://opengitops.dev/
- Application API: https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/
