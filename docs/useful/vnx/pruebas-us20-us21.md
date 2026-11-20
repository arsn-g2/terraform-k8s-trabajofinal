# 🧪 Pruebas de US-20 y US-21 · MySQL en `bbdd` y rsyslog en `logs`

Historias: [US-20](../../../historias/persona-a.md#us-20) · [US-21](../../../historias/persona-a.md#us-21) · Decisiones: [D-006](../../../decisions.md) (rsyslog), [D-012](../../../decisions.md) (MySQL en vez de MariaDB) · Escenario: [datos-escenario §9](../../datos-escenario.md)

Cómo comprobar, después de `vnx --create`, que los LXC `bbdd` y `logs` cumplen los 🧪 criterios de US-20 y US-21. Se prueba **por capas**: primero **dentro** del LXC (¿se instaló y arrancó el servicio?), después **desde la VLAN** (¿se llega por red?) y por último **desde un Pod** con `net1` (el criterio de la historia). Así, si algo falla, sabes si el problema es el servicio, la VLAN o Multus.

```
                     VlanNet (OVS) · VLAN 1000 · 10.1.2.0/24
  ┌──────────────────────┬────────────────────────┬──────────────────────────┐
  │ trunk                │ trunk                  │ access tag 1000          │ access tag 1000
k8s-worker1           k8s-worker2              bbdd (eth1)                logs (eth1)
 e2.1000                e2.1000                10.1.2.100                 10.1.2.101
  └─ Pod tmp-vlan                               mysqld :3306               rsyslog :514 UDP/TCP
     net1 10.1.2.10-50 (macvlan, whereabouts)   sshd :22                   sshd :22
```

---

## 0. Preparación

Todo desde el **host**, en `/mnt/tmp/k8s_lab-calico-v03/shared/terraform-k8s-trabajofinal`. Valores que usamos:

| Valor | De dónde sale |
|---|---|
| `bbdd` `10.1.2.100`, `logs` `10.1.2.101` | `vnx/vnx-vm-bdd-logs.xml` |
| `appdb`, `appuser`@`10.1.2.%` | `vnx/filetree/bbdd/init.sql` |
| `keys/par1_admin` | clave privada del par 1, la que va en `authorized_keys` de los LXC ([D-004](../../../decisions.md)) |
| `g2-workshop`, `vlan1000-web` | `var.namespace` y la NAD de `terraform/multus.tf` |

**El orden importa.** Los LXC copian los ficheros del `filetree` **al crearse**, así que todo lo que copian tiene que existir antes del `--create`:

```bash
./scripts/gen-keys.sh                 # 1. claves del día → vnx/filetree/ssh/authorized_keys
cp vnx/filetree/bbdd/init.sql.example vnx/filetree/bbdd/init.sql
nano vnx/filetree/bbdd/init.sql       # 2. cambia __CAMBIA_ESTA_PASSWORD__ (init.sql no se sube a Git)
./scripts/setup-vlan-workers.sh       # 3. e2.1000 en los workers
sudo vnx -f vnx/vnx-vm-bdd-logs.xml --create
```

> **Por qué este orden:** si `gen-keys.sh` corre **después** del `--create`, los LXC tienen la clave pública de ayer y el SSH con `par1_admin` falla. Si falta `init.sql`, el `<filetree>` no copia nada y el `mysql -e "source /root/init.sql"` del `<exec>` falla: MySQL funciona, pero sin base de datos ni usuario.

⚠️ El `<exec>` hace `apt-get install` por `eth9` (`virbr0`) y tarda unos minutos. Espera a que termine antes de seguir.

---

## 1. Los LXC existen y están en la VLAN

```bash
sudo lxc-ls -f                                          # bbdd y logs en RUNNING
sudo lxc-attach -n bbdd -- ip -4 addr show eth1         # 10.1.2.100/24
sudo lxc-attach -n logs -- ip -4 addr show eth1         # 10.1.2.101/24
sudo ovs-vsctl show | grep -A2 -E 'bbdd-e1|logs-e1'     # tag: 1000
```

Ping desde un worker por la VLAN, con una IP temporal en `e2.1000` (fuera del rango de whereabouts y de las IPs fijas):

```bash
ssh k8s-worker1 'ip addr add 10.1.2.250/24 dev e2.1000 2>/dev/null; ping -c2 10.1.2.100; ping -c2 10.1.2.101'
```

> **Por qué:** es la misma prueba que US-12 ([`capturas/us-12-vnx-una-vlan.txt`](../../capturas/us-12-vnx-una-vlan.txt)). Si no hay ping, el fallo está en la VLAN, no en MySQL ni en rsyslog: revisa que `e2.1000` exista (`setup-vlan-workers.sh`) y que los puertos tengan el tag 1000. La IP `10.1.2.250` desaparece cuando se reinicia el escenario. Mientras exista, el worker se comporta como un equipo más de la VLAN.

---

## 2. US-20 · MySQL dentro de `bbdd`

### 2.1 El `<exec>` y el `<filetree>` hicieron su trabajo

```bash
sudo lxc-attach -n bbdd -- systemctl is-active mysql ssh            # active / active
sudo lxc-attach -n bbdd -- ls -l /etc/mysql/mysql.conf.d/ /root/init.sql /root/.ssh/authorized_keys
```

Esperado: `zz-bbdd.cnf` dentro de `mysql.conf.d/`, `init.sql` en `/root/` y `authorized_keys` con permisos `-rw-------`.

### 2.2 Escucha en todas las interfaces, no solo en localhost

```bash
sudo lxc-attach -n bbdd -- ss -tlnp | grep 3306
```

Esperado: `0.0.0.0:3306`. Si sale `127.0.0.1:3306`, el drop-in no se aplicó.

> **Por qué:** el `mysqld.cnf` de Ubuntu trae `bind-address = 127.0.0.1`. MySQL lee los ficheros de `mysql.conf.d/` **en orden alfabético** y el último valor gana, por eso el nuestro se llama `zz-bbdd.cnf`. En MariaDB la carpeta sería `mariadb.conf.d/` (D-012).

### 2.3 El `init.sql` creó la base de datos y el usuario

```bash
sudo lxc-attach -n bbdd -- mysql -e "SHOW DATABASES; SELECT user, host, plugin FROM mysql.user WHERE user='appuser';"
```

Esperado: `appdb` en la lista y `appuser | 10.1.2.% | mysql_native_password`.

> **Por qué `mysql` entra sin contraseña:** `root@localhost` usa el plugin `auth_socket`, que deja entrar al usuario `root` del sistema operativo. Por eso el `<exec>` puede ejecutar `init.sql` sin conocer ninguna contraseña.

### 2.4 Prueba negativa: `appuser` no entra desde fuera de la VLAN

```bash
sudo lxc-attach -n bbdd -- mysql -h 127.0.0.1 -u appuser -p appdb    # pon la contraseña
```

Esperado: `ERROR 1045 (28000): Access denied for user 'appuser'@'localhost'`.

> **Por qué:** en MySQL un usuario es el par `'usuario'@'origen'`. `appuser` solo existe para `10.1.2.%`, y esta conexión llega desde `127.0.0.1`. Así se comprueba que la restricción por subred funciona antes de probarla desde la VLAN.

---

## 3. US-20 · MySQL desde la VLAN

Desde el worker con la IP temporal de §1 se comprueba el puerto (el worker no tiene cliente `mysql`):

```bash
ssh k8s-worker1 'nc -zv -w3 10.1.2.100 3306'      # "succeeded" / "open"
```

El login completo con usuario y contraseña se hace desde un Pod (§7).

> **Por qué separar puerto y login:** `nc` solo abre la conexión TCP. Si funciona, la red y el `bind-address` están bien, y un fallo posterior del login ya solo puede ser del usuario o de la contraseña.

---

## 4. US-20 · SSH a `bbdd` con la clave del par 1

El criterio dice "desde el admin", pero el Pod admin todavía no tiene `net1` (eso es [US-24](../../../historias/persona-c.md#us-24)). Mientras tanto, se prueba la **misma clave** por la **misma VLAN**, saltando por `k8s-worker1`:

```bash
ssh -i keys/par1_admin -o IdentitiesOnly=yes -J k8s-worker1 root@10.1.2.100 hostname     # bbdd, sin pedir contraseña
```

Prueba negativa, con la otra clave:

```bash
ssh -i keys/par2_host -o IdentitiesOnly=yes -o PasswordAuthentication=no -J k8s-worker1 root@10.1.2.100 hostname
# esperado: Permission denied (publickey)
```

> **Por qué `-J`:** el host no está en la VLAN, pero `k8s-worker1` sí (`e2.1000` con `10.1.2.250`). `-J` abre primero una conexión SSH al worker con tu configuración de siempre y, a través de ella, otra hasta `10.1.2.100`. La opción `-i` solo se usa en el **último** salto, así que el LXC recibe exactamente la clave del par 1. `IdentitiesOnly=yes` evita que SSH pruebe antes otras claves de `~/.ssh` y dé un falso positivo.

---

## 5. US-21 · rsyslog dentro de `logs`

```bash
sudo lxc-attach -n logs -- systemctl is-active rsyslog ssh           # active / active
sudo lxc-attach -n logs -- rsyslogd -N1                               # valida la configuración, sin errores
sudo lxc-attach -n logs -- ss -tulnp | grep 514
```

Esperado en `ss`: **dos** líneas, `udp ... 0.0.0.0:514` y `tcp LISTEN ... 0.0.0.0:514`.

> **Por qué dos:** `imudp` e `imtcp` son módulos distintos de rsyslog, y cada uno abre su propio socket. Si solo sale uno, falta su `module(load=...)` en `10-remote.conf`. Si no sale ninguno, rsyslog no leyó el fichero: revisa que esté en `/etc/rsyslog.d/` y la salida de `rsyslogd -N1`.

---

## 6. US-21 · Enviar logs desde la VLAN

Desde el worker con la IP temporal de §1, una vez por UDP y otra por TCP:

```bash
ssh k8s-worker1 'logger -n 10.1.2.101 -P 514 -d "us21 prueba-worker-udp"; logger -n 10.1.2.101 -P 514 -T "us21 prueba-worker-tcp"'
sudo lxc-attach -n logs -- ls -R /var/log/remote/
sudo lxc-attach -n logs -- grep -r us21 /var/log/remote/
```

Esperado: una carpeta `/var/log/remote/k8s-worker1/` con las **dos** líneas en `syslog.log`.

SSH al LXC con la clave del par 1, igual que en §4:

```bash
ssh -i keys/par1_admin -o IdentitiesOnly=yes -J k8s-worker1 root@10.1.2.101 hostname     # logs
```

> **Por qué la carpeta se llama como el worker:** la plantilla `RemoteLogs` usa `%HOSTNAME%`, el nombre que viene **dentro** del mensaje syslog, que `logger` rellena con el hostname del emisor. La condición `$fromhost-ip != '127.0.0.1'` separa los mensajes remotos de los del propio LXC, que siguen yendo a `/var/log/syslog`. El `stop` impide que los remotos se dupliquen ahí.

---

## 7. Desde un Pod en la VLAN (criterio de las historias)

Un Pod temporal con la imagen `mysql:8.0`, que trae el cliente `mysql` y `bash`, y con la anotación de Multus para que tenga `net1`. Requisito: `terraform apply` ya ha creado la NAD `vlan1000-web`, y `setup-whereabouts.sh` se ha ejecutado.

**1. Crear el Pod:**

```bash
kubectl run tmp-vlan -n g2-workshop --image=mysql:8.0 --restart=Never \
  --annotations=k8s.v1.cni.cncf.io/networks=vlan1000-web --command -- sleep 3600
kubectl wait -n g2-workshop --for=condition=Ready pod/tmp-vlan --timeout=180s
kubectl get pod -n g2-workshop tmp-vlan -o jsonpath='{.metadata.annotations.k8s\.v1\.cni\.cncf\.io/network-status}{"\n"}'
```

Esperado en `network-status`: dos interfaces, `eth0` (Calico, `172.16.x.x`) y `net1` (`10.1.2.10`–`50`).

**2. US-20: login en MySQL por la VLAN:**

```bash
kubectl exec -it -n g2-workshop tmp-vlan -- mysql -h 10.1.2.100 -u appuser -p appdb \
  -e "SELECT CURRENT_USER(), USER(), @@hostname;"
```

Esperado: `CURRENT_USER()` = `appuser@10.1.2.%`, `USER()` = `appuser@10.1.2.<ip de net1>`, `@@hostname` = `bbdd`.

> **Por qué estas tres columnas:** `USER()` es **desde dónde** te conectas (la IP de `net1`, no la de `eth0`), y `CURRENT_USER()` es la **cuenta** de MySQL que te aceptó. Juntas demuestran que el tráfico salió por la VLAN y que entró por la regla `10.1.2.%`. El Pod usa `net1` porque tiene una ruta directa a `10.1.2.0/24` por esa interfaz, que es más específica que la ruta por defecto por `eth0`.

**3. US-21: enviar un log** (la imagen no trae `logger`, así que se usa `/dev/udp` y `/dev/tcp` de bash):

```bash
kubectl exec -n g2-workshop tmp-vlan -- bash -c \
  'echo "<14>$(date "+%b %e %H:%M:%S") $HOSTNAME us21: prueba-pod-udp" > /dev/udp/10.1.2.101/514'
kubectl exec -n g2-workshop tmp-vlan -- bash -c \
  'echo "<14>$(date "+%b %e %H:%M:%S") $HOSTNAME us21: prueba-pod-tcp" > /dev/tcp/10.1.2.101/514'
sudo lxc-attach -n logs -- grep -r prueba-pod /var/log/remote/
```

Esperado: las dos líneas en `/var/log/remote/tmp-vlan/syslog.log`.

> **Por qué ese formato:** `<14>` es la prioridad syslog (facility `user`, severity `info`), seguida de la fecha y del hostname, como en RFC 3164. Así rsyslog sabe sacar `%HOSTNAME%` del mensaje. Sin esa cabecera, el texto acabaría en una carpeta con un nombre raro.

**4. Borrar el Pod:**

```bash
kubectl delete pod -n g2-workshop tmp-vlan --now
```

> whereabouts libera la IP de `net1` al borrar el Pod (se ve con `kubectl get ippools -A -o yaml`).

---

## 📸 Evidencias

Guarda la salida de cada sección en `docs/capturas/`, como en las historias anteriores. Por ejemplo:

```bash
{ echo "### US-20 · usuarios · $(date '+%F %T')"; sudo lxc-attach -n bbdd -- mysql -e "SELECT user,host,plugin FROM mysql.user WHERE user='appuser';"; } | tee -a docs/capturas/us-20-mysql.txt
```

Nombres sugeridos: `us-20-mysql.txt`, `us-20-ssh.txt`, `us-21-rsyslog.txt`, `us-21-ssh.txt`. Nunca pegues la contraseña de `appuser` en una captura.

---

## 🩺 Problemas típicos

| Síntoma | Dónde mirar | Causa probable |
|---|---|---|
| `systemctl is-active mysql` → `inactive`/`unknown` | `sudo lxc-attach -n bbdd -- dpkg -l mysql-server` | El `<exec>` no terminó: `apt` sin Internet por `eth9` (`ip -4 addr show eth9`), o sigue en marcha |
| `ss` muestra `127.0.0.1:3306` | §2.1 (`ls mysql.conf.d/`) | Falta `zz-bbdd.cnf` o está en otra carpeta (la de MariaDB) |
| No existe `appdb` ni `appuser` | `ls /root/init.sql` en `bbdd` | No había `init.sql` antes del `--create` (solo está el `.example` en Git) |
| `ERROR 1045 Access denied` desde el Pod | `USER()` en §7, §2.3 | Contraseña errónea, o conecta desde una IP que no es `10.1.2.x` (no salió por `net1`) |
| `ERROR 2003 Can't connect` / `nc` timeout | §1 (ping), §2.2 | Sin VLAN (`e2.1000` o tag), o MySQL solo escucha en localhost |
| Pod `tmp-vlan` en `ContainerCreating` | `kubectl describe pod` | No existe la NAD (`terraform apply`), no está whereabouts o falta `e2.1000` en ese worker |
| `ssh` pide contraseña o `Permission denied` con `par1_admin` | `cat /root/.ssh/authorized_keys` en el LXC vs `keys/par1_admin.pub` | `gen-keys.sh` se ejecutó después del `--create`: claves distintas. Recrea los LXC |
| `ssh -J` falla en el primer salto | `ssh k8s-worker1 hostname` | El problema es el acceso del host al worker, no el LXC |
| Nada en `/var/log/remote/` | §5 (`ss`, `rsyslogd -N1`) | rsyslog no cargó `10-remote.conf`, o el mensaje llega pero sin cabecera syslog (míralo en `/var/log/syslog`) |
| Solo llega por UDP, no por TCP (o al revés) | §5 (`ss`) | Falta uno de los dos `module(load=...)` |

---

## ✅ Checklist para el PR (copiar en la descripción)

**US-20**
- [ ] `mysql` y `ssh` activos en `bbdd`; `zz-bbdd.cnf`, `init.sql` y `authorized_keys` copiados (§2.1)
- [ ] MySQL escucha en `0.0.0.0:3306` (§2.2)
- [ ] Existen `appdb` y `appuser@10.1.2.%` (§2.3); `appuser` no entra desde localhost (§2.4)
- [ ] Puerto 3306 accesible desde un worker por la VLAN (§3)
- [ ] `ssh root@10.1.2.100` con `par1_admin` entra sin contraseña; con `par2_host` no (§4)
- [ ] Desde un Pod con `net1`, `mysql -h 10.1.2.100 -u appuser -p` conecta como `appuser@10.1.2.%` (§7)

**US-21**
- [ ] `rsyslog` y `ssh` activos en `logs`; escucha en 514 UDP **y** TCP (§5)
- [ ] `logger` desde un worker deja las líneas en `/var/log/remote/k8s-worker1/` (§6)
- [ ] `ssh root@10.1.2.101` con `par1_admin` entra sin contraseña (§6)
- [ ] Un mensaje desde un Pod con `net1` llega a `/var/log/remote/` (§7)
