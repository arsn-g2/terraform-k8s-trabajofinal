# 🧪 Pruebas de US-22 · Interfaz Multus en los Pods web

⬅️ [Guía web](guia-web.md) · Historia: [US-22](../../../historias/persona-b.md#us-22) · Antes: [pruebas de US-15](pruebas-us15.md) · Relacionado: [guía Multus](../multus/guia-multus.md)

Cómo comprobar, después de `terraform apply`, que los Pods web tienen una segunda interfaz `net1` en la VLAN y cumplen los 🧪 criterios de US-22. Se prueba **por capas**, de dentro hacia fuera: NAD → anotación → interfaz del Pod → IPs → VLAN. Así, si algo falla, sabes en qué capa está.

```
                        VlanNet (OVS) · VLAN 1000 · 10.1.2.0/24
        ┌─────────────────────┬──────────────────────┬──────────────────┐
  k8s-worker1 e2.1000   k8s-worker2 e2.1000   bbdd 10.1.2.100    logs 10.1.2.101
        │                     │
   Pod web (x2)          Pod web (x1)
   net1 10.1.2.1x        net1 10.1.2.1x      ← macvlan bridge, IP de whereabouts
   eth0 172.16.x.x       eth0 172.16.x.x     ← Calico: Service, Ingress, DNS
```

Requisito: las pruebas de [US-15](pruebas-us15.md) pasan (3 Pods `Running 2/2` detrás del Ingress).

---

## 0. Preparación

Los comandos `kubectl` se ejecutan desde el **host** (o desde `ssh root@k8s-master` si el `kubectl` del host falla por la diferencia de versión). Valores que usamos:

| Valor | De dónde sale |
|---|---|
| `g2-workshop` | `var.namespace` |
| `app=web` | `local.web_labels` |
| `nginx-server` | contenedor principal del Pod web |
| `vlan1000-web` | NAD de A en `terraform/multus.tf` (IPAM whereabouts, D-005) |
| `10.1.2.10`–`10.1.2.50` | `var.vlan_web_range_start` / `var.vlan_web_range_end` |
| `10.1.2.100`, `10.1.2.101` | `bbdd` y `logs` en `vnx/vnx-vm-bdd-logs.xml` |

En el host, cada día antes del `apply`:

```bash
./scripts/setup-vlan-workers.sh               # e2.1000 en los dos workers
./scripts/setup-whereabouts.sh                # plugin whereabouts en los nodos
sudo vnx -f vnx/vnx-vm-bdd-logs.xml --create  # LXC bbdd y logs (para los ping de §6)
```

En la VM `terraform`:

```bash
terraform plan               # 1 to change: el Deployment, solo la anotación
terraform apply
terraform output nad_web_name   # vlan1000-web
```

---

## 1. La NAD existe en el namespace de los Pods

```bash
kubectl get net-attach-def -n g2-workshop
kubectl get net-attach-def vlan1000-web -n g2-workshop -o jsonpath='{.spec.config}{"\n"}'
```

Qué esperar:
- `vlan1000-web` y `vlan1000-admin` en la lista;
- en el `config`: `"type":"macvlan"`, `"master":"e2.1000"`, `"mode":"bridge"` e `"ipam":{"type":"whereabouts", ...}`.

> **Por qué:** la anotación solo pone el nombre (`vlan1000-web`), y Multus lo busca en el namespace **del Pod**. Si la NAD estuviera en otro namespace, habría que escribir `<namespace>/vlan1000-web`.

---

## 2. La anotación está en el template del Pod

```bash
kubectl get deploy nginx-deployment -n g2-workshop -o jsonpath='{.spec.template.metadata.annotations}{"\n"}'
# esperado: {"k8s.v1.cni.cncf.io/networks":"vlan1000-web"}
kubectl get deploy nginx-deployment -n g2-workshop -o jsonpath='{.metadata.annotations}{"\n"}'
# aquí NO debe salir networks
```

> **Por qué:** Multus lo llama el kubelet al crear cada **Pod**, y lee las anotaciones del Pod. Las anotaciones del `metadata` exterior son del objeto Deployment y no se copian a sus Pods; solo se copia `template.metadata`. Si la pones fuera, el `apply` funciona, pero los Pods siguen sin `net1`.

---

## 3. Los Pods se recrean y Multus les da `net1`

```bash
kubectl rollout status deployment/nginx-deployment -n g2-workshop
kubectl get pods -n g2-workshop -l app=web -o wide
POD=$(kubectl get pod -n g2-workshop -l app=web -o jsonpath='{.items[0].metadata.name}'); echo $POD
kubectl get pod $POD -n g2-workshop -o jsonpath='{.metadata.annotations.k8s\.v1\.cni\.cncf\.io/network-status}{"\n"}'
```

Qué esperar:
- 3 Pods **nuevos** (`AGE` de segundos), `Running 2/2`, en los dos workers;
- en `network-status`, **dos** entradas: `eth0` con la IP de Calico (`172.16.x.x`, `"default": true`) y `net1` de `g2-workshop/vlan1000-web` con una IP `10.1.2.x`.

> **Por qué se recrean:** cambiar el `template` es una nueva versión del Deployment, así que se crea un ReplicaSet nuevo y los Pods se sustituyen uno a uno (rolling update). Las interfaces solo se crean **al arrancar** un Pod. Y `networks` es lo que **pides**, mientras que `network-status` lo escribe Multus con lo que **consiguió**: si solo sale `eth0`, Multus no pudo crear `net1` (ver 🩺).

### 3.1 Y `eth0` sigue siendo la interfaz de Kubernetes

```bash
kubectl get endpointslices -n g2-workshop -l kubernetes.io/service-name=nginx-service
```

Esperado: 3 IPs `172.16.x.x` en el puerto 80. **Ninguna** `10.1.2.x`.

> **Por qué:** Kubernetes solo conoce la IP de la interfaz principal (`status.podIP`). Services, Ingress y NetworkPolicies ignoran `net1`. Por eso la VLAN no se ve desde el Ingress, y Calico tampoco la filtra (US-33).

---

## 4. `net1` dentro del Pod

```bash
kubectl exec -n g2-workshop $POD -c nginx-server -- ip -4 addr show net1
kubectl exec -n g2-workshop $POD -c nginx-server -- ip -d link show net1 | grep macvlan
kubectl exec -n g2-workshop $POD -c nginx-server -- ip route
```

Qué esperar:
- `inet 10.1.2.x/24`, la misma IP que en `network-status`;
- `macvlan mode bridge`;
- en las rutas: `default via 169.254.1.1 dev eth0` y `10.1.2.0/24 dev net1 ... src 10.1.2.x`.

> **Por qué:** el kernel del Pod usa la ruta **más específica**. Lo que va a `10.1.2.0/24` sale por `net1` directamente a la VLAN, y todo lo demás por `eth0` hacia Calico (`169.254.1.1` es su puerta de enlace ficticia, [guía Calico](../calico/guia-calico.md)). Por eso añadir `net1` no cambia nada del Service ni del Ingress.

---

## 5. Las 3 IPs de `net1` son distintas (criterio principal)

```bash
for p in $(kubectl get pods -n g2-workshop -l app=web -o jsonpath='{.items[*].metadata.name}'); do
  node=$(kubectl get pod $p -n g2-workshop -o jsonpath='{.spec.nodeName}')
  ip=$(kubectl exec -n g2-workshop $p -c nginx-server -- ip -4 -o addr show net1 | awk '{print $4}')
  echo "$p  $node  $ip"
done
```

Esperado: 3 líneas, con Pods en `k8s-worker1` **y** `k8s-worker2`, y **3 IPs diferentes** dentro de `10.1.2.10`–`10.1.2.50`.

Dónde las guarda whereabouts:

```bash
kubectl get ippools.whereabouts.cni.cncf.io -A
kubectl get ippools.whereabouts.cni.cncf.io -A -o yaml | grep podref
```

Esperado: un `IPPool` para `10.1.2.0/24` con **3** `podref: g2-workshop/nginx-deployment-…`.

> **Por qué es lo importante:** con `host-local`, cada worker lleva su propio contador, y dos Pods en workers distintos acaban con la misma IP (se probó en US-19). whereabouts guarda las reservas en un objeto del API de Kubernetes, compartido por todos los nodos, así que nunca repite una IP (D-005).

---

## 6. Ping por la VLAN a `bbdd` y `logs`

```bash
kubectl exec -n g2-workshop $POD -c nginx-server -- ping -c2 10.1.2.100      # bbdd
kubectl exec -n g2-workshop $POD -c nginx-server -- ping -c2 10.1.2.101      # logs
kubectl exec -n g2-workshop $POD -c nginx-server -- ip route get 10.1.2.100  # ... dev net1
```

Esperado: `0% packet loss` en los dos, y la ruta por `dev net1`.

Y al revés, desde un LXC hacia el Pod (pon la IP de `net1` de §5):

```bash
sudo lxc-attach -n bbdd -- ping -c2 10.1.2.1x
```

> **Por qué funciona:** `macvlan` le da a `net1` su **propia MAC** sobre `e2.1000`. El worker etiqueta las tramas con VLAN 1000 al salir por `e2`, y el OVS `VlanNet` las entrega a los LXC, que están en puertos *access* con tag 1000. Para la VLAN, cada Pod es un equipo más conectado al switch.

### 6.1 Ping al admin: pendiente de US-24

```bash
kubectl exec -n g2-workshop $POD -c nginx-server -- ping -c2 -W2 10.1.2.5    # hoy: 100% packet loss
```

El criterio también pide ping al admin, pero el Pod admin aún no tiene la anotación de `vlan1000-admin` ([US-24](../../../historias/persona-c.md#us-24), de C). Marca esta casilla cuando esté. Es 🔀: pruébenlo juntos.

---

## 7. Ping entre Pods web de workers distintos

Elige en la tabla de §5 un Pod de cada worker:

```bash
kubectl exec -n g2-workshop <pod-worker1> -c nginx-server -- ping -c2 <ip-net1-pod-worker2>
```

Esperado: `0% packet loss`.

> **Por qué:** el tráfico sale del worker 1 por `e2.1000`, cruza `VlanNet` (los puertos de los workers son *trunk*) y entra en el worker 2 por su `e2.1000`. No pasa por Calico, ni por `eth0`, ni por el túnel entre nodos.

---

## 8. El Ingress sigue balanceando

```bash
IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}'); echo $IP
for i in $(seq 1 12); do curl -s http://$IP/servers-G2 | grep -o 'Pod: <b>[^<]*' | sed 's/.*<b>//'; done | sort | uniq -c
```

Esperado: los **3 nombres de los Pods nuevos** (§3), unos 4 cada uno.

> **Por qué:** es la prueba de [US-15 §7](pruebas-us15.md) repetida. Confirma que el rolling update terminó y que `net1` no ha tocado el camino Ingress → Service → `eth0`.

---

## 9. Un Pod nuevo recibe IP y la vieja se libera

```bash
kubectl delete pod -n g2-workshop $POD
kubectl get pods -n g2-workshop -l app=web -w      # Ctrl-C cuando el nuevo esté Running 2/2
```

Repite §5: siguen siendo **3 IPs distintas**, y el `IPPool` sigue con **3** `podref` (el del Pod borrado desaparece y aparece el del nuevo).

> **Por qué:** al borrar el Pod, el kubelet llama al CNI con `DEL` y whereabouts quita su reserva del `IPPool`. Si hubiera más `podref` que Pods, serían reservas huérfanas que ocupan IPs del rango.

---

## 🩺 Problemas típicos

| Síntoma | Dónde mirar | Causa probable |
|---|---|---|
| `terraform plan` dice `No changes` | §2 | El fichero no está guardado, o la VM ve otra copia del repo en `/shared` |
| `plan` dice `must be replaced` | diff del plan | Ha cambiado algo más que la anotación (por ejemplo el `selector`, que es inmutable) |
| Pods sin `net1` y `network-status` solo con `eth0` | §2 | La anotación está en el `metadata` del Deployment, no en el del `template` |
| Pods en `ContainerCreating` con `network-attachment-definitions … not found` | §1 | La NAD no existe o está en otro namespace |
| Pods en `ContainerCreating` con `failed to find plugin "whereabouts"` | `kubectl get ds -n kube-system \| grep whereabouts` | No se ejecutó `setup-whereabouts.sh` hoy |
| Pods en `ContainerCreating` con `Link not found` (`e2.1000`) | `ssh k8s-workerN ip link show e2.1000` | No se ejecutó `setup-vlan-workers.sh`. Si falta en un solo worker, fallan solo los Pods de ese nodo |
| Dos Pods con la misma IP de `net1` | §1 (`ipam.type`) | La NAD usa `host-local` en vez de `whereabouts` |
| `net1` existe pero no hay ping a `bbdd`/`logs` | §6, `sudo ovs-vsctl show` | LXC no creados, o sus puertos sin tag 1000 en `VlanNet` |
| El **worker** no hace ping al `net1` de sus propios Pods | — | Normal en macvlan: la interfaz padre (`e2.1000`) no habla con sus hijas macvlan. Prueba desde otro worker, un LXC u otro Pod |
| El Ingress da `503` justo después del `apply` | §3, §3.1 | El rolling update no ha terminado o los Pods nuevos no están `Ready` |

---

## ✅ Checklist para el PR (copiar en la descripción)

- [ ] `terraform fmt -check` y `terraform validate` pasan; `terraform plan` sin cambios tras `apply`
- [ ] La NAD `vlan1000-web` existe en `g2-workshop`, `macvlan` sobre `e2.1000` con IPAM `whereabouts` (§1)
- [ ] La anotación está en `spec.template.metadata`, no en el Deployment (§2)
- [ ] `network-status` de cada Pod muestra `eth0` y `net1` (§3); los endpoints del Service siguen en `eth0` (§3.1)
- [ ] `net1` tiene IP `10.1.2.x/24` y la ruta `10.1.2.0/24 dev net1` (§4)
- [ ] Los 3 Pods tienen IPs de `net1` **distintas**, con Pods en los dos workers (§5)
- [ ] Ping a `bbdd` (`10.1.2.100`) y `logs` (`10.1.2.101`) por `net1` (§6)
- [ ] Ping al admin (`10.1.2.5`), cuando esté [US-24](../../../historias/persona-c.md#us-24) (§6.1)
- [ ] Ping entre Pods web de workers distintos (§7)
- [ ] El Ingress sigue balanceando entre los 3 Pods (§8)
- [ ] Un Pod nuevo recibe IP de `net1` y el `IPPool` sigue con 3 reservas (§9)
