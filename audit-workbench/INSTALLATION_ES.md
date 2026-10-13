# Instalación y actualización de Audit Workbench

Esta guía está dirigida a auditores y administradores que necesitan usar la aplicación en escritorio, tablet o móvil, con conectividad limitada.

## Antes de empezar

- Elige **una URL estable** para tus expedientes; el navegador asocia IndexedDB al origen. `http://localhost:8765` y `http://127.0.0.1:8765` tienen almacenes distintos.
- Exporta un **backup JSON completo** antes de actualizar, reinstalar o modificar el perfil del navegador.
- Un PDF no permite restaurar una auditoría. CSV y XLSX tampoco.
- El proyecto se distribuye sin cuentas, telemetría ni servicios online obligatorios.

## Windows

Desde una copia del repositorio:

```powershell
cd audit-workbench
.\audit-workbench.ps1
```

Para actualizar los archivos instalados:

```powershell
.\audit-workbench.ps1 -Update
```

También puedes servir los archivos con Python desde la carpeta `audit-workbench/`:

```powershell
py -m http.server 8765 --bind 127.0.0.1
```

Abre `http://127.0.0.1:8765` en tu navegador. Si trabajaste antes con otra dirección, importa el backup JSON desde ese perfil.

## Linux y macOS

Desde el repositorio:

```bash
cd audit-workbench
bash ./audit-workbench.sh
```

Para actualizar:

```bash
bash ./audit-workbench.sh --update
```

Servidor local opcional:

```bash
python3 -m http.server 8765 --bind 127.0.0.1
```

Para instalar sin abrir navegador, añade `--no-open`. Para elegir carpeta de destino usa `--dir RUTA`. Ambas instalaciones incluyen los módulos `js/`, `css/`, `fonts/` y `icons/`.

## Tablet y móvil: instalación PWA

La instalación desde navegador requiere, en general, **una primera carga HTTPS** desde un servidor fiable y accesible al dispositivo. Un ZIP por sí mismo **no es un APK o IPA instalable**.

1. Publica **solo los archivos estáticos** de `audit-workbench/` en una intranet o alojamiento HTTPS con certificado válido. Nunca publiques JSON, PDFs o evidencias confidenciales.
2. Accede desde Chrome/Edge (Android) o Safari (iPhone/iPad) y espera a que cargue la aplicación.
3. En Android usa la opción **Instalar aplicación** o **Añadir a pantalla de inicio**, si se ofrece. En iOS/iPadOS utiliza **Compartir → Añadir a pantalla de inicio**.
4. Abre la aplicación desde su icono y comprueba que funciona sin conexión antes de llevarla a una red aislada.
5. Exporta backups JSON regularmente a una ubicación protegida. En tablets, las APIs para elegir carpetas pueden no estar disponibles.

Las opciones exactas dependen de navegador y versión del sistema; la PWA y sus datos siguen sujetos a las políticas de almacenamiento del dispositivo.

## Uso sin servidor

Puedes abrir `index.html` como archivo local para un uso básico, pero `file://` no ofrece las mismas garantías de almacenamiento y **no permite instalar la PWA mediante service worker**. Para trabajo continuado utiliza un origen estable.

## Migrar o recuperar expedientes

1. En el equipo anterior entra en **Copias y exportaciones → Descargar backup completo (.json)**.
2. Copia el JSON utilizando un canal aprobado y protegido por cifrado.
3. Abre Audit Workbench en el nuevo dispositivo, pulsa **Importar** y elige el archivo.
4. Comprueba cliente, inventarios, hallazgos, evidencias e informe generado. No elimines el original hasta verificar la restauración.

Las copias automáticas a carpeta solo funcionan en navegadores compatibles, con permiso activo y la aplicación abierta. No constituyen sincronización entre dispositivos.

## Actualizaciones de la PWA

La caché de la aplicación se actualiza por versiones y **no almacena los expedientes**. Después de actualizar el código, cierra y vuelve a abrir la aplicación y recarga la página. Si continúas viendo recursos anteriores, revisa **Herramientas de desarrollo → Application → Service Workers**.

**No utilices «Clear site data» sin disponer de un backup comprobado:** podrías borrar los expedientes locales.

## Resolución de problemas

| Problema | Diagnóstico y solución |
| --- | --- |
| El buscador aparece oscuro en tema claro | Actualiza la versión, comprueba `css/contrast.css` y que el service worker haya renovado los estilos |
| Las fuentes Atkinson no se muestran | Comprueba `css/atkinson.css`, los cuatro WOFF2 en `fonts/` y que no haya errores CSP |
| Los expedientes han desaparecido | Verifica origen, puerto, perfil, modo privado y restauración JSON |
| La PWA no se ofrece como instalable | Comprueba HTTPS, manifiesto, service worker y compatibilidad |
| PDF con saltos o sin colores | Selecciona A4; revisa vista previa y opciones de imprimir fondos |
| Falla una conexión WebDAV | Confirma HTTPS, permisos mínimos, contraseña de aplicación y configuración del servidor |
| Un sistema operativo/modelo no aparece | Escribe el valor personalizado; los catálogos no son listas exhaustivas |

## Descarga puntual de instaladores

Para comprobarlos antes de ejecutarlos:

```bash
curl -fL -o audit-workbench.sh 'https://raw.githubusercontent.com/sempitern0/sysadmin/main/audit-workbench/audit-workbench.sh'
less audit-workbench.sh
bash ./audit-workbench.sh
```

```powershell
Invoke-WebRequest 'https://raw.githubusercontent.com/sempitern0/sysadmin/main/audit-workbench/audit-workbench.ps1' -OutFile audit-workbench.ps1
Get-Content .\audit-workbench.ps1
.\audit-workbench.ps1
```

Evita ejecutar directamente scripts de Internet mediante tuberías sin inspeccionarlos. Los instaladores realizan la descarga inicial; el trabajo ordinario en la aplicación sigue siendo offline.

Para manejo de información sensible consulta [SECURITY.md](SECURITY.md). Para funciones del asistente consulta [README.md](README.md).
