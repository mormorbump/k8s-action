# Istio の基礎（データプレーン / コントロールプレーン / xDS）

Istio が「何をどうやって」k8s の通信を支配しているかを理解する。

## サービスメッシュとは何か

- マイクロサービス間の **通信を仲介する層**
- アプリのコードを変えずに、L7 制御・観測・暗号化を実現
- 実装: 各 Pod に **プロキシ（Envoy）を sidecar として注入**し、
  全通信をそのプロキシ経由にする

## Istio のアーキテクチャ：2 層構造

```
┌─ コントロールプレーン (istiod) ──────────────────────┐
│ - VirtualService / DestinationRule 等の設定を読む      │
│ - Envoy 用設定 (xDS) に変換し、各 Envoy に配布         │
│ - mTLS の証明書発行 (Citadel 機能)                    │
│ - サービス検出 (k8s API を監視し endpoint を追跡)       │
└──────────────────────┬───────────────────────────────┘
                       │ xDS gRPC stream
                       ↓
┌─ データプレーン (各 Pod の Envoy sidecar) ───────────┐
│ - 実際のリクエストを処理                              │
│ - ルーティング・リトライ・タイムアウト・暗号化         │
│ - メトリクス・トレース・ログを記録                    │
└──────────────────────────────────────────────────────┘
```

### コントロールプレーン (istiod)

- **istiod** という Pod 1 つに Pilot / Citadel / Galley が統合された
- アプリ通信に直接は関与しない（リクエストの度に呼ばれることはない）
- 設定変更があったとき、影響範囲の Envoy にだけ差分配信

### データプレーン (Envoy sidecar)

- 各アプリ Pod に注入される **Envoy プロキシコンテナ**
- アプリ ↔ ネットワーク間の通信を全て中継
- istiod から受け取った xDS 設定に従って動作

## Envoy とは

**高性能な L7 プロキシ**（C++ 製、Lyft が OSS 化）。

| 特徴 | 説明 |
|---|---|
| 動的設定 | xDS API（gRPC）でリアルタイム設定更新、reload 不要 |
| L7 機能 | HTTP/1.1, HTTP/2, gRPC, WebSocket 対応 |
| 観測性 | 詳細なメトリクス、分散トレース、アクセスログを標準装備 |
| 拡張性 | フィルタチェーン、Lua、WebAssembly で拡張可能 |
| 性能 | 低オーバーヘッド、非ブロッキング I/O |

### nginx と何が違うか

| 観点 | nginx | Envoy |
|---|---|---|
| 設定更新 | ファイル書き換え + reload | xDS で差分配信、無停止 |
| 大規模動的環境 | ✕ reload 多発が課題 | ✅ メッシュ用途で実績多数 |
| サービス検出 | DNS or 静的 | xDS 経由で k8s 連動 |
| トレース対応 | 拡張モジュール | 標準対応 |

マイクロサービスの「Pod が頻繁に増減する」環境では、reload ベースの
nginx は追従が辛い。Envoy は「設定が常時流れる前提」で設計されている。

## xDS API とは

Envoy が外部のコントロールプレーンから設定を受け取るための **gRPC ベース API
ファミリー**。「x」は色々入る：

| 名前 | 配信内容 |
|---|---|
| LDS (Listener Discovery Service) | 受けるポート定義 |
| RDS (Route Discovery Service) | HTTP ルーティングルール |
| CDS (Cluster Discovery Service) | 上流のサービス群（≒ k8s Service） |
| EDS (Endpoint Discovery Service) | 各 Cluster の実 Pod IP |
| SDS (Secret Discovery Service) | TLS 証明書 |

これら全部まとめて **xDS**。Envoy はコントロールプレーンへの gRPC ストリーム
を保ち続け、設定変更があれば差分が流れてくる。

```
istiod ──── xDS gRPC stream ────→ Envoy A
       └─── xDS gRPC stream ────→ Envoy B
       └─── xDS gRPC stream ────→ Envoy C
```

→ **xDS は Envoy 側の概念**で、Istio はそれを利用する側。
他のコントロールプレーン（AWS App Mesh, Consul Connect 等）も同じ xDS で
Envoy を制御する。

## Istio をインストールすると k8s クラスタに何が増えるか

| 名称 | 種類 | 役割 |
|---|---|---|
| `istio-system` namespace | Namespace | Istio コンポーネント置き場 |
| `istiod` Deployment | コントロールプレーン | xDS 配信、CRD 監視、証明書発行 |
| `istio-ingressgateway` Deployment | データプレーン | クラスタ外からのリクエスト受口（特殊な Envoy） |
| `istio-proxy` (sidecar) | データプレーン | 各アプリ Pod に注入される Envoy |
| `IstioOperator` 等の CRD | リソース型 | VirtualService, Gateway, DestinationRule 等 |

## sidecar 注入の仕組み（概要）

詳細は `istio/03-sidecar-injection.md` に書くが、要点：

1. Namespace に `istio-injection=enabled` ラベルを付ける
2. その namespace に Pod を作ろうとすると、Mutating Admission Webhook が
   manifest を書き換えて `istio-proxy` コンテナを追加
3. 同時に `istio-init` initContainer も追加され、iptables ルールで
   Pod の通信を Envoy に強制リダイレクト
4. アプリは Envoy の存在を知らずに動く

## 関連リンク

- Istio 公式 Architecture: https://istio.io/latest/docs/ops/deployment/architecture/
- Envoy 公式: https://www.envoyproxy.io/
- xDS API 仕様: https://www.envoyproxy.io/docs/envoy/latest/api-docs/xds_protocol
