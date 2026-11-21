# 🧪 Pruebas de US-31 · Acceso a los web solo desde el Ingress Controller

⬅️ [Guía web](guia-web.md) · Historia: [US-31](../../../historias/persona-b.md#us-31) · Antes: [pruebas de US-15](pruebas-us15.md), [pruebas de US-30](../admin/pruebas-us30.md) · Decisión: [D-013](../../../decisions.md) (configuración aparte)

Cómo comprobar, después del `apply` en `terraform/network-policies/`, que la política `web-ingress` deja entrar en los Pods web **solo** al Ingress Controller, en el puerto 80, y cumple los 🧪 criterios de US-31: **`curl /servers-G2` vuelve a funcionar, y el acceso directo a la ClusterIP o a la IP de un Pod web desde otro Pod falla**. Además se prueba cada mitad del AND por separado, para demostrar que la regla no deja pasar de más.

```
                 namespace ingress-nginx                    namespace g2-workshop
host ──curl──► controller (name=ingress-nginx, ──── ✓ :80 ──►  Pods web (app=web)
               component=controller)                          ▲
               Pod sin labels (tmp-ns) ────────── ✗ ──────────┤  ← falla el pod_selector
namespace default                                             │
               Pod con labels del controller (tmp-labels) ✗ ──┤  ← falla el namespace_selector
               Pod normal (tmp) ───────────────── ✗ ──────────┘  ← no casa nada
```

Requisitos:
- las pruebas de [US-30](../admin/pruebas-us30.md) pasan: `default-deny-all` aplicada y el Ingress sin respuesta;
- las de [US-15](pruebas-us15.md) pasaban antes de US-30 (3 Pods web detrás del Ingress).

---

## 0. Preparación

Los comandos se ejecutan desde el **host**, en la raíz del repo (o con `ssh root@k8s-master kubectl …` si el `kubectl` del host falla por la diferencia de versión). Valores que usamos:

| Valor | De dónde sale |
|---|---|
| `g2-workshop` | `var.namespace` → output `namespace` → `local.env.namespace` |
| `app=web` | `local.web_labels` → output `web_labels` → `local.env.web_labels` |
| `web-ingress` | `terraform/network-policies/network-policy-web-ingress.tf` |
| `ingress-nginx` | namespace del controller ([datos-escenario.md §5](../../datos-escenario.md)) |
| `app.kubernetes.io/name=ingress-nginx`, `app.kubernetes.io/component=controller` | labels del Pod del controller (§5 de datos-escenario) |
| `nginx-service`, `8080 → 80` | Service web (ClusterIP) |

Variables para el resto de la guía:

```bash
NS=g2-workshop
URL=$(terraform -chdir=terraform output -raw web_url); echo $URL
CIP=$(kubectl get svc -n $NS nginx-service -o jsonpath='{.spec.clusterIP}'); echo $CIP
WEBIP=$(kubectl get pod -n $NS -l app=web -o jsonpath='{.items[0].status.podIP}'); echo $WEBIP
CAP=docs/capturas/us-31-pruebas.txt
```

Para guardar la salida en la captura de la historia, añade `2>&1 | tee -a $CAP` a los comandos de §3–§6.

---

## 1. Antes de aplicar: el controller es un Pod normal

```bash
kubectl get pod -n ingress-nginx -l app.kubernetes.io/component=controller -o wide
kubectl get pod -n ingress-nginx -l app.kubernetes.io/component=controller \
  -o jsonpath='{.items[0].spec.hostNetwork}{"\n"}'
```

Esperado: la IP del Pod es `172.16.x.x` y `hostNetwork` sale vacío o `false`.

> **Por qué:** el `pod_selector` de la regla identifica el origen por la IP del Pod que lo envía. Si el controller usara `hostNetwork`, sus paquetes saldrían con la IP del **nodo** (`10.10.10.x`), Calico no los asociaría a ningún Pod y la regla nunca casaría: el Ingress seguiría dando `504` con la política aplicada.

Y que el punto de partida es el de US-30:

```bash
kubectl get networkpolicy -n $NS                                   # solo default-deny-all
curl -s -o /dev/null -w '%{http_code}\n' -m 30 $URL                # 504 o 000
```

---

## 2. Aplicar la política

```bash
terraform -chdir=terraform/network-policies fmt -check
terraform -chdir=terraform/network-policies validate
terraform -chdir=terraform/network-policies plan                   # Plan: 1 to add (web-ingress)
terraform -chdir=terraform/network-policies apply
terraform -chdir=terraform/network-policies plan                   # No changes
terraform -chdir=terraform/network-policies output
```

Esperado en el `plan`: solo `kubernetes_network_policy_v1.web_ingress` se crea; `default_deny_all` no cambia.

> **Por qué no cambia la denegación por defecto:** las políticas se suman. Para los Pods web, Calico permite la unión de todas las que los seleccionan: `default-deny-all` (nada) + `web-ingress` (el controller en el 80). Para el admin solo sigue aplicando `default-deny-all`.

---

## 3. La regla es un AND, en el puerto 80

```bash
kubectl describe networkpolicy -n $NS web-ingress 2>&1 | tee -a $CAP
```

Esperado:

```
Spec:
  PodSelector:     app=web
  Allowing ingress traffic:
    To Port: 80/TCP
    From:
      NamespaceSelector: kubernetes.io/metadata.name=ingress-nginx
      PodSelector: app.kubernetes.io/component=controller,app.kubernetes.io/name=ingress-nginx
  Not affecting egress traffic
  Policy Types: Ingress
```

> **Cómo se lee:** `NamespaceSelector` y `PodSelector` debajo del **mismo** `From:` es el AND: Pods con esas labels **dentro** de `ingress-nginx`. Si aparecieran como dos entradas `From:` separadas (o un guion `----------` entre ellas), sería un OR: cualquier Pod de `ingress-nginx`, **o** cualquier Pod de `g2-workshop` con esas labels. `To Port: 80/TCP` es el puerto del Pod, no el 8080 del Service. `Not affecting egress traffic` porque `policy_types` solo tiene `Ingress`: la salida de los web la sigue cerrando `default-deny-all`.

---

## 4. El Ingress vuelve a funcionar (criterio)

```bash
curl -i -m 10 $URL
for i in $(seq 1 12); do curl -s -m 5 $URL | grep -o 'Pod: <b>[^<]*' | sed 's/.*<b>//'; done | sort | uniq -c
```

Esperado: `HTTP/1.1 200 OK` con `Served by Pod: <b>nginx-deployment-…</b>`, y el bucle reparte las peticiones entre los **3** Pods.

> **Por qué funciona sin regla de egress:** el controller abre la conexión hacia el Pod web, y la regla la deja entrar. La respuesta del web va por la misma conexión, y Calico sigue las conexiones (*conntrack*): una respuesta a una conexión permitida pasa aunque `default-deny-all` cierre la salida del web. Y el balanceo funciona porque la regla permite la entrada a **todos** los Pods `app=web`, sin importar en qué worker estén.

---

## 5. Acceso directo desde otros Pods: falla (criterio)

### 5.1 Desde el admin

```bash
ADMIN=$(kubectl get pod -n $NS -l app=admin -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n $NS $ADMIN -c admin-server -- curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://$CIP:8080; echo "exit=$?"
kubectl exec -n $NS $ADMIN -c admin-server -- curl -s -m 5 -o /dev/null -w '%{http_code}\n' http://$WEBIP:80; echo "exit=$?"
```

Esperado: `000` y timeout en los dos.

> ⚠️ **Esta prueba sola no demuestra US-31.** Con `default-deny-all`, la **salida** del admin está cerrada: el paquete no llega ni a salir del admin, diga lo que diga `web-ingress`. Para probar que lo que bloquea es la regla de los web, hace falta un cliente con la salida abierta: §5.2.

### 5.2 Desde un Pod de otro namespace sin políticas

```bash
kubectl run tmp -n default --image=busybox --restart=Never -- sleep 3600
kubectl wait -n default --for=condition=Ready pod/tmp --timeout=60s
kubectl exec -n default tmp -- wget -qO- -T 5 http://$CIP:8080;  echo "exit=$?"
kubectl exec -n default tmp -- wget -qO- -T 5 http://$WEBIP:80;  echo "exit=$?"
```

Esperado: `wget: download timed out` y `exit=1` en los dos.

> **Por qué este sí demuestra la regla:** en `default` no hay NetworkPolicies, así que la salida de `tmp` está abierta. El paquete llega al Pod web, y es la **entrada** del web la que lo descarta, porque `tmp` no casa con el `from` de `web-ingress`. Que falle también por la ClusterIP confirma que el Service no es una puerta trasera: kube-proxy cambia la ClusterIP por la IP de un Pod web (DNAT) antes de que Calico compruebe la política, y el origen sigue siendo `tmp`.

---

## 6. Cada mitad del AND por separado

### 6.1 Namespace correcto, Pod incorrecto

Un Pod **sin** las labels del controller **dentro** de `ingress-nginx`:

```bash
kubectl run tmp-ns -n ingress-nginx --image=busybox --restart=Never -- sleep 3600
kubectl wait -n ingress-nginx --for=condition=Ready pod/tmp-ns --timeout=60s
kubectl exec -n ingress-nginx tmp-ns -- wget -qO- -T 5 http://$WEBIP:80; echo "exit=$?"
```

Esperado: timeout. Casa el `namespace_selector` pero no el `pod_selector`.

### 6.2 Pod con las labels del controller, namespace incorrecto

```bash
kubectl run tmp-labels -n default --image=busybox --restart=Never \
  --labels=app.kubernetes.io/name=ingress-nginx,app.kubernetes.io/component=controller -- sleep 3600
kubectl wait -n default --for=condition=Ready pod/tmp-labels --timeout=60s
kubectl exec -n default tmp-labels -- wget -qO- -T 5 http://$WEBIP:80; echo "exit=$?"
```

Esperado: timeout. Casa el `pod_selector` pero no el `namespace_selector`.

> **Por qué estas dos pruebas:** juntas demuestran que hacen falta **las dos** condiciones.
> - 6.1 detecta el OR (dos `from` separados): con él, cualquier Pod de `ingress-nginx` valdría y 6.1 **pasaría**.
> - 6.2 detecta un `namespace_selector` demasiado amplio (por ejemplo `namespace_selector {}`, que casa con todos los namespaces): con él, cualquier Pod con las labels del controller, en cualquier namespace, valdría y 6.2 **pasaría**. Las labels se pueden poner a mano en cualquier Pod, así que no bastan para identificar al controller: el namespace es lo que lo garantiza.
>
> Ojo: `tmp-labels` **no** se crea en `ingress-nginx`, porque con esas labels el Service del controller lo tomaría como endpoint y le mandaría tráfico real.

Limpieza:

```bash
kubectl delete pod -n default tmp tmp-labels --now
kubectl delete pod -n ingress-nginx tmp-ns --now
```

---

## 7. Lo que sigue cerrado

```bash
WEB=$(kubectl get pod -n $NS -l app=web -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n $NS $WEB -c nginx-server -- curl -s -m 5 -o /dev/null http://nginx-service:8080; echo "exit=$?"   # 28: sin DNS
NP=$(terraform -chdir=terraform output -raw admin_service_node_port)
ssh -i keys/par2_host -p $NP -o ConnectTimeout=5 -o BatchMode=yes adminuser@10.10.10.11 hostname              # timeout (US-32)
```

Esperado: los dos fallan, igual que en US-30.

> **Por qué:** `web-ingress` solo abre la **entrada** de los web desde el controller. La salida de los web (DNS incluido) y la entrada al admin siguen cerradas por `default-deny-all` hasta que otras políticas las abran.

---

## 8. Un Pod nuevo hereda la regla

```bash
kubectl delete pod -n $NS $WEB
kubectl get pods -n $NS -l app=web -w           # Ctrl-C cuando el nuevo esté Running
for i in $(seq 1 12); do curl -s -m 5 $URL | grep -o 'Pod: <b>[^<]*' | sed 's/.*<b>//'; done | sort | uniq -c
```

Esperado: el Pod nuevo aparece en el reparto, sin tocar Terraform.

> **Por qué:** la política selecciona por **labels**, no por IP. El Pod nuevo tiene otra IP de Calico, pero lleva `app=web` del `template`, así que Calico le aplica la misma regla en cuanto arranca.

---

## 🩺 Problemas típicos

| Síntoma | Dónde mirar | Causa probable |
|---|---|---|
| `plan` con `Unsupported attribute` en `local.env.web_labels` | `terraform -chdir=terraform output web_labels` | El output no está en el state principal: `apply` en `terraform/` primero |
| Con la política, el Ingress sigue dando `504` | §1, §3 | El controller usa `hostNetwork`, o las labels/namespace del `from` no coinciden con las reales (`kubectl get pod -n ingress-nginx --show-labels`) |
| Ingress `504` y `describe` sin `PodSelector: app=web` | `kubectl get pod -n $NS --show-labels` | `local.env.web_labels` no coincide con las labels de los Pods |
| §6.1 **pasa** (el web responde a `tmp-ns`) | §3 | Los selectores están en dos `from` separados: es un OR |
| `describe` muestra `To Port: 8080/TCP` | `network-policy-web-ingress.tf` | Puerto del Service en vez del puerto del Pod: el controller va al 80 y se descarta |
| Ingress `200` pero solo 1 o 2 Pods en el reparto | `kubectl get pods -n $NS -l app=web -o wide` | Pods que no están `Running 2/2`; no es la política |
| `destroy` de `terraform/` deja las políticas | `kubectl get networkpolicy -n $NS` | Orden de destrucción: primero `network-policies/` (D-013) |

---

## ✅ Checklist para el PR (copiar en la descripción)

- [ ] `terraform fmt -check` y `terraform validate` pasan en `network-policies/`; `plan` sin cambios tras `apply` (§2)
- [ ] El controller no usa `hostNetwork` (§1)
- [ ] `describe` de `web-ingress`: `app=web`, un único `From` con `NamespaceSelector` y `PodSelector`, `80/TCP` (§3)
- [ ] `curl /servers-G2` vuelve a dar `200` y reparte entre los 3 Pods (§4, criterio)
- [ ] Desde un Pod de `default`, ni la ClusterIP ni la IP de un Pod web responden (§5.2, criterio)
- [ ] Un Pod sin labels en `ingress-nginx` y un Pod con las labels del controller en `default` no entran (§6)
- [ ] El DNS de los web y el SSH al admin siguen cerrados (§7)
- [ ] Un Pod web nuevo entra en el reparto sin cambios en Terraform (§8)
- [ ] Salida guardada en `docs/capturas/us-31-pruebas.txt`
