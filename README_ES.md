# sysadmin

Asistentes autónomos de administración Windows/Linux, Active Directory, diagnóstico y recuperación.

[English](README.md) · **Español**

## Elige la tarea

| Necesitas… | Empieza por… |
|---|---|
| Administrar Samba AD en Debian/Ubuntu | `debian-ad-assistant.sh --audit` |
| Administrar Samba AD en Rocky/AlmaLinux | `rhel-ad-assistant.sh --audit` |
| Diagnosticar/administrar AD DS en Windows | `windows-ad-assistant.ps1 -Mode Audit` |
| Unir, diagnosticar o recuperar clientes Linux de AD | `linux-ad-client-assistant.sh --audit` |
| Usar la variante Linux con identidad RHEL | `rhel-ad-client-assistant.sh --audit` |
| Unir, diagnosticar o recuperar clientes Windows de AD | `windows-ad-client-assistant.ps1 -Mode Audit` |

## Primer uso en minutos

```bash
git clone https://github.com/sempitern0/sysadmin.git
cd sysadmin
```

**Asistentes AD:** revisa el script, consulta la ayuda y audita desde una consola elevada.

```bash
bash ./linux-ad-client-assistant.sh --help
sudo bash ./linux-ad-client-assistant.sh --audit
# Para un controlador Debian/Ubuntu:
sudo bash ./debian-ad-assistant.sh --audit
```

```powershell
Get-Help .\windows-ad-client-assistant.ps1 -Detailed
.\windows-ad-client-assistant.ps1 -Mode Audit
# Para un controlador Windows:
.\windows-ad-assistant.ps1 -Mode Audit
```

En Windows utiliza la política de ejecución/firma aprobada por tu organización.
Los seis scripts de la raíz son descargables y autónomos.

## Criterios de operación

- Empieza por auditoría/diagnóstico y aplica cambios con una vía de recuperación.
- Conserva backups restaurables y acceso por consola antes de cambiar DNS, SSH, firewall o pertenencia al dominio.
- El aprovisionamiento Samba AD DC en RHEL está protegido por ser un rol no soportado; consulta las [notas de plataforma](docs/OPERATIONS_ES.md#control-plane-enterprise-linux).
- Las implementaciones difieren entre plataformas. Una comprobación de sintaxis o un hardening no certifican preparación para producción ni cumplimiento completo.

## Referencia, recuperación y mantenimiento

| Consulta | Guía |
|---|---|
| Comandos AD, DNS, GPO, IDS, backups y recuperación | [Referencia operativa](docs/OPERATIONS_ES.md) |
| Diagnosticar DNS, Kerberos o unión a dominio | [Resolución de problemas](docs/OPERATIONS_ES.md#troubleshooting) |
| Localizar estado, snapshots y logs | [Rutas de estado](docs/OPERATIONS_ES.md#rutas-de-estado-y-logs) |
| Modificar código y ejecutar pruebas offline | [Mantenimiento](docs/MAINTENANCE.md) |

```bash
python3 tools/verify.py              # Sintaxis Bash y paridad de clientes
```

[Licencia MIT](LICENSE).
