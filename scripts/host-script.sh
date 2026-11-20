TERRAFORM LAB k8s

/lab/cnvr/bin/get-k8s-calico
cd /mnt/tmp/k8s_lab-calico-v03
./bin/start-k8s-calico
sudo vnx -f k8s_lab-terraform.xml --create
sudo vnx -f k8s_lab-terraform.xml -x install-terraform
./bin/get-master-kubeconf
./bin/set-terraform-kubeconf
sudo vnx -f k8s_lab-calico.xml -x config_metallb


cd /mnt/tmp/k8s_lab-calico-v03/shared/
git clone https://github.com/arsn-g2/terraform-k8s-trabajofinal.git


cd /mnt/tmp/k8s_lab-calico-v03/
code .

cd /mnt/tmp/k8s_lab-calico-v03/shared/terraform-k8s-trabajofinal
chmod +x scripts/*
# claves SSH del día (US-16): antes de crear los LXC y de terraform apply
./scripts/gen-keys.sh
# VLAN 1000 (D-009): subinterfaz e2.1000 en los workers y LXC bbdd y logs (§9)
./scripts/setup-vlan-workers.sh                    # crea e2.1000 en k8s-worker1 y k8s-worker2 (idempotente)
./scripts/setup-whereabouts.sh                     # instala el IPAM whereabouts v0.9.4 (D-010, idempotente)


# start the vnx infra: bbdd, logs servers
cd /mnt/tmp/k8s_lab-calico-v03/shared/terraform-k8s-trabajofinal/vnx
sed 's/__CAMBIA_ESTA_PASSWORD__/1q2w3e4r/g' filetree/bbdd/init.sql.example > filetree/bbdd/init.sql
sudo vnx -f vnx-vm-bdd-logs.xml --create
