da# 🌐 Investigación: Multus, tipo de NAD e IPAM

⬅️ [Volver al plan](../plan.md) · Historia: [US-19](../historias/persona-a.md#us-19) · Relacionado: [guía de Multus](useful/multus/guia-multus.md) · [datos del escenario §4](datos-escenario.md#4-multus-y-red-vlan) · [D-005](../decisions.md)

Prueba de concepto para decidir **qué tipo de NetworkAttachmentDefinition (NAD) y qué IPAM** usar para conectar los Pods web (Deployment de 3 réplicas) y el Pod admin a la VLAN compartida con los LXC `bbdd` y `logs` (enunciado §2.2 y §2.3). El resultado son decisiones, no código de entrega.

Pruebas hechas con `kubectl` (no con Terraform) en el namespace `multus-poc`, que se borra al terminar, en el entorno desplegado el **15/11/2026**.

📁 **Ficheros de las pruebas** en [`investigacion-multus/`](investigacion-multus/): [`deploy.tpl.yaml`](investigacion-multus/deploy.tpl.yaml) (plantilla de Deployment) · salidas completas en [`salidas/`](investigacion-multus/salidas/). La NAD y los Pods de la prueba 1 son los originales de P1.3, en [`useful/multus/p13/`](useful/multus/p13/).

> **Leyenda.** `⟪PENDIENTE: …⟫` = prueba o dato por completar. Lista en la [§11](#11-pendientes). Lo marcado con 🔁 (IPs de `eth0`, MACs de `net1`) cambia en cada despliegue.

---

## 1. Entorno de las pruebas

### 1.1 Escenario

| Dato | Valor |
|---|---|
| Clúster | `k8s_lab-calico-v02`: Kubernetes v1.37, Calico con IPIP, red de Pods `172.16.0.0/16` |
| Multus | Instalado en modo *thick*: `kube-multus-ds` en `Running` en los 3 nodos. El CRD `network-attachment-definitions.k8s.cni.cncf.io` existe |
| Interfaz de los workers hacia `VlanNet` | `e2`, UP y **sin IPv4** en los dos workers (solo la IPv6 de enlace local `fe80::…`) |
| Destinos en la VLAN | [`vnx/vnx-vlan.xml`](../vnx/vnx-vlan.xml) y [`vnx/vnx-vm-bdd-logs.xml`](../vnx/vnx-vm-bdd-logs.xml), **desplegados por primera vez sin errores** ([US-12](../historias/persona-a.md#us-12)): `bbdd` `10.1.2.100` (VLAN 1000), `logs` `10.1.3.100` (VLAN 1001), `vlan-router` `10.1.2.1` / `10.1.3.1` |
| Subinterfaces | `e2.1000` y `e2.1001` en los dos workers, con [`set-subinterfaces.sh`](useful/multus/p13/set-subinterfaces.sh) de P1.3 |

### 1.2 Puertos de `VlanNet`

Salida: [`p0-ovs-vlannet.txt`](investigacion-multus/salidas/p0-ovs-vlannet.txt) (`sudo ovs-vsctl show`)

| Puerto | Tag | Tipo | Qué significa |
|---|---|---|---|
| `bbdd-e1`, `vlan-router-e1` | 1000 | *Access* | OVS pone y quita la etiqueta: el contenedor ve tráfico **sin etiquetar** |
| `logs-e1`, `vlan-router-e2` | 1001 | *Access* | Igual, en la VLAN 1001 |
| `k8s-worker1-e2`, `k8s-worker2-e2` | — | *Trunk* | Las tramas viajan **etiquetadas**: el worker necesita la subinterfaz `e2.<vlan>` |

### 1.3 Subinterfaces de los workers

Salida: [`p0-subinterfaces.txt`](investigacion-multus/salidas/p0-subinterfaces.txt) (`ip -d link show e2.1000`)

`e2.1000@e2`, UP, `vlan protocol 802.1Q id 1000`. Tiene **la misma MAC que `e2`**: una subinterfaz VLAN hereda la MAC de su interfaz madre. El flag `REORDER_HDR` indica que el kernel pone y quita la etiqueta de forma transparente.

---

## 2. Prueba 1: Multus con Calico, como en P1.3

**Pregunta.** ¿La NAD de P1.3 (`macvlan` modo `bridge` sobre `e2.1000`) funciona igual con **Calico** que con Flannel?

```bash
cd docs/useful/multus/p13
kubectl -n multus-poc apply -f vlan1000.yml -f vma3.yml -f vma4.yml
kubectl -n multus-poc exec vma3 -- ip addr show net1
kubectl -n multus-poc exec vma3 -- ping -c3 10.1.2.100     # vma3 → bbdd
kubectl -n multus-poc exec vma3 -- ping -c3 10.1.2.201     # vma3 (worker1) → vma4 (worker2)
```

**Resultado** ([`p1-calico.txt`](investigacion-multus/salidas/p1-calico.txt)):

| Comprobación | Resultado |
|---|---|
| Reparto | `vma3` en `k8s-worker1` (`eth0` `172.16.194.69` 🔁) y `vma4` en `k8s-worker2` (`eth0` `172.16.126.1` 🔁) |
| `net1` de `vma3` | `net1@if13`, `10.1.2.200/24`, MAC `76:e2:e0:8a:c0:e6` 🔁. El índice 13 es el de `e2.1000` en `k8s-worker1`: `net1` **cuelga de la subinterfaz** |
| Ping `vma3` → `bbdd` | 3/3 con `ttl=64`: misma red de nivel 2, sin router de por medio |
| Ping `vma3` → `vma4` (otro worker) | 3/3: la VLAN cruza los dos workers a través de `VlanNet` |

**Conclusión.**
- Multus con `macvlan` modo `bridge` sobre `e2.1000` funciona **igual con Calico que con Flannel**: Calico sigue dando `eth0` y Multus añade `net1`.
- `macvlan` da a cada Pod **una MAC propia** en la VLAN, distinta de la del worker.
- La **VLAN 1000** y la subred **`10.1.2.0/24`** de P1.3 sirven para el Trabajo Final (propuesta para [US-03](../historias/persona-c.md#us-03)).

---

## 3. Prueba 2: etiquetado 802.1Q del tráfico de `net1`

**Pregunta.** ¿El tráfico de `net1` sale del worker etiquetado con la VLAN 1000 y llega al LXC sin etiqueta?

Ping continuo de `vma3` a `bbdd` y captura con `tshark` en el host, en dos puertos de `VlanNet` (ver [§10](#10-problemas-encontrados): en el host no hay `tcpdump`):

```bash
CAMPOS="-T fields -E header=y -e frame.len -e eth.src -e eth.dst -e vlan.id -e ip.src -e ip.dst"
tshark -i k8s-worker1-e2 -c 6 -f 'vlan and icmp' $CAMPOS     # trunk
tshark -i bbdd-e1        -c 6 -f 'icmp'          $CAMPOS     # access
```

**Resultado** ([`p2-worker1-e2.txt`](investigacion-multus/salidas/p2-worker1-e2.txt), [`p2-bbdd-e1.txt`](investigacion-multus/salidas/p2-bbdd-e1.txt); para Wireshark: [`p2-worker1-e2.pcap`](investigacion-multus/salidas/p2-worker1-e2.pcap), [`p2-bbdd-e1.pcap`](investigacion-multus/salidas/p2-bbdd-e1.pcap)):

| Punto de captura | Tamaño | VLAN | Origen (petición) | Destino (petición) |
|---|---|---|---|---|
| `k8s-worker1-e2` (*trunk*) | **102** bytes | **1000** | `76:e2:e0:8a:c0:e6` (`net1` de `vma3`) 🔁 | `02:fd:00:03:00:01` (`bbdd`) |
| `bbdd-e1` (*access*) | **98** bytes | — | `76:e2:e0:8a:c0:e6` 🔁 | `02:fd:00:03:00:01` |

**Conclusión.**
- El tráfico de `net1` sale del worker **etiquetado** con la VLAN 1000 por el puerto *trunk*, y OVS **quita la etiqueta** antes de entregarlo a `bbdd`.
- Los 4 bytes de diferencia (102 − 98) son la cabecera 802.1Q, igual que en las *provider networks* de la práctica 2.1.
- La MAC de origen es la de `net1` del Pod, no la de `e2` del worker (`02:fd:00:00:01:02`). La de `bbdd` empieza por `02:fd:00:03`, que corresponde al `automac offset="3"` de `vnx-vm-bdd-logs.xml`.

---

## 4. Prueba 3: la NAD `static` en un Deployment

**Pregunta.** ¿Sirve la NAD de P1.3 (IPAM `static`) para un **Deployment**, cuyas réplicas comparten una sola plantilla de Pod?

Deployment `poc-static` de 4 réplicas con la anotación `k8s.v1.cni.cncf.io/networks: vlan1000` y **sin IP** en la anotación:

```bash
sed -e 's/__NAME__/poc-static/g' -e 's/__NAD__/vlan1000/g' docs/investigacion-multus/deploy.tpl.yaml | kubectl -n multus-poc apply -f -
kubectl -n multus-poc describe pod <pod> | sed -n '/Events:/,$p'
```

**Resultado** ([`p3-static.txt`](investigacion-multus/salidas/p3-static.txt)): las 4 réplicas se reparten (2 por worker) pero se quedan en **`ContainerCreating`**. Los eventos repiten el mismo ciclo cada ~15 s:

1. `AddedInterface … Add eth0 [172.16.126.3/32] from k8s-pod-network`: Multus crea `eth0` con Calico sin problema.
2. `error adding container to network "vlan1000": IPAM plugin returned missing IP config`: el IPAM `static` espera que la anotación del Pod le diga la IP; la plantilla no la da.
3. `FailedCreatePodSandBox`: si falla **una** de las redes del Pod, Multus da por fallido todo el arranque. El kubelet deshace lo creado (también `eth0`) y vuelve a intentarlo.

La IP de `eth0` cambia en cada intento (`.3`, `.4`, `.6`, `.9`…): Calico asigna una nueva y libera la anterior.

**Conclusión.**
- La NAD `static` de P1.3 **no sirve para el Deployment web**: sin IP en la anotación el Pod no arranca, y con una IP en la plantilla todas las réplicas pedirían la misma.
- `static` solo sirve para un Pod suelto con IP fija: el **admin**.
- ⚠️ Corrección a la [guía de Multus §6](useful/multus/guia-multus.md#6-errores-que-ya-conocemos): con IPAM `static` y sin `ips` en la anotación, `net1` no se crea sin IP; **el Pod no llega a arrancar**.

---

## 5. Prueba 4: IPAM `host-local` en un Deployment

**Pregunta.** ¿`host-local` da IPs repetidas a Pods de workers distintos?

Misma NAD `macvlan` sobre `e2.1000`, pero con IPAM `host-local` y el rango `10.1.2.10`–`10.1.2.50` ([`nad-hostlocal.yaml`](investigacion-multus/nad-hostlocal.yaml)). Deployment `poc-hostlocal` de 4 réplicas con la misma plantilla que la prueba 3:

```bash
kubectl -n multus-poc apply -f docs/investigacion-multus/nad-hostlocal.yaml
sed -e 's/__NAME__/poc-hostlocal/g' -e 's/__NAD__/vlan1000-hostlocal/g' docs/investigacion-multus/deploy.tpl.yaml | kubectl -n multus-poc apply -f -
for w in k8s-worker1 k8s-worker2; do ssh $w ls /var/lib/cni/networks/vlan1000-hostlocal; done
```

**Resultado** ([`p4-hostlocal.txt`](investigacion-multus/salidas/p4-hostlocal.txt)): esta vez los 4 Pods **arrancan** (`Running`, 2 en cada worker), porque `host-local` reparte las IPs él solo. Pero las IPs de `net1` **se repiten** entre workers:

| IP de `net1` | Pod en `k8s-worker1` | Pod en `k8s-worker2` |
|---|---|---|
| `10.1.2.10/24` | `poc-hostlocal-…-gnkgm` 🔁 | `poc-hostlocal-…-m4kwh` 🔁 |
| `10.1.2.11/24` | `poc-hostlocal-…-z76rg` 🔁 | `poc-hostlocal-…-4jxnv` 🔁 |

La causa se ve en el disco de cada nodo. `host-local` guarda sus reservas en `/var/lib/cni/networks/vlan1000-hostlocal/` (la carpeta toma el nombre de la NAD), y **los dos workers tienen los mismos ficheros**:

| Fichero | Qué es |
|---|---|
| `10.1.2.10`, `10.1.2.11` | Una reserva por cada IP que ha repartido **ese** nodo |
| `last_reserved_ip.0` | El contador: la última IP repartida por ese nodo |
| `lock` | Bloqueo para que dos Pods **del mismo nodo** no cojan la misma IP a la vez |

Contraste con `eth0`: Calico no repite IPs porque asigna a cada nodo **un bloque distinto** de un pool común (`172.16.194.x` en `k8s-worker1`, `172.16.126.x` en `k8s-worker2`). `host-local` no tiene esa coordinación: los dos workers usan el mismo rango y empiezan por la misma IP.

**Conclusión.**
- `host-local` **queda descartado** para los web: cada worker reparte el mismo rango con su propio contador, sin saber nada del otro, y dos Pods en workers distintos reciben la misma IP en la VLAN.
- El `lock` solo evita colisiones dentro de un mismo nodo; entre nodos no hay nada que coordine.
- Para el Deployment hace falta un IPAM con un registro común para todo el clúster, como el de Calico para `eth0`: `whereabouts` ([§6](#6-prueba-5-ipam-whereabouts)) o `dhcp`.

---

## 6. Prueba 5: IPAM `whereabouts`

**Pregunta.** ¿Se puede instalar `whereabouts` en el escenario y da IPs distintas a todas las réplicas?

Salida completa: [`p5-whereabouts.txt`](investigacion-multus/salidas/p5-whereabouts.txt)

### 6.1 Requisito: salida a Internet desde los nodos

Los nodos tienen que descargar la imagen de `whereabouts` de `ghcr.io`:

```bash
ssh k8s-worker1 curl -sI https://ghcr.io | head -1      # HTTP/2 405
```

El `405` (*Method Not Allowed*) indica que el servidor **responde** pero no admite peticiones `HEAD`: el worker resuelve el nombre, llega a Internet y establece la conexión TLS. Hay salida (por la interfaz de `virbr0`, ver [datos del escenario §2](datos-escenario.md#2-máquinas-y-direcciones)).

### 6.2 Instalación

Con los manifiestos del repositorio oficial, commit `c4a6fce` (27/10/2026):

```bash
cd /tmp && git clone --depth 1 https://github.com/k8snetworkplumbingwg/whereabouts && cd whereabouts
kubectl apply -f doc/crds/daemonset-install.yaml \
              -f doc/crds/whereabouts.cni.cncf.io_ippools.yaml \
              -f doc/crds/whereabouts.cni.cncf.io_overlappingrangeipreservations.yaml
```

| Qué se crea | Resultado |
|---|---|
| CRDs | `ippools.whereabouts.cni.cncf.io` y `overlappingrangeipreservations.whereabouts.cni.cncf.io` (`v1alpha1`) |
| DaemonSet `whereabouts` (`kube-system`) | 3/3 Pods `Running`, uno por nodo (también en `k8s-master`). Usan la red del nodo (sus IPs son `10.10.10.10–12`) porque instalan el binario de IPAM en `/opt/cni/bin` de cada nodo |
| Imagen | `ghcr.io/k8snetworkplumbingwg/whereabouts:latest` |

### 6.3 Deployment con `whereabouts`

Misma NAD `macvlan` sobre `e2.1000`, con IPAM `whereabouts` y el rango `10.1.2.10`–`10.1.2.50` ([`nad-whereabouts.yaml`](investigacion-multus/nad-whereabouts.yaml)). Deployment `poc-wa` de 4 réplicas con la misma plantilla de las pruebas 3 y 4:

```bash
kubectl -n multus-poc apply -f docs/investigacion-multus/nad-whereabouts.yaml
sed -e 's/__NAME__/poc-wa/g' -e 's/__NAD__/vlan1000-wa/g' docs/investigacion-multus/deploy.tpl.yaml | kubectl -n multus-poc apply -f -
kubectl get ippools.whereabouts.cni.cncf.io -A -o yaml
```

**Resultado.** Los 4 Pods arrancan (2 por worker) y **cada uno recibe una IP distinta**, repartidas de forma intercalada entre los dos workers:

| Pod | Nodo | IP de `net1` |
|---|---|---|
| `poc-wa-…-bnwmj` 🔁 | `k8s-worker2` | `10.1.2.10/24` |
| `poc-wa-…-6s962` 🔁 | `k8s-worker1` | `10.1.2.11/24` |
| `poc-wa-…-77b2r` 🔁 | `k8s-worker2` | `10.1.2.12/24` |
| `poc-wa-…-gx4k8` 🔁 | `k8s-worker1` | `10.1.2.13/24` |

El registro común es un objeto `IPPool` en la API de Kubernetes (`10.1.2.0-24`, namespace `kube-system`). Cada entrada de `spec.allocations` es una IP (la clave es su posición dentro del rango: `"10"` = `10.1.2.10`) con el Pod que la tiene (`podref`), su interfaz (`ifname: net1`) y el contenedor (`id`). El plugin de cada nodo consulta y actualiza este mismo objeto antes de dar una IP, así que dos workers nunca reparten la misma.

| Ping | Resultado |
|---|---|
| `poc-wa-…-6s962` (`k8s-worker1`) → `10.1.2.12` (`poc-wa-…-77b2r`, `k8s-worker2`) | 3/3, `ttl=64` |
| `poc-wa-…-6s962` → `bbdd` (`10.1.2.100`) | 3/3, `ttl=64` |

**Conclusión.**
- `whereabouts` **resuelve el IPAM de los web**: un registro único para todo el clúster (como el de Calico para `eth0`), guardado en la API, que da IPs distintas a todas las réplicas aunque estén en workers diferentes.
- Los Pods se comunican entre workers y con los LXC por la VLAN.
- ⚠️ No viene instalado y el escenario se crea de cero cada día: la instalación tiene que **automatizarse** ([US-11](../historias/persona-a.md#us-11)).
- ⚠️ El manifiesto usa la imagen `:latest`: para que el despliegue sea reproducible conviene **fijar una versión** (un tag del repositorio y de la imagen) en vez de clonar la rama principal.

---

## 7. Prueba 6: ¿las NetworkPolicies filtran `net1`?

**Pregunta.** Con una política que lo deniega todo, ¿sigue funcionando el tráfico por la VLAN? Adelanta [US-33](../historias/persona-a.md#us-33).

Ping entre dos Pods de `poc-wa` en workers distintos, por las dos redes, antes y después de aplicar una NetworkPolicy *deny-all* en `multus-poc` ([`deny-all.yaml`](investigacion-multus/deny-all.yaml): `podSelector: {}`, `policyTypes: [Ingress, Egress]`, sin reglas):

```bash
kubectl -n multus-poc exec $P1 -- ping -c3 -W2 $E2     # por eth0 (Calico)
kubectl -n multus-poc exec $P1 -- ping -c3 -W2 $N2     # por net1 (VLAN)
kubectl -n multus-poc apply -f docs/investigacion-multus/deny-all.yaml
```

**Resultado** ([`p6-netpol.txt`](investigacion-multus/salidas/p6-netpol.txt)), de `poc-wa-…-6s962` (`k8s-worker1`) a `poc-wa-…-77b2r` (`k8s-worker2`):

| Ping | Sin políticas | Con `deny-all` |
|---|---|---|
| Por `eth0` (`172.16.126.4` 🔁) | ✅ 3/3, `ttl=62` | ❌ 0/3, `100% packet loss` |
| Por `net1` (`10.1.2.12` 🔁) | ✅ 3/3, `ttl=64` | ✅ 3/3, `ttl=64` |
| Por `net1` a `bbdd` (`10.1.2.100`) | — | ✅ 3/3, `ttl=64` |

El TTL también muestra que las dos redes funcionan distinto:
- **`eth0`, `ttl=62`:** el paquete pasa por **dos saltos de nivel 3**. El worker de origen lo enruta por el túnel IPIP y el de destino lo enruta hasta el Pod (ver [guía de Calico §3.3](useful/calico/guia-calico.md#33-pod--pod-en-otro-nodo-pasos-18-en-naranja)).
- **`net1`, `ttl=64`:** **ningún router**. Los Pods están en la misma red de nivel 2 (la VLAN).

**Conclusión.**
- Calico aplica las NetworkPolicies **solo a `eth0`**, la interfaz que gestiona (sus reglas van en las `caliXXXX` del nodo). El tráfico de `net1` (macvlan sobre `e2.1000`) **no pasa por esas reglas**.
- Con las políticas del enunciado (§5) activas, el SSH del admin a los web y a los LXC y el acceso a MariaDB por la VLAN **seguirán funcionando sin reglas extra**.
- ⚠️ Consecuencia para la memoria: las NetworkPolicies **no protegen la VLAN**. Allí la seguridad depende de las claves SSH y de los usuarios de MariaDB. Filtrar `net1` necesitaría otro mecanismo (por ejemplo, `MultiNetworkPolicy` o reglas en los propios Pods), que el enunciado no pide.

---

## 8. Prueba 7: la NAD con Terraform

**Pregunta.** ¿Cómo se escribe la NAD con `kubernetes_manifest` en el provider `hashicorp/kubernetes` 2.23.0? Base de [US-11](../historias/persona-a.md#us-11).

La misma NAD `whereabouts` de la prueba 5, escrita en HCL en una carpeta aparte, [`terraform-nad/`](investigacion-multus/terraform-nad/), para no mezclarla con [`terraform/`](../terraform/): [`nad.tf`](investigacion-multus/terraform-nad/nad.tf) + una copia de [`k8s-provider.tf`](../terraform/k8s-provider.tf). `spec.config` es un **string JSON**, así que se genera con `jsonencode()`:

```hcl
resource "kubernetes_manifest" "vlan1000_tf" {
  manifest = {
    apiVersion = "k8s.cni.cncf.io/v1"
    kind       = "NetworkAttachmentDefinition"
    metadata   = { name = "vlan1000-tf", namespace = "multus-poc" }
    spec = {
      config = jsonencode({
        cniVersion = "0.3.1"
        type       = "macvlan"
        master     = "e2.1000"
        mode       = "bridge"
        ipam = { type = "whereabouts", range = "10.1.2.0/24", range_start = "10.1.2.10", range_end = "10.1.2.50" }
      })
    }
  }
}
```

En la VM `terraform`, `init`, `validate`, `plan` y `apply`. En el host, un Deployment `poc-tf` de 4 réplicas que usa esa NAD.

**Resultado** ([`p7-terraform.txt`](investigacion-multus/salidas/p7-terraform.txt)):

| Paso | Resultado |
|---|---|
| `terraform init` | Terraform v1.17.2 instala `hashicorp/kubernetes` **v2.23.0** (firmado por HashiCorp) |
| `terraform validate` | `Success! The configuration is valid.` |
| `terraform plan` | `Plan: 1 to add`. Muestra dos atributos: `manifest` (lo que declaramos) y `object` (el objeto completo que devolverá la API, con `uid`, `creationTimestamp`… `known after apply`) |
| `terraform apply` | `Creation complete after 1s` |
| `kubectl get net-attach-def vlan1000-tf` | Existe. Su `spec.config` es el mismo JSON que [`nad-whereabouts.yaml`](investigacion-multus/nad-whereabouts.yaml), con las claves en orden alfabético: `jsonencode()` siempre las ordena así, y en JSON el orden no importa |
| Deployment `poc-tf` (4 réplicas) | Arranca. IPs de `net1`: `10.1.2.14`, `.15`, `.16`, `.17`, **a continuación** de las `.10`–`.13` que ya tenía `poc-wa` |

**Conclusión.**
- `kubernetes_manifest` con `jsonencode()` crea la NAD correctamente con el provider 2.23.0: es la forma de escribirla en `terraform/multus.tf` ([US-11](../historias/persona-a.md#us-11)). El CRD de Multus ya existe en el escenario, que es lo que necesita `kubernetes_manifest` en el `plan`.
- **Dos NAD distintas con el mismo `range` comparten el mismo `IPPool`** (`10.1.2.0-24`): `whereabouts` no repite IPs aunque las pidan NAD diferentes.
- ⚠️ `whereabouts` **no sabe nada de las IPs fijas**: la IP `static` del admin y las de los LXC tienen que quedar **fuera** de `range_start`–`range_end` (o añadirse en `exclude`). El [plan de direccionamiento](#91-plan-de-direccionamiento-borrador-para-us-11) ya lo cumple.
- `terraform init` crea `.terraform.lock.hcl` y recomienda subirlo a Git; el equipo decidió **no** versionarlo porque el entorno se recrea a diario y la versión del provider ya está fijada (ver [`.gitignore`](../.gitignore)).

---

## 9. Decisiones

| Tema | Decisión | Basada en | Dónde queda |
|---|---|---|---|
| Tipo de NAD | `macvlan`, modo `bridge`, `master: e2.<vlan>` | §2, §3 | Este documento |
| VLAN y subred | Propuesta: VLAN **1000**, `10.1.2.0/24` | §2 | [US-03](../historias/persona-c.md#us-03) (C) |
| IPAM del admin | `static`, con su IP fija en la anotación | §4 | [D-005](../decisions.md) |
| IPAM de los web | **`whereabouts`**, instalado en cada arranque del escenario. Descartados: `static` (el Pod no arranca) y `host-local` (IPs duplicadas entre workers) | §4, §5, §6 | [D-005](../decisions.md) |
| Número de NAD | **Dos** sobre la misma VLAN: una `static` para el admin y otra `whereabouts` para los web | §4, §6 | [US-11](../historias/persona-a.md#us-11) |
| Cómo se escribe en Terraform | `kubernetes_manifest` con `spec.config = jsonencode({…})` | §8 | [US-11](../historias/persona-a.md#us-11) |

### 9.1 Plan de direccionamiento (borrador para US-11)

VLAN **1000**, subred **`10.1.2.0/24`**, una sola VLAN para Pods y LXC, como describe el enunciado:

| Quién | IP en la VLAN | Cómo se asigna |
|---|---|---|
| Pod admin | `10.1.2.5` | NAD `static` con `"capabilities": {"ips": true}` + IP en la anotación del Pod |
| Pods web (Deployment) | `10.1.2.10`–`10.1.2.50` | NAD `whereabouts` |
| LXC `bbdd` | `10.1.2.100` | Fija en el XML de VNX (ya es así) |
| LXC `logs` | `10.1.2.101` | Fija en el XML de VNX. Hoy está en la VLAN 1001 (`10.1.3.100`): pasarla a la VLAN 1000 ([US-12](../historias/persona-a.md#us-12)) |
| `vlan-router` | — | Sobra con una sola VLAN: quitarlo de [`vnx-vlan.xml`](../vnx/vnx-vlan.xml) y las rutas por él de los LXC |

Los rangos no se solapan: la IP del admin y las de los LXC quedan fuera del rango de `whereabouts`.

---

## 10. Problemas encontrados

| Síntoma | Causa | Solución |
|---|---|---|
| `sudo: tcpdump: command not found` | El host del laboratorio no tiene `tcpdump`, ni los workers | Capturar con `tshark` (o Wireshark) en el host |
| `Sorry, user … is not allowed to execute '/usr/bin/tshark …' as root` | El usuario solo puede usar `sudo` con algunos comandos (como `vnx`) | Ejecutar `tshark` **sin** `sudo`: el usuario ya tiene permisos de captura |
| Un `cat > fichero <<'EOF'` pegado en la terminal sale mezclado (`EOFait"]…`) | La terminal descoloca las líneas al pegar bloques largos | Crear los YAML desde el editor de VS Code y dejar la terminal para comandos cortos |
| `Warning: Permanently added 'k8s-workerN' … to the list of known hosts` en cada `ssh` | El escenario no guarda las claves de los nodos | Ninguna: es solo un aviso |
| `tee: …/p7-terraform.txt: Permiso denegado` al añadir desde el host | El fichero lo creó la VM `terraform`, donde se trabaja como `root`; como `/shared` es la misma carpeta que `shared/` del host, en el host queda con dueño `root` | Cambiar el dueño desde la VM: `ssh terraform "chown $(id -u):$(id -g) /shared/…/fichero"` |
| La hora de las salidas de la VM `terraform` va una hora por detrás | La VM usa la hora UTC; el host, la de Madrid | Ninguna: tenerlo en cuenta al comparar horas |
| `bash: pod-de-worker1: No existe el fichero o el directorio` | Se ejecutó un comando con el marcador `<pod-de-worker1>` sin sustituir: bash interpreta `<` como «leer de un fichero» | Sustituir los marcadores `<…>` por el valor real, o sacarlo con una variable (`--field-selector spec.nodeName=…`) |

---

## 11. Pendientes

- [x] Prueba 4: `host-local` ([§5](#5-prueba-4-ipam-host-local-en-un-deployment)).
- [x] Prueba 5: `whereabouts` ([§6](#6-prueba-5-ipam-whereabouts)).
- [x] Prueba 6: NetworkPolicies y `net1` ([§7](#7-prueba-6-las-networkpolicies-filtran-net1)).
- [x] Prueba 7: la NAD con Terraform ([§8](#8-prueba-7-la-nad-con-terraform)).
- [ ] `terraform destroy` de [`terraform-nad/`](investigacion-multus/terraform-nad/) y borrar el Deployment `poc-tf`.
- [x] IPAM de los web y plan de direccionamiento ([§9](#9-decisiones)).
- [ ] Escribir [D-005](../decisions.md) **en inglés**, con la plantilla del fichero, y pasarla a *Accepted*.
- [ ] Elegir la versión fija de `whereabouts` (tag del repositorio y de la imagen) para [US-11](../historias/persona-a.md#us-11).
- [ ] Proponer a C la VLAN 1000 y `10.1.2.0/24` para cerrar [US-03](../historias/persona-c.md#us-03).
- [ ] Borrar el namespace `multus-poc` (criterio 🧪 de [US-19](../historias/persona-a.md#us-19)).