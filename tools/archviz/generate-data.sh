#!/usr/bin/env bash
# クラスタの実状態を data.json にスナップショットする。
# 使い方:
#   ./generate-data.sh          # カレントの kubectl コンテキストから生成
#   python3 -m http.server 8123 # 同ディレクトリで配信して http://localhost:8123
set -euo pipefail
cd "$(dirname "$0")"

echo "collecting cluster state..." >&2

NODES=$(kubectl get nodes -o json | jq '[.items[] | {
  name: .metadata.name,
  cpu: .status.allocatable.cpu,
  memory: .status.allocatable.memory,
  instanceType: (.metadata.labels["node.kubernetes.io/instance-type"] // "unknown")
}]')

# kube-system / gmp-system 等の GKE 管理系は表示ノイズになるので除外
PODS=$(kubectl get pods -A -o json | jq '[.items[]
  | select(.metadata.namespace | test("^(kube-|gmp-|gke-)") | not)
  | {
    name: .metadata.name,
    namespace: .metadata.namespace,
    node: .spec.nodeName,
    phase: .status.phase,
    ready: ([.status.containerStatuses[]? | select(.ready)] | length),
    total: (.spec.containers | length),
    hasSidecar: ([.spec.containers[].name] | contains(["istio-proxy"])),
    app: (.metadata.labels.app // .metadata.labels["app.kubernetes.io/name"] // "")
  }]')

NAMESPACES=$(kubectl get ns -o json | jq '[.items[]
  | select(.metadata.name | test("^(kube-|gmp-|gke-)") | not)
  | {
    name: .metadata.name,
    injection: (.metadata.labels["istio-injection"] // "disabled")
  }]')

SERVICES=$(kubectl get svc -A -o json | jq '[.items[]
  | select(.metadata.namespace | test("^(kube-|gmp-|gke-)") | not)
  | select(.metadata.name != "kubernetes")
  | {
    name: .metadata.name,
    namespace: .metadata.namespace,
    type: .spec.type,
    externalIP: (.status.loadBalancer.ingress[0].ip // null)
  }]')

VSLIST=$(kubectl get virtualservices -A -o json 2>/dev/null | jq '[.items[] | {
  name: .metadata.name,
  namespace: .metadata.namespace,
  hosts: .spec.hosts,
  gateways: (.spec.gateways // []),
  destinations: ([.spec.http[]?.route[]?.destination.host] | unique)
}]' || echo '[]')

CLUSTER=$(kubectl config current-context | sed 's/.*_//')

jq -n \
  --argjson nodes "$NODES" \
  --argjson pods "$PODS" \
  --argjson namespaces "$NAMESPACES" \
  --argjson services "$SERVICES" \
  --argjson virtualservices "$VSLIST" \
  --arg cluster "$CLUSTER" \
  --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{cluster: $cluster, generatedAt: $generatedAt, nodes: $nodes,
    namespaces: $namespaces, pods: $pods, services: $services,
    virtualservices: $virtualservices}' > data.json

echo "wrote data.json ($(jq '.pods | length' data.json) pods, $(jq '.namespaces | length' data.json) namespaces)" >&2
