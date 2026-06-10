# リソース管理: requests / limits とキャパシティ

## requests と limits

| | 意味 | 超えたら |
|---|---|---|
| requests | スケジューラが「この Pod はこれだけ使う前提」で配置計算する予約量 | 超えても殺されない（CPU は throttle なし、単に競合） |
| limits | 実行時の上限 | CPU: throttle / Memory: OOMKill |

- スケジューリングは **requests の合計 vs ノードの allocatable** だけで決まる。
  実際の使用量ではない（ここを混同しやすい）。
- allocatable = ノード容量 − system 予約。e2-medium (2 vCPU / 4GB) の
  allocatable CPU は約 940m しかない（GKE が kubelet/OS 分を予約する）。

## Phase 2 で実際に踏んだ事例

hello を replicas 2 にしたら 2 個目が Pending になった:

```
0/2 nodes are available: 2 Insufficient cpu.
```

原因の内訳（このクラスタの CPU requests）:

- istio-proxy sidecar: **Pod ごとに +100m**（Istio デフォルト）
- hello アプリ本体: 50m
- istiod 100m, ingressgateway 100m+sidecar, Argo CD 5 コンポーネント, GKE system Pod 群

教訓:

1. **メッシュに入れた Pod は sidecar の分だけ「見えない税金」を払う**。
   e2-medium 級では Pod 数の上限を CPU requests が先に決める。
2. Pending の原因は `kubectl get events --field-selector reason=FailedScheduling` で即わかる。
3. requests を盛りすぎると「実 CPU はガラガラなのに配置できない」状態になる。
   学習用クラスタでは requests を意図的に小さくする（istiod を 500m→100m にしたのと同じ話）。

## QoS クラス

| クラス | 条件 | OOM 時の死亡優先度 |
|---|---|---|
| Guaranteed | 全コンテナで requests == limits | 最後 |
| Burstable | requests < limits | 中間 |
| BestEffort | 何も指定なし | 最初 |

## AWS との比較

ECS のタスクサイズ（cpu/memory）が requests+limits の両方を兼ねるイメージ。
ECS は task 単位で固定割当なのに対し、k8s は requests(予約) と limits(上限) を
分離できるためオーバーコミットが可能。柔軟だが Pending / OOMKill の責任も自分持ち。
