# Audit Workbench — auditorías informáticas sin Internet

Interfaz documental privada para realizar auditorías de **sistemas, hardware, software, redes y seguridad**, anotar verificaciones y evidencias, y preparar el informe PDF de entrega. No cambia la configuración de los equipos auditados y es independiente de los asistentes de Active Directory.

La primera instalación necesita descargar tres archivos de aplicación; una vez guardados en el equipo, **el navegador no necesita conexión**, CDN, servidor, extensiones ni acceso al repositorio. Desde un clon de Git completo, los lanzadores copian los archivos locales sin usar la red.

## Puesta en marcha

Clona el repositorio y ejecuta uno de los lanzadores de la **raíz**:

```bash
bash ./audit-workbench.sh
# Para instalar sin abrir automáticamente el navegador:
bash ./audit-workbench.sh --no-open
# Cambiar destino / actualizar recursos:
bash ./audit-workbench.sh --dir "$HOME/Auditorias/Workbench" --update
```

```powershell
.\audit-workbench.ps1
.\audit-workbench.ps1 -NoOpen
.\audit-workbench.ps1 -OutputDirectory "$HOME\Auditorias\Workbench" -Update
```

### Instalación rápida sin clonar

Primero descarga el lanzador desde una rama/revisión conocida y **revísalo antes de ejecutarlo**, especialmente en equipos de clientes:

```bash
curl -fL -o audit-workbench.sh https://raw.githubusercontent.com/sempitern0/hardening-scripts/feature/offline-audit-workbench/audit-workbench.sh
bash ./audit-workbench.sh --ref feature/offline-audit-workbench
```

```powershell
Invoke-WebRequest 'https://raw.githubusercontent.com/sempitern0/hardening-scripts/feature/offline-audit-workbench/audit-workbench.ps1' -OutFile '.\audit-workbench.ps1'
.\audit-workbench.ps1 -Ref 'feature/offline-audit-workbench'
```

Tras fusionar la rama, omite `--ref` / `-Ref` para utilizar `main`. También puedes abrir directamente `audit-workbench/index.html` después de clonar; debe permanecer junto a `styles.css` y `app.js`.

Si cambias el nombre del repositorio, usa `AUDIT_WORKBENCH_REPO=usuario/nuevo-repo` en Bash o `-Repository 'usuario/nuevo-repo'` en PowerShell. Los lanzadores nunca ejecutan los archivos descargados como código de shell: los guardan para el navegador.

## Flujo de auditoría

1. **Cliente y alcance:** contexto, autorización, fechas, exclusions, metodología y alcance real de las pruebas.
2. **Hardware, redes y software:** inventario técnico por activo/servicio.
3. **Controles:** resultado explícito para cada verificación; "No verificado" no cuenta como conforme.
4. **Hallazgos:** ID, severidad, probabilidad, impacto, activos, descripción, evidencias, remediación, responsable y fecha objetivo.
5. **Evidencias:** identificador, fuente, referencia SHA-256 opcional, custodia e imágenes adjuntas opcionales.
6. **Informe final:** resumen ejecutivo, puntos fuertes/débiles, valoración, plan de mejora, acciones posteriores y firma.
7. **Exporta el expediente JSON** y pulsa **Generar PDF**; en el diálogo del navegador selecciona **Guardar como PDF** y verifica el PDF antes de entregarlo.

El PDF resultante incorpora portada, clasificación de confidencialidad, alcance y limitaciones, inventarios, controles, resumen de severidades, fichas técnicas de hallazgos, imágenes de evidencia y acciones de remediación. La escala CVSS, cuando se introduce, es **un valor documentado manualmente**, no una puntuación calculada por la app.

El esquema JSON editable es `schemaVersion: 2`. **Cada cliente debe tener un JSON distinto**; al importar un archivo se sustituye el expediente activo previa confirmación. El autoguardado del navegador es una comodidad, no una garantía de persistencia ni una copia de seguridad.

## Seguridad y limitaciones

- Sin solicitudes externas, telemetría, librerías descargadas o ejecución remota durante el uso de la interfaz.
- No ejecuta escaneos ni procedimientos de pentesting. Los hallazgos se documentan tras las verificaciones autorizadas por un auditor.
- No introducir contraseñas, claves, hashes de autenticación o datos personales innecesarios. Los expedientes e informes pueden revelar topología e información de riesgo: **cifrarlos y limitar accesos**.
- Las capturas se redimensionan en el propio navegador (máximo 5 MiB por archivo y aproximadamente 1,4 MB de datos JPEG exportados por imagen). Conserva evidencias originales por separado para mantener integridad y cadena de custodia.
- Algunos entornos corporativos bloquean los archivos `file://` o su almacenamiento local. Si sucede, abre el proyecto con un servidor **solo en loopback** provisto por tu entorno, sin publicar datos en la red, y sigue exportando JSON periódicamente.
- La exportación PDF usa el motor de impresión del navegador: depende de la configuración local. Activa «gráficos de fondo» si deseas conservar los colores.
- El informe no acredita por sí mismo conformidad legal, certificaciones o ejecución de pruebas.

## Referencia editorial

La estructura editorial está inspirada en las categorías del recurso público aportado por el usuario *RG001 Informe de resultados de la auditoría de seguridad*: confidencialidad, alcance y exclusiones, metodología y limitaciones, resumen ejecutivo, severidad, factores de riesgo, evidencias, hallazgos técnicos y remediación. No incorpora contenido, marcas, datos ni capturas de dicho documento.

## Comprobaciones

```bash
bash -n ./audit-workbench.sh
node --check ./audit-workbench/app.js
bash ./audit-workbench.sh --dir "$(mktemp -d)" --no-open
```

La app no requiere Node ni Python para funcionar. Son útiles únicamente para validar el código durante el desarrollo.
