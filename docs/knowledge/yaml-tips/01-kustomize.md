# Kustomize: base / overlay とテンプレート化

## 基本構造（このリポジトリの実物）

```
gitops/
├── base/
│   ├── frontend/   # 環境に依存しない Deployment + Service
│   └── backend/
└── overlays/
    ├── baseline/   # base を参照し、namespace と Istio リソースを足す
    └── _template/  # PR プレビュー用。ApplicationSet が値を差し替える
```

base は「どの環境でも変わらない形」、overlay は「環境差分」だけを持つ。
Helm のような変数テンプレートではなく **YAML を構造的に変換する**のが特徴。

## overlay でよく使う機能

```yaml
# kustomization.yaml
namespace: baseline          # 全リソースの metadata.namespace を強制上書き
resources:
  - ../../base/frontend      # base の参照（相対パス）
  - gateway.yaml             # overlay 固有の追加リソース
images:
  - name: old-image          # イメージ名・タグの差し替え
    newTag: v2
patches:                     # 一部フィールドの上書き
  - target: { kind: Deployment, name: frontend }
    patch: |-
      - op: replace
        path: /spec/replicas
        value: 2
```

## Argo CD ApplicationSet との組み合わせ（Phase 3 の核心）

kustomize 自体には変数機能がないため、「PR 番号で変わる値」は
**Application の spec.source.kustomize を ApplicationSet がテンプレート展開**して注入する:

```yaml
# ApplicationSet template 内
kustomize:
  namespace: "preview-pr-{{number}}"   # namespace 変換
  images:
    - "…/frontend:{{head_sha}}"        # イメージタグ差し替え
  patches:
    - target: { kind: VirtualService, name: preview-entry }
      patch: |-
        - op: replace
          path: /spec/hosts/0
          value: pr-{{number}}.<IP>.nip.io
```

役割分担:

- **kustomize**: 構造変換の実行エンジン（namespace, images, patch）
- **ApplicationSet**: `{{number}}` `{{head_sha}}` の値を供給するテンプレート層

「kustomize に変数がない」ことを ApplicationSet が補い、
「ApplicationSet に YAML 変換能力がない」ことを kustomize が補う関係。

## 落とし穴

| 罠 | 内容 |
|---|---|
| JSON patch の path 不存在 | `op: replace` は対象 path が存在しないとエラー。テンプレート側にプレースホルダを必ず置いておく |
| namespace 変換と FQDN | kustomize は文字列内の FQDN（VS の destination 等）までは書き換えない。短縮名解決か明示パッチで対応（ADR-0003） |
| 検証 | `kubectl kustomize <dir>` でローカル展開して目視確認してから push |
