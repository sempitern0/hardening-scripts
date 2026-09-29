# Hardening Scripts · Active Directory Control Planes

[![Status](https://img.shields.io/badge/status-active%20development-0A7EA4)](#estado-del-proyecto)
[![License](https://img.shields.io/badge/license-MIT-green)](./LICENSE)
[![Debian](https://img.shields.io/badge/Debian-13-A81D33?logo=debian&logoColor=white)](#debian--ubuntu--samba-active-directory-control-plane)
[![Ubuntu](https://img.shields.io/badge/Ubuntu%20Server-26.04%20LTS-E95420?logo=ubuntu&logoColor=white)](#debian--ubuntu--samba-active-directory-control-plane)
[![Samba AD](https://img.shields.io/badge/Samba-AD%20DC-1B4D7A)](#debian--ubuntu--samba-active-directory-control-plane)
[![Windows Server](https://img.shields.io/badge/Windows%20Server-2019%20%7C%202022%20%7C%202025-0078D4?logo=windows&logoColor=white)](#windows-server-active-directory-control-plane)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)](#windows-server-active-directory-control-plane)
[![Security](https://img.shields.io/badge/security-audit--first%20%7C%20backup--first-success)](#modelo-de-seguridad)
[![Navigation](https://img.shields.io/badge/navigation-0%3DBack%20%7C%20H%3DHome-blueviolet)](#navegación-de-los-menús)

Dos asistentes administrativos orientados a profesionales para desplegar, auditar, operar, endurecer, recuperar y migrar entornos **Active Directory** sobre **Samba AD DC en Debian/Ubuntu** y **AD DS nativo en Windows Server**.

El objetivo no es convertir Active Directory en un «one-click installer». El objetivo es disponer de un **control plane operativo y repetible** que detecte el estado actual, explique qué va a cambiar, cree evidencia y backups cuando corresponde, solicite confirmación en operaciones sensibles y valide el resultado.

> [!IMPORTANT]
> Estos scripts administran componentes críticos de identidad, DNS, Kerberos, Group Policy, firewall y servicios de dominio. Pruébalos primero en laboratorio, conserva acceso de recuperación y mantén backups externos y restaurables.

---

## Tabla de contenidos

- [¿A quién va dirigido?](#a-quién-va-dirigido)
- [Qué incluye el repositorio](#qué-incluye-el-repositorio)
- [Filosofía del proyecto](#filosofía-del-proyecto)
- [Modelo de seguridad](#modelo-de-seguridad)
- [Navegación de los menús](#navegación-de-los-menús)
- [Elección rápida del asistente](#elección-rápida-del-asistente)
- [Debian / Ubuntu · Samba Active Directory Control Plane](#debian--ubuntu--samba-active-directory-control-plane)
  - [Requisitos y targets](#requisitos-y-targets-linux)
  - [Descarga y ejecución](#descarga-y-ejecución-linux)
  - [Modos del script](#modos-del-script-linux)
  - [CLI instalables](#cli-instalables-linux)
  - [Bootstrap de un DC nuevo](#bootstrap-de-un-dc-nuevo)
  - [Administración diaria](#administración-diaria-linux)
  - [DNS y resolver local](#dns-y-resolver-local-linux)
  - [Kerberos, Samba y hardening](#kerberos-samba-y-hardening-linux)
  - [Group Policy](#group-policy-linux)
  - [Ubuntu ADSys y GPO](#ubuntu-adsys-y-gpo)
  - [Migración de dominio](#migración-de-dominio-linux)
  - [Directorios, logs y estado](#directorios-logs-y-estado-linux)
  - [Configuración manual post-instalación](#configuración-manual-post-instalación-linux)
- [Windows Server Active Directory Control Plane](#windows-server-active-directory-control-plane)
  - [Requisitos y targets](#requisitos-y-targets-windows)
  - [Descarga y ejecución](#descarga-y-ejecución-windows)
  - [Modos PowerShell](#modos-powershell)
  - [Provisioning de un bosque nuevo](#provisioning-de-un-bosque-nuevo)
  - [Administración diaria](#administración-diaria-windows)
  - [Hardening de host y protocolos AD](#hardening-de-host-y-protocolos-ad-windows)
  - [Backup y recuperación](#backup-y-recuperación-windows)
  - [Migración de dominio](#migración-de-dominio-windows)
  - [Configuración manual post-instalación](#configuración-manual-post-instalación-windows)
- [Clientes Windows y Linux](#clientes-windows-y-linux)
- [VirtualBox, VMware y laboratorios multi-NIC](#virtualbox-vmware-y-laboratorios-multi-nic)
- [Alta disponibilidad](#alta-disponibilidad)
- [Troubleshooting](#troubleshooting)
- [Preguntas frecuentes](#preguntas-frecuentes)
- [Validación antes de producción](#validación-antes-de-producción)
- [Referencias](#referencias)
- [Licencia](#licencia)
- [Estado del proyecto](#estado-del-proyecto)

---

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

# Qué incluye el repositorio

| Archivo | Plataforma | Línea actual | Función |
|---|---|---:|---|
| `debian-ad-assistant.sh` | Debian / Ubuntu Server | 4.6.x | Samba AD DC, DNS, Kerberos, Chrony, GPO, hardening, backups, migración y administración |
| `windows-server-ad-assistant.ps1` | Windows Server | 1.3.x | AD DS, DNS, GPO, auditoría, hardening, backup, provisioning y migración |
| `DEBIAN-AD-Assistant-GPO-Guide-v4.4.0.md` | Samba AD / GPO | guía | Formato JSON, biblioteca GPO y operación avanzada |

Los nombres de versión pueden avanzar más rápido que esta tabla. Antes de ejecutar:

```bash
head -n 10 debian-ad-assistant.sh
```

o:

```powershell
Get-Content .\windows-server-ad-assistant.ps1 -TotalCount 20
```

---

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

> [!WARNING]
> Un controlador de dominio es infraestructura de identidad. Un cambio aparentemente pequeño en DNS, hora, Kerberos, LDAP o SYSVOL puede impedir el inicio de sesión de toda la organización.

---

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

# Debian / Ubuntu · Samba Active Directory Control Plane

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

> [!TIP]
> Para producción es mejor descargar una tag/release concreta, revisar el archivo y verificar SHA-256. Ejecutar `main` directamente es cómodo para laboratorio, pero `main` puede cambiar.

### Verificar SHA-256

```bash
sha256sum debian-ad-assistant.sh
```

Guarda el hash aprobado en tu sistema de cambios o CMDB.

---

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
| `--install-cli` | instalar/refrescar comandos `ad-*` |
| `--cli-info` | mostrar comandos instalados |
| `--no-color` | desactivar ANSI colors |
| `--help` | ayuda |

Ejemplos:

```bash
sudo bash ./debian-ad-assistant.sh --validate
sudo bash ./debian-ad-assistant.sh --gpo
sudo bash ./debian-ad-assistant.sh --samba-security
sudo bash ./debian-ad-assistant.sh --migration
```

---

## CLI instalables Linux

Instalación:

```bash
sudo bash ./debian-ad-assistant.sh --install-cli
```

El script se instala en:

```text
/usr/local/libexec/debian-ad-assistant
```

y crea symlinks en:

```text
/usr/local/sbin/
```

Comandos:

| Comando | Función |
|---|---|
| `adctl` | Main Control Plane completo |
| `ad-ops` | operaciones diarias reducidas |
| `ad-users` | usuarios |
| `ad-groups` | grupos |
| `ad-computers` | equipos |
| `ad-permissions` | membresías y ACL |
| `ad-gpo` | GPO multiplataforma |
| `ad-security` | seguridad del host/DC |
| `ad-samba` | hardening Samba + Kerberos |
| `ad-kerberos` | Kerberos security center |
| `ad-migrate` | migraciones |
| `ad-audit` | auditoría read-only |
| `ad-validate` | validación funcional |
| `ad-status` | estado rápido |
| `ad-backup` | backup del dominio |
| `ad-tools` | catálogo y estado de shortcuts |

Ejemplos:

```bash
sudo adctl
sudo ad-status
sudo ad-users
sudo ad-gpo
sudo ad-samba
sudo ad-migrate
```

Verificar shortcuts:

```bash
sudo ad-tools
```

Actualizar shortcuts después de sustituir el script:

```bash
sudo bash ./debian-ad-assistant.sh --install-cli
```

> [!NOTE]
> Si copias una nueva versión al servidor pero no vuelves a ejecutar `--install-cli`, `/usr/local/libexec/debian-ad-assistant` puede seguir siendo la versión antigua.

---

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
17. valida AD/DNS/Kerberos/LDAP/SMB/SYSVOL;
18. genera checklist post-instalación.

### Protección frente a reprovisioning

Si existe:

```text
/var/lib/samba/private/sam.ldb
```

el asistente no debe tratar el host como un DC vacío.

No elimines `sam.ldb`, `secrets.ldb` o SYSVOL para «volver a intentar» un bootstrap.

---

## Administración diaria Linux

Main Control Plane:

```bash
sudo adctl
```

Módulos principales:

```text
Audit current state
Validate AD/DC health
Repair DNS / Kerberos
Time synchronization
Firewall policy
Directory/admin baseline
Baseline GPOs
Domain backup
SYSVOL ACL repair
Post-install checklist
Operations console
Boot ordering
CLI installation
Resolver repair
Domain migration
Samba & Kerberos security
```

Consola diaria:

```bash
sudo ad-ops
```

Incluye:

```text
Users
Groups
Computers
Access & delegation
Group Policy
Security & resilience
Validation
Backup
Migration
```

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
tickets actuales
```

Clasificaciones:

```text
AES_READY
RC4_ONLY
RC4_AND_AES
IMPLICIT_DEFAULT
OTHER
```

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

Pruebas:

```bash
chronyc tracking
chronyc sources -v
```

El asistente detecta `ntp_signd` de Samba y puede configurar Chrony para respuestas MS-SNTP firmadas cuando la versión instalada lo soporta.

---

## Group Policy Linux

Acceso:

```bash
sudo ad-gpo
```

Funciones:

```text
List GPOs + GUIDs
Inspect GPO
Create GPO
Platform GPO catalog
JSON policy library
GPO status
List containers
Link / update
Remove link
Backup GPO
GPO readiness
Delete GPO
Legacy baseline pair
GPO paths & manual
```

### Estado de una GPO

El estado y el link son conceptos independientes:

```text
enabled + unlinked
enabled + linked
computer disabled
user disabled
all disabled
```

### Biblioteca persistente

```text
/var/lib/debian-ad-assistant/gpo/
├── builtin/
│   └── windows/
├── custom/
└── GPO-GUIDE.md
```

Las plantillas `builtin` son administradas por el asistente.

Para modificar una política:

```text
builtin → copy to custom → edit → validate → load
```

### JSON

Ejemplo:

```json
[
  {
    "keyname": "SOFTWARE\\Policies\\Example\\Product",
    "valuename": "ExampleSetting",
    "class": "MACHINE",
    "type": "REG_DWORD",
    "data": 1
  }
]
```

Validación:

```bash
python3 -m json.tool policy.json
```

Carga manual equivalente:

```bash
samba-tool gpo load '{GUID}' \
  --content=/path/policy.json
```

Reemplazo:

```bash
samba-tool gpo load '{GUID}' \
  --content=/path/policy.json \
  --replace
```

En producción utiliza el menú del asistente, que añade backup, selección y controles de error.

### Windows vs Linux

El asistente separa:

```text
Windows
  → Registry/CSE GPO

Ubuntu ADSys
  → Ubuntu.admx / Ubuntu.adml

Samba/winbind Linux
  → samba-gpupdate / Samba CSE

SSSD
  → GPO access-control evaluation
```

No asumas que una política Windows Registry será consumida por un Ubuntu ADSys client.

---

## Ubuntu ADSys y GPO

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

---

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

> [!IMPORTANT]
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

Un DC que requiere reiniciar Samba manualmente después de cada boot todavía no está listo.

---

# Windows Server Active Directory Control Plane

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

## Modos PowerShell

Sintaxis:

```powershell
.\windows-server-ad-assistant.ps1 -Mode <Mode>
```

Modos:

| Mode | Función |
|---|---|
| `Interactive` | Main Control Plane |
| `Audit` | auditoría read-only de host + AD cuando aplica |
| `Validate` | validación funcional de Domain Controller |
| `Harden` | hardening interactivo |
| `Backup` | configuration change-set |
| `ADAdmin` | consola Active Directory |
| `Provision` | nuevo bosque / primer DC |
| `Migration` | Domain Migration Center |
| `DirectorySecurity` | Kerberos/LDAP/SMB protocol security |

Parámetros adicionales:

```powershell
-ExportPath
-NoColor
-AllowRemoteFirewallChange
```

Ejemplos:

```powershell
.\windows-server-ad-assistant.ps1 -Mode Validate

.\windows-server-ad-assistant.ps1 `
  -Mode Audit `
  -ExportPath D:\AD-ControlPlane

.\windows-server-ad-assistant.ps1 `
  -Mode DirectorySecurity

.\windows-server-ad-assistant.ps1 `
  -Mode Harden `
  -AllowRemoteFirewallChange
```

> [!WARNING]
> `-AllowRemoteFirewallChange` no significa «aplicar sin preguntar». Solo permite proponer cambios globales de firewall durante una sesión remota; los cambios de alto impacto siguen requiriendo confirmación.

---

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

## Administración diaria Windows

Modo:

```powershell
.\windows-server-ad-assistant.ps1 -Mode ADAdmin
```

Módulos:

```text
Users
Groups & access
Computers & OUs
Group Policy
AD DNS
DC health
Backup & recovery
Host security
Domain migration
Directory protocol security
```

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

> [!IMPORTANT]
> No guardes la única copia del System State en el mismo disco físico/VM que el DC.

---

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

# Clientes Windows y Linux

## Unir un Windows al dominio

Antes:

```cmd
ipconfig /all
```

El DNS del adaptador debe apuntar al DC.

Prueba:

```cmd
nslookup dc01.corp.example.com
nltest /dsgetdc:corp.example.com
```

PowerShell:

```powershell
Add-Computer `
  -DomainName corp.example.com `
  -Credential CORP\Administrator `
  -Restart
```

En producción utiliza una cuenta delegada para joins, no necesariamente Domain Admin.

---

## Cliente Ubuntu con realmd/SSSD

Ejemplo conceptual:

```bash
sudo apt update
sudo apt install realmd sssd-ad sssd-tools adcli krb5-user

realm discover corp.example.com

sudo realm join \
  corp.example.com \
  -U JoinAccount

realm list
id 'user@corp.example.com'
```

La configuración exacta puede variar por distribución y política.

---

## Cliente Ubuntu ADSys

Después de unir el equipo:

```bash
sudo apt install adsys
```

Validación:

```bash
adsysctl policy applied
```

Actualizar policy:

```bash
sudo adsysctl update -m
```

Para usuario:

```bash
adsysctl update
```

---

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

# Troubleshooting

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
migration
safe hardening
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
migration
DirectorySecurity
reboot
```

---

# Referencias

## Samba

- Samba tool:  
  https://www.samba.org/samba/docs/current/man-html/samba-tool.8.html

- `smb.conf`:  
  https://www.samba.org/samba/docs/current/man-html/smb.conf.5.html

## Ubuntu / ADSys

- ADSys documentation:  
  https://ubuntu.com/docs/adsys/latest/

- Set up AD for Ubuntu clients:  
  https://ubuntu.com/docs/adsys/latest/how-to/set-up-ad/

## Microsoft Active Directory

- AD DS deployment:  
  https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/deploy/install-active-directory-domain-services--level-100-

- `Install-ADDSForest`:  
  https://learn.microsoft.com/en-us/powershell/module/addsdeployment/install-addsforest

- LDAP signing/channel binding:  
  https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/ldap-signing

- SMB signing:  
  https://learn.microsoft.com/en-us/windows-server/storage/file-server/smb-signing-overview

## Microsoft hardening

- Windows Security Baselines:  
  https://learn.microsoft.com/windows/security/operating-system-security/device-management/windows-security-configuration-framework/windows-security-baselines

- Security Compliance Toolkit:  
  https://learn.microsoft.com/windows/security/operating-system-security/device-management/windows-security-configuration-framework/security-compliance-toolkit-10

## CIS

- CIS Benchmarks:  
  https://www.cisecurity.org/cis-benchmarks

---

# Licencia

MIT License.

Consulta:

```text
LICENSE
```

El software se proporciona sin garantía. Revisa siempre los cambios antes de utilizarlos en sistemas de producción.

---

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
