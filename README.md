# MPA Flow

Sitio web institucional bilingüe de MPA Flow.

## Publicación en Netlify

- Build command: dejar vacío
- Publish directory: `.`
- El formulario `mpa-flow-contact` utiliza Netlify Forms.
- Después del primer despliegue, configurar una notificación por email a `hello@mpaflow.com` desde **Forms > Form notifications** en Netlify.

## Panel de edición

El panel está disponible en `/admin/` y guarda los cambios en la rama `main` del repositorio `StraySheepAI/mpaflow` mediante Decap CMS.

Después de conectar el repositorio con Netlify:

1. Activar **Identity**.
2. Establecer el registro como **Invite only**.
3. Activar **Git Gateway** y vincularlo con GitHub.
4. Invitar a la administradora del sitio.
5. Ingresar en `https://TU-DOMINIO/admin/`.

Desde allí se pueden editar la portada, títulos principales, equipo, imágenes y datos de contacto. Cada publicación genera un cambio en GitHub y un nuevo despliegue automático.

## Edición

La página principal está en `index.html`. Las imágenes están en la raíz y en la carpeta `assets`.
