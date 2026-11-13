# 🔐 Historias: Persona C · Seguridad y administración

⬅️ [Volver al plan](../plan.md) · Otras personas: [🌐 A](persona-a.md) · [🖥️ B](persona-b.md) · [🔖 Leyenda de emojis](../plan.md#leyenda)

**Área:** repositorio, dudas pendientes, claves SSH y Secrets, Pod admin, Service NodePort, NetworkPolicies, memoria final.
**Carga:** 30 puntos · **Archivos:** `.gitignore`, `scripts/gen-keys.sh`, `terraform/ssh.tf`, `admin.tf`, `netpol.tf`, `docs/`, `README.md`

## 🤝 Dependencias con el equipo

| | Qué | Con quién |
|---|---|---|
| 📥 Recibes | Esqueleto de Terraform ([US-01](persona-b.md#us-01)) | B |
| 📥 Recibes | Plan de direccionamiento VLAN y NAD ([US-11](persona-a.md#us-11)) | A |
| 📥 Recibes | Label `app = web` de los Pods web ([US-14](persona-b.md#us-14)) | B |
| 📥 Recibes | IP de los LXC con SSH listo ([US-20](persona-a.md#us-20)) | A |
| 📤 Entregas | Repo y convenciones ([US-00](#us-00)), dudas cerradas ([US-03](#us-03)) | A y B |
| 📤 Entregas | Clave pública del **par 1** para el `filetree` de los LXC ([US-16](#us-16)) | A |
| 📤 Entregas | Montaje del Secret del par 1 en `web.tf` ([US-17](#us-17)) | B |
| 📤 Entregas | Política default-deny ([US-30](#us-30)) | A y B |

## 📋 Orden de trabajo

| Fase | Historia | Pts | Marcas | Completed |
|---|---|---|---|---|
| 0 | [US-00 · Repositorio y convenciones](#us-00) | 2 | ⛔ | ✅ |
| 0 | [US-03 · Cerrar las dudas pendientes](#us-03) | 1 | ⛔ | ⬜ |
| 1 | [US-16 · Claves SSH y Secrets](#us-16) | 3 | 🤝 | ⬜ |
| 1 | [US-17 · Pod de administración](#us-17) | 5 | 🔀 | ⬜ |
| 1 | [US-18 · Service NodePort del admin](#us-18) | 3 | | ⬜ |
| 2 | [US-24 · SSH desde el admin por la VLAN](#us-24) | 5 | 🔀 | ⬜ |
| 3 | [US-30 · Política de denegación por defecto](#us-30) | 3 | ⛔ | ⬜ |
| 3 | [US-32 · SSH al admin solo desde la IP del host](#us-32) | 5 | ⚠️ | ⬜ |
| 4 | [US-42 · Memoria y documentación](#us-42) | 3 | 📝 🏁 | ⬜ |

---

## 🏗️ Fase 0: Preparación

<a id="us-00"></a>
### 🏗️ US-00 · Repositorio y convenciones · 2 pts · ⛔
**Completed:** ✅ · **Depende de:** — · **Bloquea a:** [US-01](persona-b.md#us-01) y todo lo demás

El repositorio ya existe (`shared/terraform-k8s-trabajofinal/`), con la estructura de carpetas y [docs/convenciones.md](../docs/convenciones.md). Falta:
- ⚠️ **`.gitignore`:** las líneas de `keys/`, `id_rsa*`, `id_ed25519*`, `*.pem`, `*.key` y `.env` están **comentadas**. Descomentarlas antes de generar claves en [US-16](#us-16). Revisar también `*.tfvars` (dejar pasar solo `terraform.tfvars.example`) y la línea del PDF, que ignora el nombre viejo `arsn-trabajo-final-26-27.pdf` pero no el nuevo `ARSN-trabajo-final-26-27.pdf`;
- borrar los `test.txt` de relleno y decidir qué se hace con `temp-terraform-examples/` (referencia de P1.4, no se entrega) y `scripts/create-keypairs.sh` (es el de OpenStack de P1.4, no sirve aquí);
- que los tres tengan acceso de push.

🧪 Los tres pueden clonar el repo y hacer push. `git check-ignore keys/x terraform/terraform.tfstate` confirma que ambos se ignoran.

<a id="us-03"></a>
### 🏗️ US-03 · Cerrar las dudas pendientes · 1 pt · ⛔
**Completed:** ⬜ · **Depende de:** — · **Bloquea a:** [US-10](persona-a.md#us-10), [US-12](persona-a.md#us-12)

La versión del enunciado del **5 de noviembre de 2026** ya resuelve la dirección de las claves y las imágenes, y el resto se cerró con el entorno ([D-001](../decisions.md), [US-02](persona-a.md#us-02)). Ver el estado en [plan.md § Dudas](../plan.md#dudas). Quedan abiertas:
- **VLAN ID y subred** de la red compartida;
- **IPAM** de la VLAN ([D-005](../decisions.md));
- **función del servidor de logs** ([D-006](../decisions.md), propuesta: rsyslog en 514).

Decidirlas en equipo (o con el profesor si hace falta) y registrarlas en [decisions.md](../decisions.md).

🧪 Todas las dudas de [plan.md](../plan.md#dudas) tienen una respuesta o una decisión con su entrada en `decisions.md`.

🚩 Con esto y [US-01](persona-b.md#us-01) y [US-02](persona-a.md#us-02) se cierra el hito [H0](../plan.md#hitos).

---

## ⚙️ Fase 1: Componentes independientes

<a id="us-16"></a>
### 🔑 US-16 · Claves SSH y Secrets · 3 pts · 🤝
**Completed:** ⬜ · **Depende de:** [US-00](#us-00), [US-01](persona-b.md#us-01) · **Bloquea a:** [US-17](#us-17), [US-20](persona-a.md#us-20), [US-21](persona-a.md#us-21)

Según el enunciado §2.5 y [D-004](../decisions.md), **dos pares de claves independientes**, generados en el host con `ssh-keygen` por un script `scripts/gen-keys.sh` en `keys/` (ignorada por Git). Como el entorno se recrea a diario, las claves se **generan nuevas cada día**: el script debe ser no interactivo (`-N ""`), sobrescribir sin preguntar y correr antes de `terraform apply` y de crear los LXC:

| Par | Uso | Clave privada | Clave pública |
|---|---|---|---|
| **1** | admin → web y LXC | Secret en el Pod admin | Secret en los Pods web (`authorized_keys`) y `filetree` de los LXC |
| **2** | host → admin | **se queda en el host** | Secret en el Pod admin (`authorized_keys`) |

En `ssh.tf`, crear con `kubernetes_secret_v1` y `file("${var.ssh_keys_dir}/…")` (**no** con `kubectl create secret`) tres Secrets:
- `ssh-admin-private`: clave privada del par 1 (para el admin);
- `ssh-admin-authorized`: clave pública del par 2 (para el admin). El enunciado recomienda un Secret **independiente** por cada clave del admin;
- `ssh-web-authorized`: clave pública del par 1, **un solo Secret** para los 3 Pods web.

🤝 Copiar la clave pública del par 1 a `vnx/filetree/.../authorized_keys` para los LXC (con `local_file` o desde `gen-keys.sh`) y **avisar a A**.

⚠️ El contenido de los Secrets queda en el `tfstate` aunque las claves se generen fuera de Terraform. El estado nunca va a Git; mencionarlo en la memoria.

🧪 `kubectl get secrets -n <ns>` muestra los tres Secrets. La clave pública del par 1 está en el filetree de VNX. Ninguna clave aparece en `git status`.

<a id="us-17"></a>
### 🔑 US-17 · Pod de administración · 5 pts · 🔀
**Completed:** ⬜ · **Depende de:** [US-16](#us-16)

En `admin.tf`, crear el Pod (o un Deployment de 1 réplica) con **`dgsgiros/admin-ssh:latest`** (usuario `adminuser`, GID 1000, con `sudo`), `node_selector = { "kubernetes.io/hostname" = "k8s-worker1" }` (enunciado §5.3) y label `app = admin`.

Permisos, según el ejemplo del enunciado §2.5:
- `security_context { fs_group = 1000 }` en el Pod, para que los volúmenes de Secret queden con grupo 1000;
- clave privada con `default_mode`/`mode = "0440"`. **No usar `0600`:** el fichero es de `root`, así que con `0600` `adminuser` no lo puede leer. Con `0440` y `fsGroup` lo lee por grupo, y `ssh` no se queja porque el fichero no es suyo;
- dos Secrets no se pueden montar en el mismo directorio: montar cada fichero con `sub_path` (`~/.ssh/id_rsa` y `~/.ssh/authorized_keys`) o usar un volumen `projected` que junte ambos.

⚠️ Si `sshd` rechaza el `authorized_keys` por `StrictModes` (dueño o permisos del directorio), copiar las claves con un initContainer a un `empty_dir` y ajustar dueño y permisos ahí.

🔀 En los Pods web, montar `ssh-web-authorized` como `/home/webuser/.ssh/authorized_keys`. Esto toca `web.tf` de B, así que háganlo en un PR que **revise B**.

🧪 El Pod corre en `k8s-worker1`. Como `adminuser`, `cat ~/.ssh/id_rsa` funciona, `ls -l ~/.ssh` muestra los permisos esperados y `sshd` está activo.

<a id="us-18"></a>
### 🔑 US-18 · Service NodePort del admin · 3 pts
**Completed:** ⬜ · **Depende de:** [US-17](#us-17)

`kubernetes_service_v1` de tipo `NodePort`, `port = 2222`, `target_port = 22`, `external_traffic_policy = "Local"` (enunciado §4.2 y §5.3). Fijar `node_port` (por ejemplo, 30022) o sacarlo como `output`.

🧪 Desde el host, `ssh -i keys/<par2> -p <nodePort> adminuser@10.10.10.11` conecta con clave (todavía sin NetworkPolicy).

🚩 Con esto, tu parte de [H1](../plan.md#hitos) está lista.

---

## 🔀 Fase 2: Integración por la VLAN

<a id="us-24"></a>
### 🔑 US-24 · SSH desde el admin por la VLAN · 5 pts · 🔀
**Completed:** ⬜ · **Depende de:** [US-11](persona-a.md#us-11), [US-17](#us-17), [US-20](persona-a.md#us-20), [US-22](persona-b.md#us-22)

Agregar la interfaz Multus al admin (IP fija, IPAM `static`). Probar SSH con la clave del par 1 desde el admin a los 3 Pods web (`webuser@<ip-vlan-web>`) y a los 2 LXC, usando las IPs de la VLAN (enunciado §2.4 y §2.7). Opcional: un `~/.ssh/config` del admin con las IPs, cargado desde un ConfigMap (se ve bien en la demo).

🔀 Esta es la prueba donde se junta el trabajo de los tres. Háganla juntos.

🧪 `ssh webuser@<ip-vlan-web>`, `ssh root@<ip-bbdd>` y `ssh root@<ip-logs>` desde el admin entran sin contraseña.

🚩 Con esto (y [US-23](persona-b.md#us-23)) se cierra el hito [H2](../plan.md#hitos).

---

## 🛡️ Fase 3: NetworkPolicies

<a id="us-30"></a>
### 🛡️ US-30 · Política de denegación por defecto · 3 pts · ⛔
**Completed:** ⬜ · **Depende de:** Fase 2 completa ([H2](../plan.md#hitos)) · **Bloquea a:** [US-31](persona-b.md#us-31), [US-32](#us-32), [US-33](persona-a.md#us-33)

En `netpol.tf`, crear `kubernetes_network_policy_v1` en el namespace del proyecto con `pod_selector {}` y `policy_types = ["Ingress", "Egress"]`, sin reglas (enunciado §5.1).

⚠️ Avisen al equipo antes de aplicarla: va a "romper" el Ingress y el SSH hasta que estén [US-31](persona-b.md#us-31) y [US-32](#us-32). Ver también el DNS y el `apt` en [US-33](persona-a.md#us-33) y [D-007](../decisions.md).

🧪 Después de aplicarla, el Ingress deja de responder y el SSH al admin por NodePort falla (esto es lo esperado).

<a id="us-32"></a>
### 🛡️ US-32 · SSH al admin solo desde la IP del host · 5 pts · ⚠️
**Completed:** ⬜ · **Depende de:** [US-30](#us-30), [US-18](#us-18)

Regla de ingress en `app = admin` con `ip_block { cidr = "${var.host_user_lan_ip}/32" }` (= `10.10.20.2/32`) en el puerto 22/TCP (enunciado §5.3).

⚠️ Comprobar que `externalTrafficPolicy: Local` preserva la IP de origen: en el admin, `ss -tn` o los logs de `sshd` deben mostrar `10.10.20.2` y no la IP de un nodo. `r1` enruta sin NAT, así que debería llegar la IP real del host.

🧪 El SSH desde el host funciona. Desde otra IP (por ejemplo, desde un worker o desde otro Pod) se rechaza. Usar `10.10.10.12:<nodePort>` (worker2) también falla, porque el Pod no está en ese nodo.

---

## 🔵 Fase 4: Verificación y entrega

<a id="us-42"></a>
### 📝 US-42 · Memoria y documentación · 3 pts · 🏁
**Completed:** ⬜ · **Depende de:** [US-41](persona-a.md#us-41) (se va llenando desde la Fase 1) · **Bloquea a:** [US-43](../plan.md#us-43)

README y memoria con:
- arquitectura (diagrama),
- decisiones de diseño, tomadas de [decisions.md](../decisions.md) (initContainer vs sidecar, IPAM, claves, Multus vs Calico),
- explicación de cada recurso de Terraform,
- capturas de cada criterio de aceptación,
- problemas encontrados y cómo se resolvieron.

Cada responsable escribe la sección de su área y C la integra y le da formato.

🧪 El documento cubre los apartados 2 a 5 del enunciado (versión del 5/11/2026), punto por punto.

🏁 Después sigue la demo ([US-43](../plan.md#us-43)).
