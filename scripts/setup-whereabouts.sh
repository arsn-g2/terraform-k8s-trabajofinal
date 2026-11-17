#!/bin/bash
# Instala el IPAM whereabouts en el clúster (US-11, D-005, D-010).
# El escenario se crea de cero cada día: ejecutarlo en cada arranque, después de
# ./bin/get-master-kubeconf y antes de `terraform apply`.
# Uso: scripts/setup-whereabouts.sh [tag]      (por defecto, v0.9.4)
# Idempotente: si ya está instalado, kubectl apply no cambia nada.
set -euo pipefail

VERSION="${1:-v0.9.4}"
REPO="https://github.com/k8snetworkplumbingwg/whereabouts"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "--- whereabouts $VERSION"
git -c advice.detachedHead=false clone -q --depth 1 --branch "$VERSION" "$REPO" "$TMP/whereabouts"
cd "$TMP/whereabouts/doc/crds"

# El manifiesto pide la imagen :latest incluso en los tags: la fijamos a la misma versión
sed -i "s|whereabouts:latest|whereabouts:${VERSION}|" daemonset-install.yaml

kubectl apply -f whereabouts.cni.cncf.io_ippools.yaml \
              -f whereabouts.cni.cncf.io_overlappingrangeipreservations.yaml \
              -f daemonset-install.yaml
kubectl -n kube-system rollout status ds/whereabouts --timeout=180s
kubectl -n kube-system get ds whereabouts -o wide