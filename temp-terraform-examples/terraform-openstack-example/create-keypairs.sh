#!/bin/bash
# Crea los keypairs vm1..vm6 usados en el apartado2.4
# Ejecutar en el host:
#   source /mnt/tmp/openstack_lab-antelope_4n_classic_ovs-v04/bin/admin-openrc.sh
#   bash /mnt/tmp/openstack_lab-antelope_4n_classic_ovs-v04/shared/terraform-lab/terraform_files_p14/apartado2-4/create-keypairs.sh
# Por defecto guarda las claves privadas en ./keys
# Si un keypair ya existe en OpenStack no se toca (su clave privada no se puede recuperar).

KEYS_DIR="${1:-keys}"
mkdir -p "$KEYS_DIR"

for vm in vm1 vm2 vm3 vm4 vm5 vm6; do
  if openstack keypair show "$vm" >/dev/null 2>&1; then
    echo "keypair $vm ya existe: se omite"
  else
    openstack keypair create "$vm" > "$KEYS_DIR/$vm"
    chmod 600 "$KEYS_DIR/$vm"
    echo "keypair $vm creado -> $KEYS_DIR/$vm"
  fi
done
