# Istio を 3 段階の Helm Chart で導入する。
#
# - base: CRD と cluster-scoped リソース
# - istiod: コントロールプレーン（Pilot, Citadel, Galley 統合版）
# - gateway: Istio Ingress Gateway（外部公開の入口、特殊な Envoy）
#
# 依存順: base → istiod → gateway

resource "helm_release" "istio_base" {
  name             = "istio-base"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "base"
  namespace        = var.system_namespace
  create_namespace = true
  version          = var.istio_version

  # CRD のインストールを許可
  set {
    name  = "defaultRevision"
    value = "default"
  }
}

resource "helm_release" "istiod" {
  name       = "istiod"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "istiod"
  namespace  = var.system_namespace
  version    = var.istio_version

  # 学習用 e2-medium × 2 ノードに収まるよう resources を抑制。
  # 本番では Helm chart のデフォルト (cpu 500m / mem 2Gi) に戻すべき。
  set {
    name  = "pilot.resources.requests.cpu"
    value = var.istiod_cpu_request
  }
  set {
    name  = "pilot.resources.requests.memory"
    value = var.istiod_memory_request
  }
  set {
    name  = "pilot.autoscaleEnabled"
    value = "false"
  }
  set {
    name  = "pilot.replicaCount"
    value = "1"
  }

  depends_on = [helm_release.istio_base]
}

resource "helm_release" "istio_ingressgateway" {
  name             = "istio-ingressgateway"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "gateway"
  namespace        = var.ingress_namespace
  create_namespace = true
  version          = var.istio_version

  # Service type は LoadBalancer（GCP の External LB が作られる）
  set {
    name  = "service.type"
    value = "LoadBalancer"
  }

  # 学習用にリソース抑制
  set {
    name  = "resources.requests.cpu"
    value = var.gateway_cpu_request
  }
  set {
    name  = "resources.requests.memory"
    value = var.gateway_memory_request
  }
  set {
    name  = "autoscaling.enabled"
    value = "false"
  }
  set {
    name  = "replicaCount"
    value = "1"
  }

  depends_on = [helm_release.istiod]
}
