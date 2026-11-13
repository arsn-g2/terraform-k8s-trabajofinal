terraform {
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.53.0"
    }
  }
}

# Puerto con IP fija (equivale a: openstack port create ... --fixed-ip ... port-vmX)
resource "openstack_networking_port_v2" "port" {
  name       = "port-${var.name}"
  network_id = var.network_id

  fixed_ip {
    subnet_id  = var.subnet_id
    ip_address = var.ip_address
  }
}

# Maquina virtual conectada a traves del puerto
resource "openstack_compute_instance_v2" "vm" {
  name              = var.name
  image_name        = var.image
  flavor_name       = var.flavor
  key_pair          = var.key_pair
  availability_zone = var.availability_zone

  network {
    port = openstack_networking_port_v2.port.id
  }
}

# IP flotante y su asociacion al puerto de la VM
resource "openstack_networking_floatingip_v2" "fip" {
  pool = var.floating_ip_pool
}

resource "openstack_networking_floatingip_associate_v2" "fip_assoc" {
  floating_ip = openstack_networking_floatingip_v2.fip.address
  port_id     = openstack_networking_port_v2.port.id
}
