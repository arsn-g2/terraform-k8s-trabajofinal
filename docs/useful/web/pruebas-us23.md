# 🧪 Pruebas de US-23 · Acceso a MySQL desde los Pods web y admin

⬅️ [Volver al plan](../../../plan.md) · Historia: [US-23](../../../historias/persona-b.md#us-23) · Depende de: [US-20](../../../historias/persona-a.md#us-20) (MySQL en `bbdd`), [US-22](../../../historias/persona-b.md#us-22) (net1 en los web) · Decisiones: [D-007](../../../decisions.md), [D-013](../../../decisions.md)

Cómo comprobar que los Pods web y el admin pueden administrar la base de datos de `bbdd` (10.1.2.100) por la VLAN.

## Cómo está montado
- Las imágenes `dgsgiros/*-ssh` **no traen** cliente MySQL (web = Debian 13, admin = Ubuntu 22.04, ambas como root). Un `lifecycle.post_start` en cada contenedor instala `default-mysql-client` al arrancar el Pod (apt, sin sudo). Corre bajo el **1er `terraform apply`** (sin políticas), cuando el Pod aún tiene salida a Internet ([D-013](../../../decisions.md)).
- Las credenciales (`DB_HOST`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`) vienen de un `kubernetes_secret_v1` (`db-credentials`) inyectado como variables de entorno. La contraseña se pasa por `TF_VAR_db_password` (no va a Git).
- El tráfico web/admin → MySQL va por **net1 (VLAN 1000)**, que Calico **no** filtra, así que funciona también con la deny-all aplicada ([US-33](../../../historias/persona-a.md#us-33)).

## Requisitos previos
- Escenario arriba (clúster + `VlanNet`) y `bbdd` con MySQL (US-20): `sudo lxc-attach -n bbdd -- systemctl is-active mysql` → `active`.
- Pods desplegados con `net1` (US-22 / US-24).
- Antes del apply: `export TF_VAR_db_password=1q2w3e4r` (debe coincidir con el `init.sql` de `bbdd`).

## Pruebas (NS = tu `var.namespace`, p. ej. `g2-workshop`)

### 1. El cliente se instaló (post_start)
```bash
kubectl exec -n $NS deploy/nginx-deployment -c nginx-server -- which mysql
kubectl exec -n $NS deploy/admin-deployment -c admin-server  -- which mysql
```
Esperado: `/usr/bin/mysql`. Si sale vacío, el `post_start` no instaló → mira el egress del Pod.

### 2. Las credenciales llegan como variables de entorno
```bash
kubectl exec -n $NS deploy/nginx-deployment -c nginx-server -- printenv DB_HOST DB_USER DB_NAME
```
Esperado: `10.1.2.100`, `appuser`, `appdb`.

### 3. 🧪 mysql desde un Pod web
```bash
kubectl exec -n $NS deploy/nginx-deployment -c nginx-server -- \
  sh -c 'mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" -e "SHOW DATABASES;"'
```
Esperado: aparece `appdb`.

### 4. 🧪 mysql desde el admin
```bash
kubectl exec -n $NS deploy/admin-deployment -c admin-server -- \
  sh -c 'mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASSWORD" -e "SHOW DATABASES;"'
```

### 5. Tras el 2º apply (políticas) sigue funcionando
Repite 3 y 4 después del `terraform apply` en `terraform/network-policies/`. Debe **seguir** funcionando: el tráfico va por net1 (VLAN), no por eth0 (donde Calico aplica la deny-all). Si fallara, revisar US-33.

## Si algo falla
- `which mysql` vacío → el `post_start` falló (apt sin egress). `kubectl describe pod <pod> -n $NS` (eventos) y prueba a mano `kubectl exec ... -- apt-get update`.
- `Access denied for user 'appuser'` → `TF_VAR_db_password` no coincide con la del `init.sql` de `bbdd`.
- `Can't connect to ... 10.1.2.100` → falta net1 (US-22) o `bbdd` no escucha (US-20): `sudo lxc-attach -n bbdd -- ss -lntp | grep 3306`.

## 🧪 Criterios de aceptación
- [ ] El cliente `mysql` está en el Pod web y en el admin (post_start).
- [ ] `SHOW DATABASES;` desde un web muestra `appdb`.
- [ ] `SHOW DATABASES;` desde el admin muestra `appdb`.
- [ ] Sigue funcionando con las NetworkPolicies aplicadas (2º apply).

## Nota: TLS de MySQL 8 (cliente)
MySQL 8 ofrece TLS por defecto con un certificado **autofirmado**; hay que decirle al cliente que no lo verifique, y cada cliente usa su flag:
- Pod web (Debian → cliente **MariaDB**): `mysql --skip-ssl -h ...`
- Pod admin (Ubuntu → cliente **MySQL**): `mysql --ssl-mode=DISABLED -h ...`
Sin esto: `ERROR 2026 (HY000): TLS/SSL error: self-signed certificate in certificate chain`.
