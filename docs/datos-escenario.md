# 🧪 Datos del escenario

⬅️ [Volver al plan](../plan.md) · Historia: [US-02](../historias/persona-a.md#us-02)

Datos medidos en el entorno desplegado el **13/11/2026**. El entorno se crea **de cero cada día de trabajo** y solo este repo persiste. Lo marcado con 🔁 puede cambiar entre despliegues: vuelvan a comprobarlo antes de usarlo en Terraform o en `verify.sh`.

---

## 1. Cómo levantar el entorno

En el host del laboratorio:

```bash
/lab/cnvr/bin/get-k8s-calico                       # descarga el escenario en /mnt/tmp/k8s_lab-calico-v03
cd /mnt/tmp/k8s_lab-calico-v03
./bin/start-k8s-calico                             # crea el clúster, une los workers e intenta cargar MetalLB
sudo vnx -f k8s_lab-calico.xml -x config_metallb   # relanzar (ver §6)
kubectl get ipaddresspools -n metallb-system       # debe mostrar el pool
sudo vnx -f k8s_lab-terraform.xml --create         # VM LXC "terraform"
sudo vnx -f k8s_lab-terraform.xml -x install-terraform
./bin/get-master-kubeconf                          # kubeconfig → ~/.kube/config del host
./bin/set-terraform-kubeconf                       # kubeconfig → VM terraform

cd /mnt/tmp/k8s_lab-calico-v03/shared/
git clone https://github.com/arsn-g2/terraform-k8s-trabajofinal.git
cd /mnt/tmp/k8s_lab-calico-v03/
code .
cd /mnt/tmp/k8s_lab-calico-v03/shared/terraform-k8s-trabajofinal
chmod +x scripts/*
# claves SSH del día (US-16): antes de crear los LXC y de terraform apply
./scripts/gen-keys.sh
# VLAN 1000 (D-009): subinterfaz e2.1000 en los workers y LXC bbdd y logs (§9)
./scripts/setup-vlan-workers.sh                    # crea e2.1000 en k8s-worker1 y k8s-worker2 (idempotente)
./scripts/setup-whereabouts.sh                     # instala el IPAM whereabouts v0.9.4 (D-010, idempotente)


# start the vnx infra: bbdd, logs servers
cd /mnt/tmp/k8s_lab-calico-v03/shared/terraform-k8s-trabajofinal/vnx
sed 's/__CAMBIA_ESTA_PASSWORD__/1q2w3e4r/g' filetree/bbdd/init.sql.example > filetree/bbdd/init.sql
sudo vnx -f vnx-vm-bdd-logs.xml --create


```

Para trabajar con Terraform:

```bash
ssh terraform
cd /shared/terraform-k8s-trabajofinal/terraform
terraform init && terraform plan
```

Para apagarlo todo: `sudo vnx -f vnx/vnx-vm-bdd-logs.xml --destroy` (desde el repo), `./bin/stop-k8s-calico` y `sudo vnx -f k8s_lab-terraform.xml --destroy`.

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
| `whereabouts` | v0.9.4. No viene con el escenario: lo instala `scripts/setup-whereabouts.sh` en cada arranque ([D-010](../decisions.md)). DaemonSet `whereabouts` e `IPPool` en `kube-system` |
| Interfaz hacia `VlanNet` | **`e2`** en los dos workers (no `eth2`), en estado UP y sin IP. `VlanNet` es un switch Open vSwitch compartido con el escenario de los LXC |
| Subinterfaces VLAN | `e2.1000` en los dos workers. La crea `scripts/setup-vlan-workers.sh` en cada arranque ([US-10](../historias/persona-a.md#us-10)) |

Cómo lo hicimos en la práctica 1.3 y plantillas para Terraform: [guía de Multus](useful/multus/guia-multus.md).

VLAN ID y subred: **1000** y `10.1.2.0/24` ([D-009](../decisions.md)). Terraform crea dos NAD en `multus.tf` ([US-11](../historias/persona-a.md#us-11)): `vlan1000-web` (whereabouts, `10.1.2.10`–`10.1.2.50`) y `vlan1000-admin` (static; el Pod pide `10.1.2.5/24` en su anotación).

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

Definido en `vnx/vnx-vm-bdd-logs.xml`, a partir de `k8s_lab-vms-vlan.xml` de la práctica 1.3 ([US-12](../historias/persona-a.md#us-12)). Desplegado el **16/11/2026**: los tags de `VlanNet` y el ping desde `k8s-worker1` por `e2.1000` a las dos IPs están en [`capturas/us-12-vnx-una-vlan.txt`](capturas/us-12-vnx-una-vlan.txt). Por ahora solo levanta la infraestructura básica, sin `exec` ni `filetree` (sin MySQL, rsyslog ni claves SSH).

Hay **una sola VLAN compartida** (D-009): ID **1000**, subred `10.1.2.0/24`. La plantilla de P1.3 tenía dos VLAN (1000 y 1001) unidas por un `vlan-router`; con una sola VLAN el router sobra, así que se han quitado `vnx/vnx-vlan.xml` y el `vlan-router`, y los LXC ya no llevan la ruta `10.1.0.0/16`.

| Fichero | `scenario_name` | Contenido | `automac offset` | Red de gestión (`vm_mgmt`) |
|---|---|---|---|---|
| `vnx/vnx-vm-bdd-logs.xml` | `tf-bdd-logs` | `bbdd`, `logs` | 3 | `10.251.0.0/24` |

El nombre, el offset de MACs y la red de gestión tienen que ser distintos de los de `k8s_lab-kubeadm` (offset 0, `192.168.50.0/24`) y `k8s_lab-terraform` (offset 1, `192.168.50.0/24`, offset de gestión 100). Si coinciden, VNX mezcla los escenarios, las IPs de gestión chocan o dos contenedores salen con la misma MAC en `virbr0`.

| Máquina | Tipo | `VlanNet` (puerto *access*) | Otras interfaces |
|---|---|---|---|
| `bbdd` | LXC, Ubuntu 20.04 | `eth1` tag **1000**, `10.1.2.100/24` | `eth9` en `virbr0` (DHCP) |
| `logs` | LXC, Ubuntu 20.04 | `eth1` tag **1000**, `10.1.2.101/24` | `eth9` en `virbr0` (DHCP) |

- Plan de direcciones de la VLAN (D-009): admin `10.1.2.5` (`static`), Pods web `10.1.2.10`–`10.1.2.50` (`whereabouts`, D-005), `bbdd` `10.1.2.100`, `logs` `10.1.2.101`.
- **Cómo funciona la VLAN en `VlanNet`:** los puertos de los workers (`k8s-worker1-e2`, `k8s-worker2-e2`) no tienen tag, son *trunk*, así que los workers necesitan la subinterfaz `e2.1000`, que crea `scripts/setup-vlan-workers.sh` ([US-10](../historias/persona-a.md#us-10)) y hay que relanzar en cada arranque. Los LXC tienen puertos *access* con tag: OVS pone y quita la etiqueta, y el contenedor ve tráfico sin etiquetar en `eth1`.
- La interfaz de `virbr0` es la salida a Internet que necesitarán los `exec` para instalar paquetes (`apt`).
- Rootfs: `/usr/share/vnx/filesystems/vnx_rootfs_lxc_ubuntu64-20.04-v025-vnxlab`. En el host también está la `24.04-v025-vnxlab`.

Arranque y parada (el clúster tiene que estar levantado antes, porque crea `VlanNet`: en este XML tiene `managed="no"`):

```bash
cd /mnt/tmp/k8s_lab-calico-v03/shared/terraform-k8s-trabajofinal
./scripts/setup-vlan-workers.sh              # e2.1000 en los workers
sudo vnx -f vnx/vnx-vm-bdd-logs.xml --create
sudo ovs-vsctl show                          # puertos de VlanNet y su tag (bbdd-e1 y logs-e1 con tag 1000)
sudo vnx -f vnx/vnx-vm-bdd-logs.xml --destroy   # parada
```

---

## 10. NetworkPolicies y direccionamiento de los Pods

Explicación de cómo encajan las NetworkPolicies del enunciado (§5 del PDF) con el escenario. Las IPs de Pods del diagrama son ejemplos.

### 10.1 ¿Cada Pod necesita una IP distinta? ¿Hay que configurarla?

- **No hay que configurar nada para `eth0`.** El IPAM de Calico asigna a cada Pod una IP única de la red de Pods `172.16.0.0/16` (§3). Calico reparte bloques `/26` por nodo, así que no hay colisiones.
- **Las NetworkPolicies no usan IPs de Pods.** Seleccionan Pods por **labels** (`podSelector`), y Calico traduce esos labels a las IPs actuales. La única IP literal en una policy es el `ipBlock` del host, porque el host no es un Pod y no tiene labels.
- **Donde sí importa la IP es en la segunda interfaz (`net1`, la VLAN).** Esa IP la da el IPAM del NAD de Multus, no Calico, y las NetworkPolicies no le aplican (ver §10.4).

### 10.2 Dónde se aplican las políticas

Calico aplica las políticas en la **veth del lado del host de cada Pod** (`caliXXXX` en el worker). Todo paquete que entra o sale por el `eth0` del Pod pasa por las reglas iptables que Calico genera a partir de las políticas que seleccionan ese Pod.

```
                         ┌──────────────────────── namespace ingress-nginx ───────────────┐
 Clientes / host         │  Pod ingress-nginx-controller   (k8s-worker1)                  │
 10.10.20.2              │  labels: app.kubernetes.io/name=ingress-nginx                  │
   │                     │  eth0 172.16.x.a  (IP de Calico)                               │
   │ HTTP                └───────────────▲──────────────────────────┬─────────────────────┘
   │ 10.10.10.11:30097 (NodePort)        │                          │ conexión NUEVA
   │ o MetalLB 10.10.10.2x:80 ───────────┘                          │ src 172.16.x.a
   │                                                                │ dst <IP Pod web>:80  (puerto del Pod, NO 8080)
   │                                                                ▼
   │      ┌────────────────────────── namespace var.namespace (G2) ──────────────────────────────┐
   │      │                                                                                      │
   │      │   ⓪ default-deny  podSelector {}  policyTypes [Ingress, Egress]  → aplica a TODOS ↓  │
   │      │                                                                                      │
   │      │   ① allow-web-from-ingress   (podSelector app=web)                                   │
   │      │      ingress.from: { namespaceSelector name=ingress-nginx                            │
   │      │                      AND podSelector app.kubernetes.io/name=ingress-nginx }          │
   │      │      ports: TCP 80                                                                   │
   │      │        ┌─────────┐  ┌─────────┐  ┌─────────┐                                        │
   │      │        │ S1 web  │  │ S2 web  │  │ S3 web  │    eth0 172.16.<w1|w2>.y  :80          │
   │      │        │ ◄─cali  │  │ ◄─cali  │  │ ◄─cali  │    ◄─cali = donde Calico aplica        │
   │      │        └──┬──────┘  └──┬──────┘  └──┬──────┘                                        │
   │      │           │ net1       │ net1       │ net1    (VLAN, macvlan sobre e2.<vlan>)       │
   │      │           │            │            │         ✗ Calico NO ve este tráfico          │
   │      │  Svc web ClusterIP 10.x.x.x:8080 → :80  (ingress-nginx no lo usa: va Pod→Pod)        │
   │      │                                                                                      │
   │ SSH  │   ② allow-admin-ssh-from-host  (podSelector app=admin)                               │
   └──────┼──► ingress.from: { ipBlock 10.10.20.2/32 }   ports: TCP 22                           │
   10.10.10.11:<nodePort>  (Svc admin NodePort 2222→22, externalTrafficPolicy: Local)            │
   r1 enruta sin NAT  →  el origen sigue siendo 10.10.20.2                                       │
          │        ┌──────────────┐                                                              │
          │        │ Pod admin    │  nodeSelector k8s-worker1                                    │
          │        │ ◄─cali :22   │  eth0 172.16.<w1>.z                                          │
          │        └──────┬───────┘                                                              │
          │               │ net1 ──────────────┐                                                 │
          └───────────────┼────────────────────┼─────────────────────────────────────────────────┘
                          ▼                    ▼
              ═════════ VLAN <id> en VlanNet (e2.<vlan> en los workers) ═════════
                     │                         │
               LXC bbdd (MySQL :3306)   LXC logs (rsyslog :514)
               no son Pods: aquí no hay NetworkPolicy
```

### 10.3 Qué hace cada política y por qué

**⓪ Denegación por defecto** (`podSelector: {}`, Ingress + Egress)
- Selecciona todos los Pods del namespace. En cuanto un Pod está seleccionado por alguna política en una dirección, solo pasa lo que esté permitido explícitamente en esa dirección.
- También bloquea la salida, DNS incluido. Las respuestas a conexiones entrantes permitidas sí salen, porque Calico sigue el estado de las conexiones (conntrack): una respuesta no necesita regla de egress.

**① Web ← solo ingress-nginx, TCP 80**
- El controller de ingress-nginx no pasa por el Service ClusterIP. Lee los endpoints del Service y abre una conexión **nueva** directamente a `<IP Pod web>:80`. Por eso:
  - el origen es la **IP de Calico del Pod del controller**, no la del cliente;
  - el puerto es el **puerto del Pod, 80**, no el 8080.
- `namespaceSelector` y `podSelector` van en la **misma** entrada de `from`, lo que significa AND. En dos entradas separadas significaría OR: entraría cualquier Pod de `ingress-nginx` y cualquier Pod con el label `ingress-nginx` de cualquier namespace.

**② Admin ← solo el host 10.10.20.2, TCP 22**
- Usa `ipBlock` porque el host no es un Pod y no hay label que seleccionar.
- Solo funciona si la IP de origen **sigue siendo 10.10.20.2** al llegar al Pod:
  - `r1` enruta entre `user_LAN` y la red del clúster sin NAT (§2).
  - Con `externalTrafficPolicy: Cluster` (el valor por defecto), kube-proxy en el worker haría SNAT a la IP del nodo para poder reenviar a cualquier nodo, y el `ipBlock` no coincidiría nunca.
  - `Local` desactiva ese SNAT. A cambio, el nodo solo reenvía a Pods que corren **en ese mismo nodo**. Por eso el Pod admin lleva `nodeSelector: k8s-worker1` y el SSH se hace a `10.10.10.11`. Enviado a `10.10.10.12`, la conexión se descarta.

### 10.4 VLAN / `net1`: aquí sí importa que las IPs sean distintas

- `net1` lo crea Multus a partir del NAD (macvlan sobre `e2.<vlan>`). Calico no le pone una veth `cali`, así que **ninguna NetworkPolicy aplica ahí**. El SSH admin → web por la VLAN y el acceso web → MySQL no se filtran, y la denegación por defecto no los rompe.
- La IP de esa interfaz la da el IPAM del NAD:
  - `static`: una IP fija por Pod. Sencillo para el único Pod admin, incómodo para 3 réplicas de un mismo Deployment.
  - `host-local`: un rango, pero **asignado por separado en cada worker**, así que S1 en worker1 y S2 en worker2 pueden recibir la misma IP. Es el problema de [D-005](../decisions.md) / [US-19](../historias/persona-a.md#us-19).
  - `whereabouts`: rango global del clúster sin duplicados. Se instala en cada arranque (§4).
  - Decisión ([D-005](../decisions.md)): `whereabouts` para los web y `static` para el admin. Las NAD son `vlan1000-web` y `vlan1000-admin` (US-11).
- Los LXC `bbdd` y `logs` tienen IPs estáticas en el XML de VNX (§9), en la misma subred y fuera del rango de los Pods.

### 10.5 Comandos para verlo en el clúster

```bash
kubectl get pods -n <ns> -o wide                         # IPs de Calico (eth0) y nodo de cada Pod
kubectl exec -n <ns> <pod-web> -- ip -4 addr             # eth0 (172.16.x) frente a net1 (VLAN)
ssh root@k8s-worker1 ip link | grep cali                 # las veth donde se aplican las políticas
kubectl get networkpolicy -n <ns> -o wide
```
