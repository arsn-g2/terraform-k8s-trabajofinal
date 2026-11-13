TERRAFORM LAB k8s

/lab/cnvr/bin/get-k8s-calico
cd /mnt/tmp/k8s_lab-calico-v02
./bin/start-k8s-calico
sudo vnx -f k8s_lab-terraform.xml --create
sudo vnx -f k8s_lab-terraform.xml -x install-terraform
./bin/get-master-kubeconf
./bin/set-terraform-kubeconf
sudo vnx -f k8s_lab-calico.xml -x config_metallb


cd /mnt/tmp/k8s_lab-calico-v02/shared/
git clone https://github.com/arsn-g2/terraform-k8s-trabajofinal.git

cd /mnt/tmp/k8s_lab-calico-v02/
code .
