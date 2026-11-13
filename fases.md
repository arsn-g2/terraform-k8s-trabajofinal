# 🧭 Fases y dependencias

⬅️ [Volver al plan](plan.md) · Historias: [🌐 A](historias/persona-a.md) · [🖥️ B](historias/persona-b.md) · [🔐 C](historias/persona-c.md) · [🔖 Leyenda de emojis](plan.md#leyenda)

**Calendario sugerido** (ajústenlo a la fecha de entrega real): cada fase dura aproximadamente 1 semana, y la Fase 0 dura de 1 a 2 días. Al cierre de cada fase hay un hito 🚩: los tres se juntan, hacen `terraform destroy && terraform apply` en limpio y comprueban los [criterios del hito](plan.md#hitos).

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

---

## 🏗️ Fase 0: Preparación

| Historia | Persona | Pts | Depende de | Marcas | Completed |
|---|---|---|---|---|---|
| [US-00 · Repositorio y convenciones](historias/persona-c.md#us-00) | 🔐 C | 2 | — | ⛔ | ✅ |
| [US-01 · Esqueleto de Terraform](historias/persona-b.md#us-01) | 🖥️ B | 3 | [US-00](historias/persona-c.md#us-00) | ⛔ | ✅ |
| [US-02 · Levantar el escenario de lab y recopilar datos](historias/persona-a.md#us-02) | 🌐 A | 2 | — | | ✅ |
| [US-03 · Cerrar las dudas pendientes](historias/persona-c.md#us-03) | 🔐 C | 1 | — | ⛔ | ⬜ |

🚩 **H0: Arranque.** Repo creado, `terraform apply` crea el namespace, datos del escenario documentados, dudas abiertas cerradas en `decisions.md`.

---

## ⚙️ Fase 1: Componentes independientes (en paralelo)

| Historia | Persona | Pts | Depende de | Marcas | Completed |
|---|---|---|---|---|---|
| [US-19 · Investigación: Multus, tipo de NAD e IPAM](historias/persona-a.md#us-19) | 🌐 A | 3 | [US-02](historias/persona-a.md#us-02) | ⛔ | ⬜ |
| [US-10 · Subinterfaces VLAN en los workers](historias/persona-a.md#us-10) | 🌐 A | 3 | [US-02](historias/persona-a.md#us-02), [US-03](historias/persona-c.md#us-03) | | ⬜ |
| [US-11 · NetworkAttachmentDefinition (Multus)](historias/persona-a.md#us-11) | 🌐 A | 3 | [US-10](historias/persona-a.md#us-10), [US-19](historias/persona-a.md#us-19) | ⛔ 🤝 | ⬜ |
| [US-12 · Escenario VNX con LXC de BBDD y logs](historias/persona-a.md#us-12) | 🌐 A | 5 | [US-02](historias/persona-a.md#us-02), [US-03](historias/persona-c.md#us-03) | | ⬜ |
| [US-13 · ConfigMap con la plantilla HTML](historias/persona-b.md#us-13) | 🖥️ B | 2 | [US-01](historias/persona-b.md#us-01) | | ⬜ |
| [US-14 · Deployment web con página personalizada](historias/persona-b.md#us-14) | 🖥️ B | 5 | [US-13](historias/persona-b.md#us-13) | 🤝 | ⬜ |
| [US-15 · Service ClusterIP e Ingress](historias/persona-b.md#us-15) | 🖥️ B | 3 | [US-14](historias/persona-b.md#us-14) | ⚠️ | ⬜ |
| [US-16 · Claves SSH y Secrets](historias/persona-c.md#us-16) | 🔐 C | 3 | [US-00](historias/persona-c.md#us-00), [US-01](historias/persona-b.md#us-01) | 🤝 | ⬜ |
| [US-17 · Pod de administración](historias/persona-c.md#us-17) | 🔐 C | 5 | [US-16](historias/persona-c.md#us-16) | 🔀 | ⬜ |
| [US-18 · Service NodePort del admin](historias/persona-c.md#us-18) | 🔐 C | 3 | [US-17](historias/persona-c.md#us-17) | | ⬜ |

🚩 **H1: Componentes listos.** La VLAN y la NAD funcionan con un Pod de prueba, los LXC hacen ping, `curl /servers-G2` balancea entre 3 Pods, el SSH al admin por NodePort funciona.

---

## 🔀 Fase 2: Integración por la VLAN

| Historia | Persona | Pts | Depende de | Marcas | Completed |
|---|---|---|---|---|---|
| [US-20 · MariaDB en el LXC `bbdd`](historias/persona-a.md#us-20) | 🌐 A | 5 | [US-12](historias/persona-a.md#us-12), [US-16](historias/persona-c.md#us-16) | 🤝 🔀 | ⬜ |
| [US-21 · Servidor de logs en el LXC `logs`](historias/persona-a.md#us-21) | 🌐 A | 3 | [US-12](historias/persona-a.md#us-12), [US-16](historias/persona-c.md#us-16) | | ⬜ |
| [US-22 · Interfaz Multus en los Pods web](historias/persona-b.md#us-22) | 🖥️ B | 3 | [US-11](historias/persona-a.md#us-11), [US-14](historias/persona-b.md#us-14) | 🔀 | ⬜ |
| [US-23 · Acceso a MariaDB desde los web y el admin](historias/persona-b.md#us-23) | 🖥️ B | 3 | [US-20](historias/persona-a.md#us-20), [US-22](historias/persona-b.md#us-22) | 🔀 | ⬜ |
| [US-24 · SSH desde el admin por la VLAN](historias/persona-c.md#us-24) | 🔐 C | 5 | [US-11](historias/persona-a.md#us-11), [US-17](historias/persona-c.md#us-17), [US-20](historias/persona-a.md#us-20), [US-22](historias/persona-b.md#us-22) | 🔀 | ⬜ |

🚩 **H2: Integración por VLAN.** Ping y SSH entre web ↔ admin ↔ `bbdd` ↔ `logs` por la VLAN, y `mysql` funciona desde los web y desde el admin.

---

## 🛡️ Fase 3: NetworkPolicies

| Historia | Persona | Pts | Depende de | Marcas | Completed |
|---|---|---|---|---|---|
| [US-30 · Política de denegación por defecto](historias/persona-c.md#us-30) | 🔐 C | 3 | Fase 2 completa (🚩 H2) | ⛔ | ⬜ |
| [US-31 · Acceso a los web solo desde el Ingress Controller](historias/persona-b.md#us-31) | 🖥️ B | 5 | [US-30](historias/persona-c.md#us-30), [US-15](historias/persona-b.md#us-15) | ⚠️ | ⬜ |
| [US-32 · SSH al admin solo desde la IP del host](historias/persona-c.md#us-32) | 🔐 C | 5 | [US-30](historias/persona-c.md#us-30), [US-18](historias/persona-c.md#us-18) | ⚠️ | ⬜ |
| [US-33 · Validar que el tráfico de la VLAN sigue funcionando](historias/persona-a.md#us-33) | 🌐 A | 3 | [US-30](historias/persona-c.md#us-30), [US-24](historias/persona-c.md#us-24) | 🔀 | ⬜ |

🚩 **H3: Seguridad aplicada.** Las 3 NetworkPolicies están activas y todas las pruebas de H1 y H2 siguen pasando. Las pruebas negativas fallan como se espera.

---

## 🔵 Fase 4: Verificación y entrega

| Historia | Persona | Pts | Depende de | Marcas | Completed |
|---|---|---|---|---|---|
| [US-40 · Script de verificación automática](historias/persona-b.md#us-40) | 🖥️ B | 5 | Fase 3 completa (🚩 H3) | | ⬜ |
| [US-41 · Despliegue de cero, de punta a punta](historias/persona-a.md#us-41) | 🌐 A | 3 | [US-40](historias/persona-b.md#us-40) | 🔀 | ⬜ |
| [US-42 · Memoria y documentación](historias/persona-c.md#us-42) | 🔐 C | 3 | [US-41](historias/persona-a.md#us-41) (se va llenando desde la Fase 1) | 📝 | ⬜ |
| [US-43 · Ensayo de la demo](plan.md#us-43) | 👥 Todos | — | [US-42](historias/persona-c.md#us-42) | 🏁 | ⬜ |

🏁 **Entrega.** `verify.sh` en verde tras un despliegue de cero en otra computadora, memoria lista, demo ensayada.
