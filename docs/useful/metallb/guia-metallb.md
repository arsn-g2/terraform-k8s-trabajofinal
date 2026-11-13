# 🧭 Guía: MetalLB e Ingress (de la práctica 1.3 al Trabajo Final)

⬅️ [Volver al plan](../../../plan.md) · Relacionado: [datos del escenario §5–6](../../datos-escenario.md#6-metallb) · [US-02](../../../historias/persona-a.md#us-02) · [US-15](../../../historias/persona-b.md#us-15) · [US-31](../../../historias/persona-b.md#us-31)

Lo que hicimos en la **práctica 1.3, §6** ("Servicio de tipo LoadBalancer y MetalLB") y **§7** ("Ingress"), y cómo se usa en el Trabajo Final. Van juntos porque el Ingress Controller es un Service `LoadBalancer` que depende de MetalLB.

📁 **Ficheros originales de P1.3** en [`p13/`](p13/), copiados del escenario `k8s_lab-flannel-v02`:
[`metallb-config.yaml`](p13/metallb-config.yaml) · [`config-pool.yaml`](p13/config-pool.yaml) · [`config-l2adv.yaml`](p13/config-l2adv.yaml) (de `conf/k8s/metallb/`) · [`service.yml`](p13/service.yml) · [`ingress.yml`](p13/ingress.yml) (de `examples/`)

> **Leyenda.** `⟪PENDIENTE: …⟫` = dato que no está en los ficheros (sale de nuestra memoria de P1.3). Lista en la [§8](#8-pendientes).

---

## 1. Para qué sirve

Un Service `LoadBalancer` pide una **IP externa**. En la nube la pone el proveedor; en un clúster *bare metal* como el nuestro no hay nadie que la dé, y el Service se queda en `EXTERNAL-IP <pending>`. MetalLB cubre ese hueco:

| Componente | Dónde corre | Qué hace |
|---|---|---|
| `controller` (Deployment, label `component=controller`) | 1 Pod | Elige una IP libre del **`IPAddressPool`** y se la asigna al Service |
| `speaker` (DaemonSet, label `component=speaker`) | 1 Pod por nodo | Anuncia la IP en la red. En modo **L2** responde a los ARP de esa IP. Por cada Service se elige **un speaker líder**, que recibe todo el tráfico y lo pasa a los Pods |

Hacen falta **dos objetos de configuración** en `metallb-system`: un `IPAddressPool` (qué IPs) y un `L2Advertisement` (anunciarlas por ARP). Sin ellos, MetalLB está instalado pero no hace nada.

---

## 2. MetalLB en la práctica 1.3

### 2.1 Configuración: la misma que hoy

Comparando los dos escenarios, la parte de MetalLB es **idéntica**:
- `conf/k8s/metallb/` tiene los mismos tres ficheros en `k8s_lab-flannel-v02` y en `k8s_lab-calico-v02`;
- en los dos XML, `k8s-master` recibe por `filetree` **solo** `metallb-config.yaml` (en `/root/k8s/`), y el `<exec seq="config_metallb">` hace lo mismo:

```bash
export KUBECONFIG='/root/.kube/config'
kubectl wait --namespace metallb-system --for=condition=available deployment/controller --timeout=180s
kubectl apply -f /root/k8s/metallb-config.yaml
```

Así que en P1.3 el pool era el mismo que tenemos ahora. [`metallb-config.yaml`](p13/metallb-config.yaml), sin comentarios:

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
    - 10.10.10.20-10.10.10.30
  autoAssign: true
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default-l2-advertisement
  namespace: metallb-system
spec:
  ipAddressPools:
    - default-pool
```

[`config-pool.yaml`](p13/config-pool.yaml) (pool `first-pool`, mismo rango) y [`config-l2adv.yaml`](p13/config-l2adv.yaml) (`L2Advertisement` `empty`, que sin `ipAddressPools` anuncia **todos** los pools) son una versión equivalente en dos ficheros que **ningún XML usa**. ⚠️ No apliquen las dos versiones: quedarían dos pools con el mismo rango.

### 2.2 Del NodePort al LoadBalancer

El Service de P1.3 ([`service.yml`](p13/service.yml)) era `NodePort`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
spec:
  type: NodePort
  ports:
    - protocol: TCP
      port: 8080
      targetPort: 80
      nodePort: 30001
  selector:
    app: nginx
```

La práctica pedía cambiarlo a `type: LoadBalancer` y **quitar `nodePort`**. Luego:

```bash
kubectl get pods -n metallb-system -o wide         # controller + un speaker por nodo
kubectl get ipaddresspool -n metallb-system        # default-pool 10.10.10.20-10.10.10.30
kubectl get svc                                    # EXTERNAL-IP asignada del pool
for i in 1 2 3 4 5 6; do curl -s http://<external-ip>:8080 | grep -i title; done   # balanceo
kubectl logs -n metallb-system -l component=speaker | grep <external-ip>             # speaker líder
```

⚠️ El PDF de P1.3 escribe `kubectl logs -n metallb …`: el namespace es **`metallb-system`**.

Lo que vimos (respuesta a R7 de nuestra memoria de P1.3):

```
⟪PENDIENTE: resumen de R7 — IP asignada, qué speaker/nodo era el líder, cómo se vio en los logs⟫
```

---

## 3. Ingress en la práctica 1.3

[`ingress.yml`](p13/ingress.yml) crea **dos** objetos:

```yaml
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: nginx-ingress-class
spec:
  controller: k8s.io/ingress-nginx
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx-ingress-class
  rules:
  - http:
      paths:
      - path: /servidores
        pathType: Prefix
        backend:
          service:
            name: nginx-service
            port:
              number: 8080
```

Lo que nos llevamos al Trabajo Final ([US-15](../../../historias/persona-b.md#us-15)):
- **`rewrite-target: /`**: sin ella Nginx recibe `/servidores` (o `/servers-G2`) y responde 404;
- `pathType: Prefix` y el backend por **nombre del Service y puerto del Service** (8080, no el 80 del Pod);
- la prueba se hace contra la **IP externa del Service del Ingress Controller** (`kubectl get svc -n ingress-nginx`), que es la que da MetalLB.

Lo que **no** copiamos: la `IngressClass` propia. El escenario ya trae la `IngressClass` **`nginx`** (la crea la instalación de ingress-nginx), así que usamos `ingress_class_name = "nginx"` y no creamos otra.

---

## 4. El escenario del Trabajo Final

| Dato | Valor |
|---|---|
| Versión | 0.16.1, instalada en la imagen del escenario con `metallb-native.yaml` |
| Pool | `default-pool`, `10.10.10.20-10.10.10.30`, dentro de `k8s_LAN` |
| Quién lo aplica | `<exec seq="config_metallb">` de `k8s_lab-calico.xml` (igual que en P1.3) |
| Quién lo usa | `ingress-nginx-controller` (tipo `LoadBalancer`), la entrada a `/servers-G2` |

### Por qué funciona desde el host

El host no está en `k8s_LAN`: llega a `10.10.10.0/24` por `r1`. Cuando el host hace `curl` a una IP del pool, `r1` pregunta por ARP en `k8s_LAN` "¿quién tiene 10.10.10.2x?", y responde el speaker líder con la MAC de su nodo:

```bash
ssh r1 ip neigh | grep 10.10.10.2
```

---

## 5. Arranque diario

Ya está en `scripts/host-script.sh`, después de `start-k8s-calico`:

```bash
sudo vnx -f k8s_lab-calico.xml -x config_metallb
```

Comprobación:

```bash
kubectl get ipaddresspools,l2advertisements -n metallb-system
kubectl get svc -n ingress-nginx ingress-nginx-controller      # EXTERNAL-IP en 10.10.10.20-30
curl http://<external-ip>/servers-G2
```

Si sigue sin pool, aplicarlo a mano:

```bash
ssh root@k8s-master kubectl apply -f /root/k8s/metallb-config.yaml
```

---

## 6. Problemas conocidos

| Síntoma | Causa probable / arreglo |
|---|---|
| `EXTERNAL-IP <pending>` y `kubectl get ipaddresspools -n metallb-system` vacío | La configuración no se aplicó (nos pasó el 13/11/2026 tras `start-k8s-calico`). Relanzar `config_metallb` ([§5](#5-arranque-diario)) |
| `kubectl apply` del pool falla con un error del *webhook* de MetalLB | Posible causa: el controller todavía no está listo. El `config_metallb` ya espera hasta 180 s; si aun así falla, esperar y repetir |
| IP asignada pero `curl` no responde | Mirar qué speaker es el líder (`kubectl logs -n metallb-system -l component=speaker \| grep <ip>`) y la tabla ARP de `r1` |
| Dos pools con el mismo rango | Se aplicaron `metallb-config.yaml` **y** `config-pool.yaml`. Borrar uno |
| `/servers-G2` devuelve 404 | Falta la anotación `rewrite-target: /` en el Ingress ([§3](#3-ingress-en-la-práctica-13)) |
| El Ingress no tiene `ADDRESS` | `ingressClassName` incorrecto: aquí es `nginx`, no `nginx-ingress-class` |
| ⟪PENDIENTE: problemas que nos salieron en P1.3⟫ | |

---

## 7. ¿Hace falta en el Trabajo Final?

- El enunciado **no pide** ningún Service `LoadBalancer` propio: el web es `ClusterIP` y el admin `NodePort`.
- Sí lo usamos **indirectamente**: el Ingress Controller es `LoadBalancer`, y su IP externa es la forma limpia de probar `/servers-G2` y de hacer la demo. Sin MetalLB se puede probar igual por el NodePort del Ingress (`http://10.10.10.11:30097/servers-G2`).
- La configuración de MetalLB es parte del **entorno** (la aplica VNX), no de nuestro Terraform. Si quisiéramos gestionarla con Terraform, sería con `kubernetes_manifest` y necesitaría una entrada en [decisions.md](../../../decisions.md).

---

## 8. Pendientes

- [ ] Resumen de la respuesta R7 de nuestra memoria de P1.3 ([§2.2](#22-del-nodeport-al-loadbalancer)).
- [ ] Problemas que nos encontramos en P1.3 ([§6](#6-problemas-conocidos)).
