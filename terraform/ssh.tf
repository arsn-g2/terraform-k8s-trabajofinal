# US-16 · Secrets con las claves SSH (D-004, enunciado §2.5)
# Las claves las genera scripts/gen-keys.sh en keys/ (fuera de Git). Si no existen,
# `terraform plan` falla con "no file exists": falta correr gen-keys.sh.
#
#   par 1 (par1_admin): admin -> web y LXC
#   par 2 (par2_host):  host  -> admin   (la privada no sale del host)
#
# La clave de cada entrada de `data` es el nombre del fichero al montar el Secret como volumen.
# `data` va en texto plano: el provider lo codifica en base64 (no usar base64encode()).
# ⚠️ El contenido queda en el tfstate: el estado nunca va a Git.

locals {
  # file() resuelve rutas relativas desde donde se ejecuta terraform; path.module las fija a terraform/
  ssh_keys_path = "${path.module}/${var.ssh_keys_dir}"
}

# Privada del par 1 -> Pod admin (~/.ssh/id_ed25519)
resource "kubernetes_secret_v1" "ssh_admin_private" {
  metadata {
    name      = "ssh-admin-private"
    namespace = kubernetes_namespace_v1.namespace.metadata[0].name
  }

  data = {
    "id_ed25519" = file("${local.ssh_keys_path}/par1_admin")
  }
}

# Pública del par 2 -> Pod admin (~/.ssh/authorized_keys): acceso host -> admin
resource "kubernetes_secret_v1" "ssh_admin_authorized" {
  metadata {
    name      = "ssh-admin-authorized"
    namespace = kubernetes_namespace_v1.namespace.metadata[0].name
  }

  data = {
    "authorized_keys" = file("${local.ssh_keys_path}/par2_host.pub")
  }
}

# Pública del par 1 -> los 3 Pods web (~/.ssh/authorized_keys): acceso admin -> web
# La misma clave va a los LXC por vnx/filetree/ssh/authorized_keys (la copia gen-keys.sh)
resource "kubernetes_secret_v1" "ssh_web_authorized" {
  metadata {
    name      = "ssh-web-authorized"
    namespace = kubernetes_namespace_v1.namespace.metadata[0].name
  }

  data = {
    "authorized_keys" = file("${local.ssh_keys_path}/par1_admin.pub")
  }
}
