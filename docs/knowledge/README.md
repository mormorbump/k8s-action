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
| k8s/06-resource-management.md | ✅完了 | Phase 2 | requests/limits, QoS, sidecar の CPU 税, Insufficient cpu 実例 |
| k8s/07-gke-specifics.md | ✅完了 | Phase 1 | deletion_protection, gke-gcloud-auth-plugin, active account, VPC-native, WI 2 段設定 |

### istio

| ファイル | 状態 | 関連フェーズ | 内容 |
|---|---|---|---|
| istio/01-mesh-basics.md | ✅完了 | Phase 1 | data plane / control plane, Envoy, xDS |
| istio/02-traffic-management.md | ✅完了 | Phase 1, 3 | Gateway, VirtualService, DestinationRule, subset, ヘッダー分岐 |
| istio/03-sidecar-injection.md | ✅完了 | Phase 1 | auto injection, init container, iptables, Mutating Webhook |
| istio/04-header-routing.md | ✅完了 | Phase 3 | x-pr-id スイムレーン全体像, ヘッダー注入/match, exportTo, 短縮名解決 |
| istio/05-observability.md | 未着手 | Phase 4 | Kiali, Prometheus, Jaeger |

### networking

| ファイル | 状態 | 関連フェーズ | 内容 |
|---|---|---|---|
| networking/01-cni-overlay.md | 未着手 | Phase 1 | CNI, overlay, Pod CIDR, Secondary IP Range |
| networking/02-dns.md | ✅完了 | Phase 1-C | nip.io 仕組み, 外部 DNS とクラスタ内 DNS の層の違い |
| networking/03-load-balancer.md | 未着手 | Phase 1 | GCP LB 種別, forwarding rule, NEG |
| networking/04-tls-cert.md | 未着手 | Phase 4 | cert-manager, Let's Encrypt, SNI |
| networking/05-cidr-design.md | ✅完了 | Phase 1 | Subnet/Pods/Services CIDR サイジング, max-pods-per-node, /22 採択根拠 |

### container

| ファイル | 状態 | 関連フェーズ | 内容 |
|---|---|---|---|
| container/01-image-build.md | 未着手 | Phase 1 | multi-stage build, distroless, layer cache |
| container/02-go-dockerfile-tips.md | 未着手 | Phase 3 | Go 用 Dockerfile のベストプラクティス |
| container/03-artifact-registry.md | ✅完了 | Phase 1, 2 | GAR の権限, タグ戦略, GCR 比較, ECR との対応 |

### yaml-tips

| ファイル | 状態 | 関連フェーズ | 内容 |
|---|---|---|---|
| yaml-tips/01-kustomize.md | ✅完了 | Phase 3 | base/overlay, ApplicationSet との役割分担, JSON patch の罠 |
| yaml-tips/02-helm.md | 未着手 | Phase 1 | chart 構造, values, template |
| yaml-tips/03-common-pitfalls.md | 未着手 | 全 | YAML の罠（インデント, タブ, anchor 等） |

### gitops

| ファイル | 状態 | 関連フェーズ | 内容 |
|---|---|---|---|
| gitops/01-argocd-basics.md | ✅完了 | Phase 2 | GitOps 4 原則, Argo CD は k8s 上の Pod, Application, sync |
| gitops/02-applicationset.md | ✅完了 | Phase 3 | Generator, PR Generator, トークンなし運用, managedNamespaceMetadata（Phase 3 実践済）|

### terraform

| ファイル | 状態 | 関連フェーズ | 内容 |
|---|---|---|---|
| terraform/01-state-backend.md | ✅完了 | Phase 1 | GCS backend, state lock, force-unlock, prefix 分割, lock.hcl |
| terraform/02-helm-provider.md | ✅完了 | Phase 1-B | helm_release, GKE 認証 data source, wait/timeout, リソース縮小 |
| terraform/03-google-provider.md | ✅完了 | Phase 1 | provider 設定, ADC, user_project_override, disable_on_destroy |
| terraform/04-multi-stage-apply.md | ✅完了 | Phase 1-B | state 分割と terraform_remote_state, helm provider chicken-and-egg, destroy 逆順 |

### gcp

| ファイル | 状態 | 関連フェーズ | 内容 |
|---|---|---|---|
| gcp/01-iam-fundamentals.md | ✅完了 | Phase 1 | SA / IAM binding / role / 階層, active account vs ADC, kubectl 認証 |
| gcp/02-billing-budget-gotchas.md | ✅完了 | Phase 1 | currency_code 通貨マッチ, all_updates_rule 省略, ADC user_project_override |

### ci-cd

| ファイル | 状態 | 関連フェーズ | 内容 |
|---|---|---|---|
| ci-cd/01-workload-identity-federation.md | ✅完了 | Phase 1, 2 | WIF 三段構造, attribute_mapping/condition (CEL), principalSet, GHA 連携 |
| ci-cd/02-github-actions-tips.md | ✅完了 | Phase 2, 3 | label ゲート, concurrency, matrix, head SHA タグ受け渡し |

### observability

| ファイル | 状態 | 関連フェーズ | 内容 |
|---|---|---|---|
| observability/01-otel-baggage.md | ✅完了 | Phase 3 | 分散トレース, OTel, W3C Trace Context, Baggage, x-pr-id 伝播 |
| observability/02-kiali-dashboard.md | 未着手 | Phase 4 | サービストポロジ, traffic graph |

### comparison（他クラウドとの対応）

| ファイル | 状態 | 関連フェーズ | 内容 |
|---|---|---|---|
| comparison/01-aws-ecs-mapping.md | ✅完了 | 全 | ECS/App Mesh/ECR/IAM Roles for Tasks ↔ k8s/Istio/GAR/Workload Identity, 隠蔽 vs 柔軟性比較 |

## 運用ルール

- 個別ファイルは**コンテンツが発生してから作成**する（空ファイルは作らない）
- ファイル作成・更新時は本索引の状態を必ず更新
- 過去の knowledge を実装で参照したら、本索引の該当行に
  「✅ Phase X-Y で実践」のような補足を残す
- 同じトピックを別フェーズで掘り下げた場合、ファイル末尾に
  「## Phase X での追記」のようにセクションを立てて追記する
