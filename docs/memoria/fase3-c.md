# Fase 3 · Persona C: denegación por defecto

Historias: [US-30](../../historias/persona-c.md#us-30) · Decisiones: [D-002](../../decisions.md) (namespace propio), [D-013](../../decisions.md) (NetworkPolicies en una configuración aparte) · Salidas: [`us-30-pruebas.txt`](../capturas/us-30-pruebas.txt)

En esta fase empezamos a aplicar el enunciado §5: primero se cierra todo el tráfico del namespace y luego cada historia abre solo lo necesario (US-31 para los web, US-32 para el admin). US-30 es el primer paso: una política que aísla todos los Pods en los dos sentidos.

## US-30 · Política `default-deny-all`

### Qué cambiamos

La política está en [`network-policy-deny-all.tf`](../../terraform/network-policies/network-policy-deny-all.tf):

```hcl
resource "kubernetes_network_policy_v1" "default_deny_all" {
  metadata {
    name      = "default-deny-all"
    namespace = local.env.namespace
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress", "Egress"]
  }
}
```

- **`pod_selector {}` vacío selecciona todos los Pods del namespace**: los tres web y el admin. Las NetworkPolicies solo afectan a los Pods que seleccionan, y uno vacío no filtra por ninguna label.
- **`policy_types = ["Ingress", "Egress"]` sin bloques `ingress {}` ni `egress {}`.** Las NetworkPolicies son listas de lo permitido. Un Pod que no está seleccionado por ninguna política lo acepta todo. En cuanto alguna lo selecciona para un sentido, ese sentido queda aislado y solo pasa lo que permita alguna política. Aquí no hay reglas, así que no se permite nada: no entra ni sale tráfico por `eth0`.
- **Las políticas se suman.** US-31 y US-32 no tienen que modificar esta: añaden políticas nuevas con reglas de permiso, y Calico aplica la unión de todas.
- **Solo afecta al namespace del proyecto** (`g2-workshop`, D-002). El Ingress Controller, CoreDNS y MetalLB están en otros namespaces y no cambian.

### Una configuración de Terraform aparte (D-013)

La política no está en `terraform/` sino en una segunda configuración, [`terraform/network-policies/`](../../terraform/network-policies/), con su propio provider y su propio state. Al principio estaba en `terraform/netpol.tf`, pero así cada `apply` de la aplicación aislaba los Pods nada más crearlos, y las historias de A y B no se podían probar por separado. Ahora se aplica en dos pasos y en orden (así lo hace [`host-script.sh`](../../scripts/host-script.sh)): primero `terraform/`, luego `terraform/network-policies/`. Para destruir se sigue el orden inverso.

Para no volver a definir el namespace ni las labels, la segunda configuración lee los outputs de la principal desde su state, en [`env-outputs.tf`](../../terraform/network-policies/env-outputs.tf):

```hcl
data "terraform_remote_state" "main" {
  backend = "local"
  config = {
    path = "${path.module}/../terraform.tfstate"
  }
}

locals {
  env = data.terraform_remote_state.main.outputs
}
```

`local.env.namespace` es el output `namespace` del último `apply` de `terraform/`. Solo se ven los **outputs**, no los recursos: si una política necesita un valor nuevo (por ejemplo, las labels del admin para US-32), hay que añadirlo a `terraform/outputs.tf` y hacer `apply` allí primero.

### Pruebas

Con la política aplicada, `kubectl describe networkpolicy` confirma que selecciona todos los Pods y los aísla en los dos sentidos:

```
Spec:
  PodSelector:     <none> (Allowing the specific traffic to all pods in this namespace)
  Allowing ingress traffic:
    <none> (Selected pods are isolated for ingress connectivity)
  Allowing egress traffic:
    <none> (Selected pods are isolated for egress connectivity)
  Policy Types: Ingress, Egress
```

| Prueba | Esperado | Resultado | Por qué |
|---|---|---|---|
| `curl` al Ingress `/servers-G2` | sin respuesta o 504 | `000`: ninguna respuesta HTTP | El controller recibe la petición, pero no puede abrir la conexión al Pod web: el web tiene la entrada cerrada |
| SSH del host al admin, `10.10.10.11:30002` | timeout | `Connection timed out` | El NodePort entrega el paquete al Pod admin, y la política lo descarta en la entrada |
| `curl` a un nombre desde un web | falla la resolución | `exit code 28` (timeout de `curl`) | La salida está cerrada también hacia `kube-dns`, así que la consulta DNS no tiene respuesta |
| `ping 10.1.2.100` (`bbdd`) desde un web | **sí** responde | 2/2, 0 % de pérdida | El tráfico sale por `net1`, la macvlan de Multus, y Calico solo filtra `eth0` |

Las tres primeras pruebas son el criterio 🧪 de la historia: la aplicación queda "rota" a propósito hasta US-31 y US-32. La última es la consecuencia más importante para la fase: **las NetworkPolicies no protegen la VLAN**. `net1` va directa a `e2.1000` sin pasar por las reglas de Calico, así que el tráfico entre los Pods y los LXC solo lo protegen las claves SSH y los usuarios de la base de datos (D-005, [US-33](../../historias/persona-a.md#us-33)). Las pruebas de US-24 lo confirman desde el otro lado: con la política aplicada, el SSH del admin a un web va por la VLAN y funciona, y por la IP de Calico da timeout ([pruebas-us24.md §8](../useful/admin/pruebas-us24.md)).

<!-- TODO: screenshots/us-30-<qué>.jpg -->

### Qué queda abierto

- **DNS.** Con la salida cerrada, ningún Pod del namespace resuelve nombres. Las políticas de permiso tendrán que abrir la salida a `kube-dns` (53 UDP y TCP) a los Pods que lo necesiten.
- **Instalar paquetes desde los Pods** (el cliente de MySQL) necesita salida a Internet, que esta política bloquea ([D-007](../../decisions.md), pendiente).
- **US-32**: abrir el SSH al admin solo desde `10.10.20.2/32`.
