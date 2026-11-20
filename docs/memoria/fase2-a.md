# Fase 2 · Persona A: Servidores en la VLAN

Historias: [US-20](../../historias/persona-a.md#us-20) y [US-21](../../historias/persona-a.md#us-21) · Decisiones: [D-006](../../decisions.md), [D-010](../../decisions.md), [D-012](../../decisions.md) · Pruebas detalladas: [US-20 y US-21](../useful/vnx/pruebas-us20-us21.md)

En esta fase pusimos en marcha los dos servidores que comparten la VLAN 1000 con los Pods: `bbdd` (MySQL) y `logs` (rsyslog). Son dos contenedores LXC definidos en un escenario VNX propio, [`vnx/vnx-vm-bdd-logs.xml`](../../vnx/vnx-vm-bdd-logs.xml), basado en `k8s_lab-vms-vlan.xml` de la práctica 1.3. Ese escenario se conecta a la red `VlanNet` que crea el escenario de Kubernetes, así que hay que arrancar primero el clúster.

## Escenario VNX

Partimos de la plantilla de la P1.3, que tenía dos VLAN unidas por un `vlan-router`. Como el enunciado describe una única VLAN para todo, nos quedamos con la VLAN 1000 y la subred `10.1.2.0/24` y quitamos el router (D-010):

| LXC | Interfaz | IP en la VLAN | Servicio |
|---|---|---|---|
| `bbdd` | `eth1` (tag 1000) | `10.1.2.100` | MySQL 8.0 (3306) y SSH |
| `logs` | `eth1` (tag 1000) | `10.1.2.101` | rsyslog (514 UDP/TCP) y SSH |

Cada LXC usa dos mecanismos de VNX:
- **`<filetree>`** copia los ficheros de configuración desde [`vnx/filetree/`](../../vnx/filetree/) al arrancar;
- **`<exec seq="on_boot">`** instala los paquetes con `apt`, ajusta los permisos de `/root/.ssh` y habilita los servicios. La salida a Internet para `apt` va por `eth9` (`virbr0`).

Los dos LXC reciben el mismo `authorized_keys`, con la clave pública del **par 1**, la que usará el Pod admin. `scripts/gen-keys.sh` lo genera cada día en `vnx/filetree/ssh/`, por lo que debe ejecutarse **antes** del `--create`: si no, los LXC arrancan con la clave del día anterior.

## US-20 · MySQL en `bbdd`

El enunciado propone MariaDB, pero usamos **MySQL 8.0** por recomendación del profesor (D-012). Lo configuramos con dos ficheros:

- [`zz-bbdd.cnf`](../../vnx/filetree/bbdd/zz-bbdd.cnf): un *drop-in* en `/etc/mysql/mysql.conf.d/` con `bind-address = 0.0.0.0`. Por defecto MySQL solo escucha en `127.0.0.1` y no sería accesible desde la VLAN. El prefijo `zz-` hace que se cargue después de `mysqld.cnf` y sobrescriba su valor.
- `init.sql`: crea la base de datos `appdb` y el usuario `appuser`@`10.1.2.%`, que solo puede conectarse desde la subred de la VLAN. Usa `mysql_native_password` para evitar problemas con clientes que no soportan `caching_sha2_password`. El `<exec>` lo carga con `mysql -e "source /root/init.sql"`, que funciona sin contraseña porque `root@localhost` se autentica por *socket*.

La contraseña real no se sube a Git. Solo se versiona [`init.sql.example`](../../vnx/filetree/bbdd/init.sql.example), con un marcador, y cada día se genera `init.sql` a partir de él antes de crear el escenario. Los datos de acceso se pasaron a B y C por un canal privado.

Al probar el escenario encontramos un fallo de orden: lanzamos el `sed` que genera `init.sql` desde la carpeta `vnx/`, con rutas pensadas para la raíz del repositorio, y el fichero no se creó. Como el `<exec>` solo se ejecuta al arrancar el LXC, `bbdd` quedó con MySQL funcionando pero sin `appdb` ni `appuser`. Lo resolvimos destruyendo el escenario y volviendo a crearlo con `init.sql` ya generado.

### Pruebas

- MySQL activo y escuchando en `0.0.0.0:3306`; `appdb` y `appuser`@`10.1.2.%` creados.
- Una conexión de `appuser` desde dentro del propio `bbdd` es rechazada (`Access denied for 'appuser'@'localhost'`). Es lo esperado: el usuario solo existe para la VLAN.
- Desde un Pod temporal conectado a la VLAN con el NAD `vlan1000-web` (IP `10.1.2.10`, asignada por whereabouts), `mysql -h 10.1.2.100 -u appuser -p appdb` conecta. MySQL ve al cliente como `appuser@10.1.2.10`.
- SSH a `bbdd` con la clave privada del par 1 entra sin contraseña; con la del par 2 es rechazado.

⟪PENDIENTE: captura de la conexión MySQL desde el Pod en la VLAN⟫

## US-21 · Servidor de logs en `logs`

El enunciado no define qué hace el servidor de logs, así que decidimos que reciba syslog remoto (D-006). La configuración está en [`10-remote.conf`](../../vnx/filetree/logs/10-remote.conf), en `/etc/rsyslog.d/`:
- carga los módulos `imudp` e `imtcp` y escucha en el puerto 514 de ambos protocolos;
- guarda lo que llega de otras máquinas en `/var/log/remote/<host>/syslog.log`, un fichero por origen, y lo excluye del log local (`stop`).

### Pruebas

- rsyslog escucha en 514 UDP y TCP, y `rsyslogd -N1` valida la configuración sin errores.
- Desde un worker, `logger -n 10.1.2.101 -P 514` envía un mensaje por TCP (`-T`) y otro por UDP (`-d`). Los dos aparecen en `/var/log/remote/k8s-worker1/syslog.log`.
- Desde el Pod temporal en la VLAN (la imagen no trae `logger`) escribimos un mensaje syslog directamente en `/dev/udp/10.1.2.101/514` y `/dev/tcp/10.1.2.101/514`. Los dos llegan a `/var/log/remote/tmp-vlan/syslog.log`.
- SSH a `logs` con la clave del par 1 entra sin contraseña.

⟪PENDIENTE: captura de los mensajes en `/var/log/remote/`⟫

## Observaciones

- **Prueba desde el worker.** La subinterfaz `e2.1000` de los workers no tiene IP, porque los Pods usan macvlan con su propia IP. Para probar desde el worker le añadimos a mano una IP temporal (`10.1.2.250`); sin ella, el tráfico hacia `10.1.2.0/24` salía por la ruta por defecto (`e9`) y no llegaba. Esta IP solo sirve para la prueba y se pierde al reiniciar el escenario.
- **SSH desde el admin.** El acceso por SSH se probó desde el host con la clave del par 1, saltando a través de `k8s-worker1`. La prueba desde el propio Pod admin por la VLAN corresponde a [US-24](../../historias/persona-c.md#us-24).
- **NetworkPolicies.** Estas pruebas se hicieron sin NetworkPolicies. En la Fase 3 hay que repetirlas con la política *default-deny* activa ([US-33](../../historias/persona-a.md#us-33)).
