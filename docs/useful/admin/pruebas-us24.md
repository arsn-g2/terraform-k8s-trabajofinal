# 🧪 Pruebas de US-24 · SSH desde el admin por la VLAN

Historia: [US-24](../../../historias/persona-c.md#us-24) · Antes: [pruebas de US-18](pruebas-us18.md), [pruebas de US-22](../web/pruebas-us22.md) · Relacionado: [claves SSH](../../ssh-keys.md), [guía Multus](../multus/guia-multus.md) · Después: [US-32](../../../historias/persona-c.md#us-32)

Cómo comprobar, después de `terraform apply`, que el Pod admin tiene una segunda interfaz `net1` con la IP fija `10.1.2.5` y que entra por SSH, sin contraseña, en los 3 Pods web y en los 2 LXC usando las IPs de la VLAN. Se prueba **por capas**, de dentro hacia fuera: NAD → anotación → interfaz del Pod → ping → SSH. Así, si algo falla, sabes en qué capa está.

```
                        VlanNet (OVS) · VLAN 1000 · 10.1.2.0/24
        ┌─────────────────────┬──────────────────────┬──────────────────┐
  k8s-worker1 e2.1000   k8s-worker2 e2.1000   bbdd 10.1.2.100    logs 10.1.2.101
        │                     │
   Pod admin             Pod web (x1)
   net1 10.1.2.5         net1 10.1.2.1x      ← macvlan bridge
   (IPAM static)         (whereabouts)
   Pod web (x2)
   net1 10.1.2.1x

   admin ──ssh (par 1)──► webuser@10.1.2.1x  ·  root@10.1.2.100  ·  root@10.1.2.101
```

Requisitos:
- las pruebas de [US-17](../../../historias/persona-c.md#us-17) pasan (Pod admin `Running` en `k8s-worker1`, claves montadas);
- las de [US-22](../web/pruebas-us22.md) pasan (3 Pods web con `net1`);
- `bbdd` y `logs` están creados (US-20, US-21).

⚠️ **La política de denegación por defecto de US-30 está aplicada.** Hasta que esté US-32, el SSH del host al admin por el NodePort no funciona, así que aquí se entra en el admin con `kubectl exec`, que va por el API server y el kubelet y no pasa por las NetworkPolicies. El tráfico por `net1` no lo filtra Calico, así que el SSH por la VLAN **debería funcionar igual** con la denegación aplicada (lo comprobamos en §8).

---

## 0. Preparación

Los comandos se ejecutan desde el **host**, en la raíz del repo (o desde `ssh root@k8s-master` si el `kubectl` del host falla por la diferencia de versión). Valores que usamos:

| Valor | De dónde sale |
|---|---|
| `g2-workshop` | `var.namespace` |
| `app=admin`, `admin-deployment` | `local.admin_labels`, Deployment en `admin-service-deployment.tf` |
| `admin-server` | contenedor del Pod admin |
| `vlan1000-admin` | NAD de A en `terraform/multus.tf` (IPAM static, D-005) |
| `10.1.2.5` | `var.vlan_admin_ip` |
| `10.1.2.10`–`10.1.2.50` | rango de los web (whereabouts) |
| `10.1.2.100`, `10.1.2.101` | `bbdd` y `logs` en `vnx/vnx-vm-bdd-logs.xml` |
| `/home/adminuser/.ssh/id_ed25519` | privada del par 1 (Secret `ssh-admin-private`, modo `0440`) |

En el host, cada día antes del `apply`:

```bash
./scripts/gen-keys.sh                         # claves de hoy (también en vnx/filetree/ssh/)
./scripts/setup-vlan-workers.sh               # e2.1000 en los dos workers
./scripts/setup-whereabouts.sh                # IPAM de los web
sudo vnx -f vnx/vnx-vm-bdd-logs.xml --create  # LXC bbdd y logs, con el authorized_keys de hoy
```

En la VM `terraform`:

```bash
terraform plan
terraform apply
```

Variables y funciones de ayuda para el resto de la guía (en el host):

```bash
NS=g2-workshop
ADMIN=$(kubectl get pod -n $NS -l app=admin -o jsonpath='{.items[0].metadata.name}'); echo $ADMIN
adm() { kubectl exec -n $NS "$ADMIN" -c admin-server -- "$@"; }
SSH='ssh -i /home/adminuser/.ssh/id_ed25519 -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'

adm id        # ¿con qué usuario entra kubectl exec?
```

Según la salida de `adm id`, define **una** de estas dos:

```bash
# si sale uid=1000(adminuser):
ssh_adm() { adm $SSH "$@"; }
# si sale uid=0(root):
ssh_adm() { adm su adminuser -s /bin/sh -c "$SSH $(printf '%q ' "$@")"; }
```

> El `printf '%q '` vuelve a poner comillas a cada argumento. Con `$*` a secas se pierden: `'hostname; id -un'` llegaría como `hostname; id -un` y el `;` haría que `id -un` se ejecutara **en el admin** (saldría `adminuser`) y no en el destino.

> **Por qué estas opciones de `ssh`:**
> - `BatchMode=yes`: si la clave no vale, `ssh` **falla** en vez de pedir contraseña. Así la prueba demuestra el "sin contraseña" del criterio.
> - `StrictHostKeyChecking=no` y `UserKnownHostsFile=/dev/null`: los Pods web se recrean con claves de host nuevas, y whereabouts puede reutilizar una IP. Si guardáramos `known_hosts`, el segundo intento daría `REMOTE HOST IDENTIFICATION HAS CHANGED`.
> - `su adminuser` si entras como root: la privada está montada como `root:1000` con modo `0440`. Si `ssh` se ejecuta como root, ve que es **dueño** de una privada que el grupo puede leer y la rechaza (`UNPROTECTED PRIVATE KEY FILE`). Como `adminuser` no es el dueño, `ssh` no se queja, y la puede leer gracias al grupo 1000 (`fsGroup`).

Para guardar la salida de las pruebas en la captura de la historia, añade `| tee -a docs/capturas/us-24-ssh.txt` a los comandos de §6 y §7.

---

## 1. La NAD del admin existe y usa IPAM `static`

```bash
kubectl get net-attach-def -n $NS
kubectl get net-attach-def vlan1000-admin -n $NS -o jsonpath='{.spec.config}{"\n"}'
```

Qué esperar:
- `vlan1000-admin` (y `vlan1000-web`) en la lista;
- en el `config`: `"type":"macvlan"`, `"master":"e2.1000"`, `"mode":"bridge"`, `"capabilities":{"ips":true}` e `"ipam":{"type":"static"}`, **sin** ninguna dirección.

> **Por qué no hay IP en la NAD:** con `capabilities.ips`, Multus coge la IP que pide el Pod en su anotación y se la pasa al plugin `static` como argumento. La misma NAD serviría para varios Pods con IPs fijas distintas. Sin esa *capability*, el plugin `static` no recibe ninguna IP y falla.

---

## 2. La anotación y la estrategia del Deployment

```bash
kubectl get deploy admin-deployment -n $NS -o jsonpath='{.spec.template.metadata.annotations}{"\n"}'
# esperado: {"k8s.v1.cni.cncf.io/networks":"[{\"ips\":[\"10.1.2.5/24\"],\"name\":\"vlan1000-admin\"}]"}
kubectl get deploy admin-deployment -n $NS -o jsonpath='{.spec.strategy.type}{"\n"}'
# esperado: Recreate
```

> **Por qué JSON y no el nombre a secas** (como en los web): el formato corto `vlan1000-admin` solo dice qué red. Para pedir además una IP hace falta el formato largo, una lista de objetos JSON, que en Terraform se genera con `jsonencode`. La IP lleva el prefijo (`/24`): sin él, `static` no sabría la máscara y no crearía la ruta `10.1.2.0/24 dev net1`.

---

## 3. El Pod admin tiene `net1` con `10.1.2.5`

```bash
kubectl get pod -n $NS -l app=admin -o wide
kubectl get pod $ADMIN -n $NS -o jsonpath='{.metadata.annotations.k8s\.v1\.cni\.cncf\.io/network-status}{"\n"}'
```

Qué esperar:
- 1 Pod `Running` en `k8s-worker1` (el `nodeSelector` de US-17);
- en `network-status`, **dos** entradas: `eth0` con la IP de Calico (`172.16.x.x`, `"default": true`) y `net1` de `g2-workshop/vlan1000-admin` con `10.1.2.5`.

> **Por qué:** `networks` es lo que el Pod **pide** y `network-status` lo que Multus **consiguió**. Si aquí solo sale `eth0`, Multus no pudo crear `net1`: mira los eventos del Pod (ver 🩺).

---

## 4. `net1` dentro del Pod admin

```bash
adm ip -4 addr show net1
adm ip -d link show net1 | grep macvlan
adm ip route
```

Qué esperar:
- `inet 10.1.2.5/24`;
- `macvlan mode bridge`;
- `default via 169.254.1.1 dev eth0` y `10.1.2.0/24 dev net1 ... src 10.1.2.5`.

> **Por qué:** igual que en los web (US-22 §4), el kernel usa la ruta más específica: lo que va a la VLAN sale por `net1` y el resto por `eth0` hacia Calico. Si la imagen del admin no trae `ip` (`executable file not found`), basta con la salida de §3.

---

## 5. Ping por la VLAN (cierra el pendiente de US-22)

Las IPs de `net1` de los web, de US-22 §5:

```bash
for p in $(kubectl get pods -n $NS -l app=web -o jsonpath='{.items[*].metadata.name}'); do
  echo "$p  $(kubectl exec -n $NS $p -c nginx-server -- ip -4 -o addr show net1 | awk '{print $4}')"
done
WEB_IPS="10.1.2.1x 10.1.2.1y 10.1.2.1z"   # ← pon aquí las 3 IPs, sin el /24
```

De un web al admin (es la casilla de [US-22 §6.1](../web/pruebas-us22.md#61-ping-al-admin-pendiente-de-us-24)):

```bash
WEB=$(kubectl get pod -n $NS -l app=web -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n $NS $WEB -c nginx-server -- ping -c2 10.1.2.5
```

Del admin a los LXC (si la imagen trae `ping`):

```bash
adm ping -c2 10.1.2.100
adm ping -c2 10.1.2.101
```

Esperado: `0% packet loss` en todos.

> **Por qué antes del SSH:** si no hay ping, el problema es de red (capa 2/3: `e2.1000`, tags del OVS, IP) y no de claves. Si hay ping pero el SSH falla, el problema está en `sshd` o en las claves.

---

## 6. SSH del admin a los 3 Pods web (criterio)

```bash
for ip in $WEB_IPS; do echo "### admin -> webuser@$ip"; ssh_adm webuser@$ip 'hostname; id -un'; done
```

Esperado, para cada IP: el **nombre de un Pod web** (`nginx-deployment-…`, los 3 distintos) y `webuser`. Ningún `Permission denied` ni petición de contraseña.

> **Por qué funciona:** el admin presenta la privada del par 1, y cada Pod web tiene la pública del par 1 en `~/.ssh/authorized_keys` (Secret `ssh-web-authorized`, US-17). `hostname` demuestra que has entrado en el Pod que corresponde a esa IP, y no en otro.

---

## 7. SSH del admin a `bbdd` y `logs` (criterio)

```bash
for ip in 10.1.2.100 10.1.2.101; do echo "### admin -> root@$ip"; ssh_adm root@$ip 'hostname; id -un'; done
```

Esperado: `bbdd` y `root`, y luego `logs` y `root`.

> **Por qué funciona:** la misma pública del par 1 la copió `gen-keys.sh` a `vnx/filetree/ssh/authorized_keys`, y el `<filetree>` de VNX la instaló en `/root/.ssh/` de los dos LXC al crearlos. Por eso, si regeneras las claves, hay que **volver a crear los LXC**: los que ya existen siguen con la pública vieja.

---

## 8. Contraste: por `eth0` el SSH está bloqueado

Las IPs de Calico de los web:

```bash
kubectl get pods -n $NS -l app=web -o wide          # columna IP: 172.16.x.x
ssh_adm webuser@172.16.x.x hostname                 # ← una de ellas
```

Esperado: `Connection timed out` (después de los 5 s de `ConnectTimeout`).

> **Por qué:** es el mismo destino y la misma clave que en §6, pero esta vez por `eth0`. La política `default-deny-all` (US-30) bloquea la salida del admin y la entrada al web en `eth0`, y Calico solo controla esa interfaz. `net1` es una macvlan que va directa a `e2.1000`, sin pasar por las reglas de Calico. Esto demuestra que el SSH de §6 y §7 va **por la VLAN**, y es lo que hay que tener en cuenta en US-33: las NetworkPolicies no protegen la VLAN.

---

## 9. Un rollout no duplica la IP fija

```bash
kubectl rollout restart deployment/admin-deployment -n $NS
kubectl get pods -n $NS -l app=admin -w     # Ctrl-C cuando el nuevo esté Running
```

Esperado: el Pod viejo pasa a `Terminating` y **desaparece antes** de que se cree el nuevo. Nunca hay dos Pods admin a la vez. Repite §3 con el Pod nuevo: vuelve a tener `net1` con `10.1.2.5`.

```bash
ADMIN=$(kubectl get pod -n $NS -l app=admin -o jsonpath='{.items[0].metadata.name}'); echo $ADMIN
```

> **Por qué:** con `RollingUpdate` el nuevo arrancaría antes de borrar el viejo, y los dos tendrían `10.1.2.5` en la VLAN a la vez: dos MAC distintas respondiendo a la misma IP, y el ARP de los web y los LXC acertaría o no según cuál contestara antes. `Recreate` evita eso, pero **solo en los rollouts** (cambios del `template`, `rollout restart`). Si haces `kubectl delete pod`, el ReplicaSet crea el sustituto enseguida, sin esperar a que el viejo termine, y puede haber unos segundos con la IP duplicada.

---

## 🩺 Problemas típicos

| Síntoma | Dónde mirar | Causa probable |
|---|---|---|
| Pod admin en `ContainerCreating` y `kubectl describe pod` con `network-attachment-definitions … not found` | §1 | La NAD no existe o está en otro namespace |
| `ContainerCreating` con un error del plugin `static` (sin IP) | §1, §2 | La NAD no tiene `capabilities.ips`, o la anotación no lleva `ips` |
| `ContainerCreating` con `Link not found` (`e2.1000`) | `ssh k8s-worker1 ip link show e2.1000` | No se ejecutó `setup-vlan-workers.sh` hoy |
| `network-status` solo con `eth0` | §2 | La anotación no está en el `metadata` del `template` |
| `net1` existe pero no hay ping | §5, `sudo ovs-vsctl show` | LXC no creados, o puertos sin tag 1000 en `VlanNet` |
| `UNPROTECTED PRIVATE KEY FILE` | §0, `adm id` | `ssh` se está ejecutando como root: usa la variante con `su adminuser` |
| `Permission denied (publickey)` a un web | `kubectl exec <web> -c nginx-server -- cat /home/webuser/.ssh/authorized_keys` | El Secret `ssh-web-authorized` tiene otra pública: no se volvió a hacer `apply` después de `gen-keys.sh` |
| `Permission denied (publickey)` a `bbdd`/`logs` | `sudo lxc-attach -n bbdd -- cat /root/.ssh/authorized_keys` | Los LXC se crearon con las claves de otro día: `--destroy` y `--create` |
| `Connection refused` a un LXC | `sudo lxc-attach -n bbdd -- ss -tlnp \| grep :22` | `sshd` no arrancado en el LXC |
| `Connection timed out` por la VLAN | §5 | Problema de red, no de SSH: vuelve a §4 y §5 |
| Pings que fallan a ratos al `10.1.2.5` | `kubectl get pods -n $NS -l app=admin` | Dos Pods admin a la vez (ver §9) |

---

## ✅ Checklist para el PR (copiar en la descripción)

- [ ] `terraform fmt -check` y `terraform validate` pasan; `terraform plan` sin cambios tras `apply`
- [ ] La NAD `vlan1000-admin` existe, con `macvlan` sobre `e2.1000`, `capabilities.ips` e IPAM `static` (§1)
- [ ] La anotación del `template` pide `vlan1000-admin` con `10.1.2.5/24`, y la estrategia es `Recreate` (§2)
- [ ] `network-status` del admin muestra `eth0` y `net1` con `10.1.2.5`, en `k8s-worker1` (§3, §4)
- [ ] Ping de un web al admin (`10.1.2.5`) y del admin a `bbdd` y `logs` (§5)
- [ ] `ssh webuser@<ip-vlan-web>` desde el admin entra sin contraseña en los 3 Pods web (§6)
- [ ] `ssh root@10.1.2.100` y `ssh root@10.1.2.101` desde el admin entran sin contraseña (§7)
- [ ] Por `eth0` el SSH al web da timeout con la denegación por defecto (§8)
- [ ] `rollout restart` no deja nunca dos Pods admin, y el nuevo vuelve a tener `10.1.2.5` (§9)
- [ ] Salida guardada en `docs/capturas/us-24-ssh.txt`
