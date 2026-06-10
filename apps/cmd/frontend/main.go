// frontend: HTTP を受けて backend を呼び、両者の素性をまとめて返す。
// backend の呼び先は常に baseline の Service 名（BACKEND_URL）であり、
// x-pr-id ヘッダーが付いていれば Istio の VirtualService が
// PR 環境の backend へ振り替える（= スイムレーン）。
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
	Version   string `json:"version"`
	Namespace string `json:"namespace"`
	Hostname  string `json:"hostname"`
	PRID      string `json:"pr_id"`
}

type response struct {
	Frontend info            `json:"frontend"`
	Backend  json.RawMessage `json:"backend"`
}

func main() {
	hostname, _ := os.Hostname()
	backendURL := os.Getenv("BACKEND_URL")
	if backendURL == "" {
		backendURL = "http://backend"
	}
	client := swimlane.NewClient()

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		self := info{
			Service:   "frontend",
			Version:   os.Getenv("VERSION"),
			Namespace: os.Getenv("NAMESPACE"),
			Hostname:  hostname,
			PRID:      swimlane.PRID(r.Context()),
		}

		// 受信時の context を引き継ぐことで x-pr-id が backend へ伝播する
		req, err := http.NewRequestWithContext(r.Context(), http.MethodGet, backendURL, nil)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		var backend json.RawMessage
		resp, err := client.Do(req)
		if err != nil {
			backend, _ = json.Marshal(map[string]string{"error": err.Error()})
		} else {
			defer resp.Body.Close()
			var buf json.RawMessage
			if err := json.NewDecoder(resp.Body).Decode(&buf); err != nil {
				backend, _ = json.Marshal(map[string]string{"error": err.Error()})
			} else {
				backend = buf
			}
		}

		w.Header().Set("Content-Type", "application/json")
		enc := json.NewEncoder(w)
		enc.SetIndent("", "  ")
		enc.Encode(response{Frontend: self, Backend: backend})
	})

	addr := ":8080"
	if p := os.Getenv("PORT"); p != "" {
		addr = ":" + p
	}
	log.Printf("frontend listening on %s (backend=%s)", addr, backendURL)
	log.Fatal(http.ListenAndServe(addr, swimlane.Middleware(mux)))
}
