# 🌐 Investigación: Multus, tipo de NAD e IPAM

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
- Corrección a la [guía de Multus §6](useful/multus/guia-multus.md#6-errores-que-ya-conocemos): con IPAM `static` y sin `ips` en la anotación, `net1` no se crea sin IP; **el Pod no llega a arrancar**.

---

## 5. Prueba 4: IPAM `host-local` en un Deployment

**Pregunta.** ¿`host-local` da IPs repetidas a Pods de workers distintos?

`⟪PENDIENTE: prueba 4⟫`

---

## 6. Prueba 5: IPAM `whereabouts`

**Pregunta.** ¿Se puede instalar `whereabouts` en el escenario y da IPs distintas a todas las réplicas?

`⟪PENDIENTE: prueba 5⟫`

---

## 7. Prueba 6: ¿las NetworkPolicies filtran `net1`?

**Pregunta.** Con una política que lo deniega todo, ¿sigue funcionando el tráfico por la VLAN? Adelanta [US-33](../historias/persona-a.md#us-33).

`⟪PENDIENTE: prueba 6⟫`

---

## 8. Prueba 7: la NAD con Terraform

**Pregunta.** ¿Cómo se escribe la NAD con `kubernetes_manifest` en el provider `hashicorp/kubernetes` 2.23.0? Base de [US-11](../historias/persona-a.md#us-11).

`⟪PENDIENTE: prueba 7⟫`

---

## 9. Decisiones

| Tema | Decisión | Basada en | Dónde queda |
|---|---|---|---|
| Tipo de NAD | `macvlan`, modo `bridge`, `master: e2.<vlan>` | §2, §3 | Este documento |
| VLAN y subred | Propuesta: VLAN **1000**, `10.1.2.0/24` | §2 | [US-03](../historias/persona-c.md#us-03) (C) |
| IPAM del admin | `static`, con su IP en la anotación | §4 | [D-005](../decisions.md) |
| IPAM de los web | `⟪PENDIENTE: pruebas 4 y 5⟫` | §4, §5, §6 | [D-005](../decisions.md) |

Plan de direccionamiento para [US-11](../historias/persona-a.md#us-11): `⟪PENDIENTE: depende del IPAM de los web⟫`

---

## 10. Problemas encontrados

| Síntoma | Causa | Solución |
|---|---|---|
| `sudo: tcpdump: command not found` | El host del laboratorio no tiene `tcpdump`, ni los workers | Capturar con `tshark` (o Wireshark) en el host |
| `Sorry, user … is not allowed to execute '/usr/bin/tshark …' as root` |Ejecutar `tshark` **sin** `sudo`: ya tenemos permisos de captura |


---

## 11. Pendientes

- [ ] Prueba 4: `host-local` ([§5](#5-prueba-4-ipam-host-local-en-un-deployment)).
- [ ] Prueba 5: `whereabouts` ([§6](#6-prueba-5-ipam-whereabouts)).
- [ ] Prueba 6: NetworkPolicies y `net1` ([§7](#7-prueba-6-las-networkpolicies-filtran-net1)).
- [ ] Prueba 7: la NAD con Terraform ([§8](#8-prueba-7-la-nad-con-terraform)).
- [ ] IPAM de los web y plan de direccionamiento ([§9](#9-decisiones)); pasar [D-005](../decisions.md) a *Accepted*.
- [ ] Proponer a C la VLAN 1000 y `10.1.2.0/24` para cerrar [US-03](../historias/persona-c.md#us-03).
- [ ] Borrar el namespace `multus-poc` (criterio 🧪 de [US-19](../historias/persona-a.md#us-19)).