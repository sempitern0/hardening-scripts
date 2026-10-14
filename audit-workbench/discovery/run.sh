#!/usr/bin/env bash
set -Eeuo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
command -v python3 >/dev/null 2>&1 || { echo 'Instala Python 3.9+ en el equipo auditor.' >&2; exit 1; }
exec python3 "${here}/discover.py" "$@"
