# Audit Workbench

**Asistente de auditorías informáticas offline** para inventariar activos, evaluar controles, documentar hallazgos y evidencias, planificar correcciones y preparar informes para clientes.

Funciona en el navegador, sin servicios externos obligatorios. No escanea redes ni modifica equipos.

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

Abre `http://127.0.0.1:8765`. Para instalar la PWA en tablet o móvil, consulta **[Instalación por dispositivo](INSTALLATION.md)**: la primera carga requiere HTTPS y un navegador compatible.

## Flujo recomendado

1. **Configuración:** registra tu consultora y su equipo de auditores; asigna profesionales al expediente.
2. **Biblioteca:** crea o abre una auditoría, identifica el cliente y delimita alcance, autorizaciones y exclusiones.
3. **Inventario:** documenta hardware, sistemas operativos, redes y software. Usa búsquedas y selectores; se admiten valores personalizados.
4. **Controles:** selecciona plantillas de sistemas, redes, identidad o continuidad. Todos comienzan como *Pendiente* y requieren verificación real.
5. **Hallazgos y evidencias:** registra lo observado, vincula activos y controles, documenta consecuencias, acciones recomendadas y criterios de cierre. Conserva los originales de evidencias y sus huellas SHA-256.
6. **Calidad y entrega:** revisa avisos, prioridades y plan de remediación antes de generar el PDF. Si faltan datos esenciales, el informe se identifica como borrador.
7. **Seguimiento:** registra las correcciones verificadas y emite un informe de reevaluación independiente, con evolución histórica y decisiones pendientes.

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

Consulta **[Seguridad y privacidad](SECURITY.md)** y **[Cláusulas modelo (España)](LEGAL.md)**.

## Ayuda e incidencias

| Situación | Qué comprobar |
| --- | --- |
| No aparecen mis auditorías | Verifica la misma URL/origen, navegador y perfil; restaura desde JSON |
| No se carga la interfaz tras actualizar | Fuerza recarga; revisa caché/service worker sin borrar IndexedDB |
| No puedo instalar en tablet | Comprueba HTTPS, manifiesto y compatibilidad del navegador |
| Faltan fuentes o colores | Comprueba `css/`, `fonts/`, rutas y errores CSP en consola |
| PDF incompleto | Revisa **Calidad**, activa impresión de fondos y verifica A4 |

El proceso completo de instalación, actualización y diagnóstico está en **[INSTALLATION.md](INSTALLATION.md)**.

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

Audit Workbench es independiente de los scripts de hardening situados en la raíz de `sysadmin`.
