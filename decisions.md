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
- **Status:** Pending (US-19)
- **Context:** `host-local` IPAM can give the same IP to Pods on different workers. `whereabouts` is **not** installed in the lab (checked 2026-11-13); available CNI plugins include `macvlan`, `vlan`, `host-local`, `static` and `dhcp`.
- **Options:** `static` for the admin plus, for the web Deployment: install `whereabouts`; `dhcp` IPAM with dnsmasq in an LXC; or per-node `host-local` NADs with node affinity.

### D-006 Log server function
- **Status:** Proposed (US-21)
- **Context:** the PDF names a "servidor de logs" but does not define what it does.
- **Decision:** rsyslog receiving remote syslog (UDP/TCP 514) from Pods.

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
