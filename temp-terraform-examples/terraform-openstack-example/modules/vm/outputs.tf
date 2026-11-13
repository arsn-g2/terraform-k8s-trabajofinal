output "instance_id" {
  value = openstack_compute_instance_v2.vm.id
}

output "fixed_ip" {
  value = openstack_networking_port_v2.port.all_fixed_ips[0]
}

output "floating_ip" {
  value = openstack_networking_floatingip_v2.fip.address
}
