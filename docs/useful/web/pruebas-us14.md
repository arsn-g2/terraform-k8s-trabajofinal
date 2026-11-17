# 🧪 Pruebas de US-14 · Deployment web con página personalizada

⬅️ [Guía web](guia-web.md) · Historia: [US-14](../../../historias/persona-b.md#us-14) · Decisión: [D-009](../../../decisions.md) (sidecar)

Cómo comprobar, después de `terraform apply`, que el Deployment web cumple los 🧪 criterios de US-14. Cada paso dice **qué** mirar y **por qué**. Al final hay una tabla de problemas típicos y la checklist para el PR.

---

## 0. Preparación

Desde el **host** (o desde `ssh root@k8s-master` si el `kubectl` v1.29 del host falla por la diferencia de versión):

```bash
NS=g2-workshop                    # var.namespace (D-002), creado en namespace.tf
LBL='app=web'                     # local.web_labels; la usan el Service (US-15) y las NetworkPolicies de C (🤝)
WEB=nginx-server                  # nombre del contenedor de Nginx
SIDE=page-updater-sidecar         # nombre del contenedor sidecar
```

Antes de probar nada en el clúster, en la VM `terraform`:

```bash
terraform plan        # debe decir "No changes": lo desplegado coincide con el código
terraform state list | grep -E 'config_map|deployment'
```

> **Por qué:** si `plan` muestra cambios, estás probando algo distinto de lo que vas a subir al repo.

### 0.1 Todo está en el namespace correcto

```bash
kubectl get ns $NS                                       # STATUS Active
kubectl get all,cm -n $NS                                # ConfigMap, Deployments, Services y Pods
kubectl get all,cm -n default | grep -E 'nginx|admin'    # no debe devolver nada
```

> **Por qué:** un recurso sin `namespace` en su `metadata` acaba en `default`, y un Service solo selecciona Pods **de su propio namespace**. Todos los recursos usan `kubernetes_namespace_v1.namespace.metadata[0].name` (no `var.namespace`) para que Terraform cree el namespace antes que ellos y lo borre después.

---

## 1. Los 3 Pods están `Running`

```bash
kubectl get deploy,rs,pods -n $NS -l $LBL -o wide
kubectl rollout status deploy/nginx-deployment -n $NS
```

Qué esperar:
- Deployment `READY 3/3`, un solo ReplicaSet activo.
- 3 Pods `Running` con **`READY 2/2`**: con el sidecar (D-009) cada Pod tiene **dos** contenedores. `1/2` significa que uno de los dos no arranca o se reinicia.
- `RESTARTS 0`. Si el sidecar se reinicia, revisa que termine en `sleep infinity` (§5).
- Columna `NODE`: lo normal es que se repartan entre `k8s-worker1` y `k8s-worker2`. No es obligatorio, pero conviene saberlo para US-22 (IPAM `host-local` por nodo, D-005).

---

## 2. Labels (🤝 entrega a C)

```bash
kubectl get pods -n $NS --show-labels
kubectl get deploy nginx-deployment -n $NS -o jsonpath='{.spec.selector.matchLabels}{"\n"}'
```

> **Por qué:** el `selector` del Service (US-15) y las NetworkPolicies de C (US-31…) seleccionan los Pods **por esta label**. Si cambia después, sus recursos dejan de seleccionar nada sin dar error. Avisa a C de la label final.

---

## 3. ConfigMap: plantilla con el marcador

```bash
kubectl get cm nginx-web-config -n $NS -o yaml
```

Qué esperar:
- `data.index.html` con **`__POD_NAME__`** sin sustituir (lo sustituye el sidecar, no Terraform).
- `${group}` **ya** sustituido por `2` (eso sí lo hace `templatefile()` en el `plan`).

---

## 4. Volúmenes y montajes

```bash
kubectl describe pod -n $NS -l $LBL | sed -n '/Containers:/,/Conditions:/p'
kubectl get pod -n $NS -l $LBL -o jsonpath='{.items[0].spec.volumes}' | python3 -m json.tool
```

Qué esperar en `Mounts:`:  
NOTE: add this table to memoria.md and a placeholder for a screenshot

| Contenedor | Volumen | Ruta | Modo |
|---|---|---|---|
| sidecar | ConfigMap (plantilla) | `/template` | **`ro`** |
| sidecar | `emptyDir` | `/html` | `rw` (tiene que escribir) |
| nginx | `emptyDir` | raíz de Nginx (§4.1) | `ro` o `rw` |

**El ConfigMap es de solo lectura** (criterio de la historia). Pruébalo escribiendo:

```bash
POD=$(kubectl get pod -n $NS -l $LBL -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n $NS $POD -c $SIDE -- touch /template/prueba
# esperado: touch: cannot touch '/template/prueba': Read-only file system
```

> **Por qué:** los volúmenes ConfigMap ya son de solo lectura por defecto; `read_only = true` lo deja explícito en el Pod spec, que es lo que pide el enunciado §3.3.

### 4.1 La raíz de Nginx coincide con el montaje del `emptyDir`

```bash
kubectl exec -n $NS $POD -c $WEB -- grep -rn 'root' /etc/nginx/
kubectl exec -n $NS $POD -c $WEB -- ls -l /usr/share/nginx/html     # la ruta que devolvió el grep (línea "root")
```

El `mount_path` del `emptyDir` en el contenedor Nginx tiene que ser **exactamente** esa ruta. Si no, Nginx sirve su página por defecto, o un 403/404, y el `index.html` generado queda en una carpeta que nadie lee.

---

## 5. El sidecar generó la página y sigue vivo

```bash
kubectl exec -n $NS $POD -c $SIDE -- cat /html/index.html | grep -i pod
kubectl exec -n $NS $POD -c $SIDE -- ps -ef        # debe verse "sleep infinity"
kubectl logs -n $NS $POD -c $SIDE                  # vacío si sed no falló
```

> **Por qué:** un contenedor normal que termina se reinicia (`restartPolicy: Always`), aunque haya terminado bien. Por eso el sidecar tiene que quedarse vivo; si no, ves `RESTARTS` subiendo y `CrashLoopBackOff` (D-009, consecuencias).

---

## 6. Cada Pod sirve **su propio nombre** (criterio principal)

```bash
for p in $(kubectl get pod -n $NS -l $LBL -o jsonpath='{.items[*].metadata.name}'); do
  got=$(kubectl exec -n $NS $p -c $WEB -- curl -s localhost | grep -o 'Pod: <b>[^<]*' | sed 's/.*<b>//')
  [ "$got" = "$p" ] && echo "OK   $p" || echo "FAIL $p -> '$got'"
done
```

Esperado: 3 líneas `OK`, con 3 nombres distintos.

- Si la imagen no trae `curl`, usa `wget -qO- localhost`. Si tampoco hay, lee el fichero con `cat /usr/share/nginx/html/index.html`, aunque así solo pruebas el fichero, no que Nginx lo sirva.
- Si ves `__POD_NAME__` literal, el `sed` no se ejecutó o `POD_NAME` está vacío. Mira `kubectl exec ... -c $SIDE -- env | grep POD_NAME`.

### 6.1 Desde fuera del Pod (por IP de Pod, sin Service)

Comprueba que Nginx escucha en la red de Calico y no solo en `localhost`:

```bash
kubectl get pod -n $NS -l $LBL -o wide            # columna IP
IP=$(kubectl get pod -n $NS $POD -o jsonpath='{.status.podIP}'); echo $IP
kubectl run tmp-curl -n $NS --rm -it --restart=Never --image=busybox -- wget -qO- http://$IP
```

`kubectl run` crea un Pod temporal (`tmp-curl`) con `busybox`, ejecuta `wget` contra la IP del Pod web y se borra al terminar (`--rm`). Es un **cliente** dentro del clúster, como lo será el Ingress Controller.

Si aparece `warning: couldn't attach to pod/tmp-curl, falling back to streaming logs`, no es un fallo: `wget` terminó antes de que `kubectl` se conectara, y el HTML sale de los logs. Lo que cuenta es que se vea la página.

> ⚠️ Cuando esté la política default-deny de C (US-30), esta prueba **debe fallar**. Hoy debe funcionar.

---

## 7. Nginx **y** `sshd` siguen arrancando

```bash
kubectl exec -n $NS $POD -c $WEB -- ps -ef | grep -E 'nginx|sshd' | grep -v grep
kubectl exec -n $NS $POD -c $WEB -- id webuser    # uid=… gid=1000
```

> **Por qué:** si el contenedor web tuviera un `command` propio, sustituiría el entrypoint de la imagen, que arranca **los dos** procesos. Sin `sshd`, el admin no podrá entrar por SSH a los web más adelante.

---

## 8. Recreación de un Pod

```bash
kubectl delete pod -n $NS $POD
kubectl get pods -n $NS -l $LBL -w                # Ctrl-C cuando vuelva a haber 3 Running 2/2
```

Repite §6. El Pod nuevo tiene **otro nombre**, y su página tiene que mostrar el nuevo, no el del Pod borrado.

> **Por qué:** demuestra que la página se genera en cada arranque del Pod y no queda guardada en el `emptyDir` (que se borra con el Pod).

---

## 🩺 Problemas típicos

| Síntoma | Dónde mirar | Causa probable |
|---|---|---|
| `apply` falla al crear el namespace | mensaje de error | Los nombres de namespace deben ser RFC 1123: **minúsculas**, dígitos y `-` |
| `namespaces "g2-workshop" not found` | el recurso que falla | Ese recurso usa `var.namespace` en vez de la referencia al recurso namespace, así que Terraform no espera a que exista |
| Recursos en `default` | §0.1 | Falta `namespace` en el `metadata` del recurso |
| Pod `Pending` | `kubectl describe pod` → Events | Falta CPU/memoria en el nodo (`requests`) o hay un `nodeSelector` erróneo |
| `ImagePullBackOff` | Events | Nombre de imagen o nodo sin salida a Internet (`virbr0`) |
| `READY 1/2`, sidecar en `CrashLoopBackOff` | `kubectl logs -c $SIDE --previous` | El comando termina (falta `sleep infinity`) o la ruta de la plantilla es otra |
| `CreateContainerConfigError` | Events | El ConfigMap no existe en **ese** namespace o el nombre no coincide |
| 403 Forbidden | §4.1 | El `emptyDir` está vacío en la raíz de Nginx (montaje en ruta equivocada) |
| Página por defecto de Nginx | §4.1 | El `emptyDir` no está montado sobre la raíz real |
| Se ve `__POD_NAME__` | §5, `env` | No se ejecutó el `sed`, o falta `POD_NAME` (Downward API) |
| Todos muestran el mismo nombre | §6 | Se lee el ConfigMap directamente, sin la página generada |

---

## ✅ Checklist para el PR (copiar en la descripción)

- [ ] `terraform fmt -check` y `terraform validate` pasan; `terraform plan` sin cambios tras `apply`
- [ ] Todos los recursos en `g2-workshop`, nada en `default` (§0.1)
- [ ] 3 Pods `Running`, `READY 2/2`, `RESTARTS 0` (§1)
- [ ] Label de los Pods comunicada a C (§2)
- [ ] ConfigMap con `__POD_NAME__` y grupo sustituido (§3)
- [ ] ConfigMap montado como **solo lectura** (§4)
- [ ] `curl localhost` en cada Pod devuelve **su** nombre (§6)
- [ ] Nginx y `sshd` corriendo en el contenedor web (§7)
- [ ] Un Pod recreado muestra su nombre nuevo (§8)
