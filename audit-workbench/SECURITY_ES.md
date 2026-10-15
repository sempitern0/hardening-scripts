# Modelo de seguridad de Audit Workbench

[English](SECURITY.md) · **Español**

## Despliegue HTTPS

El [despliegue opcional](deploy/README_ES.md) sirve solo archivos estáticos permitidos mediante Caddy; no aloja expedientes, no ejecuta Discovery y no incorpora endpoints de escritura. Publicar la URL hace público el código cliente. TLS no añade cifrado a IndexedDB ni sincroniza perfiles: cada dispositivo debe proteger su almacenamiento y sus copias. Antes de migrar de dominio exporta el JSON. El administrador debe mantener Docker/Caddy y el servidor actualizados y aplicar controles de acceso de red si el servicio no debe ser público.

## Superficie

- Aplicación web sin backend, cuentas, servidores propios, cookies de seguimiento, analítica ni librerías externas.
- Expedientes locales en IndexedDB y, cuando falla, `localStorage`. El navegador no cifra los JSON exportados y el usuario gestiona su almacenamiento seguro.
- Imágenes/logos pasan por canvas y se convierten a JPEG base64; importaciones validan tamaño, tipo de esquema y campos permitidos.
- Textos se escapan antes de insertarlos en HTML; no se evalúa código proveniente de expedientes JSON ni hay HTML arbitrario del cliente.
- La CSP limita scripts y recursos ejecutables al origen; `connect-src https:` admite integraciones HTTPS iniciadas expresamente por el auditor (CVE y WebDAV/Nextcloud). No hay conexión a servicios externos por defecto.
- Service worker con caché de archivos estáticos; no está diseñado para conservar expedientes, respuestas de CVE, archivos PDF ni credenciales. La comprobación explícita del servidor omite la caché.

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
| Subir JSON sin cifrar mediante WebDAV | Servidor Nextcloud configurado | **Expediente completo sin cifrado a nivel de archivo** (TLS en tránsito) | Desbloqueo de conexión, botón y confirmación. Se desaconseja frente al backup cifrado. |
| Backup JSON cifrado | Nextcloud configurado | Archivo cifrado AES-256-GCM antes de enviarse | Frase de cifrado, botón y confirmación. |
| Compartir PDF | Nextcloud configurado | PDF completo, no cifrado a nivel de archivo | Selección de PDF, subida explícita y confirmación. |
| Enlace temporal PDF | API OCS de Nextcloud | Solicitud de enlace de lectura con contraseña y caducidad | Creación explícita después de subir el PDF. |
| Revocar enlace | API OCS de Nextcloud | Identificador de compartición de la sesión | Confirmación expresa. |
| Otros proveedores (S3/Google Drive/OneDrive) | No integrados | Ninguno | Requieren desarrollo o envío manual. |

No existe búsqueda de CVE por producto/versión ni escaneo automático; un registro CVE tampoco acredita afectación de un activo. **La ausencia de consulta online no bloquea la auditoría ni el PDF.**

## Límites y seguimiento

La PWA no tiene autenticación de usuario propia, control multiusuario, firmas digitales, auditoría de acceso al perfil ni verificación de integridad firmada. Los expedientes permanecen en claro en IndexedDB: **el cifrado opcional protege el archivo de backup exportado, no cifra automáticamente toda la base local**. Las credenciales Nextcloud pueden guardarse cifradas bajo una frase local; una sesión de navegador desbloqueada o comprometida sigue siendo una amenaza. Para otros proveedores harán falta autorización del cliente, permisos mínimos y una estrategia verificable de revocación. No se deben introducir secretos API persistentes en JavaScript público.

## Conexiones y copias cifradas opcionales

Las credenciales WebDAV se cifran localmente con AES-GCM, derivando la clave de una frase de paso del auditor con PBKDF2-SHA256/310.000 rondas y sal aleatoria. Se necesitan contexto seguro (HTTPS o localhost) y Web Crypto API. La frase de paso no se persiste, y el perfil se desbloquea manualmente cada sesión. **No hay un servidor de respaldo de claves ni recuperación de contraseñas**. La protección no equivale a un gestor de secretos empresarial ni cubre terminales comprometidos o acceso a la sesión desbloqueada.

No utilices WebDAV con credenciales personales principales: crea una **contraseña de aplicación** dedicada, revocable y con permisos mínimos. Las transferencias requieren HTTPS válido, CORS permitido por el servidor y confirmación explícita del auditor. Si el servidor no permite CORS, utiliza exportación manual. Existen dos rutas distintas: la subida JSON original no aplica cifrado adicional al archivo (solo TLS en tránsito); **la función de backup cifrado** deriva una clave independiente con PBKDF2-SHA256 y cifra el JSON mediante AES-256-GCM antes de transferirlo. El PDF tampoco incorpora cifrado propio del archivo, aunque viaja por HTTPS. La custodia del almacenamiento remoto y sus controles de acceso corresponde al servidor y al cliente.

La CSP permite `connect-src https:` únicamente para soportar servidores Nextcloud definidos por el usuario y consultas CVE expresas. No hay analítica, conexiones en segundo plano ni inyección de scripts desde dominios externos. Configura una CSP más restrictiva en el reverse proxy cuando un despliegue corporativo utiliza proveedores conocidos.

El algoritmo de checksum español de DNI/NIE y el de NIF ordinario de entidad son **validadores de formato y control**, no verificaciones contra el censo de la AEAT ni contra la identidad de sus titulares.

## Exportaciones tabulares y carpeta de respaldo

- **JSON:** formato restaurable de auditorías. La exportación normal no cifra el archivo y puede incluir imágenes, identificadores y datos personales; requiere custodia cifrada.
- **Backup cifrado (`.awenc`):** contiene JSON cifrado con frase independiente y puede recuperarse desde el panel de conexiones. La pérdida de la frase puede impedir la recuperación.
- **XLSX/CSV:** exportaciones de tablas sin imágenes. CSV protege campos que empiezan por caracteres interpretables como fórmulas; XLSX utiliza celdas de texto, sin macros ni fórmulas generadas. Revisa cada entregable antes de enviarlo.
- **Carpeta local:** la aplicación solo escribe en una carpeta seleccionada explícitamente mediante File System Access API, si está disponible. El permiso puede revocarse al cerrar o actualizar el navegador. No se proporciona ejecución automática con la app cerrada. Los nombres de carpeta y los tiempos de respaldo se guardan como preferencias; los permisos se custodian localmente mediante IndexedDB.
- No utilices como destino del backup la carpeta pública servida por Python o un servidor web: los expedientes podrían quedar accesibles a terceros.
