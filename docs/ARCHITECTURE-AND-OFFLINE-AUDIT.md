# Revisión arquitectónica y propuesta de auditoría offline

## Alcance y estado

Diagnóstico inicial realizado sobre `main` el 11-10-2026. Esta revisión es documental y estática: **no se ha ejecutado hardening ni probado un join/leave contra sistemas reales**.

## Hallazgos observables

| Prioridad | Hallazgo | Acción |
| --- | --- | --- |
| P1 | README principal presenta cuatro asistentes, pero existen también `rhel-ad-assistant.sh` y `rhel-ad-client-assistant.sh`. | Mantener una matriz de seis scripts por SO, rol, modos y advertencias de soporte. |
| P1 | Los clientes `linux-ad-client-assistant.sh` y `rhel-ad-client-assistant.sh` tienen 4.414 líneas cada uno y 25 diferencias de línea. | Planificar generación desde fuente común preservando nombres, tablas nftables, servicios y paths propios, tras ensayos de lifecycle. |
| P1 | El README ronda las 1.586 líneas. | Dividir en guías de instalación, DC Linux/Windows, clientes Linux/Windows, recuperación, reportes, amenazas y troubleshooting. |
| P1 | Modos y logs difieren por plataforma. | Especificar contrato de evidencias versionado y correlación sin imponer paridad forzada a las APIs nativas. |
| P0 | Join, rollback, DNS, firewall y provisioning operan sobre infraestructura crítica. | Mantener los scripts autocontenidos, exigir pruebas de regresión de estados y evitar refactorizaciones simultáneas. |

## Ruta de integración recomendada

1. **Documentar capacidades verificadas.** Matriz de plataformas (Debian/Ubuntu, Rocky/Alma, RHEL con límite de soporte explícito, Windows Server, equipos cliente), argumentos y requisitos.
2. **Validación estática en CI.** `bash -n`, ShellCheck con exclusiones razonadas, parser de PowerShell, PSScriptAnalyzer, comprobación de enlaces/documentación. No ejecutar tareas modificadoras en CI general.
3. **Contrato de auditoría JSON v1.** Campos mínimos: `schemaVersion`, `tool`, `toolVersion`, `capturedAt`, `hostname`, `checks[]` con `id`, `result`, `message`, `evidenceIds[]` y `evidence[]`. El export debe ser explícito, solo lectura y sanear secretos, SID y datos identificativos innecesarios.
4. **Importador de auditoría.** Normalizar formatos de los seis asistentes por adaptadores independientes; comprobar versión de esquema y conservar la fuente original para trazabilidad.
5. **Mantenimiento Linux.** Unificar únicamente después de fixtures que comprueben paridad de estados de join/leave/recover y diferencias intencionales de firewall y systemd.

## Offline Audit Workbench (prototipo independiente)

Un único HTML autónomo puede cubrir cliente/alcance, inventario físico, red, software, checklist de controles, hallazgos con severidad y remediación, registro de evidencias y conclusiones. El expediente se exporta en JSON y el navegador permite imprimir el informe a PDF (sin bibliotecas ni Internet). El almacenamiento temporal del navegador no reemplaza backups. No incorporar secretos o archivos de evidencia sin cifrado y custodia.

### Criterios de aceptación

- Abre sin red ni servidor, sin recursos CDN.
- Edición manual y persistencia exportable/importable con esquema validado.
- Informe entregable con fecha, cliente, alcance, controles, hallazgos y limitaciones.
- Datos textuales escapados en HTML; eliminación confirmada; sin ejecución remota.
- Los scripts existentes no se alteran hasta superar pruebas en laboratorio.
