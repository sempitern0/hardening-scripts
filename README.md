# Hardening Scripts · Active Directory Control Planes

[![Status](https://img.shields.io/badge/status-active%20development-0A7EA4)](#estado-del-proyecto)
[![License](https://img.shields.io/badge/license-MIT-green)](./LICENSE)
[![Debian](https://img.shields.io/badge/Debian-13-A81D33?logo=debian&logoColor=white)](#control-plane-samba-ad)
[![Ubuntu](https://img.shields.io/badge/Ubuntu%20Server-26.04%20LTS-E95420?logo=ubuntu&logoColor=white)](#control-plane-samba-ad)
[![Windows Server](https://img.shields.io/badge/Windows%20Server-2019%20%7C%202022%20%7C%202025-0078D4?logo=windows&logoColor=white)](#control-plane-windows-server)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)](#control-plane-windows-server)
[![Security](https://img.shields.io/badge/model-audit--first%20%7C%20recovery--aware-success)](#principios-de-operacion)

Herramientas autocontenidas para desplegar, auditar, operar, endurecer y recuperar entornos **Active Directory** sobre:

- Samba AD DC en Debian / Ubuntu Server;
- Active Directory Domain Services en Windows Server;
- clientes y member servers Linux;
- clientes y member servers Windows.

El proyecto está orientado a administración técnica real: primero detecta el estado actual, presenta el contexto operativo, conserva evidencia y snapshots cuando corresponde y solicita confirmación antes de cambios sensibles.

> **Importante**
> Active Directory, DNS, Kerberos, Group Policy, firewall y servicios de dominio son infraestructura crítica. Valida los procedimientos en laboratorio, conserva una vía de administración alternativa y mantén backups externos y restaurables antes de intervenir sistemas de producción.

---

## Contenido

- [Qué herramienta usar](#que-herramienta-usar)
- [Principios de operación](#principios-de-operacion)
- [Inicio rápido](#inicio-rapido)
- [Control Plane Samba AD](#control-plane-samba-ad)
- [Control Plane Windows Server](#control-plane-windows-server)
- [Asistentes de clientes AD](#asistentes-de-clientes-ad)
- [DNS: requisito fundamental](#dns-requisito-fundamental)
- [Operaciones remotas](#operaciones-remotas)
- [GPO y SYSVOL: permisos y diagnóstico](#gpo-y-sysvol-permisos-y-diagnostico)
- [Suricata IDS](#suricata-ids)
- [Backups, snapshots y recuperación](#backups-snapshots-y-recuperacion)
- [Hardening y compatibilidad](#hardening-y-compatibilidad)
- [Virtualización y hosts multi-NIC](#virtualizacion-y-hosts-multi-nic)
- [Troubleshooting](#troubleshooting)
- [Rutas de estado y logs](#rutas-de-estado-y-logs)
- [Checklist antes de producción](#checklist-antes-de-produccion)
- [Estado del proyecto](#estado-del-proyecto)

---

<a id="que-herramienta-usar"></a>
## Qué herramienta usar

| Archivo | Plataforma | Uso principal |
|---|---|---|
| `debian-ad-assistant.sh` | Debian / Ubuntu Server | Provisioning y operación de Samba Active Directory Domain Controller |
| `windows-ad-assistant.ps1` | Windows Server | Provisioning, auditoría y operación de AD DS nativo |
| `linux-ad-client-assistant.sh` | Linux | Unión reversible de clientes/member servers a Active Directory |
| `windows-ad-client-assistant.ps1` | Windows | Unión reversible y transaccional de clientes/member servers a Active Directory |

Elección rápida:

```text
Quiero administrar un Domain Controller
│
├─ Samba AD sobre Linux       → debian-ad-assistant.sh
└─ Microsoft AD DS            → windows-ad-assistant.ps1

Quiero unir un equipo al dominio
│
├─ Linux                      → linux-ad-client-assistant.sh
└─ Windows                    → windows-ad-client-assistant.ps1
```

Los asistentes de Linux y Windows persiguen **paridad funcional**, no implementaciones idénticas. Cada plataforma utiliza las herramientas nativas apropiadas para DNS, identidad, servicios, backup y administración remota.

---

<a id="principios-de-operacion"></a>
## Principios de operación

El flujo habitual es:

```text
DETECT
  ↓
AUDIT / PREFLIGHT
  ↓
PLAN
  ↓
BACKUP / SNAPSHOT
  ↓
CONFIRM
  ↓
APPLY
  ↓
VALIDATE
  ↓
REBOOT / RE-AUDIT
```

Principios comunes:

- detectar antes de modificar;
- no reprovisionar silenciosamente infraestructura existente;
- conservar una ruta de recuperación;
- separar auditoría de remediación;
- pedir confirmación explícita en operaciones de alto impacto;
- utilizar herramientas nativas del sistema siempre que sea razonable;
- no almacenar contraseñas administrativas;
- conservar logs y evidencia operativa;
- validar DNS, Kerberos y conectividad antes de interpretar un fallo como un problema de credenciales;
- no aplicar rollback agresivo cuando el estado de una operación de dominio es ambiguo;
- no afirmar cumplimiento CIS completo por validar únicamente un subconjunto de controles.

### Qué no intenta hacer el proyecto

No pretende sustituir el diseño de Active Directory ni convertir un DC en un instalador de un clic. Decisiones como topología DNS, trusts, delegación, políticas Kerberos, LDAP channel binding, segmentación de red o estrategia de backup siguen requiriendo criterio de administración.

---

<a id="inicio-rapido"></a>
## Inicio rápido

### 1. Clonar y revisar

```bash
git clone https://github.com/sempitern0/hardening-scripts.git
cd hardening-scripts
```

Antes de ejecutar un script con privilegios, revísalo y comprueba el modo que vas a utilizar.

### 2. Empezar por auditoría

Samba AD / Linux:

```bash
sudo bash ./debian-ad-assistant.sh --audit
```

Windows Server:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\windows-ad-assistant.ps1 -Mode Audit
```

Linux client:

```bash
sudo bash ./linux-ad-client-assistant.sh --audit
```

Windows client:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\windows-ad-client-assistant.ps1 -Mode Audit
```

> Ejecutar una auditoría antes del provisioning o hardening ayuda a detectar DNS incorrecto, roles existentes, interfaces inesperadas, estados pendientes y otros conflictos antes de modificar el host.

---

<a id="control-plane-samba-ad"></a>
## Control Plane Samba AD

`debian-ad-assistant.sh` administra un Samba Active Directory Domain Controller sobre Debian / Ubuntu Server.

### Targets principales

- Debian 13;
- Ubuntu Server 26.04 LTS;
- Bash;
- systemd;
- Samba AD DC;
- IPv4 como camino principal de administración/AD.

Otros derivados Debian pueden funcionar en modo best-effort, pero no se consideran targets equivalentes hasta ser probados.

### Operaciones habituales

```bash
sudo bash ./debian-ad-assistant.sh --audit
sudo bash ./debian-ad-assistant.sh --validate
sudo bash ./debian-ad-assistant.sh --bootstrap
sudo bash ./debian-ad-assistant.sh --manage
sudo bash ./debian-ad-assistant.sh --status
sudo bash ./debian-ad-assistant.sh --backup
```

Consulta siempre la ayuda de la versión instalada para el conjunto completo de modos:

```bash
sudo bash ./debian-ad-assistant.sh --help
```

#### Bootstrap de un DC nuevo

```bash
sudo bash ./debian-ad-assistant.sh --bootstrap
```

Antes de iniciar:

- define hostname definitivo;
- utiliza una dirección estable para el DC;
- decide el dominio DNS y realm;
- verifica hora y conectividad;
- conserva acceso por consola/hipervisor si vas a modificar red o firewall;
- no reutilices un servidor con una instalación Samba desconocida como si estuviera vacío.

El asistente detecta una base AD existente y evita reprovisionarla como un dominio nuevo.

#### Administración diaria

```bash
sudo bash ./debian-ad-assistant.sh --manage
```

El control plane agrupa funciones por workspace:

```text
[O] Daily operations       [D] Directory
[P] Policy / GPO           [S] Security
[R] Remote operations      [I] Insights / IDS
[M] Maintenance            [A] All modules
```

Áreas principales:

- usuarios y grupos;
- equipos y permisos;
- Group Policy;
- DNS y Kerberos;
- validación del DC;
- hardening;
- dependencias;
- backups;
- migración;
- Suricata IDS;
- operaciones remotas;
- decommission/reset controlado.

#### CLI instalable

El asistente puede instalar accesos directos administrativos:

```bash
sudo bash ./debian-ad-assistant.sh --install-cli
```

Después pueden estar disponibles comandos como:

```text
adctl
ad-ops
ad-users
ad-groups
ad-computers
ad-permissions
ad-gpo
ad-security
ad-samba
ad-kerberos
ad-migrate
ad-reset
ad-deps
ad-ids
ad-remote
ad-audit
ad-validate
ad-status
ad-backup
```

Tras sustituir el script principal por una versión nueva, refresca los shortcuts para evitar operar una copia instalada anterior.

#### Después de un reboot

Un DC no debe considerarse validado solo porque el provisioning haya terminado. Tras reiniciar comprueba, como mínimo:

```bash
sudo bash ./debian-ad-assistant.sh --validate
```

Y revisa:

```bash
systemctl status samba-ad-dc --no-pager
chronyc tracking
samba-tool dbcheck --cross-ncs
```

---

<a id="control-plane-windows-server"></a>
## Control Plane Windows Server

`windows-ad-assistant.ps1` administra Windows Server y Active Directory Domain Services mediante tooling nativo de Microsoft.

### Targets principales

- Windows Server 2019;
- Windows Server 2022;
- Windows Server 2025;
- Windows PowerShell 5.1+.

### Modos principales

```powershell
.\windows-ad-assistant.ps1 -Mode Audit
.\windows-ad-assistant.ps1 -Mode Validate
.\windows-ad-assistant.ps1 -Mode Harden
.\windows-ad-assistant.ps1 -Mode Backup
.\windows-ad-assistant.ps1 -Mode ADAdmin
.\windows-ad-assistant.ps1 -Mode Provision
.\windows-ad-assistant.ps1 -Mode Migration
.\windows-ad-assistant.ps1 -Mode DirectorySecurity
.\windows-ad-assistant.ps1 -Mode Dependencies
.\windows-ad-assistant.ps1 -Mode IDS
.\windows-ad-assistant.ps1 -Mode RemoteOps
```

Sin `-Mode` abre el control plane interactivo.

#### Workspaces

```text
[O] Daily operations       [D] Directory
[P] Policy / DNS           [S] Security
[R] Remote operations      [I] Insights / IDS
[M] Maintenance            [A] All modules
```

Funciones relevantes:

- provisioning de un bosque nuevo;
- inventario y auditoría del host;
- usuarios, grupos, equipos y OUs;
- GPO y DNS integrado;
- DCDiag, replicación, SYSVOL y FSMO;
- hardening de Windows y protocolos de directorio;
- backup de configuración y system state;
- dependencias/features de Windows;
- migración de dominio;
- Suricata/EVE;
- operaciones remotas WinRM/SSH;
- demotion/decommission controlado.

#### Provisioning

```powershell
.\windows-ad-assistant.ps1 -Mode Provision
```

Utiliza las herramientas soportadas de AD DS y realiza prerequisite checks antes de la promoción.

Para el primer DC de un bosque, prepara previamente:

- hostname definitivo;
- IPv4 estática;
- dominio DNS y NetBIOS;
- acceso administrativo local;
- hora correcta;
- acceso alternativo si trabajas remotamente.

#### Backup de Domain Controller

Un export de configuración no sustituye un backup de recuperación de AD DS. En Windows Server, para recuperación real de un DC, utiliza **System State Backup** y una política de backup externa acorde a tu entorno.

---

<a id="asistentes-de-clientes-ad"></a>
## Asistentes de clientes AD

Los asistentes de cliente están diseñados para que el join sea **observable y recuperable**, especialmente alrededor de DNS y reboot.

### Linux AD Client Assistant

Archivo:

```text
linux-ad-client-assistant.sh
```

Targets principales:

- Debian / Ubuntu y derivados APT;
- RHEL / Fedora / Rocky / Alma y derivados DNF/YUM;
- systemd;
- realmd + SSSD + adcli.

Uso:

```bash
sudo bash ./linux-ad-client-assistant.sh --audit
sudo bash ./linux-ad-client-assistant.sh --join
sudo bash ./linux-ad-client-assistant.sh --status
sudo bash ./linux-ad-client-assistant.sh --leave
sudo bash ./linux-ad-client-assistant.sh --restore
sudo bash ./linux-ad-client-assistant.sh --snapshots
```

Sin argumentos abre el control plane interactivo.

El flujo de join incluye:

- selección de interfaz consciente de la ruta;
- snapshot de resolver, hostname e identidad;
- instalación controlada de dependencias cuando corresponde;
- comprobación directa de DNS AD;
- comprobación de forwarding DNS externo;
- discovery de Active Directory;
- autenticación Kerberos mediante ccache privado;
- join realmd/SSSD;
- validación post-join;
- rollback local cuando la membresía todavía no ha sido comprometida;
- recuperación de intentos interrumpidos.

### Windows AD Client Assistant

Archivo:

```text
windows-ad-client-assistant.ps1
```

Ejecuta desde Windows PowerShell 5.1+ como administrador.

#### Modos

```powershell
.\windows-ad-client-assistant.ps1 -Mode Audit
.\windows-ad-client-assistant.ps1 -Mode Join
.\windows-ad-client-assistant.ps1 -Mode Status
.\windows-ad-client-assistant.ps1 -Mode Leave
.\windows-ad-client-assistant.ps1 -Mode Restore
.\windows-ad-client-assistant.ps1 -Mode Snapshots
.\windows-ad-client-assistant.ps1 -Mode Recover
```

Sin `-Mode` abre el menú interactivo.

#### Flujo de join

```text
preflight DNS directo
        ↓
selección de NIC / ruta
        ↓
snapshot pre-join
        ↓
configurar DNS AD
        ↓
discovery + puertos + hora
        ↓
Add-Computer
        ↓
reboot
        ↓
secure channel + nltest + DNS
```

El snapshot conserva la información necesaria para recuperar el estado DNS/hostname previo al join.

#### Estados de lifecycle

El asistente mantiene una fase persistente para distinguir operaciones seguras de estados que requieren cautela. Algunos estados que puedes ver son:

```text
SNAPSHOT_CREATED
DNS_APPLIED
JOIN_SUBMITTED
JOIN_AMBIGUOUS
JOIN_PENDING_REBOOT
JOINED
JOINED_DEGRADED
LEAVE_PENDING_REBOOT
RESTORE_READY
RESTORE_PENDING_REBOOT
```

No es necesario memorizar todos los estados. La regla importante es:

> Si el asistente indica `JOIN_SUBMITTED`, `JOIN_AMBIGUOUS` o `JOIN_PENDING_REBOOT`, **no restaures DNS manualmente** hasta verificar si Windows ha aceptado la membresía.

Utiliza:

```powershell
.\windows-ad-client-assistant.ps1 -Mode Recover
```

El recovery combina el estado persistente, la membresía que reporta Windows y la evidencia de `NetSetup.log`. Cuando no puede demostrar si el join fue comprometido, evita el rollback automático.

#### Snapshots

```powershell
.\windows-ad-client-assistant.ps1 -Mode Snapshots
```

Muestra snapshots conservados con dominio objetivo, equipo, interfaz y estado asociado.

Los snapshots se conservan como evidencia aunque el lifecycle activo haya terminado.

#### DNS forwarding estricto

Antes de reemplazar el resolver del cliente, el asistente comprueba cada DNS AD configurado:

1. debe devolver los registros SRV del dominio;
2. debe poder resolver un nombre fuera de la zona AD.

Por defecto se utiliza:

```text
www.microsoft.com
```

Puedes seleccionar otro probe:

```powershell
.\windows-ad-client-assistant.ps1 `
  -Mode Join `
  -ExternalDnsProbe 'www.example.net'
```

Para redes deliberadamente aisladas, existe un override explícito:

```powershell
.\windows-ad-client-assistant.ps1 `
  -Mode Join `
  -AllowAdDnsWithoutExternalResolution
```

No utilices el override para ocultar un forwarder roto en una red que sí necesita resolución externa.

#### Leave y restauración

En Windows, `Remove-Computer` requiere reboot para materializar completamente la salida del dominio. Por ello el flujo correcto es:

```text
Leave
  ↓
AD DNS se conserva temporalmente
  ↓
reboot
  ↓
Restore / Recover
  ↓
DNS + hostname pre-join
```

No restaures DNS antes del reboot del leave.

---

<a id="dns-requisito-fundamental"></a>
## DNS: requisito fundamental

Active Directory depende de sus registros DNS SRV.

El patrón recomendado es:

```text
AD clients
    │
    ├─ DNS → DC01
    └─ DNS → DC02
               │
               ├─ zonas AD
               └─ forwarders → resolución externa/corporativa
```

### No mezclar DNS públicos en los clientes AD

Evita configurar como DNS alternativo del cliente:

```text
8.8.8.8
1.1.1.1
9.9.9.9
router doméstico
DNS de NAT del hipervisor
```

El cliente puede seleccionar ese resolver y perder discovery de Active Directory.

Los resolvers externos pertenecen al **forwarding del DNS del dominio**, no a la lista DNS del miembro del dominio.

### Pruebas Linux

```bash
dig _ldap._tcp.dc._msdcs.corp.example.com SRV

dig @10.0.10.10 \
  _ldap._tcp.dc._msdcs.corp.example.com SRV

getent hosts dc01.corp.example.com
```

### Pruebas Windows

```powershell
Resolve-DnsName `
  -Name _ldap._tcp.dc._msdcs.corp.example.com `
  -Type SRV

Resolve-DnsName `
  -Name _ldap._tcp.dc._msdcs.corp.example.com `
  -Type SRV `
  -Server 10.0.10.10

nltest /dsgetdc:corp.example.com
```

Si una consulta directa al DNS AD funciona pero la consulta del resolver del sistema falla, el problema está en el camino DNS local del cliente, no necesariamente en Active Directory.

---

<a id="operaciones-remotas"></a>
## Operaciones remotas

Los dos control planes de DC incluyen un centro de operaciones remotas para endpoints registrados en Active Directory.

### Desde Windows Server

Camino recomendado:

```text
Windows → Windows : WinRM / PowerShell Remoting / Kerberos
Windows → Linux   : OpenSSH
```

Windows puede mantener una credencial alternativa en memoria durante la sesión cuando el operador lo decide.

### Desde Samba AD / Linux

Camino recomendado:

```text
Linux → Linux     : OpenSSH
Linux → Windows   : OpenSSH
                    Samba RPC como fallback limitado de power control
```

### Guardrails

Las consolas remotas están pensadas para operaciones administrativas concretas:

- readiness;
- sesiones activas;
- mensajes a usuarios;
- logoff controlado;
- diagnóstico;
- gestión limitada de servicios;
- restart / shutdown;
- export de evidencia.

No se expone un shell arbitrario como opción normal del menú.

Para delegación operativa utiliza:

```text
Windows → JEA / role capabilities
Linux   → sudoers limitado
Network → WinRM/SSH solo desde redes de management
```

---

<a id="gpo-y-sysvol-permisos-y-diagnostico"></a>
## GPO y SYSVOL: permisos y diagnóstico

Crear una GPO en un Samba AD DC combina **privilegios locales** y **autorización de dominio**. Son capas diferentes:

```text
shell del operador
      │
      ├─ sudo/root ────────────────> ficheros locales, runtime, backups, herramientas
      │
      └─ ticket Kerberos del admin
              │
              ├─ LDAP ────────────> CN=Policies,CN=System,...
              │
              └─ CIFS/SMB ────────> \\DC\SYSVOL\dominio\Policies\{GUID}
```

El asistente se autoeleva mediante `sudo` cuando se inicia como usuario normal. Por tanto, ejecutar:

```bash
./debian-ad-assistant.sh --gpo
```

es válido; no es necesario anteponer `sudo` manualmente mientras `sudo` esté disponible y el usuario local tenga permiso para utilizarlo. El control plane muestra y conserva el invocador original, pero las operaciones locales se ejecutan como root.

**Root no sustituye al administrador de Active Directory.** `samba-tool gpo create` utiliza las credenciales Kerberos del operador para acceder tanto a LDAP como a SYSVOL. Un proceso root puede seguir recibiendo un rechazo de LDAP o SMB.

### GPO mutation preflight

Antes de una mutación GPO, el asistente ejecuta automáticamente un preflight y reutiliza el resultado durante unos minutos dentro de la misma ejecución. También puede lanzarse manualmente desde:

```text
Group Policy Control
  -> [11] GPO mutation preflight
```

El preflight:

1. confirma que el proceso efectivo es root;
2. destruye el ccache privado anterior y solicita un **TGT Kerberos fresco** del administrador seleccionado;
3. verifica la identidad exacta del principal;
4. comprueba la membresía administrativa registrada en el directorio;
5. solicita tickets para `ldap/<DC_FQDN>` y `cifs/<DC_FQDN>` cuando `kvno` está disponible;
6. comprueba lectura GPO por LDAP;
7. ejecuta `samba-tool ntacl sysvolcheck`;
8. accede a SYSVOL mediante `smbclient` usando **el mismo ccache**;
9. crea y elimina un directorio temporal `.DAD-GPO-PROBE-*` bajo `SYSVOL/<dominio>/Policies` para comprobar escritura SMB real;
10. ejecuta `gpo aclcheck` como diagnóstico de consistencia de las GPO existentes;
11. captura el DS ACL de `CN=Policies,CN=System,<baseDN>` y el NT ACL del directorio `Policies`.

La prueba de escritura se ejecuta únicamente dentro de una ruta de mutación/diagnóstico GPO y elimina inmediatamente el directorio temporal. Si la limpieza falla, el asistente muestra la ruta exacta para revisión manual.

La evidencia queda bajo:

```text
/var/lib/debian-ad-assistant/runs/<run>/gpo-diagnostics/
```

Archivos relevantes pueden incluir:

```text
execution-context.txt
kvno-ldap.txt
kvno-cifs.txt
gpo-listall.txt
sysvolcheck.txt
sysvol-smb-read.txt
sysvol-smb-write.txt
gpo-aclcheck.txt
policies-container-dsacl.txt
policies-filesystem-acl.txt
gpo-create-<nombre>.txt
```

### Por qué una membresía correcta puede seguir fallando

Ver:

```text
Domain Admins       : member
GPO Creator Owners  : member
```

confirma el **estado del directorio**, pero no demuestra que un TGT Kerberos ya emitido contenga esas autorizaciones. Si un usuario se añadió recientemente a un grupo privilegiado, un ticket anterior puede seguir representando el token viejo.

Por eso el preflight fuerza un nuevo `kinit` antes de la primera mutación GPO del run. Esto evita diagnosticar como "ACL roto" lo que en realidad era un PAC/ticket antiguo.

Además, históricamente han existido diferencias y problemas de Samba alrededor de la delegación mediante `Group Policy Creator Owners`. Para operaciones administrativas críticas, la membresía de `Domain Admins` con un ticket fresco es una referencia diagnóstica más fuerte; no conviene modificar ACLs de SYSVOL únicamente para compensar una delegación que todavía no se ha aislado correctamente.

### Interpretar un fallo de `samba-tool gpo create`

El asistente conserva la salida completa y muestra una clasificación inicial:

| Evidencia | Frontera probable | Primer paso |
|---|---|---|
| `LDAP_INSUFFICIENT_ACCESS_RIGHTS`, `LDAP error 50` | ACL/autorización en `CN=Policies,CN=System` o token Kerberos antiguo | refrescar ticket y revisar `policies-container-dsacl.txt` |
| `NT_STATUS_ACCESS_DENIED` | autorización SMB/NT ACL de SYSVOL | revisar `sysvol-smb-write.txt` y ACL de `Policies` |
| `KDC_ERR*`, SPNEGO/GSSAPI, `LOGON_FAILURE` | Kerberos, DNS, SPN o tiempo | revisar `kvno-ldap.txt`, `kvno-cifs.txt`, DNS y reloj |
| error creando directorio temporal | problema local `/tmp`, espacio o privilegio Unix | revisar root, permisos y almacenamiento |
| `gpo aclcheck` falla pero `sysvolcheck` y write probe pasan | inconsistencia en alguna GPO existente | inspeccionar `gpo-aclcheck.txt`; no asumir que todo SYSVOL está roto |

### `sysvolcheck`, `gpo aclcheck` y `sysvolreset` no son equivalentes

`ntacl sysvolcheck` comprueba que los ACL de SYSVOL coincidan con lo esperado por Samba. `gpo aclcheck` compara aspectos de los ACL de las GPO entre LDAP y SYSVOL. Un fallo en uno no identifica automáticamente la reparación correcta.

No ejecutes `samba-tool ntacl sysvolreset` únicamente porque falle la creación de una GPO o `gpo aclcheck`. Es una operación amplia sobre ACL de SYSVOL y debe tratarse como **último recurso**, después de:

- backup de dominio;
- identificar si el rechazo es LDAP o SMB;
- comprobar el ticket Kerberos efectivo;
- revisar los ACL concretos afectados;
- confirmar la versión de Samba y el comportamiento esperado de herencia.

El asistente mantiene `sysvolreset` en el flujo avanzado y nunca lo ejecuta automáticamente tras un fallo GPO.

### Flujo recomendado para una GPO que no se crea

```text
[11] GPO mutation preflight
          │
          ├─ LDAP ticket FAIL ──> DNS / hora / SPN / Kerberos
          │
          ├─ CIFS ticket FAIL ──> SPN CIFS / DNS / Kerberos
          │
          ├─ SYSVOL read FAIL ──> autenticación SMB / share
          │
          ├─ SYSVOL create FAIL -> NT ACL / autorización efectiva
          │
          ├─ sysvolcheck FAIL ──> investigar ACL local/NT ACL antes de reparar
          │
          └─ todo PASS
                 │
                 └─ retry Create GPO
                        │
                        └─ si falla: revisar gpo-create-*.txt
                           para distinguir LDAP add de SMB/set_acl
```

Para un administrador delegado recién añadido a grupos privilegiados, salir/entrar de una sesión de escritorio **no es el mecanismo relevante para el asistente**: utiliza un ccache privado por ejecución y el preflight solicita un ticket fresco explícitamente.

---

<a id="suricata-ids"></a>
## Suricata IDS

Los control planes de DC incluyen integración opcional con Suricata para visibilidad de red y protocolos relacionados con Active Directory. En Linux el sensor se configura en modo **pasivo**: observa tráfico, genera telemetría y alertas, pero no bloquea paquetes.

### Modelo mental: actividad no es lo mismo que alerta

Esta distinción evita una de las confusiones más frecuentes al empezar con un IDS:

```text
ACTIVIDAD
Suricata ha visto tráfico o un protocolo.
Ejemplos: ping, DNS, Kerberos, LDAP, SMB, una conexión TCP.

ALERTA
Una regla/signature ha coincidido con ese tráfico.
Ejemplos: acceso a una superficie AD desde fuera de HOME_NET,
ráfaga anómala de SMB, una firma ET/Open o una anomalía de protocolo.
```

Por tanto:

> Un `ping` normal **no debería generar necesariamente una alerta**. En las versiones recientes del asistente se habilita telemetría EVE `flow`, por lo que el ICMP puede aparecer en **Connection activity** aunque `Recent alerts` siga vacío.

Los registros `flow` suelen emitirse cuando el flujo termina o expira. Un ping enviado hace unos segundos puede tardar algo en aparecer en la vista de actividad.

### Linux / Samba AD

Acceso habitual:

```bash
sudo bash ./debian-ad-assistant.sh --ids
```

El workspace diferencia la vista diaria del administrador de la evidencia técnica:

```text
[1]  IDS readiness assessment
[2]  Install / repair Suricata
[3]  Configure passive IDS
[4]  Sensor health
[5]  Operator overview
[6]  Recent alerts explained
[7]  AD protocol intelligence
[8]  Rule management
[9]  Daily local reports
[10] Export evidence
[11] Disable IDS integration
[12] Trusted network scope
[13] Connection activity
```

#### Qué mirar primero

Para operación diaria, una secuencia útil es:

```text
Sensor health
     ↓
Operator overview
     ↓
Connection activity
     ↓
Recent alerts explained
     ↓
AD protocol intelligence si necesitas detalle
```

`Operator overview` intenta responder preguntas operativas, no mostrar JSON:

- ¿está llegando telemetría reciente?;
- ¿hay pérdida de paquetes del sensor?;
- ¿quién está hablando con este DC?;
- ¿qué servicios reciben tráfico?;
- ¿hay ICMP/ping?;
- ¿hay alertas y qué significan en términos prácticos?;
- ¿el origen está dentro o fuera del `HOME_NET` confiable?

`Connection activity` está orientado específicamente a **quién se conecta**. Agrupa fuentes, servicios y actividad reciente. Una línea de esa vista significa que Suricata vio tráfico; no implica por sí sola actividad maliciosa.

#### Trusted network scope / HOME_NET

`HOME_NET` puede contener varias redes legítimas, por ejemplo:

```text
192.168.10.0/24,10.20.0.0/16,10.8.0.0/24
```

Incluye aquí las LAN, VLAN de administración, VPN y redes site-to-site cuyos clientes deban acceder legítimamente al DC. Las reglas locales de exposición utilizan `!$HOME_NET`; una red legítima olvidada en este scope puede producir alertas que parecen externas.

No añadas una red al scope únicamente para silenciar una alerta: primero confirma que realmente sea una red administrada y confiable.

### Pruebas seguras para aprender qué ve el sensor

Haz estas pruebas únicamente en infraestructura propia o expresamente autorizada.

#### 1. ICMP / ping

Desde otro equipo:

```bash
ping <IP_DEL_DC>
```

Esperado:

```text
Connection activity  → ICMP / ping
Recent alerts        → normalmente ninguna alerta nueva
```

Esto prueba visibilidad básica, **no la capacidad de disparar firmas**.

#### 2. DNS

Linux:

```bash
dig @<IP_DEL_DC> example.org
```

Windows:

```powershell
Resolve-DnsName example.org -Server <IP_DEL_DC>
```

Esperado: actividad DNS, IP origen y nombres consultados en las vistas de actividad/inteligencia.

#### 3. Kerberos + SMB desde un miembro del dominio

Windows:

```powershell
klist purge
dir \\<DC_FQDN>\SYSVOL
```

En un cliente correctamente unido al dominio esto suele generar actividad Kerberos y SMB. `klist purge` elimina tickets del cache del usuario para forzar una nueva negociación; úsalo solo si entiendes el efecto sobre esa sesión.

#### 4. Probar una regla local de exposición

Desde una máquina de laboratorio cuya IP esté **fuera de `HOME_NET`**, realiza únicamente una conexión al servicio del DC que quieras comprobar.

Linux:

```bash
nc -vz <IP_DEL_DC> 445
```

Windows:

```powershell
Test-NetConnection <IP_DEL_DC> -Port 445
```

Si la ruta llega al sensor y el origen está realmente fuera del scope confiable, la regla local de SMB/RPC debería poder producir una alerta similar a:

```text
DAD IDS External access to AD SMB-RPC TCP surface
```

No utilices scanners ni tráfico agresivo contra sistemas de terceros para "probar Suricata".

### Cómo interpretar alertas comunes

| Señal | Interpretación inicial | Qué comprobar |
|---|---|---|
| `DAD IDS External access ...` | Un origen fuera de `HOME_NET` alcanzó una superficie del DC | IP origen, red/VPN esperada, puerto y si falta una CIDR legítima |
| `DAD IDS High-rate SMB ...` | Muchas conexiones SMB en poco tiempo | scanner autorizado, inventario, cliente roto o reconocimiento |
| `applayer` / `app-layer` | Suricata no pudo interpretar limpiamente una conversación de aplicación | origen/destino, protocolo real, recurrencia y firma exacta |
| `ET SCAN` / firma de scanning | Tráfico parecido a discovery/reconocimiento | si el origen es un scanner autorizado y qué puertos tocó |
| `ET POLICY` | Tráfico relevante para una política, no necesariamente malware | contexto y necesidad operativa |
| malware / trojan / C2 | Patrón asociado a compromiso o command-and-control | endpoint origen, DNS/TLS, proceso y evidencia adicional |

Una alerta es una **señal de investigación**, no una sentencia. Correlaciona siempre firma, IP origen, destino, servicio, hora, Event Center y logs del endpoint.

### ¿Qué significa una alerta `applayer`?

Una alerta o anomalía `applayer` puede aparecer porque Suricata esperaba un protocolo y recibió datos incompletos, inesperados, cifrados, malformados o que su parser no pudo clasificar. Puede ser ruido, software extraño, una versión de protocolo poco común o tráfico hostil.

Antes de escalarla como incidente:

1. identifica `src_ip`, `dest_ip`, puerto y protocolo;
2. comprueba si el host origen es conocido;
3. mira si la alerta se repite;
4. revisa la actividad de la misma IP alrededor de esa hora;
5. comprueba Event Center y logs del servicio/endpoint;
6. escala si hay otras señales coherentes con scanning, explotación o compromiso.

### Rule management: feeds mantenidos antes que reglas manuales

El flujo recomendado no consiste en copiar firmas una a una. `suricata-update` es el gestor oficial de reglas de Suricata y genera el ruleset consolidado en:

```text
/var/lib/suricata/rules/suricata.rules
```

Ese fichero es un **artefacto generado**. No debe editarse directamente. La arquitectura del asistente es:

```text
                 SURICATA DETECTION PIPELINE

  feeds mantenidos              contexto local
  por suricata-update            del entorno
         │                            │
         ├─ ET/Open                   ├─ AD/DC context.rules
         ├─ OISF TrafficID            └─ custom.rules (opcional)
         ├─ abuse.ch feeds                  │
         └─ fuentes opcionales              │
                 │                          │
                 └──────────┬───────────────┘
                            ↓
                      suricata -T
                            ↓
                     safe rule reload
```

La consola ofrece ahora:

```text
Suricata IDS
  -> [8] Rule management

SURICATA RULE MANAGEMENT
 [1] Professional baseline
 [2] Rule status
 [3] Update now
 [4] Recommended sources
 [5] Browse source catalog
 [6] Enable indexed source
 [7] Disable source
 [8] Add HTTPS source
 [9] Local custom rules
 [10] Automatic updates
```

#### Professional baseline

Durante `Configure passive IDS`, el asistente propone este perfil con respuesta predeterminada **Y**. La activación sigue siendo explícita: el operador puede rechazarla y quedarse con ET/Open + las reglas contextuales del DC, y aplicarla más adelante desde `Rule management -> Professional baseline`.

El perfil recomendado para un sensor pasivo profesional instala/activa estas capas:

| Capa | Fuente | Función |
|---|---|---|
| General | ET/Open | amenazas, exploits, malware, scans y policy signatures mantenidas por ET |
| Visibilidad | `oisf/trafficid` | identificación de aplicaciones/tráfico mediante reglas `noalert` |
| Threat intelligence | `abuse.ch/feodotracker` | infraestructura C2 de botnets |
| Threat intelligence | `abuse.ch/urlhaus` | URLs usadas para distribución de malware |
| Threat intelligence | `abuse.ch/sslbl-blacklist` | certificados TLS asociados a infraestructura maliciosa |
| Contexto | Debian AD Assistant | exposición de Kerberos/LDAP/SMB/RPC/DNS/NTP del DC y ráfagas SMB |

ET/Open es el feed general por defecto de `suricata-update`. Si el administrador instala una fuente comercial que lo sustituya, el asistente no intenta mezclarla de forma ciega con ET/Open.

El baseline **no**:

- convierte `alert` en `drop`;
- habilita IPS/NFQUEUE;
- activa feeds de hunting de alto coste por defecto;
- añade fuentes comerciales sin licencia/token;
- edita directamente `suricata.rules`;
- deshabilita categorías del vendor silenciosamente.

El objetivo es disponer de una base útil y mantenida sin transformar el DC en un experimento de miles de firmas arbitrarias.

#### Fuentes adicionales propuestas

`Recommended sources` permite añadir de forma explícita fuentes del catálogo OISF. Además de las incluidas en el baseline, el asistente propone actualmente:

```text
stamus/lateral
    detecciones orientadas a movimiento lateral en entornos Windows/AD

ptrules/open
    conjunto adicional de detecciones abiertas de Positive Technologies
```

Son **opcionales**. Más reglas no equivalen automáticamente a más seguridad: pueden aumentar CPU, memoria, volumen de EVE y falsos positivos. Activa una fuente adicional porque responde a una necesidad concreta y revisa después el comportamiento del sensor.

El catálogo en vivo se obtiene con:

```bash
suricata-update update-sources
suricata-update list-sources
```

Desde el menú puedes refrescarlo y habilitar cualquier identificador `vendor/name`. La fuente solo se conserva como cambio válido si el ruleset resultante pasa la validación del sensor.

#### Fuente HTTPS no incluida en el catálogo

Para un feed público/privado no indexado, `Add HTTPS source` utiliza el mecanismo nativo:

```bash
suricata-update add-source custom/<nombre> https://servidor/rules.tar.gz
```

El workflow del asistente acepta únicamente HTTPS y después reconstruye y valida el ruleset.

No introduce API keys, bearer tokens ni contraseñas en argumentos propios del asistente. Si un proveedor requiere credenciales y ya existe en el índice de `suricata-update`, utiliza la fuente indexada para que el gestor aplique sus parámetros. Revisa siempre cómo y dónde el proveedor/`suricata-update` persiste esas credenciales antes de usar un feed comercial.

#### Reglas manuales locales: solo para contexto propio

La edición manual sigue disponible como escape hatch, pero no como mecanismo principal de actualización:

```text
/etc/suricata/debian-ad-rules/context.rules
    gestionado por el asistente; no editar

/etc/suricata/debian-ad-rules/custom.rules
    gestionado por el operador
```

`custom.rules` sirve para información que un feed genérico no puede conocer, por ejemplo:

- una subred que jamás debe contactar determinado servicio interno;
- un protocolo legacy que debe desaparecer después de una fecha;
- una aplicación propia;
- una IOC interna temporal;
- un patrón específico descubierto durante un incidente.

El editor integrado realiza:

```text
backup
  ↓
edit
  ↓
suricata -T
  ├─ FAIL -> rollback del fichero
  └─ PASS -> rule reload
```

Cada regla debe utilizar un `sid` globalmente único. Consulta la documentación de SID y `sidallocation.org` antes de reservar un rango permanente. No reutilices SID de ET/Open u otros feeds.

Las reglas locales se almacenan fuera de `/var/lib/suricata/rules`, porque esa ruta pertenece a `suricata-update`. El asistente también migra sus reglas contextuales antiguas fuera del directorio de reglas de la distribución para evitar cargar accidentalmente una misma firma dos veces.

#### Actualizaciones automáticas

Para un sensor operativo no es razonable depender de que el administrador recuerde ejecutar el updater. `Automatic updates` instala:

```text
debian-ad-suricata-rules.service
debian-ad-suricata-rules.timer
```

Cadencias disponibles:

```text
cada 6 horas     recomendado
cada 12 horas
diario
```

La programación añade `RandomizedDelaySec=15m` para que muchos servidores no consulten las fuentes exactamente a la vez.

El timer ejecuta el asistente instalado mediante un modo no interactivo:

```text
--ids-rules-update
```

El pipeline es:

```text
ruleset anterior
      ↓ backup
suricata-update
      ↓
¿suricata.rules existe y no está vacío?
      ↓
suricata -T con HOME_NET + overlay + reglas locales
      ↓
 PASS ───────────────→ reload del sensor
 FAIL ───────────────→ restaurar ruleset anterior
```

Si el live reload falla, el asistente intenta un restart controlado. El timer **no cambia qué fuentes están habilitadas**; únicamente actualiza las fuentes que el administrador ya seleccionó.

#### Tuning y supresiones

`suricata-update` soporta política declarativa mediante `enable.conf`, `disable.conf`, `modify.conf` y `drop.conf`. No edites el fichero consolidado para silenciar una firma. Si una regla resulta ruidosa, primero investiga por qué dispara y después utiliza un filtro declarativo o threshold/suppression adecuado.

El asistente todavía mantiene el tuning avanzado separado de la selección de feeds para evitar que un perfil “recomendado” desactive silenciosamente detecciones que pueden ser necesarias en otro entorno. La fuente de verdad debe seguir siendo explícita y auditable.

Referencias oficiales:

- Suricata rule management: `https://docs.suricata.io/en/latest/rule-management/suricata-update.html`
- suricata-update: `https://suricata-update.readthedocs.io/en/latest/`
- Source index OISF: `https://github.com/OISF/suricata-intel-index`
- Rule/SID documentation: `https://docs.suricata.io/en/latest/rules/meta.html`

El sensor continúa siendo **alert-only** en este workflow; gestionar más fuentes no lo convierte en IPS inline.

### Informes y evidencia

La consola prioriza una representación legible. Los informes persistentes mantienen más detalle técnico para poder conservarlos como evidencia:

```text
/var/lib/debian-ad-assistant/ids/reports/ids-report-*.txt
```

La opción `Daily local reports → View generated reports` valida que el fichero siga existiendo y sea legible antes de abrirlo; un fallo del pager o del fichero debe volver al menú como `WARN`, no finalizar el asistente.

`Export evidence` conserva las vistas técnicas y metadatos relevantes. La intención es separar:

```text
CONSOLE / OPERADOR
explicación, contexto, quién, qué servicio, siguiente paso

EVIDENCIA TXT / JSONL
campos técnicos, timestamps, firmas, timeline y datos para auditoría
```

### Event Center: vista humana frente a evidencia

El **AD Event Center** aplica la misma filosofía. Las opciones interactivas traducen la timeline a bloques del tipo:

```text
[WARN] 2026-10-01 13:02:10  Suricata IDS — Network IDS
       Subject : 10.20.30.40 -> 192.168.1.90
       Detail  : ET ...
       Meaning : una firma de Suricata coincidió; correlacionar antes de escalar
```

mientras que la exportación sigue guardando `timeline.txt` y `timeline.jsonl` técnicos para análisis posterior.

Esto no intenta ocultar datos: ofrece una capa de **triage humano** delante de la evidencia cruda.

### Windows

El control plane de Windows puede analizar `eve.json`, generar informes y mostrar un dashboard nativo cuando el entorno lo permite:

```powershell
.\windows-ad-assistant.ps1 -Mode IDS
```

La instalación de Suricata/Npcap en Windows se mantiene como una acción administrativa explícita; el script no instala silenciosamente un driver de captura de terceros en un Domain Controller.

La paridad funcional buscada entre Debian/Samba, RHEL y Windows incluye el mismo modelo conceptual: redes confiables, diferencia entre actividad y alerta, vista de operador, timeline humana, evidencia técnica y recuperación segura. La implementación concreta puede variar según las capacidades nativas de cada plataforma.

### Qué significa IDS aquí

La integración es principalmente **pasiva**:

- flujos y conexiones;
- telemetría;
- alertas;
- DNS;
- Kerberos;
- LDAP;
- SMB;
- TLS/SSH según plataforma/configuración.

No asumas que habilitar Suricata convierte el DC en un IPS o firewall inline.

---

<a id="backups-snapshots-y-recuperacion"></a>
## Backups, snapshots y recuperación

No todos los backups sirven para el mismo problema.

### Snapshot de cliente

Sirve para restaurar configuración local relacionada con un join:

- DNS;
- hostname;
- identidad/configuración local según plataforma;
- estado de lifecycle.

No es un backup de Active Directory.

### Backup de configuración del DC

Sirve para conservar evidencia y configuración antes de cambios.

No siempre es suficiente para reconstruir un dominio.

### Backup recuperable del dominio

Samba AD:

- utiliza las funciones de backup de dominio soportadas por Samba;
- conserva copias fuera del propio DC.

Windows AD DS:

- utiliza System State Backup;
- integra la estrategia con backup externo y pruebas de restauración.

### Operaciones de alto impacto

Antes de cambios como:

- decommission de un DC;
- cambios fuertes de Kerberos/LDAP;
- eliminación de objetos críticos;
- GPO de seguridad global;
- reparación de SYSVOL;
- migración de dominio;

crea un backup apropiado para la operación y verifica que sea restaurable.

---

<a id="hardening-y-compatibilidad"></a>
## Hardening y compatibilidad

El proyecto favorece un baseline compatible antes que una política extrema aplicada a ciegas.

Ejemplos de controles habituales:

- firewall activo y con política coherente;
- Defender donde corresponda;
- RDP con NLA;
- SMB signing y restricciones de protocolos heredados;
- reducción de LLMNR;
- logging de PowerShell;
- LDAP signing/channel binding según readiness;
- Kerberos AES/RC4 readiness;
- SMB y NTLM legacy awareness;
- hardening Samba equivalente donde la plataforma lo soporte.

Cambios con riesgo de compatibilidad no deberían aplicarse únicamente porque aparezcan en una guía de hardening. Valida primero clientes, appliances, service accounts y software heredado.

### CIS y otros benchmarks

Los asistentes pueden implementar controles alineados con buenas prácticas o benchmarks, pero **no certifican cumplimiento completo** de CIS, DISA STIG u otro estándar por sí solos.

Para una afirmación formal de compliance utiliza el benchmark, perfil y herramienta de evaluación correspondientes y conserva evidencia independiente.

---

<a id="virtualizacion-y-hosts-multi-nic"></a>
## Virtualización y hosts multi-NIC

Los laboratorios con varias interfaces son una fuente frecuente de problemas AD.

Ejemplo típico:

```text
NIC 1 → NAT / Internet
NIC 2 → red interna AD
NIC 3 → management
```

Recomendaciones:

- conoce qué interfaz transporta tráfico hacia el DNS/DC;
- evita que DHCP de una red secundaria inyecte un resolver público por encima del DNS AD;
- revisa métricas y rutas;
- en producción, separa claramente red de administración y red de servicio cuando la arquitectura lo requiera;
- no cambies routing de un host remoto sin una vía de recuperación.

Los asistentes de cliente utilizan selección de interfaz consciente de ruta y avisan cuando la NIC elegida no coincide con el camino esperado hacia Active Directory.

### VirtualBox / VMware / Hyper-V

En laboratorio, el DNS proporcionado por NAT puede resolver Internet pero no la zona AD. Esto no lo convierte en un DNS válido para un miembro del dominio.

Una configuración frecuente es:

```text
Cliente → DNS del DC → forwarder externo
```

No:

```text
Cliente → DC + DNS NAT + 8.8.8.8
```

---

<a id="troubleshooting"></a>
## Troubleshooting

Empieza por identificar la capa que falla.

### 1. DNS

Linux:

```bash
dig _ldap._tcp.dc._msdcs.corp.example.com SRV
realm discover corp.example.com
```

Windows:

```powershell
Resolve-DnsName _ldap._tcp.dc._msdcs.corp.example.com -Type SRV
nltest /dsgetdc:corp.example.com
```

### 2. Hora / Kerberos

Linux:

```bash
chronyc tracking
klist
```

Windows:

```powershell
w32tm /query /status
w32tm /stripchart /computer:dc01.corp.example.com /samples:3 /dataonly
```

### 3. Secure channel

Linux client:

```bash
adcli testjoin -D corp.example.com
```

Windows client:

```powershell
Test-ComputerSecureChannel
nltest /sc_verify:corp.example.com
```

### 4. Join de Windows

Windows registra información detallada de unión al dominio en:

```text
%SystemRoot%\debug\NetSetup.log
```

El Windows AD Client Assistant guarda evidencia asociada al snapshot e identifica errores comunes como:

- domain/DC discovery;
- credenciales rechazadas;
- access denied;
- protección moderna contra reutilización insegura de computer accounts.

Si el asistente muestra `JOIN_AMBIGUOUS`, utiliza:

```powershell
.\windows-ad-client-assistant.ps1 -Mode Recover
```

No borres el estado ni cambies DNS manualmente hasta determinar si Windows llegó a aceptar el join.

### 5. Samba AD DC

```bash
systemctl status samba-ad-dc --no-pager
samba-tool dbcheck --cross-ncs
samba-tool dns zonelist localhost -U Administrator
```

### 6. Windows Domain Controller

```powershell
dcdiag /q
repadmin /replsummary
Get-ADReplicationFailure -Target * -Scope Forest
```

---

<a id="rutas-de-estado-y-logs"></a>
## Rutas de estado y logs

### Samba AD Control Plane

```text
State : /var/lib/debian-ad-assistant
Logs  : /var/log/debian-ad-assistant
```

La ruta concreta de backups/reportes se muestra en el resumen de cada ejecución.

### Linux AD Client Assistant

```text
State     : /var/lib/ad-client-assistant
Snapshots : /var/backups/ad-client-assistant
Logs      : /var/log/ad-client-assistant
```

### Windows Server AD Control Plane

Por defecto:

```text
%ProgramData%\WindowsADControlPlane
```

Puede cambiarse mediante el parámetro `-ExportPath`.

### Windows AD Client Assistant

Por defecto:

```text
%ProgramData%\ADClientAssistant
```

Estructura principal:

```text
current.json     lifecycle activo
snapshots\       snapshots pre-join
logs\            log por ejecución
reports\         resumen JSON por ejecución
```

`current.json` representa una operación activa o una membresía gestionada. No lo elimines como método de recuperación; utiliza `Status`, `Restore` o `Recover`.

---

<a id="checklist-antes-de-produccion"></a>
## Checklist antes de producción

Antes de desplegar o modificar un entorno AD:

- [ ] backups externos disponibles y probados;
- [ ] consola/ILO/iDRAC/hipervisor disponible si vas a tocar red o firewall;
- [ ] hostname y dominio definitivos;
- [ ] IP estable en los Domain Controllers;
- [ ] DNS AD funcional;
- [ ] forwarding DNS validado si los clientes necesitan resolución externa;
- [ ] hora sincronizada;
- [ ] puertos AD alcanzables desde las redes de clientes;
- [ ] cuentas de administración y delegación revisadas;
- [ ] GPO probadas primero en una OU piloto;
- [ ] compatibilidad revisada antes de retirar RC4, SMB heredado o endurecer LDAP;
- [ ] join/leave de clientes validado incluyendo reboot;
- [ ] logs y reportes revisados después de la ejecución;
- [ ] segundo DC / estrategia de redundancia considerada para producción.

### Prueba mínima recomendada para un cliente

1. ejecutar `Audit`;
2. ejecutar join guiado;
3. reiniciar;
4. ejecutar `Status`;
5. validar inicio de sesión con un usuario de prueba;
6. comprobar DNS y secure channel;
7. ejecutar leave en un equipo de laboratorio;
8. reiniciar;
9. restaurar estado pre-join;
10. verificar que DNS/hostname local quedaron como antes.

No declares un flujo de lifecycle listo para producción hasta haber probado también el camino de recuperación.

---

<a id="estado-del-proyecto"></a>
## Estado del proyecto

El repositorio está en desarrollo activo.

Las herramientas están diseñadas con un enfoque conservador y orientado a recuperación, pero siguen administrando sistemas sensibles. La cobertura real depende de plataforma, versión, topología, GPO existentes y componentes externos.

Antes de actualizar una versión ya desplegada:

1. revisa el diff;
2. ejecuta auditoría;
3. prueba en laboratorio o piloto;
4. conserva la versión anterior durante la validación;
5. vuelve a ejecutar los instaladores de shortcuts/CLI cuando corresponda.

---

## Licencia

MIT. Consulta [LICENSE](./LICENSE).
