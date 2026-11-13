# Creacion dinamica de keypairs desde Terraform (sustituye a create-keypairs.sh)
# Se crea un keypair por cada VM definida en local.vms (vms.tf).
# OpenStack genera el par de claves; la clave privada se guarda en ./keys/<nombre>
# mediante un provisioner local-exec, y se borra al destruir el keypair.

variable "keypair_prefix" {
  description = "Prefijo de los keypairs (evita choques con keypairs ya existentes, p.ej. vm1 y vm2)"
  type        = string
  default     = "tf-"
}

resource "openstack_compute_keypair_v2" "kp" {
  for_each = local.vms
  name     = "${var.keypair_prefix}${each.key}"

  # Al crear: guardar la clave privada generada con permisos 600
  provisioner "local-exec" {
    command = "mkdir -p keys && printf '%s' \"$PRIVATE_KEY\" > keys/${self.name} && chmod 600 keys/${self.name}"
    environment = {
      PRIVATE_KEY = self.private_key
    }
  }

  # Al destruir: borrar el fichero de la clave privada
  provisioner "local-exec" {
    when    = destroy
    command = "rm -f keys/${self.name}"
  }
}
