# 🧭 Guía: Multus y VLAN (de la práctica 1.3 al Trabajo Final)

⬅️ [Volver al plan](../plan.md) · Historias: [US-19](../historias/persona-a.md#us-19) (investigación) · [US-10](../historias/persona-a.md#us-10) (subinterfaces) · [US-11](../historias/persona-a.md#us-11) (NAD) · [US-22](../historias/persona-b.md#us-22) / [US-24](../historias/persona-c.md#us-24) (Pods)

Resumen de lo que hicimos con Multus en la **práctica 1.3, §8** ("Conectividad exterior desde pods usando VLANs"), y cómo se traslada al Trabajo Final.

> **Leyenda.** `⟪PENDIENTE: …⟫` = dato que hay que copiar del escenario de la práctica 1.3 (`/mnt/tmp/k8s_lab-flannel-v02`). La lista de comandos para rellenarlos está en la [§6](#6-checklist-para-rellenar-los-pendientes).

---

## 1. Qué es Multus (en una línea)

Multus es un CNI "meta": deja que la red principal del clúster (Flannel en P1.3, **Calico** aquí) siga dando `eth0` a cada Pod y añade interfaces extra (`net1`, `net2`…) delegando en otros plugins CNI (`macvlan`, `vlan`, `bridge`…). Cada interfaz extra se describe en un objeto **`NetworkAttachmentDefinition`** (NAD), y el Pod la pide con una **anotación**.

```
          Pod
   ┌──────────────────┐
   │ eth0  ── Calico ─┼──► red de Pods 172.16.0.0/16 (Services, Ingress, NetworkPolicies)
   │ net1  ── Multus ─┼──► macvlan sobre e2.<vlan> ──► VlanNet (OVS) ──► LXC bbdd / logs
   └──────────────────┘
```

---

## 2. Cómo se hizo en la práctica 1.3

Escenario: clúster `k8s_lab-flannel-v02` + escenario VNX `k8s_lab-vms-vlan.xml` con dos VMs externas en VLANs distintas y un router entre ellas.

| Máquina (VNX) | VLAN | IP | Gateway |
|---|---|---|---|
| `vmA2` | 1000 | `10.1.2.100/24` | `10.1.2.1` |
| `vmB2` | 1001 | `10.1.3.100/24` | `10.1.3.1` |
| `vlan-router` | 1000 y 1001 | `10.1.2.1/24`, `10.1.3.1/24` | — |

Datos sacados de `k8s_lab-vms-vlan.xml` (está en la raíz del escenario de hoy también). Las tres cuelgan de `VlanNet`, la misma red OVS a la que están conectados los workers por su interfaz `e2`.

### Paso 1: arrancar las máquinas externas

```bash
cd /mnt/tmp/k8s_lab-flannel-v02
sudo vnx -f k8s_lab-vms-vlan.xml -v -t
```

### Paso 2: subinterfaces VLAN en los workers

```bash
ssh k8s-worker1 ip link add link e2 name e2.1000 type vlan id 1000
ssh k8s-worker1 ip link add link e2 name e2.1001 type vlan id 1001
ssh k8s-worker2 ip link add link e2 name e2.1000 type vlan id 1000
ssh k8s-worker2 ip link add link e2 name e2.1001 type vlan id 1001
ssh k8s-worker1 ip link set e2.1000 up
ssh k8s-worker1 ip link set e2.1001 up
ssh k8s-worker2 ip link set e2.1000 up
ssh k8s-worker2 ip link set e2.1001 up
```

El escenario traía lo mismo en un script, `examples/multus/set-subinterfaces.sh`:

```bash
⟪PENDIENTE: contenido de examples/multus/set-subinterfaces.sh⟫
```

### Paso 3: una NAD por VLAN

```bash
cd /mnt/tmp/k8s_lab-flannel-v02/examples/multus
kubectl create -f vlan1000.yml
kubectl create -f vlan1001.yml
```

`vlan1000.yml`:

```yaml
⟪PENDIENTE: contenido de examples/multus/vlan1000.yml⟫
```

Qué mirar en la NAD (la práctica preguntaba por el campo `master`):

| Campo de `spec.config` | Valor en P1.3 | Para qué sirve |
|---|---|---|
| `type` | `⟪PENDIENTE⟫` | Plugin CNI que crea `net1` (¿`macvlan`?, ¿`vlan`?) |
| `master` | `⟪PENDIENTE⟫` | Interfaz del **nodo** sobre la que se cuelga `net1` (¿`e2.1000`?) |
| `mode` | `⟪PENDIENTE⟫` | Modo de macvlan, si aplica (¿`bridge`?) |
| `ipam.type` | `⟪PENDIENTE⟫` | Quién reparte la IP de `net1` (`static`, `host-local`…) |
| `ipam` (resto) | `⟪PENDIENTE⟫` | Rango/IPs, gateway, rutas |

### Paso 4: Pods con la interfaz extra

```bash
kubectl create -f vma3.yml
kubectl create -f vma4.yml
kubectl create -f vmb3.yml
kubectl create -f vmb4.yml
```

La anotación de `vma3.yml` (es lo que hay que copiar a nuestro Deployment y al admin):

```yaml
⟪PENDIENTE: bloque metadata.annotations de examples/multus/vma3.yml⟫
```

| Pod (P1.3) | Nodo | VLAN | IP de `net1` |
|---|---|---|---|
| `vma3` | `⟪PENDIENTE⟫` | 1000 | `⟪PENDIENTE⟫` |
| `vma4` | `⟪PENDIENTE⟫` | 1000 | `⟪PENDIENTE⟫` |
| `vmb3` | `⟪PENDIENTE⟫` | 1001 | `⟪PENDIENTE⟫` |
| `vmb4` | `⟪PENDIENTE⟫` | 1001 | `⟪PENDIENTE⟫` |

### Paso 5: comprobar

```bash
kubectl get pods -o wide                                   # en qué worker cayó cada Pod
kubectl exec -it vma3 -- ip addr show net1                 # interfaz extra
kubectl exec -it vma3 -- ping -c 3 10.1.2.100              # Pod → vmA2, misma VLAN
kubectl exec -it vma3 -- ping -c 3 10.1.3.100              # Pod → vmB2, a través de vlan-router
ssh k8s-worker1 tcpdump -n -e -i e2 vlan                   # tramas 802.1Q con la etiqueta 1000/1001
ssh k8s-worker1 tcpdump -n -i e2.1000                      # mismo tráfico ya sin etiqueta
```

Lo que vimos (respuesta a R9 de la memoria de P1.3):

```
⟪PENDIENTE: resumen de R9 — por dónde sale el tráfico del Pod, dónde aparece la etiqueta VLAN,
             cómo llega a vmA2/vmB2⟫
```

---

## 3. Qué cambia en el Trabajo Final

| | Práctica 1.3 | Trabajo Final |
|---|---|---|
| CNI principal | Flannel | **Calico** (interfaz `e1`) |
| Multus | `⟪PENDIENTE: versión / thick o thin en flannel⟫` | thick (`ghcr.io/k8snetworkplumbingwg/multus-cni:snapshot-thick`) |
| VLANs | 1000 y 1001 | **una** VLAN compartida, ID `⟪PENDIENTE: US-03⟫` |
| Subred | `10.1.2.0/24`, `10.1.3.0/24` | `⟪PENDIENTE: US-03⟫` |
| Máquinas externas | `vmA2`, `vmB2`, `vlan-router` | LXC `bbdd` (MariaDB) y `logs` ([US-12](../historias/persona-a.md#us-12)) |
| Pods | 4 Pods sueltos, uno por fichero | Deployment de 3 réplicas + Pod admin |
| Cómo se crean | `kubectl create -f` | **Terraform** (`kubernetes_manifest`) |
| Subinterfaces | a mano / `set-subinterfaces.sh` | `scripts/setup-vlan-workers.sh`, cada día ([US-10](../historias/persona-a.md#us-10)) |
| IPAM | `⟪PENDIENTE⟫` | por decidir en [US-19](../historias/persona-a.md#us-19) / [D-005](../decisions.md) |

⚠️ **El problema nuevo es el IPAM.** En P1.3 cada Pod era un fichero distinto, así que se le podía dar una IP fija a cada uno. Aquí las 3 réplicas web salen **de la misma plantilla**, y `whereabouts` no está instalado. Las opciones están en [US-19](../historias/persona-a.md#us-19).

⚠️ Calico aplica las NetworkPolicies a `eth0`, **no a `net1`** ([US-33](../historias/persona-a.md#us-33)).

---

## 4. Plantillas para el Trabajo Final

### 4.1 Subinterfaz en los workers (`scripts/setup-vlan-workers.sh`)

```bash
#!/bin/bash
# Crea <IF>.<VLAN> en los dos workers. Idempotente: se puede correr varias veces.
VLAN_ID=${1:?uso: $0 <vlan_id>}     # ⟪PENDIENTE: US-03⟫
IF=e2
for w in k8s-worker1 k8s-worker2; do
  ssh root@$w "ip link show $IF.$VLAN_ID >/dev/null 2>&1 || ip link add link $IF name $IF.$VLAN_ID type vlan id $VLAN_ID; ip link set $IF.$VLAN_ID up"
done
```

### 4.2 NAD con Terraform (`terraform/multus.tf`)

Traducción del YAML de P1.3 a `kubernetes_manifest`. `spec.config` es un **string JSON**, así que se escribe con `jsonencode()`:

```hcl
resource "kubernetes_manifest" "vlan_nad" {
  manifest = {
    apiVersion = "k8s.cni.cncf.io/v1"
    kind       = "NetworkAttachmentDefinition"
    metadata = {
      name      = "vlan${var.vlan_id}"
      namespace = var.namespace
    }
    spec = {
      config = jsonencode({
        cniVersion = "0.3.1"                           # ⟪PENDIENTE: el de vlan1000.yml⟫
        type       = "macvlan"                         # ⟪PENDIENTE: confirmar con vlan1000.yml⟫
        master     = "${var.vlan_master_if}.${var.vlan_id}"
        mode       = "bridge"
        ipam = {
          type = "⟪PENDIENTE: D-005⟫"
          # ⟪PENDIENTE: rango / IPs / gateway según D-005⟫
        }
      })
    }
  }
}
```

### 4.3 Anotación en el Pod

En `kubernetes_deployment_v1` (web) y en el Pod admin, dentro de `metadata`:

```hcl
annotations = {
  "k8s.v1.cni.cncf.io/networks" = "vlan${var.vlan_id}"
  # Con IP fija (IPAM static, solo admin):
  # "k8s.v1.cni.cncf.io/networks" = jsonencode([{ name = "vlan${var.vlan_id}", ips = ["⟪PENDIENTE⟫/24"] }])
}
```

⚠️ En el Deployment la anotación va en `spec.template.metadata`, **no** en el `metadata` del Deployment.

### 4.4 Comprobación

```bash
kubectl get net-attach-def -n <ns>
kubectl get pod <pod> -n <ns> -o jsonpath='{.metadata.annotations.k8s\.v1\.cni\.cncf\.io/network-status}' | jq
kubectl exec -n <ns> <pod> -- ip -br addr show net1
kubectl exec -n <ns> <pod> -- ping -c 3 <ip-bbdd>
```

---

## 5. Errores que ya conocemos

| Síntoma | Causa probable |
|---|---|
| El Pod se queda en `ContainerCreating` y `describe` dice `Link not found` | La subinterfaz `e2.<vlan>` no existe en ese worker (se pierde al recrear el escenario) |
| `terraform plan` falla con *no matches for kind NetworkAttachmentDefinition* | El CRD de Multus no está; revisar `kubectl get crd \| grep cni` |
| Dos Pods con la misma IP en `net1` | IPAM `host-local` con Pods en workers distintos (ver [D-005](../decisions.md)) |
| Ping del Pod a su propio worker por la VLAN falla | Normal con `macvlan`: el padre no habla con sus hijos macvlan. Probar contra otro Pod o un LXC |
| ⟪PENDIENTE: problemas que salieron en P1.3⟫ | |

---

## 6. Checklist para rellenar los pendientes

En el escenario de P1.3 (`/mnt/tmp/k8s_lab-flannel-v02`):

- [ ] `ls examples/multus/` y copiar al repo, por ejemplo en `docs/referencia-p13/multus/`:
  ```bash
  mkdir -p <repo>/docs/referencia-p13/multus
  cp /mnt/tmp/k8s_lab-flannel-v02/examples/multus/* <repo>/docs/referencia-p13/multus/
  ```
- [ ] Pegar `vlan1000.yml` y rellenar la tabla de campos de la NAD (§2, paso 3).
- [ ] Pegar las `annotations` de `vma3.yml` (§2, paso 4).
- [ ] Pegar `set-subinterfaces.sh` (§2, paso 2).
- [ ] Tras crear los Pods: `kubectl get pods -o wide` y `kubectl exec <pod> -- ip -br addr show net1` → tabla de Pods (§2, paso 4).
- [ ] Versión y modo de Multus en ese escenario: `kubectl get ds -n kube-system -o wide | grep multus`.
- [ ] Plugins CNI y si hay `whereabouts`: `ssh k8s-worker1 ls /opt/cni/bin`.
- [ ] Resumen de la respuesta R9 de nuestra memoria de P1.3 (§2, paso 5).
- [ ] Cualquier error que nos encontráramos entonces (§5).
