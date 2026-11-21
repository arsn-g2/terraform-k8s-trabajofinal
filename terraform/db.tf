# US-23 · Credenciales de la BD en un Secret, inyectadas como env en los Pods web y admin.
# La contrasena viene de var.db_password : se pasa por TF_VAR_db_password al desplegar,
# nunca en terraform.tfvars. Acaba en el tfstate y en el Secret.
resource "kubernetes_secret_v1" "db_credentials" {
  metadata {
    name      = "db-credentials"
    namespace = kubernetes_namespace_v1.namespace.metadata[0].name
  }
  type = "Opaque"
  data = {
    DB_HOST     = var.db_host
    DB_NAME     = var.db_name
    DB_USER     = var.db_user
    DB_PASSWORD = var.db_password
  }
}
