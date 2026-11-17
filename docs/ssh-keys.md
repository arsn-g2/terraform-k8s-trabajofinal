# 🔑 Claves SSH y Secrets (US-16)

Guía de cómo se generan, se cargan en Kubernetes y se usan las claves SSH del proyecto. Historia: [US-16](../historias/persona-c.md#us-16). Decisión: [D-004](../decisions.md). Enunciado: §2.5.

## 1. Resumen

Hay **dos pares de claves independientes**, uno por cada relación de confianza:

| Par | Ficheros en `keys/` | Dirección | Privada va a… | Pública va a… |
|---|---|---|---|---|
| **1** | `par1_admin`, `par1_admin.pub` | admin → web y LXC | Secret `ssh-admin-private` → Pod admin | Secret `ssh-web-authorized` → Pods web · `vnx/filetree/ssh/authorized_keys` → LXC `bbdd` y `logs` |
| **2** | `par2_host`, `par2_host.pub` | host → admin | **se queda en el host** | Secret `ssh-admin-authorized` → Pod admin |

```
           par 2                         par 1
 host ─────────────────► admin ─────────────────► web (x3)
 (privada par 2)   (pública par 2 +      │        (pública par 1)
                    privada par 1)       │
                                         └──────► bbdd, logs (LXC)
                                                  (pública par 1, por filetree)
```

**¿Por qué dos pares y no uno?** La privada del par 1 vive dentro del clúster (en un Secret, en el `tfstate` y en el Pod admin). Si se filtra, da acceso a los web y a los LXC, pero **no** al admin, porque para entrar al admin hace falta la privada del par 2, que nunca sale del host.

## 2. Dependencias

**Necesita:**
- [US-00](../historias/persona-c.md#us-00): `.gitignore` con `keys/` y los patrones de claves activos (✅ hecho);
- [US-01](../historias/persona-b.md#us-01): esqueleto de Terraform (provider, `variables.tf`). De aquí salen `var.ssh_keys_dir` y `var.namespace`.

**Bloquea a:**

| Historia | Quién | Qué usa de US-16 |
|---|---|---|
| [US-17](../historias/persona-c.md#us-17) · Pod admin | C | monta `ssh-admin-private` y `ssh-admin-authorized`; monta `ssh-web-authorized` en los web (PR revisado por B) |
| [US-20](../historias/persona-a.md#us-20) · MariaDB en `bbdd` | A | `vnx/filetree/ssh/authorized_keys` en su `<filetree>` |
| [US-21](../historias/persona-a.md#us-21) · logs en `logs` | A | ídem |

Más adelante: [US-18](../historias/persona-c.md#us-18) prueba host → admin con el par 2, y [US-24](../historias/persona-c.md#us-24) prueba admin → web/LXC con el par 1.

## 3. Generación: `scripts/gen-keys.sh`

Se ejecuta **en el host**, **sin `sudo`**, **cada día**, **antes** de `terraform apply` y de `vnx --create` de los LXC:

```bash
cd /mnt/tmp/k8s_lab-calico-v02/shared/terraform-k8s-trabajofinal
./scripts/gen-keys.sh
```

Qué hace, paso a paso:

1. Crea `keys/` (permisos `700`) y `vnx/filetree/ssh/`.
2. Para cada par (`par1_admin`, `par2_host`):
   - `rm -f` de las claves del día anterior: `ssh-keygen` pregunta antes de sobrescribir, y el script tiene que ser no interactivo;
   - `ssh-keygen -q -t ed25519 -N "" -C "<par>-<fecha>" -f keys/<par>`.
3. Copia `keys/par1_admin.pub` a `vnx/filetree/ssh/authorized_keys`.

| Opción | Por qué |
|---|---|
| `-t ed25519` | clave corta (una línea de ~80 caracteres) y moderna |
| `-N ""` | sin passphrase: el Pod admin tiene que poder usarla sin que nadie la teclee |
| `-C "par1_admin-2026-11-16"` | comentario al final del `.pub`: al mirar un `authorized_keys` se sabe qué clave es y de qué día |
| `-q` | sin el *randomart* en la salida |
| `set -euo pipefail` | si algo falla, el script se para y no quedan claves a medias |

**¿Por qué sin `sudo`?** Si se genera como root, tu usuario del host no puede leer `keys/par2_host` y el `ssh -i` al admin falla. La VM `terraform` las lee igual a través de `/shared`.

**¿Por qué cada día?** El entorno se recrea a diario y `keys/` no va a Git, así que no hay forma de que las claves sobrevivan. Al regenerarlas cambian **todas**: hay que volver a hacer `terraform apply` (actualiza los Secrets) y recrear los LXC (copian el `filetree` al arrancar).

**Nada de esto va a Git:**
- `keys/` está en `.gitignore`;
- `vnx/filetree/ssh/` también tiene que estar: la clave pública no es secreta, pero cambia cada día y ensuciaría cada commit.

Comprobar con `git check-ignore -v keys/par1_admin vnx/filetree/ssh/authorized_keys`.

## 4. Carga en Kubernetes: `terraform/ssh.tf`

Tres `kubernetes_secret_v1`, leyendo las claves con `file()` (el enunciado pide gestionarlos con Terraform, **no** con `kubectl create secret`). Esquema de uno:

```hcl
resource "kubernetes_secret_v1" "ssh_web_authorized" {
  metadata {
    name      = "ssh-web-authorized"
    namespace = var.namespace
  }
  data = {
    authorized_keys = file("${var.ssh_keys_dir}/par1_admin.pub")
  }
}
```

| Secret | Clave en `data` | Fichero de origen |
|---|---|---|
| `ssh-admin-private` | `id_ed25519` | `keys/par1_admin` |
| `ssh-admin-authorized` | `authorized_keys` | `keys/par2_host.pub` |
| `ssh-web-authorized` | `authorized_keys` | `keys/par1_admin.pub` |

Detalles importantes:
- **La clave dentro de `data` es el nombre del fichero** cuando el Secret se monta como volumen. Por eso se llaman `authorized_keys` e `id_ed25519`.
- **No usar `base64encode()`.** En `data` el provider ya codifica en base64; si lo haces tú queda codificado dos veces y `sshd` lee basura. (`binary_data` es el campo que espera base64.)
- **Ruta de `file()`.** Las rutas relativas se resuelven desde el directorio donde corres `terraform`, no desde el `.tf`. Por eso `var.ssh_keys_dir` vale `"../keys"` y en `ssh.tf` se usa como `"${path.module}/${var.ssh_keys_dir}"` (el `default` de una variable no puede contener `path.module`). En la VM queda `/shared/terraform-k8s-trabajofinal/keys`.
- **Un solo Secret para los 3 web:** todos aceptan la misma clave, y un Secret se puede montar en todos los Pods del Deployment.
- **Dos Secrets separados para el admin** (privada y `authorized_keys`): es lo que recomienda el enunciado, y así cada uno se puede montar con permisos distintos.
- **Si `keys/` no existe**, `terraform plan` falla con `no file exists at …`. Eso es lo que debe pasar: recuerda que falta correr `gen-keys.sh`.

⚠️ **El `tfstate` contiene las claves en claro** (base64 no es cifrado). Por eso `*.tfstate*` está en `.gitignore`. Hay que mencionarlo en la memoria.

## 5. Uso de cada clave

### 5.1 Host → admin (par 2)

```bash
ssh -i keys/par2_host -p <nodePort> adminuser@10.10.10.11
```
- El host presenta la privada del par 2.
- `sshd` en el admin la compara con `~/.ssh/authorized_keys`, que viene del Secret `ssh-admin-authorized`.
- Solo por `10.10.10.11` (worker1), porque el Service es `NodePort` con `externalTrafficPolicy: Local` y el admin está fijado a `k8s-worker1` ([US-18](../historias/persona-c.md#us-18)).
- En Fase 3, la NetworkPolicy solo deja entrar desde `10.10.20.2/32` ([US-32](../historias/persona-c.md#us-32)).

### 5.2 Admin → web y LXC (par 1)

Desde dentro del admin:
```bash
ssh webuser@<ip-vlan-web>     # Pods web
ssh root@<ip-bbdd>            # LXC (usuario a confirmar con A)
ssh root@<ip-logs>
```
- `ssh` usa por defecto `~/.ssh/id_ed25519` (Secret `ssh-admin-private`), sin `-i`.
- Los web la aceptan porque tienen la pública en `/home/webuser/.ssh/authorized_keys` (Secret `ssh-web-authorized`).
- Los LXC la aceptan porque el `<filetree>` copió `vnx/filetree/ssh/authorized_keys` a su `.ssh/`.
- Va por la VLAN (interfaz `net1` de Multus), con las IPs de la VLAN ([US-24](../historias/persona-c.md#us-24)).

### 5.3 Montaje en el Pod admin (US-17)

- `security_context { fs_group = 1000 }` en el Pod: los ficheros de los volúmenes de Secret quedan con grupo 1000 (el de `adminuser`).
- Privada con `default_mode = "0440"`, **no** `0600`. El fichero lo crea Kubernetes como `root`: con `0600` solo lo leería root, y con `0440` + `fsGroup` `adminuser` lo lee por grupo. `ssh` no se queja de los permisos porque el fichero no es suyo.
- Dos Secrets no se pueden montar en el mismo directorio como volúmenes enteros (el segundo tapa al primero). Usar `sub_path` para cada fichero (`~/.ssh/id_ed25519` y `~/.ssh/authorized_keys`) o un volumen `projected` que junte los dos.
- ⚠️ La historia US-17 dice `~/.ssh/id_rsa`: con claves ed25519 el nombre correcto es **`id_ed25519`**. `ssh` busca los dos por defecto, pero llamarla `id_rsa` confunde.

### 5.4 Montaje en los Pods web (US-17, toca `web.tf` de B)

- Montar `ssh-web-authorized` en `/home/webuser/.ssh/authorized_keys` (con `sub_path`, para no tapar el resto de `~/.ssh`).
- PR revisado por B.

### 5.5 LXC (US-20 / US-21, A)

En cada `<vm>` del XML:
```xml
<filetree seq="on_boot" root="/root/.ssh/" perms="600">filetree/ssh</filetree>
```
- La ruta `filetree/ssh` es relativa a la carpeta del XML (`vnx/`) y se copia **su contenido**.
- Se usa una subcarpeta (`ssh/`) para que otros ficheros que A ponga en `filetree/` (configuración de MariaDB o rsyslog) no acaben en `.ssh/`.
- Si el usuario de destino no es `root`, cambia `root=` y el usuario tiene que existir en el LXC.

## 6. Orden del día a día

```
1. ./scripts/gen-keys.sh                        (host)
2. sudo vnx -f vnx/<xml-lxc> --create           (host; copia el filetree)
3. terraform apply                              (VM terraform; carga los Secrets)
```
Si se regeneran las claves con todo ya desplegado: `terraform apply` actualiza los Secrets, pero **los Pods que usan `sub_path` no ven el cambio** hasta que se recrean (`kubectl rollout restart`), y los LXC hay que recrearlos (o re-ejecutar el `filetree`).

## 7. Verificación (🧪 de US-16)

```bash
# Host
./scripts/gen-keys.sh
diff keys/par1_admin.pub vnx/filetree/ssh/authorized_keys && echo "filetree OK"
git status                                   # ninguna clave aparece

# VM terraform
terraform fmt -recursive && terraform validate && terraform apply
kubectl get secrets -n <ns>                  # los tres Secrets
kubectl get secret ssh-web-authorized -n <ns> \
  -o jsonpath='{.data.authorized_keys}' | base64 -d   # igual que keys/par1_admin.pub
```

## 8. Problemas típicos

| Síntoma | Causa probable | Qué mirar |
|---|---|---|
| `bad interpreter: /bin/bash^M` | el script tiene finales de línea CRLF (editado en Windows) | `sed -i 's/\r$//' scripts/gen-keys.sh` |
| `Permission denied` al ejecutar el script | falta el bit de ejecución | `chmod +x`, y en Git `git update-index --chmod=+x scripts/gen-keys.sh` |
| `terraform plan`: `no file exists` | no se corrió `gen-keys.sh`, o `ssh_keys_dir` apunta mal | `ls /shared/terraform-k8s-trabajofinal/keys` desde la VM |
| `Permission denied (publickey)` | la pública en destino no corresponde a la privada (claves de otro día) | comparar el comentario `-C` de la clave en destino con `keys/*.pub` |
| `sshd` ignora el `authorized_keys` | `StrictModes`: `.ssh` o el fichero con dueño o permisos incorrectos | `ls -la ~/.ssh` en destino; `/var/log/auth.log` o `journalctl -u ssh` |
| `ssh: Load key …: bad permissions` | privada con permisos demasiado abiertos y **del propio usuario** | en el admin: `0440` y dueño `root` (ver §5.3) |
| `Load key …: invalid format` | doble base64 (`base64encode()` en `data`) o fichero truncado | `kubectl get secret … -o jsonpath=… \| base64 -d` |

## 9. Pendiente

- Usuario de destino en los LXC (`root` u otro): confirmar con A.
- D-004 sigue en `Proposed`: pasarla a `Accepted` (con el tipo de clave ed25519) al terminar US-16.
