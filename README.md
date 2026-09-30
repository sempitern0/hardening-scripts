# Hardening Scripts · Active Directory Control Planes

[![Status](https://img.shields.io/badge/status-active%20development-0A7EA4)](#estado-del-proyecto)
[![License](https://img.shields.io/badge/license-MIT-green)](./LICENSE)
[![Debian](https://img.shields.io/badge/Debian-13-A81D33?logo=debian&logoColor=white)](#debian-samba-ad)
[![Ubuntu](https://img.shields.io/badge/Ubuntu%20Server-26.04%20LTS-E95420?logo=ubuntu&logoColor=white)](#debian-samba-ad)
[![Samba AD](https://img.shields.io/badge/Samba-AD%20DC-1B4D7A)](#debian-samba-ad)
[![Windows Server](https://img.shields.io/badge/Windows%20Server-2019%20%7C%202022%20%7C%202025-0078D4?logo=windows&logoColor=white)](#windows-ad)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)](#windows-ad)
[![Security](https://img.shields.io/badge/security-audit--first%20%7C%20backup--first-success)](#modelo-seguridad)
[![Navigation](https://img.shields.io/badge/navigation-0%3DBack%20%7C%20H%3DHome-blueviolet)](#navegacion)

El repositorio reúne **dos control planes de Domain Controller y dos asistentes reversibles de cliente** para desplegar, auditar, operar, endurecer, recuperar y migrar entornos **Active Directory** sobre **Samba AD DC en Debian/Ubuntu**, **AD DS nativo en Windows Server** y sus equipos miembro Linux/Windows.

El objetivo no es convertir Active Directory en un «one-click installer». El objetivo es disponer de un **control plane operativo y repetible** que detecte el estado actual, explique qué va a cambiar, cree evidencia y backups cuando corresponde, solicite confirmación en operaciones sensibles y valide el resultado.

> **Importante:**
> Estos scripts administran componentes críticos de identidad, DNS, Kerberos, Group Policy, firewall y servicios de dominio. Pruébalos primero en laboratorio, conserva acceso de recuperación y mantén backups externos y restaurables.

---

## Tabla de contenidos

- [¿A quién va dirigido?](#audiencia)
- [Qué incluye el repositorio](#contenido-repositorio)
- [Filosofía del proyecto](#filosofia)
- [Modelo de seguridad](#modelo-seguridad)
- [Navegación de los menús](#navegacion)
- [Elección rápida del asistente](#eleccion-asistente)
- [Debian / Ubuntu · Samba Active Directory Control Plane](#debian-samba-ad)
  - [Requisitos y targets](#requisitos-linux)
  - [Descarga y ejecución](#descarga-linux)
  - [Modos del script](#modos-linux)
  - [CLI instalables](#cli-linux)
  - [Dependencias y paquetes](#dependencias-linux)
  - [Bootstrap de un DC nuevo](#bootstrap-linux)
  - [Administración diaria](#operacion-linux)
  - [Remote Operations Center](#remote-ops-linux)
  - [DNS y resolver local](#dns-linux)
  - [Kerberos, Samba y hardening](#hardening-linux)
  - [Group Policy · guía integrada](#gpo-linux)
  - [Ubuntu ADSys y GPO](#ubuntu-adsys)
  - [Network IDS / Suricata](#ids-linux)
  - [Decommission / reset](#reset-linux)
  - [Migración de dominio](#migracion-linux)
  - [Directorios, logs y estado](#estado-linux)
  - [Configuración manual post-instalación](#postinstalacion-linux)
- [Windows Server Active Directory Control Plane](#windows-ad)
  - [Requisitos y targets](#requisitos-windows)
  - [Descarga y ejecución](#descarga-windows)
  - [Modos PowerShell](#modos-windows)
  - [Provisioning de un bosque nuevo](#provisioning-windows)
  - [Administración diaria](#operacion-windows)
  - [Remote Operations Center](#remote-ops-windows)
  - [Hardening de host y protocolos AD](#hardening-windows)
  - [Backup y recuperación](#backup-windows)
  - [Dependencias y servicing](#dependencias-windows)
  - [Network IDS / Suricata](#ids-windows)
  - [Decommission / reset](#reset-windows)
  - [Migración de dominio](#migracion-windows)
  - [Configuración manual post-instalación](#postinstalacion-windows)
- [Client Join Assistants · unión reversible](#client-join-assistants)
  - [Linux AD Client Assistant](#linux-client-assistant)
  - [Windows AD Client Assistant](#windows-client-assistant)
  - [Modelo de rollback](#client-rollback)
- [Unir equipos al dominio · procedimiento manual](#clientes)
- [VirtualBox, VMware y laboratorios multi-NIC](#virtualizacion)
- [Alta disponibilidad](#alta-disponibilidad)
- [Troubleshooting](#troubleshooting)
- [Preguntas frecuentes](#faq)
- [Validación antes de producción](#validacion-produccion)
- [Referencias](#referencias)
- [Licencia](#licencia)
- [Estado del proyecto](#estado-proyecto)

---

## Compatibilidad del README

Este documento evita extensiones exclusivas de un único renderer de Markdown.

Los avisos utilizan blockquotes estándar, por ejemplo:

```markdown
> **Importante:** revisa el cambio antes de aplicarlo.
```

La tabla de contenidos utiliza anclas HTML ASCII explícitas para reducir diferencias entre
GitHub, GitLab, VS Code, Obsidian, CommonMark, MarkText y otros previews. Los bloques de código,
tablas, listas y enlaces usan sintaxis Markdown ampliamente soportada.

<a id="audiencia"></a>
# ¿A quién va dirigido?

Estos asistentes están pensados principalmente para:

- administradores de sistemas y Active Directory;
- profesionales DevOps/SRE que administran infraestructura híbrida;
- ingenieros de seguridad y hardening;
- MSP y consultores que necesitan procedimientos repetibles;
- responsables IT de pymes y medianas organizaciones;
- laboratorios empresariales, homelabs avanzados y entornos de formación técnica;
- equipos que necesiten inventario, evidencia, backups y procedimientos de cambio antes de tocar un controlador de dominio.

Se presupone familiaridad básica con:

```text
Active Directory
DNS
Kerberos
LDAP
Group Policy
redes IPv4
firewall
backup y recuperación
PowerShell o Bash
```

No está orientado a sustituir el conocimiento del administrador. Cuando una decisión depende de la arquitectura —por ejemplo, direccionamiento, DNS corporativo, trusts, migración de dominio, cifrado Kerberos o LDAP channel binding— el asistente intenta **detectar y asistir**, no adivinar.

---

<a id="contenido-repositorio"></a>
# Qué incluye el repositorio

El repositorio mantiene dos control planes de DC y dos asistentes reversibles de clientes:

| Archivo | Plataforma | Línea actual | Función |
|---|---|---:|---|
| `debian-ad-assistant.sh` | Debian / Ubuntu Server | 5.1.x | Samba AD DC, DNS, Kerberos, Chrony, GPO, dependencias, IDS, hardening, backup, reset, migración y operación diaria |
| `windows-server-ad-assistant.ps1` | Windows Server | 1.7.x | AD DS, DNS, GPO, hardening, dependencias, IDS/EVE, backup, demotion/reset, provisioning y migración |
| `linux-ad-client-assistant.sh` | Linux client/member | 1.1.x | snapshot, dependencias, DNS AD, realmd/SSSD/adcli, join, validación, leave y rollback |
| `windows-ad-client-assistant.ps1` | Windows client/member | 1.1.x | snapshot DNS/hostname, discovery, Add-Computer, secure-channel checks, leave y rollback |

Revisiones utilizadas para esta edición:

```text
DC Debian      : 5.1.0-remote-ops-ui
DC Windows     : 1.7.0-remote-ops-ui
Client Linux   : 1.1.3-resolver-convergence
Client Windows : 1.1.0-resilient
```

La antigua guía separada:

```text
DEBIAN-AD-Assistant-GPO-Guide-v4.4.0.md
```

se ha **integrado en este README**. Puede conservarse como documento histórico, pero la referencia
operativa actual es [Group Policy · guía integrada](#gpo-linux).

Cambios recientes relevantes:

```text
Debian
  Chrony discovery/syntax/synchronization fixes
  Kerberos audit no interactivo
  selectors e idempotencia de membresías
  dependency lifecycle (ad-deps)
  domain reset center
  Suricata IDS (ad-ids)
  Samba listener/KDC boot self-heal
  revisión pipefail/SIGPIPE de rutas operativas
  fallos Kerberos/GPO contenidos sin expulsar del menú
  Remote Operations Center y navegación compacta por workspaces

Windows
  selectors e idempotencia
  native dependency center
  supported AD DS demotion/reset
  Suricata EVE analytics + Windows Forms dashboard
  límites de recuperación para errores dentro de menús interactivos
  Remote Operations Center WinRM/SSH y navegación compacta por workspaces

Client assistants v1.1
  selección de interfaz consciente de ruta y multi-NIC
  preflight de todos los DNS AD antes de modificar el resolver local
  readiness de puertos AD sin dependencias nuevas
  lifecycle explícito alrededor de reboot/leave
  validación post-join reforzada
  rollback más completo y diagnóstico accionable
```

Verifica siempre la versión real antes de ejecutar:

```bash
head -n 12 debian-ad-assistant.sh
```

```powershell
Get-Content .\windows-server-ad-assistant.ps1 -TotalCount 25
```

---

<a id="filosofia"></a>
# Filosofía del proyecto

Ambos asistentes siguen el mismo patrón:

```text
DETECT
  ↓
AUDIT
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

No:

```text
"hardening"
    ↓
copiar 200 valores del registro o smb.conf
    ↓
esperar que nada se rompa
```

Principios:

1. detectar antes de modificar;
2. no reprovisionar silenciosamente infraestructura existente;
3. distinguir instalación nueva de operación diaria;
4. mantener la vía de administración;
5. crear backups antes de operaciones sensibles;
6. exigir confirmación explícita para cambios de alto impacto;
7. validar después de aplicar;
8. utilizar herramientas nativas siempre que sea posible;
9. no almacenar credenciales innecesariamente;
10. separar hardening compatible de hardening agresivo;
11. tratar GPO y configuración como código;
12. conservar evidencia de ejecución;
13. diseñar para recuperación;
14. no considerar un servidor listo hasta superar un reinicio y una validación posterior;
15. no afirmar cumplimiento CIS completo cuando solo se ha validado un subconjunto de controles.

---

<a id="modelo-seguridad"></a>
# Modelo de seguridad

Los asistentes son **audit-first** y **backup-first**.

Operaciones destructivas o de impacto alto pueden requerir escribir literalmente:

```text
APPLY
```

Algunas áreas son deliberadamente conservadoras:

- no se ejecuta `sysvolreset` automáticamente solo porque una GPO falle;
- no se deshabilita RC4 Kerberos a ciegas;
- no se fuerza SMB3 encryption en todos los clientes;
- no se cambia una IP activa automáticamente durante un provisioning remoto;
- no se guardan contraseñas administrativas dentro de scripts de migración;
- no se realiza un rename de dominio de producción como si fuera un simple cambio DNS;
- no se habilita una GPO en producción sin dar al operador control sobre link, scope y estado.

> **Advertencia:**
> Un controlador de dominio es infraestructura de identidad. Un cambio aparentemente pequeño en DNS, hora, Kerberos, LDAP o SYSVOL puede impedir el inicio de sesión de toda la organización.

---

<a id="navegacion"></a>
# Navegación de los menús

Los dos asistentes utilizan navegación consistente:

```text
[0] Back
[H] Main menu
```

- `0`: vuelve un nivel;
- `H`: salta directamente al control plane principal.

En Debian:

```text
sudo adctl
```

abre el **AD/DC Main Control Plane completo**.

Para administración diaria reducida:

```text
sudo ad-ops
```

abre usuarios, grupos, equipos, permisos, GPO y operaciones habituales.

---

<a id="eleccion-asistente"></a>
# Elección rápida del asistente

```text
¿El DC será Samba sobre Linux?
        │
        ├── Sí → debian-ad-assistant.sh
        │
        └── No
             │
             └── Windows Server AD DS
                    → windows-server-ad-assistant.ps1
```

Ambos pueden convivir en laboratorios, pero **no son intercambiables**. Cada uno utiliza el modelo operativo y herramientas nativas de su plataforma.

---

<a id="debian-samba-ad"></a>
# Debian / Ubuntu · Samba Active Directory Control Plane

<a id="requisitos-linux"></a>
## Requisitos y targets Linux

Targets principales:

- Debian 13;
- Ubuntu Server 26.04 LTS;
- Bash;
- systemd;
- Samba AD DC;
- `samba-tool`;
- Chrony;
- IPv4 como camino principal de administración/AD.

También puede funcionar en derivados Debian de forma `best-effort`.

### Requisitos operativos recomendados

Antes de provisionar:

- hostname definitivo;
- IP estable o plan claro para hacerla persistente inmediatamente después;
- DNS domain/realm decidido;
- acceso `root`/`sudo`;
- conectividad hacia repositorios;
- hora razonablemente correcta;
- backup si el servidor ya contiene datos;
- acceso por consola/hipervisor si vas a tocar red o firewall remotamente.

Para producción se recomienda NIC cableada. Wi-Fi puede funcionar técnicamente, pero un Domain Controller se beneficia de conectividad estable y predecible.

---

<a id="descarga-linux"></a>
## Descarga y ejecución Linux

Repositorio:

```text
https://github.com/sempitern0/hardening-scripts
```

### Método recomendado: descargar, revisar y ejecutar

```bash
curl -fsSLo /tmp/debian-ad-assistant.sh \
  https://raw.githubusercontent.com/sempitern0/hardening-scripts/main/debian-ad-assistant.sh

less /tmp/debian-ad-assistant.sh

sudo bash /tmp/debian-ad-assistant.sh --audit
```

Para abrir la consola completa:

```bash
sudo bash /tmp/debian-ad-assistant.sh --manage
```

### Con `wget`

```bash
wget -O /tmp/debian-ad-assistant.sh \
  https://raw.githubusercontent.com/sempitern0/hardening-scripts/main/debian-ad-assistant.sh

chmod +x /tmp/debian-ad-assistant.sh
sudo /tmp/debian-ad-assistant.sh --audit
```

### Clonando el repositorio

```bash
git clone https://github.com/sempitern0/hardening-scripts.git
cd hardening-scripts

bash -n debian-ad-assistant.sh
sudo bash ./debian-ad-assistant.sh --audit
```

### Una sola línea · audit

```bash
curl -fsSL \
  https://raw.githubusercontent.com/sempitern0/hardening-scripts/main/debian-ad-assistant.sh \
  | sudo bash -s -- --audit
```

### Una sola línea · consola principal

```bash
curl -fsSL \
  https://raw.githubusercontent.com/sempitern0/hardening-scripts/main/debian-ad-assistant.sh \
  | sudo bash -s -- --manage
```

### Una sola línea · bootstrap

```bash
curl -fsSL \
  https://raw.githubusercontent.com/sempitern0/hardening-scripts/main/debian-ad-assistant.sh \
  | sudo bash -s -- --bootstrap
```

El asistente abre `/dev/tty` para mantener los prompts interactivos incluso si stdin contiene el propio script.

> **Consejo:**
> Para producción es mejor descargar una tag/release concreta, revisar el archivo y verificar SHA-256. Ejecutar `main` directamente es cómodo para laboratorio, pero `main` puede cambiar.

### Verificar SHA-256

```bash
sha256sum debian-ad-assistant.sh
```

Guarda el hash aprobado en tu sistema de cambios o CMDB.

---

<a id="modos-linux"></a>
## Modos del script Linux

Ayuda:

```bash
sudo bash ./debian-ad-assistant.sh --help
```

| Modo | Finalidad |
|---|---|
| sin argumento | modo interactivo |
| `--audit` | inventario y evidencia read-only |
| `--validate` | validación funcional de AD/DC |
| `--bootstrap` | provisionar un nuevo Samba AD DC o reanudar de forma segura |
| `--manage` | control plane principal completo |
| `--backup` | backup online del dominio |
| `--status` | estado operativo compacto |
| `--admin` / `--ops` | consola diaria reducida |
| `--users` | administración de usuarios |
| `--groups` | administración de grupos |
| `--computers` | inventario/administración de equipos |
| `--permissions` | membresías y ACL del directorio |
| `--gpo` | consola Group Policy |
| `--security` | seguridad del host/DC |
| `--samba-security` / `--samba-hardening` | Samba + Kerberos security center |
| `--kerberos` / `--kerberos-security` | seguridad Kerberos |
| `--migration` / `--migrate` | Domain Migration Center |
| `--reset-domain` / `--decommission` | decommission/reset destructivo con recovery bundle |
| `--dependencies` / `--deps` | inventario, reparación y actualización acotada de dependencias |
| `--ids` / `--suricata` / `--network-ids` | IDS pasivo Suricata y analítica EVE |
| `--remote` / `--remote-ops` / `--remote-control` | Remote Operations Center |
| `--install-cli` | instalar/refrescar comandos `ad-*` |
| `--cli-info` | mostrar comandos instalados |
| `--no-color` | desactivar ANSI colors |
| `--help` | ayuda |

`--ids-daily` es un target no interactivo utilizado por el timer de reports IDS.

Ejemplos:

```bash
sudo bash ./debian-ad-assistant.sh --validate
sudo bash ./debian-ad-assistant.sh --gpo
sudo bash ./debian-ad-assistant.sh --dependencies
sudo bash ./debian-ad-assistant.sh --ids
sudo bash ./debian-ad-assistant.sh --reset-domain
```

---

<a id="cli-linux"></a>
## CLI instalables Linux

Instalar o refrescar:

```bash
sudo bash ./debian-ad-assistant.sh --install-cli
```

Control plane instalado:

```text
/usr/local/libexec/debian-ad-assistant
```

Shortcuts:

| Comando | Función |
|---|---|
| `adctl` | Main Control Plane completo |
| `ad-ops` | operaciones diarias reducidas |
| `ad-users` | usuarios |
| `ad-groups` | grupos |
| `ad-computers` | equipos |
| `ad-permissions` | membresías y ACL |
| `ad-gpo` | GPO |
| `ad-security` | seguridad del host/DC |
| `ad-samba` | Samba + Kerberos |
| `ad-kerberos` | Kerberos security center |
| `ad-migrate` | migración |
| `ad-reset` | decommission/reset |
| `ad-deps` | dependencias y paquetes |
| `ad-ids` | IDS Suricata |
| `ad-remote` | operaciones remotas controladas sobre endpoints del dominio |
| `ad-audit` | auditoría |
| `ad-validate` | validación funcional |
| `ad-status` | estado rápido |
| `ad-backup` | backup del dominio |
| `ad-tools` | catálogo/estado de shortcuts |

> **Nota:** después de sustituir el script por una versión nueva vuelve a ejecutar
> `--install-cli`; de lo contrario `/usr/local/libexec/debian-ad-assistant` puede seguir apuntando
> a una copia anterior.

<a id="dependencias-linux"></a>
## Dependencias y paquetes Linux

El control plane evita gestores externos y mantiene un perfil mínimo.

Core de un DC existente:

```text
samba-ad-dc
krb5-user
chrony
ldb-tools
smbclient
python3
iproute2
bind9-dnsutils / dnsutils equivalente
```

Bootstrap añade cuando la distribución lo separa:

```text
samba-ad-provision
```

Opcionales:

```text
ufw
fail2ban
suricata
suricata-update
```

No son dependencias del core:

```text
pip
snap
PPA
curl installers
third-party APT repositories
```

Acceso:

```bash
sudo ad-deps
```

Funciones:

```text
Dependency inventory
Install missing required
Update required packages
Optional security tools
```

La actualización utiliza el conjunto explícito de dependencias y `--only-upgrade`; no convierte la
operación en un `dist-upgrade`/`full-upgrade` del servidor.

Las consultas de versión/candidate/origen son informativas y no deben terminar el control plane por
un fallo de metadatos APT. Para componentes Samba, el asistente puede proponer un backup previo y
vuelve a validar el servicio después de actualizar.

---

<a id="bootstrap-linux"></a>
## Bootstrap de un DC nuevo

Ejecuta:

```bash
sudo bash ./debian-ad-assistant.sh --bootstrap
```

El asistente:

1. detecta distribución y runtime;
2. detecta topología de red;
3. distingue WAN, AD y management interface;
4. instala dependencias;
5. valida hostname y dirección;
6. prepara Chrony;
7. persiste identidad de bootstrap antes de provisionar;
8. ejecuta `samba-tool domain provision`;
9. configura Samba DNS;
10. prepara el resolver local;
11. instala la configuración Kerberos generada por Samba;
12. establece boot ordering;
13. crea OUs/grupos base opcionales;
14. configura administrador delegado;
15. prepara GPO opcionales;
16. configura UFW/Fail2ban/sysctl cuando se autoriza;
17. instala el guard de salud de listeners post-boot;
18. valida AD/DNS/Kerberos/LDAP/SMB/SYSVOL;
19. genera checklist post-instalación.

### Protección frente a reprovisioning

Si existe:

```text
/var/lib/samba/private/sam.ldb
```

el asistente no debe tratar el host como un DC vacío.

No elimines `sam.ldb`, `secrets.ldb` o SYSVOL para «volver a intentar» un bootstrap.

---

<a id="operacion-linux"></a>
## Administración diaria Linux

Main Control Plane:

```bash
sudo adctl
```

La interfaz principal usa **workspaces con letras estables** en vez de ampliar indefinidamente el
menú numérico:

```text
[O] Daily operations       [D] Directory
[P] Policy / GPO           [S] Security
[R] Remote operations      [I] Insights / IDS
[M] Maintenance            [A] All modules
[0] Exit
```

`[A] All modules` conserva el mapa numérico completo como vía de descubrimiento y compatibilidad.
Las letras están pensadas para operación por memoria muscular.

La cabecera compacta muestra en cada workspace:

```text
domain / DC / IP / interface
operator / local-or-SSH session

AD
DNS:53
KRB:88
LDAP:389
SMB:445
KPWD:464
TIME
IDS
```

Los colores se reservan para significado operativo:

```text
green    healthy / normal operation
cyan     directory / information
blue     remote endpoint operations
magenta  policy / advanced control
yellow   attention / maintenance
red      destructive / degraded
gray     optional / unavailable
```

Consola diaria:

```bash
sudo ad-ops
```

Atajos:

```text
[U] Users       [G] Groups
[C] Computers   [A] Access / delegation
[P] GPO         [R] Remote operations
[S] Security    [V] Validate
[B] Backup      [M] Migration
```

Los números históricos siguen aceptándose donde se han mantenido como aliases internos.

### Usuarios

```bash
sudo ad-users
```

Soporta, entre otras operaciones:

- listar e inspeccionar;
- crear mediante wizard;
- nombre/apellidos/display name;
- UPN y correo;
- descripción/departamento/puesto/empresa/oficina/teléfonos;
- profile path, script path, home directory y drive;
- RFC2307;
- OU destino;
- membresías mediante selector;
- cambio de contraseña al siguiente logon;
- reset de contraseña;
- enable/disable/unlock;
- cuenta sensible/no delegable;
- edición avanzada.

### Grupos

```bash
sudo ad-groups
```

Operaciones de creación, inventario y membresías con selectores.

### Equipos

```bash
sudo ad-computers
```

Inventario de cuentas de equipo y presencia de red `best-effort`.

### Permisos

```bash
sudo ad-permissions
```

Membresías y operaciones avanzadas `DS ACL`.

---

<a id="remote-ops-linux"></a>
## Remote Operations Center Linux

Acceso:

```bash
sudo ad-remote
```

o:

```bash
sudo ./debian-ad-assistant.sh --remote
```

Menú:

```text
[T] Target / readiness     [S] Active sessions
[M] Message users          [L] Log off session
[D] Diagnostics            [V] Service control
[R] Restart endpoint       [X] Shut down endpoint
[C] Cancel shutdown        [E] Export evidence
[G] Guardrails / setup
```

El target se elige desde el inventario de equipos de AD; el operador no necesita volver a escribir
el hostname cuando el directorio ya lo conoce.

Transportes:

```text
Debian DC -> Linux endpoint
  OpenSSH

Debian DC -> Windows endpoint
  OpenSSH para sesiones/mensajes/diagnóstico/control de servicio
  Samba RPC como fallback limitado para restart/shutdown/cancel
```

El control plane de Debian **no añade un stack WinRM adicional** solo para conseguir paridad con
Windows. Si un endpoint Windows no tiene OpenSSH, el panel sigue pudiendo evaluar reachability y,
cuando RPC/SMB y permisos lo permiten, realizar operaciones de energía limitadas. Para administración
Windows completa se prefiere el control plane Windows.

Acciones destructivas:

```text
logoff
service restart
restart
shutdown
```

usan confirmación de alto impacto y se registran en:

```text
/var/lib/debian-ad-assistant/remote-ops/operations.tsv
```

Evidencia:

```text
/var/lib/debian-ad-assistant/remote-ops/evidence/
```

No se expone un shell remoto arbitrario desde el menú normal. La recomendación de delegación es:

```text
Windows endpoints → JEA / roles limitados
Linux endpoints   → sudoers limitado
network           → SSH/WinRM solo desde redes de management
```

---

<a id="dns-linux"></a>
## DNS y resolver local Linux

Active Directory depende de DNS. El modelo esperado es:

```text
Clientes del dominio
        │
        ▼
  Samba DNS del DC
        │
        ├── zona AD / SRV → Samba
        │
        └── Internet      → dns forwarder
```

El propio DC debe usar Samba DNS una vez validado.

Estado esperado:

```bash
ls -l /etc/resolv.conf
cat /etc/resolv.conf
```

Debe ser un **archivo regular persistente**, no un symlink roto hacia un stub de `systemd-resolved`.

Ejemplo:

```text
nameserver 127.0.0.1
search corp.example.com
options timeout:2 attempts:2
```

El asistente puede reparar esta transición:

```bash
sudo ad-security
```

y elegir:

```text
Repair local resolver
```

### Verificaciones

```bash
dig @127.0.0.1 dc01.corp.example.com A

dig @127.0.0.1 \
  _ldap._tcp.dc._msdcs.corp.example.com SRV

dig @127.0.0.1 \
  _kerberos._tcp.corp.example.com SRV

getent hosts dc01.corp.example.com
getent hosts github.com
```

También:

```bash
sudo ad-validate
```

### DNS de los clientes

Los clientes AD deben usar DNS del dominio:

```text
DNS client → DC01
           → DC02 (si existe)
```

No mezcles como DNS alternativo:

```text
8.8.8.8
1.1.1.1
9.9.9.9
router doméstico
VirtualBox NAT DNS
```

Un cliente puede elegir ese resolver externo y dejar de encontrar los registros SRV de Active Directory.

Los forwarders públicos/corporativos se configuran **en el DNS del DC**, no en cada miembro del dominio.

---

<a id="hardening-linux"></a>
## Kerberos, Samba y hardening Linux

Acceso directo:

```bash
sudo ad-samba
```

o:

```bash
sudo ad-kerberos
```

Módulos:

```text
Full security audit
Safe Samba baseline
Kerberos config audit
Repair krb5.conf
Kerberos crypto readiness
AES-only KDC
Restore KDC defaults
Signed domain time
Configure signed time
Samba transport audit
```

### Safe Samba baseline

El perfil compatible intenta reforzar:

```text
LDAP strong auth
LDAP SASL wrapping
SMB signing
SMB2 minimum
IPC signing
NTLMv2-only
LANMAN disabled
raw NTLMv2 disabled
NT4 crypto disabled
guest mapping disabled
weak KDC session-key behavior
```

No obliga automáticamente:

```text
SMB3-only
SMB encryption required globally
AES-only Kerberos
```

porque esos cambios pueden romper equipos y appliances heredados.

### Kerberos crypto readiness

Antes de eliminar RC4 se inventarían:

```text
computer accounts
service accounts con SPN
msDS-SupportedEncryptionTypes
tickets actuales cuando existe un ccache válido
```

La auditoría de seguridad es **no interactiva**: no debe solicitar una contraseña Kerberos ni
abortar solo porque el ccache aislado del asistente esté vacío. El inventario local continúa;
`kvno` y los enctypes del ticket se consideran evidencia adicional.

El asistente utiliza un ccache Kerberos aislado por ejecución para operaciones autenticadas. Un
`kinit` ejecutado previamente por el usuario que invoca `sudo` no equivale automáticamente al
cache privado de la ejecución privilegiada.

Clasificaciones:

```text
AES_READY
RC4_ONLY
RC4_AND_AES
IMPLICIT_DEFAULT
OTHER
```

En Samba, valores como:

```text
kdc supported enctypes = 0
kdc default domain supported enctypes = 0
```

representan comportamiento automático/default de Samba; no significan «cero algoritmos
habilitados». La interfaz los presenta como valores automáticos para evitar interpretaciones
erróneas.

No habilites AES-only solo porque el menú lo permita. Revisa primero el informe.

### `/etc/krb5.conf`

El DC utiliza la configuración generada por Samba como referencia:

```text
/var/lib/samba/private/krb5.conf
```

El asistente puede restaurarla a:

```text
/etc/krb5.conf
```

si no existe una necesidad deliberada de configuración multi-realm personalizada.

Pruebas:

```bash
kinit Administrator@CORP.EXAMPLE.COM
klist
klist -e

kvno ldap/dc01.corp.example.com
kvno cifs/dc01.corp.example.com
```

### Tiempo firmado

Kerberos depende de una hora consistente.

El asistente distingue explícitamente:

```text
package   = chrony
daemon    = /usr/sbin/chronyd
client    = /usr/bin/chronyc
systemd   = chrony.service
```

No confundas el nombre del proceso (`chronyd`) con la unidad systemd (`chrony.service`).

Diagnóstico manual:

```bash
dpkg-query -W chrony
dpkg -L chrony | grep -E '/(chronyd|chronyc)$'

sudo /usr/sbin/chronyd   -p   -f /etc/chrony/chrony.conf

systemctl status chrony.service --no-pager -l

chronyc tracking
chronyc sources -v
chronyc activity
```

Después de reiniciar Chrony puede aparecer temporalmente:

```text
Leap status : Not synchronised
```

La herramienta utiliza `chronyc waitsync` antes de clasificarlo como fallo. Si existe una fuente
alcanzable o seleccionada y Chrony aún está convergiendo, se informa como estado transitorio.

Prueba manual equivalente:

```bash
chronyc waitsync 12 0 0 5
echo $?
```

Un retorno `0` indica que Chrony alcanzó estado sincronizado dentro del periodo de espera.

El asistente detecta `ntp_signd` de Samba y puede configurar Chrony para respuestas MS-SNTP
firmadas cuando la versión instalada lo soporta.

---

<a id="gpo-linux"></a>
## Group Policy · guía integrada

Acceso:

```bash
sudo ad-gpo
```

Esta sección absorbe la antigua **DEBIAN AD Assistant — GPO Operations Guide v4.4.0** y las
mejoras operativas posteriores.

### Menú y flujo

Operaciones principales:

```text
List GPOs + GUIDs + status
Inspect GPO
Create GPO
Platform GPO catalog
JSON policy library
GPO status
List linked containers
Link / update
Remove link
Backup
Readiness
Delete GPO
Legacy baseline pair
Paths & manual
```

Ruta habitual:

```text
sudo ad-gpo
  1  List GPOs + GUIDs + status
  4  Platform GPO catalog
  5  JSON policy library
  6  GPO status
  7  List linked containers
  8  Link/update
  9  Remove link
 10  Backup
 11  Readiness
 14  Paths & manual
```

### Paths persistentes

```text
/var/lib/debian-ad-assistant/gpo/
├── builtin/
│   └── windows/
│       ├── sec-powershell-logging.json
│       ├── sec-disable-llmnr.json
│       ├── sec-smb-guest.json
│       ├── sec-rdp-nla.json
│       ├── sec-screen-lock.json
│       ├── sec-disable-alwaysinstallelevated.json
│       ├── sec-legal-notice.json
│       └── sec-workstation-starter-combined.json
├── custom/
│   └── example-custom-policy.json
└── GPO-GUIDE.md
```

`builtin/` es gestionado por el asistente. Para editar:

```text
builtin → copy to custom → edit → validate → load
```

### Formato JSON Samba

```json
[
  {
    "keyname": "SOFTWARE\\Policies\\Example\\Product",
    "valuename": "SettingName",
    "class": "MACHINE",
    "type": "REG_DWORD",
    "data": 1
  }
]
```

`class`:

```text
MACHINE
USER
BOTH
```

Validar:

```bash
python3 -m json.tool policy.json
```

Merge:

```bash
samba-tool gpo load '{GUID}' --content=policy.json
```

Replace de Registry policy content:

```bash
samba-tool gpo load '{GUID}' \
  --content=policy.json \
  --replace
```

Eliminar valores:

```bash
samba-tool gpo remove '{GUID}' \
  --content=remove.json
```

El asistente automatiza estas operaciones y hace backup de la GPO seleccionada cuando corresponde.

### Almacenamiento real de una GPO

La biblioteca JSON es material fuente. La GPO real se divide entre:

```text
LDAP
  CN={GUID},CN=Policies,CN=System,<domain DN>

SYSVOL
  <SYSVOL>/<domain>/Policies/{GUID}/
```

No construyas ni elimines manualmente esos directorios para intentar reparar una creación fallida.

### Estado enable/disable

AD usa `flags`:

| Valor | Estado |
|---:|---|
| `0` | enabled |
| `1` | user configuration disabled |
| `2` | computer configuration disabled |
| `3` | all settings disabled |

El estado es independiente del link:

```text
enabled + unlinked
enabled + linked
computer disabled
user disabled
all disabled
```

Consulta:

```text
ad-gpo → GPO status
```

### Staging recomendado

El starter pack puede prepararse como:

```text
ALL_DISABLED + UNLINKED
```

Después:

1. inspeccionar;
2. enlazar a una OU de prueba;
3. habilitar solo la parte machine/user necesaria;
4. probar en un cliente;
5. ampliar scope.

### Consumidores de GPO/policy

```text
Windows
  → Registry / Windows CSE

Ubuntu ADSys
  → Ubuntu.admx / Ubuntu.adml + ADSys mapping

Samba/winbind Linux
  → samba-gpupdate / Samba policy managers

SSSD
  → principalmente GPO access-control evaluation
```

No asumas que un JSON Registry Windows tiene significado directo para Linux.

### Ubuntu ADSys

Generar plantillas en un cliente Ubuntu con una versión ADSys compatible:

```bash
mkdir -p ~/adsys-admx
cd ~/adsys-admx

adsysctl policy admx lts-only
```

o:

```bash
adsysctl policy admx all
```

Produce:

```text
Ubuntu.admx
Ubuntu.adml
```

Central Store:

```text
<SYSVOL>/<domain>/Policies/PolicyDefinitions/Ubuntu.admx
<SYSVOL>/<domain>/Policies/PolicyDefinitions/en-US/Ubuntu.adml
```

Menú:

```text
ad-gpo
  → Platform GPO catalog
  → Ubuntu ADSys clients
```

### Samba Linux / winbind

Dependiendo de la versión Samba:

```bash
samba-tool gpo manage smb_conf ...
samba-tool gpo manage access ...
samba-tool gpo manage openssh ...
samba-tool gpo manage sudoers ...
samba-tool gpo manage scripts ...
samba-tool gpo manage motd ...
```

El asistente comprueba capacidades de runtime cuando es posible.

### SSSD

SSSD puede evaluar GPO para **access control**. Eso no equivale a ejecutar las CSE Registry de
Windows. El asistente utiliza inventario LDAP/SYSVOL/GPT.INI como diagnóstico de compatibilidad.

### Readiness y troubleshooting

Antes de crear/modificar:

```text
ad-gpo
  → GPO readiness
```

y:

```bash
sudo samba-tool ntacl sysvolcheck
```

Si aparece:

```text
Could not find a DC for domain
```

revisa primero DNS/resolver/DC locator.

Si aparece:

```text
ACCESS_DENIED
```

revisa:

```bash
klist
samba-tool user getgroups <usuario>
samba-tool gpo aclcheck
samba-tool ntacl sysvolcheck
```

No ejecutes `sysvolreset` únicamente porque una operación GPO falle.

El wrapper GPO intenta conservar el menú y capturar evidencia para distinguir:

```text
DNS/DC locator
Kerberos
delegation/ACL
SYSVOL
unsupported Samba capability
```

La consola GPO ya no exige un ticket Kerberos solo para abrir el menú. Las operaciones que sí
necesitan autenticación intentan obtener el ticket en ese momento; si falla, la operación se
cancela de forma limpia y el control vuelve al menú.

La creación de GPO sigue dependiendo del comportamiento y capacidades de la versión Samba
instalada; esta guía no presupone que un error actual de GPO haya quedado resuelto por otras
correcciones del control plane.

---

<a id="ubuntu-adsys"></a>
## Ubuntu ADSys y GPO

ADSys es específico de Ubuntu y **no es requisito para unir Linux al dominio**. La unión genérica está en [Unir equipos al dominio](#clientes).

En un Ubuntu cliente con ADSys:

```bash
sudo apt install adsys
```

Generar templates:

```bash
mkdir -p ~/adsys-admx
cd ~/adsys-admx

adsysctl policy admx lts-only
```

o:

```bash
adsysctl policy admx all
```

Genera:

```text
Ubuntu.admx
Ubuntu.adml
```

El asistente detecta el SYSVOL y prepara el Central Store:

```text
<SYSVOL>/<dominio>/Policies/PolicyDefinitions/Ubuntu.admx

<SYSVOL>/<dominio>/Policies/PolicyDefinitions/en-US/Ubuntu.adml
```

Accede mediante:

```bash
sudo ad-gpo
```

```text
Platform GPO catalog
  → Ubuntu ADSys clients
```

Mantén GPO de Ubuntu y Windows separadas siempre que sea posible.

---

<a id="ids-linux"></a>
## Network IDS / Suricata

Suricata es opcional y no forma parte del runtime mínimo AD.

```bash
sudo ad-ids
```

Postura por defecto:

```text
passive IDS
AF_PACKET
sin inline drop
sin NFQUEUE enforcement
```

Paths gestionados:

```text
/etc/suricata/debian-ad-assistant.yaml
/etc/systemd/system/suricata.service.d/90-debian-ad-assistant.conf
/var/log/suricata/eve.json
```

Funciones:

```text
readiness
install/repair
passive configuration
sensor health
security summary
recent alerts
AD protocol intelligence
rule update
daily local reports
evidence export
disable integration
```

La analítica EVE presta especial atención a DNS, Kerberos, SMB/NTLMSSP, alertas y packet drops.

Reports:

```text
/var/lib/debian-ad-assistant/ids/reports/
```

Un IDS con drops elevados no debe interpretarse como evidencia de ausencia de ataques.

<a id="reset-linux"></a>
## Decommission / reset Linux

```bash
sudo ad-reset
```

Flujo:

```text
assessment
  ↓
DC topology
  ↓
explicit destructive confirmation
  ↓
external recovery bundle
  ↓
offline Samba backup when available
  ↓
local AD/DC state cleanup
  ↓
restore assistant-managed host configuration
  ↓
validate
  ↓
reboot
```

Si existen otros DC, el asistente no hace un wipe local a ciegas: exige primero una democión
correcta del DC.

Recovery root:

```text
/var/backups/debian-ad-assistant/
```

No se purgan indiscriminadamente paquetes y se conserva la configuración de IP/red salvo cambios
que el control plane pueda atribuirse de forma segura.

---

<a id="migracion-linux"></a>
## Migración de dominio Linux

Acceso:

```bash
sudo ad-migrate
```

El Migration Center diferencia:

```text
Branding / mail / web only
DC replacement in same domain
New AD domain
New forest
Advanced renamed-domain backup
```

Un cambio de IP/DC manteniendo el mismo dominio **no requiere rejoin de todos los clientes**.

Un cambio real de dominio:

```text
old.example.com
      ↓
new.example.com
```

sí cambia la relación de confianza de los equipos y requiere una migración/rejoin controlado.

DNS alias/CNAME no sustituye esa operación.

El asistente puede:

- exportar inventario;
- comprobar readiness de equipos;
- inspeccionar trusts;
- generar paquete PowerShell de migración Windows;
- generar helper Linux `realmd/SSSD`;
- hacer backup de GPO;
- crear backup del dominio;
- mostrar capacidades y limitaciones de `samba-tool domain backup rename`.

Las credenciales no se incrustan en los paquetes generados.

---

<a id="estado-linux"></a>
## Directorios, logs y estado Linux

Persistencia:

```text
/var/lib/debian-ad-assistant/
```

Logs:

```text
/var/log/debian-ad-assistant/
```

Cada ejecución:

```text
/var/lib/debian-ad-assistant/runs/<timestamp-pid>/
```

Incluye según el modo:

```text
backup/
domain-backup/
krb5cc
GPO diagnostics
migration exports
evidence
```

Configuración persistente:

```text
/var/lib/debian-ad-assistant/config.env
```

Checklist:

```text
/var/lib/debian-ad-assistant/POST-INSTALL.txt
```

GPO:

```text
/var/lib/debian-ad-assistant/gpo/
```

Migración:

```text
/var/lib/debian-ad-assistant/migration/
```

IDS:

```text
/var/lib/debian-ad-assistant/ids/
```

Recovery bundles:

```text
/var/backups/debian-ad-assistant/
```

---

<a id="postinstalacion-linux"></a>
# Configuración manual post-instalación Linux

`--bootstrap` termina el provisioning, pero un DC nuevo **no debe considerarse production-ready automáticamente**.

## 1. Hacer persistente la IP

Primero:

```bash
ip -br addr
ip route
```

El AD interface debe tener dirección estable.

### Ubuntu / Netplan

Identifica el archivo:

```bash
ls -l /etc/netplan/
sudo cat /etc/netplan/*.yaml
```

Ejemplo conceptual:

```yaml
network:
  version: 2
  ethernets:
    enp1s0:
      dhcp4: false
      addresses:
        - 192.168.10.10/24
      routes:
        - to: default
          via: 192.168.10.1
```

> **Importante:**
> El asistente gestiona el resolver local del DC para usar Samba DNS. No reinstales a ciegas un symlink de `systemd-resolved` después de configurar Netplan.

Prueba remota segura:

```bash
sudo netplan try
```

Luego:

```bash
ip -br addr
ip route
```

### Multi-NIC

Regla habitual:

```text
WAN_IFACE
  → default gateway

AD_IFACE
  → IP estable
  → normalmente sin segundo default gateway
```

---

## 2. Validar `/etc/resolv.conf`

```bash
ls -l /etc/resolv.conf
cat /etc/resolv.conf
```

No debe apuntar a un stub inexistente.

Esperado:

```text
nameserver 127.0.0.1
search corp.example.com
```

Comprobar:

```bash
getent hosts "$(hostname -f)"

dig +short SRV \
  _ldap._tcp.dc._msdcs.corp.example.com
```

---

## 3. Revisar DNS forwarder

```bash
sudo testparm -s \
  --parameter-name='dns forwarder'
```

Prueba:

```bash
dig @127.0.0.1 github.com A
```

Si falla Internet pero la zona AD funciona, revisa el forwarder.

---

## 4. Configurar clientes para usar DNS AD

Ejemplo:

```text
Client DNS 1 = 192.168.10.10   DC01
Client DNS 2 = 192.168.10.11   DC02
```

No:

```text
DNS 1 = DC
DNS 2 = 8.8.8.8
```

---

## 5. Validar Kerberos

```bash
kdestroy || true
kinit Administrator@CORP.EXAMPLE.COM
klist
klist -e
```

Prueba service tickets:

```bash
kvno ldap/dc01.corp.example.com
kvno cifs/dc01.corp.example.com
```

---

## 6. Validar hora

```bash
chronyc tracking
chronyc sources -v
```

Después:

```bash
sudo ad-samba
```

y revisa `Signed domain time`.

---

## 7. Validar Samba AD

```bash
sudo systemctl status samba-ad-dc --no-pager

sudo samba-tool domain info "$(hostname -I | awk '{print $1}')"

sudo samba-tool dbcheck --cross-ncs

sudo samba-tool ntacl sysvolcheck
```

Luego:

```bash
sudo ad-validate
```

---

## 8. Revisar firewall

```bash
sudo ufw status numbered
sudo ufw status verbose
```

Confirma que:

- SSH solo está disponible desde la red/IP administrativa;
- DNS/Kerberos/LDAP/SMB están limitados al scope AD;
- el DC no está exponiendo servicios de dominio por una WAN no confiable.

---

## 9. Revisar GPO

```bash
sudo ad-gpo
```

Primero:

```text
GPO readiness
```

Después:

```bash
sudo samba-tool ntacl sysvolcheck
```

No ejecutes `sysvolreset` únicamente porque una creación de GPO falle.

---

## 10. Crear backup fuera del DC

```bash
sudo ad-backup
```

Después copia el backup a almacenamiento independiente.

Recomendaciones:

- varias generaciones;
- almacenamiento off-host;
- acceso restringido;
- prueba de restore en laboratorio;
- RPO/RTO documentado.

---

## 11. Reinicio de aceptación

```bash
sudo reboot
```

Al volver:

```bash
sudo ad-status
sudo ad-validate
sudo ad-samba
```

El control plane instala un guard post-boot para listeners críticos:

```text
53
88
389
445
464
```

Si `samba-ad-dc.service` está activo pero incompleto, hace **un único restart controlado** y
revalida.

```bash
systemctl status debian-ad-samba-health.service --no-pager -l

journalctl \
  -u debian-ad-samba-health.service \
  -b \
  --no-pager

ss -lntup |
  grep -E ':(53|88|389|445|464)([[:space:]]|$)'
```

Si necesita autorrepararse en cada boot, conserva el journal y busca la causa del arranque
incompleto; el restart no debe ocultar una degradación recurrente.

---

<a id="windows-ad"></a>
# Windows Server Active Directory Control Plane

<a id="requisitos-windows"></a>
## Requisitos y targets Windows

Targets:

- Windows Server 2019;
- Windows Server 2022;
- Windows Server 2025;
- Windows PowerShell 5.1+.

El script utiliza:

```text
ActiveDirectory
GroupPolicy
DnsServer
ADDSDeployment
Defender
NetSecurity
Storage/BitLocker cmdlets
dcdiag
repadmin
wbadmin
```

según estén disponibles.

Debe ejecutarse **como Administrador**.

El propio script declara:

```powershell
#requires -RunAsAdministrator
```

---

<a id="descarga-windows"></a>
## Descarga y ejecución Windows

Canonical repository filename:

```text
windows-server-ad-assistant.ps1
```

### Método recomendado

Abre **Windows PowerShell como Administrador**:

```powershell
$Url = 'https://raw.githubusercontent.com/sempitern0/hardening-scripts/main/windows-server-ad-assistant.ps1'
$Path = 'C:\Temp\windows-server-ad-assistant.ps1'

New-Item C:\Temp -ItemType Directory -Force | Out-Null
Invoke-WebRequest $Url -OutFile $Path

Get-FileHash $Path -Algorithm SHA256
notepad $Path

Unblock-File $Path
& $Path -Mode Audit
```

### Una sola línea · audit

Desde una consola elevada:

```powershell
$p="$env:TEMP\windows-server-ad-assistant.ps1"; `
iwr 'https://raw.githubusercontent.com/sempitern0/hardening-scripts/main/windows-server-ad-assistant.ps1' -OutFile $p; `
Unblock-File $p; `
& $p -Mode Audit
```

En una única línea literal:

```powershell
$p="$env:TEMP\windows-server-ad-assistant.ps1"; iwr 'https://raw.githubusercontent.com/sempitern0/hardening-scripts/main/windows-server-ad-assistant.ps1' -OutFile $p; Unblock-File $p; & $p -Mode Audit
```

### Una sola línea · control plane interactivo

```powershell
$p="$env:TEMP\windows-server-ad-assistant.ps1"; iwr 'https://raw.githubusercontent.com/sempitern0/hardening-scripts/main/windows-server-ad-assistant.ps1' -OutFile $p; Unblock-File $p; & $p
```

### Clonar el repositorio

Si Git está instalado:

```powershell
git clone https://github.com/sempitern0/hardening-scripts.git
Set-Location .\hardening-scripts

Unblock-File .\windows-server-ad-assistant.ps1
.\windows-server-ad-assistant.ps1 -Mode Audit
```

### Execution Policy

No cambies permanentemente la política del servidor solo para ejecutar el asistente.

Primero intenta:

```powershell
Unblock-File .\windows-server-ad-assistant.ps1
```

Si la política local permite `RemoteSigned`, suele ser suficiente.

Para una sesión deliberada:

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
.\windows-server-ad-assistant.ps1 -Mode Audit
```

Al cerrar esa consola, el scope `Process` desaparece.

---

<a id="modos-windows"></a>
## Modos PowerShell

```powershell
.\windows-server-ad-assistant.ps1 -Mode <Mode>
```

| Mode | Función |
|---|---|
| `Interactive` | Main Control Plane |
| `Audit` | auditoría host + AD |
| `Validate` | validación funcional DC |
| `Harden` | hardening interactivo |
| `Backup` | configuration change-set |
| `ADAdmin` | consola Active Directory |
| `Provision` | nuevo bosque / primer DC |
| `Migration` | Domain Migration Center |
| `DirectorySecurity` | Kerberos/LDAP/SMB protocol security |
| `Dependencies` | features/módulos oficiales y servicing status |
| `Reset` | democión soportada + cleanup post-reboot |
| `IDS` | Suricata/EVE + dashboard nativo cuando hay GUI |
| `IDSReport` | target no interactivo de Task Scheduler |
| `RemoteOps` | Remote Operations Center |

Parámetros adicionales:

```powershell
-ExportPath
-NoColor
-AllowRemoteFirewallChange
```

Ejemplos:

```powershell
.\windows-server-ad-assistant.ps1 -Mode Validate
.\windows-server-ad-assistant.ps1 -Mode Dependencies
.\windows-server-ad-assistant.ps1 -Mode DirectorySecurity
.\windows-server-ad-assistant.ps1 -Mode IDS
.\windows-server-ad-assistant.ps1 -Mode Reset
```

> **Advertencia:** `-AllowRemoteFirewallChange` no elimina confirmaciones; únicamente permite
> proponer determinados cambios globales durante una sesión remota.

---

<a id="provisioning-windows"></a>
## Provisioning de un bosque nuevo

```powershell
.\windows-server-ad-assistant.ps1 -Mode Provision
```

El wizard bloquea provisioning si:

- el equipo ya es Domain Controller;
- el equipo ya está unido a un dominio;
- no detecta IPv4 persistente/estática.

Solicita:

```text
DNS domain
NetBIOS domain
DSRM password
```

Instala si hace falta:

```powershell
Install-WindowsFeature AD-Domain-Services `
  -IncludeManagementTools
```

Valida primero:

```powershell
Test-ADDSForestInstallation
```

y finalmente utiliza:

```powershell
Install-ADDSForest
```

El servidor reiniciará durante la promoción.

---

<a id="operacion-windows"></a>
## Administración diaria Windows

Modo:

```powershell
.\windows-server-ad-assistant.ps1 -Mode ADAdmin
```

La navegación principal también usa workspaces compactos:

```text
[O] Daily operations       [D] Directory
[P] Policy / DNS           [S] Security
[R] Remote operations      [I] Insights / IDS
[M] Maintenance            [A] All modules
[0] Exit
```

La cabecera muestra el rol del servidor y badges de:

```text
NTDS / AD
DNS
KDC / Kerberos
Netlogon
ADWS
SMB
WinRM
Suricata
```

`[A] All modules` mantiene el mapa numérico histórico. Los submenús diarios usan letras estables
para reducir navegación y mantener memoria muscular.

### Usuarios

Wizard de creación y edición con:

- UPN;
- display name;
- email;
- department;
- title;
- company;
- office;
- telephone;
- OU;
- enable/disable;
- password change at next logon;
- password never expires;
- cannot change password;
- memberships mediante selector.

### Group Policy

El assistant permite:

- inventario con GUID;
- creación;
- inspección;
- link/unlink;
- backup;
- catálogo de seguridad;
- selección profesional de domain root/OUs.

### DNS

Utiliza el módulo `DnsServer` cuando está disponible para inventario y operación sobre zonas/registros.

### DC health

Utiliza evidencia de:

```text
dcdiag
repadmin
DNS
SYSVOL
FSMO
replication
```

---

<a id="remote-ops-windows"></a>
## Remote Operations Center Windows

Modo directo:

```powershell
.\windows-server-ad-assistant.ps1 -Mode RemoteOps
```

Desde la interfaz:

```text
[R] Remote operations
```

Menú:

```text
[T] Target / readiness     [S] Active sessions
[M] Message users          [L] Log off session
[D] Diagnostics            [V] Service control
[R] Restart endpoint       [X] Shut down endpoint
[C] Cancel shutdown        [E] Export evidence
[K] Alternate credential   [J] Guardrails / JEA
```

### Windows endpoints

Ruta preferida:

```text
AD computer selector
   ↓
FQDN
   ↓
WinRM / PowerShell Remoting
   ↓
Kerberos when domain conditions permit
```

El panel utiliza `quser`, `msg`, `logoff` y `shutdown` donde las primitivas Windows nativas ofrecen
la operación directa; PowerShell Remoting se utiliza para diagnóstico y operaciones más ricas.

Una credencial alternativa puede mantenerse **solo en memoria durante la sesión**. No se serializa
en el estado del control plane.

### Linux endpoints

El Windows Server actúa como cliente OpenSSH:

```text
Windows management server
  → Microsoft OpenSSH Client
  → sshd Linux
  → delegated sudo
```

Si falta OpenSSH Client, el panel puede ofrecer instalar la capability oficial de Windows después
de confirmación.

### Seguridad operacional

No se incluye un botón de “ejecutar cualquier comando como SYSTEM/root”.

La política del panel es:

```text
select known endpoint
  ↓
known operation
  ↓
show impact
  ↓
explicit confirmation for destructive action
  ↓
execute
  ↓
audit
```

Registro:

```text
C:\ProgramData\WindowsADControlPlane\remote-ops\operations.tsv
```

Evidencia:

```text
C:\ProgramData\WindowsADControlPlane\remote-ops\evidence\
```

Para delegación real se recomienda JEA en Windows y sudoers limitado en Linux, evitando usar
`Domain Admins` como permiso genérico de helpdesk.

---

<a id="hardening-windows"></a>
## Hardening de host y protocolos AD Windows

### Host security

Modo:

```powershell
.\windows-server-ad-assistant.ps1 -Mode Harden
```

o menú `Host security`.

Audita/remedia selectivamente:

- Windows Firewall;
- Microsoft Defender;
- RDP/NLA;
- SMB;
- SMBv1;
- guest authentication;
- LLMNR;
- PowerShell Script Block Logging;
- PowerShell Module Logging;
- BitLocker/TPM/Secure Boot cuando aplica;
- administradores;
- Windows LAPS;
- updates/evidence.

### Directory Protocol Security

Acceso:

```powershell
.\windows-server-ad-assistant.ps1 -Mode DirectorySecurity
```

Incluye:

```text
Full protocol audit
Require SMB signing
Require LDAP signing
LDAP channel binding
Kerberos RC4 readiness
Explicit AES-only KDC default
```

#### SMB signing

En un DC/servidor privilegiado revisa:

```powershell
Get-SmbServerConfiguration
Get-SmbClientConfiguration
```

La remediación puede requerir signing inbound y outbound.

#### LDAP signing

Antes de exigir LDAP signing o channel binding:

1. inventaría aplicaciones LDAP;
2. revisa appliances y software legacy;
3. monitoriza eventos;
4. prueba en un DC/lab;
5. despliega por fases.

No actives channel binding agresivo porque «es más seguro» sin conocer tus clientes LDAP.

#### Kerberos / RC4

El asistente analiza:

```text
msDS-SupportedEncryptionTypes
service accounts con SPN
computer accounts
KDC hardening events
DefaultDomainSupportedEncTypes
```

Antes de fijar explícitamente:

```text
0x18 = AES128 + AES256
```

Las versiones de Windows Server actualizadas en 2026 ya incluyen cambios importantes de enforcement RC4. Revisa siempre el estado real y los eventos antes de añadir overrides manuales.

---

<a id="backup-windows"></a>
## Backup y recuperación Windows

Menú:

```text
Backup & Recovery
```

Incluye:

```text
Configuration change-set
DC system-state backup
GPO backup
Run/backup paths
```

Ruta por defecto:

```text
C:\ProgramData\WindowsADControlPlane
```

Cada ejecución crea:

```text
runs\<timestamp-pid>\
backup\
```

Logs:

```text
control-plane-<timestamp-pid>.log
```

Report:

```text
control-plane-report-<timestamp-pid>.json
```

System State utiliza `wbadmin` cuando está disponible.

> **Importante:**
> No guardes la única copia del System State en el mismo disco físico/VM que el DC.

---

<a id="dependencias-windows"></a>
## Dependencias y servicing Windows

El control plane utiliza componentes Microsoft:

```text
AD-Domain-Services
RSAT-AD-Tools
GPMC
RSAT-DNS-Server
Windows-Server-Backup
```

Módulos principales:

```text
ActiveDirectory
GroupPolicy
DnsServer
ADDSDeployment
ServerManager
NetSecurity
```

No requiere:

```text
Chocolatey
winget
NuGet
PowerShell Gallery modules
PSWindowsUpdate
```

```powershell
.\windows-server-ad-assistant.ps1 -Mode Dependencies
```

La aplicación de updates del sistema operativo queda en Windows Update/WSUS/WUfB/Configuration
Manager o el mecanismo corporativo equivalente.

<a id="ids-windows"></a>
## Network IDS / Suricata Windows

```powershell
.\windows-server-ad-assistant.ps1 -Mode IDS
```

El módulo puede detectar:

```text
Suricata
Npcap
suricata.yaml
eve.json
service/capture posture
```

y ofrece:

```text
sensor health
security summary
recent alerts
Kerberos/SMB/NTLMSSP intelligence
daily reports
native Windows Forms dashboard
```

No instala silenciosamente drivers de captura en un Domain Controller.

En Desktop Experience utiliza `System.Windows.Forms`; en Server Core o sesiones no interactivas
cae a la consola.

<a id="reset-windows"></a>
## Decommission / reset Windows

```powershell
.\windows-server-ad-assistant.ps1 -Mode Reset
```

No borra manualmente `NTDS.dit` ni SYSVOL.

```text
assessment
  ↓
recovery bundle
  ↓
optional System State
  ↓
FSMO transfer if needed
  ↓
Test-ADDSDomainControllerUninstallation
  ↓
Uninstall-ADDSDomainController
  ↓
reboot
  ↓
post-demotion cleanup
```

Recovery root:

```text
C:\WindowsAD-ControlPlane-Recovery\
```

El DNS Server role no se elimina automáticamente porque puede contener zonas que no pertenecen a
Active Directory.

---

<a id="migracion-windows"></a>
## Migración de dominio Windows

Modo:

```powershell
.\windows-server-ad-assistant.ps1 -Mode Migration
```

Diferencia:

```text
Branding only
DC replacement
New AD domain
New forest
Domain rename assessment
```

Puede:

- guardar plan;
- exportar usuarios/grupos/equipos/OUs/GPO/DNS/trusts;
- evaluar readiness de equipos;
- inventariar trusts;
- generar paquete `Add-Computer`/`netdom`;
- hacer backup de GPO;
- evaluar `rendom`;
- lanzar System State backup.

Un rename real de AD no es una redirección DNS.

---

<a id="postinstalacion-windows"></a>
# Configuración manual post-instalación Windows

## 1. IP estática

Antes de crear AD:

```powershell
Get-NetIPConfiguration
Get-NetIPAddress -AddressFamily IPv4
Get-NetRoute -DestinationPrefix '0.0.0.0/0'
```

El modo `Provision` exige dirección persistente.

Ejemplo genérico:

```powershell
New-NetIPAddress `
  -InterfaceAlias 'Ethernet' `
  -IPAddress 192.168.10.20 `
  -PrefixLength 24 `
  -DefaultGateway 192.168.10.1
```

No copies este ejemplo sin adaptar interfaz/red.

---

## 2. DNS del propio DC

En un primer/único DC, tras validar el servicio DNS, el servidor debe utilizar DNS AD y no resolvers públicos directamente en la NIC.

Revisar:

```powershell
Get-DnsClientServerAddress -AddressFamily IPv4
```

En un entorno multi-DC decide la secuencia de resolvers según tu diseño.

Configurar:

```powershell
Set-DnsClientServerAddress `
  -InterfaceAlias 'Ethernet' `
  -ServerAddresses 192.168.10.20
```

Para dos DC:

```powershell
Set-DnsClientServerAddress `
  -InterfaceAlias 'Ethernet' `
  -ServerAddresses 192.168.10.21,192.168.10.20
```

No uses un DNS público como fallback en una NIC miembro de AD.

---

## 3. DNS forwarders

Consultar:

```powershell
Get-DnsServerForwarder
```

Configurar según política corporativa:

```powershell
Set-DnsServerForwarder `
  -IPAddress 1.1.1.1,9.9.9.9
```

En empresa puede ser preferible utilizar resolvers internos/upstream en lugar de servicios públicos.

---

## 4. Validar AD después del reboot

```powershell
dcdiag /v
repadmin /replsummary
repadmin /showrepl

Resolve-DnsName `
  _ldap._tcp.dc._msdcs.corp.example.com `
  -Type SRV
```

Después:

```powershell
.\windows-server-ad-assistant.ps1 -Mode Validate
```

---

## 5. Revisar hora

```cmd
w32tm /query /status
w32tm /query /configuration
```

En un bosque con varios DC, la fuente externa de hora debe diseñarse alrededor de la jerarquía de tiempo AD, especialmente el PDC Emulator.

---

## 6. Guardar DSRM de forma segura

La contraseña Directory Services Restore Mode es un secreto de recuperación.

Debe estar protegida según la política de credenciales/secret management de la organización.

No la guardes dentro del script ni en README internos.

---

## 7. Crear System State backup

En un DC:

```text
Backup & Recovery
  → DC system-state backup
```

También puedes validar disponibilidad:

```powershell
Get-Command wbadmin
```

---

## 8. Auditar protocolos antes de enforcement

```powershell
.\windows-server-ad-assistant.ps1 `
  -Mode DirectorySecurity
```

Primero ejecuta:

```text
Full protocol audit
```

antes de:

```text
Require LDAP signing
LDAP channel binding
AES-only KDC
```

---

## 9. Reboot de aceptación

Después de hardening:

```powershell
Restart-Computer
```

Al volver:

```powershell
.\windows-server-ad-assistant.ps1 -Mode Audit
.\windows-server-ad-assistant.ps1 -Mode Validate
```

---

<a id="client-join-assistants"></a>
# Client Join Assistants · unión reversible

Los asistentes de cliente automatizan el procedimiento descrito manualmente en la siguiente sección
sin convertir el join en una operación opaca.

Modelo v1.1:

```text
detect host / OS / current identity state
  ↓
collect domain + AD DNS
  ↓
direct AD DNS preflight (zero local changes)
  ↓
route-aware NIC selection
  ↓
snapshot pre-join
  ↓
install/verify the same minimal dependency set
  ↓
configure AD DNS
  ↓
system resolver + DC discovery
  ↓
AD port + time readiness
  ↓
Kerberos / credential preflight
  ↓
join
  ↓
immediate acceptance
  ↓
reboot lifecycle
  ↓
post-reboot acceptance
```

Rollback:

```text
clean domain leave
  ↓
restore DNS behavior
  ↓
restore hostname when changed
  ↓
restore local identity files/settings
  ↓
optional removal of assistant-installed packages
  ↓
reboot
```

Principios:

- no se almacenan passwords;
- no se añaden repositorios de terceros;
- v1.1 no aumenta el conjunto base de dependencias de los asistentes;
- los DNS AD se consultan directamente antes de modificar el resolver local;
- DNS se cambia únicamente después de crear snapshot;
- el asistente conserva los datos necesarios para devolver la máquina a su estado anterior;
- una unión fallida intenta restaurar DNS/hostname automáticamente;
- dejar el dominio y borrar configuración local son operaciones distintas;
- no se simula una desunión Windows mediante edición manual del Registry;
- no se elimina automáticamente una cuenta de equipo AD si el leave soportado ha fallado.

<a id="linux-client-assistant"></a>
## Linux AD Client Assistant

Archivo:

```text
linux-ad-client-assistant.sh
```

Uso:

```bash
chmod +x linux-ad-client-assistant.sh

sudo ./linux-ad-client-assistant.sh
```

Modos:

```bash
sudo ./linux-ad-client-assistant.sh --audit
sudo ./linux-ad-client-assistant.sh --join
sudo ./linux-ad-client-assistant.sh --status
sudo ./linux-ad-client-assistant.sh --leave
sudo ./linux-ad-client-assistant.sh --restore
sudo ./linux-ad-client-assistant.sh --snapshots
```

Familias con instalación automática de paquetes:

```text
Debian / Ubuntu / derivados APT
RHEL / Fedora / Rocky / Alma / derivados DNF/YUM
```

Stack mínimo:

```text
realmd
SSSD
adcli
Kerberos
NSS/PAM
DNS diagnostic tools
```

El asistente usa únicamente los repositorios ya configurados por la distribución. No añade PPA,
COPR, repositorios vendor ni `curl | sh`.

En distribuciones no reconocidas el modo genérico queda limitado a sistemas **systemd** y puede
continuar si las herramientas necesarias ya existen:

```text
realm
adcli
kinit
klist
getent
systemctl
hostnamectl
ip
```

No se añaden dependencias ni se intenta reconfigurar automáticamente OpenRC, runit o SysV.

### Readiness y resiliencia v1.1

La revisión Linux `1.1.3-resolver-convergence` conserva las mismas dependencias que `1.1.2` y añade
diagnóstico/reparación del camino entre el gestor de red y el resolver real del sistema.

Un cliente AD **no necesita IP estática** para unirse al dominio. DHCP puede seguir gestionando
dirección, gateway y rutas; el requisito es que el resolver efectivo del cliente utilice DNS AD
para localizar el dominio.

El assistant distingue ahora:

```text
network configuration owner
  NetworkManager / systemd-resolved / resolv.conf

actual system resolver
  systemd-resolved / NetworkManager resolv.conf / direct resolv.conf
```

Esto cubre el caso en el que NetworkManager acepta correctamente `192.168.x.x` como DNS AD pero
`dig`, libc o `realmd` continúan utilizando un `/etc/resolv.conf` desconectado o un
`systemd-resolved` sin la información per-link.

Cuando el DNS AD responde directamente pero el resolver del host no converge, el flujo es:

```text
direct @AD-DNS SRV query        PASS
NetworkManager profile          PASS
  ↓
wait for resolver convergence
  ↓
systemd-resolved per-link sync
  ↓
flush caches
  ↓
system resolver SRV query
```

Si `systemd-resolved` puede descubrir AD pero `/etc/resolv.conf` no apunta al resolver activo, el
assistant muestra el diagnóstico y puede reparar explícitamente el symlink. La modificación es
reversible porque `/etc/resolv.conf` ya forma parte del snapshot pre-join.

La revisión mantiene además la selección de cuenta administrativa al final del flujo y la
recuperación transaccional de intentos de join incompletos.

Antes de tocar DNS, el wizard realiza un **preflight directo** contra todos los servidores AD DNS
introducidos. Cada uno debe responder al locator:

```text
_ldap._tcp.dc._msdcs.<domain>
```

La selección de NIC ya no depende únicamente de la primera default route. El assistant considera la
ruta efectiva hacia el primer DNS AD y, cuando hay varias interfaces, presenta un selector con:

```text
interface
IPv4/prefix
route metric
network manager
suggested AD route
```

Esto cubre mejor:

```text
Ethernet + Wi-Fi
VPN
VirtualBox / VMware multi-NIC
management VLAN
bridges / bonds
```

Después de aplicar DNS valida sin añadir utilidades nuevas:

```text
DNS/TCP 53
Kerberos/TCP 88
LDAP/TCP 389
SMB/TCP 445        # warning si no está disponible
```

El join usa un **Kerberos credential cache privado por ejecución**. El password sigue siendo
interactivo y no se persiste.

### Hostname y computer account

v1.1 separa dos conceptos:

```text
system hostname
AD computer name / NetBIOS
```

El nombre de cuenta de equipo se valida a un máximo de 15 caracteres y se pasa explícitamente a
`realm join --computer-name`. Un hostname Linux más largo ya no tiene que convertirse implícitamente
en el nombre de cuenta AD.

### Acceptance post-join

Un `realm join` exitoso ya no equivale por sí solo a `HEALTHY`.

La aceptación comprueba:

```text
realm membership
sssctl config-check         # cuando existe
sssd.service active
adcli testjoin
host principal in /etc/krb5.keytab
system resolver AD SRV
optional domain-user lookup
```

Estados operativos:

```text
JOIN_PENDING_REBOOT
JOINED
JOINED_DEGRADED
```

Si la cuenta de máquina se creó pero SSSD o la validación posterior fallan, el assistant **no restaura
DNS a ciegas**. Mantiene AD DNS y el snapshot para poder reparar o realizar un leave limpio.

### Backends DNS

En máquinas virtuales con adaptador puente, DHCP es válido y normalmente preferible para clientes.
No es necesario crear una IP estática en Netplan únicamente para hacer el domain join. El bridge
debe permitir alcanzar los DC/DNS y el cliente debe resolver el dominio mediante esos DNS.

Detección automática:

```text
NetworkManager
systemd-resolved
direct /etc/resolv.conf fallback
```

NetworkManager:

```text
snapshot connection name + UUID
snapshot ipv4/ipv6 DNS policy and DNS priority
disable DHCP DNS for AD resolution
set DC DNS
set search domain
prefer the AD DNS connection for resolver ordering
reapply interface without reconnect when possible
```

`systemd-resolved`:

```text
managed resolved.conf.d drop-in
per-link resolvectl DNS/domain
reversible snapshot
```

El fallback de `/etc/resolv.conf` requiere confirmación explícita porque la persistencia de ese
archivo depende de cómo administre la red la distribución.

### Credencial de join e identity mapping

`Administrator` vuelve a ser el valor por defecto para mantener el flujo normal de un dominio recién
creado. La cuenta **no queda fijada**: el wizard pregunta justo en el límite final de autenticación,
después de validar DNS, red, hora y puertos AD.

```text
DOMAIN CREDENTIAL

Default account: Administrator
Press Enter to use the default, or type another delegated/enabled AD account.

AD account authorized to join this computer to the domain [Administrator]:
```

Por tanto:

```text
Enter
  → Administrator

Godzilla
  → Godzilla

join-operator@CORP.EXAMPLE.COM
  → explicit delegated account
```

El asistente obtiene un ticket Kerberos aislado para la identidad seleccionada y expone tanto
`KRB5CCNAME` como `KRB5_CCACHE` al proceso `realm`. La contraseña sigue siendo interactiva y no se
persiste. El `leave` conserva el mismo comportamiento: `Administrator` por defecto con posibilidad
de introducir otra cuenta.

Si el join devuelve `Insufficient permissions to modify computer account`, el asistente distingue
ese caso y orienta a revisar un objeto de equipo preexistente/stale o los permisos delegados antes
de repetir el join.

### Recuperación de un join interrumpido antes de crear membership

v1.1.2 trata explícitamente el caso en el que un intento instala `sssd-tools`/SSSD pero termina
antes de inicializar correctamente SSSD. Ese estado podía dejar:

```text
sss_cache installed
/etc/sssd/sssd.conf missing
/var/lib/sss/db/config.ldb missing
no realm membership
```

y provocar mensajes de `sss_cache` al ejecutar herramientas locales de usuarios.

El snapshot guarda ahora también el estado previo de `sssd.service`. Mientras la membership AD no
haya sido confirmada, todos los fallos posteriores al snapshot usan un rollback unificado:

```text
failure / Ctrl+C / TERM
  ↓
private Kerberos cache cleanup
  ↓
restore DNS/network
  ↓
restore krb5 / keytab / SSSD / NSS / PAM
  ↓
restore hostname
  ↓
restore previous SSSD enabled/active state
```

Si el intento había instalado paquetes que no existían antes, el asistente ofrece además, con
respuesta recomendada `Y`, eliminar **solo esos paquetes**. No ejecuta `autoremove`.

Si el proceso anterior terminó de forma abrupta y dejó residuos, el siguiente `--join` detecta el
patrón `sss_cache` sin `sssd.conf/config.ldb`, localiza el último snapshot del asistente y ofrece:

```text
[1] Repair local identity state from the snapshot
[2] Keep the current residue and continue
[0] Cancel
```

Esto no se aplica si `adcli testjoin` demuestra que la machine account sigue siendo válida: en ese
caso el equipo se considera potencialmente unido/degradado y no se elimina SSSD automáticamente.

Una vez que `realm join` devuelve éxito, la transacción cambia a `MEMBERSHIP_COMMITTED`. Desde ese
punto un fallo posterior de SSSD o de acceptance **no** restaura DNS/identidad a ciegas; se conserva
el estado `JOINED_DEGRADED` para reparación o leave limpio.

El wizard pregunta:

```text
automatic SID → UID/GID mapping
```

o:

```text
RFC2307/POSIX attributes from AD
```

La segunda opción solo debe elegirse cuando el dominio ya mantiene correctamente `uidNumber`,
`gidNumber` y el resto de atributos POSIX necesarios.

### Home directories y autorización

La creación automática de homes es opcional.

El access policy también se mantiene separado del join:

```text
keep default
permit user
permit group
permit all
```

`permit all` requiere confirmación de alto impacto.

### Persistencia y recuperación

```text
/var/lib/ad-client-assistant/
/var/backups/ad-client-assistant/
/var/log/ad-client-assistant/
```

El snapshot conserva, según plataforma:

```text
resolver
/etc/hosts evidence
krb5.conf
krb5.keytab
realmd.conf
sssd.conf + sssd/conf.d
nsswitch.conf
PAM session config
NetworkManager DNS properties + connection UUID
systemd-resolved managed drop-in
hostname
package baseline
authselect backup/state
```

Los paquetes instalados por el assistant se registran por separado. Durante un restore pueden
eliminarse de forma explícita, pero el script nunca ejecuta un `autoremove` automático.

La línea v1.1 mantiene el mismo conjunto base de paquetes de v1.0. Las comprobaciones nuevas se
implementan usando Bash, `ip`, `dig`, systemd y las herramientas AD que ya forman parte del stack.
Las funciones opcionales, como `pam_mkhomedir`, no fuerzan la instalación de un paquete adicional si
el módulo no existe en el sistema.

<a id="windows-client-assistant"></a>
## Windows AD Client Assistant

Archivo:

```text
windows-ad-client-assistant.ps1
```

Ejecutar desde Windows PowerShell elevado:

```powershell
Unblock-File .\windows-ad-client-assistant.ps1
.\windows-ad-client-assistant.ps1
```

Modos:

```powershell
.\windows-ad-client-assistant.ps1 -Mode Audit
.\windows-ad-client-assistant.ps1 -Mode Join
.\windows-ad-client-assistant.ps1 -Mode Status
.\windows-ad-client-assistant.ps1 -Mode Leave
.\windows-ad-client-assistant.ps1 -Mode Restore
```

No requiere paquetes adicionales.

El wizard v1.1:

```text
domain + AD DNS input
  ↓
direct SRV preflight against every AD DNS
  ↓
route-aware NIC selection
  ↓
snapshot DNS + adapter GUID + hostname/workgroup
  ↓
configure AD DNS
  ↓
Resolve-DnsName + nltest
  ↓
53/88/135/389/445 readiness
  ↓
DC time sample
  ↓
Get-Credential
  ↓
Add-Computer
  ↓
JOIN_PENDING_REBOOT
  ↓
reboot
  ↓
secure-channel + DC locator acceptance
```

Soporta:

```text
OUPath opcional
computer name opcional
varios DC/DNS
Windows clients compatibles
Windows Server como member server
```

Las ediciones Windows Home/Core-client que no soportan el join clásico a AD se bloquean antes de
modificar DNS.

### Network readiness y diagnostics v1.1

Los servidores DNS introducidos se restringen explícitamente a IPv4 en esta línea para que input,
snapshot y rollback utilicen el mismo modelo. Si la interfaz conserva resolvers IPv6, el assistant los
muestra como warning para que el administrador confirme que también pueden resolver la zona AD.

Cuando existen varias NIC, `Find-NetRoute` determina qué interfaz usa Windows para alcanzar el primer
DNS AD y la propone como default del selector.

Readiness de join:

```text
DNS/TCP 53
Kerberos/TCP 88
RPC Endpoint Mapper/TCP 135
LDAP/TCP 389
SMB/TCP 445
```

No se abre el firewall ni se instalan agentes para superar un fallo. El assistant muestra el componente
que no es alcanzable y deja la decisión de red al administrador.

Si `Add-Computer` falla, se conserva un tail de:

```text
C:\Windows\Debug\NetSetup.log
```

El diagnóstico reconoce específicamente el bloqueo moderno de reutilización de cuentas de equipo
`0xAAC / NERR_AccountReuseBlockedByPolicy` y no aplica bypasses de Registry.

### Lifecycle transaccional Windows

v1.1 evita restaurar DNS demasiado pronto durante joins/leaves pendientes de reboot.

Estados:

```text
JOIN_PENDING_REBOOT
JOINED
JOINED_DEGRADED
LEAVE_PENDING_REBOOT
RESTORE_PENDING_REBOOT
```

Después de `Remove-Computer`, el DNS AD se mantiene hasta que Windows haya reiniciado y confirme que ya
no pertenece al dominio. Entonces el assistant restaura DNS y hostname. Si la recuperación del hostname
requiere otro reboot, el estado se conserva hasta completarlo.

El match de la NIC durante rollback usa:

```text
InterfaceGuid
  ↓ fallback
InterfaceIndex
  ↓ fallback
InterfaceAlias
```

para tolerar cambios de índice producidos por drivers, Hyper-V, USB NICs o cambios de hardware virtual.

### Restauración DNS Windows

El snapshot no guarda únicamente las IP DNS visibles.

También determina si existía un `NameServer` estático en la configuración TCP/IP. Por tanto:

```text
DNS originalmente DHCP
  → Set-DnsClientServerAddress -ResetServerAddresses

DNS originalmente estático
  → restore exact previous ServerAddresses
```

Esto evita convertir accidentalmente una NIC DHCP en una NIC con DNS estático permanente después
del rollback.

### Leave Windows

El camino soportado utiliza:

```powershell
Remove-Computer
```

con credencial de desunión y workgroup de retorno.

Después del reboot de desunión restaura DNS y, cuando procede, el hostname original. Durante
`LEAVE_PENDING_REBOOT` mantiene deliberadamente el DNS AD para no romper la transición que Windows aún
no ha materializado.

Si el equipo todavía figura como miembro de dominio, `-Mode Restore` **no** falsifica la salida
editando el Registry. Exige utilizar primero el leave soportado.

Persistencia:

```text
C:\ProgramData\ADClientAssistant\
```

### Acceptance recomendada antes de producción

Prueba como mínimo:

| Caso | Linux | Windows |
|---|---:|---:|
| DHCP + 1 NIC | sí | sí |
| DNS/IP estático | sí | sí |
| dos DNS AD válidos | sí | sí |
| DNS secundario incorrecto | sí | sí |
| multi-NIC | sí | sí |
| VPN activa | sí | sí |
| join remoto SSH/RDP | sí | sí |
| reboot + status | sí | sí |
| clean leave + reboot + restore | sí | sí |
| DC inaccesible durante leave | sí | sí |
| identidad previa / SSSD previo | sí | n/a |
| computer account existente | sí | sí |

---

<a id="client-rollback"></a>
## Modelo de rollback

El objetivo de rollback es devolver el **cliente local** al estado inmediatamente anterior al join.

Eso incluye:

```text
DNS behavior
hostname when modified
local identity/client config
Linux pre-join Kerberos keytab state
Windows reboot/lifecycle state
optional packages installed by the assistant
```

No significa que un rollback local pueda garantizar la eliminación del objeto de equipo del
directorio si el DC no está disponible.

Por eso el orden preferido es siempre:

```text
domain reachable
  → clean leave
  → local restore
```

y solo después:

```text
domain unavailable / failed deployment
  → explicit local recovery
  → inspect/remove stale computer account later
```

En Windows no se ofrece una pseudo-desunión basada en manipulación manual de estado interno.

---

<a id="clientes"></a>
# Unir equipos al dominio · procedimiento manual

Esta sección parte de un dominio ya funcional. Antes de unir clientes, el DC debe superar su
validación funcional.

Modelo común:

```text
CLIENT
  DNS  → DC/DNS del dominio
  TIME → sincronizado
  SRV  → _ldap._tcp.dc._msdcs.<dominio>
  JOIN → cuenta con permisos de join
```

No configures un DNS público/router como fallback de un miembro AD. El cliente puede elegirlo y
perder los registros SRV del dominio.

## Checklist común

Ejemplo:

```text
AD DNS domain : corp.example.com
Kerberos realm: CORP.EXAMPLE.COM
DC/DNS        : 192.168.10.10
Join account  : cuenta delegada
```

Antes del join:

1. hostname final y único;
2. DNS del cliente apuntando a DC01/DC02;
3. conectividad con los DC;
4. hora sincronizada;
5. registros SRV resolubles;
6. credencial con permiso de join;
7. routing/firewall compatible con AD.

En el DC:

```bash
dig @127.0.0.1 \
  _ldap._tcp.dc._msdcs.corp.example.com \
  SRV

sudo ad-validate
```

## Windows

Windows Server puede unirse como member server. En clientes Windows utiliza una edición que soporte
la unión clásica a Active Directory.

DNS/SRV:

```powershell
Get-DnsClientServerAddress -AddressFamily IPv4

Resolve-DnsName `
  _ldap._tcp.dc._msdcs.corp.example.com `
  -Type SRV
```

También:

```cmd
nltest /dsgetdc:corp.example.com
```

PowerShell elevado:

```powershell
Add-Computer `
  -DomainName 'corp.example.com' `
  -Credential (Get-Credential)

Restart-Computer
```

OU explícita:

```powershell
Add-Computer `
  -DomainName 'corp.example.com' `
  -OUPath 'OU=Workstations,DC=corp,DC=example,DC=com' `
  -Credential (Get-Credential)

Restart-Computer
```

GUI genérica:

```text
System / System Properties
  → Computer Name
  → Change
  → Member of: Domain
  → corp.example.com
  → credentials
  → reboot
```

Validación:

```powershell
(Get-CimInstance Win32_ComputerSystem).Domain
Test-ComputerSecureChannel -Verbose
```

Desde el DC Samba:

```bash
sudo ad-computers
```

## Linux genérico: realmd + SSSD

Para un miembro Linux normal, el stack portable es:

```text
realmd
SSSD con AD provider
adcli
Kerberos client
NSS/PAM integration
```

Winbind es una alternativa cuando el servidor necesita integración Samba específica.

### Familia Debian

Instala los equivalentes disponibles en tu release:

```bash
sudo apt update

sudo apt install \
  realmd \
  sssd-ad \
  sssd-tools \
  adcli \
  krb5-user \
  libnss-sss \
  libpam-sss
```

### Familia RHEL / Fedora

Stack habitual:

```bash
sudo dnf install \
  samba-common-tools \
  realmd \
  oddjob \
  oddjob-mkhomedir \
  sssd \
  adcli \
  krb5-workstation
```

### Otras distribuciones

No copies literalmente nombres de paquetes de Debian o RHEL.

Busca los equivalentes de:

```text
realmd
SSSD + AD provider
adcli
Kerberos client
NSS/PAM SSSD integration
home-directory helper (si la política lo requiere)
DNS diagnostic tools
```

El flujo posterior es el mismo.

### Descubrimiento

Configura primero el DNS del host para utilizar los DC.

```bash
realm discover --verbose corp.example.com
```

Debería identificar Active Directory y un cliente soportado.

Diagnóstico SRV:

```bash
dig \
  _ldap._tcp.dc._msdcs.corp.example.com \
  SRV
```

Si `realm discover` falla, corrige DNS/hora antes de hacer join.

### Join con SSSD

```bash
sudo realm join \
  --verbose \
  --client-software=sssd \
  -U JoinAccount \
  corp.example.com
```

OU cuando tu `realmd` lo soporte:

```bash
sudo realm join \
  --verbose \
  --client-software=sssd \
  --computer-ou='OU=Linux,OU=Servers,DC=corp,DC=example,DC=com' \
  -U JoinAccount \
  corp.example.com
```

También puedes usar un TGT:

```bash
kinit JoinAccount@CORP.EXAMPLE.COM
klist

sudo realm join \
  --verbose \
  --client-software=sssd \
  corp.example.com
```

No incrustes contraseñas en scripts de join.

### Validación Linux

```bash
realm list
sudo adcli testjoin

getent passwd 'usuario@corp.example.com'
id 'usuario@corp.example.com'

klist -k /etc/krb5.keytab
systemctl status sssd --no-pager
```

Comprueba también la cuenta de máquina desde:

```bash
sudo ad-computers
```

### Autorización de login

Estar unido al dominio y permitir logon son decisiones distintas.

Ejemplos:

```bash
sudo realm permit 'usuario@corp.example.com'
```

o:

```bash
sudo realm permit -g 'grupo@corp.example.com'
```

También puedes delegar el access control a SSSD/GPO/grupos según el diseño.

### Home directories

La creación automática de home depende de PAM/oddjob y la familia de la distribución. Decide antes:

```text
username format
use_fully_qualified_names
home layout
offline credentials
access_provider
ID mapping
```

### ID mapping vs RFC2307

Si AD ya contiene:

```text
uidNumber
gidNumber
unixHomeDirectory
loginShell
```

puedes diseñar SSSD para consumir esos IDs en vez del mapping automático. No mezcles ambos modelos
sin planificación si existen permisos de filesystem basados en UID/GID.

### Winbind como alternativa

Para Samba member servers puede resultar más apropiado:

```text
realmd
Samba/Winbind
Kerberos
```

No cambies de SSSD a Winbind para ocultar un problema de DNS/Kerberos.

## Linux y Group Policy

El join Linux no implica aplicar automáticamente todas las GPO Windows:

```text
SSSD
  → GPO access-control evaluation

Samba/winbind + samba-gpupdate
  → policy managers soportados por Samba

Ubuntu ADSys
  → mapping/templates específicos de Ubuntu
```

## Post-join común

Tras unir cualquier equipo:

```text
1. validar DNS/SRV
2. validar hora
3. comprobar cuenta de equipo
4. probar autenticación
5. comprobar autorización
6. probar policy/GPO primero en OU de test
7. reiniciar
8. volver a validar secure channel / realm membership
```

`hosts`/`/etc/hosts` no sustituye DNS SRV de Active Directory.

---

<a id="virtualizacion"></a>
# VirtualBox, VMware y laboratorios multi-NIC

Una causa frecuente de fallos AD en laboratorio es combinar:

```text
NAT
+
Bridged
+
dos gateways
+
dos DNS diferentes
```

Ejemplo correcto si necesitas ambas NIC:

```text
NAT
  10.0.2.x
  default route
  no registro DNS AD

BRIDGED / LAN
  192.168.1.x
  conectividad con DC/clientes
  DNS AD
```

Para un cliente Windows que solo necesita LAN+Internet y el bridge ya tiene gateway, a menudo es más sencillo utilizar solo:

```text
Bridged Adapter
```

### El síntoma clásico

```text
ping 192.168.1.10
  OK

ping dc01.corp.example.com
  FAIL

join domain
  _ldap._tcp.dc._msdcs... not found
```

Eso es casi siempre una señal para revisar DNS, no `/etc/hosts`.

`hosts` puede resolver:

```text
dc01.corp.example.com → 192.168.1.10
```

pero no puede representar correctamente registros:

```text
_ldap._tcp...
_kerberos._tcp...
```

Active Directory necesita DNS SRV.

---

<a id="alta-disponibilidad"></a>
# Alta disponibilidad

Un solo DC sigue siendo un Single Point of Failure.

Arquitectura recomendada cuando la disponibilidad importa:

```text
             Domain members
                   │
          ┌────────┴────────┐
          │                 │
        DC01              DC02
       AD/DNS             AD/DNS
          │                 │
          └──── replication ┘
```

Buenas prácticas:

- al menos dos DC/DNS cuando el negocio lo justifica;
- fallos de host/hipervisor separados;
- backups off-host;
- monitorización;
- restore tests;
- actualización escalonada;
- documentación de FSMO;
- RTO/RPO;
- credenciales de recuperación;
- acceso out-of-band.

---

<a id="troubleshooting"></a>
# Troubleshooting

## Linux: Samba está `active` pero falta el listener 88 después del boot

```bash
systemctl status samba-ad-dc --no-pager -l

ss -lntup |
  grep -E ':(53|88|389|445|464)([[:space:]]|$)'
```

El control plane utiliza:

```text
debian-ad-network-ready.service
debian-ad-samba-health.service
```

El primer servicio espera la identidad de red. El segundo valida los listeners y, solo si Samba
queda degradado, realiza un único restart.

```bash
journalctl \
  -u debian-ad-samba-health.service \
  -b \
  --no-pager
```

Si el self-heal ocurre repetidamente, revisa también:

```bash
journalctl -u samba-ad-dc -b --no-pager
```

La autorreparación evita dejar el DC inutilizable, pero no debe ocultar una causa recurrente.

---


## Linux: `/etc/resolv.conf` apunta a un stub roto

Síntoma:

```text
Unable to open /etc/resolv.conf
try using --system-dns
```

Revisar:

```bash
ls -l /etc/resolv.conf
readlink -f /etc/resolv.conf || true
cat /etc/resolv.conf
systemctl is-active systemd-resolved
```

Usa:

```bash
sudo ad-security
```

```text
Repair local resolver
```

No sobrescribas `/etc/resolv.conf` manualmente sin saber quién lo gestiona.

---

## Linux: Samba DNS responde por IP pero el sistema no resuelve

Compara:

```bash
dig @127.0.0.1 \
  _ldap._tcp.dc._msdcs.corp.example.com SRV

dig \
  _ldap._tcp.dc._msdcs.corp.example.com SRV
```

Si el primero funciona y el segundo no:

```text
Samba DNS probablemente OK
resolver local probablemente mal configurado
```

---

## GPO: `Could not find a DC for domain`

Primero:

```bash
sudo ad-validate
```

Después:

```bash
dig +short SRV \
  _ldap._tcp.dc._msdcs.corp.example.com
```

y:

```bash
sudo ad-gpo
```

```text
GPO readiness
```

No añadas grupos/ACL al azar hasta corregir DNS/DC locator.

---

## GPO: `ACCESS_DENIED`

Revisar:

```bash
kdestroy
kinit AdminDelegado@CORP.EXAMPLE.COM
klist
```

Membresías:

```bash
samba-tool user getgroups AdminDelegado
```

GPO diagnostics:

```bash
samba-tool ntacl sysvolcheck
samba-tool gpo aclcheck
```

Si `sysvolcheck` pasa y `aclcheck` no, no asumas automáticamente que necesitas `sysvolreset`.

---

## Windows: el script no ejecuta por ExecutionPolicy

```powershell
Unblock-File .\windows-server-ad-assistant.ps1

Set-ExecutionPolicy `
  -Scope Process `
  Bypass `
  -Force
```

Luego:

```powershell
.\windows-server-ad-assistant.ps1 -Mode Audit
```

---

## Windows: `#requires -RunAsAdministrator`

Abre:

```text
Windows PowerShell
→ Run as administrator
```

o:

```powershell
Start-Process powershell.exe -Verb RunAs
```

---

## El cliente ve la IP del DC pero no puede unirse

Comprueba en el cliente:

```text
DNS = DC
```

Pruebas Windows:

```cmd
nslookup dc01.corp.example.com
nltest /dsgetdc:corp.example.com
```

Prueba SRV:

```cmd
nslookup
set type=SRV
_ldap._tcp.dc._msdcs.corp.example.com
```

No resuelvas un problema de SRV añadiendo entradas a `hosts`.

---

## Después de hardening deja de funcionar un cliente antiguo

Identifica primero qué cambió.

Áreas típicas:

```text
SMB signing
SMB minimum protocol
LDAP signing
LDAP channel binding
NTLM policy
Kerberos RC4/AES
firewall
```

Utiliza el audit y evidence antes de hacer rollback global.

---

<a id="faq"></a>
# Preguntas frecuentes

## ¿Puedo ejecutar el script más de una vez?

Sí, gran parte de la lógica está diseñada para detectar estado existente.

Sin embargo, idempotencia no significa que todas las operaciones destructivas sean repetibles sin consecuencias.

Lee siempre el plan mostrado.

---

## ¿`--bootstrap` puede borrar/recrear un dominio existente?

No debería hacerlo. La presencia de `sam.ldb` bloquea el reprovisioning normal.

Nunca borres los archivos internos de Samba solo para saltarte esa protección.

---

## ¿Debo usar `.local` para el dominio?

No es necesario y puede crear conflictos con mDNS/Bonjour.

Para nuevas instalaciones suele ser más limpio utilizar un nombre DNS controlado por la organización, por ejemplo:

```text
ad.example.com
corp.example.com
```

Decide el nombre con cuidado: cambiar posteriormente el nombre real del dominio es una migración compleja.

---

## ¿El dominio AD debe ser el mismo que el dominio web?

No.

Ejemplo perfectamente válido:

```text
web:
example.com

AD:
corp.example.com
```

---

## ¿Puedo poner 8.8.8.8 como DNS secundario de los PCs?

No es una buena configuración para miembros del dominio.

Utiliza DC/DNS internos como resolvers del cliente. Los DC hacen forwarding externo.

---

## ¿Necesito modificar `hosts`?

Normalmente no.

AD depende de DNS A/AAAA y especialmente SRV.

---

## ¿Qué ocurre si cambio la IP del DC?

Debes actualizar red/DNS/registros y validar.

Si el dominio no cambia, los equipos no necesitan cambiar de dominio únicamente porque cambie el servidor/IP.

---

## ¿Qué ocurre si cambio de dominio AD?

No existe una «redirección» DNS que cambie la relación de dominio.

Los equipos deben establecer un nuevo secure channel con el dominio destino mediante migración/rejoin.

Utiliza `ad-migrate` / `-Mode Migration`.

---

## ¿Puedo cambiar solo el dominio de correo/web y mantener AD?

Sí. Esa es una operación de branding/servicios y no necesariamente requiere cambiar la identidad AD.

---

## ¿Puedo usar un solo DC?

Sí técnicamente.

No proporciona tolerancia al fallo del servicio de identidad/DNS.

Para producción crítica considera dos DC.

---

## ¿Puedo usar el DC como file server?

Técnicamente Samba puede exponer shares adicionales, pero separar roles reduce superficie de ataque y blast radius.

Para entornos profesionales suele ser preferible:

```text
DC
  → AD/DNS/Kerberos/SYSVOL

Member server
  → File services
```

---

## ¿Tengo que habilitar AES-only Kerberos?

No automáticamente.

Primero audita compatibilidad.

Legacy appliances, trusts, service accounts y software de terceros pueden depender de RC4.

---

## ¿LDAP channel binding siempre debe ponerse en modo estricto?

Es un objetivo de seguridad válido, pero puede romper aplicaciones LDAP antiguas.

Audita y migra clientes antes de enforcement.

---

## ¿La herramienta garantiza CIS compliance?

No.

Es `baseline-aware` y utiliza controles compatibles con buenas prácticas y hardening, pero CIS compliance requiere un benchmark concreto, alcance definido, evidencia y revisión completa.

---

## ¿La herramienta sustituye un backup?

No.

De hecho, muchos módulos presuponen que tienes backups externos y recuperables.

---

## ¿Puedo ejecutar `curl | bash` en producción?

Es posible, pero no es el método recomendado.

Mejor:

```text
download
verify
review
pin version
execute
```

---

## ¿Los scripts guardan contraseñas?

No deberían guardar credenciales administrativas como texto plano.

Kerberos utiliza un cache aislado por ejecución en el asistente Debian.

Los paquetes de migración solicitan credenciales en runtime.

---

## ¿Cómo vuelvo inmediatamente al menú principal?

En un submenu:

```text
H
```

Para volver un solo nivel:

```text
0
```

---

<a id="validacion-produccion"></a>
# Validación antes de producción

## Bash

Sintaxis:

```bash
bash -n debian-ad-assistant.sh
```

Recomendado:

```bash
shellcheck debian-ad-assistant.sh
```

Matriz mínima:

```text
Debian 13
Ubuntu Server 26.04
single NIC
dual NIC
SSH
console
nuevo DC
DC existente
segundo run
reboot
resolver roto
UFW preexistente
audit
status
validate
backup
GPO
dependencies
Suricata IDS
domain reset assessment
migration
safe hardening
boot listener self-heal
```

---

## PowerShell

Parser:

```powershell
$errors = $null
$tokens = $null

[System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path .\windows-server-ad-assistant.ps1),
    [ref]$tokens,
    [ref]$errors
) | Out-Null

$errors
```

La salida debe estar vacía.

Si PSScriptAnalyzer está instalado:

```powershell
Invoke-ScriptAnalyzer `
  .\windows-server-ad-assistant.ps1
```

Matriz:

```text
Server 2019
Server 2022
Server 2025
workgroup
member server
Domain Controller
console
RDP
WinRM
Defender
third-party AV
GPO-managed firewall
new forest
existing forest
GPO operations
Dependencies
IDS console + GUI fallback
Reset assessment
migration
DirectorySecurity
recoverable menu errors
reboot
```

---

<a id="referencias"></a>
# Referencias

## Samba

- Samba tool:  
  https://www.samba.org/samba/docs/current/man-html/samba-tool.8.html

- `smb.conf`:  
  https://www.samba.org/samba/docs/current/man-html/smb.conf.5.html

## Linux domain membership

- Debian `realm(8)`:  
  https://manpages.debian.org/trixie/realmd/realm.8.en.html

- Red Hat · integración directa con Active Directory mediante SSSD/realmd:  
  https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/

## Ubuntu / ADSys

- ADSys:  
  https://ubuntu.com/docs/adsys/latest/

## Remote administration

- PowerShell Remoting / WinRM security:
  https://learn.microsoft.com/powershell/scripting/security/remoting/winrm-security

- Just Enough Administration (JEA):
  https://learn.microsoft.com/powershell/scripting/security/remoting/jea/overview

- OpenSSH for Windows:
  https://learn.microsoft.com/windows-server/administration/openssh/openssh-overview

- `quser`, `logoff` and `shutdown`:
  https://learn.microsoft.com/windows-server/administration/windows-commands/

- systemd `loginctl`:
  https://www.freedesktop.org/software/systemd/man/latest/loginctl.html

## Microsoft Active Directory

- Join computer to domain:  
  https://learn.microsoft.com/windows-server/identity/ad-ds/manage/join-computer-to-domain

- AD DS deployment:  
  https://learn.microsoft.com/windows-server/identity/ad-ds/deploy/

- `Install-ADDSForest`:  
  https://learn.microsoft.com/powershell/module/addsdeployment/install-addsforest

- `Uninstall-ADDSDomainController`:  
  https://learn.microsoft.com/powershell/module/addsdeployment/uninstall-addsdomaincontroller

- LDAP signing/channel binding:  
  https://learn.microsoft.com/windows-server/identity/ad-ds/ldap-signing

- SMB signing:  
  https://learn.microsoft.com/windows-server/storage/file-server/smb-signing-overview

## Suricata

- Documentation:  
  https://docs.suricata.io/

- EVE JSON:  
  https://docs.suricata.io/en/latest/output/eve/eve-json-format.html

## Microsoft hardening

- Windows Security Baselines:  
  https://learn.microsoft.com/windows/security/operating-system-security/device-management/windows-security-configuration-framework/windows-security-baselines

## CIS

- CIS Benchmarks:  
  https://www.cisecurity.org/cis-benchmarks

---

<a id="licencia"></a>
# Licencia

MIT License.

Consulta:

```text
LICENSE
```

El software se proporciona sin garantía. Revisa siempre los cambios antes de utilizarlos en sistemas de producción.

---

<a id="estado-proyecto"></a>
# Estado del proyecto

Proyecto en evolución activa.

Antes de utilizar una revisión nueva en producción:

1. revisa el diff;
2. verifica la versión;
3. verifica SHA-256;
4. ejecuta parser/syntax checks;
5. pruébala en laboratorio;
6. realiza backup;
7. conserva acceso de consola/out-of-band;
8. ejecuta audit antes de modificar;
9. aplica cambios por fases;
10. valida inmediatamente;
11. reinicia;
12. vuelve a validar;
13. documenta el resultado.

Una infraestructura de identidad bien administrada no se mide por lo rápido que se instala, sino por lo fácil que resulta **entenderla, operarla, auditarla y recuperarla** cuando algo falla.
