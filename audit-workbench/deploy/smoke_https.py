#!/usr/bin/env python3
"""Post-deployment HTTPS smoke check: static assets, headers and accidental exposure."""
import argparse
import json
from urllib.error import HTTPError, URLError
from urllib.parse import urljoin, urlsplit
from urllib.request import Request, urlopen


def read(base, path):
    url = urljoin(base, path)
    if urlsplit(url).netloc != urlsplit(base).netloc:
        raise ValueError('URL de destino fuera del origen HTTPS.')
    try:
        with urlopen(Request(url, headers={'User-Agent': 'AuditWorkbenchDeploymentCheck/1'}), timeout=12) as response:
            return response.status, response.headers, response.read(3_000_000)
    except HTTPError as error:
        return error.code, error.headers, error.read(4096)


def verify(base):
    parsed = urlsplit(base)
    if parsed.scheme != 'https' or not parsed.netloc or parsed.username or parsed.password or parsed.path not in ('', '/'):
        raise ValueError('Especifica la raíz de un dominio HTTPS válido, sin usuario, puerto interno ni subruta.')
    root = base.rstrip('/') + '/'
    index_code, index_headers, html = read(root, 'index.html')
    assert index_code == 200 and b'Audit Workbench' in html, 'No se ha servido la PWA.'
    assert 'nosniff' in index_headers.get('X-Content-Type-Options', '').lower(), 'Falta X-Content-Type-Options.'
    assert index_headers.get('X-Frame-Options', '').upper() == 'DENY', 'Falta X-Frame-Options.'
    assert 'max-age=' in index_headers.get('Strict-Transport-Security', ''), 'Falta HSTS.'
    assert 'no-store' in index_headers.get('Cache-Control', ''), 'La entrada no debe usar caché HTTP persistente.'
    sw_code, sw_headers, sw = read(root, 'sw.js')
    assert sw_code == 200 and b'AUDIT_WORKBENCH_HEALTH' in sw, 'Service Worker ausente.'
    assert 'javascript' in sw_headers.get_content_type(), 'MIME incorrecto de Service Worker.'
    assert 'no-store' in sw_headers.get('Cache-Control', ''), 'El Service Worker puede quedar obsoleto.'
    code, _, raw_manifest = read(root, 'manifest.webmanifest')
    assert code == 200, 'No se ha servido el manifiesto.'
    manifest = json.loads(raw_manifest)
    assert manifest.get('display') == 'standalone', 'Manifiesto no instalable.'
    for resource in ('css/styles.css', 'js/app.js', 'icons/icon-192.png', 'icons/icon-512.png'):
        code, _, content = read(root, resource)
        assert code == 200 and content, 'Recurso ausente: ' + resource
    for forbidden in ('discovery/discover.py', 'collect-local.ps1', 'tests/test_static.py',
                      'README_ES.md', 'deploy/.env', 'no-existe.js'):
        code, _, _ = read(root, forbidden)
        assert code == 404, 'El servidor ha expuesto un archivo no publicado: ' + forbidden
    print('OK · PWA HTTPS, cabeceras, Service Worker, manifiesto, recursos y exclusiones.')


def main():
    parser = argparse.ArgumentParser(description='Comprueba un despliegue HTTPS existente de Audit Workbench.')
    parser.add_argument('url', help='https://auditoria.example.com')
    args = parser.parse_args()
    try:
        verify(args.url)
    except (ValueError, AssertionError, URLError, TimeoutError, OSError) as error:
        parser.exit(1, 'ERROR: ' + str(error) + '\n')


if __name__ == '__main__':
    main()
