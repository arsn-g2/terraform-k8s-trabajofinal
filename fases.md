# 🧭 Fases y dependencias

⬅️ [Volver al plan](plan.md) · Historias: [🌐 A](historias/persona-a.md) · [🖥️ B](historias/persona-b.md) · [🔐 C](historias/persona-c.md) · [🔖 Leyenda de emojis](plan.md#leyenda)

**Calendario sugerido** (ajústenlo a la fecha de entrega real): cada fase dura aproximadamente 1 semana, y la Fase 0 dura de 1 a 2 días. Al cierre de cada fase hay un hito 🚩: los tres se juntan, hacen `terraform destroy && terraform apply` en limpio y comprueban los [criterios del hito](plan.md#hitos).

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

---

## 🏗️ Fase 0: Preparación

| Historia | Persona | Pts | Depende de | Marcas |
|---|---|---|---|---|
| [HU-00 · Repositorio y convenciones](historias/persona-c.md#hu-00) | 🔐 C | 2 | — | ⛔ |
| [HU-01 · Esqueleto de Terraform](historias/persona-b.md#hu-01) | 🖥️ B | 3 | [HU-00](historias/persona-c.md#hu-00) | ⛔ |
| [HU-02 · Levantar el escenario de lab y recopilar datos](historias/persona-a.md#hu-02) | 🌐 A | 2 | — | |
| [HU-03 · Resolver dudas con el profesor](historias/persona-c.md#hu-03) | 🔐 C | 1 | — | ⛔ |

🚩 **H0: Arranque.** Repo creado, `terraform apply` crea el namespace, datos del escenario documentados, dudas resueltas.

---

## ⚙️ Fase 1: Componentes independientes (en paralelo)

| Historia | Persona | Pts | Depende de | Marcas |
|---|---|---|---|---|
| [HU-10 · Subinterfaces VLAN en los workers](historias/persona-a.md#hu-10) | 🌐 A | 3 | [HU-02](historias/persona-a.md#hu-02), [HU-03](historias/persona-c.md#hu-03) | |
| [HU-11 · NetworkAttachmentDefinition (Multus)](historias/persona-a.md#hu-11) | 🌐 A | 5 | [HU-10](historias/persona-a.md#hu-10) | ⛔ 🤝 |
| [HU-12 · Escenario VNX con LXC de BBDD y logs](historias/persona-a.md#hu-12) | 🌐 A | 5 | [HU-02](historias/persona-a.md#hu-02), [HU-03](historias/persona-c.md#hu-03) | |
| [HU-13 · ConfigMap con la plantilla HTML](historias/persona-b.md#hu-13) | 🖥️ B | 2 | [HU-01](historias/persona-b.md#hu-01) | |
| [HU-14 · Deployment web con página personalizada](historias/persona-b.md#hu-14) | 🖥️ B | 5 | [HU-13](historias/persona-b.md#hu-13) | 🤝 |
| [HU-15 · Service ClusterIP e Ingress](historias/persona-b.md#hu-15) | 🖥️ B | 3 | [HU-14](historias/persona-b.md#hu-14), [HU-03](historias/persona-c.md#hu-03) | ⚠️ |
| [HU-16 · Claves SSH y Secrets](historias/persona-c.md#hu-16) | 🔐 C | 3 | [HU-01](historias/persona-b.md#hu-01), [HU-03](historias/persona-c.md#hu-03) | 🤝 |
| [HU-17 · Pod de administración](historias/persona-c.md#hu-17) | 🔐 C | 5 | [HU-16](historias/persona-c.md#hu-16) | 🔀 |
| [HU-18 · Service NodePort del admin](historias/persona-c.md#hu-18) | 🔐 C | 3 | [HU-17](historias/persona-c.md#hu-17) | |

🚩 **H1: Componentes listos.** La VLAN y la NAD funcionan con un Pod de prueba, los LXC hacen ping, `curl /servers-GX` balancea entre 3 Pods, el SSH al admin por NodePort funciona.

---

## 🔀 Fase 2: Integración por la VLAN

| Historia | Persona | Pts | Depende de | Marcas |
|---|---|---|---|---|
| [HU-20 · MariaDB en el LXC `bbdd`](historias/persona-a.md#hu-20) | 🌐 A | 5 | [HU-12](historias/persona-a.md#hu-12), [HU-16](historias/persona-c.md#hu-16) | 🤝 🔀 |
| [HU-21 · Servidor de logs en el LXC `logs`](historias/persona-a.md#hu-21) | 🌐 A | 3 | [HU-12](historias/persona-a.md#hu-12), [HU-16](historias/persona-c.md#hu-16) | |
| [HU-22 · Interfaz Multus en los Pods web](historias/persona-b.md#hu-22) | 🖥️ B | 3 | [HU-11](historias/persona-a.md#hu-11), [HU-14](historias/persona-b.md#hu-14) | 🔀 |
| [HU-23 · Acceso a MariaDB desde los web y el admin](historias/persona-b.md#hu-23) | 🖥️ B | 3 | [HU-20](historias/persona-a.md#hu-20), [HU-22](historias/persona-b.md#hu-22) | 🔀 |
| [HU-24 · SSH desde el admin por la VLAN](historias/persona-c.md#hu-24) | 🔐 C | 5 | [HU-11](historias/persona-a.md#hu-11), [HU-17](historias/persona-c.md#hu-17), [HU-20](historias/persona-a.md#hu-20), [HU-22](historias/persona-b.md#hu-22) | 🔀 |

🚩 **H2: Integración por VLAN.** Ping y SSH entre web ↔ admin ↔ `bbdd` ↔ `logs` por la VLAN, y `mysql` funciona desde los web y desde el admin.

---

## 🛡️ Fase 3: NetworkPolicies

| Historia | Persona | Pts | Depende de | Marcas |
|---|---|---|---|---|
| [HU-30 · Política de denegación por defecto](historias/persona-c.md#hu-30) | 🔐 C | 3 | Fase 2 completa (🚩 H2) | ⛔ |
| [HU-31 · Acceso a los web solo desde el Ingress Controller](historias/persona-b.md#hu-31) | 🖥️ B | 5 | [HU-30](historias/persona-c.md#hu-30), [HU-15](historias/persona-b.md#hu-15) | ⚠️ |
| [HU-32 · SSH al admin solo desde la IP del host](historias/persona-c.md#hu-32) | 🔐 C | 5 | [HU-30](historias/persona-c.md#hu-30), [HU-18](historias/persona-c.md#hu-18) | ⚠️ |
| [HU-33 · Validar que el tráfico de la VLAN sigue funcionando](historias/persona-a.md#hu-33) | 🌐 A | 3 | [HU-30](historias/persona-c.md#hu-30), [HU-24](historias/persona-c.md#hu-24) | 🔀 |

🚩 **H3: Seguridad aplicada.** Las 3 NetworkPolicies están activas y todas las pruebas de H1 y H2 siguen pasando. Las pruebas negativas fallan como se espera.

---

## ✅ Fase 4: Verificación y entrega

| Historia | Persona | Pts | Depende de | Marcas |
|---|---|---|---|---|
| [HU-40 · Script de verificación automática](historias/persona-b.md#hu-40) | 🖥️ B | 5 | Fase 3 completa (🚩 H3) | |
| [HU-41 · Despliegue de cero, de punta a punta](historias/persona-a.md#hu-41) | 🌐 A | 3 | [HU-40](historias/persona-b.md#hu-40) | 🔀 |
| [HU-42 · Memoria y documentación](historias/persona-c.md#hu-42) | 🔐 C | 3 | [HU-41](historias/persona-a.md#hu-41) (se va llenando desde la Fase 1) | 📝 |
| [HU-43 · Ensayo de la demo](plan.md#hu-43) | 👥 Todos | — | [HU-42](historias/persona-c.md#hu-42) | 🏁 |

🏁 **Entrega.** `verify.sh` en verde tras un despliegue de cero en otra computadora, memoria lista, demo ensayada.
