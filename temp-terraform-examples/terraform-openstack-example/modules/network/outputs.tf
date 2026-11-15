# this file is an example, not part of the project. this file will be deleted
output "network_id" {
  value = openstack_networking_network_v2.net.id
}

output "network_name" {
  value = openstack_networking_network_v2.net.name
}

output "subnet_id" {
  value = openstack_networking_subnet_v2.subnet.id
}
