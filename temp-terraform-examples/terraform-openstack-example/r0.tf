# Red externa existente
data "openstack_networking_network_v2" "extnet" {
  name = "ExtNet"
}

# Router r0 con gateway hacia ExtNet
resource "openstack_networking_router_v2" "r0" {
  name                = "r0"
  admin_state_up      = true
  external_network_id = data.openstack_networking_network_v2.extnet.id
}

# Interfaces del router en subnet1 y subnet2
resource "openstack_networking_router_interface_v2" "r0_subnet1" {
  router_id = openstack_networking_router_v2.r0.id
  subnet_id = module.net1.subnet_id
}

resource "openstack_networking_router_interface_v2" "r0_subnet2" {
  router_id = openstack_networking_router_v2.r0.id
  subnet_id = module.net2.subnet_id
}
