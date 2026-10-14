# sysadmin

Herramientas para administradores IT y auditores de seguridad: **operación de AD**, **auditorías offline** y **descubrimiento desde un equipo auditor**.

[English](README.md) · **Español**

## Elige la tarea

| Necesitas… | Empieza por… |
|---|---|
| Documentar auditoría, inventario, hallazgos y PDF | [Audit Workbench](audit-workbench/README_ES.md) |
| Descubrir equipos en una red autorizada | [Preparar discovery e importar capturas](audit-workbench/discovery/README_ES.md) |
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

**Audit Workbench:** sirve la aplicación y abre <http://127.0.0.1:8765>.

```bash
python3 -m http.server 8765 --bind 127.0.0.1 --directory audit-workbench
```

Crea un expediente → registra inventario y evidencias → revisa hallazgos → genera PDF.
Exporta también JSON para conservar una copia restaurable: el PDF es el entregable,
no el respaldo. Para tablets y uso offline, consulta [instalación](audit-workbench/INSTALLATION.md).
Los datos pertenecen al origen del navegador; cambiar host o puerto no los migra.

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
Los seis scripts de la raíz siguen siendo descargables y autónomos; no requieren la PWA.

**Discovery:** desde el equipo auditor conectado a la red:

```bash
bash audit-workbench/discovery/setup.sh --check
bash audit-workbench/discovery/run.sh
```

Windows: `audit-workbench\discovery\iniciar.cmd`. Requiere Python 3.9+;
Nmap es opcional. Revisa y autoriza expresamente el alcance; importa después el JSON
en Hardware y Redes. No instala agentes remotos ni requiere excepciones de seguridad
del navegador. No enumera vulnerabilidades ni software instalado.

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
| Modelo de datos y seguridad de la PWA | [Seguridad](audit-workbench/SECURITY.md) |
| Modificar código y ejecutar pruebas offline | [Mantenimiento](docs/MAINTENANCE.md) |

```bash
python3 tools/verify.py              # Sintaxis Bash y paridad de clientes
python3 tools/verify.py --workbench  # También pruebas offline de PWA; requiere Node.js
```

[Licencia MIT](LICENSE).
