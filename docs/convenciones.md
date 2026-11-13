# 🌿 Convenciones de ramas y commits

⬅️ [Volver al plan](../plan.md) · Historia: [US-00](../historias/persona-c.md#us-00)

## Ramas

- `main` siempre debe desplegar sin errores. **Nadie trabaja directo en `main`.**
- **Una rama por historia**, creada desde `main` actualizado:

  ```
  us-<NN>-<descripcion-corta>
  ```

  Ejemplos: `us-01-esqueleto-terraform`, `us-14-deployment-web`, `us-30-default-deny`.
- Todo en minúsculas, separado por guiones, sin acentos ni ñ.

```bash
git switch main
git pull
git switch -c us-14-deployment-web
```

## Commits

Formato:

```
US-<NN>: <qué se hizo, en presente>
```

Ejemplos:

```
US-14: agrega initContainer que genera index.html con el nombre del Pod
US-15: corrige rewrite-target del Ingress
US-30: agrega NetworkPolicy default-deny
```

- Commits pequeños y que funcionen solos.
- Antes de cada commit con cambios de Terraform: `terraform fmt -recursive` y `terraform validate`.
- ⚠️ Revisar `git status` antes de cada commit: ningún `*.tfstate`, `*.tfvars`, clave privada ni carpeta `keys/` (ya están en `.gitignore`, pero revísenlo igual).

## Integración a `main` 🔀

1. Hacer push de la rama y abrir un Pull Request hacia `main`, con el título `US-<NN> · <título de la historia>`.
2. En la descripción, copiar los 🧪 criterios de aceptación de la historia y marcar los que se probaron.
3. **Lo revisa y aprueba otra persona del equipo**, de preferencia de otra área. Nadie hace merge de su propio PR.
4. Merge con *squash*, y borrar la rama.

## Carpetas con `test.txt`

Las carpetas vacías tienen un `test.txt` vacío para que Git las guarde. Cuando la carpeta ya tenga contenido real, borren su `test.txt`.
