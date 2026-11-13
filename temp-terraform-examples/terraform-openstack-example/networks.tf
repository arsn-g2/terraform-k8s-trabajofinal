# Redes internas del escenario 2.1, creadas con el modulo ./modules/network

module "net1" {
  source          = "./modules/network"
  network_name    = "net1"
  subnet_name     = "subnet1"
  cidr            = "10.10.2.0/24"
  gateway_ip      = "10.10.2.1"
  dns_nameservers = ["8.8.8.8"]
  pool_start      = "10.10.2.9"
  pool_end        = "10.10.2.12"
}

module "net2" {
  source          = "./modules/network"
  network_name    = "net2"
  subnet_name     = "subnet2"
  cidr            = "10.20.2.0/24"
  gateway_ip      = "10.20.2.1"
  dns_nameservers = ["8.8.8.8"]
  pool_start      = "10.20.2.9"
  pool_end        = "10.20.2.12"
}
