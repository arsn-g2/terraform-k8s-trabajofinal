# 🧪 Pruebas de US-18 · Service NodePort del admin

Historia: [US-18](../../../historias/persona-c.md#us-18) · Antes: [US-17](../../../historias/persona-c.md#us-17) · Relacionado: [claves SSH §5.1](../../ssh-keys.md#51-host--admin-par-2) · Después: [US-32](../../../historias/persona-c.md#us-32)

Cómo comprobar, después de `terraform apply`, que el Service del admin cumple el 🧪 criterio de US-18. Se prueba **por capas**, de dentro hacia fuera: Pod → Service (ClusterIP) → NodePort → host. Así, si algo falla, sabes en qué capa está.

```
host 10.10.20.2 ──r1 (sin NAT)──► 10.10.10.11:30002 (NodePort, k8s-worker1)
                                          │  externalTrafficPolicy: Local → sin SNAT
                                          ▼
                                 admin-service:2222 (ClusterIP)
                                          │
                                          ▼
                                 Pod admin :22 (sshd, k8s-worker1)

                  10.10.10.12:30002 (k8s-worker2) ──✗ sin endpoint local → se descarta
```

Requisito: las pruebas de [US-17](../../../historias/persona-c.md#us-17) pasan (Pod admin `Running` en `k8s-worker1`, `sshd` activo, claves montadas) y existen `keys/par2_host` y `keys/par2_host.pub` de hoy (`scripts/gen-keys.sh`).

---

## 0. Preparación

Desde el **host** (o desde `ssh root@k8s-master` si el `kubectl` del host falla por la diferencia de versión), en la raíz del repo:

```bash
NS=g2-workshop               # var.namespace
LBL='app=admin'              # local.admin_labels
SVC=admin-service            # Service del admin
NP=30002                     # node_port (terraform output admin_service_node_port)
KEY=keys/par2_host           # privada del par 2: host → admin
```

En la VM `terraform`:

```bash
terraform plan                             # "No changes"
terraform output admin_service_node_port   # 30002
terraform output admin_service_type        # "NodePort"
```

---

## 1. El Service es `NodePort` en 2222 → 22

```bash
kubectl get svc $SVC -n $NS -o wide
```

Qué esperar:
- `TYPE NodePort`, `EXTERNAL-IP <none>`;
- `PORT(S) 2222:30002/TCP`;
- `SELECTOR app=admin`.

```bash
kubectl get svc $SVC -n $NS -o jsonpath='{.spec.ports[0].port} -> {.spec.ports[0].targetPort} (nodePort {.spec.ports[0].nodePort}){"\n"}'
# esperado: 2222 -> 22 (nodePort 30002)
```

> **Por qué:** hay tres puertos distintos. `targetPort` es el del **contenedor** (donde escucha `sshd`: 22). `port` es el de la **ClusterIP** del Service, que solo se usa dentro del clúster (2222, lo pide el enunciado). `nodePort` se abre en la IP de **cada nodo** (rango 30000–32767) y es el que usas desde el host.

---

## 2. `externalTrafficPolicy` es `Local`

```bash
kubectl get svc $SVC -n $NS -o jsonpath='{.spec.externalTrafficPolicy}{"\n"}'
# esperado: Local
```

> **Por qué:** con `Cluster` (el valor por defecto), un nodo puede reenviar el paquete a un Pod de **otro** nodo, y para que la respuesta vuelva por él hace **SNAT**: cambia la IP de origen por la suya. Con `Local` solo reenvía a Pods de **ese mismo** nodo y no hace SNAT, así que el Pod ve la IP real del cliente. La NetworkPolicy de [US-32](../../../historias/persona-c.md#us-32) (`ipBlock 10.10.20.2/32`) depende de esto.

---

## 3. El Service encuentra el Pod (endpoints)

```bash
kubectl get endpointslices -n $NS -l kubernetes.io/service-name=$SVC
kubectl get pods -n $NS -l $LBL -o wide            # compara la IP y mira la columna NODE
```

Esperado: **1 IP**, puerto **22**, la misma que la columna `IP` del Pod, y el Pod en `NODE k8s-worker1`.

> **Por qué:** el Service busca los Pods que cumplen el `selector` **en el mismo namespace** y que están `Ready`. Si sale vacío (`<unset>`), el selector, el namespace o el readiness no cuadran, y todas las pruebas siguientes fallarán con timeout.

---

## 4. El Service funciona dentro del clúster (ClusterIP)

Desde un Pod temporal, por nombre DNS y puerto 2222:

```bash
kubectl run tmp-nc -n $NS --rm -it --restart=Never --image=busybox -- \
  sh -c "echo | nc -w 3 $SVC 2222"
```

Esperado: el banner de `sshd`, algo como `SSH-2.0-OpenSSH_9.x`.

> **Por qué:** `nc` abre una conexión TCP y muestra lo primero que manda el servidor. SSH empieza siempre con ese banner, así que comprueba `port` → `targetPort` → `sshd` sin necesitar claves. Funciona porque todavía no hay NetworkPolicies (llegan en [US-30](../../../historias/persona-c.md#us-30)).

---

## 5. SSH desde el host por `k8s-worker1` (criterio principal)

```bash
ssh -i $KEY -p $NP adminuser@10.10.10.11
```

Esperado: entra **sin pedir contraseña** y el prompt es de `adminuser` en el Pod (`hostname` devuelve `admin-deployment-…`).

Para ver qué clave se ofrece y cuál se acepta:

```bash
ssh -v -i $KEY -p $NP adminuser@10.10.10.11 exit 2>&1 | grep -E "Connecting to|Offering|Server accepts|Authenticated"
```

Esperado: `Offering public key: keys/par2_host ED25519 …`, `Server accepts key` y `Authenticated to 10.10.10.11 ([10.10.10.11]:30002) using "publickey"`.

> **Por qué funciona desde el host:** el host (10.10.20.2) llega a `10.10.10.0/24` por `r1`. El paquete entra en worker1 por el puerto 30002, kube-proxy lo traduce (DNAT) a `<IP del Pod>:22` y `sshd` valida la clave contra `~/.ssh/authorized_keys`, que viene del Secret `ssh-admin-authorized` (`keys/par2_host.pub`).

---

## 6. El Pod ve la IP real del host

Dentro de la sesión SSH del §5:

```bash
echo $SSH_CONNECTION
# esperado: 10.10.20.2 <puerto> <IP del Pod> 22
```

O en una sola línea desde el host:

```bash
ssh -i $KEY -p $NP adminuser@10.10.10.11 'echo $SSH_CONNECTION'
```

> **Por qué:** `SSH_CONNECTION` es `IP-cliente puerto-cliente IP-servidor puerto-servidor` tal como lo ve `sshd`. Que salga `10.10.20.2` (y no `10.10.10.11` u otra IP de nodo) demuestra que no hubo SNAT: es el efecto de `Local` del §2 y de que `r1` no haga NAT.

### 6.1 Opcional: comparar con `Cluster`

Para ver la diferencia (y luego volver al estado de Terraform):

```bash
kubectl patch svc $SVC -n $NS -p '{"spec":{"externalTrafficPolicy":"Cluster"}}'
ssh -i $KEY -p $NP adminuser@10.10.10.11 'echo $SSH_CONNECTION'   # ahora sale una IP del nodo, no 10.10.20.2
```

Después, en la VM `terraform`: `terraform plan` muestra el cambio (`Cluster` → `Local`, es la deriva que has provocado) y `terraform apply` lo deshace.

---

## 7. Por `k8s-worker2` **no** funciona

```bash
ssh -i $KEY -p $NP -o ConnectTimeout=5 adminuser@10.10.10.12
# esperado: Connection timed out
```

> **Por qué:** con `Local`, worker2 solo reenviaría a un Pod admin **en worker2**, y no hay ninguno (el `nodeSelector` lo fija en worker1). En vez de mandarlo a otro nodo, descarta el paquete, y por eso es un timeout y no un `connection refused`. Es el comportamiento esperado: el enunciado dice que el SSH va **solo** a `10.10.10.11:<nodePort>`.

Para verlo por dentro (si kube-proxy está en modo iptables):

```bash
ssh root@k8s-worker2 "iptables-save | grep admin-service"
# esperado: una regla con el comentario "... has no local endpoints" y -j DROP
```

---

## 🩺 Problemas típicos

| Síntoma | Dónde mirar | Causa probable |
|---|---|---|
| `Connection refused` en `10.10.10.11:30002` | §1, §4 | `targetPort` no es 22, o `sshd` no está corriendo en el Pod |
| `Connection timed out` en `10.10.10.11:30002` | §3, `kubectl get netpol -n $NS` | Sin endpoints (selector, namespace o Pod no `Ready`), el Pod no está en worker1, o hay una NetworkPolicy que bloquea |
| `Permission denied (publickey)` | §5 con `ssh -v`, pruebas de US-17 | La red funciona y falla la clave: `-i` equivocado, claves de otro día (repetir `gen-keys.sh` + `terraform apply`), o permisos de `~/.ssh/authorized_keys` en el Pod |
| Pide contraseña | §5 con `ssh -v` | No ha ofrecido la clave: falta `-i` o el fichero no existe |
| `UNPROTECTED PRIVATE KEY FILE!` | `ls -l keys/` | La privada no es `600` (ver [claves SSH](../../ssh-keys.md)) |
| `REMOTE HOST IDENTIFICATION HAS CHANGED!` | `~/.ssh/known_hosts` | El Pod es nuevo y tiene otra host key: `ssh-keygen -R '[10.10.10.11]:30002'` |
| `$SSH_CONNECTION` no muestra `10.10.20.2` | §2 | `externalTrafficPolicy` es `Cluster` (o alguien lo ha cambiado: `terraform plan`) |
| `terraform apply` falla con `provided port is already allocated` | `kubectl get svc -A \| grep 30002` | Otro Service usa ya ese `node_port` |
| `terraform apply` falla con `provided port is not in the valid range` | `node_port` | Tiene que estar entre 30000 y 32767 |

---

## ✅ Checklist para el PR (copiar en la descripción)

- [ ] `terraform fmt -check` y `terraform validate` pasan; `terraform plan` sin cambios tras `apply`
- [ ] Service `NodePort`, `2222 → 22`, `nodePort 30002`, selector `app=admin` (§1)
- [ ] `externalTrafficPolicy: Local` (§2)
- [ ] El Service tiene 1 endpoint en el puerto 22, Pod en `k8s-worker1` (§3)
- [ ] El Service responde dentro del clúster con el banner SSH (§4)
- [ ] `ssh -i keys/par2_host -p 30002 adminuser@10.10.10.11` entra con clave, sin contraseña (§5)
- [ ] `$SSH_CONNECTION` muestra `10.10.20.2` como origen (§6)
- [ ] Por `10.10.10.12:30002` da timeout (§7)
