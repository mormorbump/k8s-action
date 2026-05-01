# Knowledge 索引

学習目的で、各フェーズの実装中に得た概念・tips・落とし穴を
トピック別に集約する。時系列ではなく**概念別**で書く。

## 状態の凡例

- 未着手: ファイル未作成
- 執筆中: 一部のみ記述
- ✅完了: 主要概念を網羅

## トピック一覧

### k8s

| ファイル | 状態 | 関連フェーズ | 内容 |
|---|---|---|---|
| k8s/01-cluster-anatomy.md | ✅完了 | Phase 1 | control plane / node / kubelet / etcd / Node Pool |
| k8s/02-workloads.md | ✅完了 | Phase 1, 3 | Pod = 1 microservice, Deployment, ReplicaSet, StatefulSet, ラベル |
| k8s/03-networking.md | ✅完了 | Phase 1, 3 | Service, Ingress, DNS→ClusterIP→iptables の流れ, Istio との住み分け |
| k8s/04-config.md | 未着手 | Phase 2, 3 | ConfigMap, Secret, env, volume |
| k8s/05-namespace-rbac.md | 未着手 | Phase 2 | namespace 設計, RBAC, ServiceAccount |
| k8s/06-resource-management.md | 未着手 | Phase 3 | requests/limits, QoS, HPA |
| k8s/07-gke-specifics.md | 未着手 | Phase 1 | GKE 固有: Workload Identity, Standard |

### istio

| ファイル | 状態 | 関連フェーズ | 内容 |
|---|---|---|---|
| istio/01-mesh-basics.md | ✅完了 | Phase 1 | data plane / control plane, Envoy, xDS |
| istio/02-traffic-management.md | ✅完了 | Phase 1, 3 | Gateway, VirtualService, DestinationRule, subset, ヘッダー分岐 |
| istio/03-sidecar-injection.md | ✅完了 | Phase 1 | auto injection, init container, iptables, Mutating Webhook |
| istio/04-header-routing.md | 未着手 | Phase 3 | match による分岐, スイムレーン実装 |
| istio/05-observability.md | 未着手 | Phase 4 | Kiali, Prometheus, Jaeger |

### networking

| ファイル | 状態 | 関連フェーズ | 内容 |
|---|---|---|---|
| networking/01-cni-overlay.md | 未着手 | Phase 1 | CNI, overlay, Pod CIDR, Secondary IP Range |
| networking/02-dns.md | 未着手 | Phase 1 | cluster DNS, nip.io 仕組み, search path |
| networking/03-load-balancer.md | 未着手 | Phase 1 | GCP LB 種別, forwarding rule, NEG |
| networking/04-tls-cert.md | 未着手 | Phase 4 | cert-manager, Let's Encrypt, SNI |
| networking/05-cidr-design.md | ✅完了 | Phase 1 | Subnet/Pods/Services CIDR サイジング, max-pods-per-node, /22 採択根拠 |

### container

| ファイル | 状態 | 関連フェーズ | 内容 |
|---|---|---|---|
| container/01-image-build.md | 未着手 | Phase 1 | multi-stage build, distroless, layer cache |
| container/02-go-dockerfile-tips.md | 未着手 | Phase 3 | Go 用 Dockerfile のベストプラクティス |
| container/03-artifact-registry.md | 未着手 | Phase 1, 2 | GAR の権限, タグ戦略 |

### yaml-tips

| ファイル | 状態 | 関連フェーズ | 内容 |
|---|---|---|---|
| yaml-tips/01-kustomize.md | 未着手 | Phase 2, 3 | base/overlay, patch, namePrefix |
| yaml-tips/02-helm.md | 未着手 | Phase 1 | chart 構造, values, template |
| yaml-tips/03-common-pitfalls.md | 未着手 | 全 | YAML の罠（インデント, タブ, anchor 等） |

### gitops

| ファイル | 状態 | 関連フェーズ | 内容 |
|---|---|---|---|
| gitops/01-argocd-basics.md | ✅完了 | Phase 2 | GitOps 4 原則, Argo CD は k8s 上の Pod, Application, sync |
| gitops/02-applicationset.md | ✅完了 | Phase 3 | Generator, PR Generator, kustomize overlay, 「差分デプロイ」の正体 |

### terraform

| ファイル | 状態 | 関連フェーズ | 内容 |
|---|---|---|---|
| terraform/01-state-backend.md | 未着手 | Phase 1 | GCS backend, lock, workspace, prefix 分割 |
| terraform/02-helm-provider.md | 未着手 | Phase 1 | Terraform で Helm chart を扱う際の注意 |
| terraform/03-google-provider.md | 未着手 | Phase 1 | google / google-beta provider 使い分け |
| terraform/04-multi-stage-apply.md | 未着手 | Phase 1 | state 分割と terraform_remote_state, helm provider chicken-and-egg |

### gcp

| ファイル | 状態 | 関連フェーズ | 内容 |
|---|---|---|---|
| gcp/01-iam-fundamentals.md | 未着手 | Phase 1 | SA / IAM binding / role 階層 / Workload Identity の理解基盤 |

### ci-cd

| ファイル | 状態 | 関連フェーズ | 内容 |
|---|---|---|---|
| ci-cd/01-workload-identity-federation.md | 未着手 | Phase 1, 2 | WIF の三段構造, attribute_condition (CEL), GitHub Actions 連携 |
| ci-cd/02-github-actions-tips.md | 未着手 | Phase 2, 3 | reusable workflow, matrix, concurrency |

### observability

| ファイル | 状態 | 関連フェーズ | 内容 |
|---|---|---|---|
| observability/01-otel-baggage.md | ✅完了 | Phase 3 | 分散トレース, OTel, W3C Trace Context, Baggage, x-pr-id 伝播 |
| observability/02-kiali-dashboard.md | 未着手 | Phase 4 | サービストポロジ, traffic graph |

## 運用ルール

- 個別ファイルは**コンテンツが発生してから作成**する（空ファイルは作らない）
- ファイル作成・更新時は本索引の状態を必ず更新
- 過去の knowledge を実装で参照したら、本索引の該当行に
  「✅ Phase X-Y で実践」のような補足を残す
- 同じトピックを別フェーズで掘り下げた場合、ファイル末尾に
  「## Phase X での追記」のようにセクションを立てて追記する
