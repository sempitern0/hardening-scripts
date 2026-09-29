#!/usr/bin/env bash
# DEBIAN AD Assistant
# Version 4.2.2-gpo-user-fix
#
# Self-contained Samba Active Directory Domain Controller assistant.
#
# Targets:
#   - Debian 13
#   - Ubuntu Server 26.04 LTS
#
# Principles:
#   - detect before modify
#   - never reprovision an existing sam.ldb
#   - persist bootstrap identity before provisioning
#   - backup files before sensitive changes
#   - require explicit confirmation for destructive operations
#   - use an isolated Kerberos credential cache
#   - keep Samba AD services restricted to trusted networks where possible
#   - install systemd drop-ins instead of editing vendor unit files
#   - remain usable as a single readable/editable Bash script
#
# Modes:
#   --audit          read-only inventory + security evidence
#   --validate       functional AD/DC health checks
#   --bootstrap      NEW AD/DC bootstrap or safe matching resume
#   --manage         existing AD/DC maintenance menu
#   --backup         online Samba domain backup
#   --status         compact inventory + AD health
#   --admin          operations console
#   --users          AD user menu
#   --groups         AD group menu
#   --computers      AD computer inventory/menu
#   --permissions    memberships + DS ACL menu
#   --gpo            GPO menu
#   --security       host/DC security menu
#   --install-cli    install adctl/ad-users/... terminal commands

set -Eeuo pipefail
IFS=$'\n\t'
umask 077

SCRIPT_NAME="DEBIAN AD Assistant"
SCRIPT_VERSION="4.2.2-gpo-user-fix"

MODE="interactive"
FORCE_NO_COLOR=0

STATE_DIR="/var/lib/debian-ad-assistant"
LOG_DIR="/var/log/debian-ad-assistant"
CONFIG_FILE="${STATE_DIR}/config.env"
GPO_DIR="${STATE_DIR}/gpo"
POST_INSTALL_FILE="${STATE_DIR}/POST-INSTALL.txt"

RUN_ROOT=""
LOG_FILE=""
REPORT_FILE=""
BACKUP_DIR=""
DOMAIN_BACKUP_DIR=""
TIMESTAMP=""
INPUT_FD="/dev/null"
TTY_MODE=0
REMOTE_SESSION=0
SSH_CLIENT_IP=""
SSH_LOCAL_IP=""
CURRENT_STEP=0
TOTAL_STEPS=1
LOCK_DIR=""

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
ADMIN_USER=""
INITIAL_AUTH_USER="Administrator"
ENABLE_UFW="yes"
ENABLE_GPOS="yes"

DISTRO_ID=""
DISTRO_LIKE=""
DISTRO_VERSION=""
PRETTY_NAME_SAFE="unknown"
SAMBA_ROLE="none"

NETWORK_MODE="unknown"
WAN_IFACE=""
WAN_IP=""
WAN_CIDR=""
DEFAULT_GW=""
AD_IFACE=""
AD_IP=""
AD_CIDR=""
MGMT_IFACE=""
PRIMARY_IFACE=""
PRIMARY_IP=""
PRIMARY_CIDR=""
AD_ADDRESS_METHOD="unknown"
SAMBA_INTERFACE_SCOPED="no"

DNS_TRANSACTION_ACTIVE=0
DNS_NEEDS_COMMIT=1
RESOLV_SNAPSHOT=""
RESOLVED_WAS_ACTIVE=0
RESOLVED_WAS_ENABLED=0
BOOTSTRAP_RESUME=0

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
C_BLUE=$'\033[34m'
C_WHITE=$'\033[97m'
C_BOLD=$'\033[1m'
C_DIM=$'\033[2m'

UI_RULE="────────────────────────────────────────────────────────────────────────────────────────"

command_exists() { command -v "$1" >/dev/null 2>&1; }


# ---------------------------------------------------------------------------
# Professional console UI
# ---------------------------------------------------------------------------

ui_clear() {
    [[ $TTY_MODE -eq 1 ]] && clear 2>/dev/null || true
}

ui_rule() {
    printf '%b%s%b\n' "$C_DIM" "$UI_RULE" "$C_RESET"
}

ui_brand_compact() {
    printf '%b%b DEBIAN AD CONTROL PLANE%b  %bv%s%b\n' \
        "$C_BOLD" "$C_CYAN" "$C_RESET" "$C_DIM" "$SCRIPT_VERSION" "$C_RESET"
}

ui_service_badge() {
    local unit="$1" state
    state="$(safe_systemctl_state "$unit")"
    case "$state" in
        active) printf '%bONLINE%b' "$C_GREEN" "$C_RESET" ;;
        activating) printf '%bSTARTING%b' "$C_YELLOW" "$C_RESET" ;;
        failed) printf '%bFAILED%b' "$C_RED" "$C_RESET" ;;
        *) printf '%b%s%b' "$C_YELLOW" "${state^^}" "$C_RESET" ;;
    esac
}

ui_enabled_badge() {
    local unit="$1" state
    state="$(safe_systemctl_enabled "$unit")"
    case "$state" in
        enabled) printf '%bENABLED%b' "$C_GREEN" "$C_RESET" ;;
        disabled) printf '%bDISABLED%b' "$C_RED" "$C_RESET" ;;
        *) printf '%b%s%b' "$C_YELLOW" "${state^^}" "$C_RESET" ;;
    esac
}

ui_firewall_badge() {
    local fw="unavailable"
    if command_exists ufw; then
        fw="$(ufw status 2>/dev/null | awk 'NR==1{print tolower($2)}' || true)"
    fi
    case "$fw" in
        active) printf '%bACTIVE%b' "$C_GREEN" "$C_RESET" ;;
        inactive) printf '%bINACTIVE%b' "$C_YELLOW" "$C_RESET" ;;
        *) printf '%bN/A%b' "$C_DIM" "$C_RESET" ;;
    esac
}

ui_context_panel() {
    local host domain dc ip iface admin session
    host="$(hostname -s 2>/dev/null || hostname)"
    domain="${DOMAIN:-unconfigured}"
    dc="${DC_FQDN:-$host}"
    ip="${DC_IP:-${AD_IP:-n/a}}"
    iface="${AD_IFACE:-n/a}"
    admin="${ADMIN_USER:-not-selected}"
    session="local"
    [[ $REMOTE_SESSION -eq 1 ]] && session="SSH ${SSH_CLIENT_IP:-unknown}"

    printf '  %-13s %b%-31s%b %-13s %s\n' \
        "Domain" "$C_WHITE" "$domain" "$C_RESET" "Role" "${SAMBA_ROLE:-unknown}"
    printf '  %-13s %-31s %-13s %s\n' \
        "Controller" "$dc" "Address" "$ip / $iface"
    printf '  %-13s %-31s %-13s %s\n' \
        "Admin" "$admin" "Session" "$session"
    printf '  %-13s %s / %s    %-13s %s\n' \
        "Samba" "$(ui_service_badge samba-ad-dc)" "$(ui_enabled_badge samba-ad-dc)" \
        "Firewall" "$(ui_firewall_badge)"
}

ui_menu_screen() {
    local title="$1" subtitle="${2:-}"
    ui_clear
    ui_brand_compact
    ui_rule
    ui_context_panel
    ui_rule
    printf '%b%b%s%b\n' "$C_BOLD" "$C_WHITE" "$title" "$C_RESET"
    [[ -n "$subtitle" ]] && printf '%b%s%b\n' "$C_DIM" "$subtitle" "$C_RESET"
    printf '\n'
}

ui_menu_item() {
    local key="$1" title="$2" description="$3" colour="${4:-$C_CYAN}"
    printf '  %b[%2s]%b  %b%-29s%b %b%s%b\n' \
        "$C_DIM" "$key" "$C_RESET" \
        "$colour" "$title" "$C_RESET" \
        "$C_DIM" "$description" "$C_RESET"
}

ui_menu_exit() {
    ui_menu_item "0" "Back / Exit" "Return to previous console" "$C_RED"
}

ui_pause() {
    [[ $TTY_MODE -eq 1 ]] || return 0
    printf '\n'
    ui_rule
    read -r -p "Press [ENTER] to continue..." _ <"$INPUT_FD" || true
}

msg_info()    { printf '%b[INFO]%b %s\n' "$C_CYAN" "$C_RESET" "$*" >&2; }
msg_success() { printf '%b[OK]%b %s\n' "$C_GREEN" "$C_RESET" "$*" >&2; }
msg_warn()    { printf '%b[WARN]%b %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
msg_error()   { printf '%b[ERROR]%b %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
msg_exec()    { printf '%b[EXEC]%b %s\n' "$C_MAGENTA" "$C_RESET" "$*" >&2; }

die() {
    msg_error "$*"
    exit 1
}

log() {
    local level="$1"; shift
    local line="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
    [[ -n "${LOG_FILE:-}" ]] && printf '%s\n' "$line" >>"$LOG_FILE"
    case "$level" in
        WARN) msg_warn "$*" ;;
        ERROR) msg_error "$*" ;;
        INFO) [[ $TTY_MODE -eq 1 ]] && msg_info "$*" || true ;;
        DEBUG) [[ $TTY_MODE -eq 1 && -n "${LOG_FILE:-}" ]] && printf '%s\n' "$line" >&2 || true ;;
    esac
}

warn_msg() {
    WARNINGS+=("$*")
    log WARN "$*"
}

fail_msg() {
    FAILURES+=("$*")
    log ERROR "$*"
}

change() {
    CHANGES+=("$1|${*:2}")
}

result() {
    local status="$1" name="$2" current="$3" expected="${4:-}"
    RESULTS+=("${status}|${name}|${current}|${expected}")
    case "$status" in
        PASS) printf '  %b[ OK ]%b  %-31s %s\n' "$C_GREEN" "$C_RESET" "$name" "$current" ;;
        WARN) printf '  %b[WARN]%b  %-31s %s\n' "$C_YELLOW" "$C_RESET" "$name" "$current" ;;
        FAIL|ERROR) printf '  %b[FAIL]%b  %-31s %s\n' "$C_RED" "$C_RESET" "$name" "$current" ;;
        SKIP) printf '  %b[SKIP]%b  %-31s %s\n' "$C_DIM" "$C_RESET" "$name" "$current" ;;
        *) printf '  %b[INFO]%b  %-31s %s\n' "$C_CYAN" "$C_RESET" "$name" "$current" ;;
    esac
}

section() {
    printf '\n'
    ui_rule
    printf '%b%b  %s%b\n' "$C_BOLD" "$C_WHITE" "$1" "$C_RESET"
    ui_rule
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
        (( filled > width )) && filled=$width
        printf '\n%b[%02d/%02d]%b %-30s [' "$C_CYAN" "$CURRENT_STEP" "$TOTAL_STEPS" "$C_RESET" "$title"
        printf '%*s' "$filled" '' | tr ' ' '#'
        printf '%*s' "$((width-filled))" '' | tr ' ' '-'
        printf ']\n'
    else
        printf '\n[%02d/%02d] %s\n' "$CURRENT_STEP" "$TOTAL_STEPS" "$title"
    fi
}

confirm() {
    local prompt="$1" default="${2:-N}" answer
    while true; do
        if [[ "$default" == "Y" ]]; then
            printf '%b?%b %s %b[Y/n]%b: ' "$C_CYAN" "$C_RESET" "$prompt" "$C_DIM" "$C_RESET" >&2
            read -r answer <"$INPUT_FD" || return 1
            answer="${answer:-Y}"
        else
            printf '%b?%b %s %b[y/N]%b: ' "$C_CYAN" "$C_RESET" "$prompt" "$C_DIM" "$C_RESET" >&2
            read -r answer <"$INPUT_FD" || return 1
            answer="${answer:-N}"
        fi
        case "${answer^^}" in
            Y|YES|S|SI|SÍ) return 0 ;;
            N|NO) return 1 ;;
        esac
        msg_warn "Please answer yes or no."
    done
}

confirm_high_risk() {
    local action="$1" answer
    printf '\n'
    ui_rule
    printf '%b%b  HIGH IMPACT OPERATION%b\n' "$C_BOLD" "$C_RED" "$C_RESET"
    printf '  %s\n' "$action"
    printf '  Type %bAPPLY%b to authorize: ' "$C_RED" "$C_RESET" >&2
    read -r answer <"$INPUT_FD" || return 1
    [[ "$answer" == "APPLY" ]]
}

ask() {
    local prompt="$1" default="${2:-}" answer
    if [[ -n "$default" ]]; then
        printf '%b›%b %s %b[%s]%b: ' "$C_CYAN" "$C_RESET" "$prompt" "$C_DIM" "$default" "$C_RESET" >&2
        read -r answer <"$INPUT_FD" || return 1
        printf '%s' "${answer:-$default}"
    else
        printf '%b›%b %s: ' "$C_CYAN" "$C_RESET" "$prompt" >&2
        read -r answer <"$INPUT_FD" || return 1
        printf '%s' "$answer"
    fi
}

usage() {
    cat <<EOF
${SCRIPT_NAME} v${SCRIPT_VERSION}

Usage:
  sudo bash $0
  sudo bash $0 --audit
  sudo bash $0 --validate
  sudo bash $0 --bootstrap
  sudo bash $0 --manage
  sudo bash $0 --backup
  sudo bash $0 --status
  sudo bash $0 --admin
  sudo bash $0 --users
  sudo bash $0 --groups
  sudo bash $0 --computers
  sudo bash $0 --permissions
  sudo bash $0 --gpo
  sudo bash $0 --security
  sudo bash $0 --install-cli
  sudo bash $0 --cli-info
  sudo bash $0 --no-color
  sudo bash $0 --help

Convenience commands installed by --install-cli:
  adctl, ad-users, ad-groups, ad-computers, ad-permissions,
  ad-gpo, ad-security, ad-audit, ad-validate, ad-status, ad-backup, ad-tools

Safety:
  - Existing sam.ldb is never reprovisioned.
  - Bootstrap state is persisted before domain provision.
  - Destructive AD operations require explicit confirmation.
  - Vendor systemd unit files are not edited directly.
EOF
}

detect_invocation_alias() {
    [[ "$MODE" == "interactive" ]] || return 0
    case "$(basename "$0")" in
        adctl) MODE="admin" ;;
        ad-users) MODE="users" ;;
        ad-groups) MODE="groups" ;;
        ad-computers) MODE="computers" ;;
        ad-permissions) MODE="permissions" ;;
        ad-gpo) MODE="gpo" ;;
        ad-security) MODE="security" ;;
        ad-audit) MODE="audit" ;;
        ad-validate) MODE="validate" ;;
        ad-backup) MODE="backup" ;;
        ad-status) MODE="status" ;;
        ad-tools) MODE="cli-info" ;;
    esac
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
            --admin|--ops) MODE="admin" ;;
            --users) MODE="users" ;;
            --groups) MODE="groups" ;;
            --computers) MODE="computers" ;;
            --permissions) MODE="permissions" ;;
            --gpo) MODE="gpo" ;;
            --security) MODE="security" ;;
            --install-cli) MODE="install-cli" ;;
            --cli-info|--tools) MODE="cli-info" ;;
            --no-color) FORCE_NO_COLOR=1 ;;
            --help|-h) usage; exit 0 ;;
            *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
        esac
        shift
    done
}

detect_terminal() {
    if [[ -t 1 && "${TERM:-dumb}" != "dumb" && -z "${NO_COLOR:-}" && $FORCE_NO_COLOR -eq 0 ]]; then
        TTY_MODE=1
    else
        TTY_MODE=0
        C_RESET=""; C_CYAN=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_MAGENTA=""; C_BLUE=""; C_WHITE=""; C_BOLD=""; C_DIM=""
    fi

    if [[ -n "${SSH_CONNECTION:-}" || -n "${SSH_CLIENT:-}" ]]; then
        REMOTE_SESSION=1
        SSH_CLIENT_IP="${SSH_CLIENT%% *}"
        [[ -n "${SSH_CONNECTION:-}" ]] && SSH_LOCAL_IP="$(awk '{print $3}' <<<"$SSH_CONNECTION")"
    fi
}

ensure_privileges() {
    if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
        return 0
    fi
    command_exists sudo || die "Root privileges are required and sudo is unavailable."
    if [[ -f "$0" && -r "$0" ]]; then
        msg_info "Root privileges required; re-executing through sudo."
        exec sudo -- env \
            SSH_CONNECTION="${SSH_CONNECTION:-}" \
            SSH_CLIENT="${SSH_CLIENT:-}" \
            TERM="${TERM:-dumb}" \
            NO_COLOR="${NO_COLOR:-}" \
            bash "$0" "$@"
    fi
    die "Operational modes require root."
}

need_tty() {
    case "$MODE" in
        bootstrap|manage|interactive|backup|admin|users|groups|computers|permissions|gpo|security|install-cli)
            [[ -r /dev/tty ]] || die "Mode '$MODE' requires a controlling TTY."
            INPUT_FD="/dev/tty"
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
    chmod 700 "$STATE_DIR" "$LOG_DIR" "$RUN_ROOT" "$BACKUP_DIR" "$DOMAIN_BACKUP_DIR" "$GPO_DIR"
    touch "$LOG_FILE" "$REPORT_FILE"
    chmod 600 "$LOG_FILE" "$REPORT_FILE"

    if command_exists flock; then
        exec 9>"${STATE_DIR}/assistant.lock"
        flock -n 9 || die "Another ${SCRIPT_NAME} instance is running."
    else
        LOCK_DIR="${STATE_DIR}/assistant.lock.d"
        mkdir "$LOCK_DIR" 2>/dev/null || die "Another ${SCRIPT_NAME} instance appears to be running."
    fi

    KRB5_CACHE="${RUN_ROOT}/krb5cc"
    export KRB5CCNAME="FILE:${KRB5_CACHE}"
}

cleanup() {
    local rc=$?
    if [[ ${DNS_TRANSACTION_ACTIVE:-0} -eq 1 ]]; then
        rollback_dns_transaction "process exited before DNS transaction commit" || true
    fi
    [[ -n "${KRB5CCNAME:-}" ]] && command_exists kdestroy && kdestroy -c "$KRB5CCNAME" >/dev/null 2>&1 || true
    [[ -n "${LOCK_DIR:-}" ]] && rmdir "$LOCK_DIR" >/dev/null 2>&1 || true
    exit "$rc"
}

on_error() {
    local rc=$?
    local cmd="${BASH_COMMAND:-unknown}"
    [[ -n "${LOG_FILE:-}" ]] && {
        printf '[FATAL] rc=%s command=%s\n' "$rc" "$cmd"
        printf '[FATAL] mode=%s step=%s/%s\n' "$MODE" "$CURRENT_STEP" "$TOTAL_STEPS"
    } >>"$LOG_FILE" 2>/dev/null || true
    printf '\n%b[FATAL]%b command failed (rc=%s): %s\n' "$C_RED" "$C_RESET" "$rc" "$cmd" >&2
    return "$rc"
}

trap on_error ERR
trap cleanup EXIT INT TERM

banner() {
    ui_clear
    printf '%b%b' "$C_CYAN" "$C_BOLD"
    cat <<'EOF'
       █████╗ ██████╗        ██████╗  ██████╗
      ██╔══██╗██╔══██╗       ██╔══██╗██╔════╝
      ███████║██║  ██║ █████╗██║  ██║██║
      ██╔══██║██║  ██║ ╚════╝██║  ██║██║
      ██║  ██║██████╔╝       ██████╔╝╚██████╗
      ╚═╝  ╚═╝╚═════╝        ╚═════╝  ╚═════╝
EOF
    printf '%b' "$C_RESET"
    printf '%b%b                 DEBIAN ACTIVE DIRECTORY CONTROL PLANE%b\n' "$C_BOLD" "$C_WHITE" "$C_RESET"
    printf '%b                 Secure provisioning · operations · recovery%b\n' "$C_DIM" "$C_RESET"
    ui_rule
    printf '  Version       %b%s%b\n' "$C_CYAN" "$SCRIPT_VERSION" "$C_RESET"
    printf '  Execution     mode=%b%s%b | session=%b%s%b\n' \
        "$C_CYAN" "$MODE" "$C_RESET" \
        "$C_CYAN" "$([[ $REMOTE_SESSION -eq 1 ]] && echo "remote/SSH" || echo "local")" "$C_RESET"
    printf '  Host          %s\n' "$(hostname -f 2>/dev/null || hostname)"
    ui_rule
    printf '\n'
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
    is_valid_dns_hostname_label "$1" && [[ ${#1} -le 15 ]]
}

is_valid_dns_name() {
    local name="${1%.}" label
    local -a labels
    [[ ${#name} -le 253 && "$name" == *.* ]] || return 1
    IFS='.' read -r -a labels <<<"$name"
    for label in "${labels[@]}"; do
        is_valid_dns_hostname_label "$label" || return 1
    done
}

is_valid_netbios() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{0,14}$ ]]
}

is_valid_ad_username() {
    local value="$1"
    [[ ${#value} -ge 1 && ${#value} -le 64 ]] || return 1
    [[ "$value" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || return 1
    case "${value,,}" in administrator|guest|krbtgt) return 1 ;; esac
}

domain_dn() {
    printf '%s' "$1" | awk -F. '{for(i=1;i<=NF;i++)printf "DC=%s%s",$i,(i<NF?",":"")}'
}

netbios_from_domain() {
    printf '%s' "$1" | tr -cd '[:alnum:]' | tr '[:lower:]' '[:upper:]' | cut -c1-15
}

refresh_canonical_identity() {
    DC_HOSTNAME="${DC_HOSTNAME,,}"
    DOMAIN="${DOMAIN,,}"
    REALM="${DOMAIN^^}"
    DC_FQDN="${DC_HOSTNAME}.${DOMAIN}"
    DC_NETBIOS="${DC_HOSTNAME^^}"
}

safe_systemctl_state() {
    local state
    state="$(systemctl is-active "$1" 2>/dev/null || true)"
    printf '%s' "${state:-inactive}"
}

safe_systemctl_enabled() {
    local state
    state="$(systemctl is-enabled "$1" 2>/dev/null || true)"
    printf '%s' "${state:-not-found}"
}

require_cmd() {
    local cmd="$1" purpose="${2:-operation}"
    if ! command_exists "$cmd"; then
        result ERROR "$cmd" "missing" "$purpose"
        return 1
    fi
}

detect_os() {
    [[ -r /etc/os-release ]] || die "Missing /etc/os-release"
    # shellcheck disable=SC1091
    source /etc/os-release
    DISTRO_ID="${ID:-unknown}"
    DISTRO_LIKE="${ID_LIKE:-}"
    DISTRO_VERSION="${VERSION_ID:-unknown}"
    PRETTY_NAME_SAFE="${PRETTY_NAME:-$DISTRO_ID}"

    case "$DISTRO_ID" in
        debian|ubuntu) ;;
        *)
            [[ "$DISTRO_LIKE" == *debian* ]] || die "Unsupported distribution: $DISTRO_ID"
            warn_msg "Debian derivative detected: $DISTRO_ID; best-effort support."
            ;;
    esac
    result INFO "Distribution" "$PRETTY_NAME_SAFE" "Debian/Ubuntu"
}

discover_network_topology() {
    WAN_IFACE=""
    WAN_IP=""
    WAN_CIDR=""
    DEFAULT_GW=""
    AD_IFACE=""
    AD_IP=""
    AD_CIDR=""
    MGMT_IFACE=""

    local default_line
    default_line="$(ip -4 route show default 2>/dev/null | head -n1 || true)"
    WAN_IFACE="$(awk '{for(i=1;i<=NF;i++)if($i=="dev"){print $(i+1);exit}}' <<<"$default_line")"
    DEFAULT_GW="$(awk '{for(i=1;i<=NF;i++)if($i=="via"){print $(i+1);exit}}' <<<"$default_line")"

    if [[ -n "$WAN_IFACE" ]]; then
        WAN_CIDR="$(ip -4 -o addr show dev "$WAN_IFACE" scope global 2>/dev/null | awk 'NR==1{print $4}' || true)"
        WAN_IP="${WAN_CIDR%%/*}"
    fi

    local -a global_ifaces=()
    mapfile -t global_ifaces < <(ip -4 -o addr show scope global 2>/dev/null | awk '{print $2}' | sort -u)

    if ((${#global_ifaces[@]} == 0)); then
        NETWORK_MODE="no-ipv4"
        return 0
    elif ((${#global_ifaces[@]} == 1)); then
        NETWORK_MODE="single-nic"
        AD_IFACE="${global_ifaces[0]}"
    else
        NETWORK_MODE="dual-or-multihomed"
        local iface
        for iface in "${global_ifaces[@]}"; do
            [[ "$iface" != "$WAN_IFACE" ]] && { AD_IFACE="$iface"; break; }
        done
        [[ -n "$AD_IFACE" ]] || AD_IFACE="$WAN_IFACE"
    fi

    AD_CIDR="$(ip -4 -o addr show dev "$AD_IFACE" scope global 2>/dev/null | awk 'NR==1{print $4}' || true)"
    AD_IP="${AD_CIDR%%/*}"

    if [[ $REMOTE_SESSION -eq 1 && -n "$SSH_LOCAL_IP" && -n "$SSH_CLIENT_IP" ]]; then
        MGMT_IFACE="$(ip -4 route get "$SSH_CLIENT_IP" from "$SSH_LOCAL_IP" 2>/dev/null |
            awk '{for(i=1;i<=NF;i++)if($i=="dev"){print $(i+1);exit}}' || true)"
    fi
    [[ -n "$MGMT_IFACE" ]] || MGMT_IFACE="${WAN_IFACE:-$AD_IFACE}"

    PRIMARY_IFACE="$AD_IFACE"
    PRIMARY_CIDR="$AD_CIDR"
    PRIMARY_IP="$AD_IP"
}

show_network_topology() {
    section "NETWORK TOPOLOGY"
    printf 'Detected mode : %s\n' "$NETWORK_MODE"
    printf 'WAN/default   : %-12s %-18s gateway=%s\n' "${WAN_IFACE:-none}" "${WAN_CIDR:-none}" "${DEFAULT_GW:-none}"
    printf 'AD candidate  : %-12s %-18s\n' "${AD_IFACE:-none}" "${AD_CIDR:-none}"
    printf 'Management    : %-12s client=%s\n' "${MGMT_IFACE:-none}" "${SSH_CLIENT_IP:-local}"
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
            *member*) SAMBA_ROLE="member" ;;
            *standalone*) SAMBA_ROLE="standalone" ;;
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
    [[ -n "$AD_IP" ]] && DC_IP="$AD_IP"
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
    [[ -f "$dest" ]] && command_exists sha256sum && hash="$(sha256sum "$dest" | awk '{print $1}')"
    mode="$(stat -c '%a' "$src" 2>/dev/null || printf '?')"
    owner="$(stat -c '%U:%G' "$src" 2>/dev/null || printf '?')"
    BACKUP_MANIFEST+=("${src}|${dest}|${hash}|${mode}|${owner}")
}

write_backup_manifest() {
    {
        printf 'Generated: %s\n' "$(date -Is)"
        printf 'source|backup|sha256|mode|owner\n'
        printf '%s\n' "${BACKUP_MANIFEST[@]}"
    } >"${BACKUP_DIR}/manifest.txt"
    chmod 600 "${BACKUP_DIR}/manifest.txt"
}

snapshot_system() {
    local d="${RUN_ROOT}/snapshot"
    mkdir -p "$d"
    chmod 700 "$d"
    {
        date -Is
        uname -a
        printf '\n-- ip addr --\n'; ip -br addr 2>&1 || true
        printf '\n-- ip route --\n'; ip route 2>&1 || true
        printf '\n-- resolver --\n'; ls -l /etc/resolv.conf 2>&1 || true; cat /etc/resolv.conf 2>&1 || true
        printf '\n-- samba service --\n'; systemctl status samba-ad-dc --no-pager --full 2>&1 || true
        printf '\n-- ufw --\n'; ufw status verbose 2>&1 || true
    } >"${d}/system.txt"
    chmod 600 "${d}/system.txt"

    backup_file /etc/samba/smb.conf
    backup_file /etc/hosts
    backup_file /etc/resolv.conf
    backup_file /etc/krb5.conf
}

package_available() {
    apt-cache show "$1" >/dev/null 2>&1
}

install_required_packages() {
    step "Install required packages"
    require_cmd apt-get "package management" || return 1
    apt-get update

    local dns_tools="dnsutils"
    package_available bind9-dnsutils && dns_tools="bind9-dnsutils"

    local -a pkgs=(
        samba-ad-dc samba-ad-provision krb5-user chrony acl attr
        ldb-tools smbclient python3 iproute2 "$dns_tools"
    )
    [[ "$ENABLE_UFW" == "yes" ]] && package_available ufw && pkgs+=(ufw)

    DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}"
    result PASS "Packages" "required packages present" "Samba/Kerberos/DNS/Chrony"
}

choose_ad_interface() {
    discover_network_topology
    show_network_topology

    local -a candidates=()
    mapfile -t candidates < <(ip -4 -o addr show scope global | awk '{print $2}' | sort -u)
    ((${#candidates[@]})) || die "No global IPv4 interface detected."

    if ((${#candidates[@]} > 1)); then
        local chosen
        chosen="$(ask 'Interface dedicated/preferred for Active Directory' "$AD_IFACE")"
        ip link show dev "$chosen" >/dev/null 2>&1 || die "Interface '$chosen' does not exist."
        AD_IFACE="$chosen"
        AD_CIDR="$(ip -4 -o addr show dev "$AD_IFACE" scope global | awk 'NR==1{print $4}')"
        AD_IP="${AD_CIDR%%/*}"
    fi

    PRIMARY_IFACE="$AD_IFACE"
    PRIMARY_CIDR="$AD_CIDR"
    PRIMARY_IP="$AD_IP"
}

collect_identity() {
    step "Domain and network identity"
    choose_ad_interface

    DC_HOSTNAME="$(ask 'Short DNS hostname for the DC' "${DC_HOSTNAME:-dc01}")"
    DC_HOSTNAME="${DC_HOSTNAME,,}"
    DOMAIN="$(ask 'AD DNS domain' "${DOMAIN:-example.internal}")"
    DOMAIN="${DOMAIN,,}"
    is_valid_ad_dc_hostname "$DC_HOSTNAME" || die "Invalid DC hostname."
    is_valid_dns_name "$DOMAIN" || die "Invalid DNS domain."

    refresh_canonical_identity

    DC_IP="$(ask 'DC IPv4 address already assigned to AD interface' "${DC_IP:-${AD_IP:-192.168.1.10}}")"
    NETBIOS_DOMAIN="$(ask 'NetBIOS domain' "${NETBIOS_DOMAIN:-$(netbios_from_domain "$DOMAIN")}")"
    NETBIOS_DOMAIN="${NETBIOS_DOMAIN^^}"
    is_valid_ipv4 "$DC_IP" || die "Invalid IPv4: $DC_IP"
    is_valid_netbios "$NETBIOS_DOMAIN" || die "Invalid NetBIOS domain."

    ip -4 addr show dev "$AD_IFACE" | grep -Fq " ${DC_IP}/" ||
        die "DC IP $DC_IP is not assigned to $AD_IFACE. Configure the static IP first."

    AD_CIDR="$(ip -4 -o addr show dev "$AD_IFACE" scope global |
        awk -v ip="$DC_IP" '$4 ~ "^"ip"/" {print $4;exit}')"
    [[ -n "$AD_CIDR" ]] || AD_CIDR="$(ip -4 -o addr show dev "$AD_IFACE" scope global | awk 'NR==1{print $4}')"
    AD_IP="$DC_IP"
    PRIMARY_IFACE="$AD_IFACE"
    PRIMARY_CIDR="$AD_CIDR"
    PRIMARY_IP="$DC_IP"
}

collect_admin_identity() {
    step "Delegated AD administrator"
    local candidate="${ADMIN_USER:-}"
    printf '\nThe built-in Administrator is used only for bootstrap/recovery.\n'
    printf 'Choose the delegated administrator that will be used afterwards.\n\n'

    while true; do
        candidate="$(ask 'First delegated AD administrator account' "$candidate")"
        is_valid_ad_username "$candidate" && break
        msg_warn "Invalid/reserved name. Use letters/numbers and . _ -; not Administrator, Guest or krbtgt."
        candidate=""
    done
    ADMIN_USER="$candidate"
    result INFO "Delegated AD admin" "$ADMIN_USER" "created/promoted and verified later"
}

cidr_from_interface() {
    local cidr="$1"
    command_exists python3 || { printf '%s' "$cidr"; return 0; }
    python3 -c 'import ipaddress,sys; print(ipaddress.ip_interface(sys.argv[1]).network)' "$cidr" 2>/dev/null || printf '%s' "$cidr"
}

collect_network_policy() {
    step "Network policy inputs"
    local default_net
    default_net="$(cidr_from_interface "${AD_CIDR:-192.168.1.10/24}")"

    AD_CLIENT_CIDR="$(ask 'AD/NTP client network (CIDR)' "${AD_CLIENT_CIDR:-$default_net}")"
    is_valid_ipv4 "$AD_CLIENT_CIDR" && AD_CLIENT_CIDR="${AD_CLIENT_CIDR}/32"
    is_valid_cidr "$AD_CLIENT_CIDR" || die "Invalid AD client CIDR."

    [[ -z "$SSH_SOURCE" && -n "$SSH_CLIENT_IP" ]] && SSH_SOURCE="${SSH_CLIENT_IP}/32"
    SSH_SOURCE="$(ask 'SSH management source (CIDR)' "${SSH_SOURCE:-$AD_CLIENT_CIDR}")"
    is_valid_ipv4 "$SSH_SOURCE" && SSH_SOURCE="${SSH_SOURCE}/32"
    is_valid_cidr "$SSH_SOURCE" || die "Invalid SSH management CIDR."

    result INFO "AD clients" "$AD_CLIENT_CIDR via $AD_IFACE" "restricted source/interface"
    result INFO "SSH source" "$SSH_SOURCE via ${MGMT_IFACE:-any}" "preserve management access"
}

rewrite_hosts_for_dc() {
    backup_file /etc/hosts
    local tmp="${RUN_ROOT}/hosts.new"
    awk -v ip="$DC_IP" -v fqdn="$DC_FQDN" -v short="$DC_HOSTNAME" '
        BEGIN { inblock=0 }
        $0=="# BEGIN DEBIAN-AD-ASSISTANT" { inblock=1; next }
        $0=="# END DEBIAN-AD-ASSISTANT" { inblock=0; next }
        inblock { next }
        {
            if ($1 == ip) {
                keep=""
                for (i=2;i<=NF;i++) {
                    if ($i != fqdn && $i != short && $i !~ /^#/) keep=keep (keep?" ":"") $i
                }
                if (keep!="") print $1 "\t" keep
                next
            }
            print
        }
        END {
            print ""
            print "# BEGIN DEBIAN-AD-ASSISTANT"
            print ip "\t" fqdn " " short
            print "# END DEBIAN-AD-ASSISTANT"
        }
    ' /etc/hosts >"$tmp"
    install -o root -g root -m 0644 "$tmp" /etc/hosts
}

validate_local_identity_preflight() {
    refresh_canonical_identity
    local short fqdn
    short="$(hostname -s 2>/dev/null || true)"
    fqdn="$(hostname -f 2>/dev/null || true)"

    [[ "${short,,}" == "$DC_HOSTNAME" ]] || { fail_msg "hostname -s='$short', expected '$DC_HOSTNAME'."; return 1; }
    [[ "${fqdn,,}" == "$DC_FQDN" ]] || { fail_msg "hostname -f='$fqdn', expected '$DC_FQDN'."; return 1; }
    getent ahostsv4 "$DC_FQDN" | awk '{print $1}' | grep -Fxq "$DC_IP" ||
        { fail_msg "$DC_FQDN does not resolve locally to $DC_IP."; return 1; }

    result PASS "Local hostname" "$short" "$DC_HOSTNAME"
    result PASS "Local FQDN" "$fqdn" "$DC_FQDN"
}

configure_hostname_hosts() {
    step "Hostname / FQDN / hosts preflight"
    refresh_canonical_identity
    backup_file /etc/hostname
    rewrite_hosts_for_dc

    if [[ "$(hostname -s 2>/dev/null || true)" != "$DC_HOSTNAME" ]]; then
        hostnamectl set-hostname "$DC_HOSTNAME"
        change APPLIED "hostname=$DC_HOSTNAME"
    fi
    validate_local_identity_preflight
}

set_smb_global_option() {
    local key="$1" value="$2"
    require_cmd python3 "safe smb.conf editing" || return 1
    python3 -c '
from pathlib import Path
import re,sys
p=Path("/etc/samba/smb.conf")
key,value=sys.argv[1],sys.argv[2]
t=p.read_text(encoding="utf-8")
rx=re.compile(r"(?mi)^[ \t]*"+re.escape(key)+r"[ \t]*=.*$")
line="\t%s = %s"%(key,value)
if rx.search(t):
    t=rx.sub(line,t,count=1)
else:
    t=re.sub(r"(?mi)^\[global\][ \t]*$",lambda m:m.group(0)+"\n"+line,t,count=1)
p.write_text(t,encoding="utf-8")
' "$key" "$value"
}

configure_samba_interface_scope() {
    [[ -f /etc/samba/smb.conf ]] || return 0
    if [[ "$NETWORK_MODE" == "single-nic" ]]; then
        result INFO "Samba interface scope" "single NIC" "reviewed"
        return 0
    fi

    printf '\nMultihomed host detected. Proposed Samba bind: 127.0.0.1 + %s\n' "$DC_IP"
    if confirm "Restrict Samba to loopback + AD IPv4?" Y; then
        backup_file /etc/samba/smb.conf
        set_smb_global_option "interfaces" "127.0.0.1 ${DC_IP}"
        set_smb_global_option "bind interfaces only" "yes"
        testparm -s >/dev/null
        SAMBA_INTERFACE_SCOPED="yes"
        result PASS "Samba interface scope" "127.0.0.1 $DC_IP" "WAN excluded"
    else
        warn_msg "Samba remains able to bind additional interfaces."
    fi
}

configure_samba_boot_ordering() {
    discover_network_topology
    [[ -n "$DC_IP" ]] || DC_IP="${AD_IP:-$PRIMARY_IP}"
    [[ -n "$AD_IFACE" && -n "$DC_IP" ]] || die "Cannot configure boot ordering without AD interface/IP."

    local helper="/usr/local/libexec/debian-ad-wait-network"
    local ready_unit="/etc/systemd/system/debian-ad-network-ready.service"
    local dropin_dir="/etc/systemd/system/samba-ad-dc.service.d"
    local dropin="${dropin_dir}/20-debian-ad-network.conf"

    mkdir -p /usr/local/libexec "$dropin_dir"
    backup_file "$helper"
    backup_file "$ready_unit"
    backup_file "$dropin"

    cat >"$helper" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
iface="${1:?interface required}"
ip_addr="${2:?IPv4 required}"
timeout="${3:-90}"

for ((i=0; i<timeout; i++)); do
    if /usr/sbin/ip -4 -o addr show dev "$iface" scope global 2>/dev/null | /usr/bin/grep -Fq " ${ip_addr}/"; then
        exit 0
    fi
    /usr/bin/sleep 1
done

printf '[ERROR] Interface %s did not acquire %s within %ss\n' "$iface" "$ip_addr" "$timeout" >&2
exit 1
EOF
    chmod 0755 "$helper"

    "$helper" "$AD_IFACE" "$DC_IP" 5 ||
        die "Current AD interface/IP is not ready. Refusing to install a broken boot dependency."

    cat >"$ready_unit" <<EOF
[Unit]
Description=Wait for Samba AD DC network identity
After=network-pre.target systemd-networkd.service wpa_supplicant.service NetworkManager.service
Before=network-online.target samba-ad-dc.service

[Service]
Type=oneshot
ExecStart=$helper $AD_IFACE $DC_IP 90
RemainAfterExit=yes

[Install]
WantedBy=network-online.target
EOF

    cat >"$dropin" <<'EOF'
[Unit]
Wants=network-online.target
Requires=debian-ad-network-ready.service
After=network-online.target debian-ad-network-ready.service
EOF

    systemctl daemon-reload
    systemctl enable debian-ad-network-ready.service >/dev/null
    systemctl unmask samba-ad-dc >/dev/null 2>&1 || true
    systemctl enable samba-ad-dc >/dev/null

    change APPLIED "Samba waits for $AD_IFACE/$DC_IP before boot"
    result PASS "Samba boot ordering" "$AD_IFACE $DC_IP" "persistent network guard"
}

audit_samba_boot_persistence() {
    local enabled guard
    enabled="$(safe_systemctl_enabled samba-ad-dc)"
    [[ "$enabled" == "enabled" ]] \
        && result PASS "samba-ad-dc boot" "$enabled" "enabled" \
        || result FAIL "samba-ad-dc boot" "$enabled" "enabled"

    guard="$(safe_systemctl_enabled debian-ad-network-ready.service)"
    if [[ "$guard" == "enabled" && -f /etc/systemd/system/samba-ad-dc.service.d/20-debian-ad-network.conf ]]; then
        result PASS "AD network boot guard" "enabled" "wait before Samba"
    else
        result WARN "AD network boot guard" "$guard" "configure from Security menu"
    fi
}

configure_samba_service_model() {
    step "Samba service model"
    local unit
    for unit in smbd nmbd winbind; do
        systemctl disable --now "$unit" >/dev/null 2>&1 || true
        systemctl mask "$unit" >/dev/null 2>&1 || true
    done
    systemctl unmask samba-ad-dc >/dev/null 2>&1 || true
    systemctl enable samba-ad-dc >/dev/null
    configure_samba_boot_ordering
    result PASS "Samba service model" "samba-ad-dc" "dedicated AD/DC"
}

capture_resolver_state() {
    RESOLV_SNAPSHOT="${RUN_ROOT}/resolv.conf.before"
    [[ -e /etc/resolv.conf || -L /etc/resolv.conf ]] &&
        cp -a --no-dereference /etc/resolv.conf "$RESOLV_SNAPSHOT"
    systemctl is-active --quiet systemd-resolved 2>/dev/null && RESOLVED_WAS_ACTIVE=1 || RESOLVED_WAS_ACTIVE=0
    systemctl is-enabled --quiet systemd-resolved 2>/dev/null && RESOLVED_WAS_ENABLED=1 || RESOLVED_WAS_ENABLED=0
}

restore_resolv_snapshot() {
    rm -f /etc/resolv.conf
    [[ -e "$RESOLV_SNAPSHOT" || -L "$RESOLV_SNAPSHOT" ]] &&
        cp -a --no-dereference "$RESOLV_SNAPSHOT" /etc/resolv.conf
}

rollback_dns_transaction() {
    local reason="${1:-DNS transaction failed}"
    warn_msg "DNS rollback: $reason"
    restore_resolv_snapshot || true
    [[ $RESOLVED_WAS_ENABLED -eq 1 ]] && systemctl enable systemd-resolved >/dev/null 2>&1 || true
    [[ $RESOLVED_WAS_ACTIVE -eq 1 ]] && systemctl start systemd-resolved >/dev/null 2>&1 || true
    DNS_TRANSACTION_ACTIVE=0
}

detect_dns_forwarder() {
    local existing candidates
    existing="$(testparm -s --parameter-name='dns forwarder' 2>/dev/null | awk 'NF{print $1;exit}' || true)"
    if is_valid_ipv4 "$existing" && [[ "$existing" != 127.0.0.1 && "$existing" != 127.0.0.53 ]]; then
        printf '%s' "$existing"
        return
    fi
    candidates="$(awk '/^[[:space:]]*nameserver[[:space:]]+/{print $2}' /etc/resolv.conf 2>/dev/null || true)"
    printf '%s\n' "$candidates" | grep -Ev '^(127\.0\.0\.1|127\.0\.0\.53)$' | head -n1 || true
}

samba_dns_stack_healthy() {
    command_exists dig || return 1
    systemctl is-active --quiet samba-ad-dc || return 1
    [[ -n "$DC_FQDN" && -n "$DC_IP" ]] || return 1
    dig +time=3 +tries=1 @127.0.0.1 "$DC_FQDN" A +short 2>/dev/null | grep -Fxq "$DC_IP" || return 1
    grep -Eq '^[[:space:]]*nameserver[[:space:]]+127\.0\.0\.1([[:space:]]|$)' /etc/resolv.conf 2>/dev/null || return 1
}

prepare_dns_transaction() {
    step "Prepare DNS transition"
    DNS_NEEDS_COMMIT=1

    if [[ "$BOOTSTRAP_RESUME" -eq 1 ]] && samba_dns_stack_healthy; then
        DNS_FORWARDER="${DNS_FORWARDER:-$(detect_dns_forwarder)}"
        DNS_NEEDS_COMMIT=0
        result SKIP "DNS transition" "Samba DNS/resolver already healthy" "retained"
        return 0
    fi

    capture_resolver_state
    DNS_TRANSACTION_ACTIVE=1
    DNS_FORWARDER="${DNS_FORWARDER:-$(detect_dns_forwarder)}"
    DNS_FORWARDER="$(ask 'Upstream DNS forwarder' "${DNS_FORWARDER:-1.1.1.1}")"
    is_valid_ipv4 "$DNS_FORWARDER" || die "Invalid DNS forwarder."

    dig +time=3 +tries=1 @"$DNS_FORWARDER" raw.githubusercontent.com A >/dev/null 2>&1 ||
        die "Upstream resolver $DNS_FORWARDER cannot resolve external names."

    [[ $RESOLVED_WAS_ACTIVE -eq 1 ]] && systemctl stop systemd-resolved
    printf 'nameserver %s\noptions timeout:2 attempts:2\n' "$DNS_FORWARDER" >/etc/resolv.conf
    chmod 644 /etc/resolv.conf

    getent ahostsv4 raw.githubusercontent.com >/dev/null 2>&1 ||
        die "External DNS failed during temporary resolver transition."
    result PASS "Temporary resolver" "$DNS_FORWARDER" "external DNS preserved"
}

wait_for_samba() {
    local i listeners
    for i in {1..30}; do
        if systemctl is-active --quiet samba-ad-dc; then
            listeners="$(ss -lntup 2>/dev/null || true)"
            if grep -Eq ':53([[:space:]]|$)' <<<"$listeners" &&
               grep -Eq ':88([[:space:]]|$)' <<<"$listeners" &&
               grep -Eq ':389([[:space:]]|$)' <<<"$listeners" &&
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
    require_cmd dig "DNS validation" || return 1
    backup_file /etc/samba/smb.conf

    set_smb_global_option "dns forwarder" "$DNS_FORWARDER"
    testparm -s >/dev/null

    systemctl restart samba-ad-dc || {
        journalctl -u samba-ad-dc -b --no-pager -n 100 >"${RUN_ROOT}/samba-start-failure.log" 2>&1 || true
        return 1
    }
    wait_for_samba || {
        journalctl -u samba-ad-dc -b --no-pager -n 100 >"${RUN_ROOT}/samba-health-failure.log" 2>&1 || true
        return 1
    }

    dig +time=3 +tries=1 @127.0.0.1 "$DC_FQDN" A +short | grep -Fxq "$DC_IP" ||
        die "Samba DNS does not resolve $DC_FQDN to $DC_IP."
    dig +time=4 +tries=1 @127.0.0.1 raw.githubusercontent.com A +short | grep -Eq '^[0-9]' ||
        die "Samba DNS forwarding is not working."

    printf 'nameserver 127.0.0.1\nsearch %s\noptions timeout:2 attempts:2\n' "$DOMAIN" >/etc/resolv.conf
    chmod 644 /etc/resolv.conf
    systemctl disable systemd-resolved >/dev/null 2>&1 || true

    [[ -f /var/lib/samba/private/krb5.conf ]] || die "Missing Samba-generated krb5.conf."
    backup_file /etc/krb5.conf
    install -o root -g root -m 0644 /var/lib/samba/private/krb5.conf /etc/krb5.conf

    DNS_TRANSACTION_ACTIVE=0
    result PASS "Samba DNS" "$DC_FQDN -> $DC_IP" "authoritative + forwarding"
}

repair_dns_stack() {
    set_progress_plan 2
    prepare_dns_transaction
    configure_samba_interface_scope
    if [[ "$DNS_NEEDS_COMMIT" -eq 1 ]]; then
        commit_samba_dns_resolver || {
            rollback_dns_transaction "DNS/Samba repair failed"
            return 1
        }
    fi
}

configure_time() {
    step "Time synchronization"
    TIMEZONE="$(ask 'Timezone' "${TIMEZONE:-Europe/London}")"
    NTP_POOL="$(ask 'NTP pool/server' "${NTP_POOL:-pool.ntp.org}")"

    timedatectl set-timezone "$TIMEZONE"
    mkdir -p /etc/chrony/conf.d
    backup_file /etc/chrony/conf.d/90-debian-ad.conf
    cat >/etc/chrony/conf.d/90-debian-ad.conf <<EOF
# Managed by ${SCRIPT_NAME}.
pool ${NTP_POOL} iburst maxsources 4
allow ${AD_CLIENT_CIDR}
EOF
    systemctl enable --now chrony >/dev/null
    systemctl restart chrony
    result PASS "Chrony" "$(safe_systemctl_state chrony)" "active"
}

verify_provisioned_identity() {
    refresh_canonical_identity
    local actual_realm actual_workgroup actual_netbios
    actual_realm="$(testparm -s --parameter-name=realm 2>/dev/null | tr -d '\r' || true)"
    actual_workgroup="$(testparm -s --parameter-name=workgroup 2>/dev/null | tr -d '\r' || true)"
    actual_netbios="$(testparm -s --parameter-name='netbios name' 2>/dev/null | tr -d '\r' || true)"

    [[ "${actual_realm^^}" == "$REALM" ]] || { fail_msg "Realm mismatch: $actual_realm != $REALM"; return 1; }
    [[ "${actual_workgroup^^}" == "$NETBIOS_DOMAIN" ]] || { fail_msg "Workgroup mismatch."; return 1; }
    [[ "${actual_netbios^^}" == "$DC_NETBIOS" ]] || { fail_msg "DC NetBIOS mismatch."; return 1; }
    validate_local_identity_preflight
}

provision_new_domain() {
    step "Provision Samba AD/DC"
    [[ -f /var/lib/samba/private/sam.ldb ]] && die "Existing sam.ldb detected. Reprovision is prohibited."
    validate_local_identity_preflight || return 1

    [[ -f /etc/samba/smb.conf ]] && {
        backup_file /etc/samba/smb.conf
        mv /etc/samba/smb.conf "${BACKUP_DIR}/smb.conf.pre-provision"
    }

    printf '\nSamba will request the initial built-in Administrator password.\n'
    samba-tool domain provision \
        --domain="$NETBIOS_DOMAIN" \
        --realm="$REALM" \
        --server-role=dc \
        --use-rfc2307 \
        --dns-backend=SAMBA_INTERNAL \
        <"$INPUT_FD"

    configure_samba_interface_scope
    verify_provisioned_identity
    result PASS "Domain provision" "$DOMAIN" "database created"
}

bootstrap_resume_identity() {
    BOOTSTRAP_RESUME=1
    local saved_domain="" saved_realm="" saved_netbios="" saved_hostname="" saved_admin=""
    local had_config=0

    if load_config; then
        had_config=1
        saved_domain="$DOMAIN"
        saved_realm="$REALM"
        saved_netbios="$NETBIOS_DOMAIN"
        saved_hostname="$DC_HOSTNAME"
        saved_admin="$ADMIN_USER"
    fi

    discover_network_topology
    discover_existing_identity

    if (( had_config == 1 )); then
        [[ -z "$saved_domain" || "${saved_domain,,}" == "${DOMAIN,,}" ]] ||
            die "Resume refused: saved domain differs from existing AD."
        [[ -z "$saved_realm" || "${saved_realm^^}" == "${REALM^^}" ]] ||
            die "Resume refused: saved realm differs from existing AD."
        [[ -z "$saved_netbios" || "${saved_netbios^^}" == "${NETBIOS_DOMAIN^^}" ]] ||
            die "Resume refused: saved NetBIOS domain differs from existing AD."
        [[ -z "$saved_hostname" || "${saved_hostname,,}" == "${DC_HOSTNAME,,}" ]] ||
            die "Resume refused: saved DC hostname differs from existing AD."
        ADMIN_USER="$saved_admin"
        result PASS "Bootstrap resume identity" "matches saved assistant state" "$DOMAIN"
        confirm "Resume bootstrap against this matching AD/DC? Provision will NOT run" Y ||
            die "Bootstrap resume cancelled."
    else
        printf '\nExisting AD/DC has no assistant config.env.\n'
        printf 'This may be an older partial bootstrap. Adoption cannot be proven automatically.\n'
        confirm_high_risk "Adopt this existing AD/DC for bootstrap recovery; reprovision remains prohibited" ||
            die "Existing AD/DC was not adopted."
    fi
    refresh_canonical_identity
}

resume_or_provision_domain() {
    if [[ "$BOOTSTRAP_RESUME" -eq 1 ]]; then
        step "Provision Samba AD/DC"
        [[ -f /var/lib/samba/private/sam.ldb ]] || die "Resume expected sam.ldb but it is missing."
        verify_provisioned_identity || return 1
        result SKIP "Domain provision" "existing sam.ldb retained" "reprovision prohibited"
    else
        provision_new_domain
    fi
}

ensure_kerberos_ticket() {
    require_cmd kinit "Kerberos authentication" || return 1
    local user="${1:-${ADMIN_USER:-}}"
    [[ -n "$user" ]] || user="$(ask 'AD admin account' 'Administrator')"
    local principal="${user}@${REALM}"

    if KRB5CCNAME="$KRB5CCNAME" klist -s >/dev/null 2>&1; then
        local current
        current="$(KRB5CCNAME="$KRB5CCNAME" klist 2>/dev/null |
            awk -F': ' '/Default principal:/{print $2;exit}' || true)"
        [[ "${current^^}" == "${principal^^}" ]] && return 0
        KRB5CCNAME="$KRB5CCNAME" kdestroy >/dev/null 2>&1 || true
    fi

    printf 'Kerberos ticket required for %s\n' "$principal"
    KRB5CCNAME="$KRB5CCNAME" kinit "$principal" <"$INPUT_FD"
    KRB5CCNAME="$KRB5CCNAME" klist -s
}

ad_user_is_disabled() {
    local user="$1" uac
    uac="$(samba-tool user show "$user" --attributes=userAccountControl 2>/dev/null |
        awk -F': ' '/userAccountControl:/{print $2;exit}' | tr -d '\r[:space:]' || true)"
    [[ "$uac" =~ ^[0-9]+$ ]] || return 1
    (( (uac & 2) != 0 ))
}

harden_delegated_admin() {
    [[ -n "$ADMIN_USER" ]] || collect_admin_identity
    [[ "${ADMIN_USER,,}" != administrator ]] || die "Delegated admin cannot be Administrator."

    local auth_user="$INITIAL_AUTH_USER"
    if samba-tool user show "$ADMIN_USER" >/dev/null 2>&1 &&
       samba-tool group listmembers "Domain Admins" 2>/dev/null | grep -Fxqi "$ADMIN_USER"; then
        auth_user="$ADMIN_USER"
    fi

    ensure_kerberos_ticket "$auth_user"

    if ! samba-tool user show "$ADMIN_USER" >/dev/null 2>&1; then
        printf '\nCreating delegated administrator %s. Samba will request its password.\n' "$ADMIN_USER"
        samba-tool user create "$ADMIN_USER" <"$INPUT_FD"
        change APPLIED "Created delegated admin=$ADMIN_USER"
    fi

    samba-tool group show AdministradoresTI >/dev/null 2>&1 ||
        samba-tool group add AdministradoresTI >/dev/null

    samba-tool group listmembers "Domain Admins" 2>/dev/null | grep -Fxqi "$ADMIN_USER" ||
        samba-tool group addmembers "Domain Admins" "$ADMIN_USER" >/dev/null
    samba-tool group listmembers AdministradoresTI 2>/dev/null | grep -Fxqi "$ADMIN_USER" ||
        samba-tool group addmembers AdministradoresTI "$ADMIN_USER" >/dev/null
    if samba-tool group show "Group Policy Creator Owners" >/dev/null 2>&1; then
        if ! samba-tool group listmembers "Group Policy Creator Owners" 2>/dev/null | grep -Fxqi "$ADMIN_USER"; then
            if confirm "Add '$ADMIN_USER' to 'Group Policy Creator Owners' for explicit GPO administration rights?" Y; then
                samba-tool group addmembers "Group Policy Creator Owners" "$ADMIN_USER" >/dev/null
                change APPLIED "Added $ADMIN_USER to Group Policy Creator Owners"
            fi
        fi
    fi

    KRB5CCNAME="$KRB5CCNAME" kdestroy >/dev/null 2>&1 || true
    printf '\nVerify delegated administrator credentials before disabling built-in Administrator.\n'
    ensure_kerberos_ticket "$ADMIN_USER"

    if command_exists kvno; then
        KRB5CCNAME="$KRB5CCNAME" kvno "ldap/${DC_FQDN}" >/dev/null
        result PASS "Delegated admin LDAP ticket" "ldap/${DC_FQDN}" "acquired"
    fi

    samba-tool group listmembers "Domain Admins" | grep -Fxqi "$ADMIN_USER" ||
        die "$ADMIN_USER is not confirmed in Domain Admins."
    result PASS "Delegated admin" "$ADMIN_USER" "Kerberos + Domain Admins verified"

    if ad_user_is_disabled Administrator; then
        result PASS "Built-in Administrator" "disabled" "disabled"
    else
        printf '\nBuilt-in Administrator is still enabled.\n'
        printf 'Store its recovery credentials securely before disabling it.\n'
        if confirm_high_risk "Disable built-in Administrator now that '$ADMIN_USER' is verified"; then
            samba-tool user disable Administrator
            ad_user_is_disabled Administrator || die "Administrator disable state could not be verified."
            result PASS "Built-in Administrator" "disabled" "delegated admin active"
            change APPLIED "Disabled built-in Administrator"
        else
            result WARN "Built-in Administrator" "still enabled" "optional recovery account"
        fi
    fi

    save_config
}

ensure_directory_baseline() {
    step "Directory/admin baseline"
    local base_dn ou grp
    base_dn="$(domain_dn "$DOMAIN")"

    for ou in Usuarios Equipos Grupos; do
        ldbsearch -H /var/lib/samba/private/sam.ldb -b "OU=${ou},${base_dn}" -s base dn >/dev/null 2>&1 ||
            samba-tool ou create "OU=${ou},${base_dn}" >/dev/null
    done

    for grp in Empleados AdministradoresTI; do
        samba-tool group show "$grp" >/dev/null 2>&1 || samba-tool group add "$grp" >/dev/null
    done

    harden_delegated_admin
}

write_gpo_sources() {
    mkdir -p "$GPO_DIR"

    cat >"${GPO_DIR}/user-baseline.json" <<'EOF'
[
  {
    "keyname": "Software\\Policies\\Microsoft\\Windows\\Control Panel\\Desktop",
    "valuename": "ScreenSaveActive",
    "class": "USER",
    "type": "REG_SZ",
    "data": "1"
  },
  {
    "keyname": "Software\\Policies\\Microsoft\\Windows\\Control Panel\\Desktop",
    "valuename": "ScreenSaveTimeOut",
    "class": "USER",
    "type": "REG_SZ",
    "data": "600"
  },
  {
    "keyname": "Software\\Policies\\Microsoft\\Windows\\Control Panel\\Desktop",
    "valuename": "ScreenSaverIsSecure",
    "class": "USER",
    "type": "REG_SZ",
    "data": "1"
  }
]
EOF

    cat >"${GPO_DIR}/machine-baseline.json" <<EOF
[
  {
    "keyname": "SOFTWARE\\\\Microsoft\\\\Windows\\\\CurrentVersion\\\\Policies\\\\System",
    "valuename": "LegalNoticeCaption",
    "class": "MACHINE",
    "type": "REG_SZ",
    "data": "${DOMAIN}"
  },
  {
    "keyname": "SOFTWARE\\\\Microsoft\\\\Windows\\\\CurrentVersion\\\\Policies\\\\System",
    "valuename": "LegalNoticeText",
    "class": "MACHINE",
    "type": "REG_SZ",
    "data": "Sistema perteneciente al dominio ${DOMAIN}. Acceso restringido a usuarios autorizados."
  },
  {
    "keyname": "SOFTWARE\\\\Policies\\\\Microsoft\\\\Windows NT\\\\DNSClient",
    "valuename": "EnableMulticast",
    "class": "MACHINE",
    "type": "REG_DWORD",
    "data": 0
  }
]
EOF

    chmod 600 "${GPO_DIR}"/*.json
    python3 -m json.tool "${GPO_DIR}/user-baseline.json" >/dev/null
    python3 -m json.tool "${GPO_DIR}/machine-baseline.json" >/dev/null
}


# ---------------------------------------------------------------------------
# Robust Samba GPO execution and guided LDAP attribute updates
# ---------------------------------------------------------------------------

samba_gpo() {
    # GPO operations use LDAP + SYSVOL/SMB and therefore need an authenticated
    # domain security context. Prefer the assistant's isolated Kerberos cache.
    if samba-tool --help 2>&1 | grep -Fq -- '--use-krb5-ccache'; then
        KRB5CCNAME="$KRB5CCNAME" samba-tool --use-krb5-ccache="$KRB5CCNAME" gpo "$@"
    else
        KRB5CCNAME="$KRB5CCNAME" samba-tool --use-kerberos=required gpo "$@"
    fi
}

capture_samba_gpo() {
    local __result_var="$1"
    shift
    local output rc

    # Commands evaluated by an if condition are intentionally exempt from
    # errexit/ERR cascading. We return one controlled error to the caller.
    if output="$(samba_gpo "$@" 2>&1)"; then
        rc=0
    else
        rc=$?
    fi

    printf -v "$__result_var" '%s' "$output"
    [[ $rc -eq 0 ]] || return "$rc"
}

gpo_readiness_diagnostics() {
    local reason="${1:-GPO operation failed}"
    local diag_dir="${RUN_ROOT}/gpo-diagnostics"
    mkdir -p "$diag_dir"

    printf '\n%bGPO DIAGNOSTICS%b\n' "$C_YELLOW" "$C_RESET" >&2
    printf '  %s\n' "$reason" >&2
    printf '  Kerberos principal : %s\n' "$(KRB5CCNAME="$KRB5CCNAME" klist 2>/dev/null | awk -F': ' '/Default principal:/{print $2;exit}' || printf 'none')" >&2

    if [[ -n "${ADMIN_USER:-}" ]]; then
        if samba-tool group listmembers 'Domain Admins' 2>/dev/null | grep -Fxqi "$ADMIN_USER"; then
            printf '  Domain Admins       : member\n' >&2
        else
            printf '  Domain Admins       : NOT a direct member\n' >&2
        fi
        if samba-tool group listmembers 'Group Policy Creator Owners' 2>/dev/null | grep -Fxqi "$ADMIN_USER"; then
            printf '  GPO Creator Owners  : member\n' >&2
        else
            printf '  GPO Creator Owners  : not a direct member\n' >&2
        fi
    fi

    if samba-tool ntacl sysvolcheck >"${diag_dir}/sysvolcheck.txt" 2>&1; then
        printf '  SYSVOL ACL check    : PASS\n' >&2
    else
        printf '  SYSVOL ACL check    : WARN/FAIL (see %s)\n' "${diag_dir}/sysvolcheck.txt" >&2
    fi

    local acl_output=""
    if samba-tool gpo aclcheck --help >/dev/null 2>&1; then
        if capture_samba_gpo acl_output aclcheck; then
            printf '%s\n' "$acl_output" >"${diag_dir}/gpo-aclcheck.txt"
            printf '  GPO LDAP/SYSVOL ACL : PASS\n' >&2
        else
            printf '%s\n' "$acl_output" >"${diag_dir}/gpo-aclcheck.txt"
            printf '  GPO LDAP/SYSVOL ACL : WARN/FAIL (see %s)\n' "${diag_dir}/gpo-aclcheck.txt" >&2
        fi
    fi

    printf '  Diagnostics         : %s\n' "$diag_dir" >&2
    printf '\nThe assistant will NOT run sysvolreset automatically. Use the advanced SYSVOL repair only after reviewing these diagnostics and taking a domain backup.\n' >&2
}

create_gpo_safe() {
    local name="$1" output="" guid="" rc=0
    ensure_kerberos_ticket "${ADMIN_USER:-Administrator}"

    if capture_samba_gpo output create "$name"; then
        printf '%s\n' "$output" >>"$LOG_FILE"
        printf '%s\n' "$output" >&2
    else
        rc=$?
        printf '%s\n' "$output" >>"$LOG_FILE"
        printf '\n%b[ERROR]%b Samba could not create GPO %q (rc=%s).\n' "$C_RED" "$C_RESET" "$name" "$rc" >&2
        [[ -n "$output" ]] && printf '%s\n' "$output" >&2
        gpo_readiness_diagnostics "Creation of GPO '$name' failed."
        return 1
    fi

    guid="$(grep -oE '\{[0-9A-Fa-f-]{36}\}' <<<"$output" | head -n1 || true)"
    if [[ -z "$guid" ]]; then
        guid="$(find_gpo_guid "$name")"
    fi
    [[ -n "$guid" ]] || {
        msg_warn "GPO '$name' appears to have been created, but its GUID could not be determined."
        return 1
    }
    printf '%s' "$guid"
}

user_dn_from_samba() {
    local user="$1"
    samba-tool user show "$user" 2>/dev/null | awk -F': ' '/^dn: /{print $2;exit}'
}

ldbmodify_with_assistant_ticket() {
    local ldif_file="$1"
    local url="ldap://${DC_FQDN}"
    if ldbmodify --help 2>&1 | grep -Fq -- '--use-krb5-ccache'; then
        KRB5CCNAME="$KRB5CCNAME" ldbmodify --use-krb5-ccache="$KRB5CCNAME" -H "$url" "$ldif_file"
    else
        KRB5CCNAME="$KRB5CCNAME" ldbmodify --use-kerberos=required -H "$url" "$ldif_file"
    fi
}

ldif_b64_line() {
    local attr="$1" value="$2"
    printf '%s:: %s\n' "$attr" "$(printf '%s' "$value" | base64 -w0)"
}

set_user_ldap_attribute() {
    local user="$1" attr="$2" value="$3"
    local dn file
    dn="$(user_dn_from_samba "$user")"
    [[ -n "$dn" ]] || { msg_warn "Unable to determine DN for user '$user'."; return 1; }
    file="${RUN_ROOT}/user-${user}-${attr}.ldif"

    {
        printf 'dn: %s\n' "$dn"
        printf 'changetype: modify\n'
        if [[ "$value" == '__DELETE__' ]]; then
            printf 'delete: %s\n-\n' "$attr"
        else
            printf 'replace: %s\n' "$attr"
            ldif_b64_line "$attr" "$value"
            printf -- '-\n'
        fi
    } >"$file"
    chmod 600 "$file"

    ensure_kerberos_ticket "${ADMIN_USER:-Administrator}"
    ldbmodify_with_assistant_ticket "$file" >/dev/null
}

force_user_password_change_next_logon() {
    local user="$1"
    local dn file
    dn="$(user_dn_from_samba "$user")"
    [[ -n "$dn" ]] || return 1
    file="${RUN_ROOT}/user-${user}-pwdlastset.ldif"
    cat >"$file" <<EOF
dn: $dn
changetype: modify
replace: pwdLastSet
pwdLastSet: 0
-
EOF
    chmod 600 "$file"
    ensure_kerberos_ticket "${ADMIN_USER:-Administrator}"
    ldbmodify_with_assistant_ticket "$file" >/dev/null
    change APPLIED "Forced password change at next logon for user=$user"
}

configure_user_business_attributes() {
    local user="$1" value
    printf '\nCurrent organizational/contact attributes:\n'
    samba-tool user show "$user" --attributes=description,department,title,company,physicalDeliveryOfficeName,telephoneNumber,mobile,profilePath,scriptPath,homeDirectory,homeDrive 2>/dev/null || true
    printf '\nFor each field: blank = keep current value, - = clear value.\n'

    local -a spec=(
        'description|Description'
        'department|Department'
        'title|Job title'
        'company|Company'
        'physicalDeliveryOfficeName|Office'
        'telephoneNumber|Telephone'
        'mobile|Mobile'
        'profilePath|Windows profile path'
        'scriptPath|Logon script path'
        'homeDirectory|Home directory'
        'homeDrive|Home drive (e.g. H:)'
    )
    local item attr label
    for item in "${spec[@]}"; do
        attr="${item%%|*}"
        label="${item#*|}"
        value="$(ask "$label" '')"
        [[ -z "$value" ]] && continue
        if [[ "$value" == '-' ]]; then
            set_user_ldap_attribute "$user" "$attr" '__DELETE__' || return 1
            change APPLIED "Cleared $attr for user=$user"
        else
            [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || { msg_warn "Newlines are not allowed in $label."; continue; }
            set_user_ldap_attribute "$user" "$attr" "$value" || return 1
            change APPLIED "Updated $attr for user=$user"
        fi
    done
}

configure_user_rfc2307_interactive() {
    local user="$1" uid gid home shell gecos
    samba-tool user addunixattrs --help >/dev/null 2>&1 || {
        msg_warn "Installed Samba does not support user addunixattrs."
        return 1
    }
    uid="$(ask 'RFC2307 UID number')"
    [[ "$uid" =~ ^[0-9]+$ ]] || { msg_warn 'UID must be numeric.'; return 1; }
    gid="$(ask 'RFC2307 GID number (blank=Domain Users gidNumber)' '')"
    home="$(ask 'Unix home directory' "/home/${NETBIOS_DOMAIN}/${user}")"
    shell="$(ask 'Login shell' '/bin/sh')"
    gecos="$(ask 'GECOS/comment' "$user")"

    local -a args=(user addunixattrs "$user" "$uid" "--unix-home=$home" "--login-shell=$shell" "--gecos=$gecos")
    [[ -n "$gid" ]] && args+=("--gid-number=$gid")
    samba-tool "${args[@]}"
    change APPLIED "Configured RFC2307 attributes for user=$user uid=$uid"
}

find_gpo_guid() {
    local name="$1" output=""
    if ! capture_samba_gpo output listall; then
        printf '%s\n' "$output" >>"$LOG_FILE"
        return 1
    fi
    awk -v target="$name" '
        /^[[:space:]]*GPO[[:space:]]*:/ {
            guid=$0; sub(/^[^:]*:[[:space:]]*/, "", guid); next
        }
        /^[[:space:]]*display name[[:space:]]*:/ {
            line=$0; sub(/^[^:]*:[[:space:]]*/, "", line)
            if (line==target) {print guid; exit}
        }' <<<"$output" | grep -oE '\{[0-9A-Fa-f-]{36}\}' | head -n1 || true
}

ensure_gpo() {
    local name="$1" guid=""
    guid="$(find_gpo_guid "$name" || true)"
    [[ -n "$guid" ]] && { printf '%s' "$guid"; return 0; }

    if ! guid="$(create_gpo_safe "$name")"; then
        return 1
    fi
    printf '%s' "$guid"
}

manage_gpos() {
    step "Group Policy"
    samba-tool gpo load --help >/dev/null 2>&1 ||
        { result SKIP "GPO load" "unsupported by installed Samba" "modern samba-tool"; return 0; }

    ensure_kerberos_ticket "$ADMIN_USER"
    write_gpo_sources

    local user_guid="" machine_guid="" base_dn output=""
    if ! user_guid="$(ensure_gpo 'DC - User Baseline')"; then
        result FAIL "User baseline GPO" "creation failed" "review GPO diagnostics"
        return 1
    fi
    if ! machine_guid="$(ensure_gpo 'DC - Computer Baseline')"; then
        result FAIL "Machine baseline GPO" "creation failed" "review GPO diagnostics"
        return 1
    fi
    base_dn="$(domain_dn "$DOMAIN")"

    backup_gpo_safe "$user_guid" || true
    backup_gpo_safe "$machine_guid" || true

    if ! capture_samba_gpo output load "$user_guid" --content="${GPO_DIR}/user-baseline.json"; then
        printf '%s\n' "$output" >&2; return 1
    fi
    if ! capture_samba_gpo output load "$machine_guid" --content="${GPO_DIR}/machine-baseline.json"; then
        printf '%s\n' "$output" >&2; return 1
    fi
    if ! capture_samba_gpo output setlink "$base_dn" "$user_guid"; then
        printf '%s\n' "$output" >&2; return 1
    fi
    if ! capture_samba_gpo output setlink "$base_dn" "$machine_guid"; then
        printf '%s\n' "$output" >&2; return 1
    fi

    samba-tool ntacl sysvolcheck >/dev/null 2>&1 \
        && result PASS "SYSVOL ACL" "consistent" "consistent" \
        || result WARN "SYSVOL ACL" "differences detected" "review before sysvolreset"
}

configure_ufw() {
    step "Firewall"
    [[ "$ENABLE_UFW" == yes ]] || { result SKIP "UFW" "disabled" "operator choice"; return 0; }
    require_cmd ufw "firewall" || return 0

    [[ -n "$AD_CLIENT_CIDR" && -n "$SSH_SOURCE" ]] || collect_network_policy

    printf 'Firewall plan:\n'
    printf '  AD services : %s <- %s via %s\n' "$DC_IP" "$AD_CLIENT_CIDR" "$AD_IFACE"
    printf '  SSH admin   : source=%s via %s (rate limited)\n' "$SSH_SOURCE" "$MGMT_IFACE"
    confirm "Apply/update UFW policy?" Y || { result SKIP "UFW" "unchanged" "operator skipped"; return 0; }

    if [[ -n "$MGMT_IFACE" ]]; then
        ufw limit in on "$MGMT_IFACE" from "$SSH_SOURCE" to any port 22 proto tcp >/dev/null
    else
        ufw limit from "$SSH_SOURCE" to any port 22 proto tcp >/dev/null
    fi

    ufw default deny incoming >/dev/null
    ufw default allow outgoing >/dev/null

    local p
    local tcp_ports=(53 88 135 139 389 445 464 636 3268 3269)
    local udp_ports=(53 88 123 137 138 389 464)

    for p in "${tcp_ports[@]}"; do
        ufw allow in on "$AD_IFACE" from "$AD_CLIENT_CIDR" to "$DC_IP" port "$p" proto tcp >/dev/null
    done
    for p in "${udp_ports[@]}"; do
        ufw allow in on "$AD_IFACE" from "$AD_CLIENT_CIDR" to "$DC_IP" port "$p" proto udp >/dev/null
    done

    # Samba/Windows RPC dynamic range. Restrict to trusted AD client network.
    ufw allow in on "$AD_IFACE" from "$AD_CLIENT_CIDR" to "$DC_IP" port 49152:65535 proto tcp >/dev/null
    ufw --force enable >/dev/null

    result PASS "UFW" "$(ufw status | head -n1)" "active"
    result PASS "AD firewall scope" "$AD_IFACE / $AD_CLIENT_CIDR" "trusted network only"
}

configure_fail2ban() {
    step "Brute-force protection"
    if ! command_exists fail2ban-client; then
        package_available fail2ban || { result SKIP "Fail2ban" "package unavailable" "optional"; return 0; }
        confirm "Install Fail2ban for SSH?" Y || { result SKIP "Fail2ban" "not installed" "optional"; return 0; }
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y fail2ban
    fi

    mkdir -p /etc/fail2ban/jail.d
    backup_file /etc/fail2ban/jail.d/90-debian-ad-assistant.conf
    cat >/etc/fail2ban/jail.d/90-debian-ad-assistant.conf <<'EOF'
[sshd]
enabled = true
backend = systemd
maxretry = 5
findtime = 10m
bantime = 1h
EOF
    systemctl enable --now fail2ban >/dev/null
    systemctl restart fail2ban
    fail2ban-client status sshd >/dev/null 2>&1 \
        && result PASS "Fail2ban sshd" "active" "active" \
        || result WARN "Fail2ban sshd" "jail not confirmed" "review logs"
}

configure_network_hardening() {
    step "Linux network hardening"
    local f="/etc/sysctl.d/99-debian-ad-hardening.conf"
    local rp=1
    [[ "$NETWORK_MODE" == single-nic ]] || rp=2

    confirm "Apply conservative network sysctl hardening?" Y ||
        { result SKIP "Network hardening" "unchanged" "operator skipped"; return 0; }

    backup_file "$f"
    cat >"$f" <<EOF
# Managed by ${SCRIPT_NAME}.
net.ipv4.conf.all.rp_filter=$rp
net.ipv4.conf.default.rp_filter=$rp
net.ipv4.icmp_echo_ignore_broadcasts=1
net.ipv4.conf.all.accept_source_route=0
net.ipv4.conf.default.accept_source_route=0
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.default.accept_redirects=0
net.ipv4.conf.all.secure_redirects=0
net.ipv4.conf.default.secure_redirects=0
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.default.send_redirects=0
net.ipv4.tcp_syncookies=1
EOF
    sysctl --system >/dev/null
    result PASS "Network sysctl" "$f" "applied"
}

create_domain_backup() {
    local progress="${1:-yes}"
    [[ "$progress" == yes ]] && step "Domain backup"
    [[ "$SAMBA_ROLE" == ad-dc ]] || { result SKIP "Domain backup" "not local AD/DC" "AD/DC required"; return 0; }

    ensure_kerberos_ticket "${ADMIN_USER:-Administrator}"
    mkdir -p "$DOMAIN_BACKUP_DIR"

    samba-tool domain backup online \
        --server="${DC_FQDN:-127.0.0.1}" \
        --targetdir="$DOMAIN_BACKUP_DIR" \
        --use-krb5-ccache="$KRB5CCNAME"
    chmod -R go-rwx "$DOMAIN_BACKUP_DIR"
    result PASS "Domain backup" "$DOMAIN_BACKUP_DIR" "completed"
}

validate_ad() {
    step "AD/DC validation"
    local fail=0 port srv ans
    discover_network_topology
    [[ -n "$DC_IP" ]] || DC_IP="${AD_IP:-$PRIMARY_IP}"

    audit_samba_boot_persistence

    systemctl is-active --quiet samba-ad-dc \
        && result PASS "samba-ad-dc" "active" "active" \
        || { result FAIL "samba-ad-dc" "inactive" "active"; fail=1; }

    testparm -s >/dev/null 2>&1 \
        && result PASS "smb.conf" "valid" "valid" \
        || { result FAIL "smb.conf" "invalid" "valid"; fail=1; }

    for port in 53 88 389 445 464; do
        if ss -lntup 2>/dev/null | grep -Eq ":${port}([[:space:]]|$)"; then
            result PASS "Listener $port" "present" "present"
        else
            result FAIL "Listener $port" "missing" "present"
            fail=1
        fi
    done

    if command_exists dig && [[ -n "$DOMAIN" && -n "$DC_FQDN" ]]; then
        dig +time=3 +tries=1 @127.0.0.1 +short A "$DC_FQDN" | grep -Fxq "$DC_IP" \
            && result PASS "DNS A" "$DC_FQDN -> $DC_IP" "correct" \
            || { result FAIL "DNS A" "unexpected/no answer" "$DC_FQDN -> $DC_IP"; fail=1; }

        for srv in _ldap._tcp _kerberos._tcp _kerberos._udp _kpasswd._udp; do
            ans="$(dig +time=3 +tries=1 @127.0.0.1 +short SRV "${srv}.${DOMAIN}" 2>/dev/null | tr '\n' ' ')"
            [[ -n "$ans" ]] \
                && result PASS "SRV $srv" "$ans" "present" \
                || { result FAIL "SRV $srv" "missing" "present"; fail=1; }
        done

        dig +time=4 +tries=1 @127.0.0.1 raw.githubusercontent.com A +short | grep -Eq '^[0-9]' \
            && result PASS "DNS forwarding" "external names resolve" "working" \
            || { result FAIL "DNS forwarding" "failed" "working"; fail=1; }
    fi

    getent ahostsv4 raw.githubusercontent.com >/dev/null 2>&1 \
        && result PASS "Host resolver" "external resolution works" "working" \
        || { result FAIL "Host resolver" "failed" "working"; fail=1; }

    samba-tool domain info "$DC_IP" >"${RUN_ROOT}/domain-info.txt" 2>&1 \
        && result PASS "Domain info" "reachable" "$DOMAIN" \
        || { result FAIL "Domain info" "failed" "reachable"; fail=1; }

    samba-tool dbcheck --cross-ncs >"${RUN_ROOT}/dbcheck.txt" 2>&1 \
        && result PASS "AD dbcheck" "completed" "clean/no fatal errors" \
        || result WARN "AD dbcheck" "reported issues" "review ${RUN_ROOT}/dbcheck.txt"

    samba-tool ntacl sysvolcheck >"${RUN_ROOT}/sysvolcheck.txt" 2>&1 \
        && result PASS "SYSVOL ACL" "consistent" "consistent" \
        || result WARN "SYSVOL ACL" "differences" "review ${RUN_ROOT}/sysvolcheck.txt"

    return "$fail"
}

audit_security_baseline() {
    step "Security baseline evidence"

    if command_exists sshd; then
        local rootlogin passauth
        rootlogin="$(sshd -T 2>/dev/null | awk '$1=="permitrootlogin"{print $2;exit}' || true)"
        passauth="$(sshd -T 2>/dev/null | awk '$1=="passwordauthentication"{print $2;exit}' || true)"
        [[ "$rootlogin" == no ]] \
            && result PASS "SSH root login" "disabled" "disabled" \
            || result WARN "SSH root login" "${rootlogin:-unknown}" "review"
        result INFO "SSH password auth" "${passauth:-unknown}" "environment-specific"
    fi

    command_exists aa-status && aa-status --enabled >/dev/null 2>&1 \
        && result PASS "AppArmor" "enabled" "enabled" || true

    command_exists fail2ban-client && fail2ban-client status sshd >/dev/null 2>&1 \
        && result PASS "Fail2ban sshd" "active" "active" \
        || result INFO "Fail2ban sshd" "not confirmed" "optional"

    audit_samba_boot_persistence
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

    local u
    for u in samba-ad-dc smbd nmbd winbind chrony systemd-resolved NetworkManager systemd-networkd-wait-online; do
        result INFO "service:$u" "$(safe_systemctl_state "$u")" "role-dependent"
    done

    command_exists ufw \
        && result INFO "UFW" "$(ufw status | head -n1)" "reviewed" \
        || result INFO "UFW" "not installed" "optional"
}

advanced_sysvol_repair() {
    printf '\nThis resets SYSVOL ACLs to Samba defaults.\n'
    create_domain_backup no
    confirm_high_risk "Run samba-tool ntacl sysvolreset" ||
        { result SKIP "SYSVOL reset" "cancelled" "unchanged"; return 0; }
    samba-tool ntacl sysvolreset
    samba-tool ntacl sysvolcheck
    change APPLIED "SYSVOL ACL reset"
}

list_domain_computers_status() {
    printf '\n%-24s %-36s %-16s %s\n' "COMPUTER" "DNS NAME" "IP" "NETWORK HINT"
    printf '%s\n' "---------------------------------------------------------------------------------------------"
    local account short dns ip hint

    while IFS= read -r account; do
        [[ -n "$account" ]] || continue
        short="${account%\$}"
        dns="$(samba-tool computer show "$account" --attributes=dNSHostName 2>/dev/null |
            awk -F': ' '/dNSHostName:/{print $2;exit}' | tr -d '\r' || true)"
        [[ -n "$dns" ]] || dns="${short,,}.${DOMAIN}"
        ip="$(getent ahostsv4 "$dns" 2>/dev/null | awk 'NR==1{print $1}' || true)"
        hint="no DNS address"
        if [[ -n "$ip" ]]; then
            hint="no :445 response"
            if command_exists timeout && timeout 1 bash -c "</dev/tcp/${ip}/445" >/dev/null 2>&1; then
                hint="SMB reachable"
            fi
        fi
        printf '%-24s %-36s %-16s %s\n' "$account" "$dns" "${ip:--}" "$hint"
    done < <(samba-tool computer list 2>/dev/null | sort)
}


# ---------------------------------------------------------------------------
# Indexed directory/GPO selectors and richer account workflows
# ---------------------------------------------------------------------------

samba_tool_option_supported() {
    local area="$1" action="$2" option="$3"
    samba-tool "$area" "$action" --help 2>&1 | grep -Fq -- "$option"
}

list_domain_groups_indexed() {
    local -a groups=()
    mapfile -t groups < <(samba-tool group list 2>/dev/null | sort)
    local i
    printf '\n' >&2
    ui_rule >&2
    printf '%b%b  DOMAIN GROUPS%b\n' "$C_BOLD" "$C_WHITE" "$C_RESET" >&2
    ui_rule >&2
    for i in "${!groups[@]}"; do
        printf '  %b[%2d]%b  %s\n' "$C_DIM" "$((i+1))" "$C_RESET" "${groups[$i]}" >&2
    done
    printf '  %b[N ]%b  Create a new group\n' "$C_GREEN" "$C_RESET" >&2
    printf '  %b[M ]%b  Enter group name manually\n' "$C_CYAN" "$C_RESET" >&2
    printf '  %b[0 ]%b  Cancel\n' "$C_RED" "$C_RESET" >&2
    ui_rule >&2
}

create_group_selector_item() {
    local group
    group="$(ask 'New group name')"
    [[ -n "$group" ]] || return 1

    if samba-tool group show "$group" >/dev/null 2>&1; then
        msg_warn "Group '$group' already exists."
        printf '%s' "$group"
        return 0
    fi

    # Keep group creation portable across Samba versions; advanced group
    # attributes remain available through the group editor afterwards.
    samba-tool group add "$group" >&2
    change APPLIED "Created AD group=$group"
    printf '%s' "$group"
}

select_domain_group() {
    local -a groups=()
    mapfile -t groups < <(samba-tool group list 2>/dev/null | sort)
    list_domain_groups_indexed

    local choice
    choice="$(ask 'Select group' '0')"
    case "${choice^^}" in
        0|"") return 1 ;;
        N) create_group_selector_item ;;
        M)
            local manual
            manual="$(ask 'Group name')"
            [[ -n "$manual" ]] || return 1
            samba-tool group show "$manual" >/dev/null 2>&1 || {
                msg_warn "Group '$manual' does not exist."
                return 1
            }
            printf '%s' "$manual"
            ;;
        *)
            [[ "$choice" =~ ^[0-9]+$ ]] || { msg_warn "Invalid group selection."; return 1; }
            (( choice >= 1 && choice <= ${#groups[@]} )) || { msg_warn "Group selection out of range."; return 1; }
            printf '%s' "${groups[$((choice-1))]}"
            ;;
    esac
}

list_user_groups_indexed() {
    local user="$1"
    local -a groups=()
    mapfile -t groups < <(samba-tool user getgroups "$user" 2>/dev/null | sort)
    local i
    printf '\n' >&2
    ui_rule >&2
    printf '%b%b  CURRENT MEMBERSHIPS: %s%b\n' "$C_BOLD" "$C_WHITE" "$user" "$C_RESET" >&2
    ui_rule >&2
    for i in "${!groups[@]}"; do
        printf '  %b[%2d]%b  %s\n' "$C_DIM" "$((i+1))" "$C_RESET" "${groups[$i]}" >&2
    done
    printf '  %b[0 ]%b  Cancel\n' "$C_RED" "$C_RESET" >&2
    ui_rule >&2
}

select_user_group_membership() {
    local user="$1"
    local -a groups=()
    mapfile -t groups < <(samba-tool user getgroups "$user" 2>/dev/null | sort)
    ((${#groups[@]})) || { msg_warn "No direct group memberships returned."; return 1; }
    list_user_groups_indexed "$user"
    local choice
    choice="$(ask 'Select membership' '0')"
    [[ "$choice" =~ ^[0-9]+$ ]] || return 1
    (( choice >= 1 && choice <= ${#groups[@]} )) || return 1
    printf '%s' "${groups[$((choice-1))]}"
}

manage_user_memberships() {
    local user="$1" choice group
    while true; do
        ui_menu_screen "USER GROUP MEMBERSHIPS" "Manage direct group memberships for $user"
        ui_menu_item "1" "Show memberships" "List the user's current direct groups"
        ui_menu_item "2" "Add to group" "Select an existing group or create a new one" "$C_GREEN"
        ui_menu_item "3" "Remove from group" "Select one current membership to revoke" "$C_YELLOW"
        ui_menu_item "4" "Set primary group" "Select an existing domain group"
        ui_menu_exit
        ui_rule

        choice="$(ask 'Select operation' '1')"
        case "$choice" in
            1) samba-tool user getgroups "$user" | sort; ui_pause ;;
            2)
                if group="$(select_domain_group)"; then
                    samba-tool group addmembers "$group" "$user"
                    change APPLIED "Added $user to group=$group"
                fi
                ui_pause
                ;;
            3)
                if group="$(select_user_group_membership "$user")"; then
                    if [[ "${group,,}" == "domain users" ]]; then
                        msg_warn "Domain Users is normally the primary group; removal is not offered here."
                    elif confirm "Remove '$user' from '$group'?" N; then
                        samba-tool group removemembers "$group" "$user"
                        change APPLIED "Removed $user from group=$group"
                    fi
                fi
                ui_pause
                ;;
            4)
                if group="$(select_domain_group)"; then
                    confirm "Set '$group' as primary group for '$user'?" N &&
                        samba-tool user setprimarygroup "$user" "$group"
                fi
                ui_pause
                ;;
            0) break ;;
            *) msg_warn "Invalid menu option."; ui_pause ;;
        esac
    done
}

list_ou_dns_indexed() {
    local base_dn
    base_dn="$(domain_dn "$DOMAIN")"
    local -a ous=()
    mapfile -t ous < <(
        ldbsearch -H /var/lib/samba/private/sam.ldb -b "$base_dn" \
            '(&(objectClass=organizationalUnit))' dn 2>/dev/null |
        awk -F': ' '/^dn: /{print $2}' | sort
    )
    local i
    printf '\n' >&2
    ui_rule >&2
    printf '%b%b  DIRECTORY TARGETS%b\n' "$C_BOLD" "$C_WHITE" "$C_RESET" >&2
    ui_rule >&2
    printf '  %b[ 1]%b  %s  %b(domain root)%b\n' "$C_DIM" "$C_RESET" "$base_dn" "$C_DIM" "$C_RESET" >&2
    for i in "${!ous[@]}"; do
        printf '  %b[%2d]%b  %s\n' "$C_DIM" "$((i+2))" "$C_RESET" "${ous[$i]}" >&2
    done
    printf '  %b[M ]%b  Enter DN manually\n' "$C_CYAN" "$C_RESET" >&2
    printf '  %b[0 ]%b  Cancel\n' "$C_RED" "$C_RESET" >&2
    ui_rule >&2
}

select_directory_target_dn() {
    local base_dn
    base_dn="$(domain_dn "$DOMAIN")"
    local -a ous=()
    mapfile -t ous < <(
        ldbsearch -H /var/lib/samba/private/sam.ldb -b "$base_dn" \
            '(&(objectClass=organizationalUnit))' dn 2>/dev/null |
        awk -F': ' '/^dn: /{print $2}' | sort
    )
    list_ou_dns_indexed
    local choice
    choice="$(ask 'Select directory target' '1')"
    case "${choice^^}" in
        0|"") return 1 ;;
        M)
            local manual
            manual="$(ask 'Container/OU DN')"
            [[ -n "$manual" ]] || return 1
            printf '%s' "$manual"
            ;;
        *)
            [[ "$choice" =~ ^[0-9]+$ ]] || { msg_warn "Invalid target selection."; return 1; }
            if (( choice == 1 )); then
                printf '%s' "$base_dn"
            elif (( choice >= 2 && choice <= ${#ous[@]} + 1 )); then
                printf '%s' "${ous[$((choice-2))]}"
            else
                msg_warn "Target selection out of range."
                return 1
            fi
            ;;
    esac
}

configure_user_profile_interactive() {
    local user="$1"
    local given surname initials display mail upn

    printf '\nNaming / logon attributes. Blank = keep current/skip.\n'
    samba-tool user show "$user" --attributes=givenName,sn,initials,displayName,mail,userPrincipalName 2>/dev/null || true

    given="$(ask 'Given name' '')"
    surname="$(ask 'Surname' '')"
    initials="$(ask 'Initials' '')"
    display="$(ask 'Display name' '')"
    mail="$(ask 'Mail address' '')"
    upn="$(ask 'UPN' '')"

    local -a args=(user rename "$user")
    [[ -n "$given" ]] && args+=("--given-name=$given")
    [[ -n "$surname" ]] && args+=("--surname=$surname")
    [[ -n "$initials" ]] && args+=("--initials=$initials")
    [[ -n "$display" ]] && args+=("--display-name=$display")
    [[ -n "$mail" ]] && args+=("--mail-address=$mail")
    [[ -n "$upn" ]] && args+=("--upn=$upn")

    if ((${#args[@]} > 3)); then
        samba-tool "${args[@]}"
        change APPLIED "Updated naming/profile attributes for user=$user"
    fi

    if confirm "Configure organizational/contact/profile-path attributes?" Y; then
        configure_user_business_attributes "$user"
    fi
}

create_user_interactive() {
    local user must_change enabled target group configure_rfc="no"
    local given surname initials display mail upn

    ui_menu_screen "CREATE DOMAIN USER" "Guided account creation with identity, password, OU, profile and memberships"
    user="$(ask 'sAMAccountName')"
    is_valid_ad_username "$user" || { msg_warn "Invalid/reserved account."; return 1; }
    samba-tool user show "$user" >/dev/null 2>&1 && { msg_warn "User '$user' already exists."; return 1; }

    given="$(ask 'Given name' '')"
    surname="$(ask 'Surname' '')"
    initials="$(ask 'Initials' '')"
    display="$(ask 'Display name' "${given}${given:+ }${surname}")"
    mail="$(ask 'Mail address' '')"
    upn="$(ask 'UPN' "${user}@${DOMAIN}")"

    must_change="yes"
    confirm "Require password change at first domain logon?" Y || must_change="no"
    enabled="yes"
    confirm "Create account enabled?" Y || enabled="no"

    target=""
    if confirm "Choose target OU/container before finishing account setup?" Y; then
        target="$(select_directory_target_dn || true)"
    fi

    confirm "Configure RFC2307 Unix attributes after creation?" N && configure_rfc="yes"

    printf '\n%bUSER CREATION PLAN%b\n' "$C_CYAN" "$C_RESET"
    printf '  Account        : %s\n' "$user"
    printf '  Display name   : %s\n' "${display:-<not set>}"
    printf '  UPN            : %s\n' "${upn:-<default/not set>}"
    printf '  Mail           : %s\n' "${mail:-<not set>}"
    printf '  Target         : %s\n' "${target:-default Users container}"
    printf '  Enabled        : %s\n' "$enabled"
    printf '  Change password: %s\n' "$must_change"
    printf '  RFC2307        : %s\n' "$configure_rfc"
    confirm "Create this domain account?" Y || return 0

    local -a args=(user add "$user")
    if [[ "$must_change" == "yes" ]] && samba_tool_option_supported user add "--must-change-at-next-login"; then
        args+=(--must-change-at-next-login)
    fi

    printf '\nSamba will request the initial password for %s.\n' "$user"
    samba-tool "${args[@]}" <"$INPUT_FD"
    change APPLIED "Created AD user=$user"

    local -a rename_args=(user rename "$user")
    [[ -n "$given" ]] && rename_args+=("--given-name=$given")
    [[ -n "$surname" ]] && rename_args+=("--surname=$surname")
    [[ -n "$initials" ]] && rename_args+=("--initials=$initials")
    [[ -n "$display" ]] && rename_args+=("--display-name=$display")
    [[ -n "$mail" ]] && rename_args+=("--mail-address=$mail")
    [[ -n "$upn" ]] && rename_args+=("--upn=$upn")
    ((${#rename_args[@]} > 3)) && samba-tool "${rename_args[@]}"

    if confirm "Configure department/title/company/office/telephone/profile paths now?" Y; then
        configure_user_business_attributes "$user"
    fi

    if [[ -n "$target" ]]; then
        samba-tool user move "$user" "$target"
        change APPLIED "Moved user=$user to $target"
    fi

    if [[ "$must_change" == "yes" ]] && ! samba_tool_option_supported user add "--must-change-at-next-login"; then
        if force_user_password_change_next_logon "$user"; then
            result PASS "First-logon password change" "$user / pwdLastSet=0" "required"
        else
            msg_warn "Unable to enforce first-logon password change automatically."
        fi
    fi

    [[ "$enabled" == "yes" ]] || samba-tool user disable "$user"

    if [[ "$configure_rfc" == "yes" ]]; then
        configure_user_rfc2307_interactive "$user" || true
    fi

    if confirm "Add '$user' to domain groups now?" Y; then
        while true; do
            group=""
            if group="$(select_domain_group)"; then
                samba-tool group addmembers "$group" "$user"
                change APPLIED "Added $user to group=$group"
            fi
            confirm "Add '$user' to another group?" N || break
        done
    fi

    printf '\n%bCreated user summary%b\n' "$C_GREEN" "$C_RESET"
    samba-tool user show "$user" --attributes=sAMAccountName,userPrincipalName,displayName,givenName,sn,mail,description,department,title,company,physicalDeliveryOfficeName,telephoneNumber,mobile,pwdLastSet,userAccountControl,distinguishedName 2>/dev/null || true
}

reset_user_password_interactive() {
    local user="$1" must_change="no"
    samba-tool user show "$user" >/dev/null 2>&1 || { msg_warn "User '$user' not found."; return 1; }
    confirm "Require password change at next logon?" Y && must_change="yes"

    printf '\nSamba will request the new password for %s.\n' "$user"
    if [[ "$must_change" == "yes" ]] && samba_tool_option_supported user setpassword "--must-change-at-next-login"; then
        samba-tool user setpassword "$user" --must-change-at-next-login <"$INPUT_FD"
    else
        samba-tool user setpassword "$user" <"$INPUT_FD"
        if [[ "$must_change" == "yes" ]]; then
            force_user_password_change_next_logon "$user" || {
                msg_warn "Password was changed, but first-logon password-change enforcement failed."
                return 1
            }
        fi
    fi
}

edit_user_interactive_menu() {
    local user="$1" choice target
    while true; do
        ui_menu_screen "EDIT USER" "Structured account operations for $user"
        ui_menu_item "1" "Naming / logon" "Given name, surname, initials, display name, mail and UPN"
        ui_menu_item "2" "Business / contact" "Description, department, title, company, office, phones and profile paths"
        ui_menu_item "3" "Move to OU" "Select a directory target by index"
        ui_menu_item "4" "Group memberships" "Add/remove memberships with indexed selectors"
        ui_menu_item "5" "Reset password" "Optionally require change at next logon"
        ui_menu_item "6" "Force password change" "Set pwdLastSet=0 without resetting password" "$C_YELLOW"
        ui_menu_item "7" "Enable account" "Allow authentication" "$C_GREEN"
        ui_menu_item "8" "Disable account" "Block authentication" "$C_YELLOW"
        ui_menu_item "9" "Unlock account" "Clear supported lockout state"
        ui_menu_item "10" "Delegation sensitive" "Set/unset UF_NOT_DELEGATED for privileged identities"
        ui_menu_item "11" "RFC2307 attributes" "UID/GID, Unix home, shell and GECOS"
        ui_menu_item "12" "Advanced object editor" "Open Samba raw AD object editor" "$C_YELLOW"
        ui_menu_exit
        ui_rule

        choice="$(ask 'Select operation' '1')"
        case "$choice" in
            1) configure_user_profile_interactive "$user"; ui_pause ;;
            2) configure_user_business_attributes "$user"; ui_pause ;;
            3)
                if target="$(select_directory_target_dn)"; then
                    samba-tool user move "$user" "$target"
                    change APPLIED "Moved user=$user to $target"
                fi
                ui_pause
                ;;
            4) manage_user_memberships "$user" ;;
            5) reset_user_password_interactive "$user"; ui_pause ;;
            6) force_user_password_change_next_logon "$user"; ui_pause ;;
            7) samba-tool user enable "$user"; ui_pause ;;
            8)
                case "${user,,}" in administrator|krbtgt) msg_warn "Protected built-in account."; ui_pause; continue ;; esac
                confirm_high_risk "Disable AD user '$user'" && samba-tool user disable "$user"
                ui_pause
                ;;
            9)
                samba-tool user unlock --help >/dev/null 2>&1 \
                    && samba-tool user unlock "$user" \
                    || msg_warn "user unlock is unsupported by installed Samba."
                ui_pause
                ;;
            10)
                if samba-tool user sensitive --help >/dev/null 2>&1; then
                    samba-tool user sensitive "$user" show || true
                    local sensitive_choice
                    sensitive_choice="$(ask 'Set account as sensitive/not delegatable? [on/off]' 'on')"
                    case "$sensitive_choice" in
                        on|off) samba-tool user sensitive "$user" "$sensitive_choice" ;;
                        *) msg_warn "Expected on or off." ;;
                    esac
                else
                    msg_warn "user sensitive is unsupported by installed Samba."
                fi
                ui_pause
                ;;
            11) configure_user_rfc2307_interactive "$user"; ui_pause ;;
            12) samba-tool user edit "$user"; ui_pause ;;
            0) break ;;
            *) msg_warn "Invalid menu option."; ui_pause ;;
        esac
    done
}

gpo_inventory_tsv() {
    local output=""
    if ! capture_samba_gpo output listall; then
        printf '%s\n' "$output" >>"$LOG_FILE"
        return 1
    fi
    awk '
        /^[[:space:]]*GPO[[:space:]]*:/ {
            guid=$0
            sub(/^[^:]*:[[:space:]]*/, "", guid)
            next
        }
        /^[[:space:]]*display name[[:space:]]*:/ {
            name=$0
            sub(/^[^:]*:[[:space:]]*/, "", name)
            if (guid != "") {
                printf "%s\t%s\n", guid, name
                guid=""
            }
        }' <<<"$output"
}

show_gpo_inventory_indexed() {
    local -a entries=()
    mapfile -t entries < <(gpo_inventory_tsv)
    local i guid name
    printf '\n'
    ui_rule
    printf '%b%b  GROUP POLICY OBJECTS%b\n' "$C_BOLD" "$C_WHITE" "$C_RESET"
    ui_rule
    if ((${#entries[@]} == 0)); then
        printf '  %bNo GPOs returned.%b\n' "$C_YELLOW" "$C_RESET"
    else
        for i in "${!entries[@]}"; do
            guid="${entries[$i]%%$'\t'*}"
            name="${entries[$i]#*$'\t'}"
            printf '  %b[%2d]%b  %-42s %s\n' "$C_DIM" "$((i+1))" "$C_RESET" "$name" "$guid"
        done
    fi
    ui_rule
}

select_gpo_guid() {
    local -a entries=()
    mapfile -t entries < <(gpo_inventory_tsv)
    local i guid name
    printf '\n' >&2
    ui_rule >&2
    printf '%b%b  SELECT GROUP POLICY OBJECT%b\n' "$C_BOLD" "$C_WHITE" "$C_RESET" >&2
    ui_rule >&2
    for i in "${!entries[@]}"; do
        guid="${entries[$i]%%$'\t'*}"
        name="${entries[$i]#*$'\t'}"
        printf '  %b[%2d]%b  %-38s %s\n' "$C_DIM" "$((i+1))" "$C_RESET" "$name" "$guid" >&2
    done
    printf '  %b[M ]%b  Enter GUID manually\n' "$C_CYAN" "$C_RESET" >&2
    printf '  %b[0 ]%b  Cancel\n' "$C_RED" "$C_RESET" >&2
    ui_rule >&2

    local choice manual
    choice="$(ask 'Select GPO' '0')"
    case "${choice^^}" in
        0|"") return 1 ;;
        M)
            manual="$(ask 'GPO GUID')"
            [[ -n "$manual" ]] || return 1
            printf '%s' "$manual"
            ;;
        *)
            [[ "$choice" =~ ^[0-9]+$ ]] || { msg_warn "Invalid GPO selection."; return 1; }
            (( choice >= 1 && choice <= ${#entries[@]} )) || { msg_warn "GPO selection out of range."; return 1; }
            printf '%s' "${entries[$((choice-1))]%%$'\t'*}"
            ;;
    esac
}

backup_gpo_safe() {
    local guid="$1" dir output=""
    samba-tool gpo backup --help >/dev/null 2>&1 || return 0
    dir="${RUN_ROOT}/gpo-backup"
    mkdir -p "$dir"
    if capture_samba_gpo output backup "$guid" --tmpdir="$dir"; then
        result PASS "GPO backup" "$guid -> $dir" "created"
        return 0
    fi
    printf '%s\n' "$output" >>"$LOG_FILE"
    msg_warn "GPO backup failed for $guid; continuing only because caller allowed best-effort backup."
    return 1
}

write_security_gpo_catalog_sources() {
    mkdir -p "$GPO_DIR"

    cat >"${GPO_DIR}/sec-powershell-logging.json" <<'EOF'
[
  {"keyname":"SOFTWARE\\Policies\\Microsoft\\Windows\\PowerShell\\ScriptBlockLogging","valuename":"EnableScriptBlockLogging","class":"MACHINE","type":"REG_DWORD","data":1},
  {"keyname":"SOFTWARE\\Policies\\Microsoft\\Windows\\PowerShell\\ModuleLogging","valuename":"EnableModuleLogging","class":"MACHINE","type":"REG_DWORD","data":1},
  {"keyname":"SOFTWARE\\Policies\\Microsoft\\Windows\\PowerShell\\ModuleLogging\\ModuleNames","valuename":"*","class":"MACHINE","type":"REG_SZ","data":"*"}
]
EOF

    cat >"${GPO_DIR}/sec-disable-llmnr.json" <<'EOF'
[
  {"keyname":"SOFTWARE\\Policies\\Microsoft\\Windows NT\\DNSClient","valuename":"EnableMulticast","class":"MACHINE","type":"REG_DWORD","data":0}
]
EOF

    cat >"${GPO_DIR}/sec-smb-guest.json" <<'EOF'
[
  {"keyname":"SOFTWARE\\Policies\\Microsoft\\Windows\\LanmanWorkstation","valuename":"AllowInsecureGuestAuth","class":"MACHINE","type":"REG_DWORD","data":0}
]
EOF

    cat >"${GPO_DIR}/sec-rdp-nla.json" <<'EOF'
[
  {"keyname":"SOFTWARE\\Policies\\Microsoft\\Windows NT\\Terminal Services","valuename":"UserAuthentication","class":"MACHINE","type":"REG_DWORD","data":1}
]
EOF

    cat >"${GPO_DIR}/sec-screen-lock.json" <<'EOF'
[
  {"keyname":"Software\\Policies\\Microsoft\\Windows\\Control Panel\\Desktop","valuename":"ScreenSaveActive","class":"USER","type":"REG_SZ","data":"1"},
  {"keyname":"Software\\Policies\\Microsoft\\Windows\\Control Panel\\Desktop","valuename":"ScreenSaveTimeOut","class":"USER","type":"REG_SZ","data":"600"},
  {"keyname":"Software\\Policies\\Microsoft\\Windows\\Control Panel\\Desktop","valuename":"ScreenSaverIsSecure","class":"USER","type":"REG_SZ","data":"1"}
]
EOF

    cat >"${GPO_DIR}/sec-disable-alwaysinstallelevated.json" <<'EOF'
[
  {"keyname":"SOFTWARE\\Policies\\Microsoft\\Windows\\Installer","valuename":"AlwaysInstallElevated","class":"MACHINE","type":"REG_DWORD","data":0},
  {"keyname":"Software\\Policies\\Microsoft\\Windows\\Installer","valuename":"AlwaysInstallElevated","class":"USER","type":"REG_DWORD","data":0}
]
EOF

    cat >"${GPO_DIR}/sec-legal-notice.json" <<EOF
[
  {"keyname":"SOFTWARE\\\\Microsoft\\\\Windows\\\\CurrentVersion\\\\Policies\\\\System","valuename":"LegalNoticeCaption","class":"MACHINE","type":"REG_SZ","data":"${DOMAIN}"},
  {"keyname":"SOFTWARE\\\\Microsoft\\\\Windows\\\\CurrentVersion\\\\Policies\\\\System","valuename":"LegalNoticeText","class":"MACHINE","type":"REG_SZ","data":"Sistema perteneciente al dominio ${DOMAIN}. Acceso restringido a usuarios autorizados."}
]
EOF

    chmod 600 "${GPO_DIR}"/sec-*.json
    local f
    for f in "${GPO_DIR}"/sec-*.json; do
        python3 -m json.tool "$f" >/dev/null
    done
}

deploy_security_gpo_template() {
    local id="$1" target_dn="$2"
    local name file guid="" output=""

    case "$id" in
        1) name="SEC - PowerShell Logging"; file="${GPO_DIR}/sec-powershell-logging.json" ;;
        2) name="SEC - Disable LLMNR"; file="${GPO_DIR}/sec-disable-llmnr.json" ;;
        3) name="SEC - SMB Guest Hardening"; file="${GPO_DIR}/sec-smb-guest.json" ;;
        4) name="SEC - RDP Network Level Authentication"; file="${GPO_DIR}/sec-rdp-nla.json" ;;
        5) name="SEC - Secure Screen Lock"; file="${GPO_DIR}/sec-screen-lock.json" ;;
        6) name="SEC - Disable AlwaysInstallElevated"; file="${GPO_DIR}/sec-disable-alwaysinstallelevated.json" ;;
        7) name="SEC - Authorized Use Notice"; file="${GPO_DIR}/sec-legal-notice.json" ;;
        *) msg_warn "Unknown security GPO template: $id"; return 1 ;;
    esac

    guid="$(find_gpo_guid "$name" || true)"
    if [[ -n "$guid" ]]; then
        backup_gpo_safe "$guid" || true
    else
        if ! guid="$(ensure_gpo "$name")"; then
            msg_warn "Unable to create/find GPO '$name'. No policy or link was applied."
            return 1
        fi
    fi

    if ! capture_samba_gpo output load "$guid" --content="$file"; then
        printf '%s\n' "$output" >&2
        msg_warn "Failed to load policy content into '$name'."
        return 1
    fi
    if ! capture_samba_gpo output setlink "$target_dn" "$guid"; then
        printf '%s\n' "$output" >&2
        msg_warn "Policy was updated but could not be linked to $target_dn."
        return 1
    fi

    change APPLIED "Security GPO '$name' guid=$guid target=$target_dn"
    result PASS "$name" "$guid linked to $target_dn" "deployed"
}

security_gpo_catalog_menu() {
    ensure_kerberos_ticket "${ADMIN_USER:-Administrator}"
    samba-tool gpo load --help >/dev/null 2>&1 ||
        { msg_warn "Installed Samba does not support gpo load."; return 1; }

    write_security_gpo_catalog_sources

    while true; do
        ui_menu_screen "SECURITY GPO CATALOG" "Curated registry-based policies for common domain hardening"
        ui_menu_item "1" "PowerShell Logging" "Script Block + Module Logging"
        ui_menu_item "2" "Disable LLMNR" "Reduce multicast name-resolution poisoning exposure"
        ui_menu_item "3" "SMB Guest Hardening" "Disable insecure guest authentication"
        ui_menu_item "4" "RDP NLA" "Require Network Level Authentication"
        ui_menu_item "5" "Secure Screen Lock" "10-minute secure screensaver for users"
        ui_menu_item "6" "Disable AlwaysInstallElevated" "Disable elevated MSI policy for machine + user"
        ui_menu_item "7" "Authorized Use Notice" "Domain legal/authorized-use banner"
        ui_menu_item "A" "Recommended starter pack" "Deploy 1,2,3,4,5,6"
        ui_menu_item "D" "Domain password policy" "Review/configure Samba complexity + lockout settings"
        ui_menu_exit
        ui_rule

        local choice target id
        choice="$(ask 'Select policy' '0')"
        case "${choice^^}" in
            0) break ;;
            A)
                if target="$(select_directory_target_dn)"; then
                    for id in 1 2 3 4 5 6; do
                        if ! deploy_security_gpo_template "$id" "$target"; then
                            msg_warn "Starter-pack policy $id failed; remaining policies will still be attempted."
                        fi
                    done
                    samba-tool ntacl sysvolcheck >/dev/null 2>&1 || msg_warn "SYSVOL ACL differences detected after GPO deployment."
                fi
                ui_pause
                ;;
            D)
                domain_password_policy_menu
                ;;
            1|2|3|4|5|6|7)
                if target="$(select_directory_target_dn)"; then
                    deploy_security_gpo_template "$choice" "$target"
                    samba-tool ntacl sysvolcheck >/dev/null 2>&1 || msg_warn "SYSVOL ACL differences detected."
                fi
                ui_pause
                ;;
            *) msg_warn "Invalid catalog selection."; ui_pause ;;
        esac
    done
}

domain_password_policy_menu() {
    while true; do
        ui_menu_screen "DOMAIN PASSWORD & LOCKOUT POLICY" "Samba domain-wide password policy; separate from registry-based GPO templates"
        ui_menu_item "1" "Show current policy" "Display complexity, history, ages and lockout configuration"
        ui_menu_item "2" "Starter baseline" "Complexity on, history 24, length 12, lockout 5/30/30; review organizational policy" "$C_YELLOW"
        ui_menu_item "3" "Custom values" "Enter supported samba-tool passwordsettings values"
        ui_menu_exit
        ui_rule

        local choice
        choice="$(ask 'Select operation' '1')"
        case "$choice" in
            1) samba-tool domain passwordsettings show; ui_pause ;;
            2)
                if confirm_high_risk "Apply starter domain password baseline: complexity=on, history=24, min-length=12, lockout threshold=5, duration/reset=30"; then
                    samba-tool domain passwordsettings set \
                        --complexity=on \
                        --history-length=24 \
                        --min-pwd-length=12 \
                        --account-lockout-threshold=5 \
                        --account-lockout-duration=30 \
                        --reset-account-lockout-after=30
                    change APPLIED "Applied recommended domain password/lockout policy"
                fi
                ui_pause
                ;;
            3)
                local complexity history minlen minage maxage threshold duration reset
                complexity="$(ask 'Complexity [on/off/default]' 'on')"
                history="$(ask 'History length' '24')"
                minlen="$(ask 'Minimum password length' '12')"
                minage="$(ask 'Minimum password age (days)' '1')"
                maxage="$(ask 'Maximum password age (days)' '90')"
                threshold="$(ask 'Lockout threshold' '5')"
                duration="$(ask 'Lockout duration (minutes)' '30')"
                reset="$(ask 'Reset bad-attempt counter after (minutes)' '30')"

                printf '\nProposed domain password policy:\n'
                printf '  complexity=%s history=%s minlen=%s minage=%s maxage=%s\n' "$complexity" "$history" "$minlen" "$minage" "$maxage"
                printf '  lockout threshold=%s duration=%s reset=%s\n' "$threshold" "$duration" "$reset"
                if confirm_high_risk "Apply custom domain password/lockout policy"; then
                    samba-tool domain passwordsettings set \
                        "--complexity=$complexity" \
                        "--history-length=$history" \
                        "--min-pwd-length=$minlen" \
                        "--min-pwd-age=$minage" \
                        "--max-pwd-age=$maxage" \
                        "--account-lockout-threshold=$threshold" \
                        "--account-lockout-duration=$duration" \
                        "--reset-account-lockout-after=$reset"
                    change APPLIED "Applied custom domain password/lockout policy"
                fi
                ui_pause
                ;;
            0) break ;;
            *) msg_warn "Invalid menu option."; ui_pause ;;
        esac
    done
}

user_admin_menu() {
    while true; do
        ui_menu_screen "USER DIRECTORY" "Structured account lifecycle, profile, password and group operations"
        ui_menu_item "1" "List users" "Inventory all domain user accounts"
        ui_menu_item "2" "Inspect user" "Show directory attributes for one account"
        ui_menu_item "3" "Create user" "Guided creation with first-logon password and groups" "$C_GREEN"
        ui_menu_item "4" "Edit user" "Profile, OU, groups, password and account state"
        ui_menu_item "5" "Reset password" "Optionally require password change at next logon"
        ui_menu_item "6" "Group memberships" "Indexed add/remove membership workflow"
        ui_menu_item "7" "Enable user" "Re-enable a disabled identity" "$C_GREEN"
        ui_menu_item "8" "Disable user" "Block interactive authentication" "$C_YELLOW"
        ui_menu_item "9" "Unlock user" "Clear supported lockout state"
        ui_menu_item "10" "Delete user" "Permanently remove an identity" "$C_RED"
        ui_menu_exit
        ui_rule

        local choice user
        choice="$(ask 'Select operation' '1')"
        case "$choice" in
            1) samba-tool user list | sort; ui_pause ;;
            2) user="$(ask 'User')"; samba-tool user show "$user"; ui_pause ;;
            3) create_user_interactive; ui_pause ;;
            4)
                user="$(ask 'User')"
                samba-tool user show "$user" >/dev/null 2>&1 \
                    && edit_user_interactive_menu "$user" \
                    || { msg_warn "User '$user' not found."; ui_pause; }
                ;;
            5)
                user="$(ask 'User')"
                reset_user_password_interactive "$user"
                ui_pause
                ;;
            6)
                user="$(ask 'User')"
                manage_user_memberships "$user"
                ;;
            7) user="$(ask 'User')"; samba-tool user enable "$user"; ui_pause ;;
            8)
                user="$(ask 'User')"
                case "${user,,}" in administrator|krbtgt) msg_warn "Protected built-in account."; ui_pause; continue ;; esac
                confirm_high_risk "Disable AD user '$user'" && samba-tool user disable "$user"
                ui_pause
                ;;
            9)
                user="$(ask 'User')"
                samba-tool user unlock --help >/dev/null 2>&1 \
                    && samba-tool user unlock "$user" \
                    || msg_warn "user unlock is unsupported by installed Samba."
                ui_pause
                ;;
            10)
                user="$(ask 'User')"
                case "${user,,}" in administrator|guest|krbtgt) msg_warn "Refusing protected built-in account deletion."; ui_pause; continue ;; esac
                confirm_high_risk "PERMANENTLY delete AD user '$user'" && samba-tool user delete "$user"
                ui_pause
                ;;
            0) break ;;
            *) msg_warn "Invalid menu option."; ui_pause ;;
        esac
    done
}

group_admin_menu() {
    while true; do
        ui_menu_screen "GROUP DIRECTORY" "Indexed group selection, membership management and delegation"
        ui_menu_item "1" "List groups" "Indexed inventory of domain groups"
        ui_menu_item "2" "Inspect group" "Select a group then show its directory object"
        ui_menu_item "3" "Create group" "Create a new domain group" "$C_GREEN"
        ui_menu_item "4" "Edit group" "Select group then open Samba object editor"
        ui_menu_item "5" "List members" "Select group then display membership"
        ui_menu_item "6" "Add member" "Select group, then specify account" "$C_GREEN"
        ui_menu_item "7" "Remove member" "Select group, then revoke account membership" "$C_YELLOW"
        ui_menu_item "8" "Delete group" "Select and permanently delete non-core group" "$C_RED"
        ui_menu_exit
        ui_rule

        local choice group member
        choice="$(ask 'Select operation' '1')"
        case "$choice" in
            1) list_domain_groups_indexed; ui_pause ;;
            2)
                group="$(select_domain_group)" || { ui_pause; continue; }
                samba-tool group show "$group"
                ui_pause
                ;;
            3) create_group_selector_item >/dev/null; ui_pause ;;
            4)
                group="$(select_domain_group)" || { ui_pause; continue; }
                samba-tool group edit "$group"
                ui_pause
                ;;
            5)
                group="$(select_domain_group)" || { ui_pause; continue; }
                samba-tool group listmembers "$group"
                ui_pause
                ;;
            6)
                group="$(select_domain_group)" || { ui_pause; continue; }
                member="$(ask 'User/group/computer account')"
                samba-tool group addmembers "$group" "$member"
                ui_pause
                ;;
            7)
                group="$(select_domain_group)" || { ui_pause; continue; }
                member="$(ask 'User/group/computer account')"
                confirm "Remove '$member' from '$group'?" N && samba-tool group removemembers "$group" "$member"
                ui_pause
                ;;
            8)
                group="$(select_domain_group)" || { ui_pause; continue; }
                case "${group,,}" in
                    "domain admins"|"domain users"|"domain controllers"|"enterprise admins"|"schema admins"|"administrators")
                        msg_warn "Protected domain group."; ui_pause; continue ;;
                esac
                confirm_high_risk "PERMANENTLY delete group '$group'" && samba-tool group delete "$group"
                ui_pause
                ;;
            0) break ;;
            *) msg_warn "Invalid menu option."; ui_pause ;;
        esac
    done
}

computer_admin_menu() {
    while true; do
        ui_menu_screen "DOMAIN COMPUTERS" "Joined computer accounts and best-effort network presence"
        ui_menu_item "1" "List accounts" "Inventory computer objects joined to the domain"
        ui_menu_item "2" "Network presence" "Resolve DNS and probe SMB/445 availability"
        ui_menu_item "3" "Inspect computer" "Show one computer object's attributes"
        ui_menu_item "4" "Edit computer" "Open object editor when supported"
        ui_menu_item "5" "Delete stale account" "Remove an obsolete computer object" "$C_RED"
        ui_menu_exit
        ui_rule
        local choice computer
        choice="$(ask 'Select operation' '1')"
        case "$choice" in
            1) samba-tool computer list | sort; ui_pause ;;
            2) list_domain_computers_status; ui_pause ;;
            3) computer="$(ask 'Computer account')"; samba-tool computer show "$computer"; ui_pause ;;
            4)
                computer="$(ask 'Computer account')"
                samba-tool computer edit --help >/dev/null 2>&1 \
                    && samba-tool computer edit "$computer" \
                    || msg_warn "computer edit is unsupported."
                ui_pause
                ;;
            5)
                computer="$(ask 'Computer account')"
                confirm_high_risk "Delete computer account '$computer'" && samba-tool computer delete "$computer"
                ui_pause
                ;;
            0) break ;;
            *) msg_warn "Invalid menu option."; ui_pause ;;
        esac
    done
}

permissions_admin_menu() {
    while true; do
        ui_menu_screen "ACCESS & DELEGATION" "Indexed memberships plus advanced directory-service ACL operations"
        ui_menu_item "1" "User groups" "Show direct group memberships for a user"
        ui_menu_item "2" "Group members" "Select group then enumerate principals"
        ui_menu_item "3" "Grant membership" "Select group, then add account" "$C_GREEN"
        ui_menu_item "4" "Revoke membership" "Select group, then remove account" "$C_YELLOW"
        ui_menu_item "5" "Manage user groups" "Full indexed user membership workflow"
        ui_menu_item "6" "Inspect DS ACL" "Read access-control entries on a directory object"
        ui_menu_item "7" "Add DS ACL ACE" "Advanced: apply a raw SDDL ACE" "$C_YELLOW"
        ui_menu_item "8" "Delete DS ACL ACE" "Advanced: remove raw SDDL ACE when supported" "$C_RED"
        ui_menu_exit
        ui_rule

        local choice user group member dn sddl
        choice="$(ask 'Select operation' '1')"
        case "$choice" in
            1) user="$(ask 'User')"; samba-tool user getgroups "$user"; ui_pause ;;
            2)
                group="$(select_domain_group)" || { ui_pause; continue; }
                samba-tool group listmembers "$group"
                ui_pause
                ;;
            3)
                group="$(select_domain_group)" || { ui_pause; continue; }
                member="$(ask 'Account')"
                samba-tool group addmembers "$group" "$member"
                ui_pause
                ;;
            4)
                group="$(select_domain_group)" || { ui_pause; continue; }
                member="$(ask 'Account')"
                confirm "Remove '$member' from '$group'?" N && samba-tool group removemembers "$group" "$member"
                ui_pause
                ;;
            5) user="$(ask 'User')"; manage_user_memberships "$user" ;;
            6) dn="$(ask 'Object DN')"; samba-tool dsacl get --objectdn="$dn"; ui_pause ;;
            7)
                dn="$(ask 'Object DN')"; sddl="$(ask 'ACE SDDL')"
                confirm_high_risk "Add raw DS ACL ACE to '$dn'" &&
                    samba-tool dsacl set --objectdn="$dn" --sddl="$sddl"
                ui_pause
                ;;
            8)
                dn="$(ask 'Object DN')"; sddl="$(ask 'ACE SDDL')"
                samba-tool dsacl delete --help >/dev/null 2>&1 \
                    && { confirm_high_risk "Delete DS ACL ACE from '$dn'" &&
                         samba-tool dsacl delete --objectdn="$dn" --sddl="$sddl"; } \
                    || msg_warn "dsacl delete is unsupported."
                ui_pause
                ;;
            0) break ;;
            *) msg_warn "Invalid menu option."; ui_pause ;;
        esac
    done
}

gpo_admin_menu() {
    ensure_kerberos_ticket "${ADMIN_USER:-Administrator}"

    while true; do
        ui_menu_screen "GROUP POLICY CONTROL" "Indexed GPO lifecycle, curated security templates, scope, diagnostics and backup"
        ui_menu_item "1" "List GPOs + GUIDs" "Indexed inventory; no manual GUID lookup required"
        ui_menu_item "2" "Inspect GPO" "Select an existing GPO by index"
        ui_menu_item "3" "Create GPO" "Create an empty policy and optionally link it" "$C_GREEN"
        ui_menu_item "4" "Security GPO catalog" "Deploy common curated domain hardening policies" "$C_GREEN"
        ui_menu_item "5" "Load JSON policy" "Select GPO then merge registry policy payload"
        ui_menu_item "6" "List containers" "Select GPO then show linked containers"
        ui_menu_item "7" "Link / update" "Select GPO and domain/OU target" "$C_GREEN"
        ui_menu_item "8" "Remove link" "Select GPO and domain/OU target" "$C_YELLOW"
        ui_menu_item "9" "Backup GPO" "Select and export one GPO"
        ui_menu_item "10" "GPO readiness" "Kerberos, operator membership and SYSVOL/GPO ACL diagnostics"
        ui_menu_item "11" "Delete GPO" "Backup/domain-backup then permanently delete" "$C_RED"
        ui_menu_item "12" "Legacy baseline pair" "Create/update original assistant user+machine baselines"
        ui_menu_exit
        ui_rule

        local choice guid name file dn output=""
        choice="$(ask 'Select operation' '1')"
        case "$choice" in
            1) show_gpo_inventory_indexed; ui_pause ;;
            2)
                guid="$(select_gpo_guid)" || { ui_pause; continue; }
                if capture_samba_gpo output show "$guid"; then printf '%s\n' "$output"; else printf '%s\n' "$output" >&2; fi
                ui_pause
                ;;
            3)
                name="$(ask 'GPO display name')"
                [[ -n "$name" ]] || { msg_warn "GPO name is required."; ui_pause; continue; }
                if guid="$(create_gpo_safe "$name")"; then
                    printf '\nCreated GUID: %s\n' "$guid"
                    if confirm "Link this GPO now?" Y && dn="$(select_directory_target_dn)"; then
                        if ! capture_samba_gpo output setlink "$dn" "$guid"; then
                            printf '%s\n' "$output" >&2
                            msg_warn "GPO was created but linking failed."
                        fi
                    fi
                else
                    msg_warn "GPO creation failed cleanly; see diagnostics above."
                fi
                ui_pause
                ;;
            4) security_gpo_catalog_menu ;;
            5)
                guid="$(select_gpo_guid)" || { ui_pause; continue; }
                file="$(ask 'JSON policy file')"
                [[ -f "$file" ]] || { msg_warn "File not found."; ui_pause; continue; }
                python3 -m json.tool "$file" >/dev/null || { msg_warn "Invalid JSON."; ui_pause; continue; }
                backup_gpo_safe "$guid" || true
                if ! capture_samba_gpo output load "$guid" --content="$file"; then printf '%s\n' "$output" >&2; fi
                ui_pause
                ;;
            6)
                guid="$(select_gpo_guid)" || { ui_pause; continue; }
                if capture_samba_gpo output listcontainers "$guid"; then printf '%s\n' "$output"; else printf '%s\n' "$output" >&2; fi
                ui_pause
                ;;
            7)
                guid="$(select_gpo_guid)" || { ui_pause; continue; }
                dn="$(select_directory_target_dn)" || { ui_pause; continue; }
                if ! capture_samba_gpo output setlink "$dn" "$guid"; then printf '%s\n' "$output" >&2; fi
                ui_pause
                ;;
            8)
                guid="$(select_gpo_guid)" || { ui_pause; continue; }
                dn="$(select_directory_target_dn)" || { ui_pause; continue; }
                if confirm "Remove link $guid from $dn?" N; then
                    if ! capture_samba_gpo output dellink "$dn" "$guid"; then printf '%s\n' "$output" >&2; fi
                fi
                ui_pause
                ;;
            9) guid="$(select_gpo_guid)" || { ui_pause; continue; }; backup_gpo_safe "$guid" || true; ui_pause ;;
            10) gpo_readiness_diagnostics "Manual GPO readiness check"; ui_pause ;;
            11)
                guid="$(select_gpo_guid)" || { ui_pause; continue; }
                printf 'A domain backup is strongly recommended before deleting a GPO.\n'
                confirm "Create domain backup first?" Y && create_domain_backup no
                backup_gpo_safe "$guid" || true
                if confirm_high_risk "PERMANENTLY delete GPO $guid"; then
                    if ! capture_samba_gpo output del "$guid"; then printf '%s\n' "$output" >&2; fi
                fi
                ui_pause
                ;;
            12) set_progress_plan 1; manage_gpos; ui_pause ;;
            0) break ;;
            *) msg_warn "Invalid menu option."; ui_pause ;;
        esac
    done
}


cli_command_catalog() {
    cat <<'EOF'
adctl|Main control plane|Open the full AD/DC operations console.
ad-users|Users|Create, inspect, edit, enable/disable, reset passwords and manage group memberships.
ad-groups|Groups|Create, inspect and manage domain groups and their members.
ad-computers|Computers|List/inspect domain computer accounts and show best-effort network presence.
ad-permissions|Access & delegation|Manage memberships and advanced directory-service ACL operations.
ad-gpo|Group Policy|List/select/create/link/backup/delete GPOs and deploy curated security policies.
ad-security|Security & resilience|Boot ordering, UFW, Fail2ban, sysctl and delegated-admin hardening.
ad-audit|Audit|Run a read-only inventory and security evidence review.
ad-validate|Validation|Run functional Samba AD/DC DNS, Kerberos, LDAP, SMB, DB and SYSVOL checks.
ad-status|Status|Show a compact current-state and AD/DC health report.
ad-backup|Backup|Create an online Samba domain backup.
ad-tools|CLI help|Show this command catalog and which shortcuts are installed.
EOF
}

show_cli_commands() {
    local bindir="/usr/local/sbin"
    local target="/usr/local/libexec/debian-ad-assistant"
    local installed_version="not installed"
    local name title description path state target_path
    local installed=0 missing=0

    if [[ -r "$target" ]]; then
        installed_version="$(
            awk -F= '/^SCRIPT_VERSION=/{gsub(/"/,"",$2); print $2; exit}' "$target" 2>/dev/null || true
        )"
        [[ -n "$installed_version" ]] || installed_version="unknown"
    fi

    ui_menu_screen "INSTALLED TERMINAL COMMANDS" "Shortcut inventory, purpose and installation state"
    printf '  %-17s %s\n' "Installed build" "$installed_version"
    printf '  %-17s %s\n' "Command directory" "$bindir"
    printf '  %-17s %s\n' "Assistant target" "$target"
    printf '\n'
    printf '  %-16s %-11s %-25s %s\n' "COMMAND" "STATE" "MODULE" "PURPOSE"
    ui_rule

    while IFS='|' read -r name title description; do
        [[ -n "$name" ]] || continue
        path="${bindir}/${name}"
        state="MISSING"
        target_path="-"

        if [[ -L "$path" ]]; then
            target_path="$(readlink -f "$path" 2>/dev/null || readlink "$path" 2>/dev/null || true)"
            if [[ "$target_path" == "$target" && -x "$target" ]]; then
                state="INSTALLED"
                installed=$((installed + 1))
            else
                state="STALE"
                missing=$((missing + 1))
            fi
        elif [[ -x "$path" ]]; then
            state="CUSTOM"
            target_path="$path"
            installed=$((installed + 1))
        else
            missing=$((missing + 1))
        fi

        case "$state" in
            INSTALLED) printf '  %b%-16s%b %b%-11s%b %-25s %s\n' \
                "$C_CYAN" "$name" "$C_RESET" "$C_GREEN" "$state" "$C_RESET" "$title" "$description" ;;
            CUSTOM) printf '  %b%-16s%b %b%-11s%b %-25s %s\n' \
                "$C_CYAN" "$name" "$C_RESET" "$C_YELLOW" "$state" "$C_RESET" "$title" "$description" ;;
            *) printf '  %b%-16s%b %b%-11s%b %-25s %s\n' \
                "$C_CYAN" "$name" "$C_RESET" "$C_RED" "$state" "$C_RESET" "$title" "$description" ;;
        esac
    done < <(cli_command_catalog)

    printf '\n'
    printf '  %bInstalled/usable:%b %d    %bMissing/stale:%b %d\n' \
        "$C_GREEN" "$C_RESET" "$installed" "$C_YELLOW" "$C_RESET" "$missing"
    printf '\n'
    printf '  Examples:\n'
    printf '    sudo adctl        %b# main operations console%b\n' "$C_DIM" "$C_RESET"
    printf '    sudo ad-users     %b# user administration%b\n' "$C_DIM" "$C_RESET"
    printf '    sudo ad-gpo       %b# Group Policy console%b\n' "$C_DIM" "$C_RESET"
    printf '    sudo ad-validate  %b# full functional validation%b\n' "$C_DIM" "$C_RESET"
    printf '    sudo ad-tools     %b# show this catalog again%b\n' "$C_DIM" "$C_RESET"
    ui_rule
}

install_cli_commands() {
    local target_dir="/usr/local/libexec"
    local target="${target_dir}/debian-ad-assistant"
    local bindir="/usr/local/sbin"
    local source_path
    source_path="$(readlink -f "$0")"

    [[ -f "$source_path" ]] || die "Cannot resolve current assistant path."
    mkdir -p "$target_dir" "$bindir"
    install -m 0755 "$source_path" "$target"

    local name title description
    while IFS='|' read -r name title description; do
        [[ -n "$name" ]] || continue
        ln -sfn "$target" "${bindir}/${name}"
    done < <(cli_command_catalog)

    result PASS "AD CLI shortcuts" "installed/refreshed in $bindir" "terminal administration commands"

    printf '\n'
    printf '%b%bCLI installation complete.%b\n' "$C_BOLD" "$C_GREEN" "$C_RESET"
    printf 'The following commands are now available from the terminal:\n\n'
    show_cli_commands
    printf '\n%bTip:%b run %bsudo ad-tools%b at any time to display this catalog again.\n' \
        "$C_CYAN" "$C_RESET" "$C_BOLD" "$C_RESET"
}

security_hardening_menu() {
    while true; do
        ui_menu_screen "SECURITY & BOOT RESILIENCE" "Host controls protecting availability, management access and the AD service plane"
        ui_menu_item "1" "Boot persistence audit" "Verify Samba startup and network readiness dependency"
        ui_menu_item "2" "Repair boot ordering" "Make Samba wait for the AD interface/IP" "$C_GREEN"
        ui_menu_item "3" "Fail2ban / SSH" "Configure brute-force mitigation for SSH"
        ui_menu_item "4" "Kernel network hardening" "Apply conservative sysctl protections"
        ui_menu_item "5" "Firewall policy" "Restrict AD and SSH exposure to trusted networks"
        ui_menu_item "6" "Delegated administrator" "Verify admin, promote it, optionally disable built-in Administrator"
        ui_menu_item "7" "Full AD/DC validation" "Run DNS, Kerberos, LDAP, SMB, database and SYSVOL checks"
        ui_menu_exit
        ui_rule
        local choice
        choice="$(ask 'Select operation' '1')"
        case "$choice" in
            1) audit_samba_boot_persistence; ui_pause ;;
            2) configure_samba_boot_ordering; ui_pause ;;
            3) set_progress_plan 1; configure_fail2ban; ui_pause ;;
            4) set_progress_plan 1; configure_network_hardening; ui_pause ;;
            5) set_progress_plan 1; configure_ufw; ui_pause ;;
            6) set_progress_plan 1; harden_delegated_admin; ui_pause ;;
            7) set_progress_plan 1; validate_ad; ui_pause ;;
            0) break ;;
            *) msg_warn "Invalid menu option."; ui_pause ;;
        esac
    done
}

domain_admin_console() {
    while true; do
        ui_menu_screen "AD/DC OPERATIONS CONSOLE" "Daily administration surface for a production Samba Active Directory controller"
        ui_menu_item "1" "Users" "Create, edit, enable, disable and reset domain identities"
        ui_menu_item "2" "Groups" "Manage domain groups and memberships"
        ui_menu_item "3" "Computers" "Inventory joined devices and inspect network presence"
        ui_menu_item "4" "Access & delegation" "Memberships and advanced DS ACL operations"
        ui_menu_item "5" "Group Policy" "Lifecycle and linking of GPOs"
        ui_menu_item "6" "Security & resilience" "Firewall, Fail2ban, boot ordering and admin hardening"
        ui_menu_item "7" "Install CLI commands" "Deploy/refresh adctl, ad-users, ad-gpo and related shortcuts"
        ui_menu_item "8" "Installed CLI commands" "Show shortcut status and what every terminal command does"
        ui_menu_item "9" "Validate controller" "Run complete AD/DC functional health checks"
        ui_menu_item "10" "Domain backup" "Create an online Samba domain backup"
        ui_menu_exit
        ui_rule
        local choice
        choice="$(ask 'Select module' '1')"
        case "$choice" in
            1) user_admin_menu ;;
            2) group_admin_menu ;;
            3) computer_admin_menu ;;
            4) permissions_admin_menu ;;
            5) gpo_admin_menu ;;
            6) security_hardening_menu ;;
            7) install_cli_commands; ui_pause ;;
            8) show_cli_commands; ui_pause ;;
            9) set_progress_plan 1; validate_ad; ui_pause ;;
            10) set_progress_plan 1; create_domain_backup; ui_pause ;;
            0) break ;;
            *) msg_warn "Invalid menu option."; ui_pause ;;
        esac
    done
}

write_post_install_checklist() {
    step "Post-install checklist"
    cat >"$POST_INSTALL_FILE" <<EOF
${SCRIPT_NAME} ${SCRIPT_VERSION} - POST-INSTALL CHECKLIST
Generated: $(date -Is)

CURRENT IDENTITY
  Domain       : ${DOMAIN}
  Realm        : ${REALM}
  DC           : ${DC_FQDN}
  DC IP        : ${DC_IP}
  AD interface : ${AD_IFACE}
  AD network   : ${AD_CLIENT_CIDR}

[BOOT]
  [ ] systemctl is-enabled samba-ad-dc
  [ ] systemctl is-enabled debian-ad-network-ready.service
  [ ] systemd-analyze critical-chain samba-ad-dc.service

[AD/DNS/KERBEROS]
  [ ] sudo ${0} --validate
  [ ] dig @127.0.0.1 ${DC_FQDN}
  [ ] kinit ${ADMIN_USER}@${REALM}
  [ ] kvno ldap/${DC_FQDN}

[SECURITY]
  [ ] Review UFW rules and trusted CIDRs.
  [ ] Review Fail2ban SSH jail.
  [ ] Secure recovery credentials for built-in Administrator before disabling it.
  [ ] Keep verified domain backups off-host.

[CLIENT]
  [ ] Configure clients to use ${DC_IP} for AD DNS.
  [ ] Join a test client to ${DOMAIN}.
  [ ] Test a normal domain login and GPO application.
EOF
    chmod 600 "$POST_INSTALL_FILE"
    result INFO "Post-install checklist" "$POST_INSTALL_FILE" "review after reboot"
}

write_report() {
    write_backup_manifest
    {
        printf '%s %s\n' "$SCRIPT_NAME" "$SCRIPT_VERSION"
        printf 'Generated: %s\n' "$(date -Is)"
        printf 'Mode: %s\n' "$MODE"
        printf 'Host: %s\n' "$(hostname -f 2>/dev/null || hostname)"
        printf 'Samba role: %s\n' "$SAMBA_ROLE"
        printf 'Domain: %s\nRealm: %s\nDC: %s\nDC IP: %s\n' "$DOMAIN" "$REALM" "$DC_FQDN" "$DC_IP"
        printf '\n=== RESULTS ===\n'; printf '%s\n' "${RESULTS[@]}"
        printf '\n=== CHANGES ===\n'; printf '%s\n' "${CHANGES[@]}"
        printf '\n=== WARNINGS ===\n'; printf '%s\n' "${WARNINGS[@]}"
        printf '\n=== FAILURES ===\n'; printf '%s\n' "${FAILURES[@]}"
    } >"$REPORT_FILE"
    chmod 600 "$REPORT_FILE"
}

summary() {
    local pass warn fail applied
    pass="$(printf '%s\n' "${RESULTS[@]}" | grep -c '^PASS|' || true)"
    warn="$(printf '%s\n' "${RESULTS[@]}" | grep -c '^WARN|' || true)"
    fail="$(printf '%s\n' "${RESULTS[@]}" | grep -Ec '^(FAIL|ERROR)\|' || true)"
    applied="$(printf '%s\n' "${CHANGES[@]}" | grep -c '^APPLIED|' || true)"

    section "EXECUTION SUMMARY"
    printf '  %-18s %b%4s PASS%b   %b%4s WARN%b   %b%4s FAIL%b   %4s changes\n' \
        "Result counters" \
        "$C_GREEN" "$pass" "$C_RESET" \
        "$C_YELLOW" "$warn" "$C_RESET" \
        "$C_RED" "$fail" "$C_RESET" \
        "$applied"
    printf '\n'
    printf '  %-18s %s\n' "Log" "$LOG_FILE"
    printf '  %-18s %s\n' "Report" "$REPORT_FILE"
    printf '  %-18s %s\n' "Backups" "$BACKUP_DIR"
    printf '  %-18s %s\n' "Run data" "$RUN_ROOT"
    [[ -f "$POST_INSTALL_FILE" ]] && printf '  %-18s %s\n' "Checklist" "$POST_INSTALL_FILE"
    printf '\n'
    if (( fail > 0 )); then
        printf '  %b%bSTATUS: ATTENTION REQUIRED%b\n' "$C_BOLD" "$C_RED" "$C_RESET"
    elif (( warn > 0 )); then
        printf '  %b%bSTATUS: OPERATION COMPLETE WITH WARNINGS%b\n' "$C_BOLD" "$C_YELLOW" "$C_RESET"
    else
        printf '  %b%bSTATUS: OPERATION COMPLETE%b\n' "$C_BOLD" "$C_GREEN" "$C_RESET"
    fi
    ui_rule
}

bootstrap_mode() {
    detect_samba_role
    if [[ "$SAMBA_ROLE" == ad-dc || "$SAMBA_ROLE" == ad-dc-config ]]; then
        bootstrap_resume_identity
    elif [[ "$SAMBA_ROLE" != none ]]; then
        die "Existing non-AD Samba role detected ($SAMBA_ROLE). Bootstrap will not repurpose it."
    else
        BOOTSTRAP_RESUME=0
    fi

    set_progress_plan 16
    audit_existing

    if [[ "$BOOTSTRAP_RESUME" -eq 0 ]]; then
        collect_identity
    else
        discover_network_topology
        discover_existing_identity
        refresh_canonical_identity
    fi

    collect_admin_identity
    save_config
    snapshot_system
    install_required_packages

    [[ -n "$AD_CLIENT_CIDR" && -n "$SSH_SOURCE" ]] || collect_network_policy
    save_config

    configure_hostname_hosts
    configure_samba_service_model
    prepare_dns_transaction
    configure_time
    save_config

    resume_or_provision_domain
    save_config

    if [[ "$DNS_NEEDS_COMMIT" -eq 1 ]]; then
        commit_samba_dns_resolver || {
            rollback_dns_transaction "Samba DNS did not become healthy"
            return 1
        }
    else
        step "Start Samba DNS / commit resolver"
        result SKIP "DNS commit" "already healthy" "retained"
    fi

    ensure_directory_baseline

    if [[ "$ENABLE_GPOS" == yes ]] && confirm "Create/link baseline GPOs?" Y; then
        manage_gpos
    else
        step "Group Policy"
        result SKIP "GPO" "operator skipped" "optional"
    fi

    configure_ufw
    validate_ad
    save_config
    write_post_install_checklist

    if confirm "Install terminal shortcuts (adctl, ad-users, ad-gpo...)?" Y; then
        install_cli_commands
    fi
}

manage_menu() {
    while true; do
        ui_menu_screen "DOMAIN CONTROLLER MANAGEMENT" "Maintenance, recovery, security and operational administration"
        ui_menu_item "1" "Audit current state" "Inventory OS, topology, services and security evidence"
        ui_menu_item "2" "Validate AD/DC health" "Functional DNS/Kerberos/LDAP/SMB/database checks"
        ui_menu_item "3" "Repair DNS / Kerberos" "Transactional Samba DNS, resolver and Kerberos recovery"
        ui_menu_item "4" "Time synchronization" "Configure Chrony and domain NTP policy"
        ui_menu_item "5" "Firewall policy" "Configure UFW with trusted AD/management scopes"
        ui_menu_item "6" "Directory/admin baseline" "Ensure OUs, groups and delegated administrator"
        ui_menu_item "7" "Baseline GPOs" "Create/update assistant-managed secure policies"
        ui_menu_item "8" "Domain backup" "Create an online recoverable Samba domain backup"
        ui_menu_item "9" "SYSVOL ACL repair" "Advanced reset after backup and explicit authorization" "$C_YELLOW"
        ui_menu_item "10" "Post-install checklist" "Regenerate production-readiness checklist"
        ui_menu_item "11" "Operations console" "Users, groups, computers, permissions and GPOs" "$C_GREEN"
        ui_menu_item "12" "Boot ordering" "Repair Samba startup dependency on network readiness"
        ui_menu_item "13" "Install CLI commands" "Deploy/refresh adctl and direct administrative shortcuts"
        ui_menu_item "14" "Installed CLI commands" "Show shortcut status and a description of every command"
        ui_menu_exit
        ui_rule
        local choice
        choice="$(ask 'Select module' '1')"
        case "$choice" in
            1) set_progress_plan 2; audit_existing; audit_security_baseline; ui_pause ;;
            2) set_progress_plan 1; validate_ad; ui_pause ;;
            3) repair_dns_stack; ui_pause ;;
            4) set_progress_plan 1; configure_time; ui_pause ;;
            5) set_progress_plan 1; configure_ufw; ui_pause ;;
            6) set_progress_plan 1; ensure_directory_baseline; ui_pause ;;
            7) set_progress_plan 1; manage_gpos; ui_pause ;;
            8) set_progress_plan 1; create_domain_backup; ui_pause ;;
            9) set_progress_plan 2; advanced_sysvol_repair; ui_pause ;;
            10) set_progress_plan 1; write_post_install_checklist; ui_pause ;;
            11) domain_admin_console ;;
            12) configure_samba_boot_ordering; ui_pause ;;
            13) install_cli_commands; ui_pause ;;
            14) show_cli_commands; ui_pause ;;
            0) break ;;
            *) msg_warn "Invalid menu option."; ui_pause ;;
        esac
    done
}

prepare_existing_ad_context() {
    detect_samba_role
    [[ "$SAMBA_ROLE" == ad-dc || "$SAMBA_ROLE" == ad-dc-config ]] ||
        die "No existing Samba AD/DC detected."
    load_config || true
    discover_network_topology
    discover_existing_identity
    [[ -n "$ADMIN_USER" ]] || ADMIN_USER="$(ask 'AD admin account' 'Administrator')"
}

manage_mode() {
    prepare_existing_ad_context
    snapshot_system
    manage_menu
    save_config
}

audit_mode() {
    set_progress_plan 3
    audit_existing
    audit_security_baseline
    if [[ "$SAMBA_ROLE" == ad-dc || "$SAMBA_ROLE" == ad-dc-config ]]; then
        discover_existing_identity
        validate_ad || true
    else
        step "AD/DC validation"
        result SKIP "AD/DC validation" "not an AD/DC" "not applicable"
    fi
}

validate_mode() {
    prepare_existing_ad_context
    set_progress_plan 1
    validate_ad
}

status_mode() {
    set_progress_plan 2
    audit_existing
    if [[ "$SAMBA_ROLE" == ad-dc || "$SAMBA_ROLE" == ad-dc-config ]]; then
        load_config || true
        discover_existing_identity
        validate_ad || true
    else
        step "AD/DC health"
        result SKIP "AD/DC" "not configured" "not applicable"
    fi
}

backup_mode() {
    prepare_existing_ad_context
    set_progress_plan 1
    create_domain_backup
}

interactive_mode() {
    if [[ "$SAMBA_ROLE" == ad-dc || "$SAMBA_ROLE" == ad-dc-config ]]; then
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
    detect_invocation_alias
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
        admin) prepare_existing_ad_context; domain_admin_console; save_config ;;
        users) prepare_existing_ad_context; user_admin_menu; save_config ;;
        groups) prepare_existing_ad_context; group_admin_menu; save_config ;;
        computers) prepare_existing_ad_context; computer_admin_menu; save_config ;;
        permissions) prepare_existing_ad_context; permissions_admin_menu; save_config ;;
        gpo) prepare_existing_ad_context; gpo_admin_menu; save_config ;;
        security) prepare_existing_ad_context; security_hardening_menu; save_config ;;
        install-cli) install_cli_commands ;;
        cli-info) show_cli_commands ;;
        interactive) interactive_mode ;;
        *) die "Unknown mode: $MODE" ;;
    esac

    write_report
    summary
}

main "$@"
