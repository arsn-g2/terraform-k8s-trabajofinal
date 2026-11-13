# 🧭 Guía: Multus y VLAN (de la práctica 1.3 al Trabajo Final)

⬅️ [Volver al plan](../../../plan.md) · Historias: [US-19](../../../historias/persona-a.md#us-19) (investigación) · [US-10](../../../historias/persona-a.md#us-10) (subinterfaces) · [US-11](../../../historias/persona-a.md#us-11) (NAD) · [US-12](../../../historias/persona-a.md#us-12) (LXC) · [US-22](../../../historias/persona-b.md#us-22) / [US-24](../../../historias/persona-c.md#us-24) (Pods)

Lo que hicimos con Multus en la **práctica 1.3, §8** ("Conectividad exterior desde pods usando VLANs") y cómo se traslada al Trabajo Final.

📁 **Ficheros originales de P1.3** en [`p13/`](p13/), copiados de `examples/multus/` del escenario `k8s_lab-flannel-v02`:
[`set-subinterfaces.sh`](p13/set-subinterfaces.sh) · [`vlan1000.yml`](p13/vlan1000.yml) · [`vlan1001.yml`](p13/vlan1001.yml) · [`vma3.yml`](p13/vma3.yml) · [`vma4.yml`](p13/vma4.yml) · [`vmb3.yml`](p13/vmb3.yml) · [`vmb4.yml`](p13/vmb4.yml)

> **Leyenda.** `⟪PENDIENTE: …⟫` = dato que no está en los ficheros (sale de nuestra memoria de P1.3). Lista en la [§7](#7-pendientes).

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

### 2.1 Topología

| Máquina | Dónde | VLAN | IP | Nodo |
|---|---|---|---|---|
| `vmA2` | LXC (VNX) | 1000 | `10.1.2.100/24` | — |
| `vmB2` | LXC (VNX) | 1001 | `10.1.3.100/24` | — |
| `vlan-router` | LXC (VNX) | 1000 y 1001 | `10.1.2.1/24`, `10.1.3.1/24` | — |
| `vma3` | Pod | 1000 | `10.1.2.200/24` | `k8s-worker1` |
| `vma4` | Pod | 1000 | `10.1.2.201/24` | `k8s-worker2` |
| `vmb3` | Pod | 1001 | `10.1.3.200/24` | `k8s-worker1` |
| `vmb4` | Pod | 1001 | `10.1.3.201/24` | `k8s-worker2` |

Las VMs externas salen de `k8s_lab-vms-vlan.xml`, que es **idéntico** en el escenario de Flannel y en el de Calico (está en la raíz de `/mnt/tmp/k8s_lab-calico-v02`). Todas cuelgan de `VlanNet`, la red OVS a la que están conectados los workers por `e2` (`<if id="2" net="VlanNet">`, igual en `k8s_lab-flannel.xml` y `k8s_lab-calico.xml`).

### 2.2 Paso 1: arrancar las máquinas externas

```bash
cd /mnt/tmp/k8s_lab-flannel-v02
sudo vnx -f k8s_lab-vms-vlan.xml -v -t
```

### 2.3 Paso 2: subinterfaces VLAN en los workers ([`set-subinterfaces.sh`](p13/set-subinterfaces.sh))

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

⚠️ No es idempotente: si `e2.1000` ya existe, `ip link add` falla. Nuestra versión ([§4.1](#41-subinterfaz-en-los-workers-scriptssetup-vlan-workerssh)) lo comprueba antes.

### 2.4 Paso 3: una NAD por VLAN ([`vlan1000.yml`](p13/vlan1000.yml))

```yaml
apiVersion: "k8s.cni.cncf.io/v1"
kind: NetworkAttachmentDefinition
metadata:
  name: vlan1000
spec:
  config: '{
      "cniVersion": "0.3.1",
      "type": "macvlan",
      "master": "e2.1000",
      "mode": "bridge",
      "capabilities": { "ips": true },
      "ipam": {
        "type": "static",
        "routes": [
          {
            "dst": "10.1.0.0/16",
            "gw": "10.1.2.1"
          }
        ]
      }
    }'
```

| Campo de `spec.config` | Valor en P1.3 | Qué significa |
|---|---|---|
| `type` | `macvlan` | `net1` es una interfaz macvlan: una "MAC virtual" colgada de una interfaz del nodo |
| `master` | `e2.1000` | **Respuesta a la pregunta de la práctica:** es la subinterfaz VLAN **del worker** (paso 2), no una interfaz del Pod. Todo lo que sale por `net1` sale etiquetado con la VLAN 1000 por `e2` |
| `mode` | `bridge` | Los Pods macvlan del mismo `master` en el mismo nodo se ven entre sí |
| `capabilities.ips` | `true` | Permite que **el Pod** diga su IP en la anotación (campo `ips`) |
| `ipam.type` | `static` | No hay reparto automático: la IP es la que pone la anotación |
| `ipam.routes` | `10.1.0.0/16` vía `10.1.2.1` | Ruta en el Pod hacia la otra VLAN a través de `vlan-router`. Solo hace falta si se quiere llegar a otra subred |

`vlan1001.yml` es igual cambiando `master: e2.1001` y `gw: 10.1.3.1`.

### 2.5 Paso 4: Pods con la interfaz extra ([`vma3.yml`](p13/vma3.yml))

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: vma3
  annotations:
    k8s.v1.cni.cncf.io/networks: '[
            { "name": "vlan1000",
              "ips": [ "10.1.2.200/24" ],
              "gateway": [ "10.1.2.1" ]
            }]'
spec:
  containers:
  - name: vma3
    image: alpine
    command: ["/bin/ash", "-c", "trap : TERM INT; sleep infinity & wait"]
  nodeSelector:
    kubernetes.io/hostname: k8s-worker1
```

- La anotación es una **lista JSON**: `name` = la NAD, `ips` = IP fija de `net1` (posible gracias a `capabilities.ips` + IPAM `static`), `gateway` = puerta de enlace por esa interfaz.
- `nodeSelector` reparte los Pods: `vma3`/`vmb3` en `k8s-worker1`, `vma4`/`vmb4` en `k8s-worker2`.
- `alpine` con `sleep infinity` es un Pod de pruebas mínimo: sirve tal cual para la prueba de concepto de [US-19](../../../historias/persona-a.md#us-19).

```bash
cd /mnt/tmp/k8s_lab-flannel-v02/examples/multus
kubectl create -f vlan1000.yml -f vlan1001.yml
kubectl create -f vma3.yml -f vma4.yml -f vmb3.yml -f vmb4.yml
```

### 2.6 Paso 5: comprobar

```bash
kubectl get pods -o wide                                   # en qué worker cayó cada Pod
kubectl exec -it vma3 -- ip addr show net1                 # 10.1.2.200/24
kubectl exec -it vma3 -- ping -c 3 10.1.2.100              # vma3 → vmA2, misma VLAN
kubectl exec -it vma3 -- ping -c 3 10.1.2.201              # vma3 (worker1) → vma4 (worker2), misma VLAN
kubectl exec -it vma3 -- ping -c 3 10.1.3.100              # vma3 → vmB2, otra VLAN, vía vlan-router
ssh k8s-worker1 tcpdump -n -e -i e2 vlan                   # tramas 802.1Q con la etiqueta 1000/1001
ssh k8s-worker1 tcpdump -n -i e2.1000                      # mismo tráfico, ya sin etiqueta
```

Lo que vimos (respuesta a R9 de nuestra memoria de P1.3):

```
⟪PENDIENTE: resumen de R9 — por dónde sale el tráfico del Pod, dónde aparece la etiqueta VLAN,
             cómo llega a vmA2/vmB2⟫
```

---

## 3. Qué se reutiliza y qué cambia en el Trabajo Final

| | Práctica 1.3 | Trabajo Final |
|---|---|---|
| CNI principal | Flannel | **Calico** (interfaz `e1`) |
| Multus | ya instalado en el escenario | ya instalado, thick (`ghcr.io/k8snetworkplumbingwg/multus-cni:snapshot-thick`) |
| Interfaz de los workers hacia `VlanNet` | `e2` | `e2` (**igual**) |
| Escenario VNX externo | `k8s_lab-vms-vlan.xml` | el mismo fichero como base para `bbdd` y `logs` ([US-12](../../../historias/persona-a.md#us-12)) |
| VLANs | 1000 y 1001 | **una** VLAN compartida, ID `⟪PENDIENTE: US-03⟫` |
| Subred | `10.1.2.0/24`, `10.1.3.0/24` | `⟪PENDIENTE: US-03⟫` |
| Tipo de NAD | `macvlan`, modo `bridge`, `master: e2.<vlan>` | **igual** (es lo que pide el enunciado §2.2–2.3) |
| IPAM | `static` + IP por Pod en la anotación | ✅ sirve para el **admin**; ⚠️ **no** sirve para los web (ver abajo) |
| Rutas en la NAD | `10.1.0.0/16` vía el router | no hacen falta si Pods y LXC están en la misma subred |
| Pods | 4 Pods sueltos | Deployment de 3 réplicas + Pod admin |
| Cómo se crean | `kubectl create -f` | **Terraform** (`kubernetes_manifest` + anotaciones en los recursos) |
| Subinterfaces | `set-subinterfaces.sh` a mano | `scripts/setup-vlan-workers.sh`, cada día ([US-10](../../../historias/persona-a.md#us-10)) |

### ⚠️ El problema nuevo: IPAM para el Deployment

En P1.3 cada Pod era un fichero con **su propia** anotación e IP. Un Deployment tiene **una sola plantilla**: si ponemos `"ips": ["10.x.x.200/24"]`, las 3 réplicas piden la misma IP y chocan. Con IPAM `static` sin IP en la anotación, `net1` se queda sin dirección. Por eso la decisión de IPAM ([D-005](../../../decisions.md)) es el núcleo de [US-19](../../../historias/persona-a.md#us-19):

| Opción | Admin | Web (3 réplicas) | Notas |
|---|---|---|---|
| `static` + `ips` en la anotación (P1.3) | ✅ | ❌ misma IP para todas | Lo que ya sabemos hacer |
| `host-local` con un rango | ✅ | ⚠️ cada worker reparte por su cuenta → IPs duplicadas entre nodos | |
| `whereabouts` | ✅ | ✅ | No está instalado; hay que instalarlo cada día |
| `dhcp` + servidor DHCP en un LXC | ✅ | ✅ | Necesita el *daemon* `dhcp` del CNI en cada worker |
| 3 Pods sueltos en vez de Deployment | ✅ | ✅ | ❌ El enunciado pide un **Deployment** |

⚠️ Calico aplica las NetworkPolicies a `eth0`, **no a `net1`** ([US-33](../../../historias/persona-a.md#us-33)).

---

## 4. Plantillas para el Trabajo Final

### 4.1 Subinterfaz en los workers (`scripts/setup-vlan-workers.sh`)

Versión idempotente de [`set-subinterfaces.sh`](p13/set-subinterfaces.sh), para una sola VLAN:

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

Traducción de [`vlan1000.yml`](p13/vlan1000.yml) a `kubernetes_manifest`. `spec.config` es un **string JSON**, así que se escribe con `jsonencode()` (más seguro que pegar el JSON entre comillas como en el YAML):

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
        cniVersion   = "0.3.1"
        type         = "macvlan"
        master       = "${var.vlan_master_if}.${var.vlan_id}"
        mode         = "bridge"
        capabilities = { ips = true }     # deja que el admin fije su IP en la anotación
        ipam = {
          type = "static"                 # ⟪PENDIENTE: D-005 — puede cambiar para los web⟫
          # routes = [{ dst = "...", gw = "..." }]   # solo si hay que llegar a otra subred
        }
      })
    }
  }
}
```

Si D-005 elige un IPAM distinto para los web, pueden hacer falta **dos NAD**: una `static` para el admin y otra con el IPAM automático para el Deployment.

### 4.3 Anotación en los Pods

Admin, con IP fija como `vma3.yml`:

```hcl
metadata {
  annotations = {
    "k8s.v1.cni.cncf.io/networks" = jsonencode([{
      name    = "vlan${var.vlan_id}"
      ips     = ["⟪PENDIENTE: IP del admin⟫/24"]
    }])
  }
}
```

Web (Deployment), sin IP en la anotación (la pone el IPAM de D-005):

```hcl
spec {
  template {
    metadata {
      annotations = {
        "k8s.v1.cni.cncf.io/networks" = "⟪PENDIENTE: nombre de la NAD de los web⟫"
      }
    }
  }
}
```

⚠️ En el Deployment la anotación va en `spec.template.metadata`, **no** en el `metadata` del Deployment.

### 4.4 Comprobación

```bash
kubectl get net-attach-def -n <ns>
kubectl get pod <pod> -n <ns> -o jsonpath='{.metadata.annotations.k8s\.v1\.cni\.cncf\.io/network-status}'
kubectl exec -n <ns> <pod> -- ip -br addr show net1
kubectl exec -n <ns> <pod> -- ping -c 3 <ip-bbdd>
```

---

## 5. Prueba de concepto para US-19

Adaptación directa de los ficheros de P1.3 al escenario de Calico, en un namespace de pruebas. Con una VLAN de prueba (por ejemplo, 1000) y las IPs de P1.3, se puede probar **hoy** contra `vmA2` arrancando `k8s_lab-vms-vlan.xml`:

```bash
cd /mnt/tmp/k8s_lab-calico-v02
sudo vnx -f k8s_lab-vms-vlan.xml -v -t                        # vmA2, vmB2, vlan-router
bash shared/terraform-k8s-trabajofinal/docs/useful/multus/p13/set-subinterfaces.sh
kubectl create ns multus-poc
cd shared/terraform-k8s-trabajofinal/docs/useful/multus/p13
kubectl -n multus-poc create -f vlan1000.yml -f vma3.yml -f vma4.yml
kubectl -n multus-poc exec vma3 -- ping -c 3 10.1.2.100          # → vmA2
kubectl -n multus-poc exec vma3 -- ping -c 3 10.1.2.201          # → vma4 en el otro worker
# limpiar
kubectl delete ns multus-poc
sudo vnx -f /mnt/tmp/k8s_lab-calico-v02/k8s_lab-vms-vlan.xml --destroy
```

Después, repetir con un Deployment de 2–3 réplicas y la opción de IPAM que se quiera evaluar.

---

## 6. Errores que ya conocemos

| Síntoma | Causa probable |
|---|---|
| El Pod se queda en `ContainerCreating` y `describe` dice `Link not found` | La subinterfaz `e2.<vlan>` no existe en ese worker (se pierde al recrear el escenario) |
| `set-subinterfaces.sh` da `RTNETLINK answers: File exists` | La subinterfaz ya existía. Usar la versión idempotente ([§4.1](#41-subinterfaz-en-los-workers-scriptssetup-vlan-workerssh)) |
| `terraform plan` falla con *no matches for kind NetworkAttachmentDefinition* | El CRD de Multus no está; revisar `kubectl get crd \| grep cni` |
| `net1` existe pero sin IP | IPAM `static` sin `ips` en la anotación (típico al copiar la NAD de P1.3 a un Deployment) |
| Dos Pods con la misma IP en `net1` | La misma `ips` en la plantilla de un Deployment, o `host-local` con Pods en workers distintos ([D-005](../../../decisions.md)) |
| Ping del Pod a su propio worker por la VLAN falla | Normal con `macvlan`: el padre no habla con sus hijos macvlan. Probar contra otro Pod o un LXC |
| ⟪PENDIENTE: problemas que nos salieron en P1.3⟫ | |

---

## 7. Pendientes

- [ ] Resumen de la respuesta R9 de nuestra memoria de P1.3 ([§2.6](#26-paso-5-comprobar)).
- [ ] Problemas que nos encontramos en P1.3 ([§6](#6-errores-que-ya-conocemos)).
- [ ] VLAN ID, subred e IPs del admin y los LXC ([US-03](../../../historias/persona-c.md#us-03)).
- [ ] IPAM de los web ([US-19](../../../historias/persona-a.md#us-19), [D-005](../../../decisions.md)).
