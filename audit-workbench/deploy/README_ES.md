# Despliegue HTTPS de Audit Workbench (PWA)

[Instalación por dispositivo](../INSTALLATION_ES.md) · [Seguridad](../SECURITY_ES.md)

**Objetivo:** ofrecer una URL HTTPS estable desde la que el auditor instala la PWA en portátil, tablet o móvil. **No crea una plataforma multiusuario ni almacena expedientes en el servidor.** La imagen solo contiene `index.html`, `sw.js`, el manifiesto, CSS, JavaScript de la interfaz, fuentes e iconos. No incluye Discovery, ejecutables, JSON de clientes, evidencias, credenciales ni PDF.

## Requisitos

- Servidor Linux con Docker Engine y **Docker Compose v2**.
- Subdominio propio, p. ej. `auditoria.example.com`, con DNS **A/AAAA** apuntando al servidor (elimina registros incorrectos).
- Puertos públicos **80/TCP** y **443/TCP** alcanzables por las autoridades de certificación y los navegadores; comprueba cortafuegos, NAT y proxy/CDN.
- Acceso HTTPS con certificado **válido y confiable** en cada dispositivo. Caddy solicita y renueva certificados automáticamente cuando DNS y conectividad permiten ACME.
- El dispositivo cliente debe poder llegar a la URL al menos una vez para completar la instalación y la caché offline.

No hace falta instalar Python, Nmap ni una base de datos **en el servidor web**.

## Ponerlo en marcha

Desde la raíz del repositorio `sysadmin`:

```bash
cd audit-workbench/deploy
cp .env.example .env
# Edita .env con tu dominio real y correo
docker compose config --quiet
docker compose up --detach --build
docker compose logs -f audit-workbench
```

Abre `https://auditoria.example.com/` (sustituyendo por tu dominio). Si el certificado no se emite, **corrige DNS/puertos/relojes/ACME**: no desactives la validación TLS en los clientes. El primer arranque requiere conexión para descargar la imagen Caddy y emitir el certificado.

Para una comprobación de recursos, cabeceras HTTPS, Service Worker y archivos no expuestos:

```bash
python3 smoke_https.py https://auditoria.example.com
```

La comprobación solo solicita recursos de la aplicación; no importa expedientes ni ejecuta descubrimiento de red.

## Actualizar con seguridad

```bash
# Antes: exporta backups JSON de los dispositivos que tienen expedientes.
git pull --ff-only
cd audit-workbench/deploy
docker compose up --detach --build
```

El código nuevo se sirve a los visitantes, pero **el Service Worker no reemplaza una versión activa sin la aceptación del usuario**: la PWA ofrece guardar y actualizar. Verifica la función offline después de cada despliegue. Los volúmenes `caddy_data` y `caddy_config` persisten certificados y configuración de Caddy; no guardan auditorías.

No ejecutes `docker compose down --volumes` sin querer eliminar también los certificados. Conserva respaldo del volumen de certificados según la política de tu servidor.

## Instalar en cada dispositivo

1. Visita la URL **HTTPS** con un navegador compatible.
2. Android/Chrome/Edge: usa **Instalar aplicación** en el menú si está disponible. Safari iOS/iPadOS: **Compartir → Añadir a pantalla de inicio**.
3. Ábrela desde el icono y en **Protección del trabajo offline** comprueba que los recursos están preparados.
4. Prueba abrirla sin conexión y vuelve a conectarte para actualizaciones.
5. Exporta periódicamente **Copias y exportaciones → Backup JSON** a almacenamiento protegido.

**Cada dispositivo, navegador y origen HTTPS tiene su propia IndexedDB.** No hay sincronización entre tablets, ni SSO, ni cuentas. Compartir una URL no comparte expedientes. Cambiar de `http://localhost` a `https://auditoria.example.com`, de dominio o de perfil **no migra los datos**: exporta e importa el backup JSON desde el origen anterior.

## Protección de datos y superficie de exposición

- No publiques toda la carpeta del repositorio con un servidor de ficheros indiscriminado: especialmente `discovery/`, `collect-local.*`, `tests/`, scripts administrativos, expedientes y backups. El Dockerfile aplica una **lista positiva de archivos estáticos** y el servidor no tiene endpoints de subida ni ejecución.
- La URL pública hace público el **código de la PWA**, no los expedientes locales. Para uso exclusivo de una organización, limita acceso mediante VPN, firewall corporativo o un reverse proxy con autenticación revisada; comprueba que esas políticas no rompan la instalación/actualización/offline.
- HTTPS protege el transporte. Los expedientes continúan en el almacenamiento del navegador; exige cifrado de disco, bloqueo de pantalla, perfiles individuales y backups cifrados.
- Los scripts Discovery siguen ejecutándose **localmente en el portátil del auditor**. La página HTTPS no recibe privilegios de escaneo ni ejecuta binarios remotamente.
- El servidor incluye cabeceras anti-iframe, no-referrer, MIME seguro y HSTS sin `includeSubDomains` ni `preload`; conserva la CSP de la aplicación. No incorpores secretos a JavaScript, HTML ni variables accesibles al navegador.
- `deploy/.env` se excluye de Git. Nunca almacenes backups en el directorio publicado.

## ¿Y si ya existe un proxy HTTPS?

También puedes servir **únicamente** `index.html`, `sw.js`, `manifest.webmanifest`, `css/`, `js/`, `fonts/` e `icons/` desde tu servidor estático, preferiblemente en la raíz de un subdominio dedicado con HTTPS. Preserva los tipos MIME de JS, manifiesto e iconos, las cabeceras de seguridad y `Cache-Control: no-store` para `sw.js` y `index.html`. No uses una regla SPA que devuelva HTML ante peticiones de JS ausentes.

Para un dominio solo accesible por VPN/LAN, la emisión pública de certificados mediante desafíos HTTP/TLS puede no funcionar. Utiliza un certificado emitido por una CA confiable para esos dispositivos (p. ej. DNS-01 con proveedor compatible o un proxy con la PKI corporativa correctamente instalada), **sin excepciones TLS**. Este Compose de ejemplo está destinado al despliegue con puertos públicos 80/443.

## Verificación

`docker compose config --quiet` valida la sintaxis de Compose. El pipeline comprueba el manifiesto, el contexto de la imagen y la configuración de Caddy. Tras desplegar, ejecuta `python3 smoke_https.py URL` y comprueba la instalación/offline en un dispositivo real; **no basta con que el HTTPS responda**.
