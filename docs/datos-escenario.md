# 🧪 Datos del escenario

⬅️ [Volver al plan](../plan.md) · Historia: [US-02](../historias/persona-a.md#us-02)

Datos medidos en el entorno desplegado el **13/11/2026**. El entorno se crea **de cero cada día de trabajo** y solo este repo persiste. Lo marcado con 🔁 puede cambiar entre despliegues: vuelvan a comprobarlo antes de usarlo en Terraform o en `verify.sh`.

---

## 1. Cómo levantar el entorno

En el host del laboratorio:

```bash
/lab/cnvr/bin/get-k8s-calico                       # descarga el escenario en /mnt/tmp/k8s_lab-calico-v02
cd /mnt/tmp/k8s_lab-calico-v02
./bin/start-k8s-calico                             # crea el clúster, une los workers e intenta cargar MetalLB
sudo vnx -f k8s_lab-calico.xml -x config_metallb   # relanzar (ver §6)
kubectl get ipaddresspools -n metallb-system       # debe mostrar el pool
sudo vnx -f k8s_lab-terraform.xml --create         # VM LXC "terraform"
sudo vnx -f k8s_lab-terraform.xml -x install-terraform
./bin/get-master-kubeconf                          # kubeconfig → ~/.kube/config del host
./bin/set-terraform-kubeconf                       # kubeconfig → VM terraform

cd /mnt/tmp/k8s_lab-calico-v02/shared/
git clone https://github.com/arsn-g2/terraform-k8s-trabajofinal.git

# start the vlan and db, logs server
cd /mnt/tmp/k8s_lab-calico-v02/shared/terraform-k8s-trabajofinal/vnx
sudo vnx -f vnx-vlan.xml --create
sudo vnx -f vnx-vm-bdd-logs.xml --create

cd /mnt/tmp/k8s_lab-calico-v02
code .


```

Para trabajar con Terraform:

```bash
ssh terraform
cd /shared/terraform-k8s-trabajofinal/terraform
terraform init && terraform plan
```

Para apagarlo todo: `./bin/stop-k8s-calico` y `sudo vnx -f k8s_lab-terraform.xml --destroy`.

---

## 2. Máquinas y direcciones

| Máquina | Tipo | `k8s_LAN` (10.10.10.0/24) | Otras interfaces |
|---|---|---|---|
| `k8s-master` | KVM, 2 vCPU, 3 GB | `10.10.10.10` | — |
| `k8s-worker1` | KVM, 1 vCPU, 3 GB | `10.10.10.11` (`e1`) | `e2` en `VlanNet`, sin IP |
| `k8s-worker2` | KVM, 1 vCPU, 3 GB | `10.10.10.12` (`e1`) | `e2` en `VlanNet`, sin IP |
| `r1` | LXC (router) | `10.10.10.1` | `10.10.20.1` en `user_LAN` |
| `terraform` | LXC | `10.10.10.13` | — |
| **host** | — | (vía `r1`) | **`10.10.20.2`** en `user_LAN` |

- El host llega a `10.10.10.0/24` y a `10.10.100.0/24` a través de `r1` (`10.10.20.1`). Los nodos llegan a `10.10.20.0/24` a través de `r1` (`10.10.10.1`).
- **`r1` enruta sin NAT** (no hay reglas `MASQUERADE`): el tráfico del host llega al clúster con origen `10.10.20.2`. Esto es lo que permite la NetworkPolicy del admin con `ipBlock 10.10.20.2/32` ([US-32](../historias/persona-c.md#us-32)).
- Todas las máquinas tienen además una interfaz de gestión de VNX (`e0`/`eth0`, `192.168.50.x/30`) y una de salida a Internet por `virbr0` (`e9`/`eth9`, DHCP `192.168.122.0/24`). No se usan en el proyecto.
- Nombres resolubles desde el host por SSH: `k8s-master`, `k8s-worker1`, `k8s-worker2`, `r1`, `terraform` (usuario `root`, clave del escenario).

---

## 3. Kubernetes

| Dato | Valor |
|---|---|
| Versión | v1.37.0 (kubeadm), containerd 2.3.5, Ubuntu 24.04.5 |
| `kubectl` del host | v1.29.3. Avisa de *version skew* con el servidor; para lo básico funciona. Si algo falla, usar `ssh root@k8s-master kubectl …` |
| CNI principal | Calico, interfaz `e1` (`IP_AUTODETECTION_METHOD=interface=e1`) |
| Red de Pods (Calico) | `172.16.0.0/16`, encapsulado IPIP (`ipipMode: Always`) |
| Red de Services | `10.96.0.0/12` |
| Namespaces existentes | `default`, `kube-system`, `kube-public`, `kube-node-lease`, `ingress-nginx`, `metallb-system` |
| Labels de nodo para `nodeSelector` | `kubernetes.io/hostname=k8s-worker1` / `k8s-worker2` |

El clúster arranca vacío: en `default` solo está el Service `kubernetes`.

---

## 4. Multus y red VLAN

| Dato | Valor |
|---|---|
| Multus | **Instalado**, modo *thick* (`ghcr.io/k8snetworkplumbingwg/multus-cni:snapshot-thick`), DaemonSet `kube-multus-ds` en los 3 nodos |
| CRD | `network-attachment-definitions.k8s.cni.cncf.io` (v1) existe, así que `kubernetes_manifest` puede crear NADs |
| Config | `/etc/cni/net.d/00-multus.conf` delega en `10-calico.conflist` como red por defecto |
| Plugins en `/opt/cni/bin` (workers) | `bridge`, `macvlan`, `ipvlan`, `vlan`, `host-device`, `host-local`, `static`, `dhcp`, `tuning`, `portmap`, `bandwidth`, `firewall`, `sbr`, `vrf`, `tap`, `dummy`, `ptp`, `passthru`, `loopback`, `calico`, `calico-ipam`, `flannel`, `multus-shim` |
| `whereabouts` | **No instalado** (ver [D-005](../decisions.md)) |
| Interfaz hacia `VlanNet` | **`e2`** en los dos workers (no `eth2`), en estado UP y sin IP. `VlanNet` es un switch Open vSwitch compartido con el escenario de los LXC |
| Subinterfaces VLAN | Ninguna todavía. Hay que crear `e2.<vlan>` en cada arranque ([US-10](../historias/persona-a.md#us-10)) |

Cómo lo hicimos en la práctica 1.3 y plantillas para Terraform: [guía de Multus](useful/multus/guia-multus.md).

VLAN ID y subred: **pendientes** ([US-03](../historias/persona-c.md#us-03)). Como referencia, `k8s_lab-vms-vlan.xml` (práctica 1.3) usa los tags 1000 y 1001 con `10.1.2.0/24` y `10.1.3.0/24`.

---

## 5. Ingress

| Dato | Valor |
|---|---|
| Controller | ingress-nginx 1.15.1, namespace `ingress-nginx`, 1 réplica (en `k8s-worker1`) 🔁 |
| IngressClass | **`nginx`** (`k8s.io/ingress-nginx`) |
| Labels del Pod del controller | `app.kubernetes.io/name=ingress-nginx`, `app.kubernetes.io/component=controller`, `app.kubernetes.io/instance=ingress-nginx` |
| Label del namespace | `kubernetes.io/metadata.name=ingress-nginx` |
| Service | `ingress-nginx-controller`, tipo `LoadBalancer`, ClusterIP `10.98.225.191`, NodePorts **`80:30097`** y **`443:30753`** 🔁 |
| IP externa | `<pending>` mientras MetalLB no tenga pool (§6) 🔁 |

Mientras no haya IP externa, el Ingress se prueba por NodePort desde el host: `curl http://10.10.10.11:30097/servers-G2`.

---

## 6. MetalLB

| Dato | Valor |
|---|---|
| Versión | 0.16.1 (controller en `k8s-worker1`, speaker en los 3 nodos) |
| Pool previsto | `10.10.10.20-10.10.10.30` (`/root/k8s/metallb-config.yaml` en `k8s-master`) |
| Estado el 13/11/2026 | ⚠️ **Sin `IPAddressPool` ni `L2Advertisement`**: `start-k8s-calico` no dejó la configuración aplicada |

Conceptos, lo que hicimos en P1.3 y problemas conocidos: [guía de MetalLB](useful/metallb/guia-metallb.md).

Arreglo: relanzar `sudo vnx -f k8s_lab-calico.xml -x config_metallb` o aplicar el fichero directamente con `ssh root@k8s-master kubectl apply -f /root/k8s/metallb-config.yaml`. Comprobar con:

```bash
kubectl get ipaddresspools,l2advertisements -n metallb-system
kubectl get svc -n ingress-nginx ingress-nginx-controller   # EXTERNAL-IP dentro de 10.10.10.20-30
```

---

## 7. VM `terraform`

| Dato | Valor |
|---|---|
| IP | `10.10.10.13` (`k8s_LAN`) |
| Terraform | v1.17.2 |
| Repo | `/shared/terraform-k8s-trabajofinal` (es el `shared/` del host montado) |
| kubeconfig | `~/.kube/config`, copiado por `bin/set-terraform-kubeconf` |
| Provider | `hashicorp/kubernetes` 2.23.0 ([US-01](../historias/persona-b.md#us-01)) |

Los ficheros se editan desde el host; `terraform` se ejecuta dentro de la VM.

---



---

## 9. Escenario VNX complementario (LXC en `VlanNet`)

Definido en `vnx/`, a partir de `k8s_lab-vms-vlan.xml` de la práctica 1.3 ([US-12](../historias/persona-a.md#us-12)). **Todavía no se ha desplegado**: los valores son los del XML, no medidos. Por ahora solo levanta la infraestructura básica, sin `exec` ni `filetree` (sin MariaDB, rsyslog ni claves SSH).

Son dos escenarios independientes, cada uno con su `vnx --create`:

| Fichero | `scenario_name` | Contenido | `automac offset` | Red de gestión (`vm_mgmt`) |
|---|---|---|---|---|
| `vnx/vnx-vlan.xml` | `tf-vlan` | `vlan-router` | 2 | `10.250.0.0/24` |
| `vnx/vnx-vm-bdd-logs.xml` | `tf-bdd-logs` | `bbdd`, `logs` | 3 | `10.251.0.0/24` |

El nombre, el offset de MACs y la red de gestión tienen que ser distintos entre sí y respecto a `k8s_lab-kubeadm` (offset 0, `192.168.50.0/24`) y `k8s_lab-terraform` (offset 1, `192.168.50.0/24`, offset de gestión 100). Si coinciden, VNX mezcla los escenarios, las IPs de gestión chocan o dos contenedores salen con la misma MAC en `virbr0`.

| Máquina | Tipo | `VlanNet` (puerto *access*) | Otras interfaces |
|---|---|---|---|
| `vlan-router` | LXC, Ubuntu 20.04, `forwarding ip` | `eth1` tag **1000**, `10.1.2.1/24` · `eth2` tag **1001**, `10.1.3.1/24` | `eth9` en `virbr0` (DHCP) |
| `bbdd` | LXC, Ubuntu 20.04 | `eth1` tag **1000**, `10.1.2.100/24` | `eth9` en `virbr0` (DHCP); ruta `10.1.0.0/16` vía `10.1.2.1` |
| `logs` | LXC, Ubuntu 20.04 | `eth1` tag **1001**, `10.1.3.100/24` | `eth9` en `virbr0` (DHCP); ruta `10.1.0.0/16` vía `10.1.3.1` |

- Los tags, las subredes y la necesidad del `vlan-router` son los de la plantilla y siguen **pendientes** ([US-03](../historias/persona-c.md#us-03)). Con una única VLAN compartida, como describe el enunciado, el router sobra.
- **Cómo funciona la VLAN en `VlanNet`:** los puertos de los workers (`k8s-worker1-e2`, `k8s-worker2-e2`) no tienen tag, son *trunk*, así que los workers necesitan la subinterfaz `e2.<vlan>`. Los LXC tienen puertos *access* con tag: OVS pone y quita la etiqueta, y el contenedor ve tráfico sin etiquetar en `eth1`.
- La interfaz de `virbr0` es la salida a Internet que necesitarán los `exec` para instalar paquetes (`apt`).
- Rootfs: `/usr/share/vnx/filesystems/vnx_rootfs_lxc_ubuntu64-20.04-v025-vnxlab`. En el host también está la `24.04-v025-vnxlab`.

Arranque y parada (el clúster tiene que estar levantado antes, porque crea `VlanNet`: en estos XML tiene `managed="no"`):

```bash
cd /mnt/tmp/k8s_lab-calico-v02/shared/terraform-k8s-trabajofinal/vnx
sudo vnx -f vnx-vlan.xml --create
sudo vnx -f vnx-vm-bdd-logs.xml --create
sudo ovs-vsctl show                          # puertos de VlanNet y su tag
sudo vnx -f vnx-vm-bdd-logs.xml --destroy    # parada
sudo vnx -f vnx-vlan.xml --destroy
```
