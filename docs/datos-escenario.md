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

Cómo lo hicimos en la práctica 1.3 y plantillas para Terraform: [guía de Multus](guia-multus.md).

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

Conceptos, lo que hicimos en P1.3 y problemas conocidos: [guía de MetalLB](guia-metallb.md).

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

## 8. Valores para `variables.tf`

Nombres **propuestos** en [US-01](../historias/persona-b.md#us-01); el `variables.tf` actual todavía es el de P1.4 (solo `num_replicas`).

| Variable | Valor |
|---|---|
| `group_number` | `2` → ruta `/servers-G2` ([D-001](../decisions.md)) |
| `image_web` | `dgsgiros/nginx-ssh:latest` (usuario `webuser`, GID 1000) |
| `image_admin` | `dgsgiros/admin-ssh:latest` (usuario `adminuser`, GID 1000) |
| `host_user_lan_ip` | `10.10.20.2` |
| `worker1_ip` | `10.10.10.11` |
| `ingress_class` | `nginx` |
| `vlan_master_if` | `e2` |
| `vlan_id`, `vlan_subnet` | pendientes ([US-03](../historias/persona-c.md#us-03)) |
