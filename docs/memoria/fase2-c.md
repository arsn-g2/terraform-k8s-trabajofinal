# Fase 2 · Persona C: SSH desde el admin por la VLAN

Historias: [US-24](../../historias/persona-c.md#us-24) · Decisiones: [D-004](../../decisions.md) (solo claves), [D-005](../../decisions.md) (IPAM de la VLAN), [D-010](../../decisions.md) (una sola VLAN) · Salidas: [`us-24-admin-net1.txt`](../capturas/us-24-admin-net1.txt), [`us-24-ssh.txt`](../capturas/us-24-ssh.txt)

En esta fase conectamos el Pod admin a la VLAN 1000 (`10.1.2.0/24`), la misma que usan los Pods web y los LXC `bbdd` y `logs`. Así el admin llega a ellos por SSH con la clave privada del par 1 (US-16, US-17) sin pasar por la red de Calico.

## US-24 · Interfaz Multus en el Pod admin

### Qué cambiamos

La NAD `vlan1000-admin` ya la había definido la persona A en [`multus.tf`](../../terraform/multus.tf): `macvlan` en modo `bridge` sobre `e2.1000`, con IPAM `static` y `capabilities.ips = true`. Con esta *capability*, la IP no está escrita en la NAD: la pide el Pod en su anotación y Multus se la pasa al plugin `static`. Nuestro trabajo fue pedir esa red desde el Deployment del admin, en [`admin-service-deployment.tf`](../../terraform/admin-service-deployment.tf):

```hcl
strategy {
  type = "Recreate"
}

template {
  metadata {
    labels = local.admin_labels
    annotations = {
      "k8s.v1.cni.cncf.io/networks" = jsonencode([{
        name = kubernetes_manifest.nad_admin.manifest.metadata.name
        ips  = [local.vlan_admin_cidr]   # 10.1.2.5/24
      }])
    }
  }
```

- **La anotación usa el formato JSON**, no el nombre a secas como en los web, porque además del nombre de la red lleva la IP. `jsonencode` produce `[{"name": "vlan1000-admin", "ips": ["10.1.2.5/24"]}]`. La IP sale de `local.vlan_admin_cidr`, que une `var.vlan_admin_ip` con el prefijo de `var.vlan_subnet`.
- **Referencia el recurso de la NAD**, igual que en US-22, para que Terraform cree la NAD antes que el Deployment.
- **Estrategia `Recreate`.** Con `RollingUpdate`, la opción por defecto, Kubernetes arranca el Pod nuevo antes de borrar el viejo, y los dos tendrían `10.1.2.5` en la VLAN durante unos segundos. Con `Recreate` se borra primero el viejo. Con `whereabouts` (en los web) esto no pasa, porque cada Pod recibe una IP distinta.

### Pruebas

**El admin tiene `net1` con la IP fija.** El `network-status` que escribe Multus muestra dos interfaces: `eth0` con la IP de Calico (`172.16.194.69`, la interfaz por defecto) y `net1` en `g2-workshop/vlan1000-admin` con `10.1.2.5`.

```
"name": "g2-workshop/vlan1000-admin",
"interface": "net1",
"ips": [ "10.1.2.5" ],
```

**SSH sin contraseña por la VLAN.** <!-- TODO: completar con la salida de us-24-ssh.txt (ahora vacío) o con capturas -->
Desde el admin, con la clave privada del par 1:

| Destino | Comando | Resultado |
|---|---|---|
| Pods web (3) | `ssh webuser@10.1.2.<1x>` | <!-- TODO --> |
| `bbdd` | `ssh root@10.1.2.100` | <!-- TODO --> |
| `logs` | `ssh root@10.1.2.101` | <!-- TODO --> |

<!-- TODO: screenshots/us-24-<qué>.jpg -->

Con el admin ya en la VLAN se puede repetir el ping a `10.1.2.5` desde un Pod web, que quedó pendiente en [US-22](fase2-b.md#pendiente). <!-- TODO: resultado -->
