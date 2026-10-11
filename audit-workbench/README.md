# Audit Workbench · Offline Audit Workspace

Asistente local de documentación para auditorías de **hardware, software, redes, sistemas y ciberseguridad**. No realiza escaneos ni modifica infraestructura; el auditor documenta activos, controles, evidencias, hallazgos y recomendaciones, y prepara un **informe PDF** desde el navegador.

La aplicación está **aislada de los scripts de Active Directory** del repositorio. Todos sus archivos, incluyendo los lanzadores, viven en `audit-workbench/`.

## Inicio rápido desde un checkout

**Linux / macOS (Bash)**

```bash
bash ./audit-workbench/audit-workbench.sh
# Instalación/actualización forzada desde los archivos del checkout:
bash ./audit-workbench/audit-workbench.sh --update
```

**Windows (PowerShell 5.1+ / 7)**

```powershell
.\audit-workbench\audit-workbench.ps1
.\audit-workbench\audit-workbench.ps1 -Update
```

Los lanzadores copian la aplicación a la carpeta local de usuario y abren `index.html`. No requieren privilegios administrativos ni Internet cuando se lanzan desde un checkout completo. Puedes abrir directamente `audit-workbench/index.html` manteniendo los recursos junto a él. El PDF se obtiene con **Generar PDF → Imprimir → Guardar como PDF** (preferentemente con fondos habilitados).

## Descarga rápida sin clonar el repositorio

Obtén el lanzador desde una rama/commit conocido y **revísalo** antes de ejecutarlo. La instalación necesita Internet una vez para descargar el HTML, JS, CSS, manifest, SW e iconos; la documentación de auditoría funciona después sin red.

```bash
curl -fL -o audit-workbench.sh 'https://raw.githubusercontent.com/sempitern0/hardening-scripts/feature/offline-audit-workbench/audit-workbench/audit-workbench.sh'
bash ./audit-workbench.sh --ref feature/offline-audit-workbench
```

```powershell
Invoke-WebRequest 'https://raw.githubusercontent.com/sempitern0/hardening-scripts/feature/offline-audit-workbench/audit-workbench/audit-workbench.ps1' -OutFile './audit-workbench.ps1'
.\audit-workbench.ps1 -Ref feature/offline-audit-workbench
```

Tras fusionar en `main`, omite `--ref` y `-Ref`. Si se renombra el repositorio, utiliza `AUDIT_WORKBENCH_REPO=owner/nuevo-repo` (Bash) o `-Repository 'owner/nuevo-repo'` (PowerShell). Evita ejecutar scripts remotos directamente con `curl | bash` o `irm | iex`; revisa el archivo antes. Para actualizar una instalación anterior, usa `--update` o `-Update`.

## Cómo realizar una auditoría

1. **Auditorías guardadas:** crea un expediente, abre uno anterior, búscalo, duplica, exporta a JSON o elimina con confirmación. Los expedientes están separados por ID estable.
2. **Cliente y alcance:** identifica al cliente, autorización, fechas, exclusiones, límites y metodología.
3. **Inventario técnico:** rellena hardware, segmentos de red y software. Los selectores ofrecen valores frecuentes y **Otro / escribir** cuando sea necesario.
4. **Controles:** registra conformidad real; «Pendiente» y «No verificado» no significan conforme.
5. **Hallazgos:** severidad, probabilidad, impacto, activos, evidencia, remediación, responsables y fechas. CVSS es un campo manual, no un cálculo automático.
6. **Evidencias:** adjunta imágenes JPG/PNG/WebP que la app normaliza en el navegador (conserva el original fuera de la aplicación), referencias y hashes opcionales.
7. **Informe final:** escribe conclusiones, resume hallazgos, revisa alcance y guarda el PDF. **Exporta también el JSON** para seguir trabajando en otra ocasión o dispositivo.

Los datos viven preferentemente en **IndexedDB** y, si el navegador no lo permite, en `localStorage`. Ambos almacenamientos son locales al perfil y **origen** del navegador; no se sincronizan ni sustituyen copias de seguridad. Se conserva compatibilidad con los JSON `schemaVersion: 2`. Al abrir por primera vez la nueva versión se intenta migrar el expediente guardado bajo la clave anterior `sysadmin-tools:audit-workbench:v2` sin eliminar esa clave. Las importaciones JSON **crean una nueva auditoría** y no sobrescriben otras.

## PWA en tablets: instalación y uso sin Internet

Una PWA requiere origen seguro para poder registrarse como aplicación instalable. **`file://` sigue funcionando como aplicación web local, pero no se puede instalar como PWA** con service worker en esa modalidad.

1. Publica el contenido estático mediante **HTTPS**, por ejemplo GitHub Pages (Settings → Pages → Deploy from a branch, rama elegida, carpeta `/`); la ruta será similar a `https://USUARIO.github.io/REPOSITORIO/audit-workbench/`. La dirección es un ejemplo, no una URL actualmente confirmada.
2. Con conexión, abre esa dirección una vez y espera a que todos los recursos de la aplicación se descarguen. En Android/Chrome selecciona **Instalar aplicación**; en iPad/Safari, **Compartir → Añadir a pantalla de inicio**.
3. Abre la aplicación instalada. A partir de ese momento funciona sin Internet para **editar, consultar, guardar JSON y preparar PDF** (la opción de impresión/PDF depende del navegador y sistema operativo). Desactiva la red para comprobarlo antes de ir al cliente.

El service worker almacena **solo los archivos estáticos de la aplicación**, nunca el expediente o las imágenes. No usa CDN, API, telemetría ni recursos remotos de terceros. Una actualización futura del HTML/JS requiere volver a conectarse una vez al origen HTTPS. GitHub Pages es únicamente distribución de código público: **los datos del cliente no se suben a GitHub**.

**Atención a los orígenes:** `file://`, `http://localhost`, y `https://...` utilizan almacenamientos distintos. Para migrar entre dispositivos, dominios o modalidades exporta el JSON e impórtalo en el destino. Las PWA pueden perder datos por políticas de limpieza/capacidad del navegador, especialmente en tablets: exporta al final de cada sesión y guarda expedientes en almacenamiento cifrado. No introduzcas contraseñas, tokens ni credenciales reales en texto claro.

## Seguridad

- Interfaz sin peticiones a servicios de terceros; CSP restrictiva, HTML escapado, importación JSON con esquema validado, máximos por archivo/registro y tipos de imagen permitidos.
- Persistencia por transacciones IndexedDB y guardado automático; indicador de errores de escritura. No se envían datos a ninguna red.
- Los PDFs se renderizan en el navegador; el tema visual afecta a la interfaz pero los informes mantienen un estilo imprimible consistente.
- El borrado local es irreversible salvo que hayas exportado una copia. No sustituye al borrado seguro del dispositivo.
- La validación editorial y la autorización del contenido siguen siendo responsabilidad del auditor. El programa no acredita cumplimiento legal o normativo ni genera una puntuación CVSS verificada.

## Desarrollo y pruebas

```bash
bash -n audit-workbench/audit-workbench.sh
node --check audit-workbench/app.js
node --check audit-workbench/sw.js
python audit-workbench/tests/test_e2e.py   # Playwright y PyMuPDF instalados solo en el entorno de prueba
```

El modo de prueba automatizado monta un documento artificial porque el navegador del entorno de CI restringe la navegación directa local; prueba el CRUD y PDF, pero la instalación PWA real debe probarse en Android/iPadOS con HTTPS. La aplicación no necesita Node, Python ni Playwright para ejecutarse.

### Referencia editorial

Inspirado en la estructura del documento compartido `RG001_INFORME_RESULTADOS_PENTESTING.pdf`: alcance y exclusiones, confidencialidad, metodología, resumen ejecutivo, severidad, riesgos, evidencias, hallazgos y remediaciones. No reproduce marcas, datos, capturas ni partes sustanciales del material original.
