#!/usr/bin/env bash
# DEBIAN AD Assistant - review candidate
# Version 3.1.1-review
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
SCRIPT_VERSION="3.1.1-review"

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
PRIMARY_IFACE=""  # compatibility alias; points to AD_IFACE after discovery
PRIMARY_CIDR=""
PRIMARY_IP=""
DEFAULT_GW=""
NETWORK_MODE="unknown"
WAN_IFACE=""
WAN_IP=""
WAN_CIDR=""
AD_IFACE=""
AD_IP=""
AD_CIDR=""
MGMT_IFACE=""
SSH_LOCAL_IP=""
AD_ADDRESS_METHOD="unknown"
SAMBA_INTERFACE_SCOPED="no"
POST_INSTALL_FILE="${STATE_DIR}/POST-INSTALL.txt"

DNS_TRANSACTION_ACTIVE=0
RESOLV_SNAPSHOT=""
RESOLVED_WAS_ACTIVE=0
RESOLVED_WAS_ENABLED=0
UPSTREAM_RESOLVER=""

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

# ---------------------------------------------------------------------------
# Common runtime helpers
# Inspired by the patterns used in dotfiles/lib/common.sh, intentionally kept
# self-contained so the one-shot has no dependency on the dotfiles repository.
# ---------------------------------------------------------------------------

msg_info()    { printf '%b[INFO]%b %s\n' "$C_CYAN" "$C_RESET" "$*" >&2; }
msg_success() { printf '%b[OK]%b %s\n' "$C_GREEN" "$C_RESET" "$*" >&2; }
msg_warn()    { printf '%b[WARN]%b %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
msg_error()   { printf '%b[ERROR]%b %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
msg_exec()    { printf '%b[EXEC]%b %s\n' "$C_MAGENTA" "$C_RESET" "$*" >&2; }
msg_skip()    { printf '%b[SKIP]%b %s\n' "$C_DIM" "$C_RESET" "$*" >&2; }
msg_debug()   { [[ ${TTY_MODE:-0} -eq 1 ]] && printf '%b[DEBUG]%b %s\n' "$C_DIM" "$C_RESET" "$*" >&2 || true; }

die() {
    msg_error "$*"
    exit 1
}

ensure_dir() {
    local dir="$1"
    [[ -d "$dir" ]] || mkdir -p -- "$dir" || die "Failed to create directory: $dir"
}

require_commands() {
    local cmd
    local -a missing=()
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
    done
    if ((${#missing[@]})); then
        msg_error "Missing required commands: ${missing[*]}"
        return 1
    fi
}

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
  sudo bash $0 --status        compact current-state + AD health report
  sudo bash $0 --no-color      disable ANSI colors
  sudo bash $0 --help

Remote one-shot:
  curl -fsSL <RAW_URL> | sudo bash -s -- --bootstrap

Notes:
  - Operational modes require root; local executions auto-escalate through sudo when possible.
  - Interactive modes require a controlling TTY.
  - This script never reprovisions an existing AD database.
  - Static network addressing is not changed automatically.
  - Single-NIC and dual-NIC servers are detected separately.
  - Hostname/FQDN + /etc/hosts are validated before Samba provisioning.
  - DNS resolver transitions are transactional and roll back on failure.
  - High-impact repairs require separate explicit confirmation.
  - 99.9% availability requires architecture (redundant DC/DNS, monitoring, backups), not only a script.
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
            --status) MODE="status" ;;
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

ensure_privileges() {
    # --help has already been handled by parse_args before this function runs.
    # All operational modes need root because the assistant writes protected
    # logs/state and may inspect privileged Samba/firewall information.
    if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
        if [[ -n "${SUDO_USER:-}" ]]; then
            INVOKING_ADMIN="$SUDO_USER"
        else
            INVOKING_ADMIN="root"
            msg_warn "Running from a root shell instead of sudo. Supported, but 'sudo bash ...' is preferred for operator traceability."
        fi
        return 0
    fi

    if ! command -v sudo >/dev/null 2>&1; then
        die "Root privileges are required and sudo is not installed. Run from a root shell or install sudo."
    fi

    # Local script: make the comfortable path automatic.
    if [[ -f "$0" && -r "$0" && "$0" != */bash && "$0" != "bash" ]]; then
        msg_info "Root privileges required; re-executing through sudo."
        exec sudo -- env \
            SSH_CONNECTION="${SSH_CONNECTION:-}" \
            SSH_CLIENT="${SSH_CLIENT:-}" \
            TERM="${TERM:-dumb}" \
            NO_COLOR="${NO_COLOR:-}" \
            bash "$0" "$@"
    fi

    # Piped stdin cannot be replayed safely after privilege escalation.
    die "This invocation is not root. For a one-shot pipe use: curl -fsSL <RAW_URL> | sudo bash -s -- <mode>"
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
        if [[ -n "${SSH_CONNECTION:-}" ]]; then
            SSH_LOCAL_IP="$(awk '{print $3}' <<<"$SSH_CONNECTION")"
        fi
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
    if [[ ${DNS_TRANSACTION_ACTIVE:-0} -eq 1 ]]; then
        rollback_dns_transaction "process exit before DNS commit" || true
    fi
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

is_valid_dns_hostname_label() {
    local label="$1"
    [[ ${#label} -ge 1 && ${#label} -le 63 ]] || return 1
    [[ "$label" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]]
}

is_valid_ad_dc_hostname() {
    # Keep the DC computer name within the classic 15-character NetBIOS limit
    # for widest Windows/Samba interoperability, while also enforcing DNS syntax.
    local label="$1"
    is_valid_dns_hostname_label "$label" || return 1
    [[ ${#label} -le 15 ]]
}

refresh_canonical_identity() {
    # There is one source of truth for the DNS identity. DC_FQDN is derived;
    # never accept a stale independently stored FQDN during critical steps.
    DC_HOSTNAME="${DC_HOSTNAME,,}"
    DOMAIN="${DOMAIN,,}"
    REALM="${DOMAIN^^}"
    DC_FQDN="${DC_HOSTNAME}.${DOMAIN}"
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

discover_network_topology() {
    WAN_IFACE=""
    WAN_IP=""
    WAN_CIDR=""
    AD_IFACE=""
    AD_IP=""
    AD_CIDR=""
    MGMT_IFACE=""
    DEFAULT_GW=""

    local default_line
    default_line="$(ip -4 route show default 2>/dev/null | awk '{m=0; for(i=1;i<=NF;i++) if($i=="metric") m=$(i+1); printf "%010d %s\n", m, $0}' | sort -n | sed 's/^[0-9][0-9]* //' | head -n1 || true)"
    WAN_IFACE="$(awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}' <<<"$default_line")"
    DEFAULT_GW="$(awk '{for(i=1;i<=NF;i++) if($i=="via"){print $(i+1); exit}}' <<<"$default_line")"

    if [[ -n "$WAN_IFACE" ]]; then
        WAN_CIDR="$(ip -4 -o addr show dev "$WAN_IFACE" scope global 2>/dev/null | awk 'NR==1{print $4}' || true)"
        WAN_IP="${WAN_CIDR%%/*}"
    fi

    local -a global_ifaces=()
    mapfile -t global_ifaces < <(ip -4 -o addr show scope global 2>/dev/null | awk '{print $2}' | sort -u)

    if [[ ${#global_ifaces[@]} -eq 0 ]]; then
        NETWORK_MODE="no-ipv4"
        return 0
    elif [[ ${#global_ifaces[@]} -eq 1 ]]; then
        NETWORK_MODE="single-nic"
        AD_IFACE="${global_ifaces[0]}"
    else
        NETWORK_MODE="dual-or-multihomed"
        local candidate="" iface
        for iface in "${global_ifaces[@]}"; do
            if [[ "$iface" != "$WAN_IFACE" ]]; then
                candidate="$iface"
                break
            fi
        done
        AD_IFACE="${candidate:-$WAN_IFACE}"
    fi

    AD_CIDR="$(ip -4 -o addr show dev "$AD_IFACE" scope global 2>/dev/null | awk 'NR==1{print $4}' || true)"
    AD_IP="${AD_CIDR%%/*}"

    if [[ $REMOTE_SESSION -eq 1 && -n "$SSH_LOCAL_IP" ]]; then
        MGMT_IFACE="$(ip -4 route get "$SSH_CLIENT_IP" from "$SSH_LOCAL_IP" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}' || true)"
        [[ -n "$MGMT_IFACE" ]] || MGMT_IFACE="$(ip -4 -o addr show | awk -v ip="$SSH_LOCAL_IP" '$4 ~ "^"ip"/" {print $2; exit}')"
    fi
    [[ -n "$MGMT_IFACE" ]] || MGMT_IFACE="${WAN_IFACE:-$AD_IFACE}"

    # Compatibility aliases used by older helpers.
    PRIMARY_IFACE="$AD_IFACE"
    PRIMARY_CIDR="$AD_CIDR"
    PRIMARY_IP="$AD_IP"
}

show_network_topology() {
    section "NETWORK TOPOLOGY"
    printf 'Detected mode : %s
' "$NETWORK_MODE"
    printf 'WAN/default   : %-12s %-18s gateway=%s
' "${WAN_IFACE:-none}" "${WAN_CIDR:-none}" "${DEFAULT_GW:-none}"
    printf 'AD candidate  : %-12s %-18s
' "${AD_IFACE:-none}" "${AD_CIDR:-none}"
    printf 'Management    : %-12s local-ip=%s client=%s
' "${MGMT_IFACE:-none}" "${SSH_LOCAL_IP:-n/a}" "${SSH_CLIENT_IP:-n/a}"

    local iface
    while read -r iface; do
        [[ -n "$iface" ]] || continue
        printf '  %-12s IPv4=%-20s IPv6=%s
' \
            "$iface" \
            "$(ip -4 -o addr show dev "$iface" scope global 2>/dev/null | awk '{print $4}' | paste -sd, -)" \
            "$(ip -6 -o addr show dev "$iface" scope global 2>/dev/null | awk '{print $4}' | paste -sd, -)"
    done < <(ip -o link show | awk -F': ' '{print $2}' | cut -d@ -f1)
}

choose_ad_interface() {
    discover_network_topology
    show_network_topology

    local -a candidates=()
    mapfile -t candidates < <(ip -4 -o addr show scope global 2>/dev/null | awk '{print $2}' | sort -u)
    ((${#candidates[@]})) || { fail_msg "No global IPv4 interface detected."; return 1; }

    if ((${#candidates[@]} > 1)); then
        local chosen
        chosen="$(ask 'Interface dedicated/preferred for Active Directory' "$AD_IFACE")"
        if ! ip link show dev "$chosen" >/dev/null 2>&1; then
            fail_msg "Interface '$chosen' does not exist."
            return 1
        fi
        AD_IFACE="$chosen"
        AD_CIDR="$(ip -4 -o addr show dev "$AD_IFACE" scope global 2>/dev/null | awk 'NR==1{print $4}' || true)"
        AD_IP="${AD_CIDR%%/*}"
        PRIMARY_IFACE="$AD_IFACE"; PRIMARY_CIDR="$AD_CIDR"; PRIMARY_IP="$AD_IP"
    fi

    if [[ "$NETWORK_MODE" != "single-nic" && "$AD_IFACE" == "$WAN_IFACE" ]]; then
        warn_msg "AD and WAN/default-route interfaces are the same despite a multihomed host. Review topology before production."
    fi

    if [[ "$NETWORK_MODE" != "single-nic" ]] && ip -4 route show default dev "$AD_IFACE" 2>/dev/null | grep -q '^default'; then
        warn_msg "AD interface $AD_IFACE has a default route. In a typical dual-NIC DC, keep the default gateway only on the WAN/management interface."
    fi
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

    choose_ad_interface

    DC_HOSTNAME="$(ask 'Short DNS hostname for the DC (letters, numbers, hyphen)' "${DC_HOSTNAME:-dc01}")"
    DC_HOSTNAME="${DC_HOSTNAME,,}"
    DOMAIN="$(ask 'AD DNS domain' "${DOMAIN:-example.internal}")"
    DOMAIN="${DOMAIN,,}"

    if ! is_valid_ad_dc_hostname "$DC_HOSTNAME"; then
        fail_msg "Invalid AD DC hostname: '$DC_HOSTNAME'. Use 1-15 letters/numbers/hyphens; no underscores and no leading/trailing hyphen."
        return 1
    fi
    is_valid_dns_name "$DOMAIN" || { fail_msg "Invalid DNS domain: $DOMAIN"; return 1; }

    refresh_canonical_identity

    DC_IP="$(ask 'DC IPv4 address (must already exist on AD interface)' "${DC_IP:-${AD_IP:-192.168.56.10}}")"
    NETBIOS_DOMAIN="$(ask 'NetBIOS domain' "${NETBIOS_DOMAIN:-$(netbios_from_domain "$DOMAIN")}")"
    NETBIOS_DOMAIN="${NETBIOS_DOMAIN^^}"
    # The DC NetBIOS/computer name is derived from the same canonical hostname.
    # Keeping a second independently editable host identity caused DNS/TLS drift.
    DC_NETBIOS="${DC_HOSTNAME^^}"

    is_valid_ipv4 "$DC_IP" || { fail_msg "Invalid IPv4: $DC_IP"; return 1; }
    is_valid_netbios "$NETBIOS_DOMAIN" || { fail_msg "Invalid NetBIOS domain: $NETBIOS_DOMAIN"; return 1; }
    is_valid_netbios "$DC_NETBIOS" || { fail_msg "Derived NetBIOS DC name is invalid: $DC_NETBIOS"; return 1; }

    local first_label="${DOMAIN%%.*}"
    if [[ "${first_label,,}" == "${DC_HOSTNAME,,}" ]]; then
        warn_msg "Hostname '$DC_HOSTNAME' equals the first DNS label of '$DOMAIN'; resulting FQDN is '$DC_FQDN'. Prefer a distinct DC hostname such as dc01."
    fi

    if ! ip -4 addr show dev "$AD_IFACE" | grep -Fq " ${DC_IP}/"; then
        fail_msg "DC IP $DC_IP is not assigned to selected AD interface $AD_IFACE."
        fail_msg "Configure an address first; the assistant deliberately does not change the live network remotely."
        return 1
    fi

    AD_CIDR="$(ip -4 -o addr show dev "$AD_IFACE" scope global | awk -v ip="$DC_IP" '$4 ~ "^"ip"/" {print $4; exit}')"
    [[ -n "$AD_CIDR" ]] || AD_CIDR="$(ip -4 -o addr show dev "$AD_IFACE" scope global | awk 'NR==1{print $4}')"
    AD_IP="$DC_IP"
    PRIMARY_IFACE="$AD_IFACE"; PRIMARY_CIDR="$AD_CIDR"; PRIMARY_IP="$DC_IP"

    result INFO "Network model" "$NETWORK_MODE" "known"
    result INFO "WAN interface" "${WAN_IFACE:-none} ${WAN_CIDR:-}" "default route / Internet"
    result INFO "AD interface" "$AD_IFACE $AD_CIDR" "AD client network"
    result INFO "DC hostname" "$DC_HOSTNAME" "valid DNS label"
    result INFO "DC FQDN" "$DC_FQDN" "derived from hostname + domain"
    result INFO "DC IP" "$DC_IP" "stable/static before production"
}

collect_network_policy() {
    step "Network policy inputs"

    local route_cidr="${AD_CIDR:-${PRIMARY_CIDR:-192.168.56.10/24}}"
    local default_net="192.168.56.0/24"
    if command_exists python3 && [[ -n "$route_cidr" ]]; then
        default_net="$(python3 - "$route_cidr" <<'PYNET'
import ipaddress, sys
try:
    print(ipaddress.ip_interface(sys.argv[1]).network)
except Exception:
    print("192.168.56.0/24")
PYNET
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

    result INFO "AD clients" "$AD_CLIENT_CIDR via $AD_IFACE" "restricted source/interface"
    result INFO "SSH source" "$SSH_SOURCE via ${MGMT_IFACE:-any}" "preserve admin access"
}


validate_local_identity_preflight() {
    refresh_canonical_identity

    local short fqdn
    short="$(hostname -s 2>/dev/null || true)"
    fqdn="$(hostname -f 2>/dev/null || true)"

    if [[ "${short,,}" != "$DC_HOSTNAME" ]]; then
        fail_msg "Hostname preflight failed: hostname -s='$short', expected '$DC_HOSTNAME'."
        return 1
    fi
    if [[ "${fqdn,,}" != "$DC_FQDN" ]]; then
        fail_msg "FQDN preflight failed: hostname -f='$fqdn', expected '$DC_FQDN'."
        return 1
    fi
    if ! getent ahostsv4 "$DC_FQDN" 2>/dev/null | awk '{print $1}' | grep -Fxq "$DC_IP"; then
        fail_msg "Local name preflight failed: $DC_FQDN does not resolve locally to $DC_IP."
        return 1
    fi

    result PASS "Local hostname" "$short" "$DC_HOSTNAME"
    result PASS "Local FQDN" "$fqdn" "$DC_FQDN"
    result PASS "Local hosts resolution" "$DC_FQDN -> $DC_IP" "correct before provisioning"
}

rewrite_hosts_for_dc() {
    refresh_canonical_identity
    require_cmd python3 "safe /etc/hosts editing" || return 1

    local tmp="${RUN_ROOT}/hosts.new"
    python3 - "$DC_IP" "$DC_FQDN" "$DC_HOSTNAME" /etc/hosts "$tmp" <<'PYHOSTS'
from pathlib import Path
import ipaddress, sys

ip, fqdn, short, src, dst = sys.argv[1:]
srcp, dstp = Path(src), Path(dst)
begin = '# BEGIN DEBIAN-AD-ASSISTANT'
end = '# END DEBIAN-AD-ASSISTANT'
targets = {fqdn.lower(), short.lower()}

lines = srcp.read_text(encoding='utf-8', errors='replace').splitlines()
out = []
skip = False
for raw in lines:
    stripped = raw.strip()
    if stripped == begin:
        skip = True
        continue
    if stripped == end:
        skip = False
        continue
    if skip:
        continue
    if not stripped or stripped.startswith('#'):
        out.append(raw)
        continue

    body, sep, comment = raw.partition('#')
    fields = body.split()
    if len(fields) >= 2:
        try:
            ipaddress.ip_address(fields[0])
        except ValueError:
            out.append(raw)
            continue
        aliases = [x for x in fields[1:] if x.lower() not in targets]
        if aliases:
            rebuilt = fields[0] + '\t' + ' '.join(aliases)
            if sep:
                rebuilt += '  # ' + comment.strip()
            out.append(rebuilt)
        # If the only aliases were our DC names, drop the stale mapping.
        continue
    out.append(raw)

while out and not out[-1].strip():
    out.pop()
out.extend([
    '',
    begin,
    f'{ip}\t{fqdn} {short}',
    end,
    '',
])
dstp.write_text('\n'.join(out), encoding='utf-8')
PYHOSTS
    chmod 644 "$tmp"
    chown root:root "$tmp"
    mv -f -- "$tmp" /etc/hosts
}

configure_hostname_hosts() {
    step "Hostname / FQDN / hosts preflight"
    refresh_canonical_identity

    if ! is_valid_ad_dc_hostname "$DC_HOSTNAME"; then
        fail_msg "Refusing hostname '$DC_HOSTNAME': AD DC hostname must be DNS-safe and <=15 characters for broad NetBIOS compatibility."
        return 1
    fi

    local previous_hostname
    previous_hostname="$(hostname -s 2>/dev/null || hostname)"

    backup_file /etc/hostname
    backup_file /etc/hosts

    if [[ "${previous_hostname,,}" != "$DC_HOSTNAME" ]]; then
        msg_exec "hostnamectl set-hostname $DC_HOSTNAME"
        hostnamectl set-hostname "$DC_HOSTNAME"
        change APPLIED "hostname=$DC_HOSTNAME"
    fi

    rewrite_hosts_for_dc

    if ! validate_local_identity_preflight; then
        msg_warn "Identity validation failed; restoring /etc/hosts and previous hostname."
        local hosts_backup="${BACKUP_DIR}/rootfs/etc/hosts"
        if [[ -e "$hosts_backup" || -L "$hosts_backup" ]]; then
            rm -f /etc/hosts
            cp -a -- "$hosts_backup" /etc/hosts
        fi
        if [[ -n "$previous_hostname" ]]; then
            hostnamectl set-hostname "$previous_hostname" >/dev/null 2>&1 || true
        fi
        return 1
    fi

    change APPLIED "/etc/hosts canonical DC mapping: $DC_IP $DC_FQDN $DC_HOSTNAME"
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

detect_address_method() {
    AD_ADDRESS_METHOD="unknown"
    if command_exists netplan; then
        local value
        value="$(netplan get "ethernets.${AD_IFACE}.dhcp4" 2>/dev/null | tr -d '[:space:]' || true)"
        case "$value" in
            true) AD_ADDRESS_METHOD="dhcp" ;;
            false) AD_ADDRESS_METHOD="static-or-manual" ;;
        esac
    fi
    if [[ "$AD_ADDRESS_METHOD" == "unknown" ]] && command_exists nmcli; then
        local conn method
        conn="$(nmcli -g GENERAL.CONNECTION dev show "$AD_IFACE" 2>/dev/null || true)"
        if [[ -n "$conn" && "$conn" != "--" ]]; then
            method="$(nmcli -g ipv4.method con show "$conn" 2>/dev/null || true)"
            case "$method" in
                auto) AD_ADDRESS_METHOD="dhcp" ;;
                manual) AD_ADDRESS_METHOD="static-or-manual" ;;
            esac
        fi
    fi
    printf '%s' "$AD_ADDRESS_METHOD"
}

set_smb_global_option() {
    local key="$1" value="$2"
    require_cmd python3 "safe smb.conf editing" || return 1
    python3 - "$key" "$value" <<'PYSMB'
from pathlib import Path
import re, sys
p=Path('/etc/samba/smb.conf')
key, value=sys.argv[1], sys.argv[2]
text=p.read_text(encoding='utf-8')
rx=re.compile(r'(?mi)^[ \t]*'+re.escape(key)+r'[ \t]*=.*$')
line=f'\t{key} = {value}'
if rx.search(text):
    text=rx.sub(line,text,count=1)
else:
    text=re.sub(r'(?mi)^\[global\][ \t]*$',lambda m:m.group(0)+'\n'+line,text,count=1)
p.write_text(text,encoding='utf-8')
PYSMB
}

configure_samba_interface_scope() {
    [[ -f /etc/samba/smb.conf ]] || return 0
    if [[ "$NETWORK_MODE" == "single-nic" ]]; then
        result INFO "Samba interface scope" "all local interfaces (single NIC)" "reviewed"
        return 0
    fi

    printf '\nMultihomed server detected. AD services should normally not listen on the WAN/NAT interface.\n'
    printf 'Proposed Samba bind addresses: 127.0.0.1 %s\n' "$DC_IP"
    printf 'This also avoids Samba binding AD/Kerberos listeners to unrelated IPv6 addresses.\n'
    if confirm "Restrict Samba services to loopback + AD IPv4 ($DC_IP)?" Y; then
        backup_file /etc/samba/smb.conf
        set_smb_global_option "interfaces" "127.0.0.1 ${DC_IP}"
        set_smb_global_option "bind interfaces only" "yes"
        testparm -s >/dev/null
        SAMBA_INTERFACE_SCOPED="yes"
        change APPLIED "Samba interfaces restricted to 127.0.0.1 ${DC_IP}"
        result PASS "Samba interface scope" "loopback + $DC_IP" "WAN excluded"
    else
        SAMBA_INTERFACE_SCOPED="no"
        warn_msg "Samba remains able to bind all host interfaces; review exposure and IPv6 bindings before production."
    fi
}

capture_resolver_state() {
    RESOLV_SNAPSHOT="${RUN_ROOT}/resolv.conf.before"
    rm -f "$RESOLV_SNAPSHOT"
    if [[ -e /etc/resolv.conf || -L /etc/resolv.conf ]]; then
        cp -a --no-dereference /etc/resolv.conf "$RESOLV_SNAPSHOT"
    fi
    systemctl is-active --quiet systemd-resolved 2>/dev/null && RESOLVED_WAS_ACTIVE=1 || RESOLVED_WAS_ACTIVE=0
    systemctl is-enabled --quiet systemd-resolved 2>/dev/null && RESOLVED_WAS_ENABLED=1 || RESOLVED_WAS_ENABLED=0
}

restore_resolv_snapshot() {
    rm -f /etc/resolv.conf
    if [[ -e "$RESOLV_SNAPSHOT" || -L "$RESOLV_SNAPSHOT" ]]; then
        cp -a --no-dereference "$RESOLV_SNAPSHOT" /etc/resolv.conf
    fi
}

rollback_dns_transaction() {
    local reason="${1:-DNS transaction failed}"
    log WARN "DNS rollback: $reason"
    restore_resolv_snapshot || true
    if [[ $RESOLVED_WAS_ENABLED -eq 1 ]]; then
        systemctl enable systemd-resolved >/dev/null 2>&1 || true
    fi
    if [[ $RESOLVED_WAS_ACTIVE -eq 1 ]]; then
        systemctl start systemd-resolved >/dev/null 2>&1 || true
    fi
    DNS_TRANSACTION_ACTIVE=0
    change APPLIED "DNS resolver rollback completed"
}

write_external_resolver() {
    local ns="$1" tmp="${RUN_ROOT}/resolv.external"
    printf 'nameserver %s\noptions timeout:2 attempts:2\n' "$ns" >"$tmp"
    chmod 644 "$tmp"
    rm -f /etc/resolv.conf
    cp "$tmp" /etc/resolv.conf
    chmod 644 /etc/resolv.conf
}

prepare_dns_transaction() {
    step "Prepare DNS transition"
    require_cmd dig "DNS preflight" || return 1

    capture_resolver_state
    DNS_TRANSACTION_ACTIVE=1

    [[ -n "$DNS_FORWARDER" ]] || DNS_FORWARDER="$(detect_dns_forwarder)"
    DNS_FORWARDER="$(ask 'Upstream DNS forwarder for external names' "${DNS_FORWARDER:-1.1.1.1}")"
    is_valid_ipv4 "$DNS_FORWARDER" || { fail_msg "Invalid DNS forwarder: $DNS_FORWARDER"; return 1; }

    if ! dig +time=3 +tries=1 @"$DNS_FORWARDER" raw.githubusercontent.com A >/dev/null 2>&1; then
        fail_msg "Upstream resolver $DNS_FORWARDER cannot resolve external names. No resolver changes were committed."
        return 1
    fi
    UPSTREAM_RESOLVER="$DNS_FORWARDER"
    result PASS "Upstream DNS" "$DNS_FORWARDER resolves external names" "reachable"

    # Free port 53 while preserving external DNS through a temporary static resolver.
    if [[ $RESOLVED_WAS_ACTIVE -eq 1 ]]; then
        systemctl stop systemd-resolved
        change APPLIED "systemd-resolved stopped temporarily for Samba DNS"
    fi
    write_external_resolver "$DNS_FORWARDER"

    if ! getent ahostsv4 raw.githubusercontent.com >/dev/null 2>&1; then
        fail_msg "External resolution failed after temporary resolver transition."
        return 1
    fi
    result PASS "Temporary resolver" "$DNS_FORWARDER" "external DNS preserved"
}

wait_for_samba() {
    local i listeners
    for i in {1..20}; do
        if systemctl is-active --quiet samba-ad-dc; then
            listeners="$(ss -lntup 2>/dev/null || true)"
            if grep -Eq ':53([[:space:]]|$)' <<<"$listeners" && \
               grep -Eq ':88([[:space:]]|$)' <<<"$listeners" && \
               grep -Eq ':389([[:space:]]|$)' <<<"$listeners" && \
               grep -Eq ':445([[:space:]]|$)' <<<"$listeners"; then
                return 0
            fi
        fi
        sleep 1
    done
    return 1
}


commit_samba_dns_resolver() {
    step "Start Samba DNS / commit resolver"
    refresh_canonical_identity
    validate_local_identity_preflight || {
        fail_msg "Refusing to start Samba with an inconsistent local hostname/FQDN."
        return 1
    }
    require_cmd testparm "Samba configuration validation" || return 1
    require_cmd dig "DNS validation" || return 1

    backup_file /etc/samba/smb.conf
    set_smb_global_option "dns forwarder" "$DNS_FORWARDER"
    testparm -s >/dev/null

    systemctl restart samba-ad-dc || {
        journalctl -u samba-ad-dc -b --no-pager -n 80 >"${RUN_ROOT}/samba-start-failure.log" 2>&1 || true
        fail_msg "samba-ad-dc failed to start; resolver will be rolled back. See ${RUN_ROOT}/samba-start-failure.log"
        return 1
    }
    if ! wait_for_samba; then
        journalctl -u samba-ad-dc -b --no-pager -n 80 >"${RUN_ROOT}/samba-health-failure.log" 2>&1 || true
        fail_msg "Samba listeners did not become healthy; resolver will be rolled back."
        return 1
    fi

    if ! dig +time=3 +tries=1 @127.0.0.1 "$DC_FQDN" A +short | grep -Fxq "$DC_IP"; then
        fail_msg "Samba DNS does not resolve $DC_FQDN to $DC_IP. Resolver will be rolled back."
        return 1
    fi
    result PASS "Samba authoritative DNS" "$DC_FQDN -> $DC_IP" "correct"

    if ! dig +time=4 +tries=1 @127.0.0.1 raw.githubusercontent.com A +short | grep -Eq '^[0-9]'; then
        fail_msg "Samba DNS forwarding to $DNS_FORWARDER is not working. Resolver will be rolled back."
        return 1
    fi
    result PASS "Samba DNS forwarding" "external resolution works" "$DNS_FORWARDER"

    local tmp="${RUN_ROOT}/resolv.local-samba"
    printf 'nameserver 127.0.0.1\nsearch %s\noptions timeout:2 attempts:2\n' "$DOMAIN" >"$tmp"
    chmod 644 "$tmp"
    rm -f /etc/resolv.conf
    cp "$tmp" /etc/resolv.conf
    chmod 644 /etc/resolv.conf

    if ! getent ahostsv4 raw.githubusercontent.com >/dev/null 2>&1 || ! getent ahostsv4 "$DC_FQDN" >/dev/null 2>&1; then
        fail_msg "Host resolver verification failed after switching to Samba DNS."
        return 1
    fi

    # Keep resolved disabled after a successful Samba DNS transition so it does not reclaim port 53.
    systemctl disable systemd-resolved >/dev/null 2>&1 || true

    [[ -f /var/lib/samba/private/krb5.conf ]] || { fail_msg "Missing Samba-generated krb5.conf"; return 1; }
    backup_file /etc/krb5.conf
    cp -f /var/lib/samba/private/krb5.conf /etc/krb5.conf
    chmod 644 /etc/krb5.conf

    DNS_TRANSACTION_ACTIVE=0
    change APPLIED "Host resolver committed to Samba DNS 127.0.0.1"
    result PASS "Host resolver" "127.0.0.1 search $DOMAIN" "Samba DNS"
}

repair_dns_stack() {
    set_progress_plan 2
    prepare_dns_transaction
    configure_samba_interface_scope
    if ! commit_samba_dns_resolver; then
        rollback_dns_transaction "DNS/Samba repair failed"
        return 1
    fi
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

verify_provisioned_identity() {
    refresh_canonical_identity
    local actual_realm actual_workgroup actual_netbios
    actual_realm="$(testparm -s --parameter-name=realm 2>/dev/null | tr -d '\r' || true)"
    actual_workgroup="$(testparm -s --parameter-name=workgroup 2>/dev/null | tr -d '\r' || true)"
    actual_netbios="$(testparm -s --parameter-name='netbios name' 2>/dev/null | tr -d '\r' || true)"

    [[ "${actual_realm^^}" == "$REALM" ]] || { fail_msg "Provisioned realm mismatch: '$actual_realm' != '$REALM'."; return 1; }
    [[ "${actual_workgroup^^}" == "$NETBIOS_DOMAIN" ]] || { fail_msg "Provisioned workgroup mismatch: '$actual_workgroup' != '$NETBIOS_DOMAIN'."; return 1; }
    [[ "${actual_netbios^^}" == "$DC_NETBIOS" ]] || { fail_msg "Provisioned NetBIOS host mismatch: '$actual_netbios' != '$DC_NETBIOS'."; return 1; }
    validate_local_identity_preflight
}

provision_new_domain() {
    step "Provision Samba AD/DC"
    refresh_canonical_identity

    if [[ -f /var/lib/samba/private/sam.ldb ]]; then
        fail_msg "Existing sam.ldb detected. Reprovision is prohibited."
        return 1
    fi

    # Hard gate: Samba must never see a hostname identity different from the
    # one that subsequent DNS/TLS health checks will use.
    validate_local_identity_preflight || {
        fail_msg "AD provisioning aborted before any directory database was created."
        return 1
    }

    if [[ -f /etc/samba/smb.conf ]]; then
        backup_file /etc/samba/smb.conf
        mv /etc/samba/smb.conf "${BACKUP_DIR}/smb.conf.pre-provision"
    fi

    printf '\nSamba will request the initial Administrator password directly.\n'

    local provision_help
    local -a identity_args=()
    provision_help="$(samba-tool domain provision --help 2>&1 || true)"
    if grep -q -- '--host-name' <<<"$provision_help"; then
        identity_args+=("--host-name=$DC_HOSTNAME")
    else
        warn_msg "Installed samba-tool does not advertise --host-name; relying on the validated system hostname '$DC_HOSTNAME'."
    fi
    if grep -q -- '--host-ip' <<<"$provision_help"; then
        identity_args+=("--host-ip=$DC_IP")
    else
        warn_msg "Installed samba-tool does not advertise --host-ip; relying on interface discovery for $DC_IP."
    fi

    msg_exec "Provisioning AD realm=$REALM domain=$NETBIOS_DOMAIN host=$DC_HOSTNAME ip=$DC_IP"
    samba-tool domain provision \
        --domain="$NETBIOS_DOMAIN" \
        --realm="$REALM" \
        --server-role=dc \
        --use-rfc2307 \
        --dns-backend=SAMBA_INTERNAL \
        "${identity_args[@]}" <"$INPUT_FD"

    configure_samba_interface_scope
    verify_provisioned_identity || {
        fail_msg "Samba was provisioned but its generated identity does not match the requested identity. Do not continue automatically."
        return 1
    }
    result PASS "Domain provision" "$DOMAIN" "database created; identity verified; service pending DNS health checks"
}

detect_dns_forwarder() {
    local candidates="" existing=""
    if [[ -f /etc/samba/smb.conf ]] && command_exists testparm; then
        existing="$(testparm -s --parameter-name='dns forwarder' 2>/dev/null | awk 'NF{print $1; exit}' || true)"
        if is_valid_ipv4 "$existing" && [[ "$existing" != "127.0.0.1" && "$existing" != "127.0.0.53" ]]; then
            printf '%s' "$existing"
            return 0
        fi
    fi
    if command_exists resolvectl && systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        candidates="$(resolvectl dns 2>/dev/null | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' || true)"
    else
        candidates="$(awk '/^[[:space:]]*nameserver[[:space:]]+/{print $2}' /etc/resolv.conf 2>/dev/null || true)"
    fi
    printf '%s
' "$candidates" | grep -Ev '^(127\.0\.0\.1|127\.0\.0\.53)$' | head -n1 || true
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
    # Compatibility wrapper used by manage mode.
    repair_dns_stack
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

    printf 'Firewall plan:
'
    printf '  AD services : interface=%s source=%s destination=%s
' "$AD_IFACE" "$AD_CLIENT_CIDR" "$DC_IP"
    printf '  SSH admin   : interface=%s source=%s destination=%s
' "${MGMT_IFACE:-any}" "$SSH_SOURCE" "${SSH_LOCAL_IP:-any-local-address}"

    if [[ $REMOTE_SESSION -eq 1 ]]; then
        warn_msg "Remote SSH session detected from ${SSH_CLIENT_IP:-unknown}; management access rule will be added before default-deny."
    fi
    confirm "Apply/update UFW policy?" Y || { result SKIP "UFW" "operator skipped" "unchanged"; return 0; }

    # Preserve management path first. Use the actual SSH-facing interface when known.
    if [[ -n "$MGMT_IFACE" ]]; then
        ufw allow in on "$MGMT_IFACE" from "$SSH_SOURCE" to any port 22 proto tcp >/dev/null
    else
        ufw allow from "$SSH_SOURCE" to any port 22 proto tcp >/dev/null
    fi

    ufw default deny incoming >/dev/null
    ufw default allow outgoing >/dev/null

    local p
    local tcp_ports=(53 88 135 139 389 445 464 3268)
    local udp_ports=(53 88 123 137 138 389 464)
    for p in "${tcp_ports[@]}"; do
        ufw allow in on "$AD_IFACE" from "$AD_CLIENT_CIDR" to "$DC_IP" port "$p" proto tcp >/dev/null
    done
    for p in "${udp_ports[@]}"; do
        ufw allow in on "$AD_IFACE" from "$AD_CLIENT_CIDR" to "$DC_IP" port "$p" proto udp >/dev/null
    done
    ufw allow in on "$AD_IFACE" from "$AD_CLIENT_CIDR" to "$DC_IP" port 49152:65535 proto tcp >/dev/null
    ufw --force enable >/dev/null

    result PASS "UFW" "$(ufw status | head -n1)" "active"
    result PASS "AD firewall scope" "$AD_IFACE / $AD_CLIENT_CIDR" "WAN not used for AD client rules"
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
    discover_network_topology
    [[ -n "$DC_IP" ]] || DC_IP="${AD_IP:-$PRIMARY_IP}"

    if systemctl is-active --quiet samba-ad-dc; then
        result PASS "samba-ad-dc" "active" "active"
    else
        result FAIL "samba-ad-dc" "inactive" "active"
        journalctl -u samba-ad-dc -b --no-pager -n 80 >"${RUN_ROOT}/samba-validation-journal.txt" 2>&1 || true
        fail=1
    fi

    if command_exists testparm; then
        testparm -s >/dev/null 2>&1 \
            && result PASS "smb.conf" "valid" "valid" \
            || { result FAIL "smb.conf" "invalid" "valid"; fail=1; }
    else
        result ERROR "testparm" "missing" "installed"; fail=1
    fi

    if command_exists ss; then
        local port
        for port in 53 88 389 445; do
            if ss -lntup 2>/dev/null | grep -Eq ":${port}([[:space:]]|$)"; then
                result PASS "Listener $port" "present" "present"
            else
                result FAIL "Listener $port" "missing" "present"; fail=1
            fi
        done
    fi

    if command_exists dig && [[ -n "$DOMAIN" && -n "$DC_FQDN" ]]; then
        if [[ -n "$DC_IP" ]] && dig +time=3 +tries=1 @127.0.0.1 +short A "$DC_FQDN" | grep -Fxq "$DC_IP"; then
            result PASS "DNS A" "$DC_FQDN -> $DC_IP" "correct"
        else
            result FAIL "DNS A" "unexpected/no answer" "$DC_FQDN -> $DC_IP"; fail=1
        fi

        local srv ans
        for srv in _ldap._tcp _kerberos._tcp _kerberos._udp _kpasswd._udp; do
            ans="$(dig +time=3 +tries=1 @127.0.0.1 +short SRV "${srv}.${DOMAIN}" 2>/dev/null | tr '
' ' ')"
            [[ -n "$ans" ]] && result PASS "SRV $srv" "$ans" "present" || { result FAIL "SRV $srv" "missing" "present"; fail=1; }
        done

        if dig +time=4 +tries=1 @127.0.0.1 raw.githubusercontent.com A +short | grep -Eq '^[0-9]'; then
            result PASS "DNS forwarding" "external names resolve through Samba" "working"
        else
            result FAIL "DNS forwarding" "failed" "working"; fail=1
        fi
    else
        result SKIP "DNS validation" "dig/domain data unavailable" "available"
    fi

    if getent ahostsv4 raw.githubusercontent.com >/dev/null 2>&1; then
        result PASS "Host resolver" "external resolution works" "working"
    else
        result FAIL "Host resolver" "external resolution failed" "working"; fail=1
    fi

    if command_exists samba-tool; then
        samba-tool domain info 127.0.0.1 >"${RUN_ROOT}/domain-info.txt" 2>&1 \
            && result PASS "Domain info" "reachable" "$DOMAIN" \
            || { result FAIL "Domain info" "failed" "reachable"; fail=1; }

        samba-tool dbcheck --cross-ncs >"${RUN_ROOT}/dbcheck.txt" 2>&1 \
            && result PASS "AD dbcheck" "completed" "clean/no fatal errors" \
            || result WARN "AD dbcheck" "reported issues" "review ${RUN_ROOT}/dbcheck.txt"

        samba-tool ntacl sysvolcheck >"${RUN_ROOT}/sysvolcheck.txt" 2>&1 \
            && result PASS "SYSVOL ACL" "consistent" "consistent" \
            || result WARN "SYSVOL ACL" "differences" "review ${RUN_ROOT}/sysvolcheck.txt"
    fi

    if systemctl is-failed --quiet systemd-networkd-wait-online.service 2>/dev/null; then
        result WARN "networkd-wait-online" "failed" "review required; must not block DC boot"
    else
        result INFO "networkd-wait-online" "not failed" "healthy boot dependency"
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
    discover_network_topology

    result INFO "OS" "$PRETTY_NAME_SAFE" "supported target"
    result INFO "Samba role" "$SAMBA_ROLE" "known"
    result INFO "Hostname" "$(hostname -f 2>/dev/null || hostname)" "FQDN"
    result INFO "Network model" "$NETWORK_MODE" "known"
    result INFO "WAN/default" "${WAN_IFACE:-none} ${WAN_CIDR:-} gw=${DEFAULT_GW:-none}" "Internet/default route"
    result INFO "AD candidate" "${AD_IFACE:-none} ${AD_CIDR:-}" "AD client network"
    result INFO "Management" "${MGMT_IFACE:-none} SSH=${SSH_CLIENT_IP:-local}" "preserved"
    result INFO "Remote session" "$([[ $REMOTE_SESSION -eq 1 ]] && echo yes || echo no)" "known"

    local u
    for u in samba-ad-dc smbd nmbd winbind chrony systemd-resolved NetworkManager systemd-networkd-wait-online; do
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

write_post_install_checklist() {
    step "Post-install checklist"
    detect_address_method >/dev/null

    local netplan_files=""
    if compgen -G '/etc/netplan/*.yaml' >/dev/null; then
        netplan_files="$(printf '%s ' /etc/netplan/*.yaml)"
    fi

    cat >"$POST_INSTALL_FILE" <<EOFPOST
${SCRIPT_NAME} ${SCRIPT_VERSION} - POST-INSTALL CHECKLIST
Generated: $(date -Is)

CURRENT TOPOLOGY
  Network mode : ${NETWORK_MODE}
  WAN interface: ${WAN_IFACE:-none} ${WAN_CIDR:-}
  AD interface : ${AD_IFACE:-none} ${AD_CIDR:-}
  DC address   : ${DC_IP}
  Domain       : ${DOMAIN}
  Realm        : ${REALM}
  Address mode : ${AD_ADDRESS_METHOD}
  Netplan files: ${netplan_files:-not detected}

[REQUIRED BEFORE PRODUCTION]
  [ ] Make the AD/DC address persistent/static on ${AD_IFACE}.
      Current target: ${DC_IP}${AD_CIDR:+/${AD_CIDR#*/}}
      Do NOT change networking blindly over SSH; use console/out-of-band access or 'netplan try'.
EOFPOST

    if [[ "$NETWORK_MODE" != "single-nic" ]]; then
        cat >>"$POST_INSTALL_FILE" <<EOFPOST
  [ ] Dual/multihomed host: keep the normal default gateway on ${WAN_IFACE:-the WAN interface}.
      The AD-only interface ${AD_IFACE} normally should not add another default gateway.
EOFPOST
    fi

    cat >>"$POST_INSTALL_FILE" <<EOFPOST
  [ ] Reboot once during the maintenance window, then verify persistence:
        ip -br addr
        ip route
        sudo bash ./debian-ad-assistant-v3.1.0-review.sh --validate

  [ ] Confirm the DC uses Samba DNS locally:
        cat /etc/resolv.conf
        dig @127.0.0.1 ${DC_FQDN}
        dig @127.0.0.1 raw.githubusercontent.com

  [ ] Configure domain clients to use ${DC_IP} as their AD DNS server.
      Do not place public DNS directly on AD clients as a fallback for the AD namespace.

[SECURITY]
  [ ] Verify UFW scope and management access from the expected admin network.
  [ ] Test the delegated/alternate administrative account before disabling built-in recovery accounts.
  [ ] Review GPO scope and security filtering before broad production deployment.
  [ ] Review CIS/vendor baseline findings; this assistant alone is not a CIS compliance certificate.

[BACKUP / RECOVERY]
  [ ] Create the first domain backup:
        sudo bash ./debian-ad-assistant-v3.1.0-review.sh --backup
  [ ] Copy verified backups OFF this DC and test a restore procedure in a lab.
  [ ] Keep VM snapshots as short-term maintenance aids, not as the only AD backup strategy.

[AVAILABILITY TARGET]
  [ ] A single DC is a single point of failure. For a real 99.9% service objective,
      deploy at least a second DC/DNS server on separate failure domains where feasible.
  [ ] Monitor at minimum: host reachability, disk, time sync, DNS :53, Kerberos :88,
      LDAP :389, SMB :445, samba-ad-dc state and backup freshness.
  [ ] Define maintenance windows, alerting and an off-host recovery path.

[CLIENT ACCEPTANCE TEST]
  [ ] Join a test client to ${DOMAIN}.
  [ ] Log in with a normal domain user.
  [ ] Validate DNS and Kerberos from the client.
  [ ] Apply/refresh policy and confirm expected GPO results.

READINESS
  Provisioned != production-ready. Complete the manual actions above and rerun --validate.
EOFPOST
    chmod 600 "$POST_INSTALL_FILE"

    printf '\n%b==============================================================================%b\n' "$C_CYAN" "$C_RESET"
    printf '%b POST-INSTALLATION CHECKLIST%b\n' "$C_CYAN" "$C_RESET"
    printf '%b==============================================================================%b\n' "$C_CYAN" "$C_RESET"
    printf 'AD interface : %s  %s\n' "$AD_IFACE" "$AD_CIDR"
    printf 'WAN interface: %s  %s  gateway=%s\n' "${WAN_IFACE:-none}" "${WAN_CIDR:-}" "${DEFAULT_GW:-none}"
    printf 'Address mode : %s\n' "$AD_ADDRESS_METHOD"
    printf '\nRequired next steps:\n'
    printf '  [ ] Make %s / %s persistent/static.\n' "$AD_IFACE" "$DC_IP"
    [[ "$NETWORK_MODE" != "single-nic" ]] && printf '  [ ] Keep the default gateway on the WAN interface only (normally %s).\n' "${WAN_IFACE:-review topology}"
    printf '  [ ] Reboot in a maintenance window and run --validate.\n'
    printf '  [ ] Create and export an off-host domain backup.\n'
    printf '  [ ] Join a test client and validate DNS/Kerberos/GPO.\n'
    printf '  [ ] For genuine 99.9%% AD availability, add a second DC/DNS plus monitoring.\n'
    printf '\nSaved checklist: %s\n' "$POST_INSTALL_FILE"
    result INFO "Production readiness" "READY WITH MANUAL ACTIONS" "complete POST-INSTALL checklist"
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
        printf 'Network mode: %s\n' "$NETWORK_MODE"
        printf 'WAN interface: %s %s gateway=%s\n' "$WAN_IFACE" "$WAN_CIDR" "$DEFAULT_GW"
        printf 'AD interface: %s %s\n' "$AD_IFACE" "$AD_CIDR"
        printf 'Samba interface scoped: %s\n' "$SAMBA_INTERFACE_SCOPED"
        printf 'Remote: %s\n' "$REMOTE_SESSION"
        printf 'Post-install checklist: %s\n' "$POST_INSTALL_FILE"
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
    [[ -f "$POST_INSTALL_FILE" ]] && printf 'Checklist: %s\n' "$POST_INSTALL_FILE"
    if (( fail > 0 )); then
        printf '%bReadiness: ATTENTION REQUIRED%b\n' "$C_RED" "$C_RESET"
    elif [[ "$MODE" == "bootstrap" || "$MODE" == "interactive" ]]; then
        printf '%bReadiness: READY WITH MANUAL ACTIONS%b\n' "$C_YELLOW" "$C_RESET"
    else
        printf '%bReadiness: HEALTH CHECK COMPLETE%b\n' "$C_GREEN" "$C_RESET"
    fi
}

bootstrap_mode() {
    detect_samba_role
    if [[ "$SAMBA_ROLE" != "none" ]]; then
        fail_msg "Existing Samba role/configuration detected ($SAMBA_ROLE). Bootstrap will not repurpose it automatically."
        fail_msg "Use --manage for an AD/DC, or plan an explicit Samba/member/file-server migration."
        return 2
    fi

    set_progress_plan 17
    audit_existing
    collect_identity
    snapshot_system
    install_required_packages
    collect_network_policy
    configure_hostname_hosts
    configure_samba_service_model

    # Critical ordering: preserve Internet DNS, free port 53, then provision/start Samba.
    prepare_dns_transaction
    configure_time
    provision_new_domain
    if ! commit_samba_dns_resolver; then
        rollback_dns_transaction "Samba DNS did not become healthy"
        return 1
    fi

    ensure_directory_baseline
    if [[ "$ENABLE_GPOS" == "yes" ]] && confirm "Create/link baseline GPOs?" Y; then
        manage_gpos
    else
        step "Group Policy"
        result SKIP "GPO" "operator disabled" "optional"
    fi

    # Firewall is intentionally late: services and management path are known first.
    configure_ufw
    validate_ad
    save_config
    write_post_install_checklist
}


manage_menu() {
    while true; do
        printf '\n%bManage existing AD/DC%b\n' "$C_CYAN" "$C_RESET"
        printf '  [1] Audit current state\n'
        printf '  [2] Validate AD/DC health\n'
        printf '  [3] Repair/reconfigure Samba DNS + local resolver/Kerberos (transactional)\n'
        printf '  [4] Configure Chrony\n'
        printf '  [5] Configure UFW\n'
        printf '  [6] Ensure directory baseline\n'
        printf '  [7] Create/update baseline GPOs\n'
        printf '  [8] Create domain backup\n'
        printf '  [9] Advanced SYSVOL ACL repair\n'
        printf '  [10] Show/regenerate post-install checklist\n'
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
            10) set_progress_plan 1; write_post_install_checklist ;;
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
    discover_network_topology
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
    discover_network_topology
    [[ "$SAMBA_ROLE" == "ad-dc" || "$SAMBA_ROLE" == "ad-dc-config" ]] || {
        fail_msg "No Samba AD/DC detected."
        return 2
    }
    load_config || true
    discover_existing_identity
    validate_ad
}

status_mode() {
    set_progress_plan 2
    audit_existing
    if [[ "$SAMBA_ROLE" == "ad-dc" || "$SAMBA_ROLE" == "ad-dc-config" ]]; then
        load_config || true
        discover_existing_identity
        validate_ad || true
    else
        step "AD/DC health"
        result SKIP "AD/DC" "not configured" "not applicable"
    fi
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
    detect_terminal
    ensure_privileges "$@"
    need_tty
    init_runtime
    banner

    detect_os
    discover_network_topology
    detect_samba_role

    case "$MODE" in
        audit) audit_mode ;;
        validate) validate_mode ;;
        bootstrap) bootstrap_mode ;;
        manage) manage_mode ;;
        backup) backup_mode ;;
        status) status_mode ;;
        interactive) interactive_mode ;;
        *) fail_msg "Unknown mode: $MODE"; return 2 ;;
    esac

    write_report
    summary
}

main "$@"
