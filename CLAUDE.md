# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

This repo is the **UPM ARSN/CNVR 2026-27 Trabajo Final**, "Despliegue automático de una aplicación escalable sobre Kubernetes utilizando los servicios de orquestación de Terraform". The spec is `ARSN-trabajo-final-26-27.pdf` (in Spanish, **5 Nov 2026 version**, see D-008). If the plan and the PDF disagree, the PDF wins. We are **Group 2**, so the Ingress path is `/servers-G2`.

It is not a software project, so there is nothing to build or unit-test. The work is Terraform HCL, VNX XML and shell scripts, run against the lab scenario. The project docs are written in Spanish, so keep new content in Spanish too, apart from `decisions.md` and this file, which are in English.

## How to work with me (read this first)

**I want to do the work myself.** I need to understand every configuration and what it affects, and to learn how to troubleshoot the problems we hit.
- When I ask for something, do the **minimum** that answers it. Don't go around fixing, refactoring or "improving" other things. If you notice something else, mention it in one line and leave it alone.
- When something breaks, help me troubleshoot: explain what to look at and why, suggest the next command to run, and explain the output. **Don't fix it for me unless I explicitly say so.**
- Explain the *why* (routing, CNI behaviour, what a field does), not only the *what*.

### Learning order

The topology is in PDF Fig. 1: clients → Ingress → web Service → S1–S3. Clients also reach Service admin → admin Pod. S1–S3 and admin share a VLAN with the VNX LXC `bbdd` and `logs`.
1. **Calico**: experiment to understand Pod networking and routing in the cluster.
2. **VNX VLAN**: deploy the VLAN on its own, without Multus.
3. **Multus**: deploy it and understand how traffic is routed over the extra interface.
4. **VNX DBs**: write and deploy the VNX definition for the `bbdd` and `logs` LXC.

### Project docs (read them first and keep them updated)

- `plan.md`: overview, who owns which area, open questions, proposed repo layout (§3), milestones H0–H3, coordination hand-offs, risks.
- `fases.md`: every user story (US-xx) by phase, with owner, points, dependencies and a **Completed** column.
- `historias/persona-{a,b,c}.md`: the full stories for each person, with description, files, dependencies and 🧪 acceptance criteria.
  - A: Red y VNX. VLAN subinterfaces, Multus NAD, VNX scenario, LXC `bbdd` (MariaDB) and `logs`.
  - B: Aplicación web. Terraform skeleton, ConfigMap, web Deployment, ClusterIP Service, Ingress, `scripts/verify.sh`.
  - C: Seguridad. Repo and conventions, SSH keys and Secrets, admin Pod, NodePort Service, NetworkPolicies, final report.
- `decisions.md`: **the decision log is a required deliverable.** Every design choice or deviation from the PDF needs an entry (D-xxx) that follows the template at the top. Never delete an entry: mark the old one `Superseded by D-xxx`. When you make or propose a design choice, add or update an entry.
- `docs/datos-escenario.md`: values measured in the deployed environment (IPs, versions, Multus plugins, Ingress NodePorts, MetalLB state). Values marked 🔁 can change between deployments.
- `docs/convenciones.md`: git conventions (see below).
- `docs/useful/{multus,metallb,web}/`: guides, plus the P1.3 YAML in `p13/`, which is reference material for porting to Terraform.

To mark a story done (or undo it) in every place it is tracked (`fases.md`, the persona table, and the `**Completed:**` line under the story):
```
python scripts/us-done.py 16          # US-16 -> ✅
python scripts/us-done.py --undo 16
```

### Repo state

- `terraform/` is the Trabajo Final working folder. Right now it holds the US-01 skeleton: provider, `variables.tf` with the scenario values (`vlan_id`/`vlan_subnet` still `null`, pending US-03), and outputs. `deployment-and-service-with-locals.tf` is still the P1.4 nginx example (namespace `default`, NodePort). The target per-area file split (`namespace.tf`, `multus.tf`, `web.tf`, `ssh.tf`, `admin.tf`, `netpol.tf`) is in `plan.md` §3. Each person works in their own `.tf` file to avoid conflicts.
- `terraform/terraform.tfvars` is tracked (`*.tfvars` is commented out in `.gitignore`) and sets `num_replicas = 5`, which overrides the default of 3 that the PDF asks for.
- `temp-terraform-examples/terraform-k8s-example/` is the team's P1.4 k8s solution (Deployment + Service with locals, deny-all, ingress/egress NetworkPolicies, outputs). **It is the style reference.** `terraform-openstack-example/` is OpenStack and not relevant here.
- Folders that contain an empty `test.txt` are placeholders. Delete the `test.txt` once the folder has real content.
- Planned but not written yet: `scripts/gen-keys.sh` (`scripts/create-keypairs.sh` is the old P1.4 OpenStack script and does not apply), `scripts/setup-vlan-workers.sh`, `scripts/verify.sh`, `vnx/k8s_lab-vms-vlan.xml` + `vnx/filetree/`, `README.md`.
- Before creating or copying `.tf` files into a new working folder, ask the user.

## What has to be deployed

Full requirements: PDF §2–§5. Stories: `historias/`.
- **Web**: a Deployment with 3 replicas of `dgsgiros/nginx-ssh:latest` (user `webuser`, GID 1000). `index.html` comes from a ConfigMap template, and an initContainer (D-003) writes the Pod name into it, in a shared `emptyDir`.
- **Admin**: one Pod of `dgsgiros/admin-ssh:latest` (user `adminuser`, GID 1000), with `fsGroup: 1000` and a `nodeSelector` of `kubernetes.io/hostname=k8s-worker1`.
- **Namespace**: a dedicated one, `var.namespace` (D-002), not `default`.
- **VLAN**:
  - Pods get an extra interface (`net1`) through a Multus `NetworkAttachmentDefinition`, created with `kubernetes_manifest` because the provider has no native resource for it. The plan is `macvlan` bridge on `e2.<vlan>`.
  - The workers need `e2.<vlan>` subinterfaces. The interface is **`e2`**, not `eth2`, and it is on the OVS net `VlanNet`.
  - The LXC `bbdd` (MariaDB) and `logs` (rsyslog on 514, D-006) live in a separate VNX XML based on `k8s_lab-vms-vlan.xml` from P1.3. It uses `exec` steps to install packages and `filetree` for configs and `authorized_keys`.
  - The VLAN ID, subnet and IPAM are still open (US-03, US-19, D-005).
- **SSH (keys only, D-004)**: two pairs, generated each day by `ssh-keygen` into the git-ignored `keys/` and loaded with `file()` into three `kubernetes_secret_v1` (never `kubectl create secret`):
  - `ssh-admin-private`: the pair 1 private key, for the admin Pod;
  - `ssh-admin-authorized`: the pair 2 public key, for host → admin;
  - `ssh-web-authorized`: the pair 1 public key, for the web Pods. The same key goes to the LXC through `filetree`.
  - Mount them with mode `0440`.
- **Services**:
  - web: `ClusterIP` 8080→80;
  - admin: `NodePort` 2222→22 with `externalTrafficPolicy: Local`. SSH goes **only** to `10.10.10.11:<nodePort>`.
- **Ingress**: class `nginx`, path `/servers-G${var.group_number}` → web Service. It needs the rewrite-target annotation.
- **NetworkPolicies**:
  - default deny for both Ingress and Egress;
  - web ingress only from the ingress-nginx controller Pods (namespaceSelector `kubernetes.io/metadata.name: ingress-nginx` AND podSelector `app.kubernetes.io/name=ingress-nginx`), on Pod port 80;
  - admin SSH only from `ipBlock 10.10.20.2/32`. `r1` routes without NAT, so the host IP is preserved.
  - Calico does **not** police the Multus/VLAN interfaces.

## Environment

The lab environment lives on temporary storage and is **rebuilt from scratch every working day**. Only this repo persists. So every step on the nodes or the LXC must be a script or Terraform in the repo, never a manual step, and the team should `git push` often.

- Scenario root on the host: `/mnt/tmp/k8s_lab-calico-v02/`. The repo is cloned at `shared/terraform-k8s-trabajofinal/` under it (see `scripts/host-script.sh`). Edit files on the host.
- `terraform` LXC VM (10.10.10.13) mounts `shared/` at `/shared`. **Run all `terraform` commands in `/shared/terraform-k8s-trabajofinal/terraform`** inside the VM (`ssh terraform`).
- Cluster:
  - `k8s-master` 10.10.10.10, `k8s-worker1` 10.10.10.11, `k8s-worker2` 10.10.10.12 (k8s v1.37, Calico on `e1`);
  - `r1` 10.10.10.1 / 10.10.20.1;
  - host 10.10.20.2 on `user_LAN`;
  - MetalLB pool `10.10.10.20-30`.
  - Details are in `docs/datos-escenario.md`.
- Multus (thick) and its NAD CRD are already installed. `whereabouts` is **not**.
- Provider: `hashicorp/kubernetes` pinned to `2.23.0`. `.terraform.lock.hcl` is not committed. Prefer the `_v1` resources.

### Daily bring-up (host)

```
/lab/cnvr/bin/get-k8s-calico                       # download the scenario into /mnt/tmp/k8s_lab-calico-v02
cd /mnt/tmp/k8s_lab-calico-v02
./bin/start-k8s-calico
sudo vnx -f k8s_lab-calico.xml -x config_metallb   # re-run: start-k8s-calico often leaves no IPAddressPool
kubectl get ipaddresspools -n metallb-system
sudo vnx -f k8s_lab-terraform.xml --create
sudo vnx -f k8s_lab-terraform.xml -x install-terraform   # re-run if `terraform --version` fails
./bin/get-master-kubeconf                          # kubeconfig → host
./bin/set-terraform-kubeconf                       # kubeconfig → terraform VM
# teardown: ./bin/stop-k8s-calico ; sudo vnx -f k8s_lab-terraform.xml --destroy
```

The host `kubectl` (v1.29) warns about version skew. If a command fails, use `ssh root@k8s-master kubectl …`. While MetalLB has no external IP, test the Ingress through its NodePort: `curl http://10.10.10.11:30097/servers-G2` (the port can change, see `datos-escenario.md` §5).

### Terraform (inside the VM)

```
terraform init                     # `rm -rf .terraform .terraform.lock.hcl` if init -upgrade fails
terraform fmt -recursive && terraform validate   # required before every commit
terraform plan / apply             # use -target only to debug one piece
terraform state list | terraform state show TYPE.NAME
terraform output [-json] [NAME]
```

Terraform loads **every `.tf` in the folder** as one configuration, so never mix the example folders into `terraform/`. At each milestone the team runs `terraform destroy && terraform apply` from clean.

## Git conventions (`docs/convenciones.md`)

- Never work directly on `main`. Use one branch per story, `us-<NN>-<descripcion-corta>`, all lowercase, with no accents or ñ.
- Commit messages: `US-<NN>: <qué se hizo, en presente>`.
- PR title: `US-<NN> · <título>`. In the PR body, copy the story's 🧪 criteria and tick the ones that were tested. Someone else reviews and merges, never the author. Merges are squashed.
- Never commit `keys/`, private keys or `*.tfstate*`.

## Gotchas

- `kubernetes_manifest` (used for the NAD) needs the CRD to exist at **plan** time.
- `host-local` IPAM allocates per node, so web Pods on different workers can get duplicate VLAN IPs (D-005, US-19).
- The web NetworkPolicy port is the **Pod** port 80, not the Service port 8080. When a peer combines namespaceSelector and podSelector, both must be in the **same** `from` block (AND), not separate ones (OR).
- NetworkPolicy can't match ICMP. A rule with no `ports` allows every protocol.
- With default-deny egress, Pods lose DNS unless egress to `kube-dns` on 53/UDP+TCP is allowed (the pattern is in `temp-terraform-examples/terraform-k8s-example/network-policy-egress-tcp-tester.tf`).
- Installing a MariaDB client with apt needs Internet egress, which deny-all blocks (D-007).
- Secret data ends up in the tfstate, which is another reason to keep the state out of git.
