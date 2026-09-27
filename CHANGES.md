# Auditoría técnica — `sempitern0/hardening-scripts`

Fecha de revisión: 2026-09-27  
Repositorio revisado: `sempitern0/hardening-scripts` (`main`)  
Archivos principales revisados:

- `debian-ad-assistant.sh` — v2.1.0
- `pymes-windows-server-security.ps1` — v0.2.0
- `README.md`

## 1. Resumen

El repositorio ya tiene buenas bases de ingeniería para scripts one-shot:

- auditoría previa;
- confirmación antes de cambios;
- `set -Eeuo pipefail` en Bash;
- `Set-StrictMode -Version Latest` en PowerShell;
- logs e informes;
- copias de ficheros antes de varias modificaciones;
- validación posterior;
- consciencia del rol Domain Controller;
- uso de `/dev/tty` para mantener interacción con `curl | sudo bash`;
- rechazo explícito del reprovisionado silencioso de un AD existente.

El principal problema no es la falta de controles sino que el flujo actual está demasiado acoplado a
**“servidor nuevo -> bootstrap completo”**. En un servidor ya instalado, el Linux assistant pasa
rápidamente de “no destruir” a “solo validar”, sin una zona intermedia de mantenimiento controlado.

La propuesta vNext separa cinco conceptos:

1. `audit`: observar sin modificar.
2. `validate`: comprobar salud funcional.
3. `bootstrap`: crear un DC nuevo.
4. `manage`: modificar de forma idempotente un DC existente.
5. `backup/repair`: operaciones explícitas, trazables y con salvaguardas.

No se debe afirmar “CIS compliant” porque un script compruebe una selección de reglas. CIS Debian 13,
Ubuntu 26.04 y Windows Server contienen muchas más recomendaciones y perfiles. La etiqueta correcta es
**CIS-oriented / baseline-aware**, salvo que se ejecute una herramienta oficial/validada contra el
benchmark concreto y se conserve su evidencia.

---

# 2. Hallazgos Linux

## Críticos / altos

### LNX-001 — UFW se configura antes de instalar los paquetes

En `main()` el orden actual es:

1. `configure_identity`
2. `configure_ufw`
3. `configure_time`
4. `install_packages`
5. ...

Sin embargo, `install_packages()` es la función que instala `ufw`.

En una instalación limpia:

- `configure_ufw` detecta que `ufw` no existe;
- registra un warning y salta la fase;
- `install_packages` instala UFW después;
- el firewall queda sin el conjunto de reglas previsto.

**Corrección:** instalar dependencias antes de configurar UFW, pero mantener la regla de administración
(SSH) como primera regla antes de cambiar la política por defecto.

### LNX-002 — El bootstrap bloquea cualquier mantenimiento de un AD existente

Si existe `/var/lib/samba/private/sam.ldb`, el flujo interactivo sale con código 2 y solo recomienda
`--validate`.

Eso es seguro contra reprovisionado, pero demasiado restrictivo para administración real.

**Corrección:** conservar el bloqueo de `domain provision`, pero ofrecer un menú `manage` con tareas
idempotentes separadas:

- estado/health;
- resolver local;
- Kerberos local;
- Chrony;
- UFW;
- OUs/grupos;
- GPO;
- backup de dominio;
- SYSVOL check;
- SYSVOL reset solo como reparación avanzada confirmada.

### LNX-003 — Cambios de servicio potencialmente disruptivos sin snapshot suficiente

`configure_samba_services()` deshabilita y enmascara `smbd`, `nmbd` y `winbind`.

En un servidor realmente nuevo es razonable. En infraestructura existente puede interrumpir:

- shares;
- autenticación;
- winbind;
- procesos dependientes.

**Corrección:** detectar estado/rol antes de modificar. Si hay servicios activos y no es un host fresco,
clasificar la acción como `HIGH`, mostrar impacto y tomar snapshot del estado systemd.

### LNX-004 — Kerberos destruye el cache existente del administrador

`ensure_admin_user()` ejecuta `kdestroy` antes de obtener el ticket del usuario administrativo.

Eso puede borrar un cache Kerberos que no pertenece conceptualmente al assistant.

**Corrección:** usar un cache privado por ejecución, por ejemplo:

`KRB5CCNAME=FILE:/run/debian-ad-assistant/krb5cc-<pid>`

y destruir solo ese cache al terminar.

### LNX-005 — No existe backup de dominio antes de cambios AD/GPO sensibles

Se respaldan ficheros de configuración, pero no se crea una copia del dominio antes de operaciones que
pueden modificar objetos/GPO/SYSVOL.

**Corrección:** integrar `samba-tool domain backup online` como operación explícita y recomendarla antes
de cambios de alto impacto en un DC existente. Para recuperación completa, documentar que restaurar un
backup de dominio no equivale a copiar de vuelta `sam.ldb`.

---

## Medios

### LNX-006 — Escrituras en `/var` ocurren antes de `require_root`

Los directorios/logs/lock se crean en carga global, antes de entrar en `main()` y antes de
`require_root`.

Consecuencia: una ejecución sin privilegios puede fallar por permisos antes de mostrar el mensaje
amigable “Run as root”.

**Corrección:** parsear CLI y comprobar privilegios antes de inicializar estado persistente.

### LNX-007 — Validación DNS demasiado permisiva

La regex actual acepta casos sintácticamente dudosos como labels con guiones en posiciones no válidas
o secuencias de puntos.

**Corrección:** validar label a label, longitud 1–63 y longitud FQDN.

### LNX-008 — Detección de interfaz asume la primera ruta por defecto

`ip route show default | awk 'NR==1{print $5}'` no es suficiente en hosts con:

- múltiples NIC;
- rutas con métricas;
- management VLAN;
- VPN;
- bonds/bridges;
- rutas policy-based.

**Corrección:** si hay SSH, resolver la interfaz usada para llegar al cliente mediante `ip route get`.
En caso ambiguo, mostrar interfaces y pedir selección.

### LNX-009 — La comprobación de hostname repetido no detecta el caso real

La condición:

`[[ "$DC_HOSTNAME.$DOMAIN" == "$DOMAIN" ]]`

prácticamente nunca detectará que el hostname coincide con el primer label del dominio.

Para `DC_HOSTNAME=cip` y `DOMAIN=cip.daniel.org`, el resultado es `cip.cip.daniel.org`.

**Corrección:** advertir si `${DOMAIN%%.*}` coincide, case-insensitive, con `DC_HOSTNAME`.

### LNX-010 — Gestión de `/etc/resolv.conf` tiene una ventana de riesgo

Se puede desactivar `systemd-resolved`, eliminar el symlink y luego crear un fichero nuevo. Si algo falla
entre medias, el host puede quedarse sin resolver nombres.

**Corrección:**

- verificar que Samba DNS responde en `127.0.0.1` antes del switch;
- generar el nuevo resolver en temporal;
- reemplazar de forma atómica;
- verificar inmediatamente;
- restaurar backup si la verificación falla.

### LNX-011 — Backups por basename pueden colisionar

`backup_file()` usa un secuencial + `basename`. Reduce colisiones, pero pierde el path original como
estructura recuperable.

**Corrección:** guardar una réplica bajo `BACKUP_DIR/rootfs/etc/...` y un manifest con:

- origen;
- destino;
- hash;
- propietario/permisos;
- fecha.

### LNX-012 — GPO JSON depende de escaping de heredoc

El JSON de máquina utiliza heredoc no quoted con secuencias de barras invertidas. Aunque la versión
actual valida el resultado con `python3 -m json.tool`, es una zona frágil para mantenimiento.

**Corrección:** generar JSON con Python `json.dump()` usando argumentos/variables ya validados.
Así Bash deja de ser responsable del escaping JSON.

### LNX-013 — Parsing textual de `samba-tool gpo listall`

`find_gpo_guid()` depende del formato textual y de `display name`.

**Corrección:** encapsular el parser en una única función, detectar versión/capacidad de Samba y fallar
de forma explícita si cambia el formato. No dispersar parsing textual por el script.

### LNX-014 — `--validate` asume herramientas instaladas

Un host parcialmente configurado puede no tener `dig`, `samba-tool`, `testparm`, etc.

**Corrección:** cada control debe declarar sus dependencias y devolver `SKIP/ERROR` legible en vez de
terminar el assistant por “command not found”.

---

# 3. Hallazgos Windows

## Críticos / altos

### WIN-001 — Auditoría LLMNR invertida

La función `Test-RegistryValue` devuelve `$true` únicamente cuando el valor es `1`.

`Audit-LLMNR` la usa para `EnableMulticast` y considera `$true` como “Disabled”.

La política correcta para deshabilitar LLMNR es:

`EnableMulticast = 0`

Por tanto el código actual puede:

- marcar `1` como PASS;
- marcar `0` como WARN.

**Corrección:** sustituirla por una función genérica `Test-RegistryEquals -ExpectedValue`.

### WIN-002 — Firewall puede cortar la sesión remota

`Remediate-Firewall` aplica:

- perfiles habilitados;
- inbound block.

No hay una precondición para conservar la vía de administración actual.

**Corrección:**

- detectar RDP / PowerShell remoting;
- snapshot/export del firewall;
- si la sesión es remota, no cambiar defaults sin autorización de alto impacto;
- verificar que existe una regla efectiva de management antes de aplicar;
- post-check de conectividad/servicios.

### WIN-003 — No existe snapshot/rollback general antes del hardening

Los cambios de registry, firewall, Defender y SMB se aplican individualmente y se registran, pero no
hay un paquete de recuperación.

**Corrección:** antes del primer cambio crear un `change-set` con:

- `netsh advfirewall export`;
- export de registry keys afectadas;
- JSON de SMB server/client;
- JSON de Defender preferences/status;
- export de política local con `secedit` cuando esté disponible;
- metadatos del host y roles.

No todo puede restaurarse automáticamente de forma segura; el backup debe incluir `RESTORE.md` y
diferenciar rollback automático de rollback manual.

### WIN-004 — Falta role-awareness suficiente

Solo se distingue “DC / no DC”.

Para hardening profesional conviene conocer al menos:

- AD DS;
- DNS;
- DHCP;
- File Server;
- Hyper-V;
- IIS;
- RDS;
- Failover Clustering.

**Corrección:** inventario con `Get-WindowsFeature` cuando exista y adaptar controles/remediaciones.

---

## Medios

### WIN-005 — Local Administrators depende de nombres en inglés

Aunque el grupo se resuelve correctamente por SID `S-1-5-32-544`, los miembros permitidos se filtran
por nombres como `Administrator` y `Domain Admins`.

Eso produce falsos positivos en Windows localizado.

**Corrección:** comparar SIDs/RIDs siempre que sea posible. En un DC, no tratar la gestión de
administradores como si existiera un SAM local normal.

### WIN-006 — Module Logging está incompleto

Activar `EnableModuleLogging=1` no selecciona los módulos que se deben registrar.

**Corrección:** configurar también `ModuleNames`. Si se usa `*`, avisar del incremento de volumen y
posible exposición de datos sensibles en logs.

### WIN-007 — Defender puede estar administrado o en modo pasivo

`Get-MpComputerStatus` debe interpretarse junto con el contexto de administración y modo de ejecución.
Un servidor con EDR/AV de terceros no debe “arreglarse” automáticamente activando Defender sin
entender la coexistencia.

**Corrección:** auditar primero modo/estado y marcar `MANAGED/INFO` cuando corresponda.

### WIN-008 — BitLocker solo comprueba `FullyEncrypted`

También interesa:

- `ProtectionStatus`;
- protectores;
- volumen OS vs datos;
- recovery escrow;
- método de cifrado.

### WIN-009 — No se valida realmente la familia de Windows Server

El header declara Server 2019/2022/2025, pero el script no establece un compatibility gate.

**Corrección:** detectar Caption/Build/PowerShell, marcar `SUPPORTED/UNTESTED`, y no asumir que
cmdlets ausentes son un fallo de seguridad.

### WIN-010 — `NonInteractive` equivale en la práctica a “no aplicar”

Es seguro, pero el nombre puede inducir a pensar que realiza hardening automatizado.

**Corrección:** renombrar semánticamente a `Mode=Audit` / `Mode=Interactive`, y reservar un futuro
modo plan/apply para automatización controlada.

---

# 4. Consola profesional propuesta

La UX debe ser funcional en:

- TTY local;
- SSH;
- Windows Console;
- Windows Terminal;
- PowerShell remoting;
- stdout redirigido;
- `curl | sudo bash`.

Principios:

- colores solo si el terminal los soporta;
- `NO_COLOR` respetado;
- `Write-Progress`/barra Bash solo en terminal interactivo;
- fallback a líneas de estado en CI/redirección;
- etapa actual + total;
- riesgo de la operación visible;
- estado antes/después;
- paths de log/backup siempre visibles;
- no limpiar la consola por defecto en sesiones remotas.

Ejemplo:

```text
[03/11] Network preflight        [PASS]  eth0 192.168.10.10/24
[04/11] Samba packages           [RUN ]  installing 3 missing packages...
         [##########----------] 50%
[05/11] Resolver transition      [PLAN]  systemd-resolved -> Samba DNS
         Backup: /var/lib/.../rootfs/etc/resolv.conf
         Risk  : MEDIUM (name resolution)
Apply? [y/N]:
```

---

# 5. Arquitectura recomendada del assistant Linux

```text
runtime
  ├─ parse CLI
  ├─ privilege check
  ├─ TTY/capabilities
  ├─ logging/lock
  └─ cleanup traps

discovery
  ├─ OS
  ├─ network
  ├─ Samba role
  ├─ services
  ├─ resolver
  └─ current AD identity

safety
  ├─ config backup
  ├─ system snapshot
  ├─ domain backup
  ├─ risk confirmations
  └─ atomic file replacement

operations
  ├─ bootstrap
  ├─ manage
  ├─ repair-local
  ├─ gpo
  ├─ firewall
  ├─ time
  └─ directory objects

validation
  ├─ service
  ├─ DNS A/SRV
  ├─ Kerberos
  ├─ dbcheck
  ├─ SYSVOL
  ├─ GPO ACL
  └─ firewall

reporting
  ├─ text
  ├─ optional JSON
  └─ backup manifest
```

---

# 6. Arquitectura recomendada del assistant Windows

```text
Discover
  ├─ OS / PowerShell
  ├─ role
  ├─ installed roles/features
  ├─ remote/local session
  └─ management context

Audit
  ├─ Firewall
  ├─ Defender
  ├─ SMB
  ├─ RDP
  ├─ local/domain admin exposure
  ├─ LAPS
  ├─ PowerShell logging
  ├─ LLMNR
  ├─ BitLocker
  └─ update evidence

Plan
  ├─ finding
  ├─ proposed change
  ├─ role impact
  ├─ session impact
  └─ rollback path

Backup
  ├─ firewall
  ├─ registry
  ├─ SMB
  ├─ Defender
  └─ security policy

Apply
  ├─ explicit confirmation
  ├─ one control at a time
  └─ post-check

Report
  ├─ JSON
  ├─ text log
  └─ change-set manifest
```

---

# 7. CIS / vendor baselines

A 27 de septiembre de 2026:

- CIS publica Debian Linux 13 Benchmark 1.1.0.
- CIS publica Ubuntu Linux 26.04 LTS Benchmark 1.0.0.
- CIS publica Microsoft Windows Server 2025 Benchmark 2.1.0.
- CIS publica Microsoft Windows Server 2022 Benchmark 5.1.0.
- CIS publica Microsoft Windows Server 2019 Benchmark 5.0.0.
- Microsoft mantiene Security Compliance Toolkit y una baseline específica de Windows Server 2025;
  la revisión 2602 fue publicada en febrero de 2026.

Recomendación de diseño:

- Linux Ubuntu: si USG/CIS tooling oficial está disponible, integrarlo como auditor externo y conservar
  el resultado; si no, marcar los checks internos como `CIS-oriented`, no como certificación.
- Debian: permitir importar evidencia de CIS-CAT u otra herramienta autorizada, sin reimplementar el
  benchmark completo dentro del script.
- Windows: usar Microsoft Security Baseline como referencia vendor-native y añadir una capa CIS
  opcional. Nunca aplicar cientos de políticas de forma ciega en un DC o servidor con roles.

---

# 8. Prioridad de implementación

## P0
- Corregir orden UFW/paquetes.
- Corregir LLMNR.
- Separar `bootstrap` y `manage`.
- Añadir backup/snapshot previo a cambios de alto impacto.
- Cache Kerberos aislado.
- Evitar cambios de firewall que puedan cortar sesión remota.

## P1
- Consola con progreso.
- Discovery de roles.
- JSON generado de forma segura.
- Resolver con transición atómica.
- Validaciones capability-aware.

## P2
- Integración opcional con tooling CIS/vendor.
- plan/apply reproducible.
- rollback asistido.
- tests automatizados en VMs/containers donde sea viable.
- CI de sintaxis/lint (ShellCheck/PSScriptAnalyzer).

---

# 9. Estrategia de pruebas recomendada

## Bash
- `bash -n`
- ShellCheck
- Debian 13 minimal
- Ubuntu Server 26.04 minimal
- SSH con UFW inicialmente apagado
- SSH con UFW ya configurado
- NetworkManager
- systemd-networkd/systemd-resolved
- DC nuevo
- DC ya existente
- ejecución repetida
- `curl | sudo bash`
- `sudo bash file.sh`
- `--audit` sin Samba instalado
- `--validate` con instalación parcialmente rota

## PowerShell
- parser Windows PowerShell 5.1
- PSScriptAnalyzer
- Server 2019
- Server 2022
- Server 2025
- member server
- workgroup server
- Domain Controller
- ejecución por RDP
- ejecución por WinRM
- Defender activo / pasivo
- Windows en idioma no inglés
- firewall ya administrado por GPO

---

# 10. Conclusión

La base del repositorio es buena y, sobre todo, la filosofía de “detectar antes de modificar” ya está
presente. El salto a una herramienta realmente reutilizable en producción no requiere convertirla en
un framework enorme: requiere separar estados, introducir transacciones/snapshots alrededor de los
cambios sensibles y dejar de tratar “AD existente” como un caso binario de solo lectura.

Los candidatos `*-review` entregados junto con este informe deben tratarse como una nueva línea de
desarrollo para validar primero en laboratorio. No sustituyen una prueba contra los benchmarks
completos ni una validación real en cada rol/versión objetivo.

---

# 11. Validación realizada sobre los candidatos entregados

## Linux `v3.0.0-review`

Validaciones ejecutadas en el entorno de revisión:

- `bash -n`: **PASS**.
- `--help`: **PASS**.
- ejecución completa `--audit --no-color` sobre Debian GNU/Linux 13 (trixie): **PASS**, código de salida 0.
- el smoke test detectó interfaz, IPv4, gateway, servicios, AppArmor/auditd y ausencia de AD sin abortar por dependencias no instaladas.

No se ha ejecutado un provisioning real de Samba AD/DC en este entorno; debe validarse en VM antes de producción.

## Windows `v0.3.0-review`

Se realizaron comprobaciones estructurales (delimitadores balanceados y revisión de compatibilidad con sintaxis de Windows PowerShell 5.1), pero el runtime de revisión no dispone de `powershell.exe`/`pwsh` ni de PSScriptAnalyzer. Por ello **no se afirma una validación real del parser de PowerShell** en esta entrega. Antes de promoverlo:

```powershell
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
  '.\\pymes-windows-server-security-v0.3.0-review.ps1',
  [ref]$null,
  [ref]$errors
) | Out-Null
$errors
```

Y, si PSScriptAnalyzer está disponible:

```powershell
Invoke-ScriptAnalyzer .\\pymes-windows-server-security-v0.3.0-review.ps1 -Severity Warning,Error
```

Esta limitación se deja explícita para no presentar un fichero como “probado” cuando solo ha sido revisado estáticamente.
