variable "name" {
  description = "Nombre de la VM"
  type        = string
}

variable "image" {
  description = "Nombre de la imagen"
  type        = string
  default     = "cirros-0.3.4-x86_64-vnx"
}

variable "flavor" {
  description = "Nombre del flavor"
  type        = string
  default     = "m1.tiny"
}

variable "key_pair" {
  description = "Nombre del keypair existente"
  type        = string
}

variable "availability_zone" {
  description = "Zona de disponibilidad (p.ej. nova:compute1)"
  type        = string
  default     = null
}

variable "network_id" {
  description = "ID de la red donde se crea el puerto"
  type        = string
}

variable "subnet_id" {
  description = "ID de la subred de la IP fija"
  type        = string
}

variable "ip_address" {
  description = "IP fija de la VM"
  type        = string
}

variable "floating_ip_pool" {
  description = "Red externa de la que se toma la IP flotante"
  type        = string
  default     = "ExtNet"
}
