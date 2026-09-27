# Server Assistants — Debian/Ubuntu + Windows Server

Colección de asistentes de administración y hardening pensados para **one-shot execution**, auditoría previa, cambios confirmados y trazabilidad.

## Archivos

| Archivo | Plataforma | Propósito |
|---|---|---|
| `debian-ad-assistant.sh` | Debian 13 / Ubuntu 26.04 LTS | Bootstrap/auditoría de Samba AD DC + Kerberos + DNS + Chrony + UFW + OUs/grupos + GPO base. |
| `pymes-windows-server-security.ps1` | Windows Server 2019/2022/2025 | Auditoría y hardening interactivo de firewall, Defender, SMB, RDP, administradores locales, LAPS, PowerShell y LLMNR. |

---

# 1. Filosofía de ejecución

El objetivo es poder pasar de un servidor recién instalado a una base funcional mediante una sola orden, pero **no se debe confundir one-shot con ejecución ciega**.

Orden recomendado:

```text
Repositorio versionado
        ↓
URL HTTPS concreta
        ↓
Descarga
        ↓
Integridad / revisión
        ↓
Ejecución con privilegios
        ↓
Auditoría + confirmaciones
        ↓
Cambios
        ↓
Validación
        ↓
Informe / logs
```

`curl | sudo bash` y `Invoke-Expression` son mecanismos de conveniencia. Para producción, es preferible descargar, verificar y ejecutar el fichero concreto.

---

# 2. Linux — Debian / Ubuntu

El script Linux está diseñado ahora para la familia Debian y no solo para Ubuntu. La matriz de referencia es:

- Debian 13 (trixie)
- Ubuntu 26.04 LTS

Debian 13 publica `samba-ad-dc` y `samba-ad-provision`; Ubuntu 26.04 también publica ambos paquetes. Los nombres de paquete son compatibles entre ambas distribuciones, aunque las versiones de Samba pueden diferir.

## One-shot con curl

```bash
curl -fsSL https://raw.githubusercontent.com/ORG/REPO/main/debian-ad-assistant.sh | sudo bash
```

## One-shot con wget

```bash
wget -qO- https://raw.githubusercontent.com/ORG/REPO/main/debian-ad-assistant.sh | sudo bash
```

## One-shot versionado — recomendado frente a `main`

```bash
curl -fsSL https://raw.githubusercontent.com/ORG/REPO/v2.1.0/debian-ad-assistant.sh | sudo bash
```

La ventaja es que una instalación posterior no cambia porque el branch `main` haya evolucionado.

## Descarga + SHA-256 + ejecución

```bash
curl -fsSLo /tmp/debian-ad-assistant.sh https://raw.githubusercontent.com/ORG/REPO/v2.1.0/debian-ad-assistant.sh \
  && sha256sum /tmp/debian-ad-assistant.sh \
  && sudo bash /tmp/debian-ad-assistant.sh
```

En un proceso serio, el hash calculado se compara con un valor publicado y confiable, no simplemente se muestra en pantalla.

## Ejecución local

```bash
sudo bash ./debian-ad-assistant.sh
```

## Auditoría sin cambios

```bash
sudo bash ./debian-ad-assistant.sh --audit
```

## Validación de un AD/DC existente

```bash
sudo bash ./debian-ad-assistant.sh --validate
```

## Ayuda

```bash
sudo bash ./debian-ad-assistant.sh --help
```

### Por qué el pipe sigue siendo interactivo

El script lee las respuestas desde `/dev/tty`, no desde stdin. Eso evita el problema clásico de:

```bash
curl ... | sudo bash
```

cuando el propio stdin está ocupado por el contenido del script.

---

# 3. Linux — flujo de bootstrap

```text
Audit
  ↓
Comprobación OS / red / hostname / IP
  ↓
Paquetes
  ↓
Servicio samba-ad-dc
  ↓
Chrony / timezone
  ↓
Provisioning del dominio
  ↓
DNS Samba + resolver local
  ↓
Kerberos
  ↓
OUs / grupos / Godzilla
  ↓
GPO base opcional
  ↓
UFW restringido por origen
  ↓
DNS / AD / dbcheck / SYSVOL
  ↓
Informe final
```

El bootstrap **se niega a reprovisionar automáticamente un AD existente**. Para una máquina ya provisionada utiliza `--validate`; la fase de reparación deliberada debe tratarse como una operación aparte.

La razón es evitar que una ejecución repetida modifique accidentalmente el dominio, `/etc/samba/smb.conf`, DNS o SYSVOL.

---

# 4. Linux — decisiones importantes

## Red

El script no intenta convertir DHCP en una IP estática automáticamente. Un cambio de red durante una ejecución remota puede cortar la sesión SSH a mitad del provisioning.

Antes de provisionar el DC se comprueba que la IP indicada está realmente asignada a la máquina.

## DNS

Samba AD DC necesita ser el DNS autoritativo del dominio.

Ubuntu suele utilizar `systemd-resolved`; Debian no lo instala por defecto. El script detecta la situación y trata por separado `systemd-resolved` y NetworkManager.

Si el gestor DNS puede sobrescribir el resolver local, el script no continua silenciosamente: obliga a dejar resuelto el camino `127.0.0.1 -> Samba DNS` antes de finalizar el bootstrap.

## `systemd-networkd`

No se deshabilita como efecto secundario del provisioning. Eso evita mezclar la gestión de red con la configuración del AD.

## Kerberos

La administración de GPO requiere un ticket del administrador AD, por ejemplo:

```bash
sudo kinit Godzilla@CIP.DANIEL.ORG
sudo klist
```

Después:

```bash
sudo samba-tool gpo listall --use-kerberos=required
```

## SYSVOL

Después de cargar GPO se ejecuta `samba-tool ntacl sysvolcheck`. `sysvolreset` no se ejecuta automáticamente sin confirmación explícita.

---

# 5. Linux — ejemplo de dominio del laboratorio

```text
DNS domain:       cip.daniel.org
Kerberos realm:   CIP.DANIEL.ORG
NetBIOS domain:   CIPDANIEL
DC FQDN:          cip.cip.daniel.org
DC IP:            192.168.1.162
Windows 7 lab:    192.168.1.119
LAN:              192.168.1.0/24
Timezone:         Europe/London
```

Los valores anteriores son solo la referencia del laboratorio de desarrollo. El script los solicita al operador y no debe depender de ellos para una instalación externa.

---

# 6. Linux — estado, logs y backups

Estado:

```text
/var/lib/cip-ad-assistant/
```

Logs e informes:

```text
/var/log/cip-ad-assistant/
```

Los backups se guardan por ejecución. Los ficheros de configuración y reportes usan permisos restrictivos.

El password final de `Administrator` no se guarda por el script: tras el provisioning se establece mediante el prompt de `samba-tool user setpassword Administrator`.

---

# 7. Linux — GPO

Se generan fuentes JSON locales:

```text
/var/lib/cip-ad-assistant/gpo/
├── user-baseline.json
└── machine-baseline.json
```

Después se cargan mediante:

```bash
sudo samba-tool gpo load '{GUID}' \
  --content=/var/lib/cip-ad-assistant/gpo/user-baseline.json \
  --use-kerberos=required
```

**Las llaves `{}` del GUID son intencionadas y necesarias para el formato utilizado.**

Las GPO base del asistente se enlazan al dominio para el laboratorio. Esto no equivale a un filtrado de seguridad exclusivo por `Domain Users`; ese nivel de afinado debe hacerse con ACL/GPMC cuando sea necesario.

---

# 8. Linux — UFW

Cuando se habilita, el modelo es:

```text
default deny incoming
default allow outgoing
```

Se solicitan dos ámbitos:

```text
AD_CLIENT_CIDR → clientes que deben consumir AD
SSH_SOURCE     → estación/red de administración
```

Esto es preferible a:

```bash
sudo ufw allow 22/tcp
```

Para un entorno pequeño se puede usar un `/32` para SSH y una subred específica para los servicios AD.

---

# 9. Windows Server — ejecución

El script usa:

```powershell
#requires -RunAsAdministrator
```

## Ejecución local

```powershell
.\pymes-windows-server-security.ps1
```

## Solo auditoría

```powershell
.\pymes-windows-server-security.ps1 -AuditOnly
```

## Directorio de informes personalizado

```powershell
.\pymes-windows-server-security.ps1 -ExportPath C:\SecurityAudit
```

## One-shot descargando primero — recomendado

```powershell
$u='https://raw.githubusercontent.com/ORG/REPO/v0.2.0/pymes-windows-server-security.ps1'; $p=Join-Path $env:TEMP 'pymes-windows-server-security.ps1'; Invoke-WebRequest -Uri $u -OutFile $p; Get-FileHash $p -Algorithm SHA256; Unblock-File $p; & $p
```

El hash mostrado debe compararse con el hash publicado para la versión elegida antes de ejecutar en producción.

## One-shot directo con `Invoke-Expression`

```powershell
Invoke-Expression (Invoke-RestMethod 'https://raw.githubusercontent.com/ORG/REPO/v0.2.0/pymes-windows-server-security.ps1')
```

Es cómodo, pero **no es el método recomendado** porque descarga y ejecuta el contenido sin una revisión intermedia. Microsoft documenta que `Bypass` no bloquea ni avisa y que la política de ejecución es defensa en profundidad, no una frontera de seguridad.

---

# 10. Windows Server — alcance actual

La versión actual audita:

```text
Sistema / rol
Red
Firewall
Defender
BitLocker
TPM / Secure Boot
SMB / SMBv1 / signing / guest
RDP / NLA
Administradores locales
Windows LAPS
PowerShell logging
LLMNR
Hotfix evidence
```

Las remediaciones son interactivas y se registran. No se deben aplicar indiscriminadamente sobre un Domain Controller. El script trata explícitamente algunos cambios como sensibles al rol.

---

# 11. GitHub recomendado

Una estructura sencilla:

```text
repo/
├── debian-ad-assistant.sh
├── pymes-windows-server-security.ps1
├── README.md
└── checksums.txt
```

Después:

```bash
git tag v2.1.0
git push origin v2.1.0
```

Y para Windows, mantener una versión independiente, por ejemplo `v0.2.0`.

Publica también hashes SHA-256 de los artefactos. Para cambios importantes, usa una nueva versión/tag en lugar de sobrescribir silenciosamente un fichero ya utilizado por otros servidores.

---

# 12. Revisión estricta — criterios que deben mantenerse

Los asistentes deben conservar estas reglas:

```text
1. Detectar antes de modificar
2. No destruir configuración existente
3. Confirmar cambios de impacto
4. No guardar secretos innecesariamente
5. No romper sesiones remotas durante el bootstrap
6. Validar después de cada bloque crítico
7. Registrar qué se hizo y qué no
8. Ser repetibles o rechazar claramente una repetición peligrosa
9. Diferenciar auditabilidad de cumplimiento
10. Tratar las políticas de seguridad como código versionado
```

---

# 13. Referencias operativas

La parte Samba AD/DC se basa en el procedimiento actual de Ubuntu y en la separación de paquetes publicada por Debian/Ubuntu. Ver documentación oficial antes de promover estos scripts a producción.

- Ubuntu Server — Provisioning a Samba AD/DC
- Debian packages — `samba-ad-dc` / `samba-ad-provision`
- Microsoft Learn — Windows LAPS
- Microsoft Learn — SMBv1
- Microsoft Learn — PowerShell execution policies
