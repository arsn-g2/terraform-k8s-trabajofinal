# 🗺️ Plan de trabajo: Trabajo Final ARSN/CNVR 2026-27

**Objetivo:** desplegar automáticamente, con Terraform, una aplicación web escalable sobre Kubernetes (Calico + Multus). La aplicación se conecta por una VLAN compartida a un escenario VNX con contenedores LXC (MariaDB y servidor de logs).

**Equipo:** 3 personas (**Persona A**, **Persona B** y **Persona C**). Reemplacen los nombres cuando repartan los roles.

**Fuente de verdad:** `ARSN-trabajo-final-26-27.pdf`, **versión del 5 de noviembre de 2026** ([D-008](decisions.md)). Si este plan contradice el enunciado, manda el enunciado.

**Decisiones de diseño:** [decisions.md](decisions.md) (entregable obligatorio: toda adaptación del enunciado lleva su entrada).

**Entorno:** escenario `k8s_lab-calico` en `/mnt/tmp/k8s_lab-calico-v02` y VM `terraform`, donde se corre Terraform. Cómo levantarlo y datos medidos: [US-02](historias/persona-a.md#us-02).

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
| ✅ / ⬜ | Columna **Completed**: historia terminada (cumple sus 🧪) / pendiente. Al cerrar una historia, cambiar ⬜ por ✅ en [fases.md](fases.md) y en el archivo de su persona |

Iconos de tipo de historia: 🏗️ preparación · 🌐 red · 🖥️ web · 🔑 SSH · 🛡️ NetworkPolicy · 🔵 verificación · 📝 documentación

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
## 2. ❓ Dudas: estado

La versión del enunciado del **5 de noviembre de 2026** y el entorno desplegado ([US-02](historias/persona-a.md#us-02)) resolvieron casi todo. Lo que queda abierto se cierra en [US-03](historias/persona-c.md#us-03) y se registra en [decisions.md](decisions.md).

| # | Duda | Estado |
|---|---|---|
| 1 | Dirección de las claves SSH | ✅ Enunciado §2.5: **dos pares**. Par 1 (admin → web/LXC): privada en el admin, pública en los web y los LXC. Par 2 (host → admin): privada en el host, pública en el admin ([D-004](decisions.md)) |
| 2 | Número de grupo `X` | ✅ Grupo 2, ruta `/servers-G2` ([D-001](decisions.md)) |
| 3 | ID de VLAN y subred | ⏳ **Abierta.** Como referencia, `k8s_lab-vms-vlan.xml` usa los tags 1000/1001 con `10.1.2.0/24` y `10.1.3.0/24` |
| 4 | Imágenes | ✅ Enunciado §2.1: `dgsgiros/nginx-ssh:latest` (`webuser`) y `dgsgiros/admin-ssh:latest` (`adminuser`), ambos GID 1000 y con `sudo`. Traen ping, nmap, curl, ip e ifconfig. Falta comprobar si traen cliente de MariaDB ([D-007](decisions.md)) |
| 5 | IP del host en `user_LAN` | ✅ `10.10.20.2` |
| 6 | Función del servidor de logs | ⏳ Propuesta: rsyslog en 514 UDP/TCP ([D-006](decisions.md)) |
| 7 | IPAM de la VLAN | ⏳ **Abierta.** `whereabouts` no está instalado. Se investiga en [US-19](historias/persona-a.md#us-19) ([D-005](decisions.md)) |

---

<a id="estructura"></a>
## 3. 📁 Estructura propuesta del repositorio

```
.
├── CLAUDE.md
├── plan.md                     # este archivo
├── fases.md
├── decisions.md                # registro de decisiones (entregable)
├── historias/
│   ├── persona-a.md
│   ├── persona-b.md
│   └── persona-c.md
├── README.md                   # cómo desplegar de cero (US-42)
├── terraform/
│   ├── providers.tf            # B: provider kubernetes (+ tls/local si se usan)
│   ├── variables.tf            # B: group_number, namespace, IPs, imágenes, VLAN
│   ├── terraform.tfvars.example
│   ├── outputs.tf              # B: IPs, nodePort, URL del Ingress
│   ├── namespace.tf            # B
│   ├── multus.tf               # A: NetworkAttachmentDefinition
│   ├── web.tf                  # B: ConfigMap, Deployment, Service, Ingress
│   ├── ssh.tf                  # C: 3 Secrets SSH (kubernetes_secret_v1)
│   ├── admin.tf                # C: Pod/Deployment admin y Service NodePort
│   └── netpol.tf               # C (+B): NetworkPolicies
├── vnx/
│   ├── k8s_lab-vms-vlan.xml    # A: escenario adaptado
│   └── filetree/               # A: configs de MariaDB, authorized_keys, etc.
├── keys/                       # C: los 2 pares de claves (ignorada por Git)
├── scripts/
│   ├── gen-keys.sh             # C: genera los 2 pares con ssh-keygen
│   ├── setup-vlan-workers.sh   # A: subinterfaces e2.<vlan> en los workers
│   └── verify.sh               # B: pruebas automáticas
└── docs/
    ├── convenciones.md
    ├── datos-escenario.md      # A: datos del entorno (US-02)
    ├── useful/
    │   ├── multus/             # guía Multus/VLAN + ficheros de P1.3 (p13/)
    │   ├── metallb/            # guía MetalLB/Ingress + ficheros de P1.3 (p13/)
    │   └── web/                # guía Deployment/ConfigMap + ficheros de P1.3 (p13/)
    └── capturas/               # C: evidencias para la memoria
```

`.gitignore` mínimo: `.terraform/`, `*.tfstate*`, `*.tfvars` (excepto el `.example`), `keys/`, `id_*`. ⚠️ Hoy las líneas de claves están comentadas ([US-00](historias/persona-c.md#us-00)).

---

<a id="fases"></a>
## 4. 🧭 Fases y dependencias

📄 Versión detallada, con cada historia, su responsable y sus dependencias: [fases.md](fases.md)

```
Fase 0  🏗️ Preparación ─────────►  US-00, US-01, US-02, US-03 ⛔
                                        │
                                   🚩 H0: repo + Terraform base + dudas resueltas
                                        │
Fase 1  ⚙️ Componentes en paralelo ►  A: US-19 ⛔ → US-10 → US-11 ⛔   US-12
                                      B: US-13 → US-14 → US-15
                                      C: US-16 🤝 → US-17 → US-18
                                        │
                                   🚩 H1: cada componente funciona por separado
                                        │
Fase 2  🔀 Integración por VLAN ──►  A: US-20 🤝, US-21      (necesitan US-12 y US-16)
                                      B: US-22 🔀 → US-23 🔀  (necesitan US-11, US-14, US-20)
                                      C: US-24 🔀            (necesita US-11, US-17, US-20)
                                        │
                                   🚩 H2: todo conectado por la VLAN
                                        │
Fase 3  🛡️ NetworkPolicies ───────►  C: US-30 ⛔ → US-32
                                      B: US-31               (necesita US-30)
                                      A: US-33 🔀            (necesita US-30, US-24)
                                        │
                                   🚩 H3: seguridad aplicada sin romper nada
                                        │
Fase 4  🔵 Verificación y entrega ►  B: US-40   A: US-41 🔀   C: US-42   Todos: US-43
                                        │
                                   🏁 Entrega
```

**Calendario sugerido** (ajústenlo a la fecha de entrega real): cada fase dura aproximadamente 1 semana, y la Fase 0 dura de 1 a 2 días.

### Índice de historias en orden de desarrollo

| Fase | Persona A 🌐 | Persona B 🖥️ | Persona C 🔐 |
|---|---|---|---|
| 0 🏗️ | [US-02](historias/persona-a.md#us-02) | [US-01](historias/persona-b.md#us-01) | [US-00](historias/persona-c.md#us-00), [US-03](historias/persona-c.md#us-03) ⛔ |
| 1 ⚙️ | [US-19](historias/persona-a.md#us-19) ⛔, [US-10](historias/persona-a.md#us-10), [US-11](historias/persona-a.md#us-11) ⛔🤝, [US-12](historias/persona-a.md#us-12) | [US-13](historias/persona-b.md#us-13), [US-14](historias/persona-b.md#us-14) 🤝, [US-15](historias/persona-b.md#us-15) | [US-16](historias/persona-c.md#us-16) 🤝, [US-17](historias/persona-c.md#us-17) 🔀, [US-18](historias/persona-c.md#us-18) |
| 2 🔀 | [US-20](historias/persona-a.md#us-20) 🤝, [US-21](historias/persona-a.md#us-21) | [US-22](historias/persona-b.md#us-22) 🔀, [US-23](historias/persona-b.md#us-23) 🔀 | [US-24](historias/persona-c.md#us-24) 🔀 |
| 3 🛡️ | [US-33](historias/persona-a.md#us-33) 🔀 | [US-31](historias/persona-b.md#us-31) | [US-30](historias/persona-c.md#us-30) ⛔, [US-32](historias/persona-c.md#us-32) |
| 4 🔵 | [US-41](historias/persona-a.md#us-41) 🔀 | [US-40](historias/persona-b.md#us-40) | [US-42](historias/persona-c.md#us-42) 📝 |

---

<a id="hitos"></a>
## 5. 🚩 Hitos

En cada hito los tres se juntan, hacen `terraform destroy && terraform apply` en limpio y comprueban los criterios del hito antes de seguir a la siguiente fase.

| Hito | Se cumple cuando… |
|---|---|
| 🚩 **H0: Arranque** | Repo creado ([US-00](historias/persona-c.md#us-00)), `terraform apply` crea el namespace ([US-01](historias/persona-b.md#us-01)), datos del escenario documentados ([US-02](historias/persona-a.md#us-02)), las dudas abiertas cerradas en `decisions.md` ([US-03](historias/persona-c.md#us-03)) |
| 🚩 **H1: Componentes listos** | La VLAN y la NAD funcionan con un Pod de prueba, los LXC hacen ping, `curl /servers-G2` balancea entre 3 Pods, el SSH al admin por NodePort funciona |
| 🚩 **H2: Integración por VLAN** 🔀 | Ping y SSH entre web ↔ admin ↔ `bbdd` ↔ `logs` por la VLAN, y `mysql` funciona desde los web y desde el admin |
| 🚩 **H3: Seguridad aplicada** | Las 3 NetworkPolicies están activas y todas las pruebas de H1 y H2 siguen pasando. Las pruebas negativas (acceso no autorizado) fallan |
| 🏁 **Entrega** | `verify.sh` en verde tras un despliegue de cero en otra computadora, memoria lista, demo ensayada (US-43) |

<a id="us-43"></a>
### 🏁 US-43 · Ensayo de la demo · Todos · Depende de: [US-42](historias/persona-c.md#us-42)
**Completed:** ⬜

Ensayar la demo completa, cronometrada. Cada persona explica un área que **no** sea la suya.
- 🧪 Los tres pueden contestar preguntas sobre cualquier recurso.

---

<a id="carga"></a>
## 6. ⚖️ Resumen de carga por persona

| Persona | Historias | Puntos |
|---|---|---|
| 🌐 **A** (Red y VNX) | US-02 (2), US-19 (3), US-10 (3), US-11 (3), US-12 (5), US-20 (5), US-21 (3), US-33 (3), US-41 (3) | **30** |
| 🖥️ **B** (Web) | US-01 (3), US-13 (2), US-14 (5), US-15 (3), US-22 (3), US-23 (3), US-31 (5), US-40 (5) | **29** |
| 🔐 **C** (Seguridad) | US-00 (2), US-03 (1), US-16 (3), US-17 (5), US-18 (3), US-24 (5), US-30 (3), US-32 (5), US-42 (3) | **30** |

Escala: 1 = menos de 1 h, 2 = medio día, 3 = 1 día, 5 = 2 a 3 días (incluye investigar y depurar).

---

<a id="coordinacion"></a>
## 7. 🤝 Puntos de coordinación entre áreas

| Entrega | De → a | Cuándo |
|---|---|---|
| 🤝 Plan de direccionamiento VLAN (IPs y rangos) | A → B, C | Al terminar [US-11](historias/persona-a.md#us-11) |
| 🤝 Clave pública del par 1 para el `filetree` de los LXC | C → A | Al terminar [US-16](historias/persona-c.md#us-16) |
| 🤝 Labels de los Pods (`app = web`, `app = admin`) | B, C → C | Al terminar [US-14](historias/persona-b.md#us-14) y [US-17](historias/persona-c.md#us-17) (las usan las NetworkPolicies) |
| 🔀 Montaje del Secret `ssh-web-authorized` en el Deployment web | C → B | Al terminar [US-17](historias/persona-c.md#us-17) (cambio en `web.tf`) |
| 🤝 Credenciales e IP de MariaDB | A → B, C | Al terminar [US-20](historias/persona-a.md#us-20) |

---

<a id="riesgos"></a>
## 8. ⚠️ Riesgos y cómo cubrirlos

| Riesgo | Mitigación |
|---|---|
| IPs de la VLAN duplicadas entre workers (`host-local`, sin `whereabouts`) | Investigar y probar el IPAM en [US-19](historias/persona-a.md#us-19) antes de escribir Terraform ([D-005](decisions.md)) |
| Las subinterfaces `e2.<vlan>` se pierden al recrear el escenario | `setup-vlan-workers.sh` idempotente y parte del procedimiento de [US-41](historias/persona-a.md#us-41) |
| MetalLB sin `IPAddressPool` (Ingress con `EXTERNAL-IP <pending>`) | `-x config_metallb` en la secuencia diaria de arranque ([US-02](historias/persona-a.md#us-02)); si falla, probar por NodePort |
| Permisos de las claves SSH en volúmenes de Secret | `fsGroup: 1000` + modo `0440` como en el enunciado; si `sshd` se queja, initContainer ([US-17](historias/persona-c.md#us-17)) |
| El entorno (`/mnt/tmp`) se crea de cero cada día; solo el repo persiste | Todo paso sobre los nodos o los LXC va en un script o en Terraform del repo. `git push` al terminar cada sesión. Las claves de `keys/` se regeneran cada día con `gen-keys.sh` (nunca van a Git) |
| La IP de origen no se preserva y la política del admin bloquea al host | `externalTrafficPolicy: Local` y conectar **solo** a la IP de `k8s-worker1` ([US-32](historias/persona-c.md#us-32)) |
| Default-deny rompe DNS o tráfico que no se esperaba | Validación explícita en [US-33](historias/persona-a.md#us-33) |
| Una sola persona sabe cómo funciona su área | Revisión cruzada obligatoria y [US-43](#us-43) |
