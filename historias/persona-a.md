# 🌐 Historias: Persona A · Red y VNX

⬅️ [Volver al plan](../plan.md) · Otras personas: [🖥️ B](persona-b.md) · [🔐 C](persona-c.md) · [🔖 Leyenda de emojis](../plan.md#leyenda)

**Área:** subinterfaces VLAN en los workers, Multus (`NetworkAttachmentDefinition`), escenario VNX, LXC de MariaDB y del servidor de logs.
**Carga:** 30 puntos · **Archivos:** `terraform/multus.tf`, `vnx/`, `scripts/setup-vlan-workers.sh`, `docs/datos-escenario.md`

## 🤝 Dependencias con el equipo

| | Qué | Con quién |
|---|---|---|
| 📥 Recibes | VLAN ID, subred e IPAM acordados ([US-03](persona-c.md#us-03), [D-005](../decisions.md)) | C |
| 📥 Recibes | Clave pública del **par 1** (admin → web/LXC) para el `filetree` ([US-16](persona-c.md#us-16)) | C |
| 📤 Entregas | Datos del entorno ([US-02](#us-02)) | B y C |
| 📤 Entregas | Plan de direccionamiento VLAN ([US-11](#us-11)) | B y C |
| 📤 Entregas | IP y credenciales de MariaDB ([US-20](#us-20)) | B y C |

## 📋 Orden de trabajo

| Fase | Historia | Pts | Marcas | Completed |
|---|---|---|---|---|
| 0 | [US-02 · Levantar el escenario y recopilar datos](#us-02) | 2 | | ✅ |
| 1 | [US-19 · Investigación: Multus, tipo de NAD e IPAM](#us-19) | 3 | ⛔ | ⬜ |
| 1 | [US-10 · Subinterfaces VLAN en los workers](#us-10) | 3 | | ⬜ |
| 1 | [US-11 · NetworkAttachmentDefinition](#us-11) | 3 | ⛔ 🤝 | ⬜ |
| 1 | [US-12 · Escenario VNX con LXC](#us-12) | 5 | | ⬜ |
| 2 | [US-20 · MariaDB en el LXC `bbdd`](#us-20) | 5 | 🤝 🔀 | ⬜ |
| 2 | [US-21 · Servidor de logs](#us-21) | 3 | | ⬜ |
| 3 | [US-33 · Validar el tráfico de la VLAN con las políticas](#us-33) | 3 | 🔀 | ⬜ |
| 4 | [US-41 · Despliegue de cero, de punta a punta](#us-41) | 3 | 🔀 🏁 | ⬜ |

---

## 🏗️ Fase 0: Preparación

<a id="us-02"></a>
### 🏗️ US-02 · Levantar el escenario de lab y recopilar datos · 2 pts
**Completed:** ✅ · **Depende de:** —

**Cómo se levanta el entorno** (en el host del laboratorio). El entorno es **temporal y se crea de cero cada día de trabajo**; lo único que persiste es este repo:

```bash
/lab/cnvr/bin/get-k8s-calico                       # descarga el escenario en /mnt/tmp/k8s_lab-calico-v02
cd /mnt/tmp/k8s_lab-calico-v02
./bin/start-k8s-calico                             # crea el clúster, une los workers e intenta cargar MetalLB
sudo vnx -f k8s_lab-calico.xml -x config_metallb   # relanzar: a veces start-k8s-calico no deja el pool creado
kubectl get ipaddresspools -n metallb-system       # debe mostrar el pool 10.10.10.20-30
sudo vnx -f k8s_lab-terraform.xml --create         # VM LXC "terraform" (10.10.10.13)
sudo vnx -f k8s_lab-terraform.xml -x install-terraform
./bin/get-master-kubeconf                          # kubeconfig → ~/.kube/config del host
./bin/set-terraform-kubeconf                       # kubeconfig → VM terraform
```

⚠️ `/mnt/tmp` es temporal: el repo vive en `shared/terraform-k8s-trabajofinal/`, así que hagan `git push` seguido. En la VM `terraform` (`ssh terraform`) el repo está en `/shared/terraform-k8s-trabajofinal`, y ahí se corre `terraform`. Los archivos se editan desde el host.

**Lo que ya se comprobó (13/11/2026)** y hay que pasar a `docs/datos-escenario.md`:

| Dato | Valor |
|---|---|
| Kubernetes | v1.37.0, containerd 2.3.5, Ubuntu 24.04 en los 3 nodos |
| Nodos | `k8s-master` 10.10.10.10 · `k8s-worker1` 10.10.10.11 · `k8s-worker2` 10.10.10.12 |
| Host en `user_LAN` | **10.10.20.2** (ruta a 10.10.10.0/24 por `r1`, 10.10.20.1) |
| VM `terraform` | 10.10.10.13, Terraform v1.17.2 |
| Multus | **instalado** (thick, DaemonSet `kube-multus-ds` en los 3 nodos). El CRD `network-attachment-definitions.k8s.cni.cncf.io` existe |
| Plugins CNI en `/opt/cni/bin` | `macvlan`, `vlan`, `bridge`, `ipvlan`, `host-device`, `host-local`, `static`, `dhcp`… **No hay `whereabouts`** |
| Interfaces de los workers | Calico va por **`e1`** (`k8s_LAN`). La interfaz en `VlanNet` es **`e2`**, no `eth2` |
| IngressClass | `nginx` |
| Labels del Ingress Controller | `app.kubernetes.io/name=ingress-nginx`, `app.kubernetes.io/component=controller` (namespace `ingress-nginx`) |
| Service del Ingress Controller | `LoadBalancer`. En este despliegue: `80:30097/TCP` |
| MetalLB | pool previsto `10.10.10.20-10.10.10.30` |

⚠️ El 13/11/2026 **MetalLB quedó sin configurar** después de `start-k8s-calico`: no había `IPAddressPool` ni `L2Advertisement`, y el Ingress Controller se quedó con `EXTERNAL-IP <pending>`. Por eso el `config_metallb` se relanza en la secuencia de arriba. Si aun así falla, el Ingress responde por NodePort (`http://10.10.10.11:<nodePort>/`).

⚠️ Como todo se recrea cada día, cualquier cambio en los nodos (subinterfaces VLAN, escenario VNX de los LXC, claves en `keys/`) tiene que salir de un script o de Terraform **dentro del repo**, nunca de un paso manual. Las claves de `keys/` no van a Git y se **generan nuevas cada día** con `scripts/gen-keys.sh` ([US-16](persona-c.md#us-16)), antes del `terraform apply` y de crear los LXC (que reciben la clave pública por `filetree`).

⚠️ El `kubectl` del host es v1.29 y el servidor v1.37 (avisa del *version skew*). Para lo básico funciona; si algo falla raro, usar `ssh root@k8s-master kubectl …`.

🧪 `docs/datos-escenario.md` existe con la tabla de arriba y los otros dos pueden levantar el escenario siguiendo esos pasos. MetalLB asigna una IP al Ingress Controller.

---

## ⚙️ Fase 1: Componentes independientes

<a id="us-19"></a>
### 🌐 US-19 · Investigación: Multus, tipo de NAD e IPAM · 3 pts · ⛔
**Completed:** ⬜ · **Depende de:** [US-02](#us-02) · **Bloquea a:** [US-11](#us-11)

*Spike* de investigación para cuando empiece el trabajo de la VLAN. Se puede hacer en cuanto el entorno esté levantado: no necesita Terraform ni los LXC. El resultado son decisiones, no código de entrega.

📖 Punto de partida: [guía de Multus](../docs/guia-multus.md), con lo que hicimos en la práctica 1.3.

**Qué investigar:**
1. **Cómo se hizo en la práctica 1.3:** subinterfaz en el nodo, tipo de NAD, IPAM y anotación de los Pods. Es el punto de partida que pide el enunciado (§2.2 y §2.3).
2. **Tipo de plugin CNI** (todos están en `/opt/cni/bin`, ver [datos del escenario](../docs/datos-escenario.md#4-multus-y-red-vlan)):
   - `macvlan` (modo `bridge`) con `master: e2.<vlan>`: encaja con el enunciado, que pide subinterfaces en los workers ([US-10](#us-10));
   - `vlan` con `master: e2` y `vlanId`: crea la subinterfaz por Pod y haría innecesaria US-10, pero se aparta del enunciado (si se elige, necesita entrada en `decisions.md`);
   - `bridge` o `ipvlan`, solo si `macvlan` da problemas.
3. **IPAM**, sabiendo que **`whereabouts` no está instalado** y que las 3 réplicas web comparten la misma plantilla de Pod:
   - `host-local`: cada worker reparte por su cuenta, así que da IPs duplicadas entre nodos;
   - `static` + anotación con `ips` (necesita `"capabilities": {"ips": true}` en la NAD): sirve para el admin, no para las réplicas;
   - `whereabouts`: IPAM para todo el clúster. Averiguar cómo instalarlo (DaemonSet + CRDs), si hay salida a Internet desde los nodos, y si se puede instalar de forma reproducible cada día;
   - `dhcp`: necesita el *daemon* `dhcp` del CNI en cada worker y un servidor DHCP (por ejemplo, `dnsmasq` en un LXC) en la VLAN;
   - dos NAD `host-local` con rangos distintos, una por worker, con afinidad de nodo: comprobar si es viable con un solo Deployment.
4. **Terraform:** cómo escribir la NAD con `kubernetes_manifest` en el provider 2.23.0 (el campo `spec.config` es un string JSON: usar `jsonencode()`), y qué pasa en el `plan` si el CRD no existe.
5. **Verificación:** la anotación `k8s.v1.cni.cncf.io/network-status` del Pod muestra las IPs de `net1`. Confirmar también que Calico **no** aplica NetworkPolicies a `net1` (lo comprueba [US-33](#us-33) más adelante).

**Prueba de concepto** con `kubectl apply` (no con Terraform), en un namespace de pruebas que luego se borra: subinterfaz temporal `e2.<vlan>` en los dos workers, una NAD y dos Pods de prueba (uno por worker, con `nodeSelector`).

**Entregables:**
- `docs/investigacion-multus.md` con lo aprendido, los YAML de la prueba de concepto y los comandos usados;
- [D-005](../decisions.md) pasa a *Accepted* con el IPAM elegido; si se elige un tipo de NAD distinto de `macvlan`, una entrada nueva;
- borrador del plan de direccionamiento para [US-11](#us-11).

🧪 En la prueba de concepto, los dos Pods reciben `net1` con IPs **distintas** de la VLAN y se hacen ping entre sí. D-005 está decidida y justificada. El namespace de pruebas está borrado.

<a id="us-10"></a>
### 🌐 US-10 · Subinterfaces VLAN en los workers · 3 pts
**Completed:** ⬜ · **Depende de:** [US-02](#us-02), [US-03](persona-c.md#us-03)

Script `scripts/setup-vlan-workers.sh` que, en `k8s-worker1` y `k8s-worker2` (por SSH como `root`), cree la subinterfaz VLAN sobre **`e2`**, siguiendo la práctica 1.3 (enunciado §2.2):

```bash
ip link add link e2 name e2.<vlan> type vlan id <vlan>
ip link set e2.<vlan> up
```

⚠️ Los workers se recrean en cada `start-k8s-calico` (sistema de ficheros *copy-on-write*), así que la subinterfaz se pierde. El script tiene que correrse después de cada arranque. Opcional: lanzarlo desde Terraform con `null_resource` + `remote-exec`, o añadirlo como `<exec>` en una copia del XML, para que el despliegue sea 100 % automático.

🧪 `ip -d link show e2.<vlan>` en los dos workers muestra el VLAN ID correcto y estado UP. El script es idempotente (se puede correr dos veces sin error).

<a id="us-11"></a>
### 🌐 US-11 · NetworkAttachmentDefinition (Multus) · 3 pts · ⛔ 🤝
**Completed:** ⬜ · **Depende de:** [US-10](#us-10), [US-19](#us-19) · **Bloquea a:** [US-22](persona-b.md#us-22), [US-24](persona-c.md#us-24)

Pasar a Terraform lo que salió de la investigación de [US-19](#us-19). En `multus.tf`, crear la NAD con `kubernetes_manifest` (`apiVersion: k8s.cni.cncf.io/v1`), con el tipo de plugin y el IPAM de [D-005](../decisions.md) (en principio `macvlan` modo `bridge` con `master: e2.<vlan>`), en el namespace del proyecto. Si el IPAM elegido necesita algo instalado en los nodos (por ejemplo, `whereabouts`), automatizarlo para que se repita cada día.

🤝 Definir y documentar el **plan de direccionamiento** de la VLAN (rango de los web, IP fija del admin, IP de `bbdd`, IP de `logs`) y **compartirlo con B y C** en cuanto esté.

⚠️ `kubernetes_manifest` necesita que el CRD exista en el `plan`. En este entorno ya existe; si algún día falla, revisar que el DaemonSet de Multus esté `Running`.

🧪 `kubectl get network-attachment-definitions -n <ns>` muestra la NAD. Dos Pods de prueba, uno en cada worker, reciben `net1` con IPs **distintas** de la VLAN y hacen ping entre sí.

<a id="us-12"></a>
### 🌐 US-12 · Escenario VNX con LXC de BBDD y logs · 5 pts
**Completed:** ⬜ · **Depende de:** [US-02](#us-02), [US-03](persona-c.md#us-03)

Copiar `../../k8s_lab-vms-vlan.xml` (práctica 1.3) a `vnx/` y dejar dos contenedores LXC (`bbdd` y `logs`) conectados a `VlanNet` con el `<vlan><tag id="<vlan>"/></vlan>` acordado y las IPs del plan de direccionamiento de [US-11](#us-11) (enunciado §2.6). Quitar las VMs de ejemplo (`vmA2`, `vmB2`, `vlan-router`) que no hagan falta.

⚠️ En ese XML `VlanNet` tiene `managed="no"`: la red la crea el escenario de Kubernetes, así que hay que arrancar el clúster **antes** que este escenario. Usar un `scenario_name` y una red `vm_mgmt` que no choquen con `k8s_lab-kubeadm` ni con `k8s_lab-terraform`.

🧪 `sudo vnx -f vnx/<escenario>.xml --create` levanta los dos LXC. Desde un worker (por `e2.<vlan>`, con una IP temporal) se puede hacer ping a los dos.

🚩 Con esto, tu parte de [H1](../plan.md#hitos) está lista.

---

## 🔀 Fase 2: Integración por la VLAN

<a id="us-20"></a>
### 🌐 US-20 · MariaDB en el LXC `bbdd` · 5 pts · 🤝 🔀
**Completed:** ⬜ · **Depende de:** [US-12](#us-12), [US-16](persona-c.md#us-16) · **Bloquea a:** [US-23](persona-b.md#us-23), [US-24](persona-c.md#us-24)

En el XML de VNX (enunciado §2.6):
- `<exec>` que instale `mariadb-server` y `openssh-server` y los habilite;
- `<filetree>` que copie la config de MariaDB (`bind-address` = IP de la VLAN, o `0.0.0.0`), un script SQL que cree una base de datos de prueba y un usuario con acceso desde la subred de la VLAN (`'usuario'@'<subred>.%'`), y el `authorized_keys` con la **clave pública del par 1** que te pasa C en [US-16](persona-c.md#us-16).

🤝 Pasar a B y C la IP, el usuario, la contraseña y el nombre de la BBDD (por un canal privado, no en Git).

🧪 Desde un worker o un Pod en la VLAN, `mysql -h <ip-bbdd> -u <usuario> -p` conecta. Desde el admin, `ssh root@<ip-bbdd>` entra con la clave del par 1 y sin contraseña.

<a id="us-21"></a>
### 🌐 US-21 · Servidor de logs en el LXC `logs` · 3 pts
**Completed:** ⬜ · **Depende de:** [US-12](#us-12), [US-16](persona-c.md#us-16)

Instalar SSH con el mismo `authorized_keys` (par 1) y el servicio de logs de [D-006](../decisions.md) (rsyslog escuchando en 514 UDP/TCP).

🧪 El admin puede entrar por SSH. `logger -n <ip-logs> prueba` desde un Pod deja la línea en el LXC.

🚩 Con esto, tu parte de [H2](../plan.md#hitos) está lista.

---

## 🛡️ Fase 3: NetworkPolicies

<a id="us-33"></a>
### 🛡️ US-33 · Validar que el tráfico de la VLAN sigue funcionando · 3 pts · 🔀
**Completed:** ⬜ · **Depende de:** [US-30](persona-c.md#us-30), [US-24](persona-c.md#us-24)

⚠️ Calico aplica las NetworkPolicies solo a la interfaz que gestiona (`eth0` del Pod), no a las interfaces Multus (`net1`). Comprobarlo:
- si el SSH y MariaDB por la VLAN siguen funcionando con default-deny, documentarlo como hallazgo en la memoria;
- si no funcionan, agregar las reglas de egress/ingress necesarias con `ip_block` de la subred VLAN (coordinar con C, porque es su `netpol.tf`).

⚠️ Revisar también el **DNS**: el egress denegado rompe la resolución de nombres. Si algo depende de DNS, agregar egress a `kube-dns` (UDP/TCP 53).

🧪 Todas las pruebas de la Fase 2 pasan con las políticas activas, y el comportamiento queda explicado en [decisions.md](../decisions.md).

🚩 Cierra el hito [H3](../plan.md#hitos).

---

## 🔵 Fase 4: Verificación y entrega

<a id="us-41"></a>
### 🔵 US-41 · Despliegue de cero, de punta a punta · 3 pts · 🔀 🏁
**Completed:** ⬜ · **Depende de:** [US-40](persona-b.md#us-40)

Documentar y probar el orden completo en el README:
1. Escenario k8s y VM `terraform` (los comandos de [US-02](#us-02)), y comprobar que MetalLB tiene pool.
2. `scripts/setup-vlan-workers.sh`.
3. `sudo vnx -f vnx/<escenario>.xml --create`.
4. Claves SSH en `keys/` ([US-16](persona-c.md#us-16)).
5. `terraform init && terraform apply`, dentro de la VM `terraform`.
6. `scripts/verify.sh`.

Probarlo en la cuenta de **otra persona del equipo**, sin estado previo.

🧪 Otro integrante despliega todo siguiendo solo el README. `terraform destroy`, `vnx --destroy` y `bin/stop-k8s-calico` dejan el entorno limpio.

🏁 Lo que salga de aquí es lo que se entrega. Después sigue la demo ([US-43](../plan.md#us-43)).
