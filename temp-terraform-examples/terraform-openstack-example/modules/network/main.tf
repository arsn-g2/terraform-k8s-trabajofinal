terraform {
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.53.0"
    }
  }
}

# Red interna
resource "openstack_networking_network_v2" "net" {
  name           = var.network_name
  admin_state_up = true
}

# Subred asociada a la red
resource "openstack_networking_subnet_v2" "subnet" {
  name            = var.subnet_name
  network_id      = openstack_networking_network_v2.net.id
  cidr            = var.cidr
  ip_version      = 4
  gateway_ip      = var.gateway_ip
  dns_nameservers = var.dns_nameservers

  allocation_pool {
    start = var.pool_start
    end   = var.pool_end
  }
}
