locals {
  kubernetes_connector_name = "${var.prefix}-${var.random_prefix_id}-connector"
}

# Wiz Namespace
resource "kubernetes_namespace" "wiz" {
  metadata {
    name = "wiz"
  }
}

# Wiz integration deployed directly via Helm (Terraform-owned).
#
# NOTE: We intentionally do not wait for all pods to become Ready. CI and
# "demo-cycle" should succeed even when optional components (e.g. sensor) cannot
# pull images due to missing tenant pull creds.
resource "helm_release" "wiz_kubernetes_integration" {
  name       = "wiz-kubernetes-integration"
  repository = "https://wiz-sec.github.io/charts"
  chart      = "wiz-kubernetes-integration"
  version    = var.wiz_kubernetes_integration_chart_version
  namespace  = kubernetes_namespace.wiz.metadata[0].name

  wait    = false
  timeout = 900

  values = [
    templatefile("${path.module}/wiz_values.yaml", {
      kubernetes_namespace_wiz            = kubernetes_namespace.wiz.metadata[0].name
      kubernetes_connector_name           = local.kubernetes_connector_name
      cluster_type                        = var.cluster_type
      wiz_k8s_integration_client_id       = var.wiz_k8s_integration_client_id
      wiz_k8s_integration_client_secret   = var.wiz_k8s_integration_client_secret
      wiz_k8s_integration_client_endpoint = var.wiz_k8s_integration_client_endpoint
      use_wiz_sensor                      = var.use_wiz_sensor
      wiz_sensor_pull_username            = var.wiz_sensor_pull_username
      wiz_sensor_pull_password            = var.wiz_sensor_pull_password
      use_wiz_admission_controller        = var.use_wiz_admission_controller
    })
  ]

  depends_on = [kubernetes_namespace.wiz]
}
