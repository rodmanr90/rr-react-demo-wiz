output "kubernetes_connector_name" {
  description = "The Wiz Kubernetes connector name"
  value       = local.kubernetes_connector_name
}

output "wiz_namespace" {
  description = "The Wiz namespace"
  value       = kubernetes_namespace.wiz.metadata[0].name
}

output "helm_release_name" {
  description = "The Helm release name for wiz-kubernetes-integration"
  value       = helm_release.wiz_kubernetes_integration.name
}
