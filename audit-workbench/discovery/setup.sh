#!/usr/bin/env bash
set -Eeuo pipefail
mode="${1:---check}"
[[ "$mode" == "--check" || "$mode" == "--install" ]] || { echo 'Uso: setup.sh [--check|--install]' >&2; exit 2; }
missing=()
if ! command -v python3 >/dev/null 2>&1 || ! python3 -c 'import sys;assert sys.version_info>=(3,9)' 2>/dev/null; then missing+=(python3); fi
if ! command -v nmap >/dev/null 2>&1; then missing+=(nmap); fi
printf 'Python 3: %s\nNmap opcional: %s\nPing nativo: %s\n' "$(command -v python3 || echo NO)" "$(command -v nmap || echo NO)" "$(command -v ping || echo NO)"
if [[ "$mode" == "--check" ]]; then echo 'Sin instalaciones ni escaneos. --install instala opcionalmente herramientas faltantes.';exit 0;fi
(("${#missing[@]}")) || { echo 'Todo listo.';exit 0; }
if [[ "$(uname -s)" == "Darwin" ]]; then
  command -v brew >/dev/null 2>&1 || { echo 'Instala Homebrew, o Python y Nmap manualmente.' >&2;exit 1; }
  brew install "${missing[@]}"
elif [[ "$(uname -s)" == "Linux" ]]; then
  if ((EUID==0));then elevate=();else elevate=(sudo);fi
  if command -v apt-get >/dev/null 2>&1;then "${elevate[@]}" apt-get update;"${elevate[@]}" apt-get install -y "${missing[@]}"
  elif command -v dnf >/dev/null 2>&1;then "${elevate[@]}" dnf install -y "${missing[@]}"
  elif command -v zypper >/dev/null 2>&1;then "${elevate[@]}" zypper install -y "${missing[@]}"
  elif command -v pacman >/dev/null 2>&1;then "${elevate[@]}" pacman -S --needed "${missing[@]}"
  else echo 'Gestor desconocido; instala Python 3 y Nmap manualmente.' >&2;exit 1;fi
else echo 'Instalación automática no disponible en este SO.' >&2;exit 1;fi
