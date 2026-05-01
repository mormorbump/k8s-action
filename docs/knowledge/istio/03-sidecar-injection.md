# Istio Sidecar Injection と iptables の魔法

Istio が「アプリのコードを変えずに通信を支配する」仕組みの内部。

## sidecar パターン（k8s での文脈）

**1 つの Pod に複数のコンテナを同居させ、メイン以外を補助役（sidecar）と
する設計パターン**。

Pod 内のコンテナは：
- **同じネットワーク namespace**: `localhost` で互いに通信、ポートを共有
- **同じ volume をマウント**可能
- **同じライフサイクル**: Pod 起動で全部上がり、Pod 削除で全部消える

ECS のタスク定義で「同じタスク内に複数コンテナ（sidekiq 等）」を立てた経験
がある場合、それは概念上完全に同じ。k8s Pod ≒ ECS Task と思って良い。

### sidecar の典型例

| ユースケース | sidecar の役割 |
|---|---|
| ログ収集 | アプリのログを fluentd / fluent-bit が収集して送信 |
| プロキシ | Envoy が通信を代行（**Istio はこれ**） |
| 設定再読み込み | Pod を再起動せず ConfigMap 変更を反映 |
| バックグラウンドジョブ | sidekiq、Cron ワーカー等 |

## Istio sidecar の独自性

ECS sidekiq との大きな違い：

| ECS sidekiq | Istio sidecar |
|---|---|
| 明示的に書く（タスク定義に列挙） | **自動注入**（Pod manifest を書き換えられる） |
| 機能追加（バックグラウンド処理） | インフラ層（通信を透過的に横取り） |
| アプリは sidecar の存在を意識する | アプリは何も知らない |

## 自動注入の仕組み

```
1. Namespace に istio-injection=enabled ラベルを付ける
       ↓
2. ユーザーが Deployment / Pod を kubectl apply
       ↓
3. apiserver が Pod を作る前に Mutating Admission Webhook を呼ぶ
       ↓
4. Webhook が Pod manifest に istio-proxy コンテナと
   istio-init initContainer を「追加」して返す
       ↓
5. 修正済みの Pod manifest が etcd に保存される
       ↓
6. kubelet が Pod を起動。istio-init が iptables を書き換え、
   その後にメインコンテナと istio-proxy が起動
```

### Mutating Admission Webhook とは

- k8s の拡張ポイント
- リソース作成時に外部 Webhook を呼び、manifest を書き換えてもらえる
- Istio の場合は istiod が webhook サーバーを兼ねる

### 確認コマンド

```bash
# 注入対象 namespace の確認
kubectl get ns -L istio-injection

# Pod の中に istio-proxy が居るか
kubectl get pod <pod> -n <ns> -o jsonpath='{.spec.containers[*].name}'

# annotation で個別 Pod の注入除外も可能
# pod metadata に sidecar.istio.io/inject: "false"
```

## iptables による透過化

注入された **istio-init initContainer** が Pod の network namespace に
対して iptables ルールを書き込む。

### 処理の流れ

```
Pod 起動
  ↓
istio-init コンテナが privileged で実行され、iptables を設定
  ↓
istio-init は終了（initContainer は使い捨て）
  ↓
メインコンテナと istio-proxy (Envoy) が起動
  ↓
以降、Pod 内の全通信が iptables ルールで Envoy にリダイレクトされる
```

### iptables ルールの内容（概念）

```
- アウトバウンド (Pod から外へ)
    全パケット → localhost:15001 (Envoy outbound listener) にリダイレクト
- インバウンド (Pod に来た通信)
    全パケット → localhost:15006 (Envoy inbound listener) にリダイレクト
- 例外:
    Envoy 自身からの通信、ヘルスチェック、メタデータ API 等は除外
```

つまり **アプリは「直接 backend を呼んでる」つもりでも、
カーネルレベルで Envoy に横取りされる**。

### initContainer とは

- メインコンテナの前に動く使い捨てコンテナ
- 全 initContainer が成功してからメインコンテナが起動
- 用途: マイグレーション、設定ファイル生成、ネットワーク設定など

## ノード側での処理（参考）

CNI plugin と組み合わせると、initContainer 方式の代わりに **CNI ベースの
注入**も選べる（`istio-cni` plugin）。privileged コンテナを減らせるので
セキュリティ的に好まれる。Phase 1 ではデフォルト（initContainer 方式）でよい。

## Ambient Mode（参考、将来）

Sidecar mode の負荷を減らすため、Istio は **Ambient mode** という
新方式を出している：

| 項目 | Sidecar mode | Ambient mode |
|---|---|---|
| Pod に Envoy を注入 | する | しない |
| データプレーン | 各 Pod の Envoy | ノード単位の ztunnel + waypoint proxy |
| iptables の使用 | する | eBPF も使う（実装による） |
| 教材・実績 | 豊富 | 比較的新しい |
| ユースケース | 学習・本番一般 | 大規模・リソース効率重視 |

今回は **Sidecar mode を採用**（教材豊富、機能安定）。Ambient は Phase 4
以降の探求対象。

## 注入されない場合のチェックリスト

1. namespace ラベル `istio-injection=enabled` が付いているか
2. Pod に annotation `sidecar.istio.io/inject: "false"` が付いていないか
3. istiod が Running になっているか
4. MutatingWebhookConfiguration が存在し、対象 namespace を含むか
   ```bash
   kubectl get mutatingwebhookconfigurations
   ```
5. istiod のログにエラーが出ていないか

## デバッグ Tips

```bash
# Pod 内のコンテナ一覧（istio-proxy が居るか）
kubectl describe pod <pod> -n <ns>

# istio-proxy のログ（Envoy のアクセスログ）
kubectl logs <pod> -n <ns> -c istio-proxy

# istio-init の実行結果
kubectl logs <pod> -n <ns> -c istio-init

# Envoy の設定ダンプ
istioctl proxy-config all <pod>.<ns>
```

## 関連リンク

- Istio Sidecar Injection: https://istio.io/latest/docs/setup/additional-setup/sidecar-injection/
- istio-init iptables: https://github.com/istio/istio/blob/master/tools/istio-iptables/
- Mutating Admission Webhook: https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/
