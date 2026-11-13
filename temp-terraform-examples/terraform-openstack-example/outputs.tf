output "network_ids" {
  description = "IDs de las redes internas"
  value = {
    net1 = module.net1.network_id
    net2 = module.net2.network_id
  }
}

output "router_r0_id" {
  description = "ID del router r0"
  value       = openstack_networking_router_v2.r0.id
}

output "keypair_files" {
  description = "Keypair de cada VM y fichero con su clave privada"
  value       = { for name, kp in openstack_compute_keypair_v2.kp : name => "keys/${kp.name}" }
}

output "vm_fixed_ips" {
  description = "IP fija de cada VM"
  value       = { for name, vm in module.vm : name => vm.fixed_ip }
}

output "vm_floating_ips" {
  description = "IP flotante de cada VM"
  value       = { for name, vm in module.vm : name => vm.floating_ip }
}
