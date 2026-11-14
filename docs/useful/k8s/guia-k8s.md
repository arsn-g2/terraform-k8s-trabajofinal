# 🧰 Guía: comandos k8s para verificar el despliegue y probar la conectividad

⬅️ [Volver al plan](../../../plan.md) · Relacionado: [datos del escenario](../../datos-escenario.md) · [guía de Calico](../calico/guia-calico.md) · [guía de Multus](../multus/guia-multus.md)

---

Los nombres de esta guía son los del borrador actual de `terraform/`:

| Recurso | Nombre | Label | Puertos |
|---|---|---|---|
| Deployment web | `nginx-deployment` | `app=nginx` | contenedor 80 |
| Service web | `nginx-service` (NodePort) | selector `app=nginx` | 80 → 80, nodePort `30001` |
| Deployment admin | `admin-deployment` | `app=admin` | contenedor 80 (sshd escucha en 22) |
| Service admin | `admin-service` (NodePort) | selector `app=admin` | 80 → 80, nodePort `30002` |

Todo está en el namespace `default`. Cuando pasemos al namespace propio (D-002), añadir `-n <ns>` a cada comando o fijarlo una vez:
```bash
kubectl config set-context --current --namespace=<ns>
```

Herramientas que hay dentro de las imágenes (comprobado):

| | `curl` | `ping` | `ssh` | `ip` | `getent` | `nc` | `nslookup` | `wget` |
|---|---|---|---|---|---|---|---|---|
| `nginx-ssh` (web) | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| `admin-ssh` (admin) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

> El `kubectl` del host (v1.29) avisa de *version skew*. Si un comando falla, lanzarlo en el master: `ssh root@k8s-master kubectl …`.

---

## 1. Verificar el despliegue

### Visión general
```bash
kubectl get all -o wide                    # Deployments, ReplicaSets, Pods y Services de un vistazo
kubectl get pods -o wide --show-labels     # IP del Pod, nodo donde corre y labels
kubectl get pods -l app=nginx -o wide      # solo los web (deberían ser 3)
kubectl get pods -l app=admin -o wide      # solo el admin (1)
```

### Deployments y réplicas
```bash
kubectl get deploy                                   # READY 3/3 y 1/1
kubectl rollout status deploy/nginx-deployment       # espera a que termine el rollout
kubectl describe deploy nginx-deployment             # réplicas, imagen, eventos
```

### Services y Endpoints
Un Service sin Endpoints significa que su `selector` no coincide con los labels de ningún Pod.
```bash
kubectl get svc -o wide                              # tipo, ClusterIP, puertos y nodePort
kubectl get endpoints nginx-service                  # debe listar las 3 IPs de los Pods web, puerto 80
kubectl get endpoints admin-service
kubectl describe svc nginx-service                   # Selector, TargetPort, Endpoints
```

### Cuando un Pod no arranca
```bash
kubectl describe pod <pod>                 # sección Events: imagen, scheduling, volúmenes
kubectl logs <pod>                         # logs del contenedor
kubectl logs <pod> -c <contenedor>         # si hay varios contenedores (p. ej. el initContainer)
kubectl logs <pod> --previous              # logs del contenedor anterior si ha reiniciado
kubectl get events --sort-by=.lastTimestamp | tail -20
```

### Contrastar con Terraform
Lo que Terraform cree que ha desplegado debe coincidir con lo que hay en el clúster:
```bash
# en la VM terraform, en /shared/terraform-k8s-trabajofinal/terraform
terraform state list
terraform state show kubernetes_service_v1.web_service
terraform output
terraform plan                             # "No changes" = el clúster coincide con el código
```

---

## 2. Preparar variables para las pruebas

Para no copiar nombres e IPs a mano:
```bash
WEB=$(kubectl get pod -l app=nginx -o jsonpath='{.items[0].metadata.name}')
WEB2=$(kubectl get pod -l app=nginx -o jsonpath='{.items[1].metadata.name}')
ADMIN=$(kubectl get pod -l app=admin -o jsonpath='{.items[0].metadata.name}')
WEB2_IP=$(kubectl get pod $WEB2 -o jsonpath='{.status.podIP}')
ADMIN_IP=$(kubectl get pod $ADMIN -o jsonpath='{.status.podIP}')

kubectl get pod -l app=nginx -o custom-columns=NAME:.metadata.name,IP:.status.podIP,NODE:.spec.nodeName
```

Elegir Pods en **nodos distintos** para probar el tráfico entre nodos (túnel IPIP de Calico), y en el **mismo** nodo para el tráfico local (rutas `caliXXXX`).

---

## 3. Pruebas de conectividad entre Pods

### Dentro de un Pod
```bash
kubectl exec -it $WEB -- sh                # shell interactiva
kubectl exec $WEB -- ip addr               # eth0 con una /32 (Calico)
kubectl exec $WEB -- ip route              # default via 169.254.1.1
kubectl exec $WEB -- ss -ltn               # puertos en escucha: 80 (nginx) y 22 (sshd)
kubectl exec $WEB -- curl -s localhost     # nginx responde dentro del propio Pod
```

### Pod → Pod por IP
```bash
kubectl exec $WEB   -- ping -c 3 $WEB2_IP                    # ICMP web → web
kubectl exec $WEB   -- curl -s -m 3 http://$WEB2_IP          # HTTP web → web (puerto 80)
kubectl exec $ADMIN -- curl -s -m 3 http://$WEB2_IP          # HTTP admin → web
kubectl exec $ADMIN -- nc -zv -w 2 $WEB2_IP 22               # ¿está abierto el SSH del web?
kubectl exec $WEB   -- ping -c 3 $ADMIN_IP                   # web → admin
```

Usar siempre `-m 3` en `curl` y `-w 2` en `nc`: sin timeout, una conexión bloqueada por una NetworkPolicy se queda colgada en lugar de fallar.

### Pod → Service (ClusterIP y DNS)
```bash
kubectl exec $ADMIN -- getent hosts nginx-service            # el DNS resuelve el nombre a la ClusterIP
kubectl exec $ADMIN -- nslookup nginx-service.default.svc.cluster.local
kubectl exec $ADMIN -- curl -s -m 3 -o /dev/null -w '%{http_code}\n' http://nginx-service      # 200
kubectl exec $ADMIN -- curl -s -m 3 -o /dev/null -w '%{http_code}\n' http://admin-service      # ver nota ↓
```
> ⚠️ Con el borrador actual, `admin-service` apunta al puerto **80** del Pod admin, pero en ese Pod solo escucha sshd en el **22**, así que la petición falla (`000`). Lo esperable es que el Service admin acabe siendo 2222 → 22 (ver CLAUDE.md, "Services").

La ClusterIP no responde a `ping`: es una IP virtual que kube-proxy traduce solo para los puertos del Service. Probarla con `curl` o `nc`, nunca con `ping`.

### Balanceo del Service
Hoy los Pods sirven la página por defecto de nginx, así que el balanceo no se ve en el contenido. Cuando el `index.html` lleve el nombre del Pod (initContainer, D-003):
```bash
kubectl exec $ADMIN -- sh -c 'for i in $(seq 6); do curl -s -m 3 http://nginx-service | grep -i pod; done'
```

### SSH entre Pods
```bash
kubectl exec -it $ADMIN -- ssh -o StrictHostKeyChecking=no webuser@$WEB2_IP    # admin → web (cuando estén las claves, D-004)
```

---

## 4. Desde fuera del clúster (host)

El host (10.10.20.2) llega a `10.10.10.0/24` por `r1`.
```bash
curl -s -o /dev/null -w '%{http_code}\n' http://10.10.10.11:30001     # NodePort web en worker1 → 200
curl -s -o /dev/null -w '%{http_code}\n' http://10.10.10.12:30001     # y en worker2
kubectl get svc nginx-service -o jsonpath='{.spec.ports[0].nodePort}' # comprobar el nodePort asignado
```
Un NodePort responde en **todos** los nodos aunque el Pod esté en otro, salvo con `externalTrafficPolicy: Local` (previsto para el Service admin, todavía no está en el borrador), que solo responde en el nodo donde corre el Pod.

---

## 5. NetworkPolicies

Todavía no hay ninguna (`kubectl get netpol` → `No resources found`), así que ahora mismo **todo** está permitido. Cuando se añadan, repetir las pruebas de §3 para comprobar que se bloquea lo que debe y se permite lo que debe.
```bash
kubectl get netpol
kubectl describe netpol <nombre>           # podSelector, ingress/egress y peers tal como los entiende k8s
```

Recordatorios (más detalle en [Calico §4](../calico/guia-calico.md) y CLAUDE.md, "Gotchas"):
- Una NetworkPolicy no filtra ICMP por separado: si `ping` funciona y `curl` no, la regla está limitando puertos.
- Con *default-deny* de egress, `getent hosts nginx-service` falla si no se permite el DNS (53 UDP/TCP hacia `kube-dns`).
- La regla del web se escribe sobre el puerto del **Pod** (80), no sobre el del Service.

---

## 6. Ver el tráfico en los nodos

Si una prueba falla y no está claro dónde se pierde el paquete:
```bash
ssh root@k8s-worker1
ip route | grep -E 'cali|tunl0'            # rutas /32 de los Pods locales y bloques de otros nodos por IPIP
tcpdump -ni any host <ip-pod>              # ¿llega el paquete al nodo del Pod destino?
tcpdump -ni e1 ip proto 4                  # tráfico IPIP entre nodos
```

Para ver lo que sale de un Pod concreto, primero buscar su veth:
```bash
ip route | grep <ip-pod>                   # → <ip-pod> dev caliXXXX
tcpdump -ni caliXXXX
```
