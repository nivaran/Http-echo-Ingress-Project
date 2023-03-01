terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.0"
    }
  }
}
provider "kubernetes" {
  config_path = "~/.kube/config"
}

locals {
  appdata = jsondecode(file("applications.json")) 
  apps = { for app,v in local.appdata.applications : app => v }
}

resource "kubernetes_deployment" "test" {
  for_each = local.apps
  metadata {
    name      = each.value.name
  }
  spec {
    replicas = each.value.replicas
    selector {
      match_labels = {
        app = each.value.name
      }
    }
    template {
      metadata {
        labels = {
          app = each.value.name
        }
      }
      spec {
        container {
          image = each.value.image
          name  = each.value.name
          port {
            container_port = each.value.port
          }
          args = split(" -",each.value.args)
        }
      }
    }
  }
}

resource "kubernetes_service" "test_service" {
  depends_on = [resource.kubernetes_deployment.test]
  for_each = local.apps
  metadata {
    name = "${each.value.name}-service"
}
  spec {
    selector = {
      app = each.value.name
    }
   # session_affinity = "ClientIP"
    port {
      port        = each.value.port
      target_port = each.value.port
    }
    type = "NodePort"
  }
}

resource "kubernetes_ingress_v1" "test_ingress" {
  depends_on = [resource.kubernetes_service.test_service]
  for_each = local.apps
  wait_for_load_balancer = true
  metadata {
    name = "${each.value.name}-canary-ingress"
	annotations = {
      "kubernetes.io/ingress.class" = "nginx"
      "nginx.ingress.kubernetes.io/canary" = "true"
      "nginx.ingress.kubernetes.io/canary-weight" = each.value.traffic_weight
      "kubernetes.io/elb.port" = "80"
    }
  }
  spec {
   # ingress_class_name = "nginx"
    rule {
      http {
        path {
          path = "/*"
          backend {
            service {
              name = "${each.value.name}-service"
              port {
                number = each.value.port
              }
            }
          }
        }
      }
    }
  }
}
