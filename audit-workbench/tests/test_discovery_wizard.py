"""Regresiones del asistente de consola, sin escaneo real ni servicios."""
import importlib.util
import json
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

directory = Path(__file__).resolve().parents[1] / 'discovery'
sys.path.insert(0, str(directory))
spec = importlib.util.spec_from_file_location('aw_wizard', directory / 'wizard.py')
wizard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wizard)
from discover import scope_network


def information():
    return {'platform': 'Linux', 'python': '3.12.0', 'python_ok': True,
            'tools': {'nmap': '/usr/bin/nmap', 'ping': '/usr/bin/ping'},
            'preferred_backend': 'nmap', 'install_guidance': 'Instala herramientas.'}


class WizardTests(unittest.TestCase):
    def test_linux_passive_interfaces(self):
        sample = json.dumps([
            {'ifname': 'eth0', 'addr_info': [{'family':'inet', 'local':'192.168.10.23', 'prefixlen':24}]},
            {'ifname': 'wg0', 'addr_info': [{'family':'inet', 'local':'10.0.2.2', 'prefixlen':24}]},
            {'ifname': 'lo', 'addr_info': [{'family':'inet', 'local':'127.0.0.1', 'prefixlen':8}]},
            {'ifname': 'eth1', 'addr_info': [{'family':'inet', 'local':'172.16.2.4', 'prefixlen':16}]},
        ])
        with patch.object(wizard.shutil, 'which', return_value='/sbin/ip'):
            rows = wizard.interface_candidates('Linux', runner=lambda _: sample)
        self.assertEqual([r['cidr'] for r in rows], ['192.168.10.0/24','10.0.2.0/24'])

    def test_windows_single_json(self):
        data = '{"InterfaceAlias":"Ethernet","IPAddress":"192.168.0.25","PrefixLength":24}'
        with patch.object(wizard.shutil, 'which', return_value='powershell.exe'):
            rows = wizard.interface_candidates('Windows', runner=lambda _: data)
        self.assertEqual(rows[0]['cidr'], '192.168.0.0/24')

    def test_macos_hex_mask(self):
        data = 'en0: flags=8863\n\tinet 192.168.5.17 netmask 0xffffff00 broadcast 192.168.5.255\n'
        with patch.object(wizard.shutil, 'which', return_value='ifconfig'):
            rows = wizard.interface_candidates('Darwin', runner=lambda _: data)
        self.assertEqual(rows[0]['cidr'], '192.168.5.0/24')

    def test_cancel_never_calls_scanner(self):
        with TemporaryDirectory() as path:
            executed = []
            with patch.object(wizard, 'default_output', return_value=Path(path)/'captura.json'):
                answer = iter(['1','1','', 'NO'])
                result = wizard.run_wizard(information, scope_network, lambda args: executed.append(args),
                                           read=lambda _: next(answer), write=lambda _: None,
                                           suggest=lambda: [{'interface':'eth0','address':'192.168.10.5','cidr':'192.168.10.0/24'}])
            self.assertEqual(result, 0)
            self.assertEqual(executed, [])

    def test_authorized_and_scoped(self):
        with TemporaryDirectory() as path:
            out = Path(path)/'captura.json'
            answer = iter(['192.168.10.0/24','2',str(out),'AUTORIZO'])
            called = []
            result = wizard.run_wizard(information, scope_network, lambda args: called.append(args) or 0,
                                       read=lambda _: next(answer), write=lambda _: None, suggest=lambda: [])
            self.assertEqual(result, 0)
            self.assertEqual(called[0][called[0].index('--backend')+1], 'nmap')
            self.assertEqual(called[0][called[0].index('--cidr')+1], '192.168.10.0/24')

    def test_invalid_scope_does_not_scan(self):
        called = []
        result = wizard.run_wizard(information, scope_network, lambda args: called.append(args),
                                   read=lambda _: '8.8.8.0/24', write=lambda _: None, suggest=lambda: [])
        self.assertEqual(result, 2)
        self.assertFalse(called)

    def test_new_output_filename(self):
        with TemporaryDirectory() as path:
            from datetime import datetime
            stamp = datetime(2026, 10, 14)
            first = wizard.default_output(path, stamp)
            first.touch()
            second = wizard.default_output(path, stamp)
            self.assertNotEqual(first, second)
            self.assertEqual(second.suffix, '.json')


if __name__ == '__main__':
    unittest.main()
