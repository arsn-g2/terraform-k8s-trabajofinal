# 🖥️ Historias: Persona B · Aplicación web

⬅️ [Volver al plan](../plan.md) · Otras personas: [🌐 A](persona-a.md) · [🔐 C](persona-c.md) · [🔖 Leyenda de emojis](../plan.md#leyenda)

**Área:** esqueleto de Terraform, ConfigMap, Deployment de Nginx con la página personalizada, Service ClusterIP, Ingress, script de verificación.
**Carga:** 29 puntos · **Archivos:** `terraform/providers.tf`, `variables.tf`, `outputs.tf`, `namespace.tf`, `web.tf`, `scripts/verify.sh`

## 🤝 Dependencias con el equipo

| | Qué | Con quién |
|---|---|---|
| 📥 Recibes | Datos del entorno: IngressClass, labels del Ingress Controller, IPs ([US-02](persona-a.md#us-02)) | A |
| 📥 Recibes | Plan de direccionamiento VLAN y NAD ([US-11](persona-a.md#us-11)) | A |
| 📥 Recibes | Secret con la clave pública del par 1 y su montaje en `web.tf` ([US-16](persona-c.md#us-16), [US-17](persona-c.md#us-17)) | C |
| 📥 Recibes | IP y credenciales de MariaDB ([US-20](persona-a.md#us-20)) | A |
| 📤 Entregas | Esqueleto de Terraform, que todos usan ([US-01](#us-01)) | A y C |
| 📤 Entregas | Label `app = web` de los Pods ([US-14](#us-14)) | C |

Ya no hace falta esperar a nadie para el número de grupo ni las imágenes: el grupo es **2** ([D-001](../decisions.md)) y las imágenes vienen en el enunciado (§2.1).

## 📋 Orden de trabajo

| Fase | Historia | Pts | Marcas | Completed |
|---|---|---|---|---|
| 0 | [US-01 · Esqueleto de Terraform](#us-01) | 3 | ⛔ | ✅ |
| 1 | [US-13 · ConfigMap con la plantilla HTML](#us-13) | 2 | | ⬜ |
| 1 | [US-14 · Deployment web con página personalizada](#us-14) | 5 | 🤝 | ⬜ |
| 1 | [US-15 · Service ClusterIP e Ingress](#us-15) | 3 | ⚠️ | ⬜ |
| 2 | [US-22 · Interfaz Multus en los Pods web](#us-22) | 3 | 🔀 | ⬜ |
| 2 | [US-23 · Acceso a MariaDB desde los web y el admin](#us-23) | 3 | 🔀 | ⬜ |
| 3 | [US-31 · Acceso a los web solo desde el Ingress Controller](#us-31) | 5 | | ⬜ |
| 4 | [US-40 · Script de verificación automática](#us-40) | 5 | 🔵 | ⬜ |

---

## 🏗️ Fase 0: Preparación

<a id="us-01"></a>
### 🏗️ US-01 · Esqueleto de Terraform · 3 pts · ⛔
**Completed:** ✅ · **Depende de:** [US-00](persona-c.md#us-00) · **Bloquea a:** todas las historias de Terraform

En `terraform/`:
- `providers.tf` con `hashicorp/kubernetes` fijado a `2.23.0` (igual que en P1.4, ver `temp-terraform-examples/terraform-k8s-example/k8s-provider.tf`) y `config_path = "~/.kube/config"`. Usar recursos `_v1` (`kubernetes_deployment_v1`, `kubernetes_service_v1`, `kubernetes_secret_v1`…);
- `variables.tf` con las variables previstas y sus valores por defecto conocidos: `group_number = 2`, `namespace`, `image_web = "dgsgiros/nginx-ssh:latest"`, `image_admin = "dgsgiros/admin-ssh:latest"`, `host_user_lan_ip = "10.10.20.2"`, `worker1_ip = "10.10.10.11"`, `vlan_id`, `vlan_subnet`, `ssh_keys_dir = "../keys"`;
- `terraform.tfvars.example` y `namespace.tf` ([D-002](../decisions.md)).

⚠️ `terraform` se corre **dentro de la VM `terraform`** (`ssh terraform`, luego `cd /shared/terraform-k8s-trabajofinal/terraform`), que ya tiene el kubeconfig gracias a `bin/set-terraform-kubeconf`. Los archivos se editan desde el host.

🧪 `terraform init`, `terraform validate` y `terraform apply` crean el namespace sin errores. `terraform fmt -check` pasa.

🚩 Es parte del hito [H0](../plan.md#hitos).

---

## ⚙️ Fase 1: Componentes independientes

<a id="us-13"></a>
### 🖥️ US-13 · ConfigMap con la plantilla HTML · 2 pts
**Completed:** ⬜ · **Depende de:** [US-01](#us-01)

📖 Punto de partida para US-13 y US-14: [guía del Deployment web](../docs/useful/web/guia-web.md), con lo que hicimos en la práctica 1.3 y plantillas de Terraform.

En `web.tf`, crear `kubernetes_config_map_v1` con un `index.html` que tenga un marcador (por ejemplo, `__POD_NAME__`) (enunciado §3.1). Puede incluir el número de grupo. Guardar la plantilla en `terraform/templates/index.html.tpl` y cargarla con `file()` o `templatefile()`.

🧪 `kubectl get cm -n <ns> -o yaml` muestra la plantilla con el marcador.

<a id="us-14"></a>
### 🖥️ US-14 · Deployment web con página personalizada · 5 pts · 🤝
**Completed:** ⬜ · **Depende de:** [US-13](#us-13)

`kubernetes_deployment_v1` con 3 réplicas de **`dgsgiros/nginx-ssh:latest`** (usuario `webuser`, GID 1000, con `sudo`). **Opción B (initContainer)**, según [D-003](../decisions.md):
- `env POD_NAME` vía Downward API (`field_ref { field_path = "metadata.name" }`);
- el initContainer ejecuta `sed "s/__POD_NAME__/$POD_NAME/g" /plantilla/index.html > /html/index.html`. Puede usar la misma imagen web (ya está descargada en los nodos) en vez de `busybox`;
- volúmenes (enunciado §3.3): ConfigMap (`read_only = true`) en el initContainer y `empty_dir` compartido en el initContainer y en el contenedor de Nginx, montado en la raíz que sirve la imagen (comprobarla con `kubectl exec <pod> -- grep -r root /etc/nginx/`);
- no sobrescribir el `command` del contenedor web: la imagen arranca Nginx **y** `sshd`;
- 🤝 labels claras (por ejemplo, `app = web`), porque las usan el Service y las NetworkPolicies de C. Avísale cuáles quedaron.

🧪 3 Pods `Running`. `kubectl exec <pod> -- curl -s localhost` devuelve el HTML con **el nombre de ese Pod**. El ConfigMap está montado como solo lectura.

<a id="us-15"></a>
### 🖥️ US-15 · Service ClusterIP e Ingress · 3 pts · ⚠️
**Completed:** ⬜ · **Depende de:** [US-14](#us-14)

- `kubernetes_service_v1` de tipo `ClusterIP`, `port = 8080`, `target_port = 80`, con selector `app = web` (enunciado §4.1).
- `kubernetes_ingress_v1` con `ingress_class_name = "nginx"` y ruta `"/servers-G${var.group_number}"` (= `/servers-G2`) hacia el Service en el puerto 8080 (enunciado §4.3).

⚠️ Agregar la anotación `nginx.ingress.kubernetes.io/rewrite-target: /`. Sin ella, Nginx recibe `/servers-G2` y responde 404.

⚠️ Para probarlo: por la IP que MetalLB da al Ingress Controller (`kubectl get svc -n ingress-nginx`) o, si sigue `<pending>` ([US-02](persona-a.md#us-02)), por su NodePort: `curl http://10.10.10.11:<nodePort>/servers-G2`.

🧪 `curl http://<ip-ingress>/servers-G2` muestra la página. Al repetirlo, va cambiando el nombre del Pod (balanceo entre los 3).

🚩 Con esto, tu parte de [H1](../plan.md#hitos) está lista.

---

## 🔀 Fase 2: Integración por la VLAN

<a id="us-22"></a>
### 🌐 US-22 · Interfaz Multus en los Pods web · 3 pts · 🔀
**Completed:** ⬜ · **Depende de:** [US-11](persona-a.md#us-11), [US-14](#us-14)

Agregar la anotación `k8s.v1.cni.cncf.io/networks` al template del Deployment, según el IPAM elegido por A en [US-11](persona-a.md#us-11) ([D-005](../decisions.md)).

🔀 Aquí se juntan tu Deployment y la NAD de A. Pruébenlo juntos.

🧪 Los 3 Pods tienen `net1` con IPs **distintas** de la VLAN (aunque estén en workers diferentes) y hacen ping a `bbdd`, `logs` y al admin.

<a id="us-23"></a>
### 🖥️ US-23 · Acceso a MariaDB desde los web y el admin · 3 pts · 🔀
**Completed:** ⬜ · **Depende de:** [US-20](persona-a.md#us-20), [US-22](#us-22)

Comprobar si las imágenes traen el cliente (`which mariadb mysql`). El enunciado confirma que `webuser`/`adminuser` pueden instalar paquetes con `sudo apt`, pero eso necesita salida a Internet, que el default-deny egress corta ([D-007](../decisions.md)). Decidir cómo queda instalado de forma reproducible (por ejemplo, en el arranque del contenedor antes de aplicar las políticas, o permitiendo egress solo para eso) y registrarlo en D-007.

Guardar las credenciales de la BBDD en un `kubernetes_secret_v1` y exponerlas como variables de entorno.

⚠️ Sin credenciales en texto plano en el `.tf`: usar una variable `sensitive`.

🧪 Desde un Pod web y desde el admin, `mysql -h <ip-bbdd> -e "SHOW DATABASES;"` funciona.

🚩 Con esto (y [US-24](persona-c.md#us-24)) se cierra el hito [H2](../plan.md#hitos).

---

## 🛡️ Fase 3: NetworkPolicies

<a id="us-31"></a>
### 🛡️ US-31 · Acceso a los web solo desde el Ingress Controller · 5 pts
**Completed:** ⬜ · **Depende de:** [US-30](persona-c.md#us-30), [US-15](#us-15)

Regla de ingress en los Pods `app = web` (enunciado §5.2) con un solo bloque `from`, que contenga juntos:
- `namespace_selector` con `kubernetes.io/metadata.name = ingress-nginx`;
- `pod_selector` con las labels del controller: `app.kubernetes.io/name = ingress-nginx` y `app.kubernetes.io/component = controller` ([US-02](persona-a.md#us-02));

en el puerto **80/TCP** (el puerto del Pod, no el 8080 del Service).

⚠️ Si se ponen como dos elementos separados de `from`, la regla es un **OR** y deja pasar de más. Tienen que ir en el mismo elemento para que sea un **AND**.

🧪 `curl /servers-G2` vuelve a funcionar. `curl` directo al ClusterIP o a la IP de un Pod web desde otro Pod (por ejemplo, el admin, por la interfaz de Calico) **falla**.

---

## 🔵 Fase 4: Verificación y entrega

<a id="us-40"></a>
### 🔵 US-40 · Script de verificación automática · 5 pts
**Completed:** ⬜ · **Depende de:** Fase 3 completa ([H3](../plan.md#hitos)) · **Bloquea a:** [US-41](persona-a.md#us-41)

`scripts/verify.sh`, que se corre en el host e imprime OK/FALLO por cada prueba (enunciado §2.7):
1. Hay 3 Pods web `Running` y el admin está en `k8s-worker1`.
2. Cada Pod tiene `net1` con IP de la VLAN.
3. Ping por la VLAN entre los web, el admin, `bbdd` y `logs`.
4. SSH sin contraseña desde el host al admin (par 2, `ssh -i keys/<par2> -p <nodePort> adminuser@10.10.10.11`), y del admin hacia los web y los LXC (par 1, `ssh -o BatchMode=yes`).
5. `mysql` desde un web y desde el admin.
6. `curl /servers-G2`, repetido N veces, muestra ≥ 2 nombres de Pod distintos.
7. Las pruebas negativas de las NetworkPolicies ([US-31](#us-31) y [US-32](persona-c.md#us-32)) fallan como se espera.

🧪 El script corre en limpio después de un despliegue de cero y todo sale OK.

🏁 Después sigue la demo ([US-43](../plan.md#us-43)).
