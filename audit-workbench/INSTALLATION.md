# Instalación y uso en PC, tablet y móvil

Audit Workbench se puede ejecutar **totalmente sin Internet después de obtener sus archivos**. La instalación como PWA depende del dispositivo, sistema, navegador y origen desde el que se sirve. No requiere API, autenticación, dominio corporativo ni base de datos.

## Resumen de compatibilidad

| Plataforma | Uso local | Instalación tipo app | Consideraciones |
|---|---|---|---|
| Windows 10/11 + Edge/Chrome/Firefox | Abrir `index.html` sin red | Edge/Chrome por HTTPS o `http://localhost` | La opción PWA depende de los navegadores compatibles; Firefox puede abrir la web sin modo PWA. |
| Linux + Chromium/Chrome/Firefox | Abrir `index.html` sin red | Chromium/Chrome por HTTPS o `http://localhost` | Puede alojarse localmente en un equipo del auditor; no hace falta Docker. |
| macOS + Safari/Chrome/Edge | Abrir `index.html` sin red | Depende de versión de macOS/navegador; web apps desde Safari o Chrome/Edge | Conservar mismo perfil/origen para acceder a expedientes. |
| Android + Chrome/Edge | HTTPS | Menú del navegador → Instalar aplicación / Añadir a inicio | Después de la primera instalación, service worker almacena *solo* los recursos estáticos. |
| iPadOS / iOS + Safari | HTTPS | Compartir → Añadir a pantalla de inicio | Requiere HTTPS y versión compatible; el comportamiento y límites de almacenamiento pueden variar. |
| Chromebook | HTTPS o archivos locales | Chrome → Instalar | No asumas que los archivos del almacenamiento del dispositivo comparten origen con el PWA. |
| Dispositivos gestionados/MDM | Depende de política | Depende de MDM/navegador | El administrador puede impedir instalar PWA, guardar archivos o usar IndexedDB. |

## Método A: ZIP o clone, sin servidor

1. Descarga el proyecto mientras tienes acceso a Internet (o transfiérelo por USB de confianza).
2. Extrae/abre `audit-workbench/index.html` o ejecuta `audit-workbench.sh` / `audit-workbench.ps1` desde la carpeta extraída.
3. Trabaja sin conexión; para entregar el PDF usa el diálogo de impresión del navegador.
4. El autoguardado permanece vinculado al navegador/origen. **Exporta JSON** al cambiar de equipo, perfil, origen o navegador.

**Limitación:** `file://` no soporta service workers ni instalación PWA estándar. No todos los navegadores permiten persistencia fiable bajo `file://`; prueba una auditoría y exporta una copia. Para mayor consistencia, usa `http://localhost` o HTTPS.

## Método B: Windows o Linux/macOS con servidor local

Con Python 3 instalado, desde la carpeta `audit-workbench/`:

```bash
python3 -m http.server 8765 --bind 127.0.0.1
# Windows: py -m http.server 8765 --bind 127.0.0.1
```

Abre `http://127.0.0.1:8765/` **en ese mismo PC**. El origen localhost se considera seguro para service workers y puede permitir instalar la PWA según el navegador. Para detener el servidor, `Ctrl+C`; una PWA instalada continuará con sus archivos en caché una vez instalados correctamente.

**No abras el servidor local en todas las interfaces** si contiene archivos de auditoría. El servidor simple de Python es solo para archivos estáticos, no un servicio endurecido ni un mecanismo de compartición con clientes.

## Método C: instalación PWA en tablet y móvil (HTTPS)

1. Publica **únicamente los archivos estáticos de `audit-workbench/`** (nunca un backup JSON o PDF confidencial) en un origen HTTPS con certificado válido, administrado por ti. Evita CDN de terceros, analítica y logs con información sensible. También puedes distribuir desde una intranet HTTPS validada por la tablet.
2. Conecta el dispositivo una primera vez y abre la URL en Safari (iPad/iPhone) o Chrome/Edge (Android).
3. Usa el menú **Añadir a pantalla de inicio / Instalar aplicación**. Si no aparece, la plataforma o la política corporativa puede impedir la instalación; el uso en pestaña sigue siendo válido.
4. Abre la app **una vez online y espera la carga completa** para que el service worker guarde la aplicación; luego activa modo avión y prueba apertura, edición y generación de PDF (el diálogo de impresión puede depender del SO).
5. Guarda un backup JSON en almacenamiento cifrado y verifica que puedes importarlo en otro dispositivo.

**Paquete listo para PWA:** el ZIP de distribución incluye `index.html`, CSS/JS, `manifest.webmanifest`, `sw.js` y los iconos SVG y PNG. No hay que instalar Python ni Node en Android/iPadOS: solo servir el contenido bajo HTTPS durante la primera instalación. Al usar **Añadir a pantalla de inicio / Instalar** se crea un icono propio, con el dragón, desde el que se abre la app sin conexión después del primer cacheo. Esto no es un APK/IPA firmado: instalar un ZIP o abrir un HTML con doble toque **no instala** una app nativa. Para requerir un APK/IPA independiente será necesario un wrapper firmado (por ejemplo Capacitor o TWA) y las herramientas de construcción y distribución de cada plataforma.

**No basta con compartir por HTTP una IP de la LAN** (`http://192.168.x.x:8765`), porque no es un contexto seguro para PWA. Si usas un host local accesible desde tablet, proporciona HTTPS y un certificado que el dispositivo confíe. No uses certificados ignorando alertas TLS en auditorías reales.

## Migrar de ordenador a tablet

1. PC: **Copias y exportaciones → Descargar backup completo (.json)** o **Guardar JSON** para un expediente.
2. Transfiere el archivo por USB, disco cifrado o el canal cifrado expresamente autorizado por el cliente.
3. Tablet: abre Audit Workbench en el origen PWA, pulsa **Importar** y selecciona el archivo JSON desde **Archivos** (iOS/iPadOS) o un gestor de archivos (Android).
4. Comprueba biblioteca, capturas y datos, y genera un PDF de control antes de continuar la auditoría.
5. Elimina las copias temporales solo según la política de retención, y mantén un backup seguro.

## Actualización de la aplicación

Ejecuta el lanzador con `--update` (Bash) o `-Update` (PowerShell) desde una carpeta de origen confiable. Conserva los JSON exportados; estos son independientes del código. En PWA HTTPS, el navegador puede actualizar automáticamente los archivos de la shell; exporta tu backup **antes** de cambiar de versión/origen. El service worker solo almacena la aplicación y no exportaciones o expedientes.

Para un futuro cambio de `hardening-scripts` a `sysadmin-tools`, adapta la URL y usa `AUDIT_WORKBENCH_REPO=usuario/nuevo-repo` / `-Repository usuario/nuevo-repo` mientras dure la transición. Los datos de navegador no migran entre **orígenes HTTPS diferentes**; exporta/importa.

## Resolución de incidencias

- **No se instala:** comprueba HTTPS o localhost, navegador compatible, manifiesto, iconos y políticas MDM.
- **No abre sin red:** comprueba que se abrió online una vez tras la instalación y que el navegador no eliminó el almacenamiento del sitio.
- **Faltan auditorías:** revisa el origen, perfil y navegador; restaura un backup JSON. No se puede recuperar lo que nunca se exportó si el almacenamiento local ha sido eliminado.
- **PDF sin colores:** activa gráficos de fondo; selecciona la paleta **antes** de imprimir. Las páginas técnicas mantienen fondo blanco para legibilidad, mientras la portada usa un fondo de color distinto por tema (incluidos los oscuros).
- **Faltan capturas:** verifica que las imágenes estaban incrustadas en el JSON importado y que el navegador disponía de almacenamiento suficiente.

## Actualización v6 y navegación con tablet

El menú lateral contiene Biblioteca, Configuración y Conexiones. Dentro de cada auditoría navega por **Anterior/Siguiente** y **Ir al paso**; la referencia del informe está arriba, no en el lateral. En tablets el menú principal se convierte en barra horizontal para liberar espacio.

En el primer arranque, entra en **Configuración** y guarda los datos de la consultora y el prefijo de informes. Exporta el perfil junto con la biblioteca cuando cambies de dispositivo: la numeración por cliente depende de los contadores guardados en ese perfil.

El CSS `fonts/atkinson.css` carga automáticamente las cuatro variantes locales de Atkinson Hyperlegible (Regular, Bold, Italic y BoldItalic), disponibles en el repositorio. Una distribución sin esos archivos utiliza la tipografía de reserva del sistema.

Después de actualizar por `git pull` o por los lanzadores, cierra pestañas previas y vuelve a abrir la PWA para que el service worker pase de `shell-v5` a `shell-v6`. Antes de actualizar, exporta el backup JSON desde la Biblioteca y el perfil de consultora desde Configuración. La v6 utiliza un nuevo esquema del expediente (3) y está orientada a desarrollo; no se garantiza la importación de todos los esquemas anteriores.


## Fuente Atkinson Hyperlegible

La aplicación incorpora el CSS local de Atkinson con Regular, Bold, Italic y BoldItalic. Si instalas desde GitHub, las cuatro variantes WOFF2 deben estar dentro de `audit-workbench/fonts/`. Si las omites en una distribución reducida, la aplicación conserva su funcionalidad con la fuente del sistema.

## Equipo de auditores

En **Configuración → Equipo de auditores** registra nombre, función, correo profesional y teléfono de cada miembro. En cada expediente abre **Cliente y alcance → Profesionales asignados** y marca todas las personas participantes. Guarda un JSON de cada auditoría antes de cambiar de equipo; ese JSON conserva la autoría incluida en el informe.

## Gestor de copias y formatos para el cliente

En el menú principal, **Copias y exportaciones** centraliza las descargas JSON, la restauración y la exportación XLSX/CSV. El JSON completo puede recuperarse en otro equipo mediante **Importar**. Excel y CSV son formatos de entrega editables y **no sirven para restaurar** el expediente.

Si aparece **Seleccionar carpeta**, puedes autorizar una carpeta local para guardar copias JSON con nombres fechados. La opción automática prueba a guardar cada 30 minutos con cambios, pero únicamente mientras la aplicación esté abierta y el navegador conserve acceso de escritura; no es un backup en segundo plano del sistema operativo. No se recomienda depender de esta función como único mecanismo de recuperación.

Los JSON, CSV, XLSX y PDF pueden incluir datos de carácter reservado. Usa un volumen cifrado, acceso restringido y las políticas de conservación del contrato.
