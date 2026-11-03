# 🔐 Historias: Persona C · Seguridad y administración

⬅️ [Volver al plan](../plan.md) · Otras personas: [🌐 A](persona-a.md) · [🖥️ B](persona-b.md) · [🔖 Leyenda de emojis](../plan.md#leyenda)

**Área:** repositorio, dudas con el profesor, claves SSH y Secrets, Pod admin, Service NodePort, NetworkPolicies, memoria final.
**Carga:** 30 puntos · **Archivos:** `.gitignore`, `terraform/ssh.tf`, `admin.tf`, `netpol.tf`, `docs/`, `README.md`

## 🤝 Dependencias con el equipo

| | Qué | Con quién |
|---|---|---|
| 📥 Recibes | Esqueleto de Terraform ([HU-01](persona-b.md#hu-01)) | B |
| 📥 Recibes | Plan de direccionamiento VLAN y NAD ([HU-11](persona-a.md#hu-11)) | A |
| 📥 Recibes | Label `app = web` de los Pods web ([HU-14](persona-b.md#hu-14)) | B |
| 📥 Recibes | IP de los LXC con SSH listo ([HU-20](persona-a.md#hu-20)) | A |
| 📤 Entregas | Repo creado ([HU-00](#hu-00)) y respuestas del profesor ([HU-03](#hu-03)) | A y B |
| 📤 Entregas | Clave pública para el `filetree` de los LXC ([HU-16](#hu-16)) | A |
| 📤 Entregas | Montaje del Secret SSH en `web.tf` ([HU-17](#hu-17)) | B |
| 📤 Entregas | Política default-deny ([HU-30](#hu-30)) | A y B |

## 📋 Orden de trabajo

| Fase | Historia | Pts | Marcas |
|---|---|---|---|
| 0 | [HU-00 · Repositorio y convenciones](#hu-00) | 2 | ⛔ |
| 0 | [HU-03 · Resolver dudas con el profesor](#hu-03) | 1 | ⛔ |
| 1 | [HU-16 · Claves SSH y Secrets](#hu-16) | 3 | 🤝 |
| 1 | [HU-17 · Pod de administración](#hu-17) | 5 | 🔀 |
| 1 | [HU-18 · Service NodePort del admin](#hu-18) | 3 | |
| 2 | [HU-24 · SSH desde el admin por la VLAN](#hu-24) | 5 | 🔀 |
| 3 | [HU-30 · Política de denegación por defecto](#hu-30) | 3 | ⛔ |
| 3 | [HU-32 · SSH al admin solo desde la IP del host](#hu-32) | 5 | ⚠️ |
| 4 | [HU-42 · Memoria y documentación](#hu-42) | 3 | 📝 🏁 |

---

## 🏗️ Fase 0: Preparación

<a id="hu-00"></a>
### 🏗️ HU-00 · Repositorio y convenciones · 2 pts · ⛔
**Depende de:** — · **Bloquea a:** [HU-01](persona-b.md#hu-01) y todo lo demás

Crear el repositorio Git (todavía no existe), la [estructura de carpetas del plan](../plan.md#estructura), el `.gitignore` y la convención de ramas y commits (una rama por historia: `hu-14-deployment-web`).

🧪 Los tres pueden clonar el repo y hacer push. `.gitignore` excluye el estado, las claves y los tfvars.

<a id="hu-03"></a>
### 🏗️ HU-03 · Resolver dudas con el profesor · 1 pt · ⛔
**Depende de:** — · **Bloquea a:** [HU-10](persona-a.md#hu-10), [HU-12](persona-a.md#hu-12), [HU-15](persona-b.md#hu-15), [HU-16](#hu-16)

Llevar las [preguntas del plan](../plan.md#dudas) y registrar las respuestas en `docs/decisiones.md`.

🧪 Las 6 dudas tienen una respuesta o una decisión del equipo por escrito.

🚩 Con esto y [HU-01](persona-b.md#hu-01) y [HU-02](persona-a.md#hu-02) se cierra el hito [H0](../plan.md#hitos).

---

## ⚙️ Fase 1: Componentes independientes

<a id="hu-16"></a>
### 🔑 HU-16 · Claves SSH y Secrets · 3 pts · 🤝
**Depende de:** [HU-01](persona-b.md#hu-01), [HU-03](#hu-03) · **Bloquea a:** [HU-20](persona-a.md#hu-20), [HU-21](persona-a.md#hu-21)

En `ssh.tf`, generar el par de claves con el provider `hashicorp/tls` (`tls_private_key`, ED25519 o RSA 4096) o con `ssh-keygen` fuera de Terraform en `keys/`, que está ignorada por Git. Crear los `kubernetes_secret` para lo siguiente, según la decisión de [HU-03](#hu-03):
- la clave privada, en el Pod que inicia las conexiones SSH;
- la clave pública como `authorized_keys`, en los Pods que reciben conexiones;
- 🤝 además, exportar la clave pública a `vnx/filetree/.../authorized_keys` para los LXC (con `local_file` o a mano), y **avisar a A**.

⚠️ Si usan `tls_private_key`, la clave privada queda en el `tfstate`. Mencionarlo en la memoria.

🧪 Los Secrets existen. La clave pública queda disponible en el filetree de VNX. Ninguna clave aparece en Git.

<a id="hu-17"></a>
### 🔑 HU-17 · Pod de administración · 5 pts · 🔀
**Depende de:** [HU-16](#hu-16)

En `admin.tf`, crear el Pod (o un Deployment de 1 réplica) con la imagen admin, `node_selector = { "kubernetes.io/hostname" = "k8s-worker1" }` y label `app = admin`. Montar los Secrets de SSH con permisos correctos (`default_mode = "0600"` en la clave privada, y `~/.ssh` con `0700`).

⚠️ Si `sshd` exige permisos que el volumen no puede dar, copiar las claves con un initContainer.

🔀 En los Pods web, montar el Secret correspondiente. Esto toca `web.tf` de B, así que háganlo en un PR que **revise B**.

🧪 El Pod corre en `k8s-worker1`. Dentro del Pod, `ls -l ~/.ssh` muestra las claves con los permisos correctos y `sshd` está activo.

<a id="hu-18"></a>
### 🔑 HU-18 · Service NodePort del admin · 3 pts
**Depende de:** [HU-17](#hu-17)

`kubernetes_service` de tipo `NodePort`, `port = 2222`, `target_port = 22`, `external_traffic_policy = "Local"`. Fijar `node_port` (por ejemplo, 30022) o sacarlo como `output`.

🧪 Desde el host, `ssh -p <nodePort> <usuario>@<ip-k8s-worker1>` conecta con clave (todavía sin NetworkPolicy).

🚩 Con esto, tu parte de [H1](../plan.md#hitos) está lista.

---

## 🔀 Fase 2: Integración por la VLAN

<a id="hu-24"></a>
### 🔑 HU-24 · SSH desde el admin por la VLAN · 5 pts · 🔀
**Depende de:** [HU-11](persona-a.md#hu-11), [HU-17](#hu-17), [HU-20](persona-a.md#hu-20), [HU-22](persona-b.md#hu-22)

Agregar la interfaz Multus al admin (IP fija). Probar SSH desde el admin a los 3 Pods web y a los 2 LXC usando las IPs de la VLAN. Documentar las IPs en un `~/.ssh/config` del admin, cargado desde un ConfigMap (opcional, se ve bien en la demo).

🔀 Esta es la prueba donde se junta el trabajo de los tres. Háganla juntos.

🧪 `ssh <ip-vlan-web>`, `ssh <ip-bbdd>` y `ssh <ip-logs>` desde el admin entran sin contraseña.

🚩 Con esto (y [HU-23](persona-b.md#hu-23)) se cierra el hito [H2](../plan.md#hitos).

---

## 🛡️ Fase 3: NetworkPolicies

<a id="hu-30"></a>
### 🛡️ HU-30 · Política de denegación por defecto · 3 pts · ⛔
**Depende de:** Fase 2 completa ([H2](../plan.md#hitos)) · **Bloquea a:** [HU-31](persona-b.md#hu-31), [HU-32](#hu-32), [HU-33](persona-a.md#hu-33)

En `netpol.tf`, crear `kubernetes_network_policy` con `pod_selector {}` (o los Pods que pida el enunciado) y `policy_types = ["Ingress", "Egress"]`, sin reglas.

⚠️ Avisen al equipo antes de aplicarla: va a "romper" el Ingress y el SSH hasta que estén [HU-31](persona-b.md#hu-31) y [HU-32](#hu-32). Ver también el tema del DNS en [HU-33](persona-a.md#hu-33).

🧪 Después de aplicarla, el Ingress deja de responder y el SSH al admin por NodePort falla (esto es lo esperado).

<a id="hu-32"></a>
### 🛡️ HU-32 · SSH al admin solo desde la IP del host · 5 pts · ⚠️
**Depende de:** [HU-30](#hu-30), [HU-18](#hu-18)

Regla de ingress en `app = admin` con `ip_block { cidr = "<ip_host_user_lan>/32" }` en el puerto 22/TCP.

⚠️ Comprobar que `externalTrafficPolicy: Local` preserva la IP de origen: en el admin, `ss -tn` o los logs de `sshd` deben mostrar la IP del host y no la del nodo. Si sale la IP del nodo, la política bloquea al host.

🧪 El SSH desde el host autorizado funciona. Desde otra máquina u otra IP (por ejemplo, desde un worker o desde otro Pod) se rechaza. Usar `worker2:nodePort` también falla, porque el Pod no está en ese nodo.

---

## ✅ Fase 4: Verificación y entrega

<a id="hu-42"></a>
### 📝 HU-42 · Memoria y documentación · 3 pts · 🏁
**Depende de:** [HU-41](persona-a.md#hu-41) (se va llenando desde la Fase 1) · **Bloquea a:** [HU-43](../plan.md#hu-43)

README y memoria con:
- arquitectura (diagrama),
- decisiones de diseño (initContainer vs sidecar, IPAM, claves, Multus vs Calico),
- explicación de cada recurso de Terraform,
- capturas de cada criterio de aceptación,
- problemas encontrados y cómo se resolvieron.

Cada responsable escribe la sección de su área y C la integra y le da formato.

🧪 El documento cubre los apartados 2 a 5 del enunciado, punto por punto.

🏁 Después sigue la demo ([HU-43](../plan.md#hu-43)).
