#!/usr/bin/env bash
# Audit Workbench: installation of static offline assets; does not scan or harden hosts.
set -Eeuo pipefail
umask 077

REPO="${AUDIT_WORKBENCH_REPO:-sempitern0/sysadmin}"
REF="${AUDIT_WORKBENCH_REF:-main}"
DEST="${XDG_DATA_HOME:-$HOME/.local/share}/audit-workbench"
UPDATE=0
NO_OPEN=0

usage() {
  cat <<'HELP'
Audit Workbench — auditorías offline
Uso: bash audit-workbench.sh [--dir RUTA] [--ref RAMA_O_SHA] [--update] [--no-open]
  --dir       Carpeta de instalación local
  --ref       Rama, etiqueta o SHA en GitHub (por defecto main)
  --update    Actualizar recursos de la aplicación sin tocar los expedientes del navegador
  --no-open   No abrir automáticamente el navegador
También puedes usar AUDIT_WORKBENCH_REPO=owner/repo.
La primera descarga remota requiere Internet. La edición y el PDF funcionan offline.
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
[[ "$REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || { echo 'Repositorio inválido' >&2; exit 2; }
[[ "$REF" =~ ^[A-Za-z0-9._/-]+$ && "$REF" != *..* && "$REF" != //* ]] || { echo 'Ref inválida' >&2; exit 2; }
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
FILES=(
  index.html css/normalize.css css/styles.css css/team.css css/contrast.css css/relations.css css/templates.css css/quality.css css/retest.css css/comparison.css css/glossary.css css/print.css css/atkinson.css
  js/app.js js/audit-storage.js js/audit-relations.js js/control-templates.js js/audit-quality.js js/audit-retest.js js/audit-comparison.js js/hardware-catalog.js js/os-catalog.js js/glossary.js js/inventory-import.js js/input-guidance.js js/secure-transfer.js js/secure-transfer-ui.js js/exporters.js sw.js manifest.webmanifest collect-local.sh collect-local.ps1
  fonts/AtkinsonHyperlegible-Regular.woff2 fonts/AtkinsonHyperlegible-Bold.woff2
  fonts/AtkinsonHyperlegible-Italic.woff2 fonts/AtkinsonHyperlegible-BoldItalic.woff2
  icons/os-windows.svg icons/os-linux.svg icons/os-macos.svg icons/dragon.svg icons/icon-192.png icons/icon-512.png
)
needs_install=$UPDATE
for file in "${FILES[@]}"; do [[ -s "${DEST}/${file}" ]] || needs_install=1; done
if ((needs_install)); then
  mkdir -p -- "$DEST"
  stage="$(mktemp -d "${DEST}/.staging.XXXXXXXX")"
  trap 'rm -rf -- "$stage"' EXIT
  for file in "${FILES[@]}"; do
    mkdir -p -- "$(dirname -- "${stage}/${file}")"
    if [[ -s "${SCRIPT_DIR}/${file}" ]]; then
      cp -- "${SCRIPT_DIR}/${file}" "${stage}/${file}"
    else
      url="https://raw.githubusercontent.com/${REPO}/${REF}/audit-workbench/${file}"
      if command -v curl >/dev/null 2>&1; then
        curl --fail --location --silent --show-error --connect-timeout 15 --max-time 90 "$url" -o "${stage}/${file}"
      elif command -v wget >/dev/null 2>&1; then
        wget -q --timeout=90 -O "${stage}/${file}" "$url"
      else
        echo 'Requiere curl o wget para los archivos que no se encuentran localmente.' >&2; exit 1
      fi
    fi
    [[ -s "${stage}/${file}" ]] || { echo "Archivo de aplicación vacío: ${file}" >&2; exit 1; }
  done
  grep -q 'Audit Workbench' "${stage}/index.html" && grep -q 'AuditRelations' "${stage}/js/audit-relations.js" || {
    echo 'Los archivos descargados no corresponden a Audit Workbench.' >&2; exit 1;
  }
  for file in "${FILES[@]}"; do
    mkdir -p -- "$(dirname -- "${DEST}/${file}")"
    mv -f -- "${stage}/${file}" "${DEST}/${file}"
    chmod 600 -- "${DEST}/${file}"
  done
  echo "[OK] Aplicación instalada en: ${DEST}"
fi
html="${DEST}/index.html"
echo "[OK] Archivo local: ${html}"
echo 'Los expedientes se guardan en el navegador. Exporta el JSON a almacenamiento cifrado.'
if (( ! NO_OPEN )); then
  if command -v xdg-open >/dev/null 2>&1; then xdg-open "$html" >/dev/null 2>&1 || echo "Abre manualmente: ${html}"
  elif command -v open >/dev/null 2>&1; then open "$html" || echo "Abre manualmente: ${html}"
  else echo "Abre manualmente: ${html}"; fi
fi
