# 🗺️ Plan de trabajo: Trabajo Final ARSN/CNVR 2026-27

**Objetivo:** desplegar automáticamente, con Terraform, una aplicación web escalable sobre Kubernetes (Calico + Multus). La aplicación se conecta por una VLAN compartida a un escenario VNX con contenedores LXC (MariaDB y servidor de logs).

**Equipo:** 3 personas (**Persona A**, **Persona B** y **Persona C**). Reemplacen los nombres cuando repartan los roles.

**Fuente de verdad:** `arsn-trabajo-final-26-27.pdf`. Si este plan contradice el enunciado, manda el enunciado.

🧭 **Fases y dependencias, historia por historia:** [fases.md](fases.md)

📂 **Historias de cada persona:**
- 🌐 [Persona A: Red y VNX](historias/persona-a.md)
- 🖥️ [Persona B: Aplicación web](historias/persona-b.md)
- 🔐 [Persona C: Seguridad y administración](historias/persona-c.md)

---

<a id="leyenda"></a>
## 🔖 Leyenda de emojis

| Emoji | Significado |
|---|---|
| 🔀 | **Punto de merge o integración**: el trabajo de 2 o más personas se junta. Pruébenlo juntos |
| 🤝 | **Entrega a otra persona**: al terminar, avisen al compañero que lo necesita |
| ⛔ | **Bloqueante**: otras historias esperan esta, así que va primero |
| 🚩 | **Hito**: cierre de fase (despliegue de cero con los tres presentes) |
| 🏁 | Entrega final |
| ⚠️ | Trampa conocida o detalle fácil de olvidar |
| 🧪 | Criterios de aceptación (cómo se comprueba que está lista) |

Iconos de tipo de historia: 🏗️ preparación · 🌐 red · 🖥️ web · 🔑 SSH · 🛡️ NetworkPolicy · ✅ verificación · 📝 documentación

---

<a id="reparto"></a>
## 1. 👥 Reparto por áreas

| Persona | Área | Qué le toca | Historias |
|---|---|---|---|
| **A** | 🌐 **Red y VNX** | Subinterfaces VLAN en los workers, `NetworkAttachmentDefinition` (Multus), escenario VNX, LXC de MariaDB y del servidor de logs | [persona-a.md](historias/persona-a.md) |
| **B** | 🖥️ **Aplicación web** | Esqueleto de Terraform, ConfigMap, Deployment de Nginx con la página personalizada, Service ClusterIP, Ingress, script de verificación | [persona-b.md](historias/persona-b.md) |
| **C** | 🔐 **Seguridad y administración** | Repositorio, claves SSH y Secrets, Pod admin, Service NodePort, NetworkPolicies, memoria final | [persona-c.md](historias/persona-c.md) |

**Reglas del equipo:**
- Nadie hace *merge* de su propio trabajo. Cada historia la revisa otra persona del equipo, de preferencia de otra área, para que los tres conozcan todo el proyecto (la defensa puede ser individual).
- Cada quien trabaja en su propio archivo `.tf` (ver la [sección 3](#estructura)) para minimizar conflictos de Git.
- ⚠️ Ninguna clave privada ni ningún `terraform.tfstate` se suben al repositorio.

---

<a id="dudas"></a>
## 2. ❓ Dudas que hay que resolver antes de empezar

⛔ Resolverlas con el profesor en la Fase 0 ([HU-03](historias/persona-c.md#hu-03)), porque bloquean historias posteriores.

1. **Dirección de las claves SSH.** El apartado 2.5 del enunciado dice que a los servidores web se les da la *clave privada* y al admin la *clave pública* como autorizada. Eso parece al revés del objetivo (el admin es quien entra por SSH a los web). Confirmar cuál es la interpretación correcta. Si se requiere acceso en ambos sentidos, se usan dos pares de claves.
2. **Número de grupo `X`**, para la ruta del Ingress `/servers-GX`.
3. **ID de VLAN y subred** de la red compartida (por ejemplo, VLAN 100 y `10.100.0.0/24`). Revisar si la práctica 1.3 ya trae valores asignados.
4. **Nombres y tags de las imágenes** que va a dar el profesor para el web y el admin. Revisar también qué incluyen: `sshd`, cliente `mysql`/`mariadb`, `ip`, `ping`.
5. **IP del host en `user_LAN`** (Figura 2 de la práctica 1.4), que es la única IP con permiso de SSH al admin.
6. **¿El servidor de logs necesita algún servicio concreto** (por ejemplo, rsyslog recibiendo en 514/UDP), o basta con que exista en la VLAN y acepte SSH?

---

<a id="estructura"></a>
## 3. 📁 Estructura propuesta del repositorio

```
.
├── CLAUDE.md
├── plan.md                     # este archivo
├── historias/
│   ├── persona-a.md
│   ├── persona-b.md
│   └── persona-c.md
├── README.md                   # cómo desplegar de cero (HU-42)
├── terraform/
│   ├── providers.tf            # B: provider kubernetes (+ tls/local si se usan)
│   ├── variables.tf            # B: grupo, namespace, IPs, imágenes, VLAN
│   ├── terraform.tfvars.example
│   ├── outputs.tf              # B: IPs, nodePort, URL del Ingress
│   ├── namespace.tf            # B
│   ├── multus.tf               # A: NetworkAttachmentDefinition
│   ├── web.tf                  # B: ConfigMap, Deployment, Service, Ingress
│   ├── ssh.tf                  # C: claves y Secrets
│   ├── admin.tf                # C: Pod/Deployment admin y Service NodePort
│   └── netpol.tf               # C (+B): NetworkPolicies
├── vnx/
│   ├── k8s_lab-vms-vlan.xml    # A: escenario adaptado
│   └── filetree/               # A: configs de MariaDB, authorized_keys, etc.
├── scripts/
│   ├── setup-vlan-workers.sh   # A: subinterfaces VLAN en los workers
│   └── verify.sh               # B: pruebas automáticas
└── docs/
    └── capturas/               # C: evidencias para la memoria
```

`.gitignore` mínimo: `.terraform/`, `*.tfstate*`, `*.tfvars` (excepto el `.example`), `keys/`, `id_*`.

---

<a id="fases"></a>
## 4. 🧭 Fases y dependencias

📄 Versión detallada, con cada historia, su responsable y sus dependencias: [fases.md](fases.md)

```
Fase 0  🏗️ Preparación ─────────►  HU-00, HU-01, HU-02, HU-03 ⛔
                                        │
                                   🚩 H0: repo + Terraform base + dudas resueltas
                                        │
Fase 1  ⚙️ Componentes en paralelo ►  A: HU-10 → HU-11 ⛔      HU-12
                                      B: HU-13 → HU-14 → HU-15
                                      C: HU-16 🤝 → HU-17 → HU-18
                                        │
                                   🚩 H1: cada componente funciona por separado
                                        │
Fase 2  🔀 Integración por VLAN ──►  A: HU-20 🤝, HU-21      (necesitan HU-12 y HU-16)
                                      B: HU-22 🔀 → HU-23 🔀  (necesitan HU-11, HU-14, HU-20)
                                      C: HU-24 🔀            (necesita HU-11, HU-17, HU-20)
                                        │
                                   🚩 H2: todo conectado por la VLAN
                                        │
Fase 3  🛡️ NetworkPolicies ───────►  C: HU-30 ⛔ → HU-32
                                      B: HU-31               (necesita HU-30)
                                      A: HU-33 🔀            (necesita HU-30, HU-24)
                                        │
                                   🚩 H3: seguridad aplicada sin romper nada
                                        │
Fase 4  ✅ Verificación y entrega ►  B: HU-40   A: HU-41 🔀   C: HU-42   Todos: HU-43
                                        │
                                   🏁 Entrega
```

**Calendario sugerido** (ajústenlo a la fecha de entrega real): cada fase dura aproximadamente 1 semana, y la Fase 0 dura de 1 a 2 días.

### Índice de historias en orden de desarrollo

| Fase | Persona A 🌐 | Persona B 🖥️ | Persona C 🔐 |
|---|---|---|---|
| 0 🏗️ | [HU-02](historias/persona-a.md#hu-02) | [HU-01](historias/persona-b.md#hu-01) | [HU-00](historias/persona-c.md#hu-00), [HU-03](historias/persona-c.md#hu-03) ⛔ |
| 1 ⚙️ | [HU-10](historias/persona-a.md#hu-10), [HU-11](historias/persona-a.md#hu-11) ⛔🤝, [HU-12](historias/persona-a.md#hu-12) | [HU-13](historias/persona-b.md#hu-13), [HU-14](historias/persona-b.md#hu-14) 🤝, [HU-15](historias/persona-b.md#hu-15) | [HU-16](historias/persona-c.md#hu-16) 🤝, [HU-17](historias/persona-c.md#hu-17) 🔀, [HU-18](historias/persona-c.md#hu-18) |
| 2 🔀 | [HU-20](historias/persona-a.md#hu-20) 🤝, [HU-21](historias/persona-a.md#hu-21) | [HU-22](historias/persona-b.md#hu-22) 🔀, [HU-23](historias/persona-b.md#hu-23) 🔀 | [HU-24](historias/persona-c.md#hu-24) 🔀 |
| 3 🛡️ | [HU-33](historias/persona-a.md#hu-33) 🔀 | [HU-31](historias/persona-b.md#hu-31) | [HU-30](historias/persona-c.md#hu-30) ⛔, [HU-32](historias/persona-c.md#hu-32) |
| 4 ✅ | [HU-41](historias/persona-a.md#hu-41) 🔀 | [HU-40](historias/persona-b.md#hu-40) | [HU-42](historias/persona-c.md#hu-42) 📝 |

---

<a id="hitos"></a>
## 5. 🚩 Hitos

En cada hito los tres se juntan, hacen `terraform destroy && terraform apply` en limpio y comprueban los criterios del hito antes de seguir a la siguiente fase.

| Hito | Se cumple cuando… |
|---|---|
| 🚩 **H0: Arranque** | Repo creado ([HU-00](historias/persona-c.md#hu-00)), `terraform apply` crea el namespace ([HU-01](historias/persona-b.md#hu-01)), datos del escenario documentados ([HU-02](historias/persona-a.md#hu-02)), las 6 dudas resueltas ([HU-03](historias/persona-c.md#hu-03)) |
| 🚩 **H1: Componentes listos** | La VLAN y la NAD funcionan con un Pod de prueba, los LXC hacen ping, `curl /servers-GX` balancea entre 3 Pods, el SSH al admin por NodePort funciona |
| 🚩 **H2: Integración por VLAN** 🔀 | Ping y SSH entre web ↔ admin ↔ `bbdd` ↔ `logs` por la VLAN, y `mysql` funciona desde los web y desde el admin |
| 🚩 **H3: Seguridad aplicada** | Las 3 NetworkPolicies están activas y todas las pruebas de H1 y H2 siguen pasando. Las pruebas negativas (acceso no autorizado) fallan |
| 🏁 **Entrega** | `verify.sh` en verde tras un despliegue de cero en otra computadora, memoria lista, demo ensayada (HU-43) |

<a id="hu-43"></a>
### 🏁 HU-43 · Ensayo de la demo · Todos · Depende de: [HU-42](historias/persona-c.md#hu-42)
Ensayar la demo completa, cronometrada. Cada persona explica un área que **no** sea la suya.
- 🧪 Los tres pueden contestar preguntas sobre cualquier recurso.

---

<a id="carga"></a>
## 6. ⚖️ Resumen de carga por persona

| Persona | Historias | Puntos |
|---|---|---|
| 🌐 **A** (Red y VNX) | HU-02 (2), HU-10 (3), HU-11 (5), HU-12 (5), HU-20 (5), HU-21 (3), HU-33 (3), HU-41 (3) | **29** |
| 🖥️ **B** (Web) | HU-01 (3), HU-13 (2), HU-14 (5), HU-15 (3), HU-22 (3), HU-23 (3), HU-31 (5), HU-40 (5) | **29** |
| 🔐 **C** (Seguridad) | HU-00 (2), HU-03 (1), HU-16 (3), HU-17 (5), HU-18 (3), HU-24 (5), HU-30 (3), HU-32 (5), HU-42 (3) | **30** |

Escala: 1 = menos de 1 h, 2 = medio día, 3 = 1 día, 5 = 2 a 3 días (incluye investigar y depurar).

---

<a id="coordinacion"></a>
## 7. 🤝 Puntos de coordinación entre áreas

| Entrega | De → a | Cuándo |
|---|---|---|
| 🤝 Plan de direccionamiento VLAN (IPs y rangos) | A → B, C | Al terminar [HU-11](historias/persona-a.md#hu-11) |
| 🤝 Clave pública para el `filetree` de los LXC | C → A | Al terminar [HU-16](historias/persona-c.md#hu-16) |
| 🤝 Labels de los Pods (`app = web`, `app = admin`) | B, C → C | Al terminar [HU-14](historias/persona-b.md#hu-14) y [HU-17](historias/persona-c.md#hu-17) (las usan las NetworkPolicies) |
| 🔀 Montaje del Secret SSH en el Deployment web | C → B | Al terminar [HU-17](historias/persona-c.md#hu-17) (cambio en `web.tf`) |
| 🤝 Credenciales e IP de MariaDB | A → B, C | Al terminar [HU-20](historias/persona-a.md#hu-20) |

---

<a id="riesgos"></a>
## 8. ⚠️ Riesgos y cómo cubrirlos

| Riesgo | Mitigación |
|---|---|
| Multus o el plugin CNI no están instalados en el escenario | Revisarlo en [HU-02](historias/persona-a.md#hu-02). Si falta, avisar al profesor de inmediato |
| `kubernetes_manifest` falla en el `plan` porque no existe el CRD | Aplicar en dos pasos (`-target`) o confirmar que Multus está antes del `apply` |
| Permisos de las claves SSH en volúmenes de Secret | `default_mode`, o copiarlas con un initContainer ([HU-17](historias/persona-c.md#hu-17)) |
| La IP de origen no se preserva y la política del admin bloquea al host | `externalTrafficPolicy: Local` y conectar **solo** a la IP de `k8s-worker1` ([HU-32](historias/persona-c.md#hu-32)) |
| Default-deny rompe DNS o tráfico que no se esperaba | Validación explícita en [HU-33](historias/persona-a.md#hu-33) |
| Una sola persona sabe cómo funciona su área | Revisión cruzada obligatoria y [HU-43](#hu-43) |
