# GCP IAM の基本（k8s 視点）

「誰が」「何に対して」「何を」できるかを決める仕組み。

## 3 つの登場人物

```
Principal (誰が)
   ├ User Account              (mormorbump@gmail.com)
   ├ Service Account           (gha-deployer@<project>.iam.gserviceaccount.com)
   ├ Group                     (admins@example.com)
   └ External Identity (WIF)   (principalSet://...)

Role (何を)
   ├ Predefined Role           (roles/artifactregistry.writer など)
   ├ Custom Role               (組織ポリシーで定義)
   └ Basic Role                (Owner / Editor / Viewer — 広すぎるので非推奨)

Resource (何に対して)
   ├ Organization
   ├ Folder
   ├ Project
   └ Specific Resource         (Bucket, SA, Cluster, etc.)
```

## IAM の階層

GCP IAM はリソースごとに「IAM Policy」を持ち、**親リソースから継承**される：

```
Organization
  └ Folder
      └ Project
          └ Resource (Bucket, SA, Cluster, etc.)
```

「Organization レベルで Editor」をもらうと、その下の全 Project にも Editor。
逆に「Project レベルで Editor」は他 Project には影響しない。

## Service Account (SA)

「**人ではないアカウント**」。Pod や Cloud Run、GHA から GCP API を叩くときに
身に纏う。

- Email 形式: `<name>@<project>.iam.gserviceaccount.com`
- 例: `gha-deployer@k8s-action-preview-26.iam.gserviceaccount.com`

### SA への権限付与は 2 方向ある

| 方向 | 意味 |
|---|---|
| **A. SA に何かをする権限を与える** | `roles/artifactregistry.writer` を SA に付与（プロジェクトレベル） |
| **B. SA に何かが「なり代わる」権限** | `roles/iam.workloadIdentityUser` を「外部 ID」に付与（SA レベル） |

WIF の文脈では両方使う:
- A: SA に最小権限（GAR push できる等）
- B: GitHub の特定リポジトリの principalSet が SA に impersonate できる

詳細: `ci-cd/01-workload-identity-federation.md`

## kubectl と gcloud の認証アカウントの違い

ローカル開発でハマりやすい：

```
[gcloud config]
  active account: 通常使う GCP アカウント
  ├ 影響: gcloud コマンドのデフォルト動作
  └ 影響: kubectl が GKE クラスタに認証する際の Identity（!）

[gcloud auth list]
  認証済みアカウント一覧
  ├ matz@graffity.jp        (active)
  └ mormorbump@gmail.com    (not active)

[ADC (Application Default Credentials)]
  ~/.config/gcloud/application_default_credentials.json
  ├ 影響: Terraform / gcloud SDK / Pub/Sub クライアントなどの認証
  └ active account とは独立（!）
```

**個人マシンで複数アカウントを使う場合の罠**：

1. `gcloud config set account` で切り替えても、ADC は別に独立
2. `gcloud container clusters get-credentials --account=mormorbump@gmail.com` で
   credentials を取っても、**kubeconfig には active account が書かれる**
3. 結果として kubectl が想定外のアカウントで GKE に話しかける

### 対処

```bash
# active account を mormorbump に切り替えてから
gcloud config set account mormorbump@gmail.com

# credentials を取り直す
gcloud container clusters get-credentials preview --zone=us-central1-a \
  --project=k8s-action-preview-26

# active account も ADC も合わせて mormorbump に
gcloud auth application-default login
```

## よく使うロール一覧（学習プロジェクトで使うもの）

| Role | 何ができる |
|---|---|
| `roles/owner` | プロジェクト全権限。**最強・最危険**、SA に与えない |
| `roles/editor` | リソース作成・編集（IAM 変更は不可） |
| `roles/viewer` | 読み取り専用 |
| `roles/artifactregistry.writer` | GAR への push |
| `roles/artifactregistry.reader` | GAR からの pull |
| `roles/container.admin` | GKE クラスタ操作 |
| `roles/container.developer` | GKE 内のアプリ操作（Deployment, Service 等） |
| `roles/storage.objectAdmin` | GCS バケット内のオブジェクト管理 |
| `roles/billing.user` | プロジェクトを Billing Account に紐付け |
| `roles/iam.workloadIdentityUser` | WIF principal が SA を impersonate |
| `roles/iam.serviceAccountTokenCreator` | SA のトークン発行（CI で SA impersonation） |

## RBAC との関係（k8s）

GCP IAM と Kubernetes RBAC は**別レイヤー**：

```
[GCP IAM]
  Project レベルで「container.developer」を持つ User
  → GKE クラスタに対して kubectl で接続できる権限がある

[Kubernetes RBAC]
  GKE 内で「ClusterRoleBinding」「RoleBinding」を持っている User
  → Pod を get/create/delete できる権限がある
```

GKE は IAM ロールから K8s RBAC への**自動マッピング**を提供する。
例えば `roles/container.admin` を持つ User は K8s では `cluster-admin` 相当。

ただし fine-grained に管理したい場合は、IAM では `container.clusterViewer`
だけ与えて、K8s RBAC 側で個別 namespace の権限を細かく付与する設計が一般的。

## RBAC の動作確認

```bash
# 自分が何かできるか
kubectl auth can-i get pods --all-namespaces
kubectl auth can-i create deployments -n baseline

# 他人ができるか
kubectl auth can-i get pods --as=user@example.com

# Service Account ができるか
kubectl auth can-i get pods --as=system:serviceaccount:default:default
```

## 関連

- `ci-cd/01-workload-identity-federation.md` - WIF の三段構造
- `k8s/05-namespace-rbac.md` - K8s RBAC の詳細（Phase 2 で書く）
- GCP IAM 公式: https://cloud.google.com/iam/docs/overview
