# Outputs de la configuración principal (terraform/), leídos directamente de su state (D-013).
# Así las NetworkPolicies usan el mismo namespace, labels, etc. que el despliegue, sin redefinirlos.
#
# La configuración principal no declara backend, así que su state es el local por defecto:
# ../terraform.tfstate. Este data source solo LEE ese fichero; no lo modifica.
#
# outputs es un mapa nombre => valor: local.env.namespace, local.env.web_labels, ...
# Solo están los outputs del último apply en terraform/: si se añade uno a outputs.tf,
# hay que volver a hacer apply allí antes de usarlo aquí.
data "terraform_remote_state" "main" {
  backend = "local"

  config = {
    path = "${path.module}/../terraform.tfstate"
  }
}

locals {
  env = data.terraform_remote_state.main.outputs
}
