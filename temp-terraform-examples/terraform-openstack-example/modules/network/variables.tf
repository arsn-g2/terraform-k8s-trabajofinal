variable "network_name" {
  description = "Nombre de la red"
  type        = string
}

variable "subnet_name" {
  description = "Nombre de la subred"
  type        = string
}

variable "cidr" {
  description = "Rango de direcciones de la subred (CIDR)"
  type        = string
}

variable "gateway_ip" {
  description = "IP del gateway de la subred"
  type        = string
}

variable "dns_nameservers" {
  description = "Servidores DNS de la subred"
  type        = list(string)
  default     = ["8.8.8.8"]
}

variable "pool_start" {
  description = "Primera IP del pool de direcciones"
  type        = string
}

variable "pool_end" {
  description = "Ultima IP del pool de direcciones"
  type        = string
}
