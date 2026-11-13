# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**The main purpose of this project is the UPM ARSN/CNVR 2026-27 Trabajo Final**, "Despliegue automático de una aplicación escalable sobre Kubernetes utilizando los servicios de orquestación de Terraform". The spec is `ARSN-trabajo-final-26-27.pdf`, which is in Spanish. We are **Group 2**, so the Ingress path is `/servers-G2`. A team of 3 works on it, each owning one stream (A: VLAN/Multus/VNX-LXC, B: Pods/Secrets/web content, C: Services/Ingress/NetworkPolicies/integration). Project docs (read them first and keep them updated):
- `plan.md`: overview, folder layout, interface contract, risks.
- `tasks.md`: progressive checklist (IDs S0.x, A1–A9, B1–B9, C1–C9, I1–I4, H1–H4). Tick tasks as they are completed.
- `user-stories.md`: per-task description, owner, effort, dependencies, acceptance criteria.
- `decisions.md`: **the decision log is a required deliverable.** We may adapt the PDF, but every design choice or deviation needs an entry (context, options, decision, why). When you make or propose a design choice, add or update an entry.

Practice 1.4 (Terraform) is earlier coursework and serves as reference/knowledge only:
- `terraform-k8s/`: the team's P1.4 k8s solution (Deployment + Service with locals, NetworkPolicies, outputs, `kubernetes_resources` data source). **This is the starting point for the Trabajo Final's Terraform style.** It still has live state (`terraform.tfstate`), with objects in namespace `default` (nginx NodePort 30001, `default-deny-all`, `tester`).
- `terraform_files_p14/`: read-only reference `.tf` files from Moodle. `apartado2-*` are OpenStack (another scenario, irrelevant here) and `apartado3-*` are k8s.
- `ARSN_terraform-k8s-lab-p1.4.pdf`, `create-keypairs.sh`: P1.4 material (OpenStack).

It is not a software project, so there is nothing to build or unit-test. The work is Terraform HCL, VNX XML and shell scripts, run against the lab scenario.

## Trabajo Final: what has to be deployed

Full requirements: PDF §2–§5. Proposed layout and owners: `plan.md`.
- **Web**: a Deployment with 3 replicas of `dgsgiros/nginx-ssh:latest` (user `webuser`, GID 1000). `index.html` is generated from a ConfigMap template, with the Pod name substituted in by an initContainer or sidecar into a shared `emptyDir`.
- **Admin**: one Pod of `dgsgiros/admin-ssh:latest` (user `adminuser`, GID 1000), with `fsGroup: 1000` and a `nodeSelector` for `k8s-worker1`.
- **VLAN**:
  - Pods get an extra interface via Multus `NetworkAttachmentDefinition`, created with `kubernetes_manifest` because the provider has no native resource for it;
  - the workers need `eth2.<VLAN>` subinterfaces, since their `if id=2` is on the OVS net `VlanNet`;
  - LXC `db` (MariaDB) and `logs` live in a separate VNX XML based on `../../k8s_lab-vms-vlan.xml`, with `exec` steps for installation and `filetree` for configs and `authorized_keys`.
- **SSH (keys only)**:
  - pair 1 is admin → web/LXC. The private key goes in the admin Secret, and the public key into web `authorized_keys` and the LXC;
  - pair 2 is host → admin. The public key goes into admin `authorized_keys`;
  - Secrets are created with `kubernetes_secret_v1` in Terraform, **not** `kubectl create secret`.
- **Services**:
  - web is `ClusterIP` 8080→80;
  - admin is `NodePort` 2222→22 with `externalTrafficPolicy: Local`. SSH goes to `10.10.10.11:<nodePort>`.
- **Ingress**: path `/servers-G2` (from `var.group_number = 2`) → web Service. It needs the rewrite-target annotation.
- **NetworkPolicies**:
  - default deny for Ingress and Egress;
  - web ingress allowed only from ingress-nginx Pods (namespaceSelector `kubernetes.io/metadata.name: ingress-nginx` + podSelector), on Pod port 80;
  - admin SSH allowed only from `ipBlock 10.10.20.2/32` (the host on `user_LAN`).
  - Calico does **not** police the Multus/VLAN interfaces.

NOTE shared/terraform-k8s-trabajofinal is the git repo, but has old content(we are working on this today)
shared/terraform-lab/ is the most updated in terms of environment settings. but I like the organization around team plan and user stories saved in the repo(but they need to be updated to reflect the current deployed environment)

## Environment and path mapping

- Scenario root on the host: `/mnt/tmp/k8s_lab-calico-v02/`. **`/mnt/tmp` is temporary storage** and the folder is not a git repo, so back up or commit the work elsewhere.
- k8s cluster (`k8s_lab-calico.xml`, Calico CNI):
  - `k8s-master` 10.10.10.10;
  - `k8s-worker1` 10.10.10.11 and `k8s-worker2` 10.10.10.12. Both are on `k8s_LAN`, have eth2 on `VlanNet`, and mount `shared/` at `/shared`;
  - `r1` 10.10.10.1 / 10.10.20.1;
  - host 10.10.20.2 on `user_LAN`;
  - MetalLB pool `10.10.10.20-30`.
- `terraform` LXC VM (`k8s_lab-terraform.xml`): `10.10.10.13`. `shared/` is mounted at **`/shared`**, so this directory is `/shared/terraform-lab/` inside the VM. Run all `terraform` commands there. Edit files on the host.
- `kubectl` works from the host once `bin/get-master-kubeconf` has run. `bin/set-terraform-kubeconf` copies the kubeconfig into the terraform VM's `~/.kube/config`.
- Provider: `hashicorp/kubernetes` pinned to `2.23.0` (see `terraform-k8s/k8s-provider.tf`). Prefer `_v1` resources (`kubernetes_deployment_v1`, `kubernetes_service_v1`, `kubernetes_ingress_v1`, `kubernetes_network_policy_v1`, `kubernetes_secret_v1`, `kubernetes_config_map_v1`).
- Before creating or copying `.tf` files into a new working folder, ask the user. `plan.md` proposes `trabajo-final/terraform/`.

## Scenario commands (host, from `/mnt/tmp/k8s_lab-calico-v02`)

```
bin/start-k8s-calico                 # create cluster, join workers, configure MetalLB
bin/get-master-kubeconf              # kubeconfig → host ~/.kube/config
sudo vnx -f k8s_lab-terraform.xml --create
sudo vnx -f k8s_lab-terraform.xml -x install-terraform   # re-run if `terraform --version` fails
bin/set-terraform-kubeconf           # kubeconfig → terraform VM
bin/stop-k8s-calico                  # destroy cluster
```

## Terraform workflow (inside the `terraform` VM)

```
terraform init                 # use `init -upgrade` after adding a provider/module
terraform validate             # syntax only
terraform plan / apply         # full config. Use -target only to debug one piece
terraform state list | terraform state show TYPE.NAME
terraform output [-json] [NAME]
terraform destroy              # P1.4 leftovers: run in terraform-k8s/ to clear namespace default
```

If `init -upgrade` fails, run `rm -rf .terraform .terraform.lock.hcl` and then try it again. Terraform loads **every `.tf` in the working folder** as one configuration, so keep the Trabajo Final and P1.4 folders separate. Each has its own state.

## Gotchas

- `kubernetes_manifest` (used for the NAD) needs the CRD to exist at **plan** time, so Multus must be installed before `terraform plan`.
- If Multus IPAM is `host-local`, each node allocates independently and web Pods can get duplicate VLAN IPs. Use whereabouts or per-node ranges (`plan.md` R1).
- The NetworkPolicy port for web is the **Pod** port 80, not the Service port 8080. Peers that combine namespaceSelector and podSelector must be in the **same** `from` block (AND), not separate ones (OR).
- NetworkPolicy cannot match ICMP. A rule without `ports` allows all protocols (see the comments in `terraform-k8s/network-policy-*.tf`).
- With default-deny egress, Pods lose DNS unless egress to `kube-dns` on 53/UDP+TCP is allowed (the pattern is in `terraform-k8s/network-policy-egress-tcp-tester.tf`).
- Never commit `keys/` (private SSH keys) or `*.tfstate*`.
