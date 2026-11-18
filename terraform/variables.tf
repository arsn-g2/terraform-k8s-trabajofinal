variable "namespace" {
  description = "Namespace de los recursos del escenario"
  type        = string
  default     = "g2-workshop"
}

variable "ssh_keys_dir" {
  description = "Carpeta de las claves SSH generadas por scripts/gen-keys.sh, relativa a terraform/ (D-004)"
  type        = string
  default     = "../keys"
}

variable "web_num_replicas" {
  description = "Número de réplicas del Deployment web (el enunciado pide 3)"
  type        = number
  default     = 3
}

variable "admin_num_replicas" {
  description = "Número de réplicas del Deployment web (el enunciado pide 3)"
  type        = number
  default     = 1
}

# Valores del escenario: ver docs/datos-escenario.md §8

variable "group_number" {
  description = "Número de grupo de prácticas. La ruta del Ingress es /servers-G<group_number> (D-001)"
  type        = number
  default     = 2
}

variable "g2_ingress_path" {
  description = "Ruta del Ingress para el grupo 2 (D-001)"
  type        = string
  default     = "/servers-G2"
}

variable "image_web" {
  description = "Imagen de los servidores web (usuario webuser, GID 1000)"
  type        = string
  default     = "dgsgiros/nginx-ssh:latest"
}

variable "image_admin" {
  description = "Imagen del servidor de administración (usuario adminuser, GID 1000)"
  type        = string
  default     = "dgsgiros/admin-ssh:latest"
}

# variable "host_user_lan_ip" {
#   description = "IP del host en user_LAN: única IP con acceso SSH al admin (NetworkPolicy ipBlock /32)"
#   type        = string
#   default     = "10.10.20.2"
#
#   validation {
#     condition     = can(cidrhost("${var.host_user_lan_ip}/32", 0))
#     error_message = "host_user_lan_ip debe ser una IPv4 válida."
#   }
# }
#
# variable "worker1_ip" {
#   description = "IP de k8s-worker1 en k8s_LAN: destino del SSH al admin por NodePort"
#   type        = string
#   default     = "10.10.10.11"
#
#   validation {
#     condition     = can(cidrhost("${var.worker1_ip}/32", 0))
#     error_message = "worker1_ip debe ser una IPv4 válida."
#   }
# }
#
variable "ingress_class" {
  description = "IngressClass del Ingress Controller del escenario -> kubectl get ingressclass"
  type        = string
  default     = "nginx"
}
#
variable "vlan_master_if" {
  description = "Interfaz de los workers conectada a VlanNet (sobre ella va la subinterfaz <if>.<vlan_id>)"
  type        = string
  default     = "e2"
}

variable "vlan_id" {
  description = "VLAN ID de la red compartida con los LXC (D-009)"
  type        = number
  default     = 1000

  validation {
    condition     = var.vlan_id == null ? true : (var.vlan_id >= 1 && var.vlan_id <= 4094)
    error_message = "vlan_id debe estar entre 1 y 4094."
  }
}

variable "vlan_subnet" {
  description = "Subred de la VLAN en notación CIDR, por ejemplo 10.1.2.0/24 (D-009)"
  type        = string
  default     = "10.1.2.0/24"

  validation {
    condition     = var.vlan_subnet == null ? true : can(cidrhost(var.vlan_subnet, 0))
    error_message = "vlan_subnet debe ser un CIDR válido, por ejemplo 10.1.2.0/24."
  }
}

# Plan de direcciones de la VLAN (D-005, D-009)

variable "vlan_web_range_start" {
  description = "Primera IP que whereabouts puede dar a los Pods web"
  type        = string
  default     = "10.1.2.10"
}

variable "vlan_web_range_end" {
  description = "Última IP que whereabouts puede dar a los Pods web"
  type        = string
  default     = "10.1.2.50"
}

variable "vlan_admin_ip" {
  description = "IP fija del Pod admin en la VLAN (IPAM static). Tiene que quedar fuera del rango de los web"
  type        = string
  default     = "10.1.2.5"
}