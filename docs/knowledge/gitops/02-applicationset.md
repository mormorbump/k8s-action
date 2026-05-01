# ApplicationSet と PullRequest Generator

PR ごとに環境を立てるための Argo CD 拡張機能。kustomize overlay と
組み合わせてスイムレーン環境を実現する。

## ApplicationSet とは

「**テンプレートから複数の Application を動的に生成する**」Argo CD の拡張。

Application を 1 個 1 個書くのではなく、「**Generator**」が外部情報
（PR 一覧、ディレクトリ一覧、k8s クラスタ一覧等）を取得し、それぞれに
対して Application を生やす。

```
Generator が値の集合を生成
    ↓
[{ number: 123, head_sha: abc },
 { number: 124, head_sha: def },
 { number: 125, head_sha: ghi }]
    ↓
template に値を流し込む
    ↓
Application "pr-123"   Application "pr-124"   Application "pr-125"
    ↓                       ↓                       ↓
それぞれが kustomize overlay を apply（namePrefix で名前空間化）
```

## Generator の種類

| Generator | 用途 |
|---|---|
| **PullRequest** | GitHub/GitLab の PR 一覧から生成 ← **今回採用** |
| List | 静的リスト |
| Cluster | 登録された k8s クラスタごと |
| Git | Git リポジトリのディレクトリごと |
| Matrix | 複数の Generator の直積 |
| Merge | 複数の Generator の結合 |

## PullRequest Generator の動作

```
1. ApplicationSet controller が GitHub API を叩く
2. 「open な PR」の一覧を取得
3. ラベルフィルタ等で対象 PR を絞り込む
4. 各 PR の {number, branch, head_sha, ...} を template に渡す
5. PR ごとに Application が生成される
6. PR がクローズ or ラベル外しされると、Application が削除（prune）
```

### 採用例（Phase 3 で使う想定）

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: pr-preview
  namespace: argocd
spec:
  generators:
    - pullRequest:
        github:
          owner: mormorbump
          repo: k8s-action
          tokenRef:
            secretName: github-token
            key: token
          labels:
            - preview        # この label が付いた PR のみ対象
        requeueAfterSeconds: 60
  template:
    metadata:
      name: 'pr-{{number}}'
    spec:
      source:
        repoURL: https://github.com/mormorbump/k8s-action.git
        targetRevision: '{{head_sha}}'
        path: gitops/overlays/_template
        kustomize:
          namePrefix: 'pr-{{number}}-'
          commonLabels:
            preview.example.com/pr-id: '{{number}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: 'preview-pr-{{number}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
```

## kustomize overlay とは（前提）

**kubectl 標準内蔵**の YAML 重ね合わせツール。「base + 上書き差分」で
派生 manifest を作る。テンプレートエンジン（Helm 等）と違い、純粋な YAML
レイヤリングで完結する。

### 構造

```
gitops/
├── base/                       # 共通定義（変えない）
│   ├── frontend/
│   │   ├── kustomization.yaml
│   │   ├── deployment.yaml
│   │   └── service.yaml
│   └── backend/
│       ├── kustomization.yaml
│       ├── deployment.yaml
│       └── service.yaml
└── overlays/
    ├── baseline/                # baseline 用の上書き
    │   ├── kustomization.yaml   # base を参照 + 設定追加
    │   └── patch-replicas.yaml  # 例: replicas 増やす
    └── _template/               # PR 用テンプレ
        ├── kustomization.yaml   # base 参照 + ApplicationSet が namePrefix を上書き
        └── patch-image.yaml
```

### kustomization.yaml の例

```yaml
# overlays/baseline/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: baseline
resources:
  - ../../base/frontend
  - ../../base/backend
patchesStrategicMerge:
  - patch-replicas.yaml
commonLabels:
  env: baseline
```

`kubectl apply -k overlays/baseline` で base + overlay が合成・適用される。

### ApplicationSet による派生

ApplicationSet が `_template` を見つつ、テンプレ変数で：

| 上書き | 効果 |
|---|---|
| `namePrefix: 'pr-{{number}}-'` | リソース名に `pr-123-` 接頭辞 |
| `commonLabels: pr-id: '{{number}}'` | 全リソースに label 追加 |
| image tag → `{{head_sha}}` | PR コミットの image を pull |

→ PR ごとにユニークな名前・ラベル・イメージを持つ同じ構造のリソース群が
派生する。

## 「差分だけデプロイ」の正体（重要な誤解ポイント）

> Istio がルーティングしてくれるから、変えてないサービスはデプロイ不要

これは正しい。ただし**「ApplicationSet が PR の git diff を解析して
自動で差分だけ作る」わけではない**。

| 質問 | 答え |
|---|---|
| ApplicationSet は git diff を見る？ | **× 見ない** |
| じゃあどうやって変更分だけ作る？ | **設計次第**（GitHub Actions が `_template/` を生成してコミット する 等） |

実装パターン：

| パターン | 仕組み |
|---|---|
| A. テンプレ固定 | `_template/` に「変更されうる全サービス」を入れておき、PR で必ず全部デプロイ。シンプルだが資源浪費 |
| B. CI で `_template/` を動的生成 | GitHub Actions が PR の変更を検知し、`_template/` の中身を必要なものだけに書き換えてコミット。複雑だが効率的 |
| C. ハイブリッド | デフォルトで全部デプロイ、ラベルで除外可能 |

Phase 3 で B を採用予定。Phase 1 ではここまでの理解で十分。

## Argo CD ApplicationSet が動く仕組み

```
[GitHub PR 一覧]
    ↑ poll (requeueAfterSeconds 間隔)
[applicationset-controller Pod]
    ↓ Application を作成 / 更新 / 削除
[argocd-application-controller Pod]
    ↓ Application が指す Git path を sync
[k8s cluster: preview-pr-NNN namespace]
    └─ Pod, Service, Istio resources がデプロイされる
```

PR がクローズされたら ApplicationSet が Application を消し、
`prune: true` により紐づくリソースも削除される。

## 関連リンク

- ApplicationSet: https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/
- PullRequest Generator: https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-Pull-Request/
- kustomize 公式: https://kustomize.io/
