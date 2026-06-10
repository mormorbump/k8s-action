// backend: 自分が「どのレーンの誰か」を JSON で返すだけのサービス。
// スイムレーンルーティングの行き先確認に使う。
package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"

	"github.com/mormorbump/k8s-action/apps/internal/swimlane"
)

type info struct {
	Service   string `json:"service"`
	Version   string `json:"version"`   // baseline / pr-<N>（Pod ラベルから downward API で注入）
	Namespace string `json:"namespace"` // 配置先 namespace（downward API で注入）
	Hostname  string `json:"hostname"`  // Pod 名
	PRID      string `json:"pr_id"`     // 受信した x-pr-id（無ければ空）
	Message   string `json:"message,omitempty"`
}

func main() {
	hostname, _ := os.Hostname()

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(info{
			Service:   "backend",
			Version:   os.Getenv("VERSION"),
			Namespace: os.Getenv("NAMESPACE"),
			Hostname:  hostname,
			PRID:      swimlane.PRID(r.Context()),
			Message:   "new feature from PR!", // プレビュー環境の動作確認用
		})
	})

	addr := ":8080"
	if p := os.Getenv("PORT"); p != "" {
		addr = ":" + p
	}
	log.Printf("backend listening on %s", addr)
	log.Fatal(http.ListenAndServe(addr, swimlane.Middleware(mux)))
}
