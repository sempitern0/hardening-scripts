# Audit Workbench · auditorías técnicas offline

Aplicación HTML/PWA para documentación y entrega de auditorías informáticas de **sistemas, redes, hardware, software y seguridad**. Se distribuye junto con dos instaladores Bash y PowerShell, pero no ejecuta hardening ni escanea redes. Está aislada de los asistentes de Active Directory del repositorio.

**Regla central:** el expediente se trabaja localmente y se entrega cuando el auditor lo decide. Sin registro, cuentas, analítica, telemetría, servicios cloud ni librerías CDN. La consulta online de CVE y el uso de clientes de correo o de la función de compartir son opcionales y requieren intervención explícita del usuario.

## Inicio rápido

Desde un clone/ZIP del repositorio, estando en `audit-workbench/`:

```bash
bash ./audit-workbench.sh
```

```powershell
.\audit-workbench.ps1
```

O abre directamente `index.html` en un navegador moderno. Para instalar la PWA en tablet/móvil hace falta **primera carga desde HTTPS con certificado válido**; `file://` no soporta service workers y la instalación nativa puede depender del navegador y sistema. Véase [INSTALLATION.md](INSTALLATION.md).

Para descargar solo el instalador desde GitHub, revisarlo y ejecutarlo:

```bash
curl -fL -o audit-workbench.sh \
  'https://raw.githubusercontent.com/sempitern0/hardening-scripts/feature/offline-audit-workbench/audit-workbench/audit-workbench.sh'
less audit-workbench.sh
AUDIT_WORKBENCH_REF=feature/offline-audit-workbench bash ./audit-workbench.sh
```

En Windows con PowerShell, descarga y revisa antes de ejecutar:

```powershell
Invoke-WebRequest 'https://raw.githubusercontent.com/sempitern0/hardening-scripts/feature/offline-audit-workbench/audit-workbench/audit-workbench.ps1' -OutFile audit-workbench.ps1
Get-Content .\audit-workbench.ps1
.\audit-workbench.ps1 -Ref feature/offline-audit-workbench
```

> La rama `feature/offline-audit-workbench` es de desarrollo. Sustituye su URL por `main` cuando la versión haya sido publicada. Evita `curl | bash` o `irm | iex` en clientes de terceros; descarga e inspecciona el script antes de ejecutarlo. Para cambiar el repositorio usa `AUDIT_WORKBENCH_REPO` (Bash) o `-Repository` (PowerShell).

## Contenido

- **Biblioteca:** auditorías guardadas, búsqueda, duplicado, borrado con confirmación, exportación individual y respaldo de todas las auditorías.
- **Cliente/alcance:** empresa, consultor, proyecto, clasificación, alcance autorizado, limitaciones, metodología, fechas y logotipo JPEG/PNG/WebP optimizado localmente.
- **Inventario:** modelos de hardware dependientes del fabricante (con opción «Otro»), equipos físicos/virtuales, procesadores, memoria, discos, SO/firmware, fabricantes, modelos y ciclo de vida; redes/subredes/VLAN; software y licencias. Selectores con opción **Otro / escribir**.
- **Seguridad:** controles y hallazgos con severidad, valoración de riesgo, medidas de remediación, referencias, responsables y pruebas.
- **CVE:** registro manual con estados de verificación, activos afectados y fuente; consulta individual a CVE Services bajo autorización expresa cuando hay Internet; enlace a CVE.org. **No es un escáner de vulnerabilidades.**
- **Evidencias:** fotografías/capturas opcionales comprimidas en el navegador, identificadores de evidencia y hashes manuales.
- **Cláusulas:** modelos editables de confidencialidad, autorización, limitaciones, privacidad y custodia basados en contexto español, nunca sustitutos de contrato o revisión legal.
- **Informe:** portada con logo, capítulos, distribución de severidades, inventarios, CVE, evidencias y recomendaciones. La paleta escogida modifica el acento del PDF y el fondo de su portada, mientras las páginas de contenido mantienen fondo blanco para lectura e impresión.
- **Entrega:** JSON individual, backup JSON de todos los expedientes, imprimir/guardar PDF, compartir JSON a través del diálogo nativo cuando esté disponible, y preparar correo sin adjuntos. Ningún envío es automático.

## Exportación, restauración y backup (imprescindible)

1. Al terminar una sesión pulsa **Guardar JSON**. Se genera un expediente portable `auditoria-<cliente>-<fecha>.json` con los datos, cláusulas, CVE y las imágenes/logotipo incorporados.
2. Para respaldar *todos* los informes, entra en **Mis auditorías → Respaldar todas (JSON)**. Se genera `audit-workbench-backup-AAAA-MM-DD.json`.
3. Copia el archivo a una ubicación cifrada con respaldo controlado. No lo subas a servicios no autorizados.
4. En otro equipo abre Audit Workbench, pulsa **Importar**, elige el JSON individual o el backup y acepta la importación. Los expedientes importados se agregan como **nuevas copias**; no sobrescriben los existentes.
5. Abre la biblioteca y comprueba que el número de activos, hallazgos y evidencias coincide. Genera el PDF y valida el resultado antes de entregar.

**Advertencia:** IndexedDB/localStorage pertenecen al perfil del navegador y al origen (`file://`, `https://servidor`, `http://localhost`). Borrar datos de sitio, usar incógnito, cambiar de navegador/perfil, reinstalar el sistema o cambiar la URL de origen **puede hacer desaparecer los expedientes locales**. Una PWA instalada no equivale a un backup; exporta los JSON con frecuencia. Los archivos de backup no están cifrados por la aplicación.

## Generación de PDF

Selecciona el tema y carga el logotipo en **Cliente y alcance**, revisa **Cláusulas y privacidad** y **Informe final**, y pulsa **Generar PDF**. En el diálogo de impresión del sistema selecciona **Guardar como PDF** (Android/iPadOS pueden utilizar la función de imprimir/compartir del navegador) y activa **gráficos de fondo** si tu navegador ofrece esa opción para reproducir todos los colores.

El PDF contiene una instantánea del expediente *en ese momento*. No se modifica automáticamente si luego cambias la auditoría. Revisa encabezados, saltos de página, capturas y cumplimiento de requisitos del cliente antes de enviarlo. El PDF no constituye evidencia de integridad criptográfica ni una firma digital.

## CVE y conectividad

El catálogo CVE admite trabajar sin Internet. Rellena `CVE-AAAA-NNNN`, el activo, la evaluación, la fuente y las notas. **Sin verificar** es el valor prudente por defecto. La acción **Consultar CVE online** realiza, solo después de confirmar, una petición `GET https://cveawg.mitre.org/api/cve/<ID>`, sin enviar otros campos del expediente; se importa descripción/fuente/fecha de publicación, **no** se declara una vulnerabilidad confirmada ni se inventan métricas CVSS. El navegador, una política CORS, el firewall o la disponibilidad del servicio pueden bloquear la consulta; siempre queda la consulta manual en CVE.org.

La función de compartir utiliza la API nativa `navigator.share` **solo cuando está soportada**, previa confirmación, y comparte el **JSON completo**, no el PDF: el sistema/navegador decide canales. La opción de correo genera un borrador `mailto` **sin archivos adjuntos**; adjunta personalmente el PDF a un canal autorizado. **No hay sincronización con Dropbox/Drive ni envío SMTP/API automático** en esta versión. Véase [SECURITY.md](SECURITY.md).

## Seguridad y límites

- La aplicación carece de servidor y de sistema de cuentas. **No introduzcas contraseñas, claves, hashes de autenticación o tokens sin tratar** en el expediente.
- La importación valida esquema y límites de filas/imágenes; el HTML escapa contenido textual. No se carga JavaScript de terceros; la CSP permite únicamente la consulta individual a CVE Services mediante HTTPS.
- Los datos locales y las exportaciones **no se cifran** automáticamente. Usa discos cifrados, copias controladas y una política de acceso/retención que acuerdes con el cliente.
- Los textos legales son plantillas editables; consulta [LEGAL.md](LEGAL.md) y revisión jurídica cuando corresponda.
- Un informe profesional no implica certificación ISO 27001, conformidad ENS/CIS ni auditoría exhaustiva a menos que el alcance y las evidencias lo justifiquen.

## Desarrollo y regresión

```bash
node --check audit-workbench/app.js
bash -n audit-workbench/audit-workbench.sh
python audit-workbench/tests/test_e2e.py  # Requiere Chromium, Playwright y PyMuPDF en entorno de desarrollo
```

El proyecto prioriza ECMAScript moderno sin empaquetador: funciones nativas, eventos delegados, persistencia versionada, escapado sistemático y sin `eval`, `innerHTML` de datos sin sanitizar ni bibliotecas remotas. La app está preparada para una futura separación por módulos, respetando su uso offline y su despliegue con HTML/JS estáticos.

## Interfaz y accesibilidad (v5)

- **Menú principal:** biblioteca de expedientes y herramientas conectadas. Al abrir una auditoría aparece un menú diferente con el proyecto y su referencia claramente visibles.
- **Logotipo:** PNG, JPEG y WebP de hasta 3 MiB. Se procesa enteramente en el dispositivo, se incrusta como JPEG y se valida tras importación. El formato SVG aportado por usuarios no se admite, porque puede contener código activo. El icono de la propia aplicación sí es un SVG local y estático.
- **Fabricante y modelo:** el modelo depende del fabricante; cambiar de fabricante reinicia el modelo anterior. Si no figura tu equipo, usa «Otro / escribir».
- **Severidades:** las etiquetas se actualizan al cambiar el selector, sin recargar la página.
- **Temas:** paletas claras y oscuras ahora afectan a las superficies de edición y a la portada del PDF. Para conservar fondos al imprimir, habilita los gráficos de fondo.
- **Fuente:** Atkinson Hyperlegible se utiliza desde los archivos locales Regular, Bold, Italic y BoldItalic incluidos en el repositorio. No se descargan fuentes externas.

La opción **Herramientas conectadas** reúne la consulta individual de CVE, el cliente de correo y el diálogo nativo para compartir archivos, además de explicar los límites de sincronización cloud. No existen integraciones automáticas con plataformas externas.

## Versión v6 — navegación guiada, identidad y conectores

La aplicación tiene **tres entradas principales**: Biblioteca, Configuración y Conexiones online. Al abrir un expediente, su nombre y referencia se muestran en la parte superior. Las fases de evaluación ya no ocupan el menú lateral: usa **Anterior / Siguiente** o el selector **Ir al paso** al final de cada formulario. El indicador de progreso también aparece al comienzo del contenido. Esto deja más espacio en tablets y pantallas pequeñas.

### Identidad de consultora y numeración

En **Configuración** puedes guardar el nombre legal, NIF/NIE de la consultora, dirección, contacto, prefijo, logo y **directorio de auditores**. Desde **Cliente y alcance → Profesionales asignados** selecciona uno o varios miembros del equipo para cada expediente. Las fichas de los profesionales elegidos se guardan dentro de esa auditoría y aparecen en el PDF, aunque luego se modifique el directorio global. Cada auditor debe registrar **DNI, NIE o pasaporte/otro identificador** antes de poder ser asignado: se comprueba localmente el formato y, para DNI/NIE, la letra de control. Los documentos se incorporan a la atribución del informe PDF y al JSON del expediente, por lo que deben custodiarse como datos personales; esta validación no acredita identidad real ni sustituye la identificación contractual. Los expedientes nuevos reciben por defecto los datos corporativos y el logo; los ya existentes conservan sus campos editados. **Exportar perfil JSON** guarda la configuración y los contadores de numeración (incluye logo, no credenciales); **Importar perfil JSON** restaura el perfil.

Los informes reciben códigos automáticos por cliente, por ejemplo `AUD-001`, `AUD-002`, `AUD-003`. Un cliente diferente inicia en `AUD-001`. Las secuencias se mantienen incluso si se borra una auditoría. El identificador puede editarse manualmente; desde ese momento deja de renumerarse automáticamente. **Una misma empresa debe registrarse con un nombre uniforme**; nombres escritos con variantes se consideran clientes diferentes. Este contador pertenece a la instalación local, por lo que la configuración debe exportarse si se cambia de dispositivo. La auditoría no utiliza un registro de identificadores centralizado.

### Validaciones contextuales

- **DNI / NIF persona física:** 8 dígitos y letra de control.
- **NIE:** X, Y o Z, siete cifras y letra de control.
- **NIF de entidad (antiguo CIF):** formato y carácter de control de los identificadores habituales de entidades españolas.
- **NIF intracomunitario:** únicamente comprobación de sintaxis, **sin validación VIES**.
- **Correo, teléfono, código postal español, SHA-256, VLAN, CVSS y fechas:** verificaciones contextuales para ayudar a detectar errores de transcripción.

Los avisos aparecen bajo los campos. Se puede seguir guardando un expediente incompleto; al generar un PDF se advierte si existen errores de formato. **Las comprobaciones no prueban identidad, titularidad, vigencia fiscal ni veracidad del dato.** Evita registrar identificadores personales si no son necesarios para el encargo, aplica minimización conforme a RGPD y revisa las cláusulas contractuales antes de entregar.

### Conexiones online guiadas

En **Conexiones online** hay un selector de canal y una secuencia explícita de configuración, desbloqueo y entrega. Funciones disponibles:

1. **Nextcloud/WebDAV**, mediante URL HTTPS, usuario y **contraseña de aplicación**. La conexión se guarda en `localStorage` como un sobre cifrado **AES-256-GCM** derivado de una frase de paso con **PBKDF2-SHA256 / 310.000 iteraciones**, con sal e IV aleatorios. Ni la contraseña de aplicación ni la frase de paso se almacenan en texto plano. Al reabrir se pide la frase de paso. La credencial descifrada solo permanece en memoria mientras la página está abierta. Si se olvida la frase, hay que borrar el perfil y configurarlo otra vez.
2. **Correo:** abre el cliente `mailto` con destinatario/asunto/mensaje preparados; **no adjunta el PDF automáticamente**.
3. **Compartir:** utiliza el menú nativo `navigator.share` si está disponible o exportación manual si no lo está.

**Restricción de Nextcloud:** las peticiones WebDAV desde navegador necesitan cabeceras CORS configuradas en el servidor. Si no están permitidas, la subida devolverá un error visible y el expediente permanecerá local. La subida solo se realiza tras pulsar el botón y confirmar destinatario/origen HTTPS. No hay sincronización automática ni servicios externos durante el trabajo offline. Los proveedores basados en OAuth se incorporarán con flujos para clientes públicos, sin incrustar secretos de aplicación en el frontend.

> El cifrado de la credencial protege su almacenamiento local **en reposo** frente a lectura casual del navegador; no elimina el riesgo de un dispositivo comprometido, XSS, extensiones maliciosas o filtraciones cuando la conexión está desbloqueada. Usa un perfil/browser y sistema operativos protegidos, HTTPS de confianza y permisos mínimos en Nextcloud. No compartas perfiles de navegador con clientes.

### Fuentes locales opcionales

La fuente **Atkinson Hyperlegible** se sirve localmente mediante `fonts/atkinson.css`. El repositorio incorpora cuatro archivos WOFF2: Regular, Bold, Italic y BoldItalic. En instalaciones completas de GitHub se aplican automáticamente sin conexión a servicios externos. Si distribuyes un ZIP que no incluya estas fuentes, el navegador utilizará su tipografía de sistema sin bloquear la auditoría.
