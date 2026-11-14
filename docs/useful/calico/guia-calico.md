# 🧭 Guía: Calico (y en qué se diferencia de Flannel)

⬅️ [Volver al plan](../../../plan.md) · Relacionado: [datos del escenario §3](../../datos-escenario.md#3-kubernetes) · [guía de Multus](../multus/guia-multus.md) · [US-30](../../../historias/persona-c.md#us-30)

---

## 1. Qué es Calico

Calico es el **CNI** del clúster: el plugin que da una IP a cada Pod y hace que los Pods de nodos distintos se alcancen entre sí. Además **aplica las NetworkPolicies**, algo que Flannel (el CNI de la práctica 1.3) no hace.

A diferencia de Flannel, Calico **enruta** en lugar de usar un bridge:
- Cada Pod tiene una veth (`caliXXXX`), y el nodo tiene una **ruta /32 por Pod**.
- Los nodos se pasan las rutas de sus Pods por **BGP** (el demonio BIRD dentro del Pod `calico-node`).
- Las NetworkPolicies las aplica **Felix** (también en `calico-node`) con reglas iptables en cada nodo.

En nuestro escenario: pool `172.16.0.0/16`, encapsulado **IPIP** (`ipipMode: Always`) y nodos detectados por la interfaz `e1`.

---

## 2. Flannel vs Calico

| | Flannel (P1.3) | Calico (Trabajo Final) |
|---|---|---|
| **IPs de los Pods** | Una /24 por nodo, sacada del CIDR de Pods | Pool `172.16.0.0/16`, repartido en **bloques** (normalmente /26) que se asignan a los nodos según hagan falta |
| **Dentro del nodo** | Los Pods cuelgan de un **bridge** (`cni0`), que hace de gateway | **Sin bridge.** Cada Pod tiene una veth (`caliXXXX`) y el nodo una **ruta /32 por Pod** |
| **Gateway del Pod** | La IP de `cni0` (p. ej. `10.244.1.1`) | `169.254.1.1`, una dirección ficticia a la que el nodo responde por **proxy-ARP** |
| **Entre nodos** | Overlay, normalmente **VXLAN** (`flannel.1`) | Rutas aprendidas por **BGP**; aquí encapsuladas en **IPIP** (`tunl0`) |
| **Cómo se aprenden las rutas** | flanneld lee las subredes de la API de k8s / etcd | Los nodos se intercambian rutas por BGP: es enrutamiento real |
| **NetworkPolicy** | ❌ Se aceptan pero nadie las aplica | ✅ Felix escribe las reglas (iptables o eBPF) en cada nodo |

---

## 3. Cómo verlo en el escenario

En un worker (`ssh root@k8s-worker1`):
```bash
ip route                 # 172.16.x.x/26 via <otro nodo> dev tunl0 proto bird   ← bloque del otro nodo, por IPIP
                         # 172.16.x.y dev caliXXXX scope link                     ← una ruta por Pod local
ip -d link show tunl0    # el túnel IPIP
ip link | grep cali      # una veth por Pod de este nodo
tcpdump -ni e1 ip proto 4   # paquetes IPIP entre nodos (cabecera exterior nodo→nodo, Pod→Pod dentro)
```

Dentro de un Pod (`kubectl exec -it <pod> -- sh`):
```bash
ip addr                  # eth0 con una /32: el Pod no tiene "subred"
ip route                 # default via 169.254.1.1 dev eth0
ip neigh                 # 169.254.1.1 → ee:ee:ee:ee:ee:ee (proxy-ARP del lado del nodo)
```

Desde el host:
```bash
kubectl get ippools.crd.projectcalico.org -o yaml      # CIDR, ipipMode, natOutgoing
kubectl get blockaffinities.crd.projectcalico.org      # qué bloque /26 tiene cada nodo
```

---

## 4. ⚠️ Trampas a tener en cuenta

- **Calico solo controla las interfaces que crea él.** La interfaz extra de Multus (`net1`, la VLAN) queda **fuera** de Calico: las NetworkPolicies no se aplican al tráfico de la VLAN.
- **Default-deny de egress corta el DNS.** Con la política de denegación por defecto, los Pods no resuelven nombres hasta que se permite egress a `kube-dns` en 53/UDP y 53/TCP.
- **NetworkPolicy no filtra ICMP.** No se puede escribir una regla "solo ping". Una regla **sin `ports`** permite todos los protocolos, ICMP incluido.
- **El puerto de la política es el del Pod**, no el del Service: para los web es el 80, no el 8080. La política se evalúa después del DNAT del Service.
- **`namespaceSelector` + `podSelector`** en el **mismo** elemento de `from` es un AND; en elementos separados es un OR (y abre mucho más de lo que se quiere).
- **La IP de origen se pierde con un NodePort normal.** Si el nodo reenvía el tráfico a otro nodo, hace SNAT y la política del admin (`ipBlock 10.10.20.2/32`) lo bloquea. Por eso el Service del admin usa `externalTrafficPolicy: Local` y hay que conectar a `10.10.10.11` (el nodo donde está el Pod).
- **El tráfico IPIP (protocolo 4) tiene que poder pasar entre los nodos.** Si un ping entre Pods de nodos distintos falla pero dentro del mismo nodo funciona, mirar `tunl0` y las rutas `proto bird`.
- **Las IPs de los Pods cambian** al recrearlos. Nunca usar IPs de Pods en Terraform ni en las políticas: usar labels y Services.
