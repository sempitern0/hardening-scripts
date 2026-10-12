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
  'https://raw.githubusercontent.com/sempitern0/sysadmin/main/audit-workbench/audit-workbench.sh'
less audit-workbench.sh
AUDIT_WORKBENCH_REF=main bash ./audit-workbench.sh
```

En Windows con PowerShell, descarga y revisa antes de ejecutar:

```powershell
Invoke-WebRequest 'https://raw.githubusercontent.com/sempitern0/sysadmin/main/audit-workbench/audit-workbench.ps1' -OutFile audit-workbench.ps1
Get-Content .\audit-workbench.ps1
.\audit-workbench.ps1 -Ref main
```

> Los ejemplos anteriores instalan desde `main` del repositorio `sempitern0/sysadmin`. Evita `curl | bash` o `irm | iex` en clientes de terceros; descarga e inspecciona el script antes de ejecutarlo. Para cambiar el repositorio usa `AUDIT_WORKBENCH_REPO` (Bash) o `-Repository` (PowerShell).

## Plantillas offline de controles (v13)

En una auditoría abierta, abre **Controles → Plantillas de comprobaciones**. Selecciona el área (sistemas, redes, identidad o continuidad) y despliega la lista. Puedes desmarcar controles que estén fuera del alcance antes de pulsar **Añadir controles seleccionados**. El sistema identifica las plantillas ya añadidas y **no duplica** sus controles al aplicar el mismo paquete de nuevo.

- Todos los controles se incorporan como **Pendiente**: importar una plantilla **no acredita que una prueba se haya realizado**, ni certifica cumplimiento de CIS, ISO, ENS u otro marco.
- Cada control incorpora una metodología orientativa y un desplegable **Guía rápida** con la evidencia esperada y una medida recomendada. Ajusta el método, el alcance y el resultado tras una verificación real.
- Si marcas un control **No conforme**, aparecerá **Documentar hallazgo**. La ficha resultante copiará la descripción y los datos relevantes y **heredará las evidencias vinculadas**, pero dejará la severidad **Sin evaluar** para que el auditor determine el impacto. No se ejecuta ningún cambio sobre la infraestructura.
- El expediente conserva el identificador de plantilla y la relación entre control y hallazgo. Si borras el control de origen, **Informe final** advertirá de la referencia ausente.
- Los paquetes son parte de la aplicación y funcionan sin Internet. Las auditorías existentes no se ven alteradas al actualizar: solo se añaden controles cuando lo solicita el usuario.

Los controles son **listas orientativas de revisión**, no una metodología certificada ni un diagnóstico automático. El auditor debe conocer las autorizaciones, el alcance, los criterios aplicables y las evidencias que corresponden a cada cliente.

## Contenido

- **Biblioteca:** auditorías guardadas, búsqueda, duplicado, borrado con confirmación y acceso al gestor de copias de seguridad.
- **Copias y exportaciones:** respaldo JSON restaurable, opción de guardar copias periódicas en una carpeta autorizada y entregables XLSX/CSV offline.
- **Cliente/alcance:** empresa, consultor, proyecto, clasificación, alcance autorizado, limitaciones, metodología, fechas y logotipo JPEG/PNG/WebP optimizado localmente.
- **Inventario:** modelos de hardware dependientes del fabricante (con opción «Otro»), equipos físicos/virtuales, procesadores, memoria, discos, SO/firmware, fabricantes, modelos y ciclo de vida; redes/subredes/VLAN; software y licencias. Selectores con opción **Otro / escribir**.
- **Seguridad:** controles y hallazgos con severidad, valoración de riesgo, medidas de remediación, referencias, responsables y pruebas.
- **CVE:** registro manual con estados de verificación, activos afectados y fuente; consulta individual a CVE Services bajo autorización expresa cuando hay Internet; enlace a CVE.org. **No es un escáner de vulnerabilidades.**
- **Evidencias:** fotografías/capturas opcionales comprimidas en el navegador, identificadores de evidencia y hashes manuales.
- **Cláusulas:** modelos editables de confidencialidad, autorización, limitaciones, privacidad y custodia basados en contexto español, nunca sustitutos de contrato o revisión legal.
- **Informe:** portada con logo, capítulos, distribución de severidades, inventarios, CVE, evidencias y recomendaciones. La paleta escogida modifica el acento del PDF y el fondo de su portada, mientras las páginas de contenido mantienen fondo blanco para lectura e impresión.
- **Entrega:** JSON individual, backup JSON restaurable, exportación XLSX/CSV, imprimir/guardar PDF, compartir JSON a través del diálogo nativo cuando esté disponible, y preparar correo sin adjuntos. Ningún envío es automático.

## Exportación, restauración y backup (imprescindible)

1. Al terminar una sesión pulsa **Guardar JSON**. Se genera un expediente portable `auditoria-<cliente>-<fecha>.json` con los datos, cláusulas, CVE y las imágenes/logotipo incorporados.
2. Para respaldar *todos* los informes, entra en **Copias y exportaciones → Descargar backup completo (.json)**. Se genera `audit-workbench-backup-AAAA-MM-DD.json`.
3. Copia el archivo a una ubicación cifrada con respaldo controlado. No lo subas a servicios no autorizados.
4. En otro equipo abre Audit Workbench, pulsa **Importar**, elige el JSON individual o el backup y acepta la importación. Los expedientes importados se agregan como **nuevas copias**; no sobrescriben los existentes.
5. Abre la biblioteca y comprueba que el número de activos, hallazgos y evidencias coincide. Genera el PDF y valida el resultado antes de entregar.

### Copias en una carpeta elegida (opcional)

En navegadores compatibles con la **File System Access API** (habitualmente Chrome/Edge de escritorio o ciertos Chromium), abre **Copias y exportaciones → Seleccionar carpeta**. Elige una carpeta de confianza y concede permiso de escritura. Usa **Guardar ahora** para comprobar la operación. Puedes activar **Copias cada 30 minutos**: solo se crearán cuando haya cambios, con la aplicación abierta y visible y mientras se mantengan los permisos. Los archivos tienen fecha/hora en el nombre y **no** se eliminan automáticamente. Desvincular la carpeta quita su autorización desde la aplicación, sin borrar copias anteriores.

Firefox, Safari y determinados dispositivos móviles pueden no ofrecer la API. En ese caso, utiliza **Descargar backup completo (.json)**. Por seguridad el navegador no permite escribir arbitrariamente en la carpeta donde reside la aplicación. No conviertas los backups en archivos públicos del servidor: contienen datos de clientes, evidencias y datos personales.

### CSV y Excel (XLSX)

En **Copias y exportaciones** puedes descargar:

- **Excel (.xlsx):** libro con ocho hojas (Resumen, Hardware, Redes, Software, CVE, Controles, Hallazgos y Evidencias), encabezados, filtros y primera fila fija. Se genera con JavaScript local, sin servicios online. No incrusta imágenes de evidencias.
- **CSV (.csv):** una sección a elegir, en UTF-8 con BOM y separador `;` para facilitar la apertura en Excel configurado en español. Los valores potencialmente interpretables como fórmulas se fuerzan a texto.

Ambos formatos son **entregables tabulares** destinados a revisión, intercambio y remediación: **no son backups restaurables** ni sustituyen al PDF. Solo JSON conserva la totalidad del expediente y sus capturas incrustadas. Antes de entregar hojas, revisa su contenido, los accesos autorizados y los metadatos que puedan identificar personas o sistemas.

**Advertencia:** IndexedDB/localStorage pertenecen al perfil del navegador y al origen (`file://`, `https://servidor`, `http://localhost`). Borrar datos de sitio, usar incógnito, cambiar de navegador/perfil, reinstalar el sistema o cambiar la URL de origen **puede hacer desaparecer los expedientes locales**. Una PWA instalada no equivale a un backup; exporta los JSON con frecuencia. Los archivos de backup no están cifrados por la aplicación.

## Evidencias vinculadas y trazabilidad (v12)

En **Hardware**, **Controles**, **Hallazgos** y **Evidencias**, los registros nuevos reciben identificadores estables (`ACT-001`, `CTRL-001`, `FND-001` y `EVD-001`). Los identificadores anteriores se conservan: no se renumeran automáticamente expedientes existentes.

1. Registra el activo y la comprobación o hallazgo que quieras documentar.
2. En **Evidencias**, añade una ficha y usa **Relacionar con el expediente** para seleccionar los activos, controles y hallazgos pertinentes. Las selecciones se hacen mediante listas, sin copiar códigos. Puedes quitar una relación mediante su etiqueta.
3. Opcionalmente, adjunta una captura local PNG/JPEG/WebP (máximo 5 MiB). La app calcula **SHA-256 del archivo original seleccionado** cuando el navegador dispone de Web Crypto y conserva en el JSON la huella, nombre y tamaño. La vista previa JPEG se comprime y puede tener otra huella.
4. Conserva **el archivo original** en almacenamiento seguro fuera de Audit Workbench. La herramienta no almacena automáticamente los bytes originales: el hash no constituye por sí mismo una cadena de custodia, firma digital ni prueba de autenticidad.
5. Pulsa **Manifiesto SHA-256 (JSON)** en Evidencias para descargar un resumen de nombres, hashes y asociaciones. Es un anexo de control, no un backup ni un manifiesto firmado.

Las asociaciones usan identificadores internos estables: cambiar el nombre de un activo no rompe sus vínculos. Si eliminas un activo relacionado, **Informe final** te avisará de referencias que ya no existen, sin borrar silenciosamente la evidencia. Las referencias de texto antiguas también se conservan. Al exportar o restaurar un expediente JSON, las relaciones se preservan de forma opcional dentro del mismo esquema de datos v3.

**Privacidad:** revisa las capturas para retirar secretos, identificadores y datos de personas que no sean necesarios. Calcula la huella antes de redactar u optimizar un original si necesitas conservar la trazabilidad de ambos estados.

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
node --check audit-workbench/exporters.js
bash -n audit-workbench/audit-workbench.sh
python audit-workbench/tests/test_e2e.py  # Requiere Chromium, Playwright y PyMuPDF en entorno de desarrollo
```

El proyecto utiliza pequeños módulos autocontenidos (`audit-relations.js`, `hardware-catalog.js`, `exporters.js` y `app.js`) y prioriza ECMAScript moderno sin empaquetador: funciones nativas, eventos delegados, persistencia versionada, escapado sistemático y sin `eval`, `innerHTML` de datos sin sanitizar ni bibliotecas remotas. La app está preparada para una futura separación por módulos, respetando su uso offline y su despliegue con HTML/JS estáticos.

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

En **Configuración** puedes guardar el nombre legal, NIF/NIE de la consultora, dirección, contacto, prefijo, logo y **directorio de auditores**. Desde **Cliente y alcance → Profesionales asignados** selecciona uno o varios miembros del equipo para cada expediente. Las fichas de los profesionales elegidos se guardan dentro de esa auditoría y aparecen en el PDF, aunque luego se modifique el directorio global. Los expedientes nuevos reciben por defecto los datos corporativos y el logo; los ya existentes conservan sus campos editados. **Exportar perfil JSON** guarda la configuración y los contadores de numeración (incluye logo, no credenciales); **Importar perfil JSON** restaura el perfil.

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


## Catálogo offline de fabricantes y modelos

En **Hardware**, selecciona primero el fabricante para filtrar los modelos disponibles.
El catálogo incluido cubre familias habituales de servidores, estaciones, conmutadores,
firewalls, NAS, SAI e impresoras. También contiene equipos anteriores porque pueden
seguir apareciendo en auditorías. Para cualquier equipo no listado utiliza
**«Otro / escribir…»**: su valor se conserva en el expediente y en el PDF.

El catálogo funciona **sin Internet**. No indica si un dispositivo tiene soporte,
firmware actualizado, certificaciones vigentes o disponibilidad comercial; confirma
esos datos directamente con el fabricante cuando correspondan.

## Impresión local y en red

**Generar PDF** abre la impresión nativa del navegador. Puedes elegir «Guardar como
PDF» o una impresora ya configurada en Windows, Linux, macOS, Android o iPadOS,
según las capacidades del dispositivo y del navegador. La aplicación no instala
controladores, no descubre impresoras IPP ni modifica la configuración de impresión
del sistema. Si necesitas una impresora de red, configúrala primero en el
dispositivo o mediante la administración corporativa.
