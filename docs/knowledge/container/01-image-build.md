# コンテナイメージのビルド設計

このリポジトリ（Go）と clipmind（Python/uv）で実際に組んだ 2 パターン。

## パターン1: Go + distroless（apps/Dockerfile）

```dockerfile
FROM golang:1.26 AS build
ARG SERVICE
COPY go.mod ./
COPY . .
RUN CGO_ENABLED=0 go build -o /bin/app ./cmd/${SERVICE}

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /bin/app /app
ENTRYPOINT ["/app"]
```

- `CGO_ENABLED=0` で静的リンク → libc 不要 → `distroless/static` で動く
- distroless にはシェルもパッケージマネージャもない（攻撃面・容量とも最小、数十 MB）
- デバッグは `kubectl debug` の ephemeral container で行う（exec できない）

## パターン2: Python + uv（clipmind/Dockerfile）

```dockerfile
FROM python:3.12-slim AS runtime
COPY --from=ghcr.io/astral-sh/uv:0.7 /uv /usr/local/bin/uv
WORKDIR /app
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project   # 依存だけ先に
COPY src/ src/
RUN uv sync --frozen --no-dev                        # アプリ本体
ENV PATH="/app/.venv/bin:$PATH"
CMD ["uvicorn", "clipmind.api.main:app", ...]
```

- **依存インストールとアプリコピーを分離**するとコード変更時に
  依存レイヤがキャッシュされ、再ビルドが数秒になる
- `--frozen` で uv.lock どおりに入れる（CI とローカルで完全一致）

## 実際に踏んだ罠: CUDA で 6.28GB

ultralytics (YOLO) → torch の依存連鎖で、デフォルトの PyPI wheel が
**CUDA 同梱**だった: nvidia 2.7GB + torch 1.1GB + triton 0.7GB。

調査方法:

```bash
docker run --rm --entrypoint sh IMAGE -c \
  "du -sm /app/.venv/lib/python*/site-packages/* | sort -rn | head"
```

対処（uv の PyTorch CPU index 指定）:

```toml
[[tool.uv.index]]
name = "pytorch-cpu"
url = "https://download.pytorch.org/whl/cpu"
explicit = true

[tool.uv.sources]
torch = [{ index = "pytorch-cpu", marker = "sys_platform == 'linux'" }]
torchvision = [{ index = "pytorch-cpu", marker = "sys_platform == 'linux'" }]
```

注意点 2 つ:

1. **`tool.uv.sources` は直接依存にしか効かない**。torch が推移的依存なら
   `[project].dependencies` に torch を明示してから sources を書く
2. `marker = "sys_platform == 'linux'"` で macOS ローカル開発に影響させない

## イメージサイズが効いてくる場所

| 場所 | 影響 |
|---|---|
| ノードへの pull | プレビュー環境の初回起動時間（GB 級だと分単位） |
| GAR ストレージ | PR ごとに SHA タグで積むので地味に課金が効く |
| GHA ビルド時間 | レイヤキャッシュなしのクリーンビルドが基準になる |
