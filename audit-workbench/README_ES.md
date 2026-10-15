# Audit Workbench · sysadmin

[English](README.md) · **Español**

[← Volver al repositorio sysadmin](../README_ES.md) · [Instalación](INSTALLATION_ES.md) · [Seguridad](SECURITY_ES.md) · [Notas legales](LEGAL_ES.md)

**Herramienta de auditoría, inventario y documentación técnica offline-first** para inventariar activos, evaluar controles, documentar hallazgos y evidencias, planificar correcciones y preparar informes para clientes.

La PWA funciona en el navegador y no ejecuta escaneos. El **motor opcional de descubrimiento externo** se ejecuta en el equipo del auditor, sin instalar agentes en los dispositivos del cliente ni modificar sus configuraciones.

## Comenzar

Desde la carpeta `audit-workbench/` del repositorio:

```bash
bash ./audit-workbench.sh
```

```powershell
.\audit-workbench.ps1
```

Para trabajar a través de un origen estable en el equipo:

```bash
cd audit-workbench
python -m http.server 8765 --bind 127.0.0.1
```

Abre `http://127.0.0.1:8765`. Para instalar la PWA en tablet o móvil, consulta **[Instalación por dispositivo](INSTALLATION_ES.md)**: la primera carga requiere HTTPS y un navegador compatible.

## Instalar la PWA desde un servidor HTTPS

Para instalarla en tablets y móviles desde una dirección común, hemos añadido un [despliegue HTTPS estático con Docker Compose y Caddy](deploy/README_ES.md). El servidor solo entrega la aplicación y gestiona certificados; no almacena auditorías, no sincroniza dispositivos ni ejecuta Discovery. Los datos continúan en el navegador y deben protegerse mediante backups JSON. Antes de cambiar de URL exporta los expedientes desde el origen anterior.

## Revisión inicial de la situación actual

Basándonos en la **Planificación Auditoría Informática**, se amplían las fichas de **Hardware**, **Redes** y **Software** con una sección desplegable **«Revisión ampliada · situación actual»**. Permite documentar licencias, actualizaciones, antivirus/EDR, cuentas y procesos, capacidad de RAM y discos, GPU, cableado, cifrado Wi-Fi, canal, banda y velocidad medida/contratada. Son campos **opcionales**: los valores no verificados quedan vacíos, no se asume una configuración favorable. Se conservan en el mismo expediente JSON, se pueden importar desde capturas revisadas, aparecen en CSV/XLSX y en el informe técnico únicamente cuando están cumplimentados.

En **Controles → Plantillas de comprobaciones**, el paquete **«Situación actual · revisión inicial»** permite incorporar 14 pruebas con método, evidencia esperada y recomendaciones. Todas empiezan **Pendiente**. Ningún dato recopilado se convierte por sí solo en una conformidad o vulnerabilidad. Las referencias del documento a **500 GB**, categorías CAT5/CAT5e o WPA2/WPA3 son contextuales y no se aplican como umbrales automáticos. Revisa políticas, alcance, hardware y normativas aplicables antes de emitir un juicio.

### Altas rápidas y fabricantes de software

Los registros nuevos se colocan **al principio de su lista** y la vista se desplaza al primer campo editable, tanto en altas manuales como al crear hallazgos desde controles, añadir plantillas o importar lotes. Los lotes conservan su orden original y los identificadores y relaciones se mantienen por claves estables. También se muestran arriba los nuevos profesionales del directorio.

En **Software → Fabricante / editor** se utiliza un catálogo específico de proveedores (Oracle, Google, Adobe, AWS, Microsoft, Red Hat, SAP, etc.), independiente del catálogo de hardware. Puedes seguir usando **Otro / escribir…** cuando el fabricante no aparezca, y los valores existentes no se reescriben.

## Firma visual del equipo auditor

En **Configuración → Equipo de auditores**, cada profesional puede añadir una imagen PNG/JPG/WebP de su firma (hasta 2 MiB). La imagen se optimiza como JPEG y queda almacenada en el perfil local; la firma se copia al expediente cuando el profesional es asignado en **Cliente y alcance**. Si cambias una firma posteriormente, el expediente existente conserva la anterior hasta que desmarques y vuelvas a marcar al profesional (solo en expedientes editables).

Los informes PDF **ejecutivo**, **técnico** y **de reevaluación** añaden al final una página con los profesionales asignados, sus firmas gráficas disponibles y una nota legal. Una imagen de firma **no es una firma electrónica validada** ni equivale a consentimiento/identidad acreditada. También puedes seleccionar un PDF/P7S/P7M/ASiC-E externo: la aplicación solo guarda nombre y SHA-256, **no guarda ni verifica el archivo**; conserva el original aparte. No admitimos certificados, claves privadas, P12 ni PFX.

**Privacidad:** las imágenes forman parte de la configuración, sus copias JSON y los expedientes donde se hayan asignado profesionales; protege los respaldos cifrados y limita su distribución. Las confirmaciones documentales siguen siendo necesarias para entregar la versión definitiva.

## Capturas directamente en hallazgos

En **Problemas detectados y recomendaciones** puedes adjuntar imágenes PNG/JPG/WebP de hasta 5 MiB por hallazgo. Cada imagen crea una nueva evidencia vinculada, sin sobrescribir las anteriores, con SHA-256 del original cuando está disponible. Las capturas aparecen en el informe técnico, pueden gestionarse en **Evidencias** y quedan incluidas en el JSON. Conserva el original aparte. Si el expediente está confirmado, debes abrir una rectificación antes de modificarlo.

## Entrada guiada de datos

Los formularios muestran ejemplos contextuales para DNI, NIE, CIF/NIF entidad, identificación fiscal, IP, CIDR, VLAN, CVE, CVSS, SHA-256, referencias y otros campos de formato especializado. Los campos de teléfono de cliente, consultora y auditores admiten selección de país con bandera y prefijo, y presentan una máscara orientativa. Se conserva el teléfono en formato internacional dentro del campo existente (sin migración del JSON); la validación de identidad y teléfono sigue siendo local y no comprueba la titularidad o asignación real. Los números antiguos permanecen editables.

## Distribución segura de expedientes y PDF

En **Conexiones online → Nextcloud** es posible descargar o subir un backup JSON cifrado localmente (AES-256-GCM y PBKDF2). La frase no se envía al servidor. La recuperación descarga un JSON para revisar e importar manualmente. WebDAV requiere HTTPS, contraseña de aplicación, autorización explícita y CORS compatible.

Para el PDF: genera el documento mediante **Generar PDF**, guárdalo desde impresión y selecciónalo en Conexiones. Se previsualiza mediante una URL local temporal, sin publicarse. Si lo autorizas, se sube por WebDAV y se puede crear un enlace de Nextcloud mediante OCS, con contraseña, permiso de lectura y caducidad de 1 a 7 días. Es Nextcloud quien aplica caducidad y permisos: no se crea un túnel hacia el equipo. Los enlaces de sesiones anteriores se gestionan desde Nextcloud. El PDF se almacena en claro en el servidor, sujeto a los controles y cifrado en reposo de éste.

Google Drive, OneDrive, S3 y la generación binaria automática de PDF no están conectados. Las operaciones online dependen de CORS y la configuración del servidor.

La ayuda contextual del diccionario usa botones SVG independientes de las etiquetas de los campos para no interferir con selectores nativos. El diccionario ofrece retorno inmediato al paso o campo desde el que se abrió. El catálogo offline incluye familias adicionales de portátiles y sobremesa, con entrada personalizada si no aparece un modelo.

## Informes y revisión previa

El asistente admite **hora de inicio** y **hora de fin** en formato local de 24 horas, junto a las fechas existentes. Los JSON antiguos que solo contienen fechas siguen siendo válidos y no reciben horarios supuestos. Se valida el orden cronológico, incluidas auditorías realizadas en un mismo día.

La entrega ofrece dos modos: **Generar borrador PDF**, siempre marcado como trabajo no validado, e **Informe definitivo PDF**, que bloquea errores críticos de calidad y exige revisar las advertencias restantes. En el modo definitivo se comprueban referencias a evidencias, controles pendientes, firma y coherencia temporal; los campos vacíos de hora generan avisos de precisión, no errores para los expedientes antiguos. Los informes incluyen índice interno, resumen de cobertura y paginación A4 mejorada. La exportación sigue utilizando el navegador, sin subir documentos a servicios externos.

La opción **Descargar expediente JSON** solicita una descarga local y muestra un aviso de estado; el navegador decide el destino según su configuración. Verifica la presencia del archivo en Descargas. La barra superior utiliza el mismo flujo y no recibe accidentalmente el evento `click` como contenido del expediente. Los borradores reflejan los bloqueos del preflight definitivo y el informe evita duplicar la nota legal final.

### Importar un JSON que ya existe

Al importar una auditoría individual o una copia completa, **Audit Workbench reconoce expedientes existentes por la referencia del informe** (no por el nombre del cliente). Si coincide, muestra un diálogo con dos botones: **Cancelar** (no cambia los registros) o **Sobrescribir** (sustituye íntegramente el expediente existente por el contenido del JSON). Se conservan la identidad interna y fecha de creación del registro; imágenes, firmas, hallazgos, controles y confirmaciones documentales pasan a ser las del archivo importado. Antes de confirmar, **descarga y verifica una copia de la versión local** si necesitas conservarla.

Las copias completas pueden mezclar informes nuevos y ya existentes. El diálogo resume los que se sustituirán y cuántos se crearán; todas las operaciones se guardan en una sola transacción en IndexedDB o una sola escritura en almacenamiento alternativo. Si hay referencias repetidas dentro del JSON, o la biblioteca contiene más de un registro con la misma referencia, la importación se bloquea sin modificar nada. Un JSON individual sin referencia sigue ofreciéndose como **auditoría nueva**. Ningún registro se sobrescribe automáticamente.

## Carga de varias imágenes y cierre con controles pendientes

Puedes seleccionar varias imágenes a la vez tanto en **Hallazgos** como en **Evidencias**. El asistente permite hasta 10 imágenes por registro de evidencia y limita las imágenes incrustadas del expediente a 28 MiB. Las nuevas imágenes se añaden sin sustituir las anteriores. Desde Hallazgos, se reutiliza una evidencia existente creada desde esa ficha para evitar duplicaciones. Se mantienen los enlaces por identificador y el formato JSON v3 anterior; las imágenes extra se guardan en `attachments`.

Los controles **Pendiente** y **No verificado**, y las no conformidades sin hallazgo de seguimiento, generan **avisos** en lugar de impedir la entrega. La revisión final incluye estos avisos en un capítulo de limitaciones y obliga a confirmarlos antes de generar el PDF definitivo. Se siguen bloqueando datos esenciales, inconsistencias de formato, referencias rotas, ausencia de resultados fundamentales, y expedientes sin confirmación documental. La aplicación no marca controles pendientes como conformes.

## Impresión PDF: encabezados limpios y lectura más cómoda

La hoja de impresión A4 ahora reserva **cero margen para los encabezados y pies del navegador** y aplica sus márgenes de lectura dentro de cada página. Así evita el título «Audit Workbench», la dirección local/HTTPS y la fecha incluso cuando el navegador activa sus cabeceras por defecto. Como consecuencia, el PDF no incorpora numeración automática; la portada identifica el documento. Si el navegador o la impresora siguen añadiendo datos propios, abre **Más ajustes → Encabezados y pies de página** y desmárcalo (la configuración nativa tiene la última palabra). Activa «Gráficos de fondo» para reproducir los colores de la portada.

La edición ejecutiva organiza prioridades y próximos pasos por párrafos/números sin repetirlos en la conclusión. La técnica evita repetir en las fichas los identificadores ya mostrados en los encabezados; las fotografías a tamaño completo se presentan en **Registro de evidencias**, mientras cada hallazgo enlaza sus identificadores. Los textos extensos de alcance, metodología y conclusiones se imprimen a ancho completo. Los capítulos sin redes o CVE registrados no se incluyen en el índice ni como páginas vacías. No se alteran el expediente JSON ni los controles documentales.

## Flujo recomendado

1. **Configuración:** registra tu consultora y su equipo de auditores; asigna profesionales al expediente.
2. **Biblioteca:** crea o abre una auditoría, identifica el cliente y delimita alcance, autorizaciones y exclusiones.
3. **Inventario:** documenta hardware, sistemas operativos, redes y software. Usa búsquedas y selectores; se admiten valores personalizados.
4. **Controles:** selecciona plantillas de sistemas, redes, identidad o continuidad. Todos comienzan como *Pendiente* y requieren verificación real.
5. **Hallazgos y evidencias:** registra lo observado, vincula activos y controles, documenta consecuencias, acciones recomendadas y criterios de cierre. Conserva los originales de evidencias y sus huellas SHA-256.
6. **Calidad y entrega:** revisa avisos, prioridades y plan de remediación antes de generar el PDF. Si faltan datos esenciales, el informe se identifica como borrador.
7. **Seguimiento:** registra las correcciones verificadas y emite un informe de reevaluación independiente, con evolución histórica y decisiones pendientes.

### Descubrimiento remoto desde el dispositivo del auditor

**Asistente guiado sin servidor web adicional:** desde la instalación, abre `discovery/iniciar.cmd` en Windows o ejecuta `bash discovery/run.sh` en Linux/macOS. Elige una red autorizada de las sugeridas o introduce su CIDR, selecciona Nmap o ping y confirma escribiendo `AUTORIZO`. La captura se genera como un JSON nuevo para la importación manual en la PWA. Puedes consultar los pasos en [Discovery](discovery/README_ES.md).


El nuevo [motor Discovery](discovery/README_ES.md) permite conectar un portátil a una red privada autorizada, comprobar las herramientas disponibles con `python3 discovery/discover.py doctor` y generar una captura importable con `python3 discovery/discover.py scan --cidr 192.168.10.0/24 --authorized --output captura-lan.json`. Prefiere Nmap y, si no está instalado, utiliza ping nativo de manera limitada. No necesita instalación en los activos auditados. La herramienta no confirma sistemas operativos, vulnerabilidades ni VLAN de forma remota; se revisa todo antes de importar.

### Informes PDF sin pasos innecesarios

En **Informes → Generar informe PDF** aparecen primero dos opciones, **Ejecutivo** y **Técnico**, con un botón directo **Generar borrador PDF** para cada una. Los borradores funcionan incluso cuando faltan comprobaciones para la entrega final y se marcan como **BORRADOR**. El navegador abre su diálogo de impresión; selecciona **Guardar como PDF**. Ninguna de esas operaciones envía datos a servicios externos.

Debajo se muestra un resumen de validaciones pendientes y accesos directos a la revisión de calidad. Solo para una **versión definitiva** es necesario completar los datos obligatorios, confirmar el expediente y aceptar o revisar los avisos. Las conclusiones, la firma, el control documental y las exportaciones secundarias permanecen en paneles desplegables, sin ocultar la generación de borradores.

### Captura asistida de inventario

El indicador inferior del menú informa del estado de red declarado por el navegador (rojo: sin conexión; ámbar: red detectada, no verificada). Su botón de comprobación solo consulta el manifiesto de la propia PWA (verde cuando responde), sin transmitir datos del expediente; **no verifica acceso general a Internet**, y una respuesta servida por una caché o proxy tampoco acredita conectividad externa.

Desde **Hardware, Redes o Software → Captura asistida** puedes importar un archivo CSV o JSON, inspeccionar sus registros localmente, detectar duplicados y seleccionar solo las entradas nuevas. No se sobrescriben datos y se solicita confirmación antes de incorporar elementos al expediente. CSV debe incluir encabezados (coma o punto y coma); JSON admite colecciones `assets`, `networks`, `software` o el formato de captura `audit-workbench-discovery-v1`. Máximo 2 MiB/500 filas. Las entradas importadas quedan pendientes de verificación.

Los recopiladores `collect-local.sh` (Linux/macOS con Python 3) y `collect-local.ps1` (Windows PowerShell) recogen datos básicos **solo del equipo local**. Ejecútalos únicamente con permiso y sin elevar privilegios innecesariamente. Ejemplos: `bash collect-local.sh --output captura.json` o `powershell -File .\\collect-local.ps1 -Output captura.json`. El archivo contiene identificadores de sistema: revísalo y protege su almacenamiento. Recogen también interfaces, discos locales, servicios y un inventario limitado de paquetes o aplicaciones instaladas; no realizan descubrimiento de hosts remotos ni envían datos a terceros. El inventario de servicios no confirma vulnerabilidades, versiones ni exposición.

El **Diccionario técnico** incluye 135 conceptos, búsqueda por sinónimos y, en los términos aplicables, guías de troubleshooting y alternativas de diagnóstico por consola (Windows/PowerShell, Linux, macOS y herramientas especializadas). Los comandos son orientativos y copiables, **nunca se ejecutan desde la PWA**. Muchos requieren permisos específicos o conexión a equipos autorizados; sustituye los destinos de ejemplo, valida la versión de cada herramienta y protege los resultados antes de incorporarlos a una evidencia. La referencia añade nombres extendidos de siglas, estándares ISO/IEC, NIST, IETF/IANA, OWASP y enlaces oficiales que solo necesitan conexión cuando el auditor decide abrirlos. Los iconos Windows, Linux y macOS se incluyen localmente como SVG reutilizables. Las secciones del asistente y los campos donde una aclaración aporta valor incluyen accesos «ⓘ» al diccionario. Se conserva el contexto de navegación y se puede volver directamente al campo de origen; los enlaces se definen por sección para evitar referencias ambiguas.\n\nEl término **Respuesta a incidentes** ofrece una sección desplegable con el recurso público español **INCIBE 017**, la información oficial del servicio y el canal diferenciado de reporte empresarial INCIBE-CERT. Es una referencia opcional, sin avisos globales ni transmisión de datos del expediente. Una observación aislada no acredita una vulnerabilidad.

## Dónde se guardan los datos

Los expedientes se guardan **en el navegador**, preferentemente en **IndexedDB** y con alternativa en `localStorage`. **No** se crean JSON automáticamente en la carpeta de instalación.

**No consideres este almacenamiento una copia de seguridad.** Antes de actualizar o cambiar de dispositivo, entra en **Copias y exportaciones → Descargar backup completo (.json)** y comprueba el archivo descargado.

| Formato | Para qué sirve | Se puede restaurar |
| --- | --- | --- |
| JSON individual | Continuar una auditoría en otro navegador | Sí |
| Backup JSON completo | Resguardar y recuperar todos los expedientes | Sí |
| PDF | Entrega formal de la auditoría o reevaluación | No |
| XLSX | Inventario y seguimiento tabular editable | No |
| CSV | Intercambiar una sección con otras herramientas | No |

Para recuperar un expediente, pulsa **Importar** y selecciona el JSON. Comprueba la información restaurada antes de eliminar copias anteriores. Algunos navegadores permiten guardar copias periódicas en una carpeta autorizada **solo mientras la aplicación está abierta**; no sustituye un sistema externo de backups.

Cambiar la URL, el puerto, el perfil o el navegador puede cambiar el espacio de almacenamiento. Por ejemplo, `localhost` y `127.0.0.1` no comparten necesariamente los mismos expedientes.

## Compatibilidad y trabajo offline

- **Escritorio:** navegadores modernos en Windows, Linux y macOS.
- **Tablet/móvil:** instalación PWA desde HTTPS donde el navegador lo permita; después de almacenar los recursos, puede abrirse sin conexión.
- **Tipografía:** Atkinson Hyperlegible (regular, negrita, cursiva y negrita cursiva) servida localmente.
- **Temas:** claros y oscuros; usa la paleta que facilite tu lectura. El PDF conserva un formato preparado para impresión A4.
- **Operaciones conectadas:** consulta CVE, WebDAV/Nextcloud y herramientas de compartir solo a petición expresa. No se transmiten expedientes automáticamente.

El catálogo de sistemas operativos y modelos es orientativo; **no certifica vigencia de soporte, vulnerabilidad ni conformidad**.

## Seguridad y limitaciones

- El JSON y los PDF pueden contener **información confidencial**, identificadores personales y detalles de infraestructura. Consérvalos en almacenamiento cifrado y compártelos únicamente con destinatarios autorizados.
- Las credenciales WebDAV pueden protegerse con una frase de paso local. **Esto no cifra los expedientes en IndexedDB ni los JSON exportados.**
- Los textos legales son plantillas editables, **no asesoramiento jurídico** ni sustituyen el acuerdo de auditoría o tratamiento de datos.
- Las plantillas de controles no acreditan por sí mismas cumplimiento normativo. Un control sin comprobar no debe presentarse como conforme.
- Los resultados de una auditoría se limitan al alcance, fecha y evidencias efectivamente revisados.

Consulta **[Seguridad y privacidad](SECURITY_ES.md)** y **[Cláusulas modelo (España)](LEGAL_ES.md)**.

## Ayuda e incidencias

| Situación | Qué comprobar |
| --- | --- |
| No aparecen mis auditorías | Verifica la misma URL/origen, navegador y perfil; restaura desde JSON |
| No se carga la interfaz tras actualizar | Fuerza recarga; revisa caché/service worker sin borrar IndexedDB |
| No puedo instalar en tablet | Comprueba HTTPS, manifiesto y compatibilidad del navegador |
| Faltan fuentes o colores | Comprueba `css/`, `fonts/`, rutas y errores CSP en consola |
| PDF incompleto | Revisa **Calidad**, activa impresión de fondos y verifica A4 |

El proceso completo de instalación, actualización y diagnóstico está en **[INSTALLATION.md](INSTALLATION_ES.md)**.

## Organización

```text
audit-workbench/
├── index.html
├── manifest.webmanifest
├── sw.js                  # En raíz: mantiene el alcance offline de la PWA
├── audit-workbench.sh
├── audit-workbench.ps1
├── js/                    # Catálogos, persistencia, relaciones y UI
├── css/                   # Temas, formularios e impresión
├── fonts/                 # Atkinson Hyperlegible local
├── icons/
└── tests/
```

Audit Workbench forma parte de **sysadmin**, un conjunto de herramientas de administración de sistemas. Funciona de manera independiente de los asistentes de Active Directory de la raíz: su papel es registrar y analizar auditorías, no ejecutar tareas de administración o hardening sobre equipos remotos.

## Confirmación documental y rectificaciones excepcionales

Audit Workbench diferencia entre **borrador**, **confirmado** y **rectificación en curso**. El borrador puede editarse y revisarse sin presentarse como aprobado. El preflight definitivo comprueba además responsable auditor, autorización, resumen ejecutivo, identificadores duplicados, referencias de evidencia, validación responsable y otras reglas de coherencia existentes.

En **Informe final**, identifica a la persona responsable y confirma el expediente después de revisar los avisos. La confirmación registra una huella SHA-256 local y una revisión, y deshabilita la edición ordinaria. Para modificar una auditoría confirmada, utiliza **Abrir rectificación excepcional**, identifica al responsable y justifica el motivo. Tras editar, supera las validaciones definitivas y pulsa **Validar cambios y cerrar rectificación**; el historial local registra revisión, motivo, rutas de campos modificados y huellas SHA-256 anterior y posterior. El PDF definitivo exige que el contenido coincida con la huella confirmada. Los expedientes antiguos permanecen como borradores hasta confirmación expresa.

**Alcance de la garantía:** es una protección local del flujo de trabajo, no una firma digital, sello de tiempo confiable, registro inmutable ni firma electrónica regulada. Quien controle el almacenamiento del navegador o un JSON exportado puede modificar o sustituir el historial. Conserva cada versión JSON/PDF aprobada en un repositorio externo con acceso controlado, retención independiente y copias de seguridad. Las correcciones de informes ya entregados deben comunicarse como nueva revisión, no reemplazarse silenciosamente.

## Actualizaciones controladas de la PWA

Cuando Audit Workbench se sirve desde un origen HTTPS o localhost estable, comprueba las actualizaciones al abrir, al recuperar la conexión, cuando vuelve a estar visible y periódicamente mientras está abierto. Una versión preparada se anuncia dentro de la interfaz; **no se activa automáticamente durante la edición de una auditoría**. Pulsa **Guardar y actualizar** para guardar los cambios pendientes, verificar la persistencia local, activar el service worker preparado y recargar la página. Pulsa **Más tarde** para continuar con la versión actual. También puedes usar **Buscar actualización** manualmente. La comprobación no sube datos de las auditorías.

**Primera transición:** las PWA instaladas antes de incorporar este gestor pueden necesitar cerrar todas las pestañas de Audit Workbench y volver a abrir la aplicación una vez para adquirir la nueva interfaz. Actualizar el repositorio no actualiza automáticamente los archivos servidos: también hay que desplegar la versión en el servidor. Con los instaladores de archivos locales, primero actualiza la carpeta instalada. Cierra otras pestañas antes de activar una versión nueva: el service worker afecta a todas las pestañas bajo su ámbito, pero este flujo no las recarga automáticamente. No borres los datos del sitio para forzar actualizaciones, porque pueden contener expedientes. Exporta un backup antes de versiones importantes.

## Protección de disponibilidad offline

El Service Worker instala una copia completa y versionada de los recursos esenciales antes de poder activar una nueva versión. Si falla la instalación, se mantiene la versión activa anterior. La navegación offline recurre a la página inicial almacenada; se conservan la caché actual y una anterior como reserva limitada. El panel **Protección del trabajo offline** comprueba recursos esenciales ausentes, muestra una estimación del espacio, permite solicitar almacenamiento persistente al navegador y reparar explícitamente archivos de caché faltantes cuando el servidor original está disponible. La reparación no envía expedientes ni descarga datos de auditoría.

La persistencia depende del navegador y no sustituye las copias de seguridad. No se puede garantizar un 99,9 % de disponibilidad sin mediciones, ni recuperar datos eliminados por el sistema o usuario. Prueba el arranque de la PWA instalada tras detener el servidor y exporta backups JSON antes de actualizar.

## Informes ejecutivo y técnico

**El mismo expediente genera dos documentos diferenciados sin añadir campos ni duplicar datos.** En **Informes**, elige **Ejecutivo** (riesgos, impacto para la organización, prioridades, responsables y decisiones) o **Técnico** (métodos documentados, hallazgos, controles, inventarios, CVE, evidencias vinculadas y remediación detallada). Cada uno dispone de **Borrador** y **Definitivo** y comparte referencia, revisión confirmada y requisitos de validación. Se mantiene el informe independiente de reevaluación.

El ejecutivo no incluye capturas técnicas ni inventarios completos. El técnico muestra únicamente lo que el auditor ha registrado: no inventa comandos, pruebas de explotación ni verificaciones. Ambos se imprimen localmente como PDF desde el navegador. No cambian los formularios ni el formato JSON del expediente.

## Seguridad Wi-Fi y Ethernet empresarial (2026)

El **Diccionario técnico → Redes** incorpora nueve guías prácticas: arquitectura segura de red empresarial, WPA3-Enterprise, EAP-TLS/RADIUS y validación de certificados, protección de tramas de gestión (PMF), segmentación de invitados/BYOD/IoT, defensas en switches de acceso Ethernet, protección del plano de administración, migración de Wi-Fi heredada y MACsec. Se han ampliado las entradas existentes de VLAN, 802.1X/NAC, WPA2/WPA3, RADIUS y redes de invitados. Cada guía añade justificación, controles de auditoría, enlaces a fuentes oficiales y alternativas de diagnóstico de solo lectura para Windows, Linux y macOS cuando proceda. La PWA no ejecuta comandos. Se distinguen configuraciones recomendadas para nuevas instalaciones de excepciones por compatibilidad, que deben justificarse y autorizarse.

## Asistencia contextual de campos

El asistente reutiliza como **sugerencias editables** los activos, sedes, responsables y valores ya introducidos de gateway, DNS y firewall. En controles y hallazgos, un selector permite vincular el ID de una evidencia existente sin volver a escribirlo. Si varios activos comparten nombre, se proponen identificadores de inventario para reducir la ambigüedad. La revisión de calidad advierte sobre IP de activos repetidas, nombres duplicados, prefijos de red duplicados y puertas de enlace IPv4 fuera de su CIDR. Son avisos, no juicios automáticos de conformidad, y permiten excepciones legítimas. No se transmiten datos, no se sobrescriben valores manuales y se conserva el esquema JSON v3. Una sugerencia no equivale a una observación verificada.

## Identificadores automáticos de solo lectura

Los expedientes nuevos reciben al crearse una referencia estable: `PREFIJO-AAAAMMDD-<24 caracteres hexadecimales>`, generada localmente mediante el generador aleatorio criptográfico del navegador. No cambia al editar el nombre del cliente. Los identificadores de activos (`ACT-...`), controles (`CTRL-...`), hallazgos (`FND-...`) y evidencias (`EVD-...`) se asignan al añadir cada registro y se muestran en solo lectura. Los códigos CVE oficiales siguen siendo editables porque proceden de fuentes externas.

La opción **Duplicar** crea otra referencia de auditoría y devuelve la copia a borrador; las importaciones JSON conservan las referencias históricas. Si una referencia ya existe en la biblioteca local, se rechaza la importación, evitando renumerar documentos entregados o sobrescribir auditorías. Solo se admite el esquema JSON vigente (v3). Se han eliminado migraciones e importaciones de formatos previos al lanzamiento. Estos identificadores no constituyen firmas digitales ni acreditan la identidad de quien audita; para conciliar registros entre dispositivos aislados es necesaria una custodia común.

## Contrato JSON vigente (limpieza previa al lanzamiento)

Audit Workbench admite **únicamente schemaVersion 3** para el JSON de auditorías individuales. Las copias de biblioteca utilizan `kind: "audit-workbench-library"` con `schemaVersion: 3`; los perfiles de consultora utilizan `kind: "audit-workbench-consultancy"` con `schemaVersion: 3`. Ya no se aceptan respaldos/perfiles anteriores al lanzamiento ni se recuperan expedientes desde claves antiguas v2. El contenedor de copia cifrada conserva su formato criptográfico independiente: no es otro esquema de auditoría. Se mantienen IndexedDB y el almacenamiento alternativo local para mayor resiliencia. Antes de adoptar esta versión, exporta cualquier dato de prueba que quieras conservar y considéralo descartable si no se ajusta al esquema vigente.
