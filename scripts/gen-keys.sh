#!/bin/bash
# US-16 · Genera los dos pares de claves SSH (D-004). Se ejecuta en el HOST,
# cada día, antes de `terraform apply` y de crear los LXC con VNX.
#
#   Par 1 (par1_admin): admin -> web y LXC
#       privada -> Secret ssh-admin-private   (Pod admin)
#       pública -> Secret ssh-web-authorized  (Pods web)
#                  + vnx/filetree/ssh/authorized_keys (LXC bbdd y logs)
#   Par 2 (par2_host):  host -> admin
#       privada -> se queda en el host (keys/par2_host)
#       pública -> Secret ssh-admin-authorized (Pod admin)

set -euo pipefail

REPO=/mnt/tmp/k8s_lab-calico-v02/shared/terraform-k8s-trabajofinal
KEYS_DIR="$REPO/keys"
FILETREE_SSH="$REPO/vnx/filetree/ssh"

mkdir -p "$KEYS_DIR" "$FILETREE_SSH"
chmod 700 "$KEYS_DIR"

for key in par1_admin par2_host; do
    # ssh-keygen pregunta antes de sobrescribir: borramos primero
    rm -f "$KEYS_DIR/$key" "$KEYS_DIR/$key.pub"
    # -N "": sin passphrase (no interactivo) · -C: comentario para identificarla
    ssh-keygen -q -t ed25519 -N "" -C "$key-$(date +%F)" -f "$KEYS_DIR/$key"
done

# Clave pública del par 1 para el <filetree> de los LXC
cp "$KEYS_DIR/par1_admin.pub" "$FILETREE_SSH/authorized_keys"

echo "Claves generadas en $KEYS_DIR:"
ls -l "$KEYS_DIR"
echo "authorized_keys de los LXC: $FILETREE_SSH/authorized_keys"
