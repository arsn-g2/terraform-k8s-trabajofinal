variable "name" {
    description = "Name of the VM instance"
    type = string
}
variable "flavor" {
    description = "Flavor of the VM instance"
    type = string
}
variable "image" {
    description = "Image of the VM instance"
    type = string
}
variable "key_pair" {
    description = "Key pair for the VM instance"
    type = string
}
variable "security_groups" {
  description = "List of security groups for the VM instance"
  type = list(string)
}
variable "network_name" {
  description = "Name of the network for the VM instance"
  type = string
}