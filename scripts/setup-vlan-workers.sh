#!/bin/bash
# Crea la subinterfaz VLAN <IF>.<VLAN_ID> en los workers
# Uso: scripts/setup-vlan-workers.sh [vlan_id]      (por defecto, 1000)
# si la subinterfaz ya existe, no la vuelve a crear; solo se asegura de que esté UP.
# Hay que ejecutarlo después de cada arranque del escenario: las subinterfaces no sobreviven a start-k8s-calico.
set -euo pipefail   #si comando falla el script se para  

VLAN_ID="${1:-1000}"
IF="e2"                               # interfaz de los workers conectada a VlanNet
WORKERS="k8s-worker1 k8s-worker2"

if ! [[ "$VLAN_ID" =~ ^[0-9]+$ ]] || (( VLAN_ID < 1 || VLAN_ID > 4094 )); then
  echo "VLAN ID no válido: $VLAN_ID (tiene que estar entre 1 y 4094)" >&2
  exit 1
fi

for w in $WORKERS; do
  echo "--- $w: $IF.$VLAN_ID"
  ssh "$w" "ip link show $IF.$VLAN_ID >/dev/null 2>&1 || ip link add link $IF name $IF.$VLAN_ID type vlan id $VLAN_ID; ip link set $IF.$VLAN_ID up"
  ssh "$w" "ip -d link show $IF.$VLAN_ID" | grep -E "state|vlan protocol"
done