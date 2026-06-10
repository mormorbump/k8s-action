# ADR-0003: PR プレビューのスイムレーンルーティング設計

- 状態: 採用
- 日付: 2026-06-10
- 関連: design.md §6.3〜6.5, ADR-0001

## 文脈

PR ごとのプレビュー環境で、`pr-<N>.<IP>.nip.io` への入口リクエストを
PR 版サービスへ、それ以外を baseline へ振り分ける（スイムレーン）。
design.md §6.5 は当初 DestinationRule subset（`version: pr-<N>` ラベル）方式を
想定していたが、実装段階で以下を採用した。

## 決定

### 1. subset ではなく namespace FQDN でルーティングする

PR 環境は ApplicationSet が `preview-pr-<N>` namespace に丸ごとデプロイするため、
「同一 Service 内のラベル分岐（subset）」ではなく
「別 namespace の Service への振り替え（FQDN 分岐）」で表現できる。

- subset 方式: DestinationRule の管理 + version ラベルのパッチが PR ごとに必要
- FQDN 方式: VirtualService の destination host 切り替えのみ。DR 不要

→ **FQDN 方式を採用**。管理リソースが VS 2 つだけになる。

### 2. ヘッダー注入は「PR ごとの静的 VirtualService」で行う

VirtualService には「Host ヘッダーから正規表現で PR 番号を抽出して
ヘッダーに変換する」機能はない（それができるのは EnvoyFilter + Lua）。
代わりに PR ごとに生成される VS が静的に注入する:

```yaml
# preview-entry (PR namespace に生成、host は ApplicationSet がパッチ)
hosts: ["pr-42.<IP>.nip.io"]
http:
  - headers:
      request:
        set:
          x-pr-id: "42"   # 静的注入
    route:
      - destination: { host: frontend }  # 短縮名 → PR namespace に解決
```

### 3. destination の短縮名解決を利用してパッチ箇所を減らす

Istio は VS の destination host が短縮名のとき **VS 自身の namespace 基準**で
FQDN に解決する。`_template` 内の destination を短縮名にしておけば、
ApplicationSet が namespace を `preview-pr-<N>` に差し替えるだけで
行き先も PR 環境に追従する（host の JSON パッチが不要になる）。

明示性は落ちるため、baseline へ「逃がす」側の route は必ず FQDN で書く:

```yaml
# backend-swimlane (PR namespace、exportTo: ".")
hosts: ["backend.baseline.svc.cluster.local"]
http:
  - match: [{ headers: { x-pr-id: { exact: "42" } } }]
    route: [{ destination: { host: backend } }]          # 短縮名 → PR の backend
  - route:
      - destination:
          host: backend.baseline.svc.cluster.local        # FQDN → baseline 固定
```

### 4. exportTo: ["."] で影響範囲を PR namespace に閉じる

`backend-swimlane` は「baseline の backend 宛て通信を乗っ取る」VS なので、
exportTo を `.`（自 namespace のみ）に絞る。これにより
baseline や他 PR の sidecar からはこの VS が見えず、各レーンが独立する。

### 5. frontend の呼び先は常に `backend.baseline.svc.cluster.local`

PR 環境の frontend も baseline の FQDN を呼ぶ。x-pr-id が伝播していれば
VS が PR backend へ振り替え、伝播が切れていれば baseline に落ちる。
これはスイムレーンの典型的故障モード（2 ホップ目で baseline に逃げる）を
意図的に観測可能にする設計でもある。

## 結果

- PR ごとの追加リソース: Application 1 つ（中身は Deployment×2, Service×2, VS×2）
- ApplicationSet の kustomize パッチは 3 op のみ（entry の host / x-pr-id 注入値 / swimlane の match 値）
- DestinationRule は現時点で不要（subset を使う将来要件が出たら再導入）
