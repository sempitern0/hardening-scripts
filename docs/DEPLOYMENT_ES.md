# Lanzamiento y despliegue en los equipos objetivo

[English](DEPLOYMENT.md) · [Inicio](../README_ES.md) · [Referencia operativa](OPERATIONS_ES.md)

Los seis asistentes de la raíz son autónomos: se pueden copiar individualmente a un equipo sin clonar el repositorio ni instalar Python. RabbitMole es un proyecto separado; estos asistentes no necesitan su servidor, navegador ni PWA.

## Elegir el equipo y el asistente

| Equipo objetivo | Archivo | Comprobación sin elevación | Siguiente paso, elevado |
|---|---|---|---|
| DC Samba Debian/Ubuntu | `debian-ad-assistant.sh` | `bash ./debian-ad-assistant.sh --preflight` | `sudo bash ./debian-ad-assistant.sh --audit` |
| DC Samba Rocky/AlmaLinux | `rhel-ad-assistant.sh` | `bash ./rhel-ad-assistant.sh --preflight` | `sudo bash ./rhel-ad-assistant.sh --audit` |
| Cliente Linux de AD | `linux-ad-client-assistant.sh` | `bash ./linux-ad-client-assistant.sh --preflight` | `sudo bash ./linux-ad-client-assistant.sh --audit` |
| Cliente Linux con identidad RHEL | `rhel-ad-client-assistant.sh` | `bash ./rhel-ad-client-assistant.sh --preflight` | `sudo bash ./rhel-ad-client-assistant.sh --audit` |
| Windows Server / AD DS | `windows-ad-assistant.ps1` | `powershell.exe -NoProfile -File .\windows-ad-assistant.ps1 -Mode Preflight` | `powershell.exe -NoProfile -File .\windows-ad-assistant.ps1 -Mode Audit` |
| Cliente Windows / servidor miembro | `windows-ad-client-assistant.ps1` | `powershell.exe -NoProfile -File .\windows-ad-client-assistant.ps1 -Mode Preflight` | `powershell.exe -NoProfile -File .\windows-ad-client-assistant.ps1 -Mode Audit` |

Ejecuta el asistente en el sistema que va a administrar. Para un cliente, no uses el asistente del DC. En Linux se necesitan Bash y un host systemd para los ciclos de vida automatizados; un contenedor sin systemd no es un sustituto del host. Windows requiere Windows PowerShell 5.1 o PowerShell 7 y los componentes del sistema que use cada operación. El aprovisionamiento Samba AD DC en RHEL mantiene su bloqueo de soporte y confirmación explícita.

`Preflight` comprueba plataforma y disponibilidad de comandos locales, sin instalar paquetes, modificar configuración, crear logs ni solicitar credenciales. Devuelve **0** si no detecta bloqueos y **1** si los hay. Las advertencias de dependencias de rol no cambian ese resultado: deben revisarse antes de utilizar esas funciones. No prueba DNS, pertenencia al dominio ni permisos AD. `Audit` profundiza en el estado real y sí puede crear logs/informes y realizar consultas de red.

## Descargar una revisión concreta

En GitHub, abre **Actions → sysadmin standalone verification**, elige una ejecución correcta del commit que vas a aprobar y descarga su artefacto `sysadmin-<SHA>`. Contiene un ZIP con scripts, documentación, `release.json` y `SHA256SUMS`. Solo se genera tras pasar los controles Linux y Windows. Extrae el ZIP en una carpeta dedicada, revisa el commit y conserva el paquete junto con la evidencia del cambio.

En Linux, valida los archivos extraídos:

```bash
sha256sum -c SHA256SUMS
bash -n ./linux-ad-client-assistant.sh
bash ./linux-ad-client-assistant.sh --preflight
```

En Windows, valida el archivo que vayas a ejecutar:

```powershell
$file = 'windows-ad-client-assistant.ps1'
$line = Get-Content .\SHA256SUMS | Where-Object { $_.EndsWith("  $file") }
if (@($line).Count -ne 1) { throw 'No hay un checksum único para el script' }
$expected = $line.Substring(0,64)
if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $expected) {
    throw 'El archivo no coincide con el paquete'
}
$tokens = $null; $errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path $file).Path, [ref]$tokens, [ref]$errors)
if ($errors) { $errors | Format-List; throw 'Errores de sintaxis' }
powershell.exe -NoProfile -File .\windows-ad-client-assistant.ps1 -Mode Preflight
```

Los hashes detectan corrupción o diferencias respecto al paquete; no sustituyen la confianza en su origen ni una firma. Respeta la política de firma/ejecución de tu organización: la guía no requiere cambiarla ni usar `ExecutionPolicy Bypass`.

Para descargar solo un script desde una revisión aprobada, sustituye el SHA completo de 40 caracteres:

```bash
revision='REEMPLAZAR_POR_SHA_APROBADO_DE_40_CARACTERES'
curl --fail --show-error --location --proto '=https' \
  "https://raw.githubusercontent.com/sempitern0/sysadmin/${revision}/linux-ad-client-assistant.sh" \
  --output linux-ad-client-assistant.sh
# Revisa el archivo y contrasta su hash con tu referencia aprobada antes de ejecutarlo.
bash -n ./linux-ad-client-assistant.sh
bash ./linux-ad-client-assistant.sh --preflight
```

No uses una URL de `main` como identificador de una versión aprobada: puede cambiar entre equipos. Descarga primero a un archivo; no canalices la respuesta de red directamente a Bash o `Invoke-Expression`.

## Ejecutar localmente o por SSH

Tras revisar el resultado de la precomprobación, ejecuta la auditoría desde una consola administrativa. Para abrir después el menú:

```bash
sudo bash ./linux-ad-client-assistant.sh --manage --lang es
```

Para un host remoto, copia la revisión verificada a una ruta conocida del usuario autorizado y conserva una terminal para menús, sudo y credenciales:

```bash
scp ./linux-ad-client-assistant.sh operador@cliente:/home/operador/linux-ad-client-assistant.sh
ssh -t operador@cliente 'bash /home/operador/linux-ad-client-assistant.sh --preflight'
ssh -t operador@cliente 'sudo bash /home/operador/linux-ad-client-assistant.sh --audit'
# Solo después de revisar la auditoría:
ssh -t operador@cliente 'sudo bash /home/operador/linux-ad-client-assistant.sh --manage --lang es'
```

Adapta usuario y rutas. No incluyas contraseñas en los comandos ni desactives la comprobación de la clave SSH. Los modos interactivos ahora rechazan la falta de terminal antes de inicializar el estado administrativo.

En Windows, copia el script a una carpeta de herramientas administrada y abre Windows PowerShell como administrador:

```powershell
powershell.exe -NoProfile -File C:\AdminTools\windows-ad-client-assistant.ps1 -Mode Audit -Language es
powershell.exe -NoProfile -File C:\AdminTools\windows-ad-client-assistant.ps1 -Mode Interactive -Language es
```

Los menús y diálogos de credenciales necesitan una sesión interactiva. Para distribución masiva, usa tu herramienta existente (por ejemplo, Ansible o tu gestor de endpoints) para **copiar** la revisión verificada y ejecutar `Preflight`; no automatices `Join`, `Reset`, hardening o reparaciones como si fueran auditorías. Conserva salida y código de retorno de cada equipo. Los asistentes no configuran WinRM ni despliegan agentes por ejecutar `Preflight`.

## Tareas programadas y actualización

Usa rutas absolutas estables y una cuenta con los permisos necesarios. Los registros automáticos incorporados referencian la ruta del script: no los crees desde Descargas o una carpeta temporal. Revisa tareas, servicios y rutas antes de moverlo. No ejecutes operaciones de pertenencia al dominio o configuración simultáneamente sobre el mismo host.

En el asistente Windows Server, los modos `IDSReport`, `IDSResponseCleanup` e `IDSAwarenessCheck` propagan ahora los errores capturados al proceso; revisa el resultado de la tarea además de sus logs. Esto no convierte todos los hallazgos de auditoría en códigos de error: consulta siempre el informe.

Para actualizar: conserva la versión anterior, revisa el diff y el resultado CI del nuevo commit, copia el nuevo archivo en una ventana de mantenimiento y repite preflight → auditoría. No elimines estado, snapshots o claves locales como método de actualización.

## Aceptación antes de producción

1. Prueba en una VM desechable de la misma familia/versión que el destino.
2. Ejecuta preflight y auditoría; revisa DNS, hora, permisos y acceso administrativo alternativo.
3. Prueba el cambio previsto con un dominio de laboratorio y credenciales de prueba.
4. Reinicia y valida DNS, autenticación, servicios y acceso remoto.
5. Ensaya recuperación desde el snapshot/backup; conserva resultados y versión del script.

CI valida análisis estático y comportamientos aislados, no provisiona un dominio ni certifica restauración, hardening o conectividad del entorno real. Consulta [mantenimiento y cobertura](MAINTENANCE.md).
