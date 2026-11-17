# 🧪 Pruebas de US-15 · Service ClusterIP e Ingress

⬅️ [Guía web](guia-web.md) · Historia: [US-15](../../../historias/persona-b.md#us-15) · Antes: [pruebas de US-14](pruebas-us14.md) · Relacionado: [guía MetalLB e Ingress](../metallb/guia-metallb.md)

Cómo comprobar, después de `terraform apply`, que el Service web y el Ingress cumplen los 🧪 criterios de US-15. Se prueba **por capas**, de dentro hacia fuera: Pods → Service → Ingress Controller → host. Así, si algo falla, sabes en qué capa está.

```
host 10.10.20.2 ──r1──► 10.10.10.20:80 (MetalLB) ──► ingress-nginx-controller
                                                       │  /servers-G2 → rewrite a /
                                                       ▼
                                          nginx-service:8080 (ClusterIP)
                                                       │
                                     ┌─────────────────┼─────────────────┐
                                     ▼                 ▼                 ▼
                                Pod web :80       Pod web :80       Pod web :80
```

Requisito: las pruebas de [US-14](pruebas-us14.md) pasan (3 Pods `Running 2/2`, cada uno sirve su nombre).

---

## 0. Preparación

Desde el **host** (o desde `ssh root@k8s-master` si el `kubectl` del host falla por la diferencia de versión):

```bash
NS=g2-workshop               # var.namespace
LBL='app=web'                # local.web_labels
SVC=nginx-service            # Service web
ING=g2-ingress               # Ingress
RUTA=/servers-G2             # var.g2_ingress_path
```

En la VM `terraform`:

```bash
terraform plan               # "No changes"
terraform output             # namespace, web_service_*, ingress_* si están descomentados
```

---

## 1. El Service es `ClusterIP` en 8080 → 80

```bash
kubectl get svc $SVC -n $NS -o wide
```

Qué esperar:
- `TYPE ClusterIP`, `EXTERNAL-IP <none>`;
- `PORT(S) 8080/TCP`, **sin** `:3xxxx` (un `8080:30001/TCP` significaría que sigue siendo NodePort);
- `SELECTOR app=web`.

```bash
kubectl get svc $SVC -n $NS -o jsonpath='{.spec.ports[0].port} -> {.spec.ports[0].targetPort}{"\n"}'
# esperado: 8080 -> 80
```

> **Por qué:** `port` es el puerto del **Service** (el que usa el Ingress: 8080) y `targetPort` el del **contenedor** (donde escucha Nginx: 80). Si están al revés o el `targetPort` no es 80, el Service reenvía a un puerto cerrado.

---

## 2. El Service encuentra los 3 Pods (endpoints)

```bash
kubectl get endpointslices -n $NS -l kubernetes.io/service-name=$SVC
kubectl get pods -n $NS -l $LBL -o wide            # compara las IPs
```

Esperado: **3 IPs**, puerto **80**, las mismas que la columna `IP` de los Pods.

> **Por qué:** el Service no "conoce" los Pods por nombre: Kubernetes busca los Pods que cumplen el `selector` **en el mismo namespace** y que estén `Ready`, y apunta sus IPs aquí. Si sale vacío (`<unset>`), el selector, el namespace o el readiness no cuadran, y todo lo de arriba fallará con 503.

---

## 3. El Service funciona dentro del clúster

Desde un Pod temporal, primero por **nombre DNS** y luego por ClusterIP:

```bash
kubectl run tmp-curl -n $NS --rm -it --restart=Never --image=busybox -- \
  sh -c "for i in 1 2 3 4 5 6; do wget -qO- http://$SVC:8080 | grep -o 'Pod: <b>[^<]*'; done"
```

Esperado: 6 líneas, con **nombres de Pod que van cambiando**: kube-proxy reparte las conexiones entre los endpoints.

> Si aparece `warning: couldn't attach to pod/tmp-curl, falling back to streaming logs`, no es un error (ver [pruebas de US-14 §6.1](pruebas-us14.md#61-desde-fuera-del-pod-por-ip-de-pod-sin-service)).

> **Por qué:** `nginx-service` se resuelve por el DNS del clúster (CoreDNS) a la ClusterIP, solo desde dentro del mismo namespace. Desde otro namespace hace falta `nginx-service.g2-workshop` o el nombre completo `nginx-service.g2-workshop.svc.cluster.local`.

### 3.1 Y **no** es accesible desde fuera

```bash
curl -m 3 http://10.10.10.11:30001         # el NodePort antiguo: debe fallar (connection refused o timeout)
```

> **Por qué:** con `ClusterIP` la única entrada desde fuera es el Ingress. Es lo que pide el enunciado §4.1.

---

## 4. El objeto Ingress

```bash
kubectl get ingress -n $NS
kubectl describe ingress $ING -n $NS
```

Qué esperar en `get`:

| Columna | Valor |
|---|---|
| `CLASS` | `nginx` |
| `HOSTS` | `*` (no filtramos por nombre de host) |
| `ADDRESS` | la IP del Ingress Controller, p. ej. `10.10.10.20` (puede tardar unos segundos) |
| `PORTS` | `80` |

Qué esperar en `describe`:
- `Rules:` → `/servers-G2   nginx-service:8080 (IP1:80,IP2:80,IP3:80)`. Las 3 IPs de los Pods, iguales que en §2;
- `Annotations:` → `nginx.ingress.kubernetes.io/rewrite-target: /`;
- `Events:` → `Sync ... Scheduled for sync` del controller. Si no hay eventos, ningún controller ha recogido el Ingress (clase mal puesta).

> **Por qué `ADDRESS`:** la rellena el **controller** cuando acepta el Ingress. Si se queda vacía, el controller no lo ha reconocido como suyo (`ingress_class_name` distinto de `nginx`), o su Service no tiene IP externa (§5).

---

## 5. El Ingress Controller y su IP

```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller
IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}'); echo $IP
NP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}'); echo $NP
```

- `TYPE LoadBalancer`, `EXTERNAL-IP` del pool de MetalLB (`10.10.10.20-30`).
- Si `EXTERNAL-IP` está `<pending>`, MetalLB no tiene pool: `sudo vnx -f k8s_lab-calico.xml -x config_metallb` y `kubectl get ipaddresspools -n metallb-system`. Mientras tanto, prueba por NodePort (§6).

Para ver la regla **dentro** del controller:

```bash
CTRL=$(kubectl get pod -n ingress-nginx -l app.kubernetes.io/component=controller -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n ingress-nginx $CTRL -- grep -n "servers-G2" /etc/nginx/nginx.conf
```

> **Por qué:** el controller traduce cada Ingress a un bloque `location` de su `nginx.conf`. Si la ruta no aparece, el Ingress no le llegó.

---

## 6. Acceso desde el host (criterio principal)

```bash
curl -i http://$IP$RUTA
```

Esperado: `HTTP/1.1 200 OK` y el HTML con `CNVR/ARSN G2` y `Served by Pod: <b>nginx-deployment-…</b>`.

Si MetalLB no tiene IP, por el NodePort del controller en cualquier nodo:

```bash
curl -i http://10.10.10.11:$NP$RUTA
```

> **Por qué funciona desde el host:** el host (10.10.20.2) llega a `10.10.10.0/24` por `r1` (ruta en `k8s_lab-calico.xml`). La IP de MetalLB la anuncia por ARP el speaker de un nodo ([guía MetalLB §4](../metallb/guia-metallb.md)).

### 6.1 Rutas que deben y no deben funcionar

```bash
for p in $RUTA $RUTA/ $RUTA/index.html / /servers-G3 /servers_G2; do
  printf '%-22s ' "$p"; curl -s -o /dev/null -w '%{http_code}\n' http://$IP$p
done
```

| Ruta | Esperado | Por qué |
|---|---|---|
| `/servers-G2`, `/servers-G2/`, `/servers-G2/index.html` | `200` | `pathType: Prefix` casa todo lo que empieza por `/servers-G2`, y `rewrite-target: /` lo convierte en `/` |
| `/`, `/servers-G3`, `/servers_G2` | `404` | Ninguna regla casa: responde el backend por defecto **del controller**, no tus Pods |

---

## 7. Balanceo entre los 3 Pods

```bash
for i in $(seq 1 12); do curl -s http://$IP$RUTA | grep -o 'Pod: <b>[^<]*' | sed 's/.*<b>//'; done | sort | uniq -c
```

Esperado: **3 nombres**, repartidos más o menos por igual (unos 4 cada uno).

> **Por qué:** cada `curl` es una conexión nueva, y el controller la reparte entre los endpoints del Service. Ojo: ingress-nginx manda el tráfico **directamente a las IPs de los Pods** (las que viste en §4), no a la ClusterIP; el Service lo usa para saber cuáles son.

---

## 8. El `rewrite-target` hace su trabajo

Mira el log de acceso de un Pod web mientras haces un `curl`:

```bash
POD=$(kubectl get pod -n $NS -l $LBL -o jsonpath='{.items[0].metadata.name}')
kubectl logs -n $NS $POD -c nginx-server --tail=5 -f &
for i in 1 2 3 4 5 6; do curl -s -o /dev/null http://$IP$RUTA; done
kill %1
```

Esperado en el log: `"GET / HTTP/1.1" 200`, **no** `GET /servers-G2`.

> **Por qué:** el cliente pide `/servers-G2`, pero tu Nginx solo tiene `/index.html`. La anotación reescribe la ruta en el controller antes de reenviar. Sin ella, el log mostraría `GET /servers-G2` con `404`.

---

## 9. Un Pod nuevo entra solo en el balanceo

```bash
kubectl delete pod -n $NS $POD
kubectl get endpointslices -n $NS -l kubernetes.io/service-name=$SVC -w   # Ctrl-C cuando vuelva a haber 3 IPs
```

Repite §7: siguen saliendo 3 nombres, uno de ellos **nuevo**, sin tocar ni el Service ni el Ingress.

> **Por qué:** el Service selecciona por label, no por nombre ni IP. Los endpoints se actualizan solos, y el controller los relee.

---

## 🩺 Problemas típicos

| Síntoma | Dónde mirar | Causa probable |
|---|---|---|
| `curl` al host se queda colgado (timeout) | `ip route` en el host, §5 | IP de MetalLB sin anunciar o sin ruta a `10.10.10.0/24` por `r1` |
| `EXTERNAL-IP <pending>` en el controller | `kubectl get ipaddresspools -n metallb-system` | Falta el pool: re-ejecutar `config_metallb` |
| `ADDRESS` del Ingress vacía, sin `Events` | §4 | `ingress_class_name` no es `nginx` |
| `404` en `/servers-G2` | §5 (`grep` en `nginx.conf`), §8 | Ruta mal escrita (`_` en vez de `-`), o falta `rewrite-target` y el 404 lo da tu Nginx (se ve en el log del Pod) |
| `503 Service Temporarily Unavailable` | §2, §4 (`describe`) | El Service no tiene endpoints: selector, namespace o Pods no `Ready` |
| `502 Bad Gateway` | §1 | `targetPort` no es 80: el controller llega a los Pods pero a un puerto cerrado |
| `describe ingress` → `<error: endpoints "nginx-service" not found>` | `kubectl get svc -A \| grep nginx-service` | El Ingress y el Service están en namespaces distintos |
| Siempre el mismo nombre de Pod | §2, §7 | Solo 1 endpoint `Ready`, o reutilizas la conexión (navegador con keep-alive): prueba con `curl` |
| `terraform apply` falla en el Service | mensaje de error | `node_port` sigue puesto con `type = "ClusterIP"` |

---

## ✅ Checklist para el PR (copiar en la descripción)

- [ ] `terraform fmt -check` y `terraform validate` pasan; `terraform plan` sin cambios tras `apply`
- [ ] Service `ClusterIP`, `8080 → 80`, selector `app=web` (§1)
- [ ] El Service tiene 3 endpoints en el puerto 80 (§2)
- [ ] El Service responde dentro del clúster y **no** desde fuera (§3)
- [ ] Ingress con clase `nginx`, ruta `/servers-G2`, `rewrite-target: /` y `ADDRESS` asignada (§4)
- [ ] `curl http://<ip-ingress>/servers-G2` desde el host devuelve `200` con la página (§6)
- [ ] Rutas que no son `/servers-G2` devuelven `404` (§6.1)
- [ ] Al repetir, salen los 3 nombres de Pod (§7)
- [ ] El log del Pod muestra `GET /` (§8)
