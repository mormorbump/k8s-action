# archviz — クラスタアーキテクチャの 3D ビューア

クラスタの実状態（namespace / Pod / ノード / VirtualService / LB）を
スナップショットし、Three.js でブラウザに立体表示する。

![archviz](https://raw.githubusercontent.com/mormorbump/k8s-action/main/docs/images/archviz.png)

## 使い方

```bash
cd tools/archviz
./generate-data.sh          # kubectl で実クラスタから data.json を生成
python3 -m http.server 8123 # 配信
open http://localhost:8123  # ブラウザで閲覧
```

PR プレビュー環境を立てたり消したりしたあとに `generate-data.sh` を
再実行してリロードすると、namespace 島が増減するのが見える。

## 見方

| 表現 | 意味 |
|---|---|
| 暗いプラットフォーム | GKE クラスタ |
| 色付きの島 | namespace（青枠 + ⛴ = istio-injection 有効） |
| 箱 | Pod（緑=Running/Ready, 黄=Pending/NotReady, 赤=Failed） |
| 箱の手前の青いチップ | istio-proxy sidecar |
| 箱の足元のストライプ色 | 配置されているノード（奥のスラブと同色） |
| 紫の曲線 + 流れる粒子 | Gateway 経由のトラフィック（VirtualService 由来、ラベル=Host） |
| 青緑の曲線 | メッシュ内 VirtualService（スイムレーン等） |
| 左の球 / 黄色い柱 | インターネット / Cloud Load Balancer（External IP） |

マウス: ドラッグで回転、ホイールでズーム、Pod / ノード / LB にホバーで詳細パネル。

## 仕組み

- `generate-data.sh`: kubectl + jq でクラスタ状態を `data.json` に吐く
  （GKE 管理系 namespace は除外）。クラスタへの接続はこのときだけ
- `index.html` / `main.js`: 静的ページ。Three.js は CDN の import map で取得。
  ビルド工程なし、`data.json` を fetch して描画するだけ
- ホバー詳細・凡例・タイトルは DOM HUD（WebGL 外）に置き、
  ラベルは CSS2DRenderer で 3D 位置に追従させている
