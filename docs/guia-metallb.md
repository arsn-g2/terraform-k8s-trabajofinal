# 🧭 Guía: MetalLB (de la práctica 1.3 al Trabajo Final)

⬅️ [Volver al plan](../plan.md) · Relacionado: [datos del escenario §6](datos-escenario.md#6-metallb) · [US-02](../historias/persona-a.md#us-02) · [US-15](../historias/persona-b.md#us-15)

Resumen de lo que hicimos con MetalLB en la **práctica 1.3, §6** ("Servicio de tipo LoadBalancer y MetalLB") y cómo se usa en el Trabajo Final.

> **Leyenda.** `⟪PENDIENTE: …⟫` = dato que hay que copiar del escenario de la práctica 1.3 (`/mnt/tmp/k8s_lab-flannel-v02`). La lista está en la [§7](#7-checklist-para-rellenar-los-pendientes).

---

## 1. Para qué sirve

Un Service `LoadBalancer` pide una **IP externa**. En la nube la pone el proveedor; en un clúster *bare metal* como el nuestro no hay nadie que la dé, y el Service se queda en `EXTERNAL-IP <pending>`. MetalLB cubre ese hueco:

| Componente | Dónde corre | Qué hace |
|---|---|---|
| `controller` (Deployment) | 1 Pod | Elige una IP libre del **`IPAddressPool`** y se la asigna al Service |
| `speaker` (DaemonSet) | 1 Pod por nodo | Anuncia la IP en la red. En modo **L2** responde a los ARP de esa IP. Por cada Service se elige **un speaker líder**, que recibe todo el tráfico y lo pasa a los Pods |

Hacen falta **dos objetos de configuración** en `metallb-system`: un `IPAddressPool` (qué IPs) y un `L2Advertisement` (anunciarlas por ARP). Sin ellos, MetalLB está instalado pero no hace nada.

---

## 2. Cómo se hizo en la práctica 1.3

En P1.3 MetalLB ya venía instalado **y configurado**; lo que hicimos fue usarlo:

```bash
kubectl get pods -n metallb-system -o wide         # controller + un speaker por nodo
kubectl get ipaddresspool -n metallb-system        # pool ya definido
```

| Dato en P1.3 | Valor |
|---|---|
| Nombre del pool | `⟪PENDIENTE⟫` |
| Rango | `⟪PENDIENTE⟫` |
| `L2Advertisement` | `⟪PENDIENTE: kubectl get l2advertisements -n metallb-system⟫` |

Luego cambiamos el Service del Deployment de nginx de `NodePort` a `LoadBalancer` (quitando el `nodePort`):

```yaml
⟪PENDIENTE: examples/service.yml en versión LoadBalancer, como lo dejamos⟫
```

y comprobamos el balanceo y qué speaker anunciaba la IP:

```bash
kubectl get svc                                    # EXTERNAL-IP asignada del pool
curl http://<external-ip>:<port>                   # desde el host, varias veces: cambia el Pod
kubectl logs -n metallb-system <speaker_pod>       # ⚠️ el PDF dice "-n metallb": el namespace es metallb-system
```

Lo que vimos (respuesta a R7 de la memoria de P1.3):

```
⟪PENDIENTE: resumen de R7 — IP asignada, qué speaker/nodo era el líder, cómo se vio en los logs⟫
```

---

## 3. MetalLB en el escenario del Trabajo Final

| Dato | Valor |
|---|---|
| Versión | 0.16.1, instalada en la imagen del escenario con `metallb-native.yaml` |
| Pool | `10.10.10.20-10.10.10.30`, dentro de `k8s_LAN` |
| Configuración | `conf/k8s/metallb/metallb-config.yaml` del escenario, copiado a `/root/k8s/` en `k8s-master` al arrancar |
| Quién lo aplica | el `<exec seq="config_metallb">` de `k8s_lab-calico.xml` |
| Quién lo usa | el Service `ingress-nginx-controller` (tipo `LoadBalancer`), que es la entrada a `/servers-G2` |

El fichero que se aplica (`metallb-config.yaml`) define:

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

En `conf/k8s/metallb/` hay además `config-pool.yaml` (pool `first-pool`, mismo rango) y `config-l2adv.yaml` (`L2Advertisement` `empty`, que anuncia todos los pools). Son una alternativa equivalente en dos ficheros; ⟪PENDIENTE: comprobar si es la que trae el escenario de P1.3⟫. **No apliquen las dos**: tendrían dos pools con el mismo rango.

### Por qué funciona desde el host

El host no está en `k8s_LAN`: llega a `10.10.10.0/24` por `r1`. Cuando el host hace `curl` a una IP del pool, `r1` pregunta por ARP en `k8s_LAN` "¿quién tiene 10.10.10.2x?", y responde el speaker líder con la MAC de su nodo. Se puede ver con:

```bash
ssh r1 ip neigh | grep 10.10.10.2
```

---

## 4. Arranque diario

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

## 5. Problemas conocidos

| Síntoma | Causa probable / arreglo |
|---|---|
| `EXTERNAL-IP <pending>` y `kubectl get ipaddresspools -n metallb-system` vacío | La configuración no se aplicó (nos pasó el 13/11/2026 tras `start-k8s-calico`). Relanzar `config_metallb` (§4) |
| `kubectl apply` del pool falla con un error del *webhook* de MetalLB | Posible causa: el controller todavía no está listo justo después de arrancar. Esperar a `kubectl wait -n metallb-system --for=condition=available deployment/controller` y repetir |
| IP asignada pero `curl` no responde | Mirar qué speaker es el líder (`kubectl logs -n metallb-system -l component=speaker \| grep <ip>`) y la tabla ARP de `r1` |
| Dos IPs del mismo rango en pools distintos | Se aplicaron `metallb-config.yaml` **y** `config-pool.yaml`. Borrar uno de los dos pools |
| ⟪PENDIENTE: problemas que salieron en P1.3⟫ | |

---

## 6. ¿Hace falta en el Trabajo Final?

- El enunciado **no pide** ningún Service `LoadBalancer` propio: el web es `ClusterIP` y el admin `NodePort`.
- Sí lo usamos **indirectamente**: el Ingress Controller es `LoadBalancer`, y su IP externa es la forma limpia de probar `/servers-G2` y de hacer la demo. Sin MetalLB se puede probar igual por el NodePort del Ingress (`http://10.10.10.11:30097/servers-G2`).
- La configuración de MetalLB es parte del **entorno** (la aplica VNX), no de nuestro Terraform. Si quisiéramos gestionarla con Terraform, sería con `kubernetes_manifest` y necesitaría una entrada en [decisions.md](../decisions.md).

---

## 7. Checklist para rellenar los pendientes

En el escenario de P1.3 (`/mnt/tmp/k8s_lab-flannel-v02`):

- [ ] `kubectl get ipaddresspool,l2advertisements -n metallb-system -o yaml` → nombre, rango y anuncio (§2).
- [ ] `ls conf/k8s/metallb/` en ese escenario: ¿trae `config-pool.yaml` + `config-l2adv.yaml` o `metallb-config.yaml`? (§3).
- [ ] Copiar `examples/service.yml` en su versión `LoadBalancer` (§2).
- [ ] Resumen de la respuesta R7 de nuestra memoria de P1.3 (§2).
- [ ] Cualquier error que nos encontráramos entonces (§5).
