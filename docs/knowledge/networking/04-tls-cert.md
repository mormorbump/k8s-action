# TLS / 証明書管理（cert-manager + Istio Gateway）

## cert-manager の登場人物

| リソース | 役割 |
|---|---|
| Issuer / ClusterIssuer | 証明書の発行者。selfSigned / CA / ACME (Let's Encrypt) 等 |
| Certificate | 「この内容の証明書がほしい」という宣言。発行結果は Secret に入る |
| Secret (kubernetes.io/tls) | 実際の鍵ペア。参照側（Istio Gateway 等）はこれを見る |

Certificate を作ると cert-manager controller が Issuer に発行させ、
`spec.secretName` の Secret を**作成・更新（期限前の自動ローテーション）**する。

## Phase 4 で組んだ自己署名 CA の 2 段構成

```
ClusterIssuer (selfSigned)
  → Certificate preview-root-ca (isCA: true)   # ルート CA
    → ClusterIssuer preview-ca (ca: ...)        # CA 発行者
      → Certificate preview-tls (*.nip.io)      # サーバ証明書
```

nip.io ドメインで Let's Encrypt を使うと共有レート制限に当たりやすいため、
学習用は自己署名 CA。検証は `curl -k`。本番は ACME + DNS01/HTTP01 へ。

## 実際に踏んだ罠: ClusterIssuer の secret 解決先

```
Error initializing issuer: secrets "preview-root-ca" not found
```

- **ClusterIssuer はクラスタスコープ**なので、参照する secret は
  「Cluster Resource Namespace」= **cert-manager namespace** から解決される
- CA secret を使う側（istio-ingress）に置いてもダメ。cert-manager ns に置く
- namespace スコープの Issuer なら同 namespace から解決

## Istio Gateway 側の設定

```yaml
servers:
  - port: { number: 443, name: https, protocol: HTTPS }
    tls:
      mode: SIMPLE             # サーバ側 TLS 終端
      credentialName: preview-tls
    hosts: [...]
```

- `credentialName` の Secret は **Gateway Pod（Envoy）と同じ namespace**
  （= istio-ingress）に必要。istiod が SDS で Envoy に配る
- 証明書ローテーション時も Pod 再起動不要（SDS が動的更新）
- `mode: MUTUAL` にすればクライアント証明書必須（mTLS）にできる

## レイヤの整理

| 区間 | 暗号化 | 管理者 |
|---|---|---|
| ブラウザ → Ingress Gateway | この章の TLS (SIMPLE) | cert-manager + Gateway |
| sidecar ↔ sidecar | Istio の自動 mTLS（PeerAuthentication） | istiod が証明書を自動配布 |

「外向き TLS」と「メッシュ内 mTLS」は別物。メッシュ内は何も設定しなくても
istiod が SPIFFE ID 付き証明書を各 sidecar に配って暗号化している。

## AWS との比較

ACM + ALB リスナー (443) が相当。ACM は発行・ローテーションを全自動で隠蔽するが
パブリック証明書のみ。cert-manager は発行元（自己署名/私設 CA/ACME）を
自由に選べる代わりに Issuer の設計が自分持ち。
