# 🧭 Guía: Deployment web y ConfigMap (de la práctica 1.3 al Trabajo Final)

⬅️ [Volver al plan](../../../plan.md) · Historias: [US-13](../../../historias/persona-b.md#us-13) (ConfigMap) · [US-14](../../../historias/persona-b.md#us-14) (Deployment) · [US-15](../../../historias/persona-b.md#us-15) (Service e Ingress) · Relacionado: [guía MetalLB e Ingress](../metallb/guia-metallb.md)

Lo que hicimos con el Deployment de nginx en la **práctica 1.3, §4–5**, y cómo se convierte en el Deployment web del Trabajo Final (enunciado §3).

📁 **Ficheros originales de P1.3** en [`p13/`](p13/), copiados de `examples/` del escenario `k8s_lab-flannel-v02`:
[`deployment.yml`](p13/deployment.yml) · [`deployment-volumes.yml`](p13/deployment-volumes.yml) · [`deployment-configmap.yml`](p13/deployment-configmap.yml) · [`index.html`](p13/index.html). El Service (`service.yml`) está en [`../metallb/p13/`](../metallb/p13/service.yml).

> **Leyenda.** `⟪PENDIENTE: …⟫` = dato por comprobar. Lista en la [§6](#6-pendientes).

---

## 1. Las tres versiones del Deployment en P1.3

Las tres comparten lo mismo: `nginx-deployment`, **3 réplicas**, label `app: nginx` (la que usa el `selector` del Service) e imagen `nginx` en el puerto 80. Cambia de dónde sale la página:

| Fichero | De dónde sale `index.html` | Problema |
|---|---|---|
| [`deployment.yml`](p13/deployment.yml) | la página por defecto de la imagen | No se personaliza |
| [`deployment-volumes.yml`](p13/deployment-volumes.yml) | volumen `hostPath` `/shared/html` del **nodo** (la carpeta `shared/` del host, montada en todos los nodos) | Depende del sistema de ficheros del nodo; no es portable ni se gestiona desde Kubernetes |
| [`deployment-configmap.yml`](p13/deployment-configmap.yml) | **ConfigMap** montado como volumen en `/usr/share/nginx/html` | Las 3 réplicas sirven **la misma** página |

La versión con ConfigMap es la base del Trabajo Final:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-configmap
data:
  group: X
  index.html: |
    <!DOCTYPE html>
    <html>
    <head>
      <title>NGINX server</title>
    </head>
    <body>
      <h1>Hello from Kubernetes!</h1>
      <p>This page is served by NGINX using a ConfigMap.</p>
      <p>Web server of CNVR/ARSN group X</p>
    </body>
    </html>
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  labels:
    app: nginx
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx
        envFrom:
        - configMapRef:
            name: nginx-configmap      # cada clave del ConfigMap → variable de entorno (group=X)
        ports:
        - containerPort: 80
        volumeMounts:
        - name: web-content
          mountPath: /usr/share/nginx/html
      volumes:
      - name: web-content
        configMap:
          name: nginx-configmap        # cada clave → un fichero (index.html, group)
```

Dos formas de consumir el mismo ConfigMap, las dos útiles:
- **como volumen**: cada clave pasa a ser un fichero (`/usr/share/nginx/html/index.html`, y también un fichero `group`);
- **como variables de entorno** (`envFrom`): cada clave pasa a ser una variable (`$group`).

---

## 2. Qué cambia en el Trabajo Final

El enunciado (§3) pide que **cada réplica muestre el nombre de su Pod**. Montar el ConfigMap directamente (como en P1.3) no basta: el volumen es de solo lectura y es igual para todas las réplicas. Hace falta un paso intermedio:

```
ConfigMap (plantilla con __POD_NAME__)          Downward API: metadata.name → $POD_NAME
          │ volumen de solo lectura                              │
          ▼                                                      ▼
   initContainer ── sed "s/__POD_NAME__/$POD_NAME/" ──► emptyDir (escribible)
                                                                 │
                                                                 ▼
                                                    contenedor web: sirve index.html
```

| | Práctica 1.3 | Trabajo Final |
|---|---|---|
| Imagen | `nginx` | `dgsgiros/nginx-ssh:latest` (nginx + `sshd`, usuario `webuser`) |
| Réplicas | 3 | 3 (`var.num_replicas`) |
| Label | `app: nginx` | `app = web` (lo usan el Service y las NetworkPolicies) |
| Página | ConfigMap montado directamente | ConfigMap como **plantilla** → initContainer → `emptyDir` ([D-003](../../../decisions.md)) |
| Nombre del Pod | — | Downward API (`metadata.name`) |
| Grupo | `group: X` a mano | `var.group_number` (2) con `templatefile()` |
| Raíz de nginx | `/usr/share/nginx/html` | `⟪PENDIENTE: comprobar en dgsgiros/nginx-ssh⟫` |
| Service | `nginx-service` NodePort 30001, 8080→80 | ClusterIP 8080→80 ([US-15](../../../historias/persona-b.md#us-15)) |
| Cómo se crea | `kubectl apply -f` | Terraform (`kubernetes_config_map_v1`, `kubernetes_deployment_v1`) |

---

## 3. Plantillas para el Trabajo Final

### 3.1 Plantilla HTML (`terraform/templates/index.html.tpl`)

Basada en [`index.html`](p13/index.html). `${group}` lo rellena Terraform; `__POD_NAME__` lo rellena el initContainer en cada Pod:

```html
<!DOCTYPE html>
<html>
<head>
  <title>CNVR/ARSN G${group}</title>
</head>
<body>
  <h1>Hello from Kubernetes!</h1>
  <p>Web server of CNVR/ARSN group ${group}</p>
  <p>Served by Pod: <b>__POD_NAME__</b></p>
</body>
</html>
```

### 3.2 ConfigMap ([US-13](../../../historias/persona-b.md#us-13))

```hcl
resource "kubernetes_config_map_v1" "web_template" {
  metadata {
    name      = "web-template"
    namespace = var.namespace
  }
  data = {
    "index.html" = templatefile("${path.module}/templates/index.html.tpl", {
      group = var.group_number
    })
  }
}
```

### 3.3 Deployment ([US-14](../../../historias/persona-b.md#us-14))

```hcl
resource "kubernetes_deployment_v1" "web" {
  metadata {
    name      = "web"
    namespace = var.namespace
    labels    = { app = "web" }
  }
  spec {
    replicas = var.num_replicas
    selector {
      match_labels = { app = "web" }
    }
    template {
      metadata {
        labels = { app = "web" }
        # annotations Multus: ver ../multus/guia-multus.md §4.3
      }
      spec {
        init_container {
          name    = "render-index"
          image   = var.image_web           # ya trae sed; evita descargar busybox
          command = ["sh", "-c", "sed \"s/__POD_NAME__/$POD_NAME/g\" /template/index.html > /html/index.html"]
          env {
            name = "POD_NAME"
            value_from {
              field_ref { field_path = "metadata.name" }
            }
          }
          volume_mount {
            name       = "template"
            mount_path = "/template"
            read_only  = true
          }
          volume_mount {
            name       = "html"
            mount_path = "/html"
          }
        }
        container {
          name  = "web"
          image = var.image_web               # no sobrescribir command: arranca nginx y sshd
          port { container_port = 80 }
          volume_mount {
            name       = "html"
            mount_path = "⟪PENDIENTE: raíz de nginx en la imagen⟫"
          }
        }
        volume {
          name = "template"
          config_map { name = kubernetes_config_map_v1.web_template.metadata[0].name }
        }
        volume {
          name = "html"
          empty_dir {}
        }
      }
    }
  }
}
```

Usar `kubernetes_config_map_v1.web_template.metadata[0].name` (y no el nombre escrito a mano) hace que Terraform cree el ConfigMap **antes** que el Deployment.

### 3.4 Comprobación

```bash
kubectl get pods -n <ns> -l app=web -o wide                          # 3 Pods Running
for p in $(kubectl get pods -n <ns> -l app=web -o name); do
  kubectl exec -n <ns> $p -c web -- curl -s localhost | grep Pod      # cada uno con su nombre
done
kubectl describe pod -n <ns> <pod> | grep -A3 "template:"           # ConfigMap montado read-only
```

---

## 4. Lo que **no** reutilizamos

- **`hostPath`** ([`deployment-volumes.yml`](p13/deployment-volumes.yml)): ata la página al disco del nodo; en el Trabajo Final todo sale de Terraform.
- **Montar el ConfigMap en la raíz de nginx**: oculta cualquier otro fichero de ese directorio y no permite personalizar por Pod.
- **`envFrom` para el grupo**: funciona, pero con `templatefile()` el número de grupo queda ya escrito en la plantilla y no hace falta pasarlo al contenedor.

---

## 5. Errores que ya conocemos

| Síntoma | Causa probable |
|---|---|
| Página por defecto de nginx en vez de la nuestra | El `emptyDir` no está montado en la raíz real de nginx de la imagen |
| 403 Forbidden | El `emptyDir` está vacío: el initContainer falló o escribió en otra ruta (`kubectl logs <pod> -c render-index`) |
| `__POD_NAME__` aparece literal | Falta la variable `POD_NAME` en el initContainer, o el `sed` usa comillas simples (no expande `$POD_NAME`) |
| El initContainer no puede escribir | El volumen de destino es el del ConfigMap (solo lectura) en vez del `emptyDir` |
| Las 3 réplicas muestran el mismo nombre | Se generó la página fuera del Pod (por ejemplo, en Terraform) en vez de en el initContainer |

---

## 6. Pendientes

- [ ] Raíz que sirve nginx en `dgsgiros/nginx-ssh:latest`: `kubectl run tmp --rm -it --restart=Never --image=dgsgiros/nginx-ssh:latest --command -- sh -c 'grep -r "root" /etc/nginx/'` ([§2](#2-qué-cambia-en-el-trabajo-final)).
- [ ] Comprobar que la imagen tiene `sh` y `sed` para usarla también en el initContainer; si no, usar `busybox`.
