# Define required providers
terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.23.0"
    }
  }
}

# Configure the OpenStack Provider
provider "kubernetes" {
  config_path = "~/.kube/config"
}

