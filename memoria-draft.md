# Memoria: Trabajo Final ARSN/CNVR 2026-27

**Despliegue automático de una aplicación escalable sobre Kubernetes utilizando los servicios de orquestación de Terraform**

**Grupo 2** · ⟪PENDIENTE: nombres de los integrantes⟫

> **Borrador.** Este documento se armó a partir de [plan.md](plan.md) y [fases.md](fases.md). Describe lo que hicimos o vamos a hacer en cada fase. Los resultados, las capturas y los valores definitivos se marcan como `⟪PENDIENTE: …⟫` y se completan a medida que se cierra cada historia (US-42).

---

## 1. Introducción

En este trabajo desplegamos de forma automática, con Terraform, una aplicación web escalable sobre un clúster de Kubernetes con Calico y Multus. La aplicación consta de tres servidores web Nginx detrás de un Ingress y de un Pod de administración accesible por SSH. Todos se conectan, a través de una VLAN compartida, a un escenario VNX con dos contenedores LXC: una base de datos MySQL (`bbdd`) y un servidor de logs (`logs`).

Nos repartimos el trabajo en tres áreas: red y VNX (Persona A), aplicación web (Persona B) y seguridad y administración (Persona C). Organizamos las tareas en historias de usuario agrupadas en cinco fases, cada una cerrada con un hito en el que los tres desplegamos todo de cero con `terraform destroy && terraform apply`.

⟪PENDIENTE: diagrama de arquitectura (Fig. 1 del enunciado adaptada)⟫

---

## 2. Entorno de trabajo

Trabajamos sobre el escenario `k8s_lab-calico` (un master y dos workers, Kubernetes v1.37, Calico en `e1`) y sobre la VM `terraform`, desde la que ejecutamos todos los comandos de Terraform. Como el entorno vive en almacenamiento temporal y se borra todos los días, decidimos que todo paso sobre los nodos o los LXC tenía que quedar en un script o en Terraform dentro del repositorio, nunca como un paso manual. Así, cada día levantamos el laboratorio de cero y lo dejamos listo con la misma secuencia de comandos.

---

## 3. Fase 0: Preparación

**Repositorio y convenciones (US-00).** Creamos el repositorio, definimos las convenciones de Git (una rama por historia, mensajes `US-NN: …`, revisión cruzada y *squash merge*) y configuramos el `.gitignore` para que nunca se suban claves privadas ni el `tfstate`.

**Esqueleto de Terraform (US-01).** Armamos la estructura base: el provider `hashicorp/kubernetes` fijado en la versión 2.23.0, las variables del escenario y los outputs. Tomamos como referencia de estilo nuestra solución de la práctica P1.4.

**Datos del escenario (US-02).** Levantamos el laboratorio y medimos los valores reales del entorno: IPs de los nodos, versiones, plugins de Multus instalados, NodePorts del Ingress y estado de MetalLB. Los documentamos en [docs/datos-escenario.md](docs/datos-escenario.md). Descubrimos que la interfaz de los workers hacia `VlanNet` se llama `e2` (no `eth2`), que `whereabouts` no está instalado y que a menudo MetalLB arranca sin `IPAddressPool`, por lo que agregamos un paso extra al arranque diario.

**Dudas pendientes (US-03).** Revisamos el enunciado (versión del 5/11/2026) y cerramos las dudas abiertas: la dirección de las claves SSH (dos pares, D-004), el número de grupo (`/servers-G2`, D-001), las imágenes y la IP del host. ⟪PENDIENTE: ID de VLAN, subred e IPAM definitivos⟫

🚩 **H0.** ⟪PENDIENTE: resultado del hito⟫

---

## 4. Fase 1: Componentes independientes

En esta fase cada uno trabajó en paralelo sobre su área, en su propio archivo `.tf`.

### 4.1 Red y VNX

**Investigación de Multus e IPAM (US-19).** Investigamos cómo Multus agrega una segunda interfaz (`net1`) a los Pods y probamos distintos tipos de `NetworkAttachmentDefinition` y de IPAM. Comprobamos que `host-local` asigna direcciones por nodo, de modo que dos Pods en workers distintos pueden recibir la misma IP de la VLAN (D-005). Elegimos `whereabouts` para los Pods web, que guarda las IPs asignadas en un `IPPool` común a todo el clúster, y `static` para el único Pod admin (D-005). Comprobamos también que las NetworkPolicies de Calico no filtran `net1`.

**Subinterfaces VLAN (US-10).** Creamos las subinterfaces `e2.<vlan>` en los workers mediante el script `setup-vlan-workers.sh`, que es idempotente para poder correrlo todos los días.

**NetworkAttachmentDefinition (US-11).** Creamos con `kubernetes_manifest` dos NAD, porque el provider no tiene un recurso nativo para ellas. Las dos son `macvlan` en modo *bridge* sobre `e2.1000`: `vlan1000-web` usa IPAM `whereabouts` en el rango `10.1.2.10`–`10.1.2.50`, y `vlan1000-admin` usa IPAM `static`, de modo que el Pod admin pide `10.1.2.5` en su anotación. Como `whereabouts` no viene con el escenario, el script `setup-whereabouts.sh` lo instala en cada arranque con una versión fija (D-010). Lo probamos con dos Pods en workers distintos, que recibieron IPs diferentes y se hicieron ping por la VLAN, y con un Pod con la IP fija del admin.

**Escenario VNX (US-12).** Escribimos los escenarios VNX con los LXC `bbdd` y `logs` sobre `VlanNet`, basados en `k8s_lab-vms-vlan.xml` de P1.3, y comprobamos que responden al ping.

### 4.2 Aplicación web

Detalle y capturas en [docs/memoria/fase1-b.md](docs/memoria/fase1-b.md).

**ConfigMap (US-13).** Escribimos la plantilla `templates/index.html.tpl` y la cargamos en un ConfigMap con `templatefile()`. Terraform sustituye el número de grupo durante el `plan`, y el marcador `__POD_NAME__` llega intacto al ConfigMap para que lo rellene cada Pod.

**Deployment web (US-14).** Desplegamos tres réplicas de `dgsgiros/nginx-ssh:latest` con la label `app=web`. En cada Pod, un contenedor *sidecar* (D-009):
- recibe el nombre del Pod por la Downward API;
- aplica `sed` sobre la plantilla, montada en solo lectura;
- escribe el resultado en un `emptyDir` compartido con Nginx, que lo sirve desde `/usr/share/nginx/html`;
- queda vivo con `sleep infinity` para que el kubelet no lo reinicie.

Comprobamos que cada réplica muestra su propio nombre y que un Pod recreado muestra el nuevo.

**Service e Ingress (US-15).** Expusimos los servidores con un Service `ClusterIP` (8080→80) y un Ingress de clase `nginx` en la ruta `/servers-G2`, con la anotación `rewrite-target: /`. Desde el host accedimos por la IP de MetalLB (`10.10.10.20`) y por el NodePort del controller, y comprobamos tres cosas:
- las peticiones se balancean entre los tres Pods;
- solo las rutas `/servers-G2*` devuelven 200;
- al borrar un Pod, su sustituto entra solo en los endpoints del Service.

### 4.3 Seguridad y administración

**Claves SSH y Secrets (US-16).** Generamos los dos pares de claves con `ssh-keygen` (script `gen-keys.sh`) y los cargamos con `file()` en tres `kubernetes_secret_v1`: la privada del par 1 para el admin, la pública del par 2 para el acceso host → admin y la pública del par 1 para los web y los LXC.

**Pod de administración (US-17).** Desplegamos `dgsgiros/admin-ssh:latest` en un Deployment de una réplica fijado en `k8s-worker1`, con `fsGroup: 1000`. Montamos cada clave como un fichero dentro del `~/.ssh` de la imagen, con `sub_path`: la privada del par 1 en `id_ed25519` con modo `0440`, que `adminuser` lee por grupo, y la pública del par 2 en `authorized_keys`. En los Pods web montamos la pública del par 1 en `/home/webuser/.ssh/authorized_keys`. Comprobamos que el admin entra por SSH en un web como `webuser` y que el host entra en el admin con la clave del par 2, pero no con la del par 1.

**Service NodePort (US-18).** Expusimos el SSH del admin con un Service `NodePort` (2222→22) y `externalTrafficPolicy: Local`, para preservar la IP de origen del host. Probamos el acceso desde el host a `10.10.10.11:<nodePort>`.

🚩 **H1.** ⟪PENDIENTE: resultado del hito y capturas⟫

---

## 5. Fase 2: Integración por la VLAN

**MySQL (US-20).** Instalamos y configuramos MySQL en el LXC `bbdd` con pasos `exec` y archivos del `filetree`, incluida la clave pública del par 1 en `authorized_keys`.

**Servidor de logs (US-21).** Configuramos rsyslog en el LXC `logs` para recibir mensajes en el puerto 514 UDP/TCP (D-006).

**Interfaz Multus en los web (US-22).** Agregamos la anotación `k8s.v1.cni.cncf.io/networks` al template del Deployment web, apuntando a la NAD `vlan1000-web` (`macvlan` sobre `e2.1000`, IPAM `whereabouts`, D-005). Cada réplica conserva `eth0` (Calico), que siguen usando el Service y el Ingress, y recibe una segunda interfaz `net1` en la VLAN, por la que sale todo el tráfico hacia `10.1.2.0/24`. Comprobamos que:
- los tres Pods reciben IPs de `net1` distintas, aunque estén en workers diferentes, porque whereabouts guarda las reservas en un `IPPool` común a todo el clúster;
- desde los Pods web hay conectividad por la VLAN con `bbdd`, con `logs` y con los demás Pods web;
- el Ingress sigue balanceando entre las tres réplicas;
- un Pod recreado recibe una IP nueva de la VLAN.

El ping al admin queda pendiente de US-24. Detalle y capturas en [`docs/memoria/fase2-b.md`](docs/memoria/fase2-b.md).

**Acceso a MySQL (US-23).** Probamos la conexión a MySQL desde los Pods web y desde el admin a través de la VLAN. ⟪PENDIENTE: cómo resolvimos la instalación del cliente (D-007)⟫

**SSH por la VLAN (US-24).** Verificamos que desde el admin podemos entrar por SSH a los web y a los LXC usando la clave privada del par 1.

🚩 **H2.** ⟪PENDIENTE: resultado del hito y capturas⟫

---

## 6. Fase 3: NetworkPolicies

**Denegación por defecto (US-30).** Aplicamos una política *default deny* para el tráfico de entrada y de salida en el namespace. Agregamos una excepción de salida hacia `kube-dns` (53 UDP/TCP) para que los Pods sigan resolviendo nombres.

**Web solo desde el Ingress (US-31).** Permitimos el tráfico a los web únicamente desde los Pods del controlador `ingress-nginx`, combinando `namespaceSelector` y `podSelector` en el mismo bloque `from`, sobre el puerto 80 del Pod (no el 8080 del Service).

**SSH al admin solo desde el host (US-32).** Restringimos el SSH al admin al `ipBlock 10.10.20.2/32`. Comprobamos que funciona porque `r1` enruta sin NAT y `externalTrafficPolicy: Local` conserva la IP de origen.

**Tráfico de la VLAN (US-33).** Validamos que el tráfico por la VLAN sigue funcionando con las políticas activas, ya que Calico no filtra las interfaces de Multus. ⟪PENDIENTE: hallazgos⟫

🚩 **H3.** ⟪PENDIENTE: resultado del hito, pruebas positivas y negativas⟫

---

## 7. Fase 4: Verificación y entrega

**Script de verificación (US-40).** Escribimos `verify.sh`, que comprueba automáticamente los criterios de cada hito: balanceo del Ingress, SSH al admin, conectividad por la VLAN, MySQL y el bloqueo de los accesos no autorizados.

**Despliegue de cero (US-41).** Desplegamos todo el proyecto de punta a punta en otra computadora, siguiendo solo el README, y verificamos que `verify.sh` termina en verde.

**Memoria y demo (US-42, US-43).** Redactamos esta memoria y ensayamos la demo, de modo que cada integrante explicara un área distinta de la suya.

---

## 8. Decisiones de diseño

El registro completo está en [decisions.md](decisions.md). Las más relevantes:

| Decisión | Resumen |
|---|---|
| D-001 | Grupo 2, ruta `/servers-G2` |
| D-002 | Namespace dedicado en lugar de `default` |
| D-009 | Contenedor sidecar para personalizar `index.html` (sustituye a D-003, initContainer) |
| D-004 | Solo autenticación por clave, con dos pares SSH |
| D-005 | IPAM de la VLAN: `whereabouts` para los web y `static` para el admin |
| D-006 | rsyslog en el puerto 514 como servidor de logs |
| D-007 | Cliente de MySQL con egress bloqueado ⟪PENDIENTE⟫ |
| D-008 | Usamos la versión del enunciado del 5/11/2026 |

---

## 9. Problemas encontrados

⟪PENDIENTE: cada área agrega los problemas que encontró y cómo los resolvió. Candidatos ya conocidos:⟫

- MetalLB arranca sin `IPAddressPool`: volvimos a correr `config_metallb` y, mientras tanto, probamos el Ingress por NodePort.
- En el primer despliegue del Deployment web, el `emptyDir` de Nginx se montó en una ruta provisional: el Pod arrancaba, pero Nginx no servía la página generada. Lo detectamos con `kubectl describe pod`, localizamos la raíz real con `grep -r root /etc/nginx/` y corregimos el `mount_path`.
- Las subinterfaces VLAN se pierden cuando se recrea el escenario: las creamos con un script idempotente.
- IPs duplicadas en la VLAN con `host-local` (D-005).
- El contenido de los Secrets queda en el `tfstate`: por eso el estado nunca se sube al repositorio.

---

## 10. Conclusiones

⟪PENDIENTE⟫
