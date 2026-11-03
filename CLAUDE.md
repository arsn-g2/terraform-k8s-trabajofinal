# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project status

This is the final assignment for the CNVR/ARSN course (2026-27): **automated deployment of a scalable web app on Kubernetes using Terraform**. the spec is in `arsn-trabajo-final-26-27.pdf` (in Spanish). The PDF is the source of truth. Re-read it (`pdftotext -layout arsn-trabajo-final-26-27.pdf -`) if a requirement below is unclear. Update this file once real code and commands exist.

The team's work plan is in Spanish. `plan.md` has the split between three owners, the phases, the milestones (H0–H3), the handoffs between people, and the proposed repo layout (`terraform/`, `vnx/`, `scripts/`, `docs/`), including which `.tf` file each person owns. The user stories (HU-00…HU-42) are in `historias/`, one file per owner. Each story has an `<a id="hu-NN">` anchor and the files link to each other, so keep those anchors and links working when editing. The shared final story HU-43 is in `plan.md`. Follow that layout and reference story IDs when working on a task.

## Commands

Standard Terraform workflow, using the `hashicorp/kubernetes` provider against the course's Kubernetes lab cluster:

```
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
terraform destroy
terraform apply -target=<resource_address>   # iterate on one resource
```

The VNX scenario (the LXC containers) is managed separately from Terraform with the `vnx` tool (e.g. `vnx -f <scenario>.xml --create` / `--destroy`).

## Target architecture

Two scenarios share one VLAN:

1. **Kubernetes cluster** (Calico CNI, lab scenario from práctica 1.4; workers `k8s-worker1` and `k8s-worker2`), with every resource defined in Terraform:
   - **Web Deployment**: 3 Nginx replicas, using the course-provided image (it already includes sshd).
   - **Admin Pod**: course-provided image. `nodeSelector` pins it to `k8s-worker1`.
2. **VNX scenario**: LXC containers for **MariaDB** and a **log server**. Start from `k8s_lab-vms-vlan.xml` (práctica 1.3). Install packages and enable SSH with `<exec>` steps, and copy config files and authorized SSH keys in with `<filetree>`. The containers attach to `VlanNet`, which is shared with the worker nodes.

### Requirements that span several resources

- **VLAN + Multus**: create VLAN subinterfaces on both workers, as in práctica 1.3. Define `NetworkAttachmentDefinition` resources with `kubernetes_manifest`, since the provider has no native resource for that CRD. Add the extra interface to both the web Pods and the admin Pod. The admin Pod and the web Pods must both be able to manage the DB over the VLAN.
- **SSH via Secrets**: use key-based authentication only, with no passwords. The admin Pod connects to the web servers and the LXC containers over the VLAN.
  - The spec's wording is that web servers get "the private key" and admin gets "the public key as authorized key". That looks reversed relative to the stated goal (admin SSHes into the web servers). Ask the user about this ambiguity before implementing it.
- **Per-Pod page**: a `ConfigMap` holds an `index.html` template with a placeholder. Either an initContainer or a sidecar reads the template, replaces the placeholder with the Pod name (Downward API `metadata.name`), and writes the result to a shared writable volume (e.g. `emptyDir`) that Nginx serves. The ConfigMap volume is mounted read-only.
- **Services**:
  - Web: `ClusterIP`, port 8080 → targetPort 80.
  - Admin: `NodePort`, port 2222 → targetPort 22, with `externalTrafficPolicy: Local`. This preserves the client source IP, which the NetworkPolicy depends on. Clients SSH to the IP of `k8s-worker1` on the assigned nodePort.
- **Ingress**: path `/servers-GX` → web Service, where `X` is the lab group number. Ask the user for the number if it isn't known.
- **NetworkPolicies**:
  1. Default-deny for both Ingress and Egress on the selected Pods.
  2. Web Pods accept ingress only from the ingress-nginx controller Pods: `namespaceSelector` `kubernetes.io/metadata.name: ingress-nginx` plus a `podSelector` on the controller's labels (look them up with `kubectl get pods -n ingress-nginx --show-labels`).
  3. Admin Pod accepts TCP/22 only from the host's IP on `user_LAN`, as an `ipBlock` /32 CIDR (see the topology figure in práctica 1.4).
  - Default-deny also blocks the Pod-to-Pod and Pod-to-LXC SSH/DB traffic. Check that the policies still allow the required VLAN traffic, or that Multus secondary interfaces fall outside Calico policy enforcement.


