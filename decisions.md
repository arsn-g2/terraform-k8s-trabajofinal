# Trabajo Final (Group 2): decision log

The report must say what we did and why, wherever we adapted or interpreted the PDF.
Add one entry per decision. Never delete an entry: if a decision changes, set the old one to `Superseded by D-xxx`.

**Status:** Proposed · Accepted · Superseded

## Template

```
### D-xxx Title
- Date / author:
- Status:
- Context: what problem or ambiguity in the PDF
- Options considered:
- Decision:
- Why:
- Consequences: what it affects (files, tests, other streams)
```

---

### D-001 Group number and Ingress path
- **Date / author:** 2026-11-06 / team
- **Status:** Accepted
- **Context:** PDF §4.3 asks for path `/servers-GX`.
- **Decision:** X = 2, so the path is `/servers-G2`. It is built from `var.group_number = 2`, not hard-coded.
- **Why:** this is our group number. A variable keeps the code reusable.

### D-002 Dedicated namespace
- **Status:** Proposed
- **Context:** the PDF doesn't name a namespace. The P1.4 objects live in `default`.
- **Options:** `default`, or a dedicated namespace such as `trabajo-final`.
- **Decision:** a dedicated namespace (`var.namespace`).
- **Why:** isolation from P1.4 leftovers, and `terraform destroy` / deny-all only affect our resources.

### D-003 Page generation: initContainer (Option B)
- **Status:** Superseded by D-009
- **Context:** PDF §3.2 allows either a sidecar or an initContainer.
- **Decision:** initContainer.
- **Why:** the Pod name never changes during the Pod's life, so generating the page once at start-up is enough. It is simpler, uses no long-running extra container, and the page exists before nginx starts.

### D-004 SSH keys generated on the host, loaded into Secrets with `file()`
- **Status:** Accepted (2026-11-17, when US-16 was completed)
- **Context:** PDF §2.5 recommends generating keys on the host and asks us to manage the Secrets with Terraform instead of kubectl.
- **Options:** `ssh-keygen` + `kubernetes_secret_v1` with `file()`, or `tls_private_key` inside Terraform.
- **Decision:** two independent **ed25519** key pairs (`par1_admin`, `par2_host`) generated with `ssh-keygen -t ed25519 -N ""` by `scripts/gen-keys.sh` (`scripts/create-keypairs.sh` is the P1.4 OpenStack script and does not apply) into the git-ignored `keys/`, regenerated every day because the environment is rebuilt, and loaded with `file()` into three `kubernetes_secret_v1`:
  - `ssh-admin-private`: pair 1 private key → admin Pod (file `id_ed25519`);
  - `ssh-admin-authorized`: pair 2 public key → admin `authorized_keys`;
  - `ssh-web-authorized`: pair 1 public key → `authorized_keys` of all web Pods (one Secret). The same public key goes to the LXC via `filetree`: `gen-keys.sh` copies it to the git-ignored `vnx/filetree/ssh/authorized_keys`.
  Pair 2's private key stays on the host. The admin Pod uses `fsGroup: 1000` and mode `0440`, as in the PDF example.
- **Why:** it follows the PDF (5 Nov version, §2.5), and the host keeps the private key it needs for host → admin. ed25519 gives short one-line keys and is the modern OpenSSH choice (support in the `nginx-ssh`/`admin-ssh` images and the LXC is checked in US-18/US-24).
- **Consequences:** Secret data still ends up in the tfstate, so the state must stay out of git.

### D-005 VLAN IPAM
- **Date / author:** 2026-11-16 / Persona A
- **Status:** Acepted.
- **Context:** the web servers are a Deployment of 3 replicas, so every Pod shares one template and one Multus annotation, and the replicas land on both workers. The P1.3 NAD uses `static` IPAM with the IP in each Pod's annotation, which a Deployment cannot do. `whereabouts` is not installed in the lab (checked 2026-11-13).
- **Options considered:**
  - `static` (as in P1.3): tested; the Pods never start (`IPAM plugin returned missing IP config`).
  - `host-local`: tested; each worker keeps its own counter, so Pods on different workers get the same IP (10.1.2.10 and .11 on both).
  - `whereabouts`: tested; one cluster-wide `IPPool` stored in the Kubernetes API; 4 replicas got 4 different IPs across both workers.
  - `dhcp` with dnsmasq in an LXC: not tested; needs the CNI `dhcp` daemon on every worker plus a DHCP server on the VLAN.
  - one `host-local` NAD per node with node affinity: discarded; a Deployment has a single annotation for all its replicas.
- **Decision:** two NADs on VLAN 1000 (`10.1.2.0/24`), both `macvlan` in `bridge` mode on `e2.1000`:
  - admin: `static` IPAM with `"capabilities": {"ips": true}` and its fixed IP (`10.1.2.5`) in the Pod annotation;
  - web Deployment: `whereabouts` IPAM, range `10.1.2.10`–`10.1.2.50`.
  The LXC keep fixed IPs in the VNX XML (`bbdd` 10.1.2.100, `logs` 10.1.2.101).
- **Why:** it is the only tested option that gives unique IPs to replicas on different workers. Its registry lives in the API, like Calico's IPAM for `eth0`. It installs with one `kubectl apply`, and the nodes can pull its image. Evidence: `docs/investigacion-multus.md` §4–§6 and §8.
- **Consequences:**
  - `whereabouts` must be installed on every lab start-up, before the web Pods (US-11). Pin a version instead of the `:latest` image.
  - Fixed IPs (admin, LXC) must stay outside the whereabouts range, because whereabouts does not know about them.
  - NetworkPolicies do not filter `net1` (§7): traffic on the VLAN is protected only by SSH keys and DB users (US-33).
  - Files: `terraform/multus.tf` (two `kubernetes_manifest` NADs), `scripts/setup-vlan-workers.sh`, the VNX XML (one VLAN, no `vlan-router`).

### D-006 Log server function
- **Status:** Accepted (2026-11-19 / Persona C, US-21)
- **Context:** the PDF names a "servidor de logs" but does not define what it does.
- **Decision:** rsyslog receiving remote syslog (UDP/TCP 514) from Pods.
- **Consequences:** `vnx/vnx-vm-bdd-logs.xml` gives `logs` an `<exec>` (install `rsyslog`+`openssh-server`) and `<filetree>` (`filetree/logs/10-remote.conf` loads `imudp`/`imtcp` on 514 and stores remote logs under `/var/log/remote/<host>/`, plus the par-1 `authorized_keys`). Test: `logger -n 10.1.2.101 prueba` from a Pod leaves the line on the LXC.

### D-007 DB client and default-deny egress
- **Status:** Pending (US-23)
- **Context:** installing a MariaDB client with apt needs Internet egress, which the deny-all policy blocks.

### D-008 Spec version followed
- **Date / author:** 2026-11-13 / team
- **Status:** Accepted
- **Context:** the PDF was updated from the 28 Oct 2026 version to the **5 Nov 2026** version. Only §2 changed: the images are now named (§2.1), the SSH key direction is corrected and split into two key pairs (§2.5), and there are new hints on Secrets (`defaultMode`/`mode` 0440, `fsGroup: 1000`) and on creating them with Terraform instead of kubectl. §1, §3, §4, §5 and the topology figure are unchanged.
- **Decision:** we follow the 5 Nov version (`ARSN-trabajo-final-26-27.pdf`). The old one is in git history only.
- **Why:** it is the latest, and it resolves the key-direction ambiguity we had flagged.
- **Consequences:** D-004, US-03, US-16 and US-17 were updated. Note: the new §2.4 says "seguir las recomendaciones del paso 4", which refers to itself; we read it as step 5.

### D-009 Page generation: sidecar container (Option A)
- **Date / author:** 2026-11-16 / B
- **Status:** Proposed
- **Context:** PDF §3.2 allows either a sidecar (Option A) or an initContainer (Option B). D-003 had proposed B.
- **Options considered:** A, a second `container` in the Pod that writes `index.html` into a shared `emptyDir` and stays running; B, an `init_container` that writes it once and exits.
- **Decision:** Option A (sidecar).
- **Why:** to learn and show the sidecar pattern (containers sharing a volume, parallel lifecycle), which is also what you need when content changes while the Pod runs. B would be enough for a value that never changes, such as the Pod name.
- **Consequences:** the sidecar must stay alive after writing the page (for example `sleep infinity`); otherwise the kubelet restarts it and the Pod goes into `CrashLoopBackOff`. Nginx can start before the page exists, so the first requests may return 403/404 for a moment. The sidecar runs for the Pod's whole life. US-14 (`historias/persona-b.md`) and `docs/useful/web/guia-web.md` §3.3 describe Option B and need updating.

### D-010 One shared VLAN: 1000, 10.1.2.0/24
- **Date / author:** 2026-11-16 / Persona A, agreed by the team
- **Status:** Accepted
- **Context:** the PDF (§1 and §2) describes one VLAN shared by the web Pods, the admin Pod and the two LXC. The P1.3 template `k8s_lab-vms-vlan.xml`, which our `vnx/` files are based on, has two VLANs (1000 and 1001) joined by a `vlan-router`.
- **Options considered:** keep the template's two VLANs and the router, with `bbdd` on 1000 and `logs` on 1001; or one VLAN for everything.
- **Decision:** one VLAN, ID 1000, subnet `10.1.2.0/24`. Addressing plan: admin `10.1.2.5` (static), web Pods `10.1.2.10`–`10.1.2.50` (whereabouts, D-005), `bbdd` `10.1.2.100`, `logs` `10.1.2.101`.
- **Why:** it is what the PDF describes. VLAN 1000 and `10.1.2.0/24` were tested with Calico in US-19 (`docs/investigacion-multus.md` §2–§3). One VLAN needs no router and fewer moving parts.
- **Consequences:** `logs` moves to VLAN 1000 and the `vlan-router` is removed from the VNX files (US-12). `scripts/setup-vlan-workers.sh` creates only `e2.1000` (US-10). Terraform uses `vlan_id = 1000` and `vlan_subnet = "10.1.2.0/24"` (US-11).


### D-011 whereabouts installed by a script on every start-up
- **Date / author:** 2026-11-17 / Persona A
- **Status:** Proposed
- **Context:** D-005 picks `whereabouts` for the web Pods. The scenario does not include it and is rebuilt from scratch every day, so it has to be installed every time (US-11).
- **Options considered:** install it from Terraform (one `kubernetes_manifest` per object of the upstream YAML); or a script run at start-up, like `setup-vlan-workers.sh`.
- **Decision:** `scripts/setup-whereabouts.sh`, run on every start-up after `./bin/get-master-kubeconf` and before `terraform apply`. It installs a fixed release, `v0.9.4`, and pins the image to the same tag instead of `:latest`.
- **Why:** whereabouts belongs to the cluster, like Multus: a DaemonSet in `kube-system` that copies the IPAM plugin to every node, plus two CRDs. It is not part of our application, and `terraform destroy` should not remove it. A fixed tag makes every start-up install the same version.
- **Consequences:** start-up order: `setup-vlan-workers.sh` → `setup-whereabouts.sh` → VNX → `terraform apply`. If the script has not run, the web Pods stay in `ContainerCreating` because the node has no `whereabouts` plugin. `docs/datos-escenario.md` §1 and §4 describe it.

### D-012 Database engine: MySQL instead of the proposed MariaDB
- **Date / author:** 2026-11-19 / Persona C (US-20)
- **Status:** Accepted
- **Context:** PDF *proposes* installing MariaDB on the `bbdd` LXC, but that is a recommendation, not a hard requirement. The teacher suggested MySQL as a good DB too.
- **Options considered:** MariaDB  or MySQL.
- **Decision:** MySQL 8.0 (`mysql-server`) on `bbdd`, installed with a VNX `<exec>` and configured with `<filetree>`.
- **Why:** instructor's suggestion; MySQL meets the same "database server" requirement and is apt-installable on the LXC (Internet egress via `eth9`/virbr0). Since the PDF only *proposes* MariaDB, this is a documented deviation, not a conflict.
- **Consequences:**
  - `vnx/vnx-vm-bdd-logs.xml`: `bbdd` gains `<exec>` (install `mysql-server`+`openssh-server`, enable, load SQL) and `<filetree>` (bind-address drop-in, `init.sql`, `authorized_keys`).
  - The bind-address drop-in goes to `/etc/mysql/mysql.conf.d/` (MySQL path), not `/etc/mysql/mariadb.conf.d/`.
  - The app user is created with `mysql_native_password` to avoid `caching_sha2_password` client issues.
  - The real `init.sql` (with the DB password) stays out of Git (`.gitignore`); only `init.sql.example` is committed, and the password is shared with B and C privately.
  - D-007 (DB client on the Pods) now refers to the MySQL client, not MariaDB.
  - Docs still saying "MariaDB" (persona-a US-20, CLAUDE.md, datos-escenario) need a wording pass; not done yet.
