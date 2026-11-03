# 🖥️ Historias: Persona B · Aplicación web

⬅️ [Volver al plan](../plan.md) · Otras personas: [🌐 A](persona-a.md) · [🔐 C](persona-c.md) · [🔖 Leyenda de emojis](../plan.md#leyenda)

**Área:** esqueleto de Terraform, ConfigMap, Deployment de Nginx con la página personalizada, Service ClusterIP, Ingress, script de verificación.
**Carga:** 29 puntos · **Archivos:** `terraform/providers.tf`, `variables.tf`, `outputs.tf`, `namespace.tf`, `web.tf`, `scripts/verify.sh`

## 🤝 Dependencias con el equipo

| | Qué | Con quién |
|---|---|---|
| 📥 Recibes | Labels del Ingress Controller y nombre del IngressClass ([HU-02](persona-a.md#hu-02)) | A |
| 📥 Recibes | Número de grupo e imágenes ([HU-03](persona-c.md#hu-03)) | C |
| 📥 Recibes | Plan de direccionamiento VLAN y NAD ([HU-11](persona-a.md#hu-11)) | A |
| 📥 Recibes | Montaje del Secret SSH en `web.tf` ([HU-17](persona-c.md#hu-17)) | C |
| 📥 Recibes | IP y credenciales de MariaDB ([HU-20](persona-a.md#hu-20)) | A |
| 📤 Entregas | Esqueleto de Terraform, que todos usan ([HU-01](#hu-01)) | A y C |
| 📤 Entregas | Label `app = web` de los Pods ([HU-14](#hu-14)) | C |

## 📋 Orden de trabajo

| Fase | Historia | Pts | Marcas |
|---|---|---|---|
| 0 | [HU-01 · Esqueleto de Terraform](#hu-01) | 3 | ⛔ |
| 1 | [HU-13 · ConfigMap con la plantilla HTML](#hu-13) | 2 | |
| 1 | [HU-14 · Deployment web con página personalizada](#hu-14) | 5 | 🤝 |
| 1 | [HU-15 · Service ClusterIP e Ingress](#hu-15) | 3 | ⚠️ |
| 2 | [HU-22 · Interfaz Multus en los Pods web](#hu-22) | 3 | 🔀 |
| 2 | [HU-23 · Acceso a MariaDB desde los web y el admin](#hu-23) | 3 | 🔀 |
| 3 | [HU-31 · Acceso a los web solo desde el Ingress Controller](#hu-31) | 5 | |
| 4 | [HU-40 · Script de verificación automática](#hu-40) | 5 | ✅ |

---

## 🏗️ Fase 0: Preparación

<a id="hu-01"></a>
### 🏗️ HU-01 · Esqueleto de Terraform · 3 pts · ⛔
**Depende de:** [HU-00](persona-c.md#hu-00) · **Bloquea a:** todas las historias de Terraform

`providers.tf` con `hashicorp/kubernetes` (versión fijada, `config_path = "~/.kube/config"`), `variables.tf` con todas las variables previstas (`grupo`, `namespace`, `imagen_web`, `imagen_admin`, `vlan_id`, `vlan_subred`, `ip_host_user_lan`, `ip_worker1`, etc.), `terraform.tfvars.example` y un `namespace.tf` propio para el proyecto.

🧪 `terraform init`, `terraform validate` y `terraform apply` crean el namespace sin errores. `terraform fmt -check` pasa.

🚩 Es parte del hito [H0](../plan.md#hitos).

---

## ⚙️ Fase 1: Componentes independientes

<a id="hu-13"></a>
### 🖥️ HU-13 · ConfigMap con la plantilla HTML · 2 pts
**Depende de:** [HU-01](#hu-01)

En `web.tf`, crear `kubernetes_config_map` con un `index.html` que tenga un marcador (por ejemplo, `__POD_NAME__`). Puede incluir el número de grupo y la fecha. Guardar la plantilla en `terraform/templates/index.html.tpl` y cargarla con `file()` o `templatefile()`.

🧪 `kubectl get cm -o yaml` muestra la plantilla con el marcador.

<a id="hu-14"></a>
### 🖥️ HU-14 · Deployment web con página personalizada · 5 pts · 🤝
**Depende de:** [HU-13](#hu-13)

`kubernetes_deployment` con 3 réplicas, usando la imagen dada por el profesor. **Opción B (initContainer)** recomendada, porque es más simple que un sidecar:
- `env POD_NAME` vía Downward API (`field_ref { field_path = "metadata.name" }`);
- el initContainer (por ejemplo, `busybox`) ejecuta `sed "s/__POD_NAME__/$POD_NAME/g" /plantilla/index.html > /html/index.html`;
- volúmenes: ConfigMap (`read_only = true`) en el initContainer y `empty_dir` compartido en el initContainer y en el contenedor de Nginx (en `/usr/share/nginx/html` o la ruta que use la imagen);
- 🤝 labels claras (por ejemplo, `app = web`), porque las usan el Service y las NetworkPolicies de C. Avísale cuáles quedaron.

🧪 3 Pods `Running`. `kubectl exec <pod> -- curl -s localhost` devuelve el HTML con **el nombre de ese Pod**. El ConfigMap está montado como solo lectura.

<a id="hu-15"></a>
### 🖥️ HU-15 · Service ClusterIP e Ingress · 3 pts · ⚠️
**Depende de:** [HU-14](#hu-14), [HU-03](persona-c.md#hu-03)

- `kubernetes_service` de tipo `ClusterIP`, `port = 8080`, `target_port = 80`, con selector `app = web`.
- `kubernetes_ingress_v1` con el `ingress_class_name` de [HU-02](persona-a.md#hu-02) y ruta `/servers-G<X>` hacia el Service en el puerto 8080.

⚠️ Agregar la anotación `nginx.ingress.kubernetes.io/rewrite-target: /`. Sin ella, Nginx recibe `/servers-GX` y responde 404.

🧪 `curl http://<ip-ingress>/servers-GX` muestra la página. Al repetirlo, va cambiando el nombre del Pod (balanceo entre los 3).

🚩 Con esto, tu parte de [H1](../plan.md#hitos) está lista.

---

## 🔀 Fase 2: Integración por la VLAN

<a id="hu-22"></a>
### 🌐 HU-22 · Interfaz Multus en los Pods web · 3 pts · 🔀
**Depende de:** [HU-11](persona-a.md#hu-11), [HU-14](#hu-14)

Agregar la anotación `k8s.v1.cni.cncf.io/networks` al template del Deployment, con IPs del rango que define A en [HU-11](persona-a.md#hu-11).

🔀 Aquí se juntan tu Deployment y la NAD de A. Pruébenlo juntos.

🧪 Los 3 Pods tienen `net1` con IP de la VLAN y hacen ping a `bbdd`, `logs` y al admin.

<a id="hu-23"></a>
### 🖥️ HU-23 · Acceso a MariaDB desde los web y el admin · 3 pts · 🔀
**Depende de:** [HU-20](persona-a.md#hu-20), [HU-22](#hu-22)

Verificar que las imágenes traen el cliente de MariaDB. Si no lo traen, documentar cómo instalarlo o usar un contenedor extra. Guardar las credenciales de la BBDD en un `kubernetes_secret` y exponerlas como variables de entorno.

⚠️ Sin credenciales en texto plano en el `.tf`: usar una variable `sensitive`.

🧪 Desde un Pod web y desde el admin, `mysql -h <ip-bbdd> -e "SHOW DATABASES;"` funciona.

🚩 Con esto (y [HU-24](persona-c.md#hu-24)) se cierra el hito [H2](../plan.md#hitos).

---

## 🛡️ Fase 3: NetworkPolicies

<a id="hu-31"></a>
### 🛡️ HU-31 · Acceso a los web solo desde el Ingress Controller · 5 pts
**Depende de:** [HU-30](persona-c.md#hu-30), [HU-15](#hu-15)

Regla de ingress en los Pods `app = web` con un solo bloque `from`, que contenga `namespace_selector` (`kubernetes.io/metadata.name = ingress-nginx`) **y** `pod_selector` (labels del controller de [HU-02](persona-a.md#hu-02)) juntos, en el puerto 80/TCP.

⚠️ Si se ponen como dos elementos separados de `from`, la regla es un **OR** y deja pasar de más. Tienen que ir en el mismo elemento para que sea un **AND**.

🧪 `curl /servers-GX` vuelve a funcionar. `curl` directo al ClusterIP o a la IP de un Pod web desde otro Pod (por ejemplo, el admin, por la interfaz de Calico) **falla**.

---

## ✅ Fase 4: Verificación y entrega

<a id="hu-40"></a>
### ✅ HU-40 · Script de verificación automática · 5 pts
**Depende de:** Fase 3 completa ([H3](../plan.md#hitos)) · **Bloquea a:** [HU-41](persona-a.md#hu-41)

`scripts/verify.sh`, que imprime OK/FALLO por cada prueba:
1. Hay 3 Pods web `Running` y el admin está en `k8s-worker1`.
2. Cada Pod tiene `net1` con IP de la VLAN.
3. Ping por la VLAN entre los web, el admin, `bbdd` y `logs`.
4. SSH sin contraseña del admin hacia los web y los LXC (`ssh -o BatchMode=yes`).
5. `mysql` desde un web y desde el admin.
6. `curl /servers-GX`, repetido N veces, muestra ≥ 2 nombres de Pod distintos.
7. Las pruebas negativas de las NetworkPolicies ([HU-31](#hu-31) y [HU-32](persona-c.md#hu-32)) fallan como se espera.

🧪 El script corre en limpio después de un despliegue de cero y todo sale OK.

🏁 Después sigue la demo ([HU-43](../plan.md#hu-43)).
