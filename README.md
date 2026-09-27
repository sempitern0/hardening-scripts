# Hardening Scripts

Asistentes **one-shot** para instalación, auditoría, configuración y hardening de servidores Linux y Windows.

El objetivo del repositorio es ofrecer herramientas prácticas para administradores de sistemas que:

- detecten el estado actual antes de modificar;
- pidan confirmación en cambios sensibles;
- mantengan logs y copias de seguridad;
- validen el resultado después de cada bloque crítico;
- funcionen tanto en servidores nuevos como en infraestructura existente;
- prioricen disponibilidad, recuperación y herramientas nativas;
- sirvan como base **CIS-oriented / baseline-aware**, sin afirmar cumplimiento completo por sí solas.

> **Importante:** estos scripts no sustituyen una revisión de arquitectura, una política de backups, monitorización, alta disponibilidad ni una auditoría CIS completa.

---

## Scripts

| Archivo | Plataforma | Versión | Uso principal |
|---|---|---:|---|
| `debian-ad-assistant.sh` | Debian / Ubuntu Server | 3.1.x | Samba AD DC, DNS, Kerberos, Chrony, UFW, GPO, backups y validación |
| `pymes-windows-server-security.ps1` | Windows Server 2019/2022/2025 | 0.3.x | Auditoría y hardening interactivo de Windows Server |

---

# Linux — Samba Active Directory Assistant

## Objetivo

Automatizar y asistir la preparación de un **Samba Active Directory Domain Controller** sin convertir el provisioning en una operación ciega.

Soporta dos escenarios principales:

```text
Servidor nuevo
    ↓
bootstrap
    ↓
Samba AD/DC
    ↓
validación
    ↓
tareas manuales post-instalación
```

y:

```text
AD/DC existente
    ↓
audit / validate / manage
    ↓
cambios controlados
    ↓
backup
    ↓
validación
```

El asistente **nunca reprovisiona automáticamente un dominio existente**.

---

## Targets

Objetivos principales de prueba:

- Debian 13
- Ubuntu Server 26.04 LTS
- Bash
- systemd
- Samba AD DC
- IPv4 como camino principal de administración y AD

También intenta funcionar de forma conservadora en derivados Debian, pero esos entornos deben considerarse `best-effort` hasta ser probados.

---

# Ejecución Linux

## Ayuda

```bash
sudo bash ./debian-ad-assistant.sh --help
```

## Auditoría sin cambios

```bash
sudo bash ./debian-ad-assistant.sh --audit
```

Inventaría:

- sistema operativo;
- interfaces;
- rutas;
- modelo single-NIC / multi-NIC;
- servicios Samba;
- Chrony;
- resolver;
- UFW;
- estado básico de seguridad;
- presencia de AD/DC.

## Estado rápido

```bash
sudo bash ./debian-ad-assistant.sh --status
```

Pensado para comprobaciones operativas rápidas:

- red;
- interfaz WAN;
- interfaz AD;
- Samba;
- DNS;
- Kerberos;
- LDAP;
- SMB;
- SYSVOL;
- resolver local.

## Validar un AD/DC existente

```bash
sudo bash ./debian-ad-assistant.sh --validate
```

Comprueba, entre otros:

- `samba-ad-dc`;
- `smb.conf`;
- DNS A;
- registros SRV;
- `samba-tool domain info`;
- `samba-tool dbcheck`;
- SYSVOL;
- ACL de GPO;
- Kerberos cuando esté disponible.

## Provisionar un DC nuevo

```bash
sudo bash ./debian-ad-assistant.sh --bootstrap
```

Usar únicamente sobre un servidor preparado para convertirse en un **nuevo DC**.

El modo bootstrap:

1. detecta sistema y red;
2. identifica entorno single-NIC o multi-NIC;
3. solicita la interfaz destinada al AD;
4. comprueba direccionamiento;
5. instala dependencias;
6. configura hostname;
7. prepara Chrony;
8. provisiona Samba AD;
9. configura DNS/Kerberos;
10. crea estructura AD opcional;
11. aplica GPO base opcionales;
12. configura UFW;
13. valida el resultado;
14. genera informe y checklist post-instalación.

## Administrar un DC existente

```bash
sudo bash ./debian-ad-assistant.sh --manage
```

Permite trabajar sobre un AD ya provisionado sin ejecutar nuevamente `domain provision`.

Incluye operaciones como:

- auditoría;
- validación;
- DNS/resolver local;
- Kerberos;
- Chrony;
- firewall;
- OUs y grupos;
- GPO;
- backup;
- comprobación de SYSVOL;
- reparación avanzada confirmada.

## Crear backup del dominio

```bash
sudo bash ./debian-ad-assistant.sh --backup
```

Utiliza las herramientas de Samba para crear una copia consistente del dominio.

Los backups locales **no deben ser la única copia existente**.

---

# One-shot remoto

## Recomendado: descargar, revisar y ejecutar

```bash
curl -fsSLo /tmp/debian-ad-assistant.sh \
  https://raw.githubusercontent.com/sempitern0/hardening-scripts/main/debian-ad-assistant.sh

sudo bash /tmp/debian-ad-assistant.sh --audit
```

Después de revisar:

```bash
sudo bash /tmp/debian-ad-assistant.sh --bootstrap
```

## Ejecución directa

```bash
curl -fsSL \
  https://raw.githubusercontent.com/sempitern0/hardening-scripts/main/debian-ad-assistant.sh \
  | sudo bash -s -- --bootstrap
```

El asistente utiliza `/dev/tty` para mantener prompts interactivos incluso cuando stdin contiene el propio script.

Para producción es preferible ejecutar una **tag/release concreta** y verificar su SHA-256.

---

# Red y servidores multi-NIC

El asistente diferencia entre:

```text
WAN_IFACE     salida a Internet
AD_IFACE      red donde viven los clientes del dominio
MGMT_IFACE    interfaz utilizada por el administrador
```

Ejemplo VirtualBox:

```text
enp0s3
  NAT / DHCP
  10.0.2.x
  default gateway
       │
       ▼
   Internet

enp0s8
  Host-only / LAN
  192.168.56.x
  sin gateway
       │
       ▼
 AD clients
```

Recomendación:

- el gateway por defecto debe estar normalmente en la interfaz WAN;
- la interfaz AD debe utilizar una dirección estable;
- los clientes del dominio deben utilizar el DC como DNS;
- no añadir un segundo gateway por defecto en la interfaz AD salvo que la arquitectura lo requiera deliberadamente.

---

# DNS y disponibilidad

Un DC Samba depende fuertemente de DNS.

El modelo esperado es:

```text
Cliente AD
   │
   ▼
Samba DNS
   │
   ├── dominio interno → Samba
   │
   └── Internet → DNS forwarder
```

El propio DC debe acabar resolviendo mediante Samba cuando el servicio haya sido validado.

El asistente intenta evitar este fallo:

```text
Samba DNS falla
+
resolver del host = 127.0.0.1
=
servidor sin resolución DNS
```

Antes de cambiar el resolver local debe comprobarse:

```bash
dig @127.0.0.1 dc.dominio
dig @127.0.0.1 raw.githubusercontent.com
```

Si la transición falla, el objetivo es restaurar el resolver previo y conservar la conectividad administrativa.

---

# IP estática: responsabilidad manual del administrador

El asistente **no cambia automáticamente el direccionamiento permanente** durante el bootstrap.

Motivo:

```text
cambio de red
    ↓
sesión SSH perdida
    ↓
provisioning incompleto
```

Después del provisioning, configura una IP estática/persistente para la interfaz AD.

En Ubuntu/Netplan, revisar primero:

```bash
ip -br addr
ip route
ls -l /etc/netplan/
cat /etc/netplan/*.yaml
```

Después de editar Netplan, en una sesión remota es preferible:

```bash
sudo netplan try
```

en lugar de aplicar cambios a ciegas.

Tras confirmar la configuración:

```bash
ip -br addr
ip route
```

---

# Checklist post-instalación Linux

Después de `--bootstrap`, **provisionado no significa production-ready**.

El asistente genera un recordatorio persistente:

```text
/var/lib/debian-ad-assistant/POST-INSTALL.txt
```

Completar como mínimo:

## Red

- [ ] hacer persistente la IP de `AD_IFACE`;
- [ ] comprobar que la interfaz AD no recibe una IP inesperada por DHCP;
- [ ] revisar rutas y gateways;
- [ ] comprobar conectividad después de reiniciar;
- [ ] confirmar que la interfaz WAN mantiene salida a Internet.

Pruebas:

```bash
ip -br addr
ip route
ping -c 2 1.1.1.1
getent hosts raw.githubusercontent.com
```

## DNS

- [ ] confirmar que Samba responde al dominio;
- [ ] confirmar que Samba reenvía consultas externas;
- [ ] configurar clientes para usar el DC como DNS.

Pruebas:

```bash
dig @127.0.0.1 "$(hostname -f)"
dig @127.0.0.1 _ldap._tcp.$DOMAIN SRV
dig @127.0.0.1 _kerberos._tcp.$DOMAIN SRV
dig @127.0.0.1 raw.githubusercontent.com
```

También:

```bash
cat /etc/resolv.conf
```

## Samba / Active Directory

```bash
sudo systemctl status samba-ad-dc --no-pager
sudo samba-tool domain info 127.0.0.1
sudo samba-tool dbcheck --cross-ncs
sudo samba-tool ntacl sysvolcheck
```

Y ejecutar:

```bash
sudo bash ./debian-ad-assistant.sh --validate
```

El resultado debe revisarse antes de pasar el servidor a producción.

## Kerberos

```bash
kinit Administrator@REALM
klist
```

O utilizar la cuenta administrativa definida para el entorno.

## Firewall

```bash
sudo ufw status verbose
```

Revisar que:

- SSH solo esté abierto desde la red/IP administrativa esperada;
- los servicios AD solo estén accesibles desde redes autorizadas;
- no se haya expuesto accidentalmente Samba hacia la interfaz WAN.

## GPO

```bash
sudo samba-tool gpo listall
sudo samba-tool gpo aclcheck
sudo samba-tool ntacl sysvolcheck
```

Desde un cliente Windows unido al dominio:

```powershell
gpupdate /force
gpresult /r
```

## Backup

Crear el primer backup:

```bash
sudo bash ./debian-ad-assistant.sh --backup
```

Después:

- [ ] copiar el backup fuera del DC;
- [ ] mantener varias generaciones;
- [ ] probar recuperación en laboratorio;
- [ ] proteger el almacenamiento de backup.

## Reinicio de aceptación

Después de terminar red y tareas manuales:

```bash
sudo reboot
```

Tras volver:

```bash
sudo bash ./debian-ad-assistant.sh --status
sudo bash ./debian-ad-assistant.sh --validate
```

Un servicio que solo funciona antes del primer reboot no está listo para producción.

---

# Alta disponibilidad

Un único Domain Controller sigue siendo un punto único de fallo.

```text
             Clients
                │
       ┌────────┴────────┐
       │                 │
     DC01              DC02
   AD + DNS          AD + DNS
       │                 │
       └────────┬────────┘
                │
         replication
```

Para entornos donde la disponibilidad sea importante:

- desplegar al menos dos DC/DNS;
- separar fallos de host/hipervisor cuando sea posible;
- monitorizar DNS, LDAP, Kerberos, SMB y replicación;
- mantener backups off-host;
- probar restauraciones;
- documentar RTO/RPO;
- planificar ventanas de mantenimiento.

El script reduce riesgos operativos; **no garantiza por sí solo un SLA de 99,9 %**.

---

# Logs, estado y backups Linux

Directorios principales:

```text
/var/lib/debian-ad-assistant/
/var/log/debian-ad-assistant/
```

Cada ejecución mantiene información separada de:

- resultados;
- cambios;
- warnings;
- errores;
- snapshots;
- backups de configuración;
- informes.

Los secretos no deben almacenarse innecesariamente.

---

# Windows Server Security Assistant

## Targets

Targets principales:

- Windows Server 2019
- Windows Server 2022
- Windows Server 2025
- Windows PowerShell 5.1+

El asistente es **role-aware** y diferencia, entre otros, Domain Controllers de member servers.

---

# Ejecución Windows

## Interactivo

```powershell
.\pymes-windows-server-security.ps1
```

## Solo auditoría

```powershell
.\pymes-windows-server-security.ps1 -Mode Audit
```

## Auditoría + hardening interactivo

```powershell
.\pymes-windows-server-security.ps1 -Mode Harden
```

Los cambios sensibles requieren confirmación.

## Crear snapshot/configuration backup

```powershell
.\pymes-windows-server-security.ps1 -Mode Backup
```

## Directorio personalizado

```powershell
.\pymes-windows-server-security.ps1 `
  -Mode Audit `
  -ExportPath C:\SecurityAudit
```

## Sin colores

```powershell
.\pymes-windows-server-security.ps1 -Mode Audit -NoColor
```

## Firewall durante sesión remota

Por defecto, el script evita cambios globales de firewall si detecta una sesión remota.

Solo permitirlo deliberadamente:

```powershell
.\pymes-windows-server-security.ps1 `
  -Mode Harden `
  -AllowRemoteFirewallChange
```

Incluso entonces, los cambios de alto impacto requieren confirmación.

---

# Controles Windows actuales

El asistente revisa principalmente:

- versión/build;
- rol del servidor;
- roles/features instalados;
- red;
- Windows Firewall;
- Microsoft Defender;
- BitLocker;
- TPM;
- Secure Boot;
- SMBv1;
- SMB signing;
- guest SMB;
- RDP;
- NLA;
- administradores locales;
- Windows LAPS;
- PowerShell Script Block Logging;
- PowerShell Module Logging;
- LLMNR;
- evidencia de updates.

El informe no debe interpretarse como una certificación CIS completa.

---

# Pruebas post-hardening Windows

Después de cambios:

```powershell
.\pymes-windows-server-security.ps1 -Mode Audit
```

Revisar especialmente:

```powershell
Get-NetFirewallProfile
Get-MpComputerStatus
Get-MpPreference
Get-SmbServerConfiguration
Get-SmbClientConfiguration
Get-BitLockerVolume
```

RDP/NLA:

```powershell
Get-ItemProperty `
  'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' `
  -Name UserAuthentication
```

LLMNR debe tener:

```text
EnableMulticast = 0
```

Después de cambios relevantes o reboot, repetir auditoría.

---

# Baselines y CIS

Estos scripts siguen principios de hardening y utilizan como referencia:

- documentación oficial de Samba;
- benchmarks CIS aplicables;
- Microsoft Security Baselines;
- Microsoft Security Compliance Toolkit;
- herramientas nativas del sistema operativo.

La filosofía es:

```text
baseline
   ↓
audit
   ↓
plan
   ↓
backup
   ↓
confirm
   ↓
apply
   ↓
validate
```

No:

```text
benchmark
   ↓
aplicar cientos de cambios a ciegas
```

Un `PASS` significa que el control implementado por el script ha pasado.

**No significa que el servidor cumpla automáticamente todo el benchmark CIS.**

---

# Principios de seguridad del proyecto

1. Detectar antes de modificar.
2. Nunca reprovisionar silenciosamente un AD existente.
3. Confirmar cambios de impacto.
4. Crear backups/snapshots antes de cambios sensibles.
5. Mantener la vía de administración durante cambios de red/firewall.
6. Validar inmediatamente después de modificar.
7. No almacenar secretos innecesariamente.
8. Diferenciar servidor nuevo de infraestructura existente.
9. Ser repetible o rechazar claramente operaciones peligrosas.
10. Preferir herramientas oficiales/nativas.
11. Mantener dependencias al mínimo.
12. Diferenciar auditoría de cumplimiento.
13. Tratar políticas y baselines como código versionado.
14. Diseñar pensando en recuperación, no solo instalación.
15. No considerar un servidor listo hasta superar reboot + validación.

---

# Validación antes de producción

## Bash

Como mínimo:

```bash
bash -n debian-ad-assistant.sh
shellcheck debian-ad-assistant.sh
```

Matriz recomendada:

- Debian 13 limpio;
- Ubuntu Server 26.04 limpio;
- single NIC;
- dual NIC;
- ejecución local;
- ejecución SSH;
- `curl | sudo bash`;
- AD nuevo;
- AD existente;
- segunda ejecución;
- resolver roto;
- UFW existente;
- reboot;
- `--status`;
- `--audit`;
- `--validate`;
- `--backup`.

## PowerShell

Como mínimo:

```powershell
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path .\pymes-windows-server-security.ps1),
    [ref]$null,
    [ref]$errors
) | Out-Null

$errors
```

También se recomienda PSScriptAnalyzer.

Matriz:

- Server 2019;
- Server 2022;
- Server 2025;
- workgroup;
- member server;
- Domain Controller;
- RDP;
- WinRM;
- Defender activo;
- Defender pasivo/AV externo;
- firewall administrado por GPO;
- Windows no inglés.

---

# Referencias

Samba:

https://www.samba.org/samba/docs/current/man-html/samba-tool.8.html

Netplan:

https://netplan.readthedocs.io/

Microsoft Security Baselines:

https://learn.microsoft.com/windows/security/operating-system-security/device-management/windows-security-configuration-framework/windows-security-baselines

Microsoft Security Compliance Toolkit:

https://learn.microsoft.com/windows/security/operating-system-security/device-management/windows-security-configuration-framework/security-compliance-toolkit-10

CIS Benchmarks:

https://www.cisecurity.org/cis-benchmarks

---

# Estado del proyecto

Este repositorio debe considerarse una colección de herramientas administrativas en evolución.

Antes de utilizar una nueva versión en producción:

1. revisar cambios;
2. verificar SHA-256/release;
3. ejecutar en laboratorio;
4. disponer de acceso out-of-band cuando sea posible;
5. mantener un backup probado;
6. documentar el estado previo;
7. validar después de aplicar;
8. comprobar nuevamente después de reiniciar.
