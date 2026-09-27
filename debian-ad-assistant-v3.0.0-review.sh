#!/usr/bin/env bash
# DEBIAN AD Assistant - review candidate
# Version 3.0.0-review
#
# Targets:
#   - Debian 13
#   - Ubuntu Server 26.04 LTS
#
# Modes:
#   --audit       read-only inventory
#   --validate    functional AD/DC health checks
#   --bootstrap   provision a NEW Samba AD/DC
#   --manage      manage an EXISTING Samba AD/DC without reprovisioning
#   --backup      create a Samba domain backup
#
# Principles:
#   - detect before modify
#   - no writes before privilege/runtime initialization
#   - never reprovision an existing AD
#   - isolated Kerberos credential cache
#   - backups/snapshots before sensitive changes
#   - TTY-aware output; usable over SSH and curl|bash
#   - dependencies checked per operation
#   - CIS-oriented reporting, not a claim of CIS compliance

set -Eeuo pipefail
IFS=$'\n\t'
umask 077

SCRIPT_NAME="DEBIAN AD Assistant"
SCRIPT_VERSION="3.0.0-review"

MODE="interactive"
FORCE_NO_COLOR=0
STATE_DIR="/var/lib/debian-ad-assistant"
LOG_DIR="/var/log/debian-ad-assistant"
RUN_ROOT=""
LOG_FILE=""
REPORT_FILE=""
BACKUP_DIR=""
DOMAIN_BACKUP_DIR=""
CONFIG_FILE="${STATE_DIR}/config.env"
GPO_DIR="${STATE_DIR}/gpo"
LOCK_FD=""
LOCK_DIR=""
TIMESTAMP=""
INPUT_FD="/dev/null"
TTY_MODE=0
CURRENT_STEP=0
TOTAL_STEPS=1
REMOTE_SESSION=0
SSH_CLIENT_IP=""

DOMAIN=""
REALM=""
NETBIOS_DOMAIN=""
DC_HOSTNAME=""
DC_FQDN=""
DC_NETBIOS=""
DC_IP=""
AD_CLIENT_CIDR=""
SSH_SOURCE=""
DNS_FORWARDER=""
TIMEZONE="Europe/London"
NTP_POOL="pool.ntp.org"
ADMIN_USER="Godzilla"
ENABLE_UFW="yes"
ENABLE_GPOS="yes"

DISTRO_ID=""
DISTRO_LIKE=""
DISTRO_VERSION=""
DISTRO_CODENAME=""
PRETTY_NAME_SAFE="unknown"
SAMBA_ROLE="none"
PRIMARY_IFACE=""
PRIMARY_CIDR=""
PRIMARY_IP=""
DEFAULT_GW=""

KRB5_CACHE=""
export KRB5CCNAME=""

RESULTS=()
CHANGES=()
WARNINGS=()
FAILURES=()
BACKUP_MANIFEST=()

C_RESET=$'\033[0m'
C_CYAN=$'\033[36m'
C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'
C_RED=$'\033[31m'
C_MAGENTA=$'\033[35m'
C_DIM=$'\033[2m'

usage() {
    cat <<EOF
${SCRIPT_NAME} v${SCRIPT_VERSION}

Usage:
  sudo bash $0                 interactive menu
  sudo bash $0 --audit         read-only inventory
  sudo bash $0 --validate      validate an existing Samba AD/DC
  sudo bash $0 --bootstrap     guided NEW AD/DC provisioning
  sudo bash $0 --manage        manage an EXISTING AD/DC
  sudo bash $0 --backup        create an online Samba domain backup
  sudo bash $0 --no-color      disable ANSI colors
  sudo bash $0 --help

Remote one-shot:
  curl -fsSL <RAW_URL> | sudo bash -s -- --bootstrap

Notes:
  - Interactive modes require a controlling TTY.
  - This script never reprovisions an existing AD database.
  - Static network addressing is not changed automatically.
  - High-impact repairs require separate explicit confirmation.
EOF
}

parse_args() {
    while (($#)); do
        case "$1" in
            --audit) MODE="audit" ;;
            --validate) MODE="validate" ;;
            --bootstrap) MODE="bootstrap" ;;
            --manage) MODE="manage" ;;
            --backup) MODE="backup" ;;
            --no-color) FORCE_NO_COLOR=1 ;;
            --help|-h) usage; exit 0 ;;
            *)
                printf 'Unknown argument: %s\n' "$1" >&2
                usage >&2
                exit 2
                ;;
        esac
        shift
    done
}

require_root() {
    if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
        printf 'Run as root, for example: sudo bash %s --audit\n' "$0" >&2
        exit 1
    fi
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

detect_terminal() {
    if [[ -t 1 && "${TERM:-dumb}" != "dumb" && -z "${NO_COLOR:-}" && $FORCE_NO_COLOR -eq 0 ]]; then
        TTY_MODE=1
    else
        TTY_MODE=0
        C_RESET=""; C_CYAN=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_MAGENTA=""; C_DIM=""
    fi

    if [[ -n "${SSH_CONNECTION:-}" || -n "${SSH_CLIENT:-}" ]]; then
        REMOTE_SESSION=1
        SSH_CLIENT_IP="${SSH_CLIENT%% *}"
    fi
}

need_tty() {
    case "$MODE" in
        bootstrap|manage|interactive|backup)
            if [[ -r /dev/tty ]]; then
                INPUT_FD="/dev/tty"
            else
                printf 'Mode %s requires a controlling TTY.\n' "$MODE" >&2
                printf 'Download the script and execute it from a terminal, or use --audit/--validate.\n' >&2
                exit 1
            fi
            ;;
        *) INPUT_FD="/dev/null" ;;
    esac
}

init_runtime() {
    TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
    RUN_ROOT="${STATE_DIR}/runs/${TIMESTAMP}-$$"
    LOG_FILE="${LOG_DIR}/assistant-${TIMESTAMP}-$$.log"
    REPORT_FILE="${LOG_DIR}/report-${TIMESTAMP}-$$.txt"
    BACKUP_DIR="${RUN_ROOT}/backup"
    DOMAIN_BACKUP_DIR="${RUN_ROOT}/domain-backup"

    mkdir -p "$STATE_DIR" "$LOG_DIR" "$RUN_ROOT" "$BACKUP_DIR" "$DOMAIN_BACKUP_DIR" "$GPO_DIR"
    touch "$LOG_FILE" "$REPORT_FILE"
    chmod 700 "$STATE_DIR" "$LOG_DIR" "$RUN_ROOT" "$BACKUP_DIR" "$DOMAIN_BACKUP_DIR" "$GPO_DIR"
    chmod 600 "$LOG_FILE" "$REPORT_FILE"

    if command_exists flock; then
        exec 9>"${STATE_DIR}/assistant.lock"
        flock -n 9 || {
            printf 'Another %s instance is running.\n' "$SCRIPT_NAME" >&2
            exit 1
        }
        LOCK_FD=9
    else
        LOCK_DIR="${STATE_DIR}/assistant.lock.d"
        if ! mkdir "$LOCK_DIR" 2>/dev/null; then
            printf 'Another %s instance appears to be running.\n' "$SCRIPT_NAME" >&2
            exit 1
        fi
    fi

    KRB5_CACHE="${RUN_ROOT}/krb5cc"
    export KRB5CCNAME="FILE:${KRB5_CACHE}"
}

cleanup() {
    local rc=$?
    if [[ -n "${KRB5CCNAME:-}" ]] && command_exists kdestroy; then
        kdestroy -c "$KRB5CCNAME" >/dev/null 2>&1 || true
    fi
    [[ -n "${LOCK_DIR:-}" ]] && rmdir "$LOCK_DIR" >/dev/null 2>&1 || true
    exit "$rc"
}

on_error() {
    local rc=$?
    local cmd="${BASH_COMMAND:-unknown}"
    {
        printf '[FATAL] rc=%s command=%s\n' "$rc" "$cmd"
        printf '[FATAL] mode=%s step=%s/%s\n' "$MODE" "$CURRENT_STEP" "$TOTAL_STEPS"
    } >>"$LOG_FILE" 2>/dev/null || true
    printf '\n%b[FATAL]%b command failed (rc=%s): %s\n' "$C_RED" "$C_RESET" "$rc" "$cmd" >&2
    printf 'Log: %s\n' "$LOG_FILE" >&2
    return "$rc"
}

trap on_error ERR
trap cleanup EXIT INT TERM

log() {
    local level="$1"; shift
    local line="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
    printf '%s\n' "$line" >>"$LOG_FILE"
    case "$level" in
        OK) printf '%b%s%b\n' "$C_GREEN" "$line" "$C_RESET" ;;
        WARN) printf '%b%s%b\n' "$C_YELLOW" "$line" "$C_RESET" ;;
        ERROR) printf '%b%s%b\n' "$C_RED" "$line" "$C_RESET" ;;
        CHANGE) printf '%b%s%b\n' "$C_MAGENTA" "$line" "$C_RESET" ;;
        DEBUG) [[ $TTY_MODE -eq 1 ]] && printf '%b%s%b\n' "$C_DIM" "$line" "$C_RESET" || true ;;
        *) printf '%s\n' "$line" ;;
    esac
}

banner() {
    printf '\n%b%s%b\n' "$C_CYAN" '==============================================================================' "$C_RESET"
    printf '%b  %s v%s%b\n' "$C_CYAN" "$SCRIPT_NAME" "$SCRIPT_VERSION" "$C_RESET"
    printf '%b  mode=%s  remote=%s%b\n' "$C_CYAN" "$MODE" "$([[ $REMOTE_SESSION -eq 1 ]] && echo yes || echo no)" "$C_RESET"
    printf '%b%s%b\n\n' "$C_CYAN" '==============================================================================' "$C_RESET"
}

section() {
    local title="$1"
    printf '\n%b--- %s ---%b\n' "$C_CYAN" "$title" "$C_RESET"
}

set_progress_plan() {
    TOTAL_STEPS="$1"
    CURRENT_STEP=0
}

step() {
    local title="$1"
    CURRENT_STEP=$((CURRENT_STEP + 1))
    if [[ $TTY_MODE -eq 1 ]]; then
        local width=24 filled
        filled=$((CURRENT_STEP * width / TOTAL_STEPS))
        printf '\n%b[%02d/%02d]%b %-30s [' "$C_CYAN" "$CURRENT_STEP" "$TOTAL_STEPS" "$C_RESET" "$title"
        printf '%*s' "$filled" '' | tr ' ' '#'
        printf '%*s' "$((width-filled))" '' | tr ' ' '-'
        printf ']\n'
    else
        printf '\n[%02d/%02d] %s\n' "$CURRENT_STEP" "$TOTAL_STEPS" "$title"
    fi
}

result() {
    local status="$1" name="$2" current="$3" expected="${4:-}"
    RESULTS+=("${status}|${name}|${current}|${expected}")
    case "$status" in
        PASS) printf '%b[PASS]%b %-34s %s\n' "$C_GREEN" "$C_RESET" "$name" "$current" ;;
        WARN) printf '%b[WARN]%b %-34s %s\n' "$C_YELLOW" "$C_RESET" "$name" "$current" ;;
        FAIL|ERROR) printf '%b[FAIL]%b %-34s %s\n' "$C_RED" "$C_RESET" "$name" "$current" ;;
        SKIP) printf '%b[SKIP]%b %-34s %s\n' "$C_YELLOW" "$C_RESET" "$name" "$current" ;;
        *) printf '[INFO] %-34s %s\n' "$name" "$current" ;;
    esac
}

change() { CHANGES+=("$1|${*:2}"); }
warn_msg() { WARNINGS+=("$*"); log WARN "$*"; }
fail_msg() { FAILURES+=("$*"); log ERROR "$*"; }

confirm() {
    local prompt="$1" default="${2:-N}" answer
    while true; do
        if [[ "$default" == "Y" ]]; then
            read -r -p "$prompt [Y/n]: " answer <"$INPUT_FD" || return 1
            answer="${answer:-Y}"
        else
            read -r -p "$prompt [y/N]: " answer <"$INPUT_FD" || return 1
            answer="${answer:-N}"
        fi
        answer="${answer^^}"
        case "$answer" in
            Y|YES|S|SI|SÍ) return 0 ;;
            N|NO) return 1 ;;
        esac
    done
}

confirm_high_risk() {
    local action="$1"
    local answer
    printf '\n%bHIGH IMPACT%b: %s\n' "$C_RED" "$C_RESET" "$action"
    printf 'Type APPLY to continue: '
    read -r answer <"$INPUT_FD" || return 1
    [[ "$answer" == "APPLY" ]]
}

ask() {
    local prompt="$1" default="${2:-}" answer
    if [[ -n "$default" ]]; then
        read -r -p "$prompt [$default]: " answer <"$INPUT_FD" || return 1
        printf '%s' "${answer:-$default}"
    else
        read -r -p "$prompt: " answer <"$INPUT_FD" || return 1
        printf '%s' "$answer"
    fi
}

is_valid_ipv4() {
    local ip="$1" x
    local -a p
    IFS=. read -r -a p <<<"$ip"
    [[ ${#p[@]} -eq 4 ]] || return 1
    for x in "${p[@]}"; do
        [[ "$x" =~ ^[0-9]{1,3}$ ]] || return 1
        ((10#$x >= 0 && 10#$x <= 255)) || return 1
    done
}

is_valid_cidr() {
    local value="$1" ip prefix
    [[ "$value" == */* ]] || return 1
    ip="${value%/*}"
    prefix="${value#*/}"
    is_valid_ipv4 "$ip" || return 1
    [[ "$prefix" =~ ^[0-9]{1,2}$ ]] || return 1
    ((10#$prefix >= 0 && 10#$prefix <= 32))
}

is_valid_dns_name() {
    local name="${1%.}" label
    [[ ${#name} -le 253 && "$name" == *.* ]] || return 1
    IFS='.' read -r -a labels <<<"$name"
    for label in "${labels[@]}"; do
        [[ ${#label} -ge 1 && ${#label} -le 63 ]] || return 1
        [[ "$label" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || return 1
    done
}

is_valid_netbios() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{0,14}$ ]]
}

domain_dn() {
    printf '%s' "$1" | awk -F. '{for(i=1;i<=NF;i++){printf "DC=%s%s",$i,(i<NF?",":"")}}'
}

netbios_from_domain() {
    printf '%s' "$1" | tr -cd '[:alnum:]' | tr '[:lower:]' '[:upper:]' | cut -c1-15
}

require_cmd() {
    local c="$1" purpose="${2:-operation}"
    if ! command_exists "$c"; then
        result ERROR "$c" "missing" "$purpose"
        return 1
    fi
}

safe_systemctl_state() {
    systemctl is-active "$1" 2>/dev/null || printf 'inactive'
}

detect_os() {
    [[ -r /etc/os-release ]] || { fail_msg "Missing /etc/os-release"; return 1; }
    # shellcheck disable=SC1091
    source /etc/os-release
    DISTRO_ID="${ID:-unknown}"
    DISTRO_LIKE="${ID_LIKE:-}"
    DISTRO_VERSION="${VERSION_ID:-unknown}"
    DISTRO_CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-unknown}}"
    PRETTY_NAME_SAFE="${PRETTY_NAME:-$DISTRO_ID}"

    case "$DISTRO_ID" in
        debian|ubuntu) ;;
        *)
            if [[ "$DISTRO_LIKE" == *debian* ]]; then
                warn_msg "Debian derivative detected: $DISTRO_ID. Supported best-effort only."
            else
                fail_msg "Unsupported distribution: $DISTRO_ID ($DISTRO_LIKE)"
                return 1
            fi
            ;;
    esac

    result INFO "Distribution" "$PRETTY_NAME_SAFE" "Debian 13 / Ubuntu 26.04"
}

select_primary_interface() {
    local candidate=""
    if [[ -n "$SSH_CLIENT_IP" ]] && is_valid_ipv4 "$SSH_CLIENT_IP"; then
        candidate="$(ip route get "$SSH_CLIENT_IP" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}' || true)"
    fi
    [[ -n "$candidate" ]] || candidate="$(ip route show default 2>/dev/null | sort -k5,5n | awk 'NR==1{print $5}' || true)"
    PRIMARY_IFACE="$candidate"

    if [[ -n "$PRIMARY_IFACE" ]]; then
        PRIMARY_CIDR="$(ip -4 -o addr show dev "$PRIMARY_IFACE" scope global 2>/dev/null | awk 'NR==1{print $4}' || true)"
        PRIMARY_IP="${PRIMARY_CIDR%%/*}"
    fi
    DEFAULT_GW="$(ip route show default 2>/dev/null | awk 'NR==1{print $3}' || true)"
}

detect_samba_role() {
    SAMBA_ROLE="none"
    if [[ -f /var/lib/samba/private/sam.ldb ]]; then
        SAMBA_ROLE="ad-dc"
    elif command_exists testparm && [[ -f /etc/samba/smb.conf ]]; then
        local role
        role="$(testparm -s --parameter-name='server role' 2>/dev/null || true)"
        case "${role,,}" in
            *"active directory domain controller"*) SAMBA_ROLE="ad-dc-config" ;;
            *"member"*) SAMBA_ROLE="member" ;;
            *"standalone"*) SAMBA_ROLE="standalone" ;;
            "") SAMBA_ROLE="unknown" ;;
            *) SAMBA_ROLE="$role" ;;
        esac
    fi
}

discover_existing_identity() {
    if command_exists testparm && [[ -f /etc/samba/smb.conf ]]; then
        REALM="$(testparm -s --parameter-name=realm 2>/dev/null | tr -d '\r' || true)"
        NETBIOS_DOMAIN="$(testparm -s --parameter-name=workgroup 2>/dev/null | tr -d '\r' || true)"
        REALM="${REALM^^}"
        [[ -n "$REALM" ]] && DOMAIN="${REALM,,}"
    fi
    DC_HOSTNAME="$(hostname -s 2>/dev/null || hostname)"
    DC_FQDN="$(hostname -f 2>/dev/null || printf '%s' "$DC_HOSTNAME")"
    DC_NETBIOS="${DC_HOSTNAME^^}"
    [[ -n "$PRIMARY_IP" ]] && DC_IP="$PRIMARY_IP"
}

save_config() {
    local tmp="${CONFIG_FILE}.tmp.$$"
    {
        printf 'DOMAIN=%q\n' "$DOMAIN"
        printf 'REALM=%q\n' "$REALM"
        printf 'NETBIOS_DOMAIN=%q\n' "$NETBIOS_DOMAIN"
        printf 'DC_HOSTNAME=%q\n' "$DC_HOSTNAME"
        printf 'DC_FQDN=%q\n' "$DC_FQDN"
        printf 'DC_NETBIOS=%q\n' "$DC_NETBIOS"
        printf 'DC_IP=%q\n' "$DC_IP"
        printf 'AD_CLIENT_CIDR=%q\n' "$AD_CLIENT_CIDR"
        printf 'SSH_SOURCE=%q\n' "$SSH_SOURCE"
        printf 'DNS_FORWARDER=%q\n' "$DNS_FORWARDER"
        printf 'TIMEZONE=%q\n' "$TIMEZONE"
        printf 'NTP_POOL=%q\n' "$NTP_POOL"
        printf 'ADMIN_USER=%q\n' "$ADMIN_USER"
        printf 'ENABLE_UFW=%q\n' "$ENABLE_UFW"
        printf 'ENABLE_GPOS=%q\n' "$ENABLE_GPOS"
    } >"$tmp"
    chmod 600 "$tmp"
    mv -f "$tmp" "$CONFIG_FILE"
}

load_config() {
    [[ -f "$CONFIG_FILE" ]] || return 1
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
}

backup_file() {
    local src="$1" rel dest hash mode owner
    [[ -e "$src" || -L "$src" ]] || return 0

    rel="${src#/}"
    dest="${BACKUP_DIR}/rootfs/${rel}"
    mkdir -p "$(dirname "$dest")"
    cp -a -- "$src" "$dest"

    hash="-"
    if [[ -f "$dest" ]] && command_exists sha256sum; then
        hash="$(sha256sum "$dest" | awk '{print $1}')"
    fi
    mode="$(stat -c '%a' "$src" 2>/dev/null || printf '?')"
    owner="$(stat -c '%U:%G' "$src" 2>/dev/null || printf '?')"
    BACKUP_MANIFEST+=("${src}|${dest}|${hash}|${mode}|${owner}")
    log DEBUG "Backup: $src -> $dest"
}

write_backup_manifest() {
    local manifest="${BACKUP_DIR}/manifest.txt"
    {
        printf 'Generated: %s\n' "$(date -Is)"
        printf 'Host: %s\n\n' "$(hostname -f 2>/dev/null || hostname)"
        printf 'source|backup|sha256|mode|owner\n'
        printf '%s\n' "${BACKUP_MANIFEST[@]}"
    } >"$manifest"
    chmod 600 "$manifest"
}

snapshot_system() {
    local d="${RUN_ROOT}/snapshot"
    mkdir -p "$d"
    chmod 700 "$d"

    {
        date -Is
        uname -a
        printf '\n-- ip addr --\n'
        ip -br addr 2>&1 || true
        printf '\n-- ip route --\n'
        ip route 2>&1 || true
        printf '\n-- resolver --\n'
        ls -l /etc/resolv.conf 2>&1 || true
        cat /etc/resolv.conf 2>&1 || true
        printf '\n-- services --\n'
        systemctl --no-pager --full status samba-ad-dc smbd nmbd winbind chrony systemd-resolved NetworkManager 2>&1 || true
        printf '\n-- ufw --\n'
        ufw status verbose 2>&1 || true
    } >"${d}/system.txt"
    chmod 600 "${d}/system.txt"

    if [[ -f /etc/samba/smb.conf ]]; then
        backup_file /etc/samba/smb.conf
        testparm -s >"${d}/testparm.txt" 2>&1 || true
    fi
    backup_file /etc/hosts
    backup_file /etc/resolv.conf
    backup_file /etc/krb5.conf
}

package_available() { apt-cache show "$1" >/dev/null 2>&1; }

install_required_packages() {
    step "Install required packages"

    require_cmd apt-get "Debian-family package management" || return 1
    log INFO "Refreshing package metadata; no distribution upgrade will be performed."
    apt-get update

    local dns_tools=""
    if package_available bind9-dnsutils; then
        dns_tools="bind9-dnsutils"
    elif package_available dnsutils; then
        dns_tools="dnsutils"
    else
        fail_msg "No supported DNS query package found."
        return 1
    fi

    local -a pkgs=(samba-ad-dc samba-ad-provision krb5-user chrony acl attr ldb-tools smbclient python3 iproute2 "$dns_tools")
    if [[ "$ENABLE_UFW" == "yes" ]] && package_available ufw; then
        pkgs+=(ufw)
    fi

    DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}"
    result PASS "Packages" "required packages present" "Samba/Kerberos/DNS/Chrony"
}

collect_identity() {
    step "Domain and network identity"

    select_primary_interface

    DC_HOSTNAME="$(ask 'Short hostname for the DC' "${DC_HOSTNAME:-dc01}")"
    DOMAIN="$(ask 'AD DNS domain' "${DOMAIN:-example.internal}")"
    REALM="${DOMAIN^^}"
    DC_FQDN="${DC_HOSTNAME}.${DOMAIN}"
    DC_IP="$(ask 'DC IPv4 address' "${DC_IP:-${PRIMARY_IP:-192.168.1.10}}")"
    NETBIOS_DOMAIN="$(ask 'NetBIOS domain' "${NETBIOS_DOMAIN:-$(netbios_from_domain "$DOMAIN")}")"
    NETBIOS_DOMAIN="${NETBIOS_DOMAIN^^}"
    DC_NETBIOS="$(ask 'NetBIOS name of DC' "${DC_NETBIOS:-${DC_HOSTNAME^^}}")"
    DC_NETBIOS="${DC_NETBIOS^^}"

    is_valid_dns_name "$DOMAIN" || { fail_msg "Invalid DNS domain: $DOMAIN"; return 1; }
    is_valid_ipv4 "$DC_IP" || { fail_msg "Invalid IPv4: $DC_IP"; return 1; }
    is_valid_netbios "$NETBIOS_DOMAIN" || { fail_msg "Invalid NetBIOS domain: $NETBIOS_DOMAIN"; return 1; }
    is_valid_netbios "$DC_NETBIOS" || { fail_msg "Invalid NetBIOS DC name: $DC_NETBIOS"; return 1; }

    local first_label="${DOMAIN%%.*}"
    if [[ "${first_label,,}" == "${DC_HOSTNAME,,}" ]]; then
        warn_msg "Hostname '$DC_HOSTNAME' equals the first DNS label of '$DOMAIN'; resulting FQDN is '$DC_FQDN'."
    fi

    if ! ip -4 addr show | grep -Fq " ${DC_IP}/"; then
        fail_msg "DC IP $DC_IP is not currently assigned to this server. Configure stable addressing first."
        return 1
    fi

    result INFO "Primary interface" "${PRIMARY_IFACE:-unknown}" "management/data interface"
    result INFO "DC FQDN" "$DC_FQDN" "unique hostname"
    result INFO "DC IP" "$DC_IP" "stable address"
}

collect_network_policy() {
    step "Network policy inputs"

    local route_cidr="${PRIMARY_CIDR:-192.168.1.10/24}"
    local default_net="192.168.1.0/24"
    if command_exists python3 && [[ -n "$route_cidr" ]]; then
        default_net="$(python3 - "$route_cidr" <<'PY'
import ipaddress, sys
try:
    print(ipaddress.ip_interface(sys.argv[1]).network)
except Exception:
    print("192.168.1.0/24")
PY
)"
    fi

    AD_CLIENT_CIDR="$(ask 'AD/NTP client network (CIDR)' "${AD_CLIENT_CIDR:-$default_net}")"
    is_valid_ipv4 "$AD_CLIENT_CIDR" && AD_CLIENT_CIDR="${AD_CLIENT_CIDR}/32"
    is_valid_cidr "$AD_CLIENT_CIDR" || { fail_msg "Invalid AD client CIDR: $AD_CLIENT_CIDR"; return 1; }

    if [[ -z "$SSH_SOURCE" && -n "$SSH_CLIENT_IP" ]] && is_valid_ipv4 "$SSH_CLIENT_IP"; then
        SSH_SOURCE="${SSH_CLIENT_IP}/32"
    fi
    SSH_SOURCE="$(ask 'SSH management source (CIDR)' "${SSH_SOURCE:-$AD_CLIENT_CIDR}")"
    is_valid_ipv4 "$SSH_SOURCE" && SSH_SOURCE="${SSH_SOURCE}/32"
    is_valid_cidr "$SSH_SOURCE" || { fail_msg "Invalid SSH source: $SSH_SOURCE"; return 1; }

    result INFO "AD clients" "$AD_CLIENT_CIDR" "restricted source"
    result INFO "SSH source" "$SSH_SOURCE" "restricted management"
}

configure_hostname_hosts() {
    step "Hostname and hosts file"

    if [[ "$(hostname -s)" != "$DC_HOSTNAME" ]]; then
        if confirm "Set hostname to $DC_HOSTNAME?" Y; then
            backup_file /etc/hostname
            hostnamectl set-hostname "$DC_HOSTNAME"
            change APPLIED "hostname=$DC_HOSTNAME"
        else
            fail_msg "Provisioning requires the chosen hostname to be applied."
            return 1
        fi
    fi

    local tmp begin="# BEGIN DEBIAN-AD-ASSISTANT" end="# END DEBIAN-AD-ASSISTANT"
    backup_file /etc/hosts
    tmp="$(mktemp)"
    awk -v begin="$begin" -v end="$end" '
        $0 == begin {skip=1; next}
        $0 == end {skip=0; next}
        !skip {print}
    ' /etc/hosts >"$tmp"
    {
        cat "$tmp"
        printf '%s\n' "$begin"
        printf '%s\t%s %s\n' "$DC_IP" "$DC_FQDN" "$DC_HOSTNAME"
        printf '%s\n' "$end"
    } >"${tmp}.new"
    chmod 644 "${tmp}.new"
    mv -f "${tmp}.new" /etc/hosts
    rm -f "$tmp"
    result PASS "/etc/hosts" "$DC_FQDN -> $DC_IP" "present"
}

configure_time() {
    step "Time synchronization"

    TIMEZONE="$(ask 'Timezone' "${TIMEZONE:-Europe/London}")"
    NTP_POOL="$(ask 'NTP pool/server' "${NTP_POOL:-pool.ntp.org}")"

    timedatectl set-timezone "$TIMEZONE"
    mkdir -p /etc/chrony/conf.d
    backup_file /etc/chrony/chrony.conf
    backup_file /etc/chrony/conf.d/90-debian-ad.conf

    cat >/etc/chrony/conf.d/90-debian-ad.conf <<EOF
# Managed by ${SCRIPT_NAME}.
pool ${NTP_POOL} iburst maxsources 4
allow ${AD_CLIENT_CIDR}
EOF

    systemctl enable --now chrony >/dev/null
    systemctl restart chrony
    chronyc tracking >/dev/null 2>&1 || warn_msg "Chrony is running but tracking query failed."
    result PASS "Chrony" "$(safe_systemctl_state chrony)" "active"
}

configure_samba_service_model() {
    step "Samba service model"

    local active=()
    local u
    for u in smbd nmbd winbind; do
        if systemctl is-active --quiet "$u" 2>/dev/null; then
            active+=("$u")
        fi
    done

    if ((${#active[@]})); then
        printf 'Active Samba units detected: %s\n' "${active[*]}"
        if [[ "$SAMBA_ROLE" != "none" ]]; then
            if ! confirm_high_risk "Disable/mask ${active[*]} and use samba-ad-dc"; then
                fail_msg "Service model change cancelled."
                return 1
            fi
        else
            log INFO "Samba units were started by package installation on a fresh bootstrap; switching to samba-ad-dc model."
        fi
    fi

    for u in smbd nmbd winbind; do
        systemctl disable --now "$u" >/dev/null 2>&1 || true
        systemctl mask "$u" >/dev/null 2>&1 || true
    done
    systemctl unmask samba-ad-dc >/dev/null 2>&1 || true
    systemctl enable samba-ad-dc >/dev/null
    result PASS "Samba service model" "samba-ad-dc" "dedicated AD/DC"
}

provision_new_domain() {
    step "Provision Samba AD/DC"

    if [[ -f /var/lib/samba/private/sam.ldb ]]; then
        fail_msg "Existing sam.ldb detected. Reprovision is prohibited."
        return 1
    fi

    if [[ -f /etc/samba/smb.conf ]]; then
        backup_file /etc/samba/smb.conf
        mv /etc/samba/smb.conf "${BACKUP_DIR}/smb.conf.pre-provision"
    fi

    printf '\nSamba will request the initial Administrator password directly.\n'
    samba-tool domain provision \
        --domain="$NETBIOS_DOMAIN" \
        --realm="$REALM" \
        --server-role=dc \
        --use-rfc2307 \
        --dns-backend=SAMBA_INTERNAL <"$INPUT_FD"

    systemctl restart samba-ad-dc
    result PASS "Domain provision" "$DOMAIN" "new AD/DC"
}

detect_dns_forwarder() {
    local candidates=""
    if command_exists resolvectl && systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        candidates="$(resolvectl dns 2>/dev/null | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' || true)"
    else
        candidates="$(awk '/^[[:space:]]*nameserver[[:space:]]+/{print $2}' /etc/resolv.conf 2>/dev/null || true)"
    fi
    printf '%s\n' "$candidates" | grep -Ev '^(127\.0\.0\.1|127\.0\.0\.53)$' | head -n1 || true
}

atomic_write_resolv_conf() {
    local tmp="${RUN_ROOT}/resolv.conf.new"
    cat >"$tmp" <<EOF
nameserver 127.0.0.1
search ${DOMAIN}
EOF
    chmod 644 "$tmp"

    backup_file /etc/resolv.conf
    if [[ -L /etc/resolv.conf ]]; then
        unlink /etc/resolv.conf
    fi
    cp -f "$tmp" /etc/resolv.conf
    chmod 644 /etc/resolv.conf
}

configure_resolver_kerberos() {
    step "DNS resolver and Kerberos"

    require_cmd dig "DNS validation" || return 1
    require_cmd testparm "Samba configuration validation" || return 1

    if [[ -z "$DNS_FORWARDER" ]]; then
        DNS_FORWARDER="$(detect_dns_forwarder)"
    fi
    DNS_FORWARDER="$(ask 'External DNS forwarder' "${DNS_FORWARDER:-1.1.1.1}")"
    is_valid_ipv4 "$DNS_FORWARDER" || { fail_msg "Invalid forwarder: $DNS_FORWARDER"; return 1; }

    backup_file /etc/samba/smb.conf
    python3 - "$DNS_FORWARDER" <<'PY'
from pathlib import Path
import re, sys
p = Path("/etc/samba/smb.conf")
text = p.read_text()
forwarder = sys.argv[1]
rx = re.compile(r"(?mi)^[ \t]*dns forwarder[ \t]*=.*$")
if rx.search(text):
    text = rx.sub(f"\tdns forwarder = {forwarder}", text, count=1)
else:
    text = re.sub(r"(?mi)^\[global\][ \t]*$", lambda m: m.group(0) + f"\n\tdns forwarder = {forwarder}", text, count=1)
p.write_text(text)
PY
    testparm -s >/dev/null

    systemctl restart samba-ad-dc
    sleep 1
    if ! dig @127.0.0.1 +short -t A "$DC_FQDN" | grep -Fxq "$DC_IP"; then
        fail_msg "Local Samba DNS does not yet resolve $DC_FQDN to $DC_IP; refusing resolver switch."
        return 1
    fi

    if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        if confirm "Disable systemd-resolved and switch host resolver to Samba DNS?" Y; then
            systemctl disable --now systemd-resolved
            change APPLIED "systemd-resolved disabled"
        else
            warn_msg "Resolver not changed; local DNS integration remains operator-managed."
            return 0
        fi
    fi

    if systemctl is-active --quiet NetworkManager 2>/dev/null && command_exists nmcli; then
        local conn
        conn="$(nmcli -g GENERAL.CONNECTION dev show "$PRIMARY_IFACE" 2>/dev/null || true)"
        if [[ -n "$conn" && "$conn" != "--" ]]; then
            if confirm "Set NetworkManager connection '$conn' DNS to 127.0.0.1?" Y; then
                nmcli connection modify "$conn" ipv4.ignore-auto-dns yes ipv4.dns "127.0.0.1"
                nmcli device reapply "$PRIMARY_IFACE" >/dev/null 2>&1 || true
                change APPLIED "NetworkManager DNS=127.0.0.1"
            fi
        fi
    fi

    atomic_write_resolv_conf

    if ! dig +short "$DC_FQDN" | grep -Fxq "$DC_IP"; then
        warn_msg "Resolver verification failed; restoring previous /etc/resolv.conf backup if available."
        local b="${BACKUP_DIR}/rootfs/etc/resolv.conf"
        [[ -e "$b" || -L "$b" ]] && cp -a "$b" /etc/resolv.conf
        return 1
    fi

    [[ -f /var/lib/samba/private/krb5.conf ]] || {
        fail_msg "Missing Samba-generated krb5.conf"
        return 1
    }
    backup_file /etc/krb5.conf
    cp -f /var/lib/samba/private/krb5.conf /etc/krb5.conf
    chmod 644 /etc/krb5.conf

    result PASS "Resolver" "127.0.0.1 / $DOMAIN" "Samba DNS"
    result PASS "Kerberos config" "/etc/krb5.conf" "Samba-generated"
}

ensure_kerberos_ticket() {
    require_cmd kinit "Kerberos authentication" || return 1
    local principal="${ADMIN_USER}@${REALM}"

    if KRB5CCNAME="$KRB5CCNAME" klist -s >/dev/null 2>&1; then
        return 0
    fi

    printf 'Kerberos ticket required for %s (private cache: %s)\n' "$principal" "$KRB5_CACHE"
    KRB5CCNAME="$KRB5CCNAME" kinit "$principal" <"$INPUT_FD"
    KRB5CCNAME="$KRB5CCNAME" klist -s
}

ensure_directory_baseline() {
    step "Directory baseline"

    ensure_kerberos_ticket
    local base_dn
    base_dn="$(domain_dn "$DOMAIN")"

    local ou
    for ou in Usuarios Equipos Grupos; do
        if ldbsearch -H /var/lib/samba/private/sam.ldb -b "OU=${ou},${base_dn}" -s base dn >/dev/null 2>&1; then
            result PASS "OU $ou" "present" "present"
        else
            if confirm "Create OU=$ou?" Y; then
                samba-tool ou create "OU=${ou},${base_dn}" >/dev/null
                change APPLIED "Created OU=$ou"
            fi
        fi
    done

    local grp
    for grp in Empleados AdministradoresTI; do
        if samba-tool group show "$grp" >/dev/null 2>&1; then
            result PASS "Group $grp" "present" "present"
        elif confirm "Create group '$grp'?" Y; then
            samba-tool group add "$grp" >/dev/null
            change APPLIED "Created group=$grp"
        fi
    done

    if ! samba-tool user show "$ADMIN_USER" >/dev/null 2>&1; then
        if confirm "Create administrative AD account '$ADMIN_USER'?" Y; then
            samba-tool user create "$ADMIN_USER" <"$INPUT_FD"
            change APPLIED "Created admin user=$ADMIN_USER"
        fi
    fi

    if samba-tool user show "$ADMIN_USER" >/dev/null 2>&1; then
        if ! samba-tool group listmembers "Domain Admins" 2>/dev/null | grep -Fxqi "$ADMIN_USER"; then
            if confirm_high_risk "Add '$ADMIN_USER' to Domain Admins"; then
                samba-tool group addmembers "Domain Admins" "$ADMIN_USER" >/dev/null
                change APPLIED "Added $ADMIN_USER to Domain Admins"
            fi
        fi
        if samba-tool group show AdministradoresTI >/dev/null 2>&1 &&
           ! samba-tool group listmembers AdministradoresTI 2>/dev/null | grep -Fxqi "$ADMIN_USER"; then
            samba-tool group addmembers AdministradoresTI "$ADMIN_USER" >/dev/null
            change APPLIED "Added $ADMIN_USER to AdministradoresTI"
        fi
    fi
}

write_gpo_sources() {
    require_cmd python3 "safe JSON generation" || return 1
    mkdir -p "$GPO_DIR"

    python3 - "$GPO_DIR" "$DOMAIN" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
domain = sys.argv[2]

user = [
  {
    "keyname": r"Software\Policies\Microsoft\Windows\Control Panel\Desktop",
    "valuename": "ScreenSaveActive",
    "class": "USER",
    "type": "REG_SZ",
    "data": "1",
  },
  {
    "keyname": r"Software\Policies\Microsoft\Windows\Control Panel\Desktop",
    "valuename": "ScreenSaveTimeOut",
    "class": "USER",
    "type": "REG_SZ",
    "data": "600",
  },
  {
    "keyname": r"Software\Policies\Microsoft\Windows\Control Panel\Desktop",
    "valuename": "ScreenSaverIsSecure",
    "class": "USER",
    "type": "REG_SZ",
    "data": "1",
  },
]

machine = [
  {
    "keyname": r"SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System",
    "valuename": "LegalNoticeCaption",
    "class": "MACHINE",
    "type": "REG_SZ",
    "data": domain,
  },
  {
    "keyname": r"SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System",
    "valuename": "LegalNoticeText",
    "class": "MACHINE",
    "type": "REG_SZ",
    "data": f"Sistema perteneciente al dominio {domain}. Acceso restringido a usuarios autorizados.",
  },
  {
    "keyname": r"SOFTWARE\Policies\Microsoft\Windows NT\DNSClient",
    "valuename": "EnableMulticast",
    "class": "MACHINE",
    "type": "REG_DWORD",
    "data": 0,
  },
]

for name, data in (("user-baseline.json", user), ("machine-baseline.json", machine)):
    p = root / name
    p.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    p.chmod(0o600)
PY

    python3 -m json.tool "${GPO_DIR}/user-baseline.json" >/dev/null
    python3 -m json.tool "${GPO_DIR}/machine-baseline.json" >/dev/null
}

find_gpo_guid() {
    local name="$1" output
    output="$(samba-tool gpo listall --use-kerberos=required 2>/dev/null || true)"
    printf '%s\n' "$output" | awk -v target="$name" '
        BEGIN { guid="" }
        /^GPO[[:space:]]*:/ { guid=$3 }
        /display name[[:space:]]*:/ {
            line=$0
            sub(/^.*display name[[:space:]]*:[[:space:]]*/, "", line)
            if (line == target) { print guid; exit }
        }
    ' | grep -oE '\{[0-9A-Fa-f-]{36}\}' | head -n1 || true
}

ensure_gpo() {
    local name="$1" guid output
    guid="$(find_gpo_guid "$name")"
    if [[ -n "$guid" ]]; then
        printf '%s' "$guid"
        return 0
    fi
    output="$(samba-tool gpo create "$name" --use-kerberos=required 2>&1)"
    printf '%s\n' "$output" >>"$LOG_FILE"
    guid="$(printf '%s\n' "$output" | grep -oE '\{[0-9A-Fa-f-]{36}\}' | head -n1 || true)"
    [[ -n "$guid" ]] || return 1
    printf '%s' "$guid"
}

manage_gpos() {
    step "Group Policy"

    if ! samba-tool gpo load --help >/dev/null 2>&1; then
        result SKIP "GPO load" "unsupported by installed Samba" "modern samba-tool"
        return 0
    fi

    ensure_kerberos_ticket
    write_gpo_sources

    if [[ "$SAMBA_ROLE" == "ad-dc" ]]; then
        printf 'A domain backup is recommended before changing GPO/SYSVOL on an existing DC.\n'
        if confirm "Create domain backup first?" Y; then
            create_domain_backup no
        fi
    fi

    local user_guid machine_guid base_dn
    user_guid="$(ensure_gpo 'DC - User Baseline')"
    machine_guid="$(ensure_gpo 'DC - Computer Baseline')"
    base_dn="$(domain_dn "$DOMAIN")"

    samba-tool gpo load "$user_guid" --content="${GPO_DIR}/user-baseline.json" --use-kerberos=required >/dev/null
    samba-tool gpo load "$machine_guid" --content="${GPO_DIR}/machine-baseline.json" --use-kerberos=required >/dev/null
    samba-tool gpo setlink "$base_dn" "$user_guid" --use-kerberos=required >/dev/null
    samba-tool gpo setlink "$base_dn" "$machine_guid" --use-kerberos=required >/dev/null

    if samba-tool ntacl sysvolcheck >"${RUN_ROOT}/sysvolcheck-after-gpo.txt" 2>&1; then
        result PASS "SYSVOL ACL" "clean" "clean"
    else
        result WARN "SYSVOL ACL" "differences detected" "manual review"
        warn_msg "Do not run sysvolreset blindly. Use Manage -> Advanced SYSVOL repair after backup."
    fi
}

ufw_allow() {
    ufw "$@" >/dev/null
}

configure_ufw() {
    step "Firewall"

    [[ "$ENABLE_UFW" == "yes" ]] || { result SKIP "UFW" "disabled by operator" "reviewed firewall"; return 0; }
    require_cmd ufw "UFW configuration" || return 0

    printf 'Management rule will be installed before default inbound policy changes.\n'
    printf '  SSH source : %s\n  AD clients : %s\n  DC IP      : %s\n' "$SSH_SOURCE" "$AD_CLIENT_CIDR" "$DC_IP"

    if [[ $REMOTE_SESSION -eq 1 ]]; then
        warn_msg "Remote SSH session detected from ${SSH_CLIENT_IP:-unknown}; firewall changes can affect availability."
    fi
    confirm "Apply/update UFW policy?" Y || { result SKIP "UFW" "operator skipped" "unchanged"; return 0; }

    ufw_allow allow from "$SSH_SOURCE" to "$DC_IP" port 22 proto tcp
    ufw default deny incoming >/dev/null
    ufw default allow outgoing >/dev/null

    local p
    local tcp_ports=(53 88 135 139 389 445 464 3268)
    local udp_ports=(53 88 123 137 138 389 464)
    for p in "${tcp_ports[@]}"; do
        ufw_allow allow from "$AD_CLIENT_CIDR" to "$DC_IP" port "$p" proto tcp
    done
    for p in "${udp_ports[@]}"; do
        ufw_allow allow from "$AD_CLIENT_CIDR" to "$DC_IP" port "$p" proto udp
    done
    ufw_allow allow from "$AD_CLIENT_CIDR" to "$DC_IP" port 49152:65535 proto tcp
    ufw --force enable >/dev/null

    result PASS "UFW" "$(ufw status | head -n1)" "active"
}

create_domain_backup() {
    local progress="${1:-yes}"
    [[ "$progress" == "yes" ]] && step "Domain backup"

    if [[ "$SAMBA_ROLE" != "ad-dc" ]]; then
        result SKIP "Domain backup" "no local AD database" "AD/DC required"
        return 0
    fi
    require_cmd samba-tool "domain backup" || return 1

    ensure_kerberos_ticket

    mkdir -p "$DOMAIN_BACKUP_DIR"
    local server="${DC_FQDN:-127.0.0.1}"
    log INFO "Creating online domain backup in $DOMAIN_BACKUP_DIR"
    samba-tool domain backup online \
        --server="$server" \
        --targetdir="$DOMAIN_BACKUP_DIR" \
        --use-krb5-ccache="$KRB5CCNAME"
    chmod -R go-rwx "$DOMAIN_BACKUP_DIR"
    result PASS "Domain backup" "$DOMAIN_BACKUP_DIR" "completed"
}

validate_ad() {
    step "AD/DC validation"

    local fail=0
    if systemctl is-active --quiet samba-ad-dc; then
        result PASS "samba-ad-dc" "active" "active"
    else
        result FAIL "samba-ad-dc" "inactive" "active"; fail=1
    fi

    if command_exists testparm; then
        if testparm -s >/dev/null 2>&1; then
            result PASS "smb.conf" "valid" "valid"
        else
            result FAIL "smb.conf" "invalid" "valid"; fail=1
        fi
    else
        result ERROR "testparm" "missing" "installed"; fail=1
    fi

    if command_exists dig && [[ -n "$DOMAIN" && -n "$DC_FQDN" ]]; then
        local expected_ip="${DC_IP:-$PRIMARY_IP}"
        if [[ -n "$expected_ip" ]] && dig @127.0.0.1 +short A "$DC_FQDN" | grep -Fxq "$expected_ip"; then
            result PASS "DNS A" "$DC_FQDN -> $expected_ip" "correct"
        else
            result WARN "DNS A" "unexpected/no answer" "$DC_FQDN"
        fi

        local srv ans
        for srv in _ldap._tcp _kerberos._tcp _kerberos._udp _kpasswd._udp; do
            ans="$(dig @127.0.0.1 +short SRV "${srv}.${DOMAIN}" 2>/dev/null | tr '\n' ' ')"
            [[ -n "$ans" ]] && result PASS "SRV $srv" "$ans" "present" || result FAIL "SRV $srv" "missing" "present"
        done
    else
        result SKIP "DNS validation" "dig/domain data unavailable" "available"
    fi

    if command_exists samba-tool; then
        samba-tool domain info 127.0.0.1 >"${RUN_ROOT}/domain-info.txt" 2>&1 \
            && result PASS "Domain info" "reachable" "$DOMAIN" \
            || result FAIL "Domain info" "failed" "reachable"

        samba-tool dbcheck --cross-ncs >"${RUN_ROOT}/dbcheck.txt" 2>&1 \
            && result PASS "AD dbcheck" "completed" "clean/no fatal errors" \
            || result WARN "AD dbcheck" "reported issues" "review ${RUN_ROOT}/dbcheck.txt"

        samba-tool ntacl sysvolcheck >"${RUN_ROOT}/sysvolcheck.txt" 2>&1 \
            && result PASS "SYSVOL ACL" "consistent" "consistent" \
            || result WARN "SYSVOL ACL" "differences" "review ${RUN_ROOT}/sysvolcheck.txt"

        if samba-tool gpo aclcheck >"${RUN_ROOT}/gpo-aclcheck.txt" 2>&1; then
            result PASS "GPO ACL" "consistent" "consistent"
        else
            result WARN "GPO ACL" "differences/unavailable" "review"
        fi
    fi

    return "$fail"
}

audit_security_baseline() {
    step "Security baseline evidence"

    local benchmark="CIS-oriented only"
    case "$DISTRO_ID:$DISTRO_VERSION" in
        debian:13*) benchmark="CIS Debian Linux 13 Benchmark 1.1.0 (reference)" ;;
        ubuntu:26.04*) benchmark="CIS Ubuntu Linux 26.04 LTS Benchmark 1.0.0 (reference)" ;;
    esac
    result INFO "Benchmark reference" "$benchmark" "external full benchmark required"

    if command_exists usg; then
        result INFO "Ubuntu Security Guide" "installed" "optional official audit"
    else
        result INFO "Full CIS scanner" "not invoked" "CIS-CAT/USG/authorized tooling"
    fi

    if command_exists sshd; then
        local rootlogin passauth
        rootlogin="$(sshd -T 2>/dev/null | awk '$1=="permitrootlogin"{print $2; exit}' || true)"
        passauth="$(sshd -T 2>/dev/null | awk '$1=="passwordauthentication"{print $2; exit}' || true)"
        [[ "$rootlogin" == "no" ]] \
            && result PASS "SSH root login" "disabled" "disabled" \
            || result WARN "SSH root login" "${rootlogin:-unknown}" "review/tailor"
        result INFO "SSH password auth" "${passauth:-unknown}" "tailor to environment"
    fi

    if command_exists aa-status; then
        aa-status --enabled >/dev/null 2>&1 \
            && result PASS "AppArmor" "enabled" "enabled" \
            || result WARN "AppArmor" "not enabled" "enabled"
    fi

    if systemctl is-active --quiet auditd 2>/dev/null; then
        result PASS "auditd" "active" "active where baseline requires"
    else
        result INFO "auditd" "inactive/unavailable" "evaluate against selected profile"
    fi
}

audit_existing() {
    step "Current state audit"

    result INFO "OS" "$PRETTY_NAME_SAFE" "supported target"
    result INFO "Samba role" "$SAMBA_ROLE" "known"
    result INFO "Hostname" "$(hostname -f 2>/dev/null || hostname)" "FQDN"
    result INFO "Interface" "${PRIMARY_IFACE:-unknown}" "known"
    result INFO "IPv4" "${PRIMARY_CIDR:-unknown}" "stable"
    result INFO "Gateway" "${DEFAULT_GW:-unknown}" "known"
    result INFO "Remote session" "$([[ $REMOTE_SESSION -eq 1 ]] && echo yes || echo no)" "known"

    local u
    for u in samba-ad-dc smbd nmbd winbind chrony systemd-resolved NetworkManager; do
        result INFO "service:$u" "$(safe_systemctl_state "$u")" "role-dependent"
    done

    if command_exists ufw; then
        result INFO "UFW" "$(ufw status | head -n1)" "reviewed"
    else
        result INFO "UFW" "not installed" "optional"
    fi
}

advanced_sysvol_repair() {
    printf '\nThis operation changes SYSVOL ACLs to Samba defaults.\n'
    step "Backup before SYSVOL repair"
    create_domain_backup no
    step "SYSVOL ACL repair"
    if ! confirm_high_risk "Run samba-tool ntacl sysvolreset"; then
        result SKIP "SYSVOL reset" "cancelled" "no change"
        return 0
    fi
    samba-tool ntacl sysvolreset
    samba-tool ntacl sysvolcheck
    change APPLIED "samba-tool ntacl sysvolreset"
}

write_report() {
    write_backup_manifest
    {
        printf '%s %s\n' "$SCRIPT_NAME" "$SCRIPT_VERSION"
        printf 'Generated: %s\n' "$(date -Is)"
        printf 'Mode: %s\n' "$MODE"
        printf 'Host: %s\n' "$(hostname -f 2>/dev/null || hostname)"
        printf 'OS: %s\n' "$PRETTY_NAME_SAFE"
        printf 'Samba role: %s\n' "$SAMBA_ROLE"
        printf 'Domain: %s\n' "$DOMAIN"
        printf 'Realm: %s\n' "$REALM"
        printf 'DC: %s\n' "$DC_FQDN"
        printf 'DC IP: %s\n' "$DC_IP"
        printf 'Remote: %s\n' "$REMOTE_SESSION"
        printf '\n=== RESULTS ===\n'
        printf '%s\n' "${RESULTS[@]}"
        printf '\n=== CHANGES ===\n'
        printf '%s\n' "${CHANGES[@]}"
        printf '\n=== WARNINGS ===\n'
        printf '%s\n' "${WARNINGS[@]}"
        printf '\n=== FAILURES ===\n'
        printf '%s\n' "${FAILURES[@]}"
        printf '\nBackup root: %s\n' "$BACKUP_DIR"
        printf 'Run root: %s\n' "$RUN_ROOT"
    } >"$REPORT_FILE"
    chmod 600 "$REPORT_FILE"
}

summary() {
    section "FINAL SUMMARY"
    local pass warn fail applied skipped
    pass="$(printf '%s\n' "${RESULTS[@]}" | grep -c '^PASS|' || true)"
    warn="$(printf '%s\n' "${RESULTS[@]}" | grep -c '^WARN|' || true)"
    fail="$(printf '%s\n' "${RESULTS[@]}" | grep -Ec '^(FAIL|ERROR)\|' || true)"
    applied="$(printf '%s\n' "${CHANGES[@]}" | grep -c '^APPLIED|' || true)"
    skipped="$(printf '%s\n' "${CHANGES[@]}" | grep -c '^SKIPPED|' || true)"

    printf '%bPASS%b=%s  %bWARN%b=%s  %bFAIL%b=%s  Applied=%s  Skipped=%s\n' \
        "$C_GREEN" "$C_RESET" "$pass" \
        "$C_YELLOW" "$C_RESET" "$warn" \
        "$C_RED" "$C_RESET" "$fail" "$applied" "$skipped"
    printf 'Log     : %s\n' "$LOG_FILE"
    printf 'Report  : %s\n' "$REPORT_FILE"
    printf 'Backups : %s\n' "$BACKUP_DIR"
    printf 'Run data: %s\n' "$RUN_ROOT"
}

bootstrap_mode() {
    detect_samba_role
    if [[ "$SAMBA_ROLE" != "none" ]]; then
        fail_msg "Existing Samba role/configuration detected ($SAMBA_ROLE). Bootstrap will not repurpose it automatically."
        fail_msg "Use --manage for an AD/DC, or plan an explicit Samba/member/file-server migration."
        return 2
    fi

    set_progress_plan 13
    audit_existing
    collect_identity
    snapshot_system
    install_required_packages
    collect_network_policy
    configure_ufw
    configure_hostname_hosts
    configure_samba_service_model
    configure_time
    provision_new_domain
    configure_resolver_kerberos
    ensure_directory_baseline
    if [[ "$ENABLE_GPOS" == "yes" ]] && confirm "Create/link baseline GPOs?" Y; then
        manage_gpos
    else
        step "Group Policy"
        result SKIP "GPO" "operator disabled" "optional"
    fi
    validate_ad
    save_config
}

manage_menu() {
    while true; do
        printf '\n%bManage existing AD/DC%b\n' "$C_CYAN" "$C_RESET"
        printf '  [1] Audit current state\n'
        printf '  [2] Validate AD/DC health\n'
        printf '  [3] Configure local resolver/Kerberos\n'
        printf '  [4] Configure Chrony\n'
        printf '  [5] Configure UFW\n'
        printf '  [6] Ensure directory baseline\n'
        printf '  [7] Create/update baseline GPOs\n'
        printf '  [8] Create domain backup\n'
        printf '  [9] Advanced SYSVOL ACL repair\n'
        printf '  [0] Exit\n'
        local choice
        choice="$(ask 'Choice' '1')"
        case "$choice" in
            1) set_progress_plan 2; audit_existing; audit_security_baseline ;;
            2) set_progress_plan 1; validate_ad ;;
            3) set_progress_plan 1; configure_resolver_kerberos ;;
            4) set_progress_plan 1; [[ -n "$AD_CLIENT_CIDR" ]] || collect_network_policy; configure_time ;;
            5) set_progress_plan 1; [[ -n "$AD_CLIENT_CIDR" && -n "$SSH_SOURCE" ]] || collect_network_policy; configure_ufw ;;
            6) set_progress_plan 1; ensure_directory_baseline ;;
            7) set_progress_plan 1; manage_gpos ;;
            8) set_progress_plan 1; create_domain_backup ;;
            9) set_progress_plan 2; advanced_sysvol_repair ;;
            0) break ;;
            *) printf 'Invalid choice.\n' ;;
        esac
    done
}

manage_mode() {
    detect_samba_role
    [[ "$SAMBA_ROLE" == "ad-dc" || "$SAMBA_ROLE" == "ad-dc-config" ]] || {
        fail_msg "No existing Samba AD/DC detected."
        return 2
    }

    load_config || true
    discover_existing_identity
    snapshot_system
    manage_menu
    save_config
}

audit_mode() {
    set_progress_plan 3
    audit_existing
    audit_security_baseline
    if [[ "$SAMBA_ROLE" == "ad-dc" || "$SAMBA_ROLE" == "ad-dc-config" ]]; then
        discover_existing_identity
        validate_ad || true
    else
        step "AD/DC validation"
        result SKIP "AD/DC validation" "not an AD/DC" "not applicable"
    fi
}

validate_mode() {
    set_progress_plan 1
    [[ "$SAMBA_ROLE" == "ad-dc" || "$SAMBA_ROLE" == "ad-dc-config" ]] || {
        fail_msg "No Samba AD/DC detected."
        return 2
    }
    load_config || true
    discover_existing_identity
    validate_ad
}

backup_mode() {
    [[ "$SAMBA_ROLE" == "ad-dc" || "$SAMBA_ROLE" == "ad-dc-config" ]] || {
        fail_msg "No Samba AD/DC detected."
        return 2
    }
    load_config || true
    discover_existing_identity
    ADMIN_USER="$(ask 'AD admin account' "${ADMIN_USER:-Administrator}")"
    set_progress_plan 1
    create_domain_backup
}

interactive_mode() {
    if [[ "$SAMBA_ROLE" == "ad-dc" || "$SAMBA_ROLE" == "ad-dc-config" ]]; then
        MODE="manage"
        manage_mode
    else
        printf 'No AD/DC database detected.\n'
        if confirm "Start NEW AD/DC bootstrap?" N; then
            MODE="bootstrap"
            bootstrap_mode
        else
            MODE="audit"
            audit_mode
        fi
    fi
}

main() {
    parse_args "$@"
    require_root
    detect_terminal
    need_tty
    init_runtime
    banner

    detect_os
    select_primary_interface
    detect_samba_role

    case "$MODE" in
        audit) audit_mode ;;
        validate) validate_mode ;;
        bootstrap) bootstrap_mode ;;
        manage) manage_mode ;;
        backup) backup_mode ;;
        interactive) interactive_mode ;;
        *) fail_msg "Unknown mode: $MODE"; return 2 ;;
    esac

    write_report
    summary
}

main "$@"
