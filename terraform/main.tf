# A Kubernetes cluster on Civo, the same shape as the hub's.
#
# The hub itself is built by `make hub-01`. This is here for the slide deck:
# `make record N=0` runs `terraform apply` against it to show a cluster being
# created, then destroys it again. The API key comes from CIVO_TOKEN.

terraform {
  required_providers {
    civo = {
      source  = "civo/civo"
      version = "~> 1.1"
    }
  }
}

variable "region" {
  default = "lon1"
}

variable "name" {
  default = "kagent-ctf"
}

provider "civo" {
  region = var.region
}

resource "civo_firewall" "cluster" {
  name                 = var.name
  create_default_rules = true
}

resource "civo_kubernetes_cluster" "cluster" {
  name         = var.name
  firewall_id  = civo_firewall.cluster.id
  cluster_type = "k3s"

  # Without this the provider leaves the kubeconfig output empty.
  write_kubeconfig = true

  pools {
    size       = "g4s.kube.medium"
    node_count = 3
  }
}

output "kubeconfig" {
  value     = civo_kubernetes_cluster.cluster.kubeconfig
  sensitive = true
}
