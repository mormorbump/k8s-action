// Package swimlane は PR プレビューのスイムレーン分離に必要な
// HTTP ヘッダー伝播を提供する。
//
// Istio はサービス間の VirtualService で x-pr-id ヘッダーを見て
// baseline / PR 環境へのルーティングを分岐する。しかし Envoy は
// 「受信リクエストのヘッダーを送信リクエストへ自動で引き継ぐ」ことは
// しない（HTTP の文脈はアプリの中で途切れるため）。
// そのためアプリ自身が受信時にヘッダーを覚え、送信時に付け直す必要がある。
// これを忘れると「1 ホップ目は PR 版に行くが 2 ホップ目から baseline に
// 逃げる」というスイムレーンの典型的故障モードになる。
package swimlane

import (
	"context"
	"net/http"
)

// propagatedHeaders は受信 → 送信に引き継ぐヘッダー。
// x-pr-id がスイムレーン分岐キー。残りは Istio/Envoy の分散トレース用
// （これを切らすと Kiali 等でトレースが繋がらなくなる）。
var propagatedHeaders = []string{
	"x-pr-id",
	"x-request-id",
	"traceparent",
	"tracestate",
	"baggage",
	"x-b3-traceid",
	"x-b3-spanid",
	"x-b3-parentspanid",
	"x-b3-sampled",
	"x-b3-flags",
}

type ctxKey struct{}

// Middleware は受信リクエストから伝播対象ヘッダーを取り出して
// context に保存するミドルウェア。
func Middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		carried := http.Header{}
		for _, name := range propagatedHeaders {
			if v := r.Header.Get(name); v != "" {
				carried.Set(name, v)
			}
		}
		ctx := context.WithValue(r.Context(), ctxKey{}, carried)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// PRID は context に保存された x-pr-id を返す（無ければ空文字）。
func PRID(ctx context.Context) string {
	if h, ok := ctx.Value(ctxKey{}).(http.Header); ok {
		return h.Get("x-pr-id")
	}
	return ""
}

// transport は context に保存されたヘッダーを送信リクエストへ付け直す
// http.RoundTripper。
type transport struct {
	base http.RoundTripper
}

func (t transport) RoundTrip(req *http.Request) (*http.Response, error) {
	if h, ok := req.Context().Value(ctxKey{}).(http.Header); ok {
		for name, values := range h {
			if req.Header.Get(name) == "" && len(values) > 0 {
				req.Header.Set(name, values[0])
			}
		}
	}
	return t.base.RoundTrip(req)
}

// NewClient は伝播対応の http.Client を返す。
// リクエストには必ず受信側の context を引き継いだ
// http.NewRequestWithContext を使うこと。
func NewClient() *http.Client {
	return &http.Client{Transport: transport{base: http.DefaultTransport}}
}
