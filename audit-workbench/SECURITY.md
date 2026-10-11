# Modelo de seguridad de Audit Workbench

## Superficie

- Aplicación web sin backend, cuentas, servidores propios, cookies de seguimiento, analítica ni librerías externas.
- Expedientes locales en IndexedDB y, cuando falla, `localStorage`. El navegador no cifra los JSON exportados y el usuario gestiona su almacenamiento seguro.
- Imágenes/logos pasan por canvas y se convierten a JPEG base64; importaciones validan tamaño, tipo de esquema y campos permitidos.
- Textos se escapan antes de insertarlos en HTML; no se evalúa código proveniente de expedientes JSON ni hay HTML arbitrario del cliente.
- CSP sin recursos externos salvo `connect-src https://cveawg.mitre.org` **para consultas CVE individualmente confirmadas**; la acción de enlaces CVE.org abre una pestaña solo al pulsar.
- Service worker con caché de archivos estáticos **exclusivamente**; no intercepta ni guarda respuestas de CVE, JSON, PDF o datos de negocio.

## Amenazas residuales

Una persona con acceso al perfil del navegador/almacenamiento del dispositivo puede tener acceso a los expedientes. Una extensión maliciosa, sincronización de navegador, malware, copias de seguridad del sistema operativo, un dispositivo perdido o una cuenta compartida también pueden comprometer la confidencialidad. Las capturas pueden contener IP, nombres de usuario o secretos accidentales. Por ello:

- Cifra disco/volumen y copias de backup; exige bloqueo de sesión y acceso individual.
- Usa perfiles separados por cliente/consultor si el procedimiento lo permite.
- Nunca pegues contraseñas, tokens, hashes reutilizables ni claves sin redacción. Inspecciona capturas antes de incorporarlas.
- Conserva originales fuera de la aplicación con hash e identificadores de custodia cuando sea necesario.
- Valida el destinatario antes de compartir, y clasifica el informe y el JSON.
- No uses `mailto` para enviar documentos sin adjuntarlos manualmente; no se realiza SMTP/API automático.

## Operaciones online opcionales

| Acción | Destino | Datos transmitidos | Disparador |
|---|---|---|---|
| Consultar CVE | `https://cveawg.mitre.org/api/cve/CVE-...` | Identificador CVE solamente | Botón + confirmación (consulta puede fallar por CORS). |
| Ver CVE.org | CVE.org | Identificador CVE en URL | Botón «Ver en CVE.org». |
| Compartir JSON | Destino que elija el usuario en el diálogo del SO | **JSON completo del expediente** | Botón + confirmación; API Web Share si disponible. |
| Preparar correo | Cliente de correo del usuario | Asunto y texto con nombre de cliente/proyecto; **ningún adjunto** | Botón + confirmación, destinatario manual. |
| Nube/repo externo | No implementado | No se transmite nada automáticamente | Tras exportar JSON/PDF, transmisión manual bajo autorización. |

No existe búsqueda de CVE por producto/versión ni escaneo automático; un registro CVE tampoco acredita afectación de un activo. **La ausencia de consulta online no bloquea la auditoría ni el PDF.**

## Límites y seguimiento

Actualmente no hay autenticación, cifrado de expedientes dentro de la app, firmas digitales, control multiusuario, logs de acceso, encriptación extremo a extremo ni verificación de integridad firmada. Antes de implementar cualquier conector cloud se necesitarían autorización del cliente, cifrado, gestión de credenciales fuera del frontend, permisos mínimos, revocación y auditoría de acciones. No se deben introducir secretos API persistentes en JavaScript público.
