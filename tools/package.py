#!/usr/bin/env python3
"""Package the checked-out revision for transfer to target hosts; does not run it."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'dist')
    args = parser.parse_args()
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    if subprocess.check_output(['git', 'status', '--porcelain', '--untracked-files=normal'], cwd=ROOT, text=True).strip():
        raise SystemExit('Refusing to package a dirty checkout. Commit/review changes and run verification first.')
    paths = sorted([*ROOT.glob('*.sh'), *ROOT.glob('*.ps1'), *ROOT.glob('README*.md'),
                    ROOT / 'LICENSE', *ROOT.glob('docs/*.md')])
    payload = {p.relative_to(ROOT).as_posix(): p.read_bytes() for p in paths}
    payload['release.json'] = (json.dumps({'repository': 'sempitern0/sysadmin', 'commit': revision,
                                          'validation': 'See GitHub Actions for this exact commit; lab acceptance still required.'},
                                         indent=2) + '\n').encode()
    payload['SHA256SUMS'] = ''.join(f'{hashlib.sha256(data).hexdigest()}  {name}\n'
                                  for name, data in sorted(payload.items())).encode()
    args.output.mkdir(parents=True, exist_ok=True)
    destination = args.output / f'sysadmin-{revision[:12]}.zip'
    with zipfile.ZipFile(destination, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        for name, data in sorted(payload.items()):
            info = zipfile.ZipInfo(name, (2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, data)
    print(destination)


if __name__ == '__main__':
    main()
