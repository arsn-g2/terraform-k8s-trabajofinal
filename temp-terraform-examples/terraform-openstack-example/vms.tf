# Maquinas virtuales del escenario 2.1, creadas con el modulo ./modules/vm
# Cada VM: puerto con IP fija, keypair propio, zona de disponibilidad e IP flotante

locals {
  nets = {
    net1 = module.net1
    net2 = module.net2
  }

  vms = {
    vm1 = { network = "net1", ip = "10.10.2.10", az = "nova:compute1" }
    vm3 = { network = "net1", ip = "10.10.2.11", az = "nova:compute2" }
    vm5 = { network = "net1", ip = "10.10.2.12", az = "nova:compute1" }
    vm2 = { network = "net2", ip = "10.20.2.10", az = "nova:compute2" }
    vm4 = { network = "net2", ip = "10.20.2.11", az = "nova:compute1" }
    vm6 = { network = "net2", ip = "10.20.2.12", az = "nova:compute2" }
  }
}

module "vm" {
  source   = "./modules/vm"
  for_each = local.vms

  name              = each.key
  image             = "cirros-0.3.4-x86_64-vnx"
  flavor            = "m1.tiny"
  key_pair          = openstack_compute_keypair_v2.kp[each.key].name
  availability_zone = each.value.az
  network_id        = local.nets[each.value.network].network_id
  subnet_id         = local.nets[each.value.network].subnet_id
  ip_address        = each.value.ip

  # La IP flotante solo se puede asociar cuando la subred ya esta conectada a r0
  depends_on = [
    openstack_networking_router_interface_v2.r0_subnet1,
    openstack_networking_router_interface_v2.r0_subnet2,
  ]
}
