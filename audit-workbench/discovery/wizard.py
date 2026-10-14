#!/usr/bin/env python3
"""Asistente de Discovery desde el equipo del auditor.

No abre puertos, instala software ni escanea sin confirmar una subred autorizada.
Python 3.9+ y biblioteca estándar; interfaces detectadas de forma local/pasiva.
"""
import datetime
import ipaddress
import json
from pathlib import Path
import platform
import re
import shutil
import subprocess


def _run_local(command):
    try:
        result = subprocess.run(command, capture_output=True, text=True,
                                timeout=5, check=False)
        return result.stdout if result.returncode == 0 else ''
    except (OSError, subprocess.TimeoutExpired):
        return ''


def interface_candidates(system=None, runner=None):
    """Devuelve sugerencias, nunca un permiso ni una selección automática."""
    system = system or platform.system()
    runner = runner or _run_local
    observations = []
    if system == 'Linux' and shutil.which('ip'):
        try:
            adapters = json.loads(runner(['ip', '-j', '-4', 'address', 'show']) or '[]')
            for adapter in adapters:
                for addr in adapter.get('addr_info', []):
                    if addr.get('family') == 'inet' and addr.get('local') and isinstance(addr.get('prefixlen'), int):
                        observations.append((adapter.get('ifname', 'Interfaz'), addr['local'], addr['prefixlen']))
        except (ValueError, TypeError, AttributeError):
            pass
    elif system == 'Windows' and shutil.which('powershell.exe'):
        command = ('Get-NetIPAddress -AddressFamily IPv4 | '
                   'Select-Object InterfaceAlias,IPAddress,PrefixLength | ConvertTo-Json -Compress')
        try:
            decoded = json.loads(runner(['powershell.exe', '-NoProfile', '-NonInteractive', '-Command', command]) or '[]')
            for item in decoded if isinstance(decoded, list) else [decoded]:
                observations.append((item.get('InterfaceAlias', 'Interfaz'),
                                     item.get('IPAddress', ''), item.get('PrefixLength')))
        except (ValueError, TypeError, AttributeError):
            pass
    elif system == 'Darwin' and shutil.which('ifconfig'):
        adapter = 'Interfaz'
        for line in runner(['ifconfig']).splitlines():
            if line and not line[0].isspace() and ':' in line:
                adapter = line.split(':', 1)[0]
            match = re.search(r'\binet\s+(\d+(?:\.\d+){3})\s+netmask\s+(0x[0-9a-fA-F]+|\d+(?:\.\d+){3})', line)
            if match:
                try:
                    mask = match.group(2)
                    if mask.startswith('0x'):
                        mask = str(ipaddress.IPv4Address(int(mask, 16)))
                    observations.append((adapter, match.group(1), mask))
                except (ValueError, ipaddress.AddressValueError):
                    continue
    choices = []
    known = set()
    for label, address, prefix in observations:
        try:
            ip = ipaddress.IPv4Address(address)
            network = ipaddress.IPv4Network(f'{ip}/{prefix}', strict=False)
            from discover import scope_network
            scope_network(str(network))
        except (TypeError, ValueError, ipaddress.AddressValueError):
            continue
        if str(network) not in known:
            known.add(str(network))
            choices.append({'interface': str(label)[:90], 'address': str(ip), 'cidr': str(network)})
    return sorted(choices, key=lambda x: (x['interface'], x['cidr']))


def default_output(base=None, clock=None):
    base = Path(base) if base is not None else Path.cwd()
    stamp = (clock or datetime.datetime.now()).strftime('%Y%m%d-%H%M%S')
    candidate = base / f'captura-lan-{stamp}.json'
    suffix = 2
    while candidate.exists():
        candidate = base / f'captura-lan-{stamp}-{suffix}.json'
        suffix += 1
    return candidate


def run_wizard(doctor, scope_network, execute, read=input, write=print,
               suggest=interface_candidates, output_base=None):
    """Asistente textual: no ejecuta scan si la confirmación no es literal."""
    write('\n=== Audit Workbench · Descubrimiento guiado ===')
    write('Se ejecuta en TU equipo. No instala agentes ni modifica los dispositivos.')
    write('No busca vulnerabilidades ni averigua el software instalado.')
    info = doctor()
    write(f"Equipo auditor: {info['platform']} · Python {info['python']}")
    tools = info['tools']
    write('Nmap: ' + ('Disponible' if tools.get('nmap') else 'No instalado (opcional)'))
    write('Ping nativo: ' + ('Disponible' if tools.get('ping') else 'No disponible'))
    if not info['python_ok'] or not info['preferred_backend']:
        write('Faltan herramientas para Discovery. ' + info['install_guidance'])
        return 2
    try:
        proposals = suggest()
        if proposals:
            write('\nRedes detectadas en las interfaces locales (NO implican autorización):')
            for index, row in enumerate(proposals, 1):
                write(f"  {index}. {row['interface']}: {row['address']} · {row['cidr']}")
            write('Elige un número o introduce otro CIDR privado autorizado.')
        else:
            write('\nNo se ha detectado una subred local compatible. Introduce un CIDR manualmente.')
        answer = read('Red autorizada (CIDR o número; vacío para salir): ').strip()
        if not answer:
            write('Operación cancelada: no se ha escaneado ninguna red.')
            return 0
        cidr = proposals[int(answer)-1]['cidr'] if answer.isdecimal() and 1 <= int(answer) <= len(proposals) else answer
        try:
            network = scope_network(cidr)
        except ValueError as exc:
            write('Alcance inválido: ' + str(exc))
            return 2

        preferred = info['preferred_backend']
        write('\nMotor disponible: ' + ('Nmap (descubrimiento sin puertos)' if preferred == 'nmap' else 'Ping nativo (ICMP)'))
        options = [('auto', f'Automático ({preferred})')]
        if tools.get('nmap'):
            options.append(('nmap', 'Nmap'))
        if tools.get('ping'):
            options.append(('native', 'Ping nativo'))
        for index, (_, label) in enumerate(options, 1):
            write(f'  {index}. {label}')
        choice = read('Motor [1]: ').strip() or '1'
        if not choice.isdecimal() or not 1 <= int(choice) <= len(options):
            write('Selección de motor no válida. Operación cancelada.')
            return 2
        backend = options[int(choice)-1][0]
        suggested = default_output(output_base)
        destination = Path(read(f'Archivo de salida [{suggested}]: ').strip() or str(suggested)).expanduser().absolute()
        if destination.suffix.lower() != '.json' or not destination.parent.is_dir() or destination.exists():
            write('Salida no válida: usa un archivo .json nuevo en una carpeta existente.')
            return 2
        write('\nResumen previo:')
        write(f'  Subred: {network} ({network.num_addresses} direcciones)')
        write(f'  Motor: {preferred if backend == "auto" else backend}')
        write(f'  Archivo: {destination}')
        write('Se comprobará la respuesta de los hosts de esa red. Solo procede con permiso del titular.')
        confirmation = read('Escribe AUTORIZO para comenzar (cualquier otra respuesta cancela): ').strip()
        if confirmation != 'AUTORIZO':
            write('Operación cancelada: no se ha escaneado ninguna red.')
            return 0
        write('\nIniciando reconocimiento. Pulsa Ctrl+C para interrumpir.')
        result = execute(['scan', '--cidr', str(network), '--authorized',
                          '--backend', backend, '--output', str(destination)])
        if result == 0:
            write('\nCaptura preparada. En Audit Workbench:')
            write('  1. Hardware → Captura asistida → importa el JSON → revisa las filas.')
            write('  2. Redes → Captura asistida → importa el mismo JSON → revisa el segmento.')
            write('  3. Conserva el original en almacenamiento protegido.')
        else:
            write('No se completó la captura. Revisa los mensajes anteriores.')
        return result
    except (EOFError, KeyboardInterrupt):
        write('\nCancelado por el operador.')
        return 130
