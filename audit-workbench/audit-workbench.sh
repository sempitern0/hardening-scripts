#!/usr/bin/env bash
# Audit Workbench launcher for Linux/macOS. One-time download; offline afterwards.
set -Eeuo pipefail
umask 077

REPO="${AUDIT_WORKBENCH_REPO:-sempitern0/hardening-scripts}"
REF="${AUDIT_WORKBENCH_REF:-main}"
DEST="${XDG_DATA_HOME:-$HOME/.local/share}/audit-workbench"
UPDATE=0
NO_OPEN=0

usage() {
  cat <<'HELP'
Audit Workbench — asistente documental offline
Uso: bash audit-workbench.sh [--dir RUTA] [--ref RAMA_O_SHA] [--update] [--no-open] [--help]
  --dir      Directorio de instalación local (por defecto: ~/.local/share/audit-workbench)
  --ref      Rama, etiqueta o SHA del repositorio (por defecto: main)
  --update   Reemplazar archivos de aplicación; NO elimina expedientes JSON exportados
  --no-open  Instalar sin abrir navegador

Puedes definir AUDIT_WORKBENCH_REPO=owner/repo si cambias el nombre del repositorio.
Si ejecutas el script desde audit-workbench/ en un checkout, usa esos
archivos locales sin Internet. En caso contrario descarga los recursos de la PWA por HTTPS
(solo en la instalación inicial). La app no hace solicitudes de red al usarla.
HELP
}
while (($#)); do
  case "$1" in
    --dir) (($#>=2)) || { echo 'Falta valor para --dir' >&2; exit 2; }; DEST="$2"; shift 2;;
    --ref) (($#>=2)) || { echo 'Falta valor para --ref' >&2; exit 2; }; REF="$2"; shift 2;;
    --update) UPDATE=1; shift;;
    --no-open) NO_OPEN=1; shift;;
    --help|-h) usage; exit 0;;
    *) echo "Argumento no reconocido: $1" >&2; usage >&2; exit 2;;
  esac
done
if [[ ! "$REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
  echo 'Repositorio inválido (esperado owner/repo).' >&2; exit 2
fi
if [[ ! "$REF" =~ ^[A-Za-z0-9._/-]+$ || "$REF" == *..* || "$REF" == //* ]]; then
  echo 'Ref de Git inválida.' >&2; exit 2
fi
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
LOCAL_SOURCE="${SCRIPT_DIR}"
FILES=(index.html styles.css app.js manifest.webmanifest sw.js icons/icon-192.png icons/icon-512.png)
needs_install=0
for f in "${FILES[@]}"; do
  [[ -s "${DEST}/${f}" ]] || needs_install=1
done
if ((UPDATE || needs_install)); then
  mkdir -p -- "$DEST"
  stage="$(mktemp -d "${DEST}/.staging.XXXXXXXX")"
  trap 'rm -rf -- "$stage"' EXIT
  for file in "${FILES[@]}"; do
    mkdir -p -- "$(dirname -- "${stage}/${file}")"
    if [[ -s "${LOCAL_SOURCE}/${file}" ]]; then
      cp -- "${LOCAL_SOURCE}/${file}" "${stage}/${file}"
    else
      url="https://raw.githubusercontent.com/${REPO}/${REF}/audit-workbench/${file}"
      if command -v curl >/dev/null 2>&1; then
        curl --fail --location --silent --show-error --connect-timeout 15 --max-time 90 "$url" -o "${stage}/${file}"
      elif command -v wget >/dev/null 2>&1; then
        wget -q --timeout=90 -O "${stage}/${file}" "$url"
      else
        echo 'Requiere curl o wget para la instalación inicial desde GitHub.' >&2; exit 1
      fi
    fi
    [[ -s "${stage}/${file}" ]] || { echo "Archivo de aplicación vacío: ${file}" >&2; exit 1; }
  done
  grep -q 'Audit Workbench' "${stage}/index.html" && grep -q 'sysadmin-tools:audit-workbench:v2' "${stage}/app.js" || {
    echo 'La descarga no parece corresponder con Audit Workbench; no se instala.' >&2; exit 1;
  }
  for file in "${FILES[@]}"; do mkdir -p -- "$(dirname -- "${DEST}/${file}")"; mv -f -- "${stage}/${file}" "${DEST}/${file}"; chmod 600 -- "${DEST}/${file}"; done
  echo "[OK] Aplicación instalada en: ${DEST}"
fi
html="${DEST}/index.html"
[[ -s "$html" ]] || { echo 'No se pudo preparar el HTML' >&2; exit 1; }
echo "[OK] Archivo local: ${html}"
echo 'Los datos se editan en el navegador. Exporta periódicamente el JSON; usa Imprimir > Guardar como PDF.'
if (( !NO_OPEN )); then
  if command -v xdg-open >/dev/null 2>&1; then xdg-open "$html" >/dev/null 2>&1 || echo "Abre manualmente: ${html}"
  elif command -v open >/dev/null 2>&1; then open "$html" || echo "Abre manualmente: ${html}"
  else echo "Abre manualmente: ${html}"; fi
fi
