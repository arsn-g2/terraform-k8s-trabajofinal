# 🌐 Historias: Persona A · Red y VNX

⬅️ [Volver al plan](../plan.md) · Otras personas: [🖥️ B](persona-b.md) · [🔐 C](persona-c.md) · [🔖 Leyenda de emojis](../plan.md#leyenda)

**Área:** subinterfaces VLAN en los workers, Multus (`NetworkAttachmentDefinition`), escenario VNX, LXC de MariaDB y del servidor de logs.
**Carga:** 29 puntos · **Archivos:** `terraform/multus.tf`, `vnx/`, `scripts/setup-vlan-workers.sh`

## 🤝 Dependencias con el equipo

| | Qué | Con quién |
|---|---|---|
| 📥 Recibes | Respuestas sobre VLAN ID, subred y servidor de logs ([HU-03](persona-c.md#hu-03)) | C |
| 📥 Recibes | Clave pública SSH para el `filetree` ([HU-16](persona-c.md#hu-16)) | C |
| 📤 Entregas | Plan de direccionamiento VLAN ([HU-11](#hu-11)) | B y C |
| 📤 Entregas | IP y credenciales de MariaDB ([HU-20](#hu-20)) | B y C |

## 📋 Orden de trabajo

| Fase | Historia | Pts | Marcas |
|---|---|---|---|
| 0 | [HU-02 · Levantar el escenario y recopilar datos](#hu-02) | 2 | |
| 1 | [HU-10 · Subinterfaces VLAN en los workers](#hu-10) | 3 | |
| 1 | [HU-11 · NetworkAttachmentDefinition](#hu-11) | 5 | ⛔ 🤝 |
| 1 | [HU-12 · Escenario VNX con LXC](#hu-12) | 5 | |
| 2 | [HU-20 · MariaDB en el LXC `bbdd`](#hu-20) | 5 | 🤝 🔀 |
| 2 | [HU-21 · Servidor de logs](#hu-21) | 3 | |
| 3 | [HU-33 · Validar el tráfico de la VLAN con las políticas](#hu-33) | 3 | 🔀 |
| 4 | [HU-41 · Despliegue de cero, de punta a punta](#hu-41) | 3 | 🔀 🏁 |

---

## 🏗️ Fase 0: Preparación

<a id="hu-02"></a>
### 🏗️ HU-02 · Levantar el escenario de lab y recopilar datos · 2 pts
**Depende de:** —

Arrancar el escenario de Kubernetes de la práctica 1.4 y documentar en `docs/datos-escenario.md` lo siguiente:
- las IPs de los nodos y del host en `user_LAN`;
- si Multus está instalado (`kubectl get pods -n kube-system | grep multus`) y qué plugins CNI hay en los workers (`/opt/cni/bin`: `macvlan`, `host-local`, `whereabouts`...);
- las labels de los Pods del Ingress Controller (`kubectl get pods -n ingress-nginx --show-labels`), que necesita B en [HU-31](persona-b.md#hu-31);
- el nombre del IngressClass (`kubectl get ingressclass`), que necesita B en [HU-15](persona-b.md#hu-15).

⚠️ Si Multus no está instalado, avisar al profesor **ese mismo día**: bloquea medio proyecto.

🧪 El documento existe y los otros dos pueden levantar el escenario siguiendo esos pasos.

---

## ⚙️ Fase 1: Componentes independientes

<a id="hu-10"></a>
### 🌐 HU-10 · Subinterfaces VLAN en los workers · 3 pts
**Depende de:** [HU-02](#hu-02), [HU-03](persona-c.md#hu-03)

Script `scripts/setup-vlan-workers.sh` que, en `k8s-worker1` y `k8s-worker2`, cree la subinterfaz VLAN sobre la interfaz conectada a `VlanNet` (por ejemplo, `ip link add link ethX name ethX.<vlan> type vlan id <vlan>` y `ip link set ethX.<vlan> up`), siguiendo la práctica 1.3. Opcional: lanzarlo desde Terraform con `null_resource` y `remote-exec` para que el despliegue sea 100 % automático.

🧪 `ip -d link show` en los dos workers muestra la subinterfaz con el VLAN ID correcto y en estado UP. El script es idempotente (se puede correr dos veces sin error).

<a id="hu-11"></a>
### 🌐 HU-11 · NetworkAttachmentDefinition (Multus) · 5 pts · ⛔ 🤝
**Depende de:** [HU-10](#hu-10) · **Bloquea a:** [HU-22](persona-b.md#hu-22), [HU-24](persona-c.md#hu-24)

En `multus.tf`, crear la NAD con `kubernetes_manifest` (`apiVersion: k8s.cni.cncf.io/v1`). Tipo `macvlan` (o `vlan`/`bridge`, según la práctica 1.3) sobre la subinterfaz. IPAM:
- **Opción recomendada:** IPs estáticas o `host-local` con rangos que no se pisen entre workers.
- **Alternativa:** `whereabouts`, si está instalado.

🤝 Definir y documentar el **plan de direccionamiento** de la VLAN (rango para los Pods web, IP fija del admin, IP de MariaDB, IP de logs) y **compartirlo con B y C** en cuanto esté.

⚠️ `kubernetes_manifest` necesita que el CRD exista en el `plan`. Si Multus no está instalado, el plan falla.

🧪 `kubectl get network-attachment-definitions -n <ns>` muestra la NAD. Un Pod de prueba con la anotación `k8s.v1.cni.cncf.io/networks` recibe una interfaz `net1` con IP de la VLAN.

<a id="hu-12"></a>
### 🌐 HU-12 · Escenario VNX con LXC de BBDD y logs · 5 pts
**Depende de:** [HU-02](#hu-02), [HU-03](persona-c.md#hu-03)

Partir de `k8s_lab-vms-vlan.xml` y dejar dos contenedores LXC (`bbdd` y `logs`) conectados a `VlanNet` en la VLAN acordada, con las IPs del plan de direccionamiento de [HU-11](#hu-11).

🧪 `vnx -f vnx/k8s_lab-vms-vlan.xml --create` levanta los dos LXC. Desde un worker (por la subinterfaz VLAN, con una IP temporal) se puede hacer ping a los dos.

🚩 Con esto, tu parte de [H1](../plan.md#hitos) está lista.

---

## 🔀 Fase 2: Integración por la VLAN

<a id="hu-20"></a>
### 🌐 HU-20 · MariaDB en el LXC `bbdd` · 5 pts · 🤝 🔀
**Depende de:** [HU-12](#hu-12), [HU-16](persona-c.md#hu-16) · **Bloquea a:** [HU-23](persona-b.md#hu-23), [HU-24](persona-c.md#hu-24)

En el XML de VNX:
- `<exec>` que instale `mariadb-server` y `openssh-server` y los habilite;
- `<filetree>` que copie la config de MariaDB (`bind-address` = IP de la VLAN, o `0.0.0.0`), un script SQL que cree una base de datos de prueba y un usuario con acceso desde la subred de la VLAN (`'usuario'@'10.100.0.%'`), y el `authorized_keys` que te pasa C en [HU-16](persona-c.md#hu-16).

🤝 Pasar a B y C la IP, el usuario, la contraseña y el nombre de la BBDD (por un canal privado, no en Git).

🧪 Desde un worker o un Pod en la VLAN, `mysql -h <ip-bbdd> -u <usuario> -p` conecta. `ssh root@<ip-bbdd>` entra con clave y sin contraseña.

<a id="hu-21"></a>
### 🌐 HU-21 · Servidor de logs en el LXC `logs` · 3 pts
**Depende de:** [HU-12](#hu-12), [HU-16](persona-c.md#hu-16)

Instalar SSH con `authorized_keys`, y el servicio de logs acordado en [HU-03](persona-c.md#hu-03) (por ejemplo, rsyslog escuchando en 514).

🧪 El admin puede entrar por SSH. Si hay rsyslog, `logger -n <ip-logs> prueba` desde un Pod deja la línea en el LXC.

🚩 Con esto, tu parte de [H2](../plan.md#hitos) está lista.

---

## 🛡️ Fase 3: NetworkPolicies

<a id="hu-33"></a>
### 🛡️ HU-33 · Validar que el tráfico de la VLAN sigue funcionando · 3 pts · 🔀
**Depende de:** [HU-30](persona-c.md#hu-30), [HU-24](persona-c.md#hu-24)

⚠️ Calico aplica las NetworkPolicies solo a la interfaz que gestiona (`eth0`), no a las interfaces Multus (`net1`). Comprobarlo:
- si el SSH y MariaDB por la VLAN siguen funcionando con default-deny, documentarlo como hallazgo en la memoria;
- si no funcionan, agregar las reglas de egress/ingress necesarias con `ip_block` de la subred VLAN (coordinar con C, porque es su `netpol.tf`).

⚠️ Revisar también el **DNS**: el egress denegado rompe la resolución de nombres. Si algo depende de DNS, agregar egress a `kube-dns` (UDP/TCP 53).

🧪 Todas las pruebas de la Fase 2 pasan con las políticas activas, y el comportamiento queda explicado en `docs/decisiones.md`.

🚩 Cierra el hito [H3](../plan.md#hitos).

---

## ✅ Fase 4: Verificación y entrega

<a id="hu-41"></a>
### ✅ HU-41 · Despliegue de cero, de punta a punta · 3 pts · 🔀 🏁
**Depende de:** [HU-40](persona-b.md#hu-40)

Documentar y probar el orden completo en el README:
1. Escenario k8s.
2. `setup-vlan-workers.sh`.
3. `vnx --create`.
4. `terraform apply`.
5. `verify.sh`.

Probarlo en la computadora de **otra persona del equipo**, sin estado previo.

🧪 Otro integrante despliega todo siguiendo solo el README. `terraform destroy` y `vnx --destroy` dejan el entorno limpio.

🏁 Lo que salga de aquí es lo que se entrega. Después sigue la demo ([HU-43](../plan.md#hu-43)).
