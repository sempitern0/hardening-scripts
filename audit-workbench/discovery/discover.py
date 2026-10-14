#!/usr/bin/env python3
"""Agentless, bounded IPv4 discovery for the Audit Workbench offline importer.

Standard library only. Runs on the auditor's device; never logs into remote hosts.
"""
import argparse
import concurrent.futures
import datetime
import ipaddress
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

KIND = 'audit-workbench-discovery-v1'
PRIVATE_RANGES = tuple(ipaddress.ip_network(x) for x in ('10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16'))
MAX_HOSTS = 1024
MAX_XML = 2 * 1024 * 1024


def scope_network(cidr, max_hosts=MAX_HOSTS):
    try:
        network = ipaddress.ip_network(cidr, strict=True)
    except ValueError as exc:
        raise ValueError('Introduce un CIDR de red válido y alineado, p. ej. 192.168.10.0/24.') from exc
    if network.version != 4 or not any(network.subnet_of(block) for block in PRIVATE_RANGES):
        raise ValueError('Solo se admiten rangos IPv4 RFC1918 de una red privada autorizada.')
    if network.num_addresses > max_hosts or network.num_addresses < 2:
        raise ValueError(f'El alcance debe contener entre 2 y {max_hosts} direcciones. Divide la red en bloques.')
    return network


def doctor():
    system = platform.system()
    python = f'{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}'
    tools = {name: shutil.which(name) for name in ('nmap', 'ping', 'ip', 'ipconfig', 'ifconfig')}
    suggestions = {
        'Windows': 'Instala Python 3 desde python.org o winget (Python.Python.3.13). Nmap: winget install Insecure.Nmap. Npcap puede requerir autorización administrativa.',
        'Darwin': 'Utiliza Python 3 existente o instala con brew install python. Nmap es opcional: brew install nmap.',
        'Linux': 'Utiliza python3 del sistema. Nmap opcional desde el gestor de paquetes (apt, dnf, zypper, etc.).',
    }
    return {
        'platform': system, 'python': python, 'python_ok': sys.version_info >= (3, 9),
        'tools': tools, 'native_available': bool(tools['ping']),
        'preferred_backend': 'nmap' if tools['nmap'] else 'native' if tools['ping'] else None,
        'install_guidance': suggestions.get(system, 'Se requiere Python 3.9+ y ping o Nmap.'),
        'network_scanned': False,
    }


def parse_nmap_xml(source, network):
    if len(source) > MAX_XML:
        raise ValueError('Salida XML de Nmap excesiva (máximo 2 MiB).')
    try:
        root = ET.fromstring(source)
    except ET.ParseError as exc:
        raise ValueError('Nmap no ha devuelto un XML válido.') from exc
    if root.tag != 'nmaprun':
        raise ValueError('El documento no contiene una captura XML de Nmap.')
    results = {}
    for host in root.findall('host'):
        status = host.find('status')
        if status is None or status.get('state') != 'up':
            continue
        address = next((entry.get('addr', '') for entry in host.findall('address') if entry.get('addrtype') == 'ipv4'), '')
        try:
            ip = ipaddress.IPv4Address(address)
        except ipaddress.AddressValueError:
            continue
        if ip not in network:
            continue
        mac = next((entry for entry in host.findall('address') if entry.get('addrtype') == 'mac'), None)
        hostnames = host.find('hostnames')
        raw_name = '' if hostnames is None else next((item.get('name', '') for item in hostnames.findall('hostname') if item.get('name')), '')
        name = raw_name.strip()[:160] if raw_name else str(ip)
        vendor = (mac.get('vendor') or '')[:140] if mac is not None else ''
        mac_text = (mac.get('addr') or '')[:24] if mac is not None else ''
        extra = f'; MAC observada: {mac_text}' if mac_text else ''
        results[str(ip)] = {
            'name': name, 'ip': str(ip), 'vendor': vendor,
            'notes': 'Host activo según descubrimiento Nmap; identidad, fabricante y sistema operativo pendientes de verificación' + extra + '.',
        }
    return [results[ip] for ip in sorted(results, key=ipaddress.IPv4Address)]


def scan_nmap(network, nmap_path):
    argv = [nmap_path, '-sn', '-oX', '-', '--max-retries', '1', '--max-rate', '40', str(network)]
    try:
        run = subprocess.run(argv, capture_output=True, timeout=180, check=False)
    except subprocess.TimeoutExpired as exc:
        raise RuntimeError('Se agotó el tiempo de Nmap; divide el alcance en subredes menores.') from exc
    if run.returncode != 0:
        raise RuntimeError('Nmap terminó con error: ' + run.stderr.decode('utf-8', errors='replace')[:350])
    return parse_nmap_xml(run.stdout, network)


def ping_args(ip, system):
    if system == 'Windows':
        return ['-n', '1', '-w', '1200', ip]
    if system == 'Darwin':
        return ['-n', '-c', '1', '-W', '1200', ip]
    return ['-n', '-c', '1', '-W', '2', ip]


def scan_native(network, ping_path, workers=16):
    system = platform.system()

    def probe(ip):
        try:
            run = subprocess.run([ping_path, *ping_args(ip, system)], capture_output=True, timeout=5, check=False)
            return ip if run.returncode == 0 else None
        except (OSError, subprocess.TimeoutExpired):
            return None

    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        responding = list(pool.map(probe, (str(ip) for ip in network.hosts())))
    return [{
        'name': ip, 'ip': ip,
        'notes': 'Respuesta ICMP desde el dispositivo auditor; nombre, fabricante, SO y tipo por verificar.',
    } for ip in responding if ip]


def discovery_document(network, backend, hosts):
    return {
        'kind': KIND,
        'schemaVersion': 1,
        'capturedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'source': {
            'platform': platform.system(), 'collector': 'discovery/discover.py',
            'scope': str(network), 'mode': 'read-only', 'backend': backend,
        },
        'items': {
            'assets': hosts,
            'networks': [{
                'name': 'Red observada ' + str(network), 'cidr': str(network),
                'notes': 'Alcance del reconocimiento desde un dispositivo externo. No confirma VLAN, gateway, DNS ni segmentación.',
            }],
            'software': [],
        },
    }


def save_document(output, document):
    path = Path(output).expanduser().absolute()
    if not path.parent.is_dir():
        raise ValueError('La carpeta de destino debe existir.')
    data = json.dumps(document, indent=2, ensure_ascii=False).encode('utf-8')
    if len(data) > MAX_XML:
        raise ValueError('El resultado supera el límite de importación de Audit Workbench (2 MiB).')
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    if hasattr(os, 'O_BINARY'):
        flags |= os.O_BINARY
    descriptor = os.open(path, flags, 0o600)
    try:
        with os.fdopen(descriptor, 'wb') as stream:
            stream.write(data)
    except BaseException:
        path.unlink(missing_ok=True)
        raise
    return path


def main(argv=None):
    parser = argparse.ArgumentParser(description='Audit Workbench: descubrimiento remoto acotado, sin agentes y de solo lectura.')
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('doctor', help='Comprueba dependencias y muestra instalación sugerida, sin red.')
    commands.add_parser('wizard', help='Asistente interactivo de descubrimiento sin servicios locales.')
    scan = commands.add_parser('scan', help='Descubre hosts de una red autorizada y exporta JSON.')
    scan.add_argument('--cidr', required=True, help='Subred IPv4 RFC1918 autorizada, por ejemplo 192.168.10.0/24')
    scan.add_argument('--output', required=True, help='Archivo JSON NUEVO (no sobrescribe).')
    scan.add_argument('--authorized', action='store_true', help='Confirma que tienes autorización para este alcance.')
    scan.add_argument('--backend', choices=('auto', 'nmap', 'native'), default='auto')
    scan.add_argument('--workers', type=int, default=16, help='Concurrencia del ping nativo (1 a 32).')
    args = parser.parse_args(argv)
    if args.command == 'doctor':
        print(json.dumps(doctor(), indent=2, ensure_ascii=False))
        return 0
    if args.command == 'wizard':
        from wizard import run_wizard
        return run_wizard(doctor, scope_network, main)
    try:
        if not args.authorized:
            raise ValueError('Debes confirmar el alcance con --authorized (autorización previa del titular).')
        if not 1 <= args.workers <= 32:
            raise ValueError('--workers debe estar entre 1 y 32.')
        network = scope_network(args.cidr)
        output = Path(args.output).expanduser().absolute()
        if output.exists():
            raise FileExistsError('El archivo ya existe; elige otro nombre. Nunca se sobrescriben capturas.')
        tools = doctor()['tools']
        backend = ('nmap' if tools['nmap'] else 'native') if args.backend == 'auto' else args.backend
        path = tools['nmap' if backend == 'nmap' else 'ping']
        if not path:
            raise RuntimeError(f'No está instalado {backend == "nmap" and "Nmap" or "ping"}. Ejecuta doctor para ver alternativas.')
        hosts = scan_nmap(network, path) if backend == 'nmap' else scan_native(network, path, args.workers)
        destination = save_document(output, discovery_document(network, backend, hosts))
        print(json.dumps({'file': str(destination), 'backend': backend, 'hosts_detected': len(hosts), 'networks': 1,
                          'warning': 'Los equipos sin respuesta no se consideran ausentes. Revisar antes de incorporar.'}, ensure_ascii=False))
        return 0
    except (OSError, ValueError, RuntimeError) as exc:
        print('ERROR: ' + str(exc), file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
