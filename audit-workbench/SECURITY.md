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

## Conexiones cifradas opcionales (v6)

Las credenciales WebDAV se cifran localmente con AES-GCM, derivando la clave de una frase de paso del auditor con PBKDF2-SHA256/310.000 rondas y sal aleatoria. Se necesitan contexto seguro (HTTPS o localhost) y Web Crypto API. La frase de paso no se persiste, y el perfil se desbloquea manualmente cada sesión. **No hay un servidor de respaldo de claves ni recuperación de contraseñas**. La protección no equivale a un gestor de secretos empresarial ni cubre terminales comprometidos o acceso a la sesión desbloqueada.

No utilices el flujo de WebDAV con credenciales personales principales: crea una **contraseña de aplicación** dedicada, revocable y con permisos mínimos. Las transferencias requieren HTTPS válido, CORS permitido por el servidor y confirmación explícita del auditor. Si el servidor no permite CORS, utiliza exportación manual. El contenido JSON no se cifra de extremo a extremo con una clave separada antes de subir: WebDAV lo transporta por TLS; la custodia y el cifrado en reposo del servidor corresponden a la configuración de Nextcloud/cliente.

La CSP permite `connect-src https:` únicamente para soportar servidores Nextcloud definidos por el usuario y consultas CVE expresas. No hay analítica, conexiones en segundo plano ni inyección de scripts desde dominios externos. Configura una CSP más restrictiva en el reverse proxy cuando un despliegue corporativo utiliza proveedores conocidos.

El algoritmo de checksum español de DNI/NIE y el de NIF ordinario de entidad son **validadores de formato y control**, no verificaciones contra el censo de la AEAT ni contra la identidad de sus titulares.

## Exportaciones tabulares y carpeta de respaldo

- **JSON:** única copia restaurable de auditorías. Puede incluir imágenes, identificadores y datos personales sin cifrar; requiere custodia cifrada.
- **XLSX/CSV:** exportaciones de tablas sin imágenes. CSV protege campos que empiezan por caracteres interpretables como fórmulas; XLSX utiliza celdas de texto, sin macros ni fórmulas generadas. Revisa cada entregable antes de enviarlo.
- **Carpeta local:** la aplicación solo escribe en una carpeta seleccionada explícitamente mediante File System Access API, si está disponible. El permiso puede revocarse al cerrar o actualizar el navegador. No se proporciona ejecución automática con la app cerrada. Los nombres de carpeta y los tiempos de respaldo se guardan como preferencias; los permisos se custodian localmente mediante IndexedDB.
- No utilices como destino del backup la carpeta pública servida por Python o un servidor web: los expedientes podrían quedar accesibles a terceros.
