# 🧪 Pruebas de US-30 · Política de denegación por defecto

Historia: [US-30](../../../historias/persona-c.md#us-30) · Antes: [pruebas de US-18](pruebas-us18.md), [pruebas de US-15](../web/pruebas-us15.md), [pruebas de US-24](pruebas-us24.md) · Decisión: [D-013](../../../decisions.md) (configuración aparte) · Después: [US-31](../../../historias/persona-b.md#us-31), [US-32](../../../historias/persona-c.md#us-32), [US-33](../../../historias/persona-a.md#us-33)

Cómo comprobar que la política `default-deny-all` aísla todos los Pods del namespace por `eth0`, en entrada y en salida, y cumple el 🧪 criterio de US-30: **el Ingress deja de responder y el SSH al admin por NodePort falla**. Se prueba **antes y después**: primero sin la política (línea base), luego con ella. Así se ve que lo que se rompe lo rompe la política y no otra cosa.

```
                 namespace ingress-nginx               namespace g2-workshop (default-deny-all)
host ──curl──► controller ──────────✗──────────────►  Pods web :80        ← entrada cerrada
host ──ssh───► 10.10.10.11:30002 ───✗──────────────►  Pod admin :22       ← entrada cerrada
                                                      Pods web ──✗──► kube-dns :53   ← salida cerrada
                                                      Pods web ──✓──► bbdd 10.1.2.100 (net1, Calico no la filtra)
```

Requisitos:
- las pruebas de [US-15](../web/pruebas-us15.md) (Ingress) y de [US-18](pruebas-us18.md) (SSH al admin por NodePort) pasan;
- para §7, `bbdd` está creado y los web tienen `net1` ([US-22](../web/pruebas-us22.md)).

---

## 0. Preparación

Los comandos se ejecutan desde el **host**, en la raíz del repo (o con `ssh root@k8s-master kubectl …` si el `kubectl` del host falla por la diferencia de versión). Valores que usamos:

| Valor | De dónde sale |
|---|---|
| `g2-workshop` | `var.namespace` → output `namespace` |
| `default-deny-all` | `terraform/network-policies/network-policy-deny-all.tf` |
| `app=web`, contenedor `nginx-server` | `local.web_labels`, `web-service-deployment.tf` |
| `nginx-service` | Service web, ClusterIP `8080 → 80` |
| `10.10.10.20` | IP del Ingress que asigna MetalLB → output `web_url` (`http://10.10.10.20/servers-G2`) 🔁 |
| `30002` | NodePort del admin → output `admin_service_node_port` 🔁 |
| `keys/par2_host` | privada del par 2 (host → admin, D-004) |
| `10.1.2.100` | `bbdd` en `vnx/vnx-vm-bdd-logs.xml` |

Variables para el resto de la guía:

```bash
NS=g2-workshop
WEB=$(kubectl get pod -n $NS -l app=web -o jsonpath='{.items[0].metadata.name}'); echo $WEB
web() { kubectl exec -n $NS "$WEB" -c nginx-server -- "$@"; }
CAP=docs/capturas/us-30-pruebas.txt
```

La IP del Ingress y el NodePort del admin están escritos tal cual en los comandos (🔁: pueden cambiar tras un `apply` desde cero). Compruébalos antes de empezar:

```bash
terraform -chdir=terraform output -raw web_url; echo
terraform -chdir=terraform output -raw admin_service_node_port; echo
```

Si no salen `http://10.10.10.20/servers-G2` y `30002`, cámbialos en los comandos. Si MetalLB no tiene IP, `web_url` es `http://10.10.10.11:<NodePort del controller>/servers-G2`.

Para guardar la salida en la captura de la historia, añade `2>&1 | tee -a $CAP` a los comandos de §4–§7.

> **Por qué `kubectl exec` sigue funcionando con la política:** va del API server al kubelet del nodo, y el kubelet entra en el contenedor directamente. No es tráfico de red hacia el Pod, así que las NetworkPolicies no lo ven.

---

## 1. Línea base: sin la política, todo funciona

Si la política ya está aplicada, quítala primero (solo afecta a la segunda configuración, D-013):

```bash
terraform -chdir=terraform/network-policies destroy
kubectl get networkpolicy -n $NS          # esperado: No resources found
```

Y comprueba que todo responde:

```bash
curl -s -o /dev/null -w '%{http_code}\n' -m 10 http://10.10.10.20/servers-G2     # 200
ssh -i keys/par2_host -p 30002 -o ConnectTimeout=5 adminuser@10.10.10.11 hostname          # nombre del Pod admin
web curl -s -o /dev/null -w '%{http_code}\n' -m 5 http://nginx-service:8080               # 200 (DNS + Service)
web ping -c 2 -W 2 10.1.2.100                                                             # 0% packet loss
```

> **Por qué hace falta:** si alguna de estas falla ya sin la política, el fallo de §4–§6 no demostraría nada. El tercer comando prueba a la vez la salida del web, el DNS (`nginx-service` se resuelve con `kube-dns`) y la entrada a otro web.

---

## 2. Aplicar la política (configuración `network-policies/`)

```bash
terraform -chdir=terraform/network-policies init
terraform -chdir=terraform/network-policies plan
```

Esperado: `data.terraform_remote_state.main: Reading...` y `Plan: 1 to add, 0 to change, 0 to destroy`, con `namespace = "g2-workshop"`.

```bash
terraform -chdir=terraform/network-policies apply
terraform -chdir=terraform/network-policies plan        # esperado: No changes
```

> **Por qué se lee el state:** el namespace no está escrito en esta configuración; sale de `local.env.namespace`, el output `namespace` del último `apply` de `terraform/`. Si el `plan` falla con `Unsupported attribute` en `local.env`, falta ese output o no se ha hecho `apply` en `terraform/` desde que se añadió.

---

## 3. La política existe y selecciona todos los Pods

```bash
kubectl get networkpolicy -n $NS
kubectl describe networkpolicy -n $NS default-deny-all 2>&1 | tee -a $CAP
```

Esperado:

```
PodSelector:     <none> (Allowing the specific traffic to all pods in this namespace)
Allowing ingress traffic:
  <none> (Selected pods are isolated for ingress connectivity)
Allowing egress traffic:
  <none> (Selected pods are isolated for egress connectivity)
Policy Types: Ingress, Egress
```

> **Por qué se lee así:** `PodSelector: <none>` es el `pod_selector {}` vacío, que casa con **todos** los Pods del namespace. La frase "Allowing the specific traffic" es engañosa: no permite nada, porque no hay reglas. Lo que importa son las dos líneas `isolated`: cada sentido que aparece en `Policy Types` queda cerrado salvo lo que abra otra política.

---

## 4. El Ingress deja de responder (criterio)

```bash
curl -s -o /dev/null -w '%{http_code} en %{time_total}s\n' -m 30 http://10.10.10.20/servers-G2
```

Esperado: `504` tras unos segundos, o `000` si el `-m` es más corto que la espera del controller.

Contraste en la misma IP, una ruta que no es nuestra:

```bash
curl -s -o /dev/null -w '%{http_code}\n' -m 10 http://10.10.10.20/no-existe              # 404
```

> **Por qué 504 y no `connection refused`:** el host sí llega al controller, que está en `ingress-nginx` y no tiene ninguna política. El que falla es el salto siguiente: el controller intenta conectar con la IP de un Pod web en el puerto 80, la política descarta el paquete en silencio (no lo rechaza) y el controller espera hasta su timeout de conexión antes de contestar `504 Gateway Time-out`. El `404` de `/no-existe` lo genera el propio controller, sin pasar por nuestros Pods: demuestra que el controller funciona y que lo cortado es solo la entrada a `g2-workshop`.

---

## 5. El SSH al admin por NodePort falla (criterio)

```bash
ssh -i keys/par2_host -p 30002 -o ConnectTimeout=5 -o BatchMode=yes adminuser@10.10.10.11 hostname
```

Esperado: `ssh: connect to host 10.10.10.11 port 30002: Connection timed out`.

> **Por qué timeout:** el NodePort sigue abierto en `k8s-worker1` y kube-proxy hace el DNAT a la IP del Pod admin, pero Calico descarta el paquete al entrar en el Pod. Como lo descarta sin responder, `ssh` no recibe nada y espera hasta `ConnectTimeout`. Un `Connection refused` querría decir otra cosa: que no hay nada escuchando (Service o Pod caído), no la política.

---

## 6. La salida también está cerrada

```bash
web curl -s -o /dev/null -w '%{http_code}\n' -m 5 http://nginx-service:8080; echo "exit=$?"
CIP=$(kubectl get svc -n $NS nginx-service -o jsonpath='{.spec.clusterIP}')
web curl -s -o /dev/null -w '%{http_code}\n' -m 5 http://$CIP:8080; echo "exit=$?"
```

Esperado: los dos fallan con `000` y `exit=28` (timeout de `curl`).

> **Por qué dos pruebas:** la primera falla ya en el DNS: la consulta a `kube-dns` (53/UDP) es salida del web, y está cerrada, así que `curl` agota su tiempo resolviendo el nombre. La segunda usa la ClusterIP y no necesita DNS: falla porque la salida del web hacia otro web también está cerrada (y, aunque saliera, la entrada del destino lo está). Este es el motivo por el que las políticas de permiso de US-31/US-32 tendrán que abrir `kube-dns` a quien lo necesite.

---

## 7. Lo que la política no toca

```bash
web ping -c 2 -W 2 10.1.2.100                         # bbdd por la VLAN: 0% packet loss
kubectl get pods -n $NS -o wide                       # todo sigue Running: la política no reinicia nada
```

> **Por qué la VLAN sigue funcionando:** el ping a `10.1.2.100` sale por `net1`, la macvlan de Multus sobre `e2.1000`. Calico solo pone sus reglas en la interfaz que él crea (`eth0`), así que `net1` queda fuera de las NetworkPolicies. Es la base de [US-33](../../../historias/persona-a.md#us-33) y del límite de seguridad de D-005: en la VLAN solo protegen las claves SSH y los usuarios de la base de datos. [pruebas-us24.md §8](pruebas-us24.md) lo comprueba desde el admin con SSH.

---

## 8. Es reversible y no toca la aplicación

```bash
terraform -chdir=terraform plan                                   # No changes: la app no sabe nada de la política
terraform -chdir=terraform/network-policies destroy
curl -s -o /dev/null -w '%{http_code}\n' -m 10 http://10.10.10.20/servers-G2     # vuelve a dar 200 sin reiniciar ningún Pod
terraform -chdir=terraform/network-policies apply                 # dejarla aplicada para US-31/32/33
```

> **Por qué:** es lo que justifica D-013. La política vive en otro state, así que se puede quitar y poner sin que `terraform/` vea cambios, y el efecto es inmediato: Calico actualiza las reglas en los nodos sin tocar los Pods.

---

## 🩺 Problemas típicos

| Síntoma | Dónde mirar | Causa probable |
|---|---|---|
| `plan` de `network-policies/` con `Unable to find remote state` | `ls terraform/terraform.tfstate` | No se ha hecho `apply` en `terraform/`, o se ejecuta desde otra carpeta |
| `Unsupported attribute` en `local.env.…` | `terraform -chdir=terraform output` | El output no existe en el state principal: añadirlo a `outputs.tf` y `apply` en `terraform/` |
| Con la política aplicada, el Ingress sigue dando `200` | `kubectl get networkpolicy -A` | La política está en otro namespace (`local.env.namespace` no es el de los Pods) |
| Ingress `200` y SSH bien, política en el namespace correcto | `kubectl get pods -n calico-system`, `kube-system` | El CNI no aplica NetworkPolicies (no debería pasar con Calico) |
| SSH `Connection refused` en vez de timeout | `kubectl get endpoints -n $NS` | No es la política: el admin o su Service no están |
| `destroy` de `terraform/` deja la política | `kubectl get networkpolicy -n $NS` | Orden de destrucción: primero `network-policies/` (D-013) |

---

## ✅ Checklist para el PR (copiar en la descripción)

- [ ] `terraform fmt -check` y `terraform validate` pasan en las dos configuraciones; `plan` sin cambios tras `apply` (§2, §8)
- [ ] Sin la política, Ingress `200`, SSH al admin y DNS desde un web funcionan (§1)
- [ ] `default-deny-all` existe en `g2-workshop`, con `pod_selector` vacío y `Ingress, Egress` aislados (§3)
- [ ] Con la política, el Ingress `/servers-G2` no responde (`504` o timeout) y `/no-existe` sigue dando `404` (§4, criterio)
- [ ] Con la política, `ssh -p 30002 adminuser@10.10.10.11` da `Connection timed out` (§5, criterio)
- [ ] Desde un web, ni el nombre ni la ClusterIP de `nginx-service` responden (§6)
- [ ] El ping por la VLAN a `bbdd` sigue funcionando (§7)
- [ ] Quitar la política devuelve el Ingress a `200` sin cambios en `terraform/` (§8)
- [ ] Salida guardada en `docs/capturas/us-30-pruebas.txt`
