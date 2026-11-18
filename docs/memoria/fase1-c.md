# Fase 1 · Persona C: Seguridad

Historias: [US-16](../../historias/persona-c.md#us-16) · Decisiones: [D-004](../../decisions.md) · Guía y pruebas detalladas: [ssh-keys.md](../ssh-keys.md)

En esta fase preparamos las claves SSH del escenario y las cargamos en Kubernetes como Secrets gestionados por Terraform. Las claves se generan en el host con un script del repositorio (`scripts/gen-keys.sh`) y los Secrets se definen en `terraform/ssh.tf`, en el namespace `g2-workshop`. Montarlas en los Pods y probar las conexiones SSH queda para US-17, US-18 y US-24.

## US-16 · Claves SSH y Secrets

### Diseño: dos pares independientes

Siguiendo el enunciado (§2.5), usamos **dos pares de claves**, uno por cada relación de confianza (D-004):

| Par | Ficheros | Dirección | Privada | Pública |
|---|---|---|---|---|
| 1 | `par1_admin`, `par1_admin.pub` | admin → web y LXC | Secret `ssh-admin-private` (Pod admin) | Secret `ssh-web-authorized` (Pods web) y `filetree` de los LXC `bbdd` y `logs` |
| 2 | `par2_host`, `par2_host.pub` | host → admin | se queda en el host | Secret `ssh-admin-authorized` (Pod admin) |

La privada del par 1 vive dentro del clúster (en un Secret y en el Pod admin). Si se filtrara, daría acceso a los web y a los LXC, pero no al propio admin, porque para entrar en él hace falta la privada del par 2, que nunca sale del host.

Elegimos claves **ed25519**: ocupan una sola línea corta y son el tipo recomendado actualmente por OpenSSH.

### Generación de las claves

El entorno del laboratorio se crea de cero cada día y solo el repositorio persiste, así que las claves no pueden guardarse: se **regeneran cada día** con `scripts/gen-keys.sh`, que se ejecuta en el host, sin `sudo`, después de clonar el repositorio y antes de crear los LXC y de hacer `terraform apply`. El script:

- es no interactivo: borra las claves del día anterior (`ssh-keygen` pregunta antes de sobrescribir) y genera las nuevas sin passphrase (`-N ""`), porque el Pod admin tiene que poder usarlas sin que nadie la teclee;
- añade a cada clave un comentario con el par y la fecha (`-C par1_admin-2026-11-17`), para saber de un vistazo qué clave hay en un `authorized_keys`;
- crea `keys/` con permisos `700` y copia la pública del par 1 a `vnx/filetree/ssh/authorized_keys`, desde donde el `<filetree>` de VNX la instalará en los LXC al arrancar;
- usa `set -euo pipefail`, para que un fallo detenga el script y no queden claves a medias.

Lo ejecutamos sin `sudo` para que las claves sean del usuario del host: si fueran de `root`, no podríamos usar `keys/par2_host` con `ssh -i`. La VM `terraform` las lee igualmente a través de la carpeta compartida `/shared`.

Como el script se ejecuta justo después de cada `git clone`, añadimos `chmod +x` antes de llamarlo en los pasos de arranque ([datos-escenario.md](../datos-escenario.md) §1 y `scripts/host-script.sh`).

![Generación de las claves](screenshots/us-16-generacion-keys.jpg)

En la captura se ven los cuatro ficheros: las privadas con `600` (`ssh` se niega a usar una privada propia que otros puedan leer) y las públicas con `644`.

Ni las claves ni su copia para los LXC se suben a Git. `keys/` ya estaba en `.gitignore`, y añadimos `vnx/filetree/ssh/`: la clave pública no es secreta, pero cambia cada día y aparecería en cada commit.

⟪PENDIENTE: captura de `git check-ignore -v keys/par1_admin vnx/filetree/ssh/authorized_keys` y `git status` sin claves⟫

### Secrets en Terraform

En `terraform/ssh.tf` creamos tres `kubernetes_secret_v1`, que leen las claves con `file()` en lugar de crearlas con `kubectl create secret`, como pide el enunciado:

| Recurso | Secret | Clave en `data` | Fichero |
|---|---|---|---|
| `ssh_admin_private` | `ssh-admin-private` | `id_ed25519` | `keys/par1_admin` |
| `ssh_admin_authorized` | `ssh-admin-authorized` | `authorized_keys` | `keys/par2_host.pub` |
| `ssh_web_authorized` | `ssh-web-authorized` | `authorized_keys` | `keys/par1_admin.pub` |

Algunos detalles de la implementación:

- **Nombre de la clave en `data`.** Cuando un Secret se monta como volumen, cada clave de `data` se convierte en un fichero. Por eso las llamamos `id_ed25519` y `authorized_keys`, los nombres que esperan `ssh` y `sshd`.
- **Sin `base64encode()`.** En `data` el provider ya codifica el contenido en base64; si lo hiciéramos también nosotros, quedaría codificado dos veces.
- **Ruta de las claves.** `file()` resuelve las rutas relativas desde el directorio donde se ejecuta `terraform`, no desde el `.tf`. Añadimos la variable `ssh_keys_dir = "../keys"` y la usamos como `"${path.module}/${var.ssh_keys_dir}"`, porque el valor por defecto de una variable no puede contener `path.module`.
- **Namespace.** Los Secrets referencian `kubernetes_namespace_v1.namespace.metadata[0].name` en lugar de `var.namespace`, para que Terraform cree el namespace antes que ellos.
- **Un Secret para los 3 web.** Los tres Pods aceptan la misma clave, así que comparten un único Secret. El admin, en cambio, tiene dos (privada y `authorized_keys`), como recomienda el enunciado, para poder montar cada uno con sus permisos.
- **Si falta `keys/`**, `terraform plan` falla con `no file exists`. Así, si se olvida ejecutar `gen-keys.sh`, Terraform no crea Secrets vacíos.

Añadimos también el output `ssh_secret_names` con los nombres de los tres Secrets, para consultarlos desde fuera de Terraform (por ejemplo, en `verify.sh`).

Tras el `apply`, los tres Secrets aparecen en el estado de Terraform:

![Secrets en el estado de Terraform](screenshots/us-16-keys-used-as-k8s-secret-resource-terraform.jpg)

Y en el clúster, de tipo `Opaque` y con una entrada de datos cada uno:

![Secrets en el clúster](screenshots/us-16-k8s-secrets-opaque.jpg)

⟪PENDIENTE: captura de la prueba P9 de [ssh-keys.md](../ssh-keys.md) §7 (el contenido decodificado de cada Secret coincide con su fichero de `keys/`)⟫

### Seguridad: las claves en el estado de Terraform

Aunque las claves se generan fuera de Terraform, al leerlas con `file()` su contenido queda guardado en el `terraform.tfstate`, y en claro: base64 no es cifrado. Por eso el estado nunca se sube a Git (`*.tfstate*` está en `.gitignore`). En un entorno real habría que guardar el estado en un backend cifrado y con acceso restringido.

⟪PENDIENTE: captura de `grep -c "BEGIN OPENSSH" terraform.tfstate` en la VM⟫

### Coordinación con el equipo

- **Persona A** (US-20, US-21): la pública del par 1 queda en `vnx/filetree/ssh/authorized_keys` para el `<filetree>` de los LXC. Usamos una subcarpeta propia (`ssh/`) para que, si el `filetree` incluye otras configuraciones (MariaDB, rsyslog), estas no acaben en `.ssh/`. Falta confirmar con A el usuario de destino en los LXC.
- **US-17**: montará `ssh-admin-private` y `ssh-admin-authorized` en el Pod admin (con `fsGroup: 1000` y modo `0440`) y `ssh-web-authorized` en los Pods web, en un PR que revisará la persona B.
