#!/usr/bin/env bash
# DEBIAN AD Assistant
# Version 5.0.2-samba-kdc-boot-selfheal
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

# Ensure standard administrative binaries are discoverable in sudo/non-login shells.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

SCRIPT_NAME="DEBIAN AD Assistant"
SCRIPT_VERSION="5.0.2-samba-kdc-boot-selfheal"

MODE="interactive"
FORCE_NO_COLOR=0

STATE_DIR="/var/lib/debian-ad-assistant"
LOG_DIR="/var/log/debian-ad-assistant"
CONFIG_FILE="${STATE_DIR}/config.env"
GPO_DIR="${STATE_DIR}/gpo"
GPO_BUILTIN_DIR="${GPO_DIR}/builtin"
GPO_WINDOWS_DIR="${GPO_BUILTIN_DIR}/windows"
GPO_CUSTOM_DIR="${GPO_DIR}/custom"
GPO_DOC_FILE="${GPO_DIR}/GPO-GUIDE.md"
MIGRATION_DIR="${STATE_DIR}/migration"
MIGRATION_PLAN_FILE="${MIGRATION_DIR}/migration.env"
POST_INSTALL_FILE="${STATE_DIR}/POST-INSTALL.txt"

IDS_STATE_DIR="${STATE_DIR}/ids"
IDS_REPORT_DIR="${IDS_STATE_DIR}/reports"
IDS_CONFIG="/etc/suricata/debian-ad-assistant.yaml"
IDS_DROPIN="/etc/systemd/system/suricata.service.d/90-debian-ad-assistant.conf"
IDS_EVE_DIR="/var/log/suricata"
IDS_EVE_GLOB="${IDS_EVE_DIR}/eve.json*"
IDS_DAILY_SERVICE="/etc/systemd/system/debian-ad-ids-daily.service"
IDS_DAILY_TIMER="/etc/systemd/system/debian-ad-ids-daily.timer"

SAMBA_HEALTH_HELPER="/usr/local/libexec/debian-ad-samba-health"
SAMBA_HEALTH_SERVICE="/etc/systemd/system/debian-ad-samba-health.service"

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
MENU_MAIN_REQUESTED=0
RESET_COMPLETED=0
RESET_RECOVERY_DIR=""
RESET_RECOVERY_ROOT="/var/backups/debian-ad-assistant"

KRB5_CACHE=""
# Preserve the caller's cache hint for read-only diagnostics. The assistant still
# uses a private per-run ccache for all privileged AD operations.
INHERITED_KRB5CCNAME="${KRB5CCNAME:-}"
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
    ui_menu_item "0" "Back" "Return to previous console" "$C_RED"
    ui_menu_item "H" "Main menu" "Jump to the full AD/DC Main Control Plane" "$C_MAGENTA"
}

ui_menu_root_exit() {
    ui_menu_item "0" "Exit / Back" "Leave this control plane" "$C_RED"
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
  sudo bash $0 --samba-security
  sudo bash $0 --kerberos
  sudo bash $0 --migration
  sudo bash $0 --reset-domain
  sudo bash $0 --dependencies
  sudo bash $0 --ids
  sudo bash $0 --install-cli
  sudo bash $0 --cli-info
  sudo bash $0 --no-color
  sudo bash $0 --help

Convenience commands installed by --install-cli:
  adctl, ad-users, ad-groups, ad-computers, ad-permissions,
  ad-gpo, ad-security, ad-samba, ad-kerberos, ad-migrate, ad-reset, ad-deps, ad-ids,
  ad-audit, ad-validate, ad-status, ad-backup, ad-tools

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
        adctl) MODE="manage" ;;
        ad-ops) MODE="admin" ;;
        ad-users) MODE="users" ;;
        ad-groups) MODE="groups" ;;
        ad-computers) MODE="computers" ;;
        ad-permissions) MODE="permissions" ;;
        ad-gpo) MODE="gpo" ;;
        ad-security) MODE="security" ;;
        ad-samba) MODE="samba-security" ;;
        ad-kerberos) MODE="kerberos-security" ;;
        ad-migrate) MODE="migration" ;;
        ad-reset) MODE="reset-domain" ;;
        ad-deps) MODE="dependencies" ;;
        ad-ids) MODE="ids" ;;
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
            --samba-security|--samba-hardening) MODE="samba-security" ;;
            --kerberos|--kerberos-security) MODE="kerberos-security" ;;
            --migration|--migrate) MODE="migration" ;;
            --reset-domain|--factory-reset|--decommission) MODE="reset-domain" ;;
            --dependencies|--deps) MODE="dependencies" ;;
            --ids|--suricata|--network-ids) MODE="ids" ;;
            --ids-daily) MODE="ids-daily" ;;
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
        bootstrap|manage|interactive|backup|admin|users|groups|computers|permissions|gpo|security|migration|reset-domain|dependencies|ids|install-cli)
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

    mkdir -p "$STATE_DIR" "$LOG_DIR" "$RUN_ROOT" "$BACKUP_DIR" "$DOMAIN_BACKUP_DIR" "$GPO_DIR" "$GPO_WINDOWS_DIR" "$GPO_CUSTOM_DIR" "$MIGRATION_DIR"
    chmod 700 "$STATE_DIR" "$LOG_DIR" "$RUN_ROOT" "$BACKUP_DIR" "$DOMAIN_BACKUP_DIR" "$GPO_DIR" "$GPO_BUILTIN_DIR" "$GPO_WINDOWS_DIR" "$GPO_CUSTOM_DIR" "$MIGRATION_DIR"
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


dependency_dns_package() {
    if package_available bind9-dnsutils; then
        printf 'bind9-dnsutils'
    else
        printf 'dnsutils'
    fi
}

dependency_catalog() {
    local profile="${1:-existing}"
    local dns_pkg=""
    dns_pkg="$(dependency_dns_package)"

    cat <<EOF
samba-ad-dc|required|Samba AD/DC runtime and samba-tool
krb5-user|required|Kerberos client tools: kinit, klist, kvno
chrony|required|NTP/Chrony daemon and chronyc client
ldb-tools|required|Local LDB inspection and authenticated ldbmodify workflows
smbclient|required|SMB/SYSVOL validation
python3|required|JSON, LDIF and safe configuration transformations
iproute2|required|Network/interface/listener discovery
${dns_pkg}|required|dig and DNS/SRV diagnostics
EOF

    if [[ "$profile" == "bootstrap" ]]; then
        printf 'samba-ad-provision|required|Samba AD schema/provisioning payload\n'
    fi

    printf 'ufw|optional|Host firewall when enabled by policy\n'
    printf 'fail2ban|optional|SSH brute-force protection when explicitly enabled\n'
    printf 'suricata|optional|Passive network IDS / protocol telemetry (ad-ids)\n'
    printf 'suricata-update|optional|Official/distribution Suricata ruleset updater for ad-ids\n'
}

package_installed() {
    local pkg="$1"
    dpkg-query -W -f='${db:Status-Abbrev}' "$pkg" 2>/dev/null | grep -Fxq 'ii '
}

package_installed_version() {
    dpkg-query -W -f='${Version}' "$1" 2>/dev/null || true
}

package_policy_text() {
    local pkg="$1" output="" rc=0

    # Metadata lookup is best-effort. Capture the complete apt-cache output
    # before parsing it. This avoids SIGPIPE/rc=141 with `set -o pipefail`
    # when a downstream parser stops reading early.
    if output="$(apt-cache policy "$pkg" 2>/dev/null)"; then
        printf '%s\n' "$output"
        return 0
    else
        rc=$?
    fi

    [[ -n "$output" ]] && printf '%s\n' "$output"
    return "$rc"
}

package_candidate_version() {
    local pkg="$1" policy=""

    policy="$(package_policy_text "$pkg" 2>/dev/null || true)"
    [[ -n "$policy" ]] || return 0

    # Parse captured text completely. No early exit on a live pipeline.
    awk '
        $1 == "Candidate:" && !seen {
            print $2
            seen=1
        }
    ' <<<"$policy"
}

package_candidate_origin() {
    local pkg="$1" policy="" candidate=""

    policy="$(package_policy_text "$pkg" 2>/dev/null || true)"
    [[ -n "$policy" ]] || return 0

    candidate="$(
        awk '
            $1 == "Candidate:" && !seen {
                print $2
                seen=1
            }
        ' <<<"$policy"
    )"

    [[ -n "$candidate" && "$candidate" != "(none)" ]] || return 0

    # Find the first repository line belonging to the candidate version while
    # consuming all input. The installed-version marker (***) is handled too.
    awk -v candidate="$candidate" '
        /^[[:space:]]*\*\*\*[[:space:]]+/ {
            version=$2
            in_candidate=(version == candidate)
            next
        }
        /^[[:space:]]*[^[:space:]]+[[:space:]]+[0-9]+[[:space:]]*$/ {
            version=$1
            in_candidate=(version == candidate)
            next
        }
        in_candidate && /^[[:space:]]+[0-9]+[[:space:]]+(https?:|file:)/ && !seen {
            print $2
            seen=1
        }
    ' <<<"$policy"
}

dependency_required_packages() {
    local profile="${1:-existing}"
    dependency_catalog "$profile" |
        awk -F'|' '$2=="required"{print $1}'
}

dependency_optional_packages() {
    local profile="${1:-existing}"
    dependency_catalog "$profile" |
        awk -F'|' '$2=="optional"{print $1}'
}

dependency_missing_required() {
    local profile="${1:-existing}" pkg
    while IFS= read -r pkg; do
        [[ -n "$pkg" ]] || continue
        package_installed "$pkg" || printf '%s\n' "$pkg"
    done < <(dependency_required_packages "$profile")
}

dependency_pending_updates() {
    local profile="${1:-existing}" pkg installed candidate
    while IFS= read -r pkg; do
        [[ -n "$pkg" ]] || continue
        package_installed "$pkg" || continue
        installed="$(package_installed_version "$pkg")"
        candidate="$(package_candidate_version "$pkg" 2>/dev/null || true)"
        if [[ -n "$candidate" && "$candidate" != "(none)" && -n "$installed" ]] &&
           dpkg --compare-versions "$candidate" gt "$installed"; then
            printf '%s|%s|%s\n' "$pkg" "$installed" "$candidate"
        fi
    done < <(dependency_required_packages "$profile")
}

show_dependency_inventory() {
    local profile="${1:-existing}"
    local pkg class purpose installed candidate origin state
    section "DEPENDENCY INVENTORY"

    printf '  %-22s %-9s %-20s %-20s %s\n' \
        "PACKAGE" "CLASS" "INSTALLED" "CANDIDATE" "PURPOSE"
    ui_rule

    while IFS='|' read -r pkg class purpose; do
        [[ -n "$pkg" ]] || continue
        installed="$(package_installed_version "$pkg")"
        candidate="$(package_candidate_version "$pkg" 2>/dev/null || true)"
        origin="$(package_candidate_origin "$pkg" 2>/dev/null || true)"
        [[ -n "$installed" ]] || installed="-"
        [[ -n "$candidate" && "$candidate" != "(none)" ]] || candidate="-"

        printf '  %-22s %-9s %-20.20s %-20.20s %s\n' \
            "$pkg" "$class" "$installed" "$candidate" "$purpose"
        if [[ -n "$origin" ]]; then
            printf '    source: %s\n' "$origin"
        elif [[ "$candidate" != "-" ]]; then
            printf '    source: %s\n' "configured APT source (origin not resolved)"
        fi
    done < <(dependency_catalog "$profile")

    printf '\n'
    printf '  %bPackage policy%b\n' "$C_BOLD" "$C_RESET"
    printf '    Required packages are distribution packages only.\n'
    printf '    Optional packages are installed only when their feature is enabled.\n'
    printf '    The assistant does not add PPAs, third-party APT repositories, pip packages,\n'
    printf '    curl-based installers or language-specific package managers.\n'
    printf '    Runtime provenance follows the APT sources configured by the administrator.\n'
}

install_missing_dependency_profile() {
    local profile="${1:-existing}"
    local -a missing=()
    mapfile -t missing < <(dependency_missing_required "$profile")

    if ((${#missing[@]} == 0)); then
        result PASS "Dependencies" "$profile required packages present" "complete"
        return 0
    fi

    printf '\nMissing required distribution packages:\n'
    printf '  - %s\n' "${missing[@]}"

    if [[ "$INPUT_FD" == "/dev/null" ]]; then
        result WARN "Dependencies" \
            "missing: ${missing[*]}" \
            "install via ad-deps / --dependencies"
        return 1
    fi

    confirm "Install missing required packages now?" Y || {
        result WARN "Dependencies" \
            "operator declined: ${missing[*]}" \
            "required for full functionality"
        return 1
    }

    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"

    mapfile -t missing < <(dependency_missing_required "$profile")
    if ((${#missing[@]})); then
        fail_msg "Required packages remain missing: ${missing[*]}"
        return 1
    fi

    result PASS "Dependencies" "$profile required packages installed" "complete"
}

install_required_packages() {
    step "Install required packages"
    require_cmd apt-get "package management" || return 1

    # Minimal bootstrap profile. acl/attr were intentionally removed because
    # the assistant does not invoke getfacl/setfacl/getfattr/setfattr.
    install_missing_dependency_profile bootstrap || return 1

    local chronyd_path="" chronyc_path=""
    chronyd_path="$(chronyd_binary 2>/dev/null || true)"
    chronyc_path="$(chronyc_binary 2>/dev/null || true)"
    [[ -n "$chronyd_path" && -n "$chronyc_path" ]] || {
        fail_msg "Package 'chrony' is installed but its runtime binaries are unavailable."
        printf '  Package state : %s\n' "$(chrony_package_status)" >&2
        printf '  Expected      : /usr/sbin/chronyd and /usr/bin/chronyc\n' >&2
        return 1
    }

    result PASS "Packages" "minimal bootstrap dependency profile present" "Samba/Kerberos/DNS/Chrony"
    result PASS "Chrony runtime" "$chronyd_path + $chronyc_path" "installed"
}

ensure_existing_dependency_preflight() {
    local -a missing=()
    mapfile -t missing < <(dependency_missing_required existing)
    ((${#missing[@]} == 0)) && return 0

    printf '\n'
    msg_warn "This existing AD/DC is missing one or more tools used by the control plane:"
    printf '  - %s\n' "${missing[@]}"

    if [[ "$INPUT_FD" != "/dev/null" ]]; then
        install_missing_dependency_profile existing || true
    else
        result WARN "Dependencies" \
            "missing: ${missing[*]}" \
            "run sudo ad-deps"
    fi
}

update_dependency_profile() {
    local profile="${1:-existing}"
    local -a updates=() pkgs=()
    local row pkg installed candidate

    apt-get update
    mapfile -t updates < <(dependency_pending_updates "$profile")

    if ((${#updates[@]} == 0)); then
        result PASS "Dependency updates" "no package updates pending" "$profile"
        return 0
    fi

    printf '\n%bPending dependency updates%b\n' "$C_BOLD" "$C_RESET"
    for row in "${updates[@]}"; do
        IFS='|' read -r pkg installed candidate <<<"$row"
        printf '  %-22s %s -> %s\n' "$pkg" "$installed" "$candidate"
        pkgs+=("$pkg")
    done

    # Samba updates deserve a recoverable domain backup because apt may restart
    # services and Samba packages are version-coupled.
    if printf '%s\n' "${pkgs[@]}" | grep -Eq '^samba-(ad-dc|ad-provision)$|^smbclient$'; then
        printf '\nSamba-related packages are pending updates.\n'
        if [[ "$SAMBA_ROLE" == "ad-dc" || "$SAMBA_ROLE" == "ad-dc-config" ]]; then
            confirm "Create an online domain backup before updating Samba packages?" Y &&
                create_domain_backup no
        fi
        confirm_high_risk "Update installed AD control-plane dependencies (including Samba components if listed)" ||
            return 0
    else
        confirm "Update the listed dependency packages now?" N || return 0
    fi

    # Update only the explicit dependency set; do not perform dist-upgrade/full-upgrade.
    DEBIAN_FRONTEND=noninteractive apt-get install --only-upgrade -y "${pkgs[@]}"

    if [[ "$SAMBA_ROLE" == "ad-dc" || "$SAMBA_ROLE" == "ad-dc-config" ]]; then
        systemctl is-active --quiet samba-ad-dc ||
            systemctl restart samba-ad-dc >/dev/null 2>&1 || true

        if ! wait_for_samba; then
            result FAIL "Dependency update health" "samba-ad-dc did not become healthy" "review apt/dpkg logs"
            return 1
        fi
        samba-tool domain info "$DC_IP" >/dev/null 2>&1 ||
            result WARN "Dependency update health" "domain info validation failed" "review DNS/Samba"
    fi

    result PASS "Dependency updates" "selected dependency packages updated" "validated"
}

dependency_menu() {
    while true; do
        (( MENU_MAIN_REQUESTED )) && return 0

        ui_menu_screen "DEPENDENCIES & PACKAGE LIFECYCLE" \
            "Minimal distribution packages, missing-tool repair and scoped updates"
        ui_menu_item "1" "Dependency inventory" \
            "Installed/candidate versions, purpose and configured APT source"
        ui_menu_item "2" "Install missing required" \
            "Install only packages required by an existing AD/DC" "$C_GREEN"
        ui_menu_item "3" "Update required packages" \
            "Scoped --only-upgrade; no full/dist upgrade" "$C_YELLOW"
        ui_menu_item "4" "Optional security tools" \
            "UFW / Fail2ban only when explicitly wanted"
        ui_menu_exit
        ui_rule

        local choice
        choice="$(ask 'Select dependency operation' '1')"
        case "$choice" in
            1) show_dependency_inventory existing; ui_pause ;;
            2) install_missing_dependency_profile existing; ui_pause ;;
            3) update_dependency_profile existing; ui_pause ;;
            4)
                printf '\n'
                printf '  UFW      : %s\n' "$(package_installed_version ufw || true)"
                printf '  Fail2ban : %s\n' "$(package_installed_version fail2ban || true)"
                printf '\nThese are optional and are not part of the minimum AD runtime.\n'
                if confirm "Configure/install UFW through the security workflow now?" N; then
                    configure_ufw
                fi
                if confirm "Configure/install Fail2ban for SSH now?" N; then
                    configure_fail2ban
                fi
                ui_pause
                ;;
            H|h) MENU_MAIN_REQUESTED=1; return 0 ;;
            0) return 0 ;;
            *) msg_warn "Invalid dependency operation."; ui_pause ;;
        esac
    done
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

    python3 - "$key" "$value" <<'PY'
from pathlib import Path
import re, sys

path = Path("/etc/samba/smb.conf")
key, value = sys.argv[1], sys.argv[2]
lines = path.read_text(encoding="utf-8").splitlines()

global_start = None
global_end = len(lines)

for i, line in enumerate(lines):
    if re.match(r"^\s*\[global\]\s*$", line, re.I):
        global_start = i
        break

if global_start is None:
    raise SystemExit("smb.conf has no [global] section")

for i in range(global_start + 1, len(lines)):
    if re.match(r"^\s*\[[^\]]+\]\s*$", lines[i]):
        global_end = i
        break

assignment = re.compile(r"^\s*" + re.escape(key) + r"\s*=", re.I)
replacement = f"\t{key} = {value}"

for i in range(global_start + 1, global_end):
    if assignment.match(lines[i]):
        lines[i] = replacement
        break
else:
    lines.insert(global_start + 1, replacement)

path.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY
}


remove_smb_global_option() {
    local key="$1"
    require_cmd python3 "safe smb.conf editing" || return 1

    python3 - "$key" <<'PY'
from pathlib import Path
import re, sys

path = Path("/etc/samba/smb.conf")
key = sys.argv[1]
lines = path.read_text(encoding="utf-8").splitlines()

global_start = None
global_end = len(lines)
for i, line in enumerate(lines):
    if re.match(r"^\s*\[global\]\s*$", line, re.I):
        global_start = i
        break
if global_start is None:
    raise SystemExit("smb.conf has no [global] section")

for i in range(global_start + 1, len(lines)):
    if re.match(r"^\s*\[[^\]]+\]\s*$", lines[i]):
        global_end = i
        break

assignment = re.compile(r"^\s*" + re.escape(key) + r"\s*=", re.I)
out = []
for i, line in enumerate(lines):
    if global_start < i < global_end and assignment.match(line):
        continue
    out.append(line)

path.write_text("\n".join(out) + "\n", encoding="utf-8")
PY
}

samba_parameter_supported() {
    local key="$1"
    testparm -s --parameter-name="$key" >/dev/null 2>&1
}

samba_effective_value() {
    local key="$1"
    testparm -s --parameter-name="$key" 2>/dev/null |
        tail -n1 |
        sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

samba_version_string() {
    samba -V 2>/dev/null | sed -E 's/^[Vv]ersion[[:space:]]+//' | head -n1
}

samba_security_result() {
    local key="$1" expected="$2" mode="${3:-exact}"
    local actual=""
    if ! samba_parameter_supported "$key"; then
        result INFO "Samba: $key" "unsupported by installed version" "capability-dependent"
        return 0
    fi
    actual="$(samba_effective_value "$key")"

    case "$mode" in
        exact)
            [[ "${actual,,}" == "${expected,,}" ]] \
                && result PASS "Samba: $key" "$actual" "$expected" \
                || result WARN "Samba: $key" "${actual:-unset}" "$expected"
            ;;
        oneof)
            case "|${expected,,}|" in
                *"|${actual,,}|"*) result PASS "Samba: $key" "$actual" "$expected" ;;
                *) result WARN "Samba: $key" "${actual:-unset}" "$expected" ;;
            esac
            ;;
    esac
}

audit_samba_transport_security() {
    section "SAMBA TRANSPORT & AUTHENTICATION SECURITY"
    printf '  %-27s %s\n' "Samba version" "$(samba_version_string)"
    printf '  %-27s %s\n' "Role" "$SAMBA_ROLE"

    samba_security_result "ldap server require strong auth" "yes"
    samba_security_result "client ldap sasl wrapping" "seal"
    samba_security_result "server signing" "mandatory|default" oneof
    samba_security_result "server min protocol" "SMB2_02|SMB2_10|SMB3|SMB3_00|SMB3_02|SMB3_11" oneof
    samba_security_result "ntlm auth" "ntlmv2-only|disabled" oneof
    samba_security_result "lanman auth" "no"
    samba_security_result "raw NTLMv2 auth" "no"
    samba_security_result "allow nt4 crypto" "no"
    samba_security_result "reject md5 clients" "yes"
    samba_security_result "reject md5 servers" "yes"
    samba_security_result "server schannel" "yes"
    samba_security_result "server schannel require seal" "yes"

    if samba_parameter_supported "tls enabled"; then
        samba_security_result "tls enabled" "yes"
    fi

    local mapguest
    mapguest="$(samba_effective_value "map to guest" 2>/dev/null || true)"
    case "${mapguest,,}" in
        never|"") result PASS "Samba guest mapping" "${mapguest:-Never}" "Never" ;;
        *) result WARN "Samba guest mapping" "$mapguest" "Never on an AD DC" ;;
    esac

    local sections custom=""
    sections="$(
        testparm -s 2>/dev/null |
        awk '/^\[[^]]+\]/{gsub(/^\[|\]$/,""); print tolower($0)}'
    )"
    while IFS= read -r s; do
        case "$s" in
            global|sysvol|netlogon|"") ;;
            *) custom+="${s} " ;;
        esac
    done <<<"$sections"

    if [[ -z "$custom" ]]; then
        result PASS "Dedicated AD/DC shares" "sysvol + netlogon only" "dedicated authentication controller"
    else
        result WARN "Dedicated AD/DC shares" "additional shares: $custom" "move file/print workloads to member servers"
    fi
}

audit_kerberos_client_config() {
    section "KERBEROS CLIENT CONFIGURATION"

    local generated="/var/lib/samba/private/krb5.conf"
    local installed="/etc/krb5.conf"
    local realm weak stale

    [[ -r "$generated" ]] \
        && result PASS "Samba-generated krb5.conf" "$generated" "present" \
        || result FAIL "Samba-generated krb5.conf" "missing" "$generated"

    [[ -r "$installed" ]] \
        && result PASS "System krb5.conf" "$installed" "readable" \
        || { result FAIL "System krb5.conf" "missing/unreadable" "$installed"; return 1; }

    realm="$(awk -F= '/^[[:space:]]*default_realm[[:space:]]*=/{gsub(/[[:space:]]/,"",$2);print $2;exit}' "$installed" || true)"
    [[ "${realm^^}" == "${REALM^^}" ]] \
        && result PASS "Kerberos default realm" "$realm" "$REALM" \
        || result WARN "Kerberos default realm" "${realm:-unset}" "$REALM"

    if grep -Eiq '^[[:space:]]*(allow_weak_crypto|allow_rc4|allow_des3)[[:space:]]*=[[:space:]]*(true|yes|1)' "$installed"; then
        weak="$(grep -Ei '^[[:space:]]*(allow_weak_crypto|allow_rc4|allow_des3)[[:space:]]*=' "$installed" | tr '\n' '; ')"
        result WARN "MIT Kerberos weak crypto overrides" "$weak" "no explicit weak-crypto enable"
    else
        result PASS "MIT Kerberos weak crypto overrides" "not enabled" "not enabled"
    fi

    stale="$(grep -Ei '^[[:space:]]*(default_tkt_enctypes|default_tgs_enctypes)[[:space:]]*=' "$installed" || true)"
    if [[ -n "$stale" ]]; then
        result WARN "Static client enctype lists" "$(tr '\n' '; ' <<<"$stale")" "avoid stale default_tkt/default_tgs lists"
    else
        result PASS "Static client enctype lists" "not configured" "library defaults / permitted_enctypes"
    fi

    if [[ -r "$generated" ]] && cmp -s "$generated" "$installed"; then
        result PASS "Kerberos config provenance" "matches Samba-generated config" "canonical DC client config"
    else
        result INFO "Kerberos config provenance" "custom/modified from Samba-generated file" "review if multiple realms/trusts are intentional"
    fi

    if command_exists klist && KRB5CCNAME="$KRB5CCNAME" klist -s >/dev/null 2>&1; then
        local principal
        principal="$(KRB5CCNAME="$KRB5CCNAME" klist 2>/dev/null | awk -F': ' '/Default principal:/{print $2;exit}')"
        result PASS "Kerberos credential cache" "$principal" "valid isolated assistant ticket"
    else
        result INFO "Kerberos credential cache" "no current ticket" "ticket acquired on demand"
    fi
}

repair_kerberos_client_config() {
    section "KERBEROS CLIENT CONFIG REPAIR"
    local generated="/var/lib/samba/private/krb5.conf"

    [[ -r "$generated" ]] || {
        msg_warn "Missing Samba-generated Kerberos configuration: $generated"
        return 1
    }

    printf 'The DC client configuration will be replaced with Samba-generated krb5.conf.\n'
    printf 'If this host intentionally contains multiple Kerberos realms, review/merge manually instead.\n'
    confirm "Install Samba-generated /etc/krb5.conf?" N || return 0

    backup_file /etc/krb5.conf
    install -o root -g root -m 0644 "$generated" /etc/krb5.conf

    local realm
    realm="$(awk -F= '/^[[:space:]]*default_realm[[:space:]]*=/{gsub(/[[:space:]]/,"",$2);print $2;exit}' /etc/krb5.conf || true)"
    if [[ "${realm^^}" != "${REALM^^}" ]]; then
        fail_msg "Installed Kerberos realm '$realm' does not match '$REALM'."
        return 1
    fi

    change APPLIED "Reinstalled /etc/krb5.conf from Samba-generated DC configuration"
    result PASS "Kerberos client config" "/etc/krb5.conf" "Samba-generated canonical config"
}


# ---------------------------------------------------------------------------
# Chrony discovery, validation and diagnostics
# ---------------------------------------------------------------------------


chronyd_binary() {
    local p=""

    p="$(command -v chronyd 2>/dev/null || true)"
    if [[ -n "$p" && -x "$p" ]]; then
        printf '%s' "$p"
        return 0
    fi

    for p in /usr/sbin/chronyd /sbin/chronyd /usr/local/sbin/chronyd; do
        [[ -x "$p" ]] && { printf '%s' "$p"; return 0; }
    done

    return 1
}

chronyc_binary() {
    local p=""
    p="$(command -v chronyc 2>/dev/null || true)"
    if [[ -n "$p" && -x "$p" ]]; then
        printf '%s' "$p"
        return 0
    fi

    for p in /usr/bin/chronyc /bin/chronyc /usr/local/bin/chronyc; do
        [[ -x "$p" ]] && { printf '%s' "$p"; return 0; }
    done

    return 1
}

chrony_package_status() {
    if command_exists dpkg-query; then
        dpkg-query -W -f='${db:Status-Abbrev} ${Version}\n' chrony 2>/dev/null || true
    elif command_exists dpkg; then
        dpkg -s chrony 2>/dev/null |
            awk -F': ' '/^(Status|Version):/{printf "%s=%s ",$1,$2} END{print ""}' || true
    fi
}

chrony_package_installed() {
    command_exists dpkg-query || return 1
    [[ "$(dpkg-query -W -f='${db:Status-Abbrev}' chrony 2>/dev/null || true)" == "ii " ]]
}

ensure_chrony_runtime() {
    local daemon="" client="" pkg=""

    daemon="$(chronyd_binary 2>/dev/null || true)"
    client="$(chronyc_binary 2>/dev/null || true)"
    pkg="$(chrony_package_status)"

    if [[ -n "$daemon" && -n "$client" ]]; then
        return 0
    fi

    printf '\n'
    msg_warn "Chrony runtime is incomplete."
    printf '  %-24s %s\n' "Package state" "${pkg:-not installed / unknown}"
    printf '  %-24s %s\n' "chronyd" "${daemon:-missing}"
    printf '  %-24s %s\n' "chronyc" "${client:-missing}"
    printf '  %-24s %s\n' "PATH" "$PATH"

    require_cmd apt-get "Chrony package installation/repair" || return 1

    if ! chrony_package_installed; then
        if ! confirm "Install required package 'chrony' now?" Y; then
            return 1
        fi
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y chrony
    else
        # Installed package with missing binaries is inconsistent. Reinstalling
        # the same package is safer than guessing a renamed executable.
        if ! confirm "Package 'chrony' is installed but binaries are missing. Reinstall it?" Y; then
            return 1
        fi
        DEBIAN_FRONTEND=noninteractive apt-get install --reinstall -y chrony
    fi

    daemon="$(chronyd_binary 2>/dev/null || true)"
    client="$(chronyc_binary 2>/dev/null || true)"

    if [[ -z "$daemon" || -z "$client" ]]; then
        fail_msg "Chrony package operation completed but required binaries are still unavailable."
        printf '  Expected daemon: /usr/sbin/chronyd\n' >&2
        printf '  Expected client: /usr/bin/chronyc\n' >&2
        printf '  Check: dpkg -L chrony | grep -E "/(chronyd|chronyc)$"\n' >&2
        return 1
    fi

    result PASS "Chrony runtime" "$daemon + $client" "installed"
}

chrony_main_config() {
    local candidate=""

    # Debian/Ubuntu package path.
    for candidate in /etc/chrony/chrony.conf /etc/chrony.conf; do
        [[ -f "$candidate" ]] && { printf '%s' "$candidate"; return 0; }
    done

    return 1
}

chrony_service_unit() {
    local unit=""
    for unit in chrony.service chronyd.service; do
        if systemctl list-unit-files --type=service --no-legend "$unit" 2>/dev/null |
            awk '{print $1}' | grep -Fxq "$unit"; then
            printf '%s' "$unit"
            return 0
        fi
    done

    # Debian/Ubuntu use chrony.service. Return the expected unit even when
    # systemd metadata is temporarily unavailable so diagnostics stay useful.
    if [[ "$DISTRO_ID" == "debian" || "$DISTRO_ID" == "ubuntu" ]]; then
        printf 'chrony.service'
        return 0
    fi

    return 1
}

chrony_managed_fragment() {
    printf '/etc/chrony/conf.d/90-debian-ad.conf'
}

chrony_signed_fragment() {
    printf '/etc/chrony/conf.d/91-samba-ad-signed-time.conf'
}

chrony_config_includes_conf_d() {
    local config=""
    config="$(chrony_main_config)" || return 1

    grep -Eiq \
        '^[[:space:]]*(confdir[[:space:]]+/etc/chrony/conf\.d([[:space:]]|$)|include[[:space:]]+/etc/chrony/conf\.d/.*\.conf([[:space:]]|$))' \
        "$config"
}

ensure_chrony_conf_d_included() {
    local config=""
    config="$(chrony_main_config)" || {
        fail_msg "Unable to locate Chrony main configuration file."
        return 1
    }

    mkdir -p /etc/chrony/conf.d

    chrony_config_includes_conf_d && return 0

    # Modern Debian/Ubuntu Chrony supports confdir. Add a small managed include
    # only when the package configuration does not already include conf.d.
    backup_file "$config"
    {
        printf '\n'
        printf '# BEGIN DEBIAN-AD-ASSISTANT CHRONY INCLUDE\n'
        printf 'confdir /etc/chrony/conf.d\n'
        printf '# END DEBIAN-AD-ASSISTANT CHRONY INCLUDE\n'
    } >>"$config"

    return 0
}

resolve_ad_ntp_client_cidr() {
    local cidr=""

    if [[ -n "${AD_CLIENT_CIDR:-}" ]] && is_valid_cidr "$AD_CLIENT_CIDR"; then
        printf '%s' "$AD_CLIENT_CIDR"
        return 0
    fi

    if [[ -n "${AD_CIDR:-}" ]]; then
        cidr="$(cidr_from_interface "$AD_CIDR")"
        if [[ -n "$cidr" ]] && is_valid_cidr "$cidr"; then
            printf '%s' "$cidr"
            return 0
        fi
    fi

    if [[ -n "${AD_IFACE:-}" ]]; then
        cidr="$(
            ip -4 -o addr show dev "$AD_IFACE" scope global 2>/dev/null |
            awk 'NR==1{print $4}' || true
        )"
        if [[ -n "$cidr" ]]; then
            cidr="$(cidr_from_interface "$cidr")"
            if [[ -n "$cidr" ]] && is_valid_cidr "$cidr"; then
                printf '%s' "$cidr"
                return 0
            fi
        fi
    fi

    return 1
}

validate_ntp_source_token() {
    local source="$1"

    # The assistant accepts one hostname or IPv4 address, not a complete
    # chrony directive. This prevents accidental values such as
    # "pool pool.ntp.org" from generating malformed configuration.
    [[ -n "$source" && "$source" != *[[:space:]]* ]] || return 1
    is_valid_ipv4 "$source" && return 0
    is_valid_dns_name "$source"
}

chrony_validate_config() {
    local label="${1:-current}"
    local quiet="${2:-no}"
    local config="" output="" rc=0 daemon=""

    daemon="$(chronyd_binary 2>/dev/null || true)"
    if [[ -z "$daemon" ]]; then
        [[ "$quiet" == "yes" ]] || {
            msg_error "chronyd binary was not found."
            printf '  Package state : %s\n' "$(chrony_package_status)" >&2
            printf '  Expected path : /usr/sbin/chronyd\n' >&2
            printf '  Current PATH  : %s\n' "$PATH" >&2
        }
        return 127
    fi

    config="$(chrony_main_config)" || {
        [[ "$quiet" == "yes" ]] || msg_error "Chrony main configuration file was not found."
        return 1
    }

    output="${RUN_ROOT}/chrony-validation-${label//[^A-Za-z0-9_.-]/_}.txt"

    if "$daemon" -p -f "$config" >"$output" 2>&1; then
        return 0
    else
        rc=$?
    fi

    if [[ "$quiet" != "yes" ]]; then
        msg_error "Chrony configuration validation failed (rc=$rc)."
        printf '  chronyd    : %s\n' "$daemon" >&2
        printf '  Main config: %s\n' "$config" >&2
        printf '  Evidence   : %s\n' "$output" >&2
        printf '\n%bChrony parser output:%b\n' "$C_YELLOW" "$C_RESET" >&2
        tail -n 50 "$output" >&2 || true
    fi

    return "$rc"
}

chrony_service_restart_safe() {
    local unit="" status_file=""

    unit="$(chrony_service_unit)" || {
        msg_error "Chrony systemd service unit could not be identified."
        return 1
    }

    status_file="${RUN_ROOT}/chrony-service-status.txt"

    systemctl enable "$unit" >/dev/null 2>&1 || true

    if ! systemctl restart "$unit"; then
        systemctl status "$unit" --no-pager --full >"$status_file" 2>&1 || true
        journalctl -u "$unit" -b --no-pager -n 80 >>"$status_file" 2>&1 || true
        msg_error "Failed to restart $unit."
        printf '  Evidence: %s\n' "$status_file" >&2
        tail -n 50 "$status_file" >&2 || true
        return 1
    fi

    if ! systemctl is-active --quiet "$unit"; then
        systemctl status "$unit" --no-pager --full >"$status_file" 2>&1 || true
        journalctl -u "$unit" -b --no-pager -n 80 >>"$status_file" 2>&1 || true
        msg_error "$unit did not return ACTIVE after restart."
        printf '  Evidence: %s\n' "$status_file" >&2
        tail -n 50 "$status_file" >&2 || true
        return 1
    fi

    return 0
}

chrony_restore_file_snapshot() {
    local target="$1" snapshot="$2" existed="$3"

    if [[ "$existed" -eq 1 ]]; then
        cp -a "$snapshot" "$target"
    else
        rm -f "$target"
    fi
}

show_chrony_diagnostics() {
    section "CHRONY DIAGNOSTICS"

    local config="" unit="" parser_file="${RUN_ROOT}/chrony-parser-current.txt"
    local fragment signed daemon="" client="" pkg=""

    config="$(chrony_main_config 2>/dev/null || true)"
    unit="$(chrony_service_unit 2>/dev/null || true)"
    fragment="$(chrony_managed_fragment)"
    signed="$(chrony_signed_fragment)"
    daemon="$(chronyd_binary 2>/dev/null || true)"
    client="$(chronyc_binary 2>/dev/null || true)"
    pkg="$(chrony_package_status)"

    printf '  %-27s %s\n' "Package chrony" "${pkg:-not installed / unknown}"
    printf '  %-27s %s\n' "chronyd binary" "${daemon:-missing}"
    printf '  %-27s %s\n' "chronyc binary" "${client:-missing}"
    printf '  %-27s %s\n' "PATH" "$PATH"
    printf '  %-27s %s\n' "Chrony version" \
        "$(if [[ -n "$daemon" ]]; then "$daemon" -v 2>/dev/null | head -n1; else printf 'unknown'; fi)"
    printf '  %-27s %s\n' "systemd unit" "${unit:-not detected}"
    printf '  %-27s %s\n' "main config" "${config:-not detected}"
    printf '  %-27s %s\n' "managed fragment" "$fragment"
    printf '  %-27s %s\n' "signed-time fragment" "$signed"

    if [[ -n "$unit" ]]; then
        printf '  %-27s %s\n' "service state" "$(safe_systemctl_state "$unit")"
        printf '  %-27s %s\n' "service enabled" "$(safe_systemctl_enabled "$unit")"
    fi

    printf '\n'
    if [[ -f "$fragment" ]]; then
        printf '%bManaged time fragment:%b\n' "$C_BOLD" "$C_RESET"
        nl -ba "$fragment"
    else
        printf '%bManaged time fragment:%b not present\n' "$C_BOLD" "$C_RESET"
    fi

    if [[ -f "$signed" ]]; then
        printf '\n%bSigned-time fragment:%b\n' "$C_BOLD" "$C_RESET"
        nl -ba "$signed"
    fi

    printf '\n%bPackage files:%b\n' "$C_BOLD" "$C_RESET"
    if command_exists dpkg && chrony_package_installed; then
        dpkg -L chrony 2>/dev/null | grep -E '/(chronyd|chronyc|chrony\.service)$' || true
    else
        printf '  chrony package not installed or dpkg unavailable\n'
    fi

    printf '\n%bParser validation:%b\n' "$C_BOLD" "$C_RESET"
    if [[ -n "$daemon" && -n "$config" ]] && "$daemon" -p -f "$config" >"$parser_file" 2>&1; then
        result PASS "Chrony syntax" "$config" "valid"
        printf '  Expanded configuration saved to %s\n' "$parser_file"
    else
        result FAIL "Chrony syntax" "${config:-not detected}" "valid"
        printf '  Parser evidence: %s\n' "$parser_file"
        tail -n 50 "$parser_file" 2>/dev/null || true
    fi

    if [[ -n "$unit" ]]; then
        printf '\n%bService status:%b\n' "$C_BOLD" "$C_RESET"
        systemctl status "$unit" --no-pager --full 2>&1 | tail -n 35 || true
    fi

    if [[ -n "$client" ]]; then
        printf '\n%bchronyc tracking:%b\n' "$C_BOLD" "$C_RESET"
        "$client" -n tracking 2>&1 || true
        printf '\n%bchronyc sources:%b\n' "$C_BOLD" "$C_RESET"
        "$client" -n sources -v 2>&1 || true
        printf '\n  Source legend: ^* selected, ^+ candidate, ^? unreachable/insufficient data.\n'
        printf '\n%bchronyc activity:%b\n' "$C_BOLD" "$C_RESET"
        "$client" -n activity 2>&1 || true
        printf '\n%b10-second synchronization probe:%b\n' "$C_BOLD" "$C_RESET"
        if "$client" -n waitsync 2 0 0 5 >/dev/null 2>&1; then
            printf '  %bSYNCHRONIZED%b\n' "$C_GREEN" "$C_RESET"
        else
            printf '  %bNOT SYNCHRONIZED within 10 seconds%b\n' "$C_YELLOW" "$C_RESET"
        fi
    fi

    printf '\n'
    printf 'Manual discovery commands:\n'
    printf '  dpkg-query -W chrony\n'
    printf '  dpkg -L chrony | grep -E "/(chronyd|chronyc)$"\n'
    printf '  command -v chronyd || ls -l /usr/sbin/chronyd\n'
    if [[ -n "$daemon" && -n "$config" ]]; then
        printf '  sudo %q -p -f %q\n' "$daemon" "$config"
    else
        printf '  sudo /usr/sbin/chronyd -p -f /etc/chrony/chrony.conf\n'
    fi
    if [[ -n "$unit" ]]; then
        printf '  sudo systemctl status %s\n' "$unit"
        printf '  sudo journalctl -u %s -b --no-pager -n 100\n' "$unit"
    fi
}

get_ntp_signd_dir() {
    local dir=""
    if command_exists samba; then
        dir="$(samba -b 2>/dev/null | awk -F': ' '/NTP_SIGND_SOCKET_DIR/{print $2;exit}' | xargs || true)"
    fi
    [[ -n "$dir" ]] || dir="/var/lib/samba/ntp_signd"
    printf '%s' "$dir"
}

get_chrony_runtime_group() {
    local candidate
    for candidate in _chrony chrony; do
        getent group "$candidate" >/dev/null 2>&1 && { printf '%s' "$candidate"; return 0; }
    done
    return 1
}

chrony_supports_ntp_signd() {
    local tmp dir daemon=""
    daemon="$(chronyd_binary 2>/dev/null || true)"
    [[ -n "$daemon" ]] || return 1

    dir="$(get_ntp_signd_dir)"
    tmp="${RUN_ROOT}/chrony-ntpsignd-test.conf"
    printf 'ntpsigndsocket %s\n' "$dir" >"$tmp"
    "$daemon" -p -f "$tmp" >/dev/null 2>&1
}


chrony_tracking_leap_status() {
    local client=""
    client="$(chronyc_binary 2>/dev/null || true)"
    [[ -n "$client" ]] || return 1
    "$client" -n tracking 2>/dev/null |
        awk -F': ' '/^Leap status[[:space:]]*:/{print $2;exit}'
}

chrony_selected_source_count() {
    local client=""
    client="$(chronyc_binary 2>/dev/null || true)"
    [[ -n "$client" ]] || { printf '0'; return 1; }
    "$client" -n sources 2>/dev/null |
        awk '/^[#\^]\*/ {n++} END {print n+0}'
}

chrony_reachable_source_count() {
    local client=""
    client="$(chronyc_binary 2>/dev/null || true)"
    [[ -n "$client" ]] || { printf '0'; return 1; }
    "$client" -n sources 2>/dev/null |
        awk '
            /^[#\^\?\+\-\*x~=]/ {
                if ($5 ~ /^[0-7]+$/ && $5 != "0") n++
            }
            END { print n+0 }
        '
}

chrony_capture_sync_evidence() {
    local suffix="${1:-current}"
    local client=""
    client="$(chronyc_binary 2>/dev/null || true)"
    [[ -n "$client" ]] || return 1
    "$client" -n tracking >"${RUN_ROOT}/chrony-tracking-${suffix}.txt" 2>&1 || true
    "$client" -n sources -v >"${RUN_ROOT}/chrony-sources-${suffix}.txt" 2>&1 || true
    "$client" -n activity >"${RUN_ROOT}/chrony-activity-${suffix}.txt" 2>&1 || true
    "$client" -n sourcestats >"${RUN_ROOT}/chrony-sourcestats-${suffix}.txt" 2>&1 || true
}

chrony_wait_for_sync() {
    local tries="${1:-12}"
    local interval="${2:-5}"
    local client=""
    client="$(chronyc_binary 2>/dev/null || true)"
    [[ -n "$client" ]] || return 1
    "$client" -n waitsync "$tries" 0 0 "$interval" >/dev/null 2>&1
}

chrony_report_sync_state() {
    local context="${1:-audit}"
    local wait_tries="${2:-0}"
    local wait_interval="${3:-5}"
    local leap="" selected=0 reachable=0

    if (( wait_tries > 0 )); then
        if chrony_wait_for_sync "$wait_tries" "$wait_interval"; then
            leap="$(chrony_tracking_leap_status 2>/dev/null || true)"
            chrony_capture_sync_evidence "$context"
            result PASS "Chrony synchronization" "${leap:-Normal}" "Normal"
            return 0
        fi
    fi

    leap="$(chrony_tracking_leap_status 2>/dev/null || true)"
    selected="$(chrony_selected_source_count 2>/dev/null || printf '0')"
    reachable="$(chrony_reachable_source_count 2>/dev/null || printf '0')"
    chrony_capture_sync_evidence "$context"

    if [[ "${leap,,}" == "normal" ]]; then
        result PASS "Chrony synchronization" "$leap" "Normal"
        return 0
    fi

    if (( selected > 0 )); then
        result INFO "Chrony synchronization" \
            "${leap:-unknown}; source selected, still converging" \
            "Normal"
        return 2
    fi

    if (( reachable > 0 )); then
        result INFO "Chrony synchronization" \
            "${leap:-unknown}; source(s) reachable, none selected yet" \
            "Normal after sufficient samples"
        return 2
    fi

    result WARN "Chrony synchronization" \
        "${leap:-unknown}; no reachable/selected NTP source detected" \
        "Normal"
    printf '  Evidence: %s\n' "${RUN_ROOT}/chrony-sources-${context}.txt"
    printf '            %s\n' "${RUN_ROOT}/chrony-tracking-${context}.txt"
    printf '            %s\n' "${RUN_ROOT}/chrony-activity-${context}.txt"
    return 1
}

audit_signed_domain_time() {
    section "SIGNED DOMAIN TIME / CHRONY"
    local dir group expected_group="" unit="" config=""
    dir="$(get_ntp_signd_dir)"
    expected_group="$(get_chrony_runtime_group 2>/dev/null || true)"
    unit="$(chrony_service_unit 2>/dev/null || true)"
    config="$(chrony_main_config 2>/dev/null || true)"

    if [[ -n "$unit" ]] && systemctl is-active --quiet "$unit"; then
        result PASS "Chrony service" "$unit active" "active"
    else
        result WARN "Chrony service" "${unit:-not detected}: $(safe_systemctl_state "${unit:-chrony.service}")" "active"
    fi

    if chrony_validate_config "audit" yes; then
        result PASS "Chrony syntax" "${config:-detected config}" "valid"
    else
        result FAIL "Chrony syntax" "${config:-not detected}; see ${RUN_ROOT}/chrony-validation-audit.txt" "valid"
    fi

    if chrony_supports_ntp_signd; then
        result PASS "Chrony MS-SNTP capability" "ntpsigndsocket supported" "supported"
    else
        result WARN "Chrony MS-SNTP capability" "ntpsigndsocket not accepted" "required for signed Windows domain time"
        return 0
    fi

    if [[ -d "$dir" ]]; then
        group="$(stat -c '%G' "$dir" 2>/dev/null || true)"
        result PASS "Samba ntp_signd directory" "$dir group=$group" "present"
        if [[ -n "$expected_group" && "$group" != "$expected_group" ]]; then
            result WARN "ntp_signd group access" "$group" "$expected_group"
        elif [[ -n "$expected_group" ]]; then
            result PASS "ntp_signd group access" "$group" "$expected_group"
        fi
    else
        result WARN "Samba ntp_signd directory" "$dir missing" "present after Samba AD/DC start"
    fi

    if grep -RqsE "^[[:space:]]*ntpsigndsocket[[:space:]]+${dir//\//\\/}([[:space:]]|$)" /etc/chrony 2>/dev/null; then
        result PASS "Chrony signed-time config" "$dir" "configured"
    else
        result WARN "Chrony signed-time config" "ntpsigndsocket not configured" "$dir"
    fi

    chrony_report_sync_state "audit" 0 0 || true
}

configure_signed_domain_time() {
    local dir group conf snapshot existed=0

    conf="$(chrony_signed_fragment)"

    ensure_chrony_runtime || {
        msg_warn "Chrony runtime is unavailable; signed domain time was not changed."
        return 1
    }

    chrony_supports_ntp_signd || {
        msg_warn "Installed chronyd does not accept the ntpsigndsocket directive."
        return 1
    }

    ensure_chrony_conf_d_included || return 1

    dir="$(get_ntp_signd_dir)"
    group="$(get_chrony_runtime_group 2>/dev/null || true)"
    [[ -n "$group" ]] || {
        msg_warn "Unable to determine chrony runtime group (_chrony/chrony)."
        return 1
    }

    mkdir -p "$dir" "$(dirname "$conf")"
    chown root:"$group" "$dir"
    chmod 0750 "$dir"

    snapshot="${RUN_ROOT}/$(basename "$conf").before"
    if [[ -e "$conf" ]]; then
        cp -a "$conf" "$snapshot"
        existed=1
    fi
    backup_file "$conf"

    cat >"$conf" <<EOF
# Managed by ${SCRIPT_NAME} ${SCRIPT_VERSION}
# Signed MS-SNTP responses for trusted Active Directory domain members.
ntpsigndsocket ${dir}
EOF
    chmod 0644 "$conf"

    if ! chrony_validate_config "signed-time"; then
        chrony_restore_file_snapshot "$conf" "$snapshot" "$existed"
        msg_warn "Signed-time fragment was rolled back."
        return 1
    fi

    if ! chrony_service_restart_safe; then
        chrony_restore_file_snapshot "$conf" "$snapshot" "$existed"
        chrony_service_restart_safe >/dev/null 2>&1 || true
        msg_warn "Signed-time fragment was rolled back after service failure."
        return 1
    fi

    change APPLIED "Configured Chrony signed MS-SNTP via $dir"
    result PASS "Signed domain time" "$dir / group=$group" "chrony + Samba ntp_signd"

    printf '\nWaiting up to 30 seconds for Chrony after signed-time restart...\n'
    chrony_report_sync_state "post-signed-time" 6 5 || true
}

apply_samba_safe_security_baseline() {
    section "SAMBA SAFE SECURITY BASELINE"
    printf 'This profile keeps Windows 7+/SMB2 compatibility and does NOT force SMB3 encryption or AES-only Kerberos.\n'
    printf 'It makes secure AD/DC defaults explicit and protects LDAP/SMB/NTLM downgrade surfaces.\n\n'
    confirm "Apply the compatibility-safe Samba AD/DC baseline?" N || return 0

    local snapshot="${RUN_ROOT}/smb.conf.pre-safe-hardening"
    cp -a /etc/samba/smb.conf "$snapshot"
    backup_file /etc/samba/smb.conf

    local spec key value
    local -a baseline=(
        "ldap server require strong auth|yes"
        "client ldap sasl wrapping|seal"
        "server signing|mandatory"
        "server min protocol|SMB2_02"
        "client ipc signing|mandatory"
        "ntlm auth|ntlmv2-only"
        "lanman auth|no"
        "raw NTLMv2 auth|no"
        "allow nt4 crypto|no"
        "map to guest|Never"
        "kdc force enable rc4 weak session keys|no"
    )

    for spec in "${baseline[@]}"; do
        IFS='|' read -r key value <<<"$spec"
        if samba_parameter_supported "$key"; then
            set_smb_global_option "$key" "$value"
        else
            msg_info "Skipping unsupported Samba parameter: $key"
        fi
    done

    if ! testparm -s >/dev/null 2>&1; then
        cp -a "$snapshot" /etc/samba/smb.conf
        msg_error "testparm rejected the hardened smb.conf; original configuration restored."
        return 1
    fi

    if ! systemctl restart samba-ad-dc || ! wait_for_samba; then
        cp -a "$snapshot" /etc/samba/smb.conf
        systemctl restart samba-ad-dc >/dev/null 2>&1 || true
        msg_error "Samba health check failed after hardening; original configuration restored."
        return 1
    fi

    if ! samba-tool domain info "$DC_IP" >/dev/null 2>&1; then
        cp -a "$snapshot" /etc/samba/smb.conf
        systemctl restart samba-ad-dc >/dev/null 2>&1 || true
        msg_error "Domain discovery failed after hardening; original configuration restored."
        return 1
    fi

    change APPLIED "Applied compatibility-safe Samba AD/DC security baseline"
    result PASS "Samba security baseline" "applied + service validated" "secure AD/DC defaults"
    audit_samba_transport_security
}

build_kerberos_crypto_readiness_report() {
    local raw="${RUN_ROOT}/kerberos-principals.ldif"
    local report="${RUN_ROOT}/kerberos-crypto-readiness.tsv"
    local base
    base="$(domain_dn "$DOMAIN")"

    ldbsearch -H /var/lib/samba/private/sam.ldb -b "$base" \
        '(|(objectClass=user)(objectClass=computer))' \
        sAMAccountName objectClass servicePrincipalName msDS-SupportedEncryptionTypes pwdLastSet \
        >"$raw" 2>/dev/null || return 1

    python3 - "$raw" "$report" <<'PY'
from pathlib import Path
import sys

raw = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
out = Path(sys.argv[2])

rows = []
for block in raw.split("\n\n"):
    attrs = {}
    for line in block.splitlines():
        if ": " not in line:
            continue
        k, v = line.split(": ", 1)
        attrs.setdefault(k, []).append(v)

    sam = (attrs.get("sAMAccountName") or [""])[0]
    if not sam:
        continue

    classes = [x.lower() for x in attrs.get("objectClass", [])]
    kind = "computer" if "computer" in classes else "user"
    spns = attrs.get("servicePrincipalName", [])
    enc_raw = (attrs.get("msDS-SupportedEncryptionTypes") or [""])[0]

    try:
        enc = int(enc_raw, 0) if enc_raw else 0
    except ValueError:
        enc = 0

    if enc == 0:
        state = "IMPLICIT_DEFAULT"
    else:
        has_rc4 = bool(enc & 0x4)
        has_aes = bool(enc & (0x8 | 0x10))
        if has_rc4 and has_aes:
            state = "RC4_AND_AES"
        elif has_rc4:
            state = "RC4_ONLY"
        elif has_aes:
            state = "AES_READY"
        else:
            state = "OTHER"

    # Service-bearing users and all computers matter most for migration/readiness.
    if kind == "computer" or spns:
        rows.append((sam, kind, enc_raw or "0/unset", state, len(spns)))

with out.open("w", encoding="utf-8") as fh:
    fh.write("account\tkind\tmsDS-SupportedEncryptionTypes\tclassification\tspn_count\n")
    for row in sorted(rows, key=lambda r: (r[3], r[0].lower())):
        fh.write("\t".join(map(str, row)) + "\n")
PY

    printf '%s' "$report"
}


assistant_kerberos_ticket_valid() {
    local expected="${1:-}"
    command_exists klist || return 1
    KRB5CCNAME="$KRB5CCNAME" klist -s >/dev/null 2>&1 || return 1

    [[ -z "$expected" ]] && return 0

    local current=""
    current="$(
        KRB5CCNAME="$KRB5CCNAME" klist 2>/dev/null |
        awk -F': ' '/Default principal:/{print $2;exit}' || true
    )"
    [[ "${current^^}" == "${expected^^}" ]]
}

caller_kerberos_ticket_evidence() {
    local outfile="$1"
    local caller="${SUDO_USER:-}"
    local -a env_args=()

    [[ -n "$caller" && "$caller" != "root" ]] || return 1
    command_exists sudo || return 1
    command_exists klist || return 1

    if [[ -n "${INHERITED_KRB5CCNAME:-}" ]]; then
        env_args=("KRB5CCNAME=${INHERITED_KRB5CCNAME}")
    fi

    if sudo -u "$caller" env "${env_args[@]}" klist -s >/dev/null 2>&1; then
        sudo -u "$caller" env "${env_args[@]}" klist -e >"$outfile" 2>&1 || true
        return 0
    fi

    # If the caller did not export KRB5CCNAME, try the conventional FILE cache.
    local uid=""
    uid="$(id -u "$caller" 2>/dev/null || true)"
    if [[ -n "$uid" && -r "/tmp/krb5cc_${uid}" ]]; then
        if sudo -u "$caller" env KRB5CCNAME="FILE:/tmp/krb5cc_${uid}" \
            klist -s >/dev/null 2>&1; then
            sudo -u "$caller" env KRB5CCNAME="FILE:/tmp/krb5cc_${uid}" \
                klist -e >"$outfile" 2>&1 || true
            return 0
        fi
    fi

    return 1
}

audit_kerberos_ticket_evidence() {
    local principal="${ADMIN_USER:-Administrator}@${REALM}"
    local assistant_out="${RUN_ROOT}/kerberos-ticket-enctypes.txt"
    local caller_out="${RUN_ROOT}/kerberos-caller-ticket-enctypes.txt"

    # Security audit must never request a password. If a private assistant
    # ticket already exists, use it. Otherwise report the missing evidence and
    # continue.
    if assistant_kerberos_ticket_valid "$principal"; then
        if command_exists kvno; then
            KRB5CCNAME="$KRB5CCNAME" kvno "ldap/${DC_FQDN}" >/dev/null 2>&1 || true
            KRB5CCNAME="$KRB5CCNAME" kvno "cifs/${DC_FQDN}" >/dev/null 2>&1 || true
        fi

        KRB5CCNAME="$KRB5CCNAME" klist -e >"$assistant_out" 2>&1 || true

        if grep -Eiq 'arcfour|rc4' "$assistant_out"; then
            result WARN "Current Kerberos ticket enctypes" \
                "RC4/arcfour observed in isolated assistant cache" \
                "AES preferred"
        else
            result PASS "Current Kerberos ticket enctypes" \
                "no RC4 observed in isolated assistant cache" \
                "AES"
        fi
        printf '  %-31s %s\n' "Ticket enctype evidence" "$assistant_out"
        return 0
    fi

    if caller_kerberos_ticket_evidence "$caller_out"; then
        local caller_principal=""
        caller_principal="$(
            awk -F': ' '/Default principal:/{print $2;exit}' "$caller_out" 2>/dev/null || true
        )"

        result INFO "Kerberos ticket evidence" \
            "caller cache detected (${caller_principal:-unknown principal}); not imported into privileged assistant cache" \
            "isolated-cache policy"

        if grep -Eiq 'arcfour|rc4' "$caller_out"; then
            result WARN "Caller ticket enctypes" \
                "RC4/arcfour observed; evidence only" \
                "AES preferred"
        else
            result INFO "Caller ticket enctypes" \
                "no RC4 observed in caller cache" \
                "evidence only"
        fi

        printf '  %-31s %s\n' "Caller ticket evidence" "$caller_out"
        return 0
    fi

    result INFO "Kerberos ticket evidence" \
        "no valid ticket in isolated assistant cache; service-ticket check skipped" \
        "not required for read-only crypto inventory"
    return 0
}

format_samba_kdc_enctype_setting() {
    local key="$1" value=""
    value="$(samba_effective_value "$key" 2>/dev/null || true)"

    if [[ "$value" == "0" || -z "$value" ]]; then
        case "$key" in
            "kdc supported enctypes")
                printf '0 (automatic: software-supported enctypes)'
                ;;
            "kdc default domain supported enctypes")
                printf '0 (automatic/default; DFL-dependent)'
                ;;
            *)
                printf '%s' "${value:-default}"
                ;;
        esac
    else
        printf '%s' "$value"
    fi
}

audit_kerberos_crypto_readiness() {
    section "KERBEROS CRYPTO READINESS"
    local report="" rc4_only=0 transitional=0 implicit=0 aes=0

    if samba_parameter_supported "kdc supported enctypes"; then
        result INFO "KDC supported enctypes" \
            "$(format_samba_kdc_enctype_setting 'kdc supported enctypes')" \
            "review before AES-only"
    fi

    if samba_parameter_supported "kdc default domain supported enctypes"; then
        result INFO "KDC default domain enctypes" \
            "$(format_samba_kdc_enctype_setting 'kdc default domain supported enctypes')" \
            "AES preferred"
    fi

    if samba_parameter_supported "kerberos encryption types"; then
        result INFO "Samba Kerberos client enctypes" \
            "$(samba_effective_value 'kerberos encryption types')" \
            "strong for AES-only profile"
    fi

    samba-tool domain level show >"${RUN_ROOT}/domain-functional-level.txt" 2>&1 || true
    result INFO "Domain functional level" \
        "$(tr '\n' '; ' <"${RUN_ROOT}/domain-functional-level.txt" | cut -c1-180)" \
        "2008+ required for normal AES use"

    if report="$(build_kerberos_crypto_readiness_report)"; then
        rc4_only="$(awk -F'\t' '$4=="RC4_ONLY"{n++}END{print n+0}' "$report")"
        transitional="$(awk -F'\t' '$4=="RC4_AND_AES"{n++}END{print n+0}' "$report")"
        implicit="$(awk -F'\t' '$4=="IMPLICIT_DEFAULT"{n++}END{print n+0}' "$report")"
        aes="$(awk -F'\t' '$4=="AES_READY"{n++}END{print n+0}' "$report")"

        (( rc4_only == 0 )) \
            && result PASS "Explicit RC4-only principals" "0" "0" \
            || result WARN "Explicit RC4-only principals" "$rc4_only" "0 before AES-only enforcement"

        (( transitional == 0 )) \
            && result PASS "Explicit RC4+AES principals" "0" "0 preferred" \
            || result WARN "Explicit RC4+AES principals" "$transitional" "review/remove RC4 where possible"

        result INFO "Implicit/default enctypes" "$implicit" \
            "resolved by KDC defaults; validate service interoperability"
        result INFO "Explicit AES-ready principals" "$aes" "informational"
        printf '  %-31s %s\n' "Readiness report" "$report"
    else
        result WARN "Kerberos principal scan" "failed" "review manually"
    fi

    # Optional evidence only. This audit is intentionally non-interactive and
    # must never ask for an AD password or abort because a ccache is empty.
    audit_kerberos_ticket_evidence || true

    return 0
}

apply_kerberos_aes_only_profile() {
    section "KERBEROS AES-ONLY ENFORCEMENT"

    local report rc4_only snapshot="${RUN_ROOT}/smb.conf.pre-aes-only"
    report="$(build_kerberos_crypto_readiness_report)" || {
        msg_warn "Cannot build Kerberos readiness report. AES-only enforcement is blocked."
        return 1
    }
    rc4_only="$(awk -F'\t' '$4=="RC4_ONLY"{n++}END{print n+0}' "$report")"

    if (( rc4_only > 0 )); then
        msg_error "AES-only enforcement blocked: $rc4_only principal(s) explicitly advertise RC4 without AES."
        printf 'Review: %s\n' "$report"
        return 1
    fi

    for key in "kerberos encryption types" "kdc supported enctypes" "kdc default domain supported enctypes"; do
        samba_parameter_supported "$key" || {
            msg_error "Installed Samba does not support required AES-only control: $key"
            return 1
        }
    done

    printf 'This can break legacy devices, trusts, service accounts or third-party Kerberos implementations.\n'
    printf 'Windows 7 supports AES, but old accounts/devices may still lack usable AES keys.\n'
    printf 'Readiness evidence: %s\n\n' "$report"

    create_domain_backup no
    confirm_high_risk "Enforce AES-only Kerberos ticket encryption on this Samba AD/DC" || return 0

    cp -a /etc/samba/smb.conf "$snapshot"
    backup_file /etc/samba/smb.conf

    set_smb_global_option "kerberos encryption types" "strong"
    set_smb_global_option "kdc supported enctypes" "aes128-cts-hmac-sha1-96 aes256-cts-hmac-sha1-96"
    set_smb_global_option "kdc default domain supported enctypes" "aes128-cts-hmac-sha1-96 aes256-cts-hmac-sha1-96"
    samba_parameter_supported "kdc force enable rc4 weak session keys" &&
        set_smb_global_option "kdc force enable rc4 weak session keys" "no"

    if ! testparm -s >/dev/null 2>&1 || ! systemctl restart samba-ad-dc || ! wait_for_samba; then
        cp -a "$snapshot" /etc/samba/smb.conf
        systemctl restart samba-ad-dc >/dev/null 2>&1 || true
        msg_error "AES-only profile failed service validation; smb.conf restored."
        return 1
    fi

    KRB5CCNAME="$KRB5CCNAME" kdestroy >/dev/null 2>&1 || true
    local principal="${ADMIN_USER}@${REALM}"
    if ! KRB5CCNAME="$KRB5CCNAME" kinit "$principal" <"$INPUT_FD"; then
        cp -a "$snapshot" /etc/samba/smb.conf
        systemctl restart samba-ad-dc >/dev/null 2>&1 || true
        msg_error "Fresh Kerberos authentication failed under AES-only profile; smb.conf restored."
        return 1
    fi

    if command_exists kvno && ! KRB5CCNAME="$KRB5CCNAME" kvno "ldap/${DC_FQDN}" >/dev/null 2>&1; then
        cp -a "$snapshot" /etc/samba/smb.conf
        systemctl restart samba-ad-dc >/dev/null 2>&1 || true
        msg_error "LDAP service ticket failed under AES-only profile; smb.conf restored."
        return 1
    fi

    change APPLIED "Enforced Samba KDC AES-only encryption profile"
    result PASS "Kerberos AES-only profile" "AES128 + AES256 / Samba client strong" "validated with fresh ticket"
}

restore_kerberos_compatibility_defaults() {
    section "RESTORE SAMBA KERBEROS COMPATIBILITY DEFAULTS"
    printf 'This removes assistant-enforced AES-only overrides and returns to the installed Samba defaults.\n'
    confirm_high_risk "Remove explicit Samba KDC/client enctype restrictions" || return 0

    local snapshot="${RUN_ROOT}/smb.conf.pre-kerberos-defaults"
    cp -a /etc/samba/smb.conf "$snapshot"
    backup_file /etc/samba/smb.conf

    remove_smb_global_option "kerberos encryption types"
    remove_smb_global_option "kdc supported enctypes"
    remove_smb_global_option "kdc default domain supported enctypes"

    if ! testparm -s >/dev/null 2>&1 || ! systemctl restart samba-ad-dc || ! wait_for_samba; then
        cp -a "$snapshot" /etc/samba/smb.conf
        systemctl restart samba-ad-dc >/dev/null 2>&1 || true
        msg_error "Compatibility-default restoration failed; previous smb.conf restored."
        return 1
    fi

    change APPLIED "Removed explicit Samba Kerberos enctype overrides"
    result PASS "Kerberos compatibility defaults" "installed Samba defaults restored" "service healthy"
}

audit_samba_kerberos_security() {
    audit_samba_transport_security || true
    audit_kerberos_client_config || true
    audit_kerberos_crypto_readiness || true
    audit_signed_domain_time || true
    return 0
}

samba_kerberos_security_menu() {
    while true; do
        (( MENU_MAIN_REQUESTED )) && return 0
        ui_menu_screen "SAMBA & KERBEROS SECURITY" "Protocol hardening, KDC crypto posture, signed time and compatibility-safe remediation"
        ui_menu_item "1" "Full security audit" "Samba transport/auth, Kerberos config/crypto and signed time"
        ui_menu_item "2" "Safe Samba baseline" "LDAP strong auth, signing, SMB2+, NTLMv2-only and legacy crypto blocks" "$C_GREEN"
        ui_menu_item "3" "Kerberos config audit" "Realm, generated config provenance, weak crypto and ticket cache"
        ui_menu_item "4" "Repair krb5.conf" "Restore Samba-generated Kerberos client configuration"
        ui_menu_item "5" "Kerberos crypto readiness" "Non-interactive principal/SPN inventory; ticket evidence is optional"
        ui_menu_item "6" "Enforce AES-only KDC" "Advanced: block RC4 after readiness scan + domain backup" "$C_RED"
        ui_menu_item "7" "Restore KDC defaults" "Remove explicit AES-only overrides and use Samba defaults" "$C_YELLOW"
        ui_menu_item "8" "Signed domain time" "Audit Chrony + Samba ntp_signd integration"
        ui_menu_item "9" "Configure signed time" "Enable Chrony MS-SNTP signing for trusted AD clients" "$C_GREEN"
        ui_menu_item "10" "Samba transport audit" "SMB, LDAP, NTLM, schannel and custom-share posture"
        ui_menu_item "11" "Chrony diagnostics" "Show config path, parser output, systemd unit, tracking and sources"
        ui_menu_exit
        ui_rule

        local choice
        choice="$(ask 'Select security operation' '1')"
        case "$choice" in
            1) audit_samba_kerberos_security; ui_pause ;;
            2) apply_samba_safe_security_baseline; ui_pause ;;
            3) audit_kerberos_client_config || true; ui_pause ;;
            4) repair_kerberos_client_config; ui_pause ;;
            5) audit_kerberos_crypto_readiness || true; ui_pause ;;
            6) apply_kerberos_aes_only_profile; ui_pause ;;
            7) restore_kerberos_compatibility_defaults; ui_pause ;;
            8) audit_signed_domain_time || true; ui_pause ;;
            9)
                if ! configure_signed_domain_time; then
                    msg_warn "Signed-domain-time configuration was not applied."
                fi
                ui_pause
                ;;
            10) audit_samba_transport_security || true; ui_pause ;;
            11) show_chrony_diagnostics; ui_pause ;;
            H|h) MENU_MAIN_REQUESTED=1; break ;;
            0) break ;;
            *) msg_warn "Invalid security operation."; ui_pause ;;
        esac
    done
}

kerberos_security_menu() {
    samba_kerberos_security_menu
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


samba_required_ports() {
    printf '%s\n' 53 88 389 445 464
}

samba_listener_snapshot() {
    ss -H -lntup 2>/dev/null || true
}

samba_missing_required_ports() {
    local listeners="${1:-}" port
    [[ -n "$listeners" ]] || listeners="$(samba_listener_snapshot)"

    while IFS= read -r port; do
        [[ -n "$port" ]] || continue
        if ! grep -Eq ":${port}([[:space:]]|$)" <<<"$listeners"; then
            printf '%s\n' "$port"
        fi
    done < <(samba_required_ports)
}

samba_required_listeners_ready() {
    systemctl is-active --quiet samba-ad-dc || return 1

    local listeners="" missing=""
    listeners="$(samba_listener_snapshot)"
    missing="$(samba_missing_required_ports "$listeners")"
    [[ -z "$missing" ]]
}

capture_samba_runtime_evidence() {
    local label="${1:-runtime}"
    local prefix="${RUN_ROOT}/samba-${label}"
    local listeners="" missing=""

    listeners="$(samba_listener_snapshot)"
    missing="$(samba_missing_required_ports "$listeners" | paste -sd, -)"

    systemctl status samba-ad-dc --no-pager --full >"${prefix}-status.txt" 2>&1 || true
    journalctl -u samba-ad-dc -b --no-pager -n 200 >"${prefix}-journal.txt" 2>&1 || true
    printf '%s\n' "$listeners" >"${prefix}-listeners.txt"

    {
        printf 'timestamp=%s\n' "$(date -Is)"
        printf 'service_state=%s\n' "$(safe_systemctl_state samba-ad-dc)"
        printf 'missing_ports=%s\n' "${missing:-none}"
    } >"${prefix}-summary.txt"
}

ensure_samba_runtime_health() {
    [[ "$SAMBA_ROLE" == "ad-dc" || "$SAMBA_ROLE" == "ad-dc-config" ]] || return 0

    if samba_required_listeners_ready; then
        return 0
    fi

    local before="" missing_before="" after="" missing_after=""
    before="$(samba_listener_snapshot)"
    missing_before="$(samba_missing_required_ports "$before" | paste -sd, -)"
    capture_samba_runtime_evidence "pre-selfheal"

    # Automatic only when the current AD/DC is already degraded.
    # Merely opening the assistant never restarts a healthy DC.
    msg_info "Samba AD/DC runtime incomplete (missing listener(s): ${missing_before:-unknown}); attempting one controlled restart."

    if ! systemctl restart samba-ad-dc >/dev/null 2>&1; then
        capture_samba_runtime_evidence "restart-failed"
        result WARN "Samba runtime self-heal" \
            "restart failed; evidence saved under $RUN_ROOT" \
            "manual investigation required"
        return 1
    fi

    if wait_for_samba 60; then
        capture_samba_runtime_evidence "post-selfheal"
        result PASS "Samba runtime self-heal" \
            "listeners 53/88/389/445/464 restored after one controlled restart" \
            "healthy"
        return 0
    fi

    after="$(samba_listener_snapshot)"
    missing_after="$(samba_missing_required_ports "$after" | paste -sd, -)"
    capture_samba_runtime_evidence "post-selfheal-failed"
    result WARN "Samba runtime self-heal" \
        "still missing listener(s): ${missing_after:-unknown}; evidence saved under $RUN_ROOT" \
        "manual investigation required"
    return 1
}

samba_boot_health_guard_installed() {
    [[ -x "$SAMBA_HEALTH_HELPER" && -f "$SAMBA_HEALTH_SERVICE" ]] || return 1
    systemctl is-enabled --quiet debian-ad-samba-health.service 2>/dev/null
}

install_samba_boot_health_guard() {
    local helper="$SAMBA_HEALTH_HELPER"
    local service="$SAMBA_HEALTH_SERVICE"

    mkdir -p /usr/local/libexec
    backup_file "$helper"
    backup_file "$service"

    cat >"$helper" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail

initial_timeout="${1:-45}"
recovery_timeout="${2:-60}"
tag="debian-ad-samba-health"

snapshot() {
    /usr/bin/ss -H -lntup 2>/dev/null || true
}

missing_ports() {
    local listeners="${1:-}" port=""
    [[ -n "$listeners" ]] || listeners="$(snapshot)"

    for port in 53 88 389 445 464; do
        if ! /usr/bin/grep -Eq ":${port}([[:space:]]|$)" <<<"$listeners"; then
            printf '%s\n' "$port"
        fi
    done
}

healthy() {
    /usr/bin/systemctl is-active --quiet samba-ad-dc.service || return 1

    local listeners="" missing=""
    listeners="$(snapshot)"
    missing="$(missing_ports "$listeners")"
    [[ -z "$missing" ]]
}

wait_healthy() {
    local timeout="$1" i
    for ((i=0; i<timeout; i++)); do
        if healthy; then
            return 0
        fi
        /usr/bin/sleep 1
    done
    return 1
}

if wait_healthy "$initial_timeout"; then
    /usr/bin/logger -t "$tag" \
        "Samba AD/DC listeners healthy after boot; no restart required."
    exit 0
fi

before="$(missing_ports "$(snapshot)" | /usr/bin/paste -sd, -)"
/usr/bin/logger -p daemon.warning -t "$tag" \
    "Samba AD/DC started incompletely; missing listener(s): ${before:-unknown}. Performing one controlled restart."

if ! /usr/bin/systemctl restart samba-ad-dc.service; then
    /usr/bin/logger -p daemon.err -t "$tag" \
        "Controlled Samba restart failed. Manual investigation required."
    exit 1
fi

if wait_healthy "$recovery_timeout"; then
    /usr/bin/logger -p daemon.notice -t "$tag" \
        "Samba AD/DC listener self-heal succeeded after one restart."
    exit 0
fi

after="$(missing_ports "$(snapshot)" | /usr/bin/paste -sd, -)"
/usr/bin/logger -p daemon.err -t "$tag" \
    "Samba AD/DC still unhealthy after restart; missing listener(s): ${after:-unknown}."
exit 1
EOF
    chmod 0755 "$helper"

    cat >"$service" <<EOF
[Unit]
Description=Verify and self-heal Samba AD/DC listeners after boot
Documentation=man:samba(8)
Wants=network-online.target samba-ad-dc.service
After=network-online.target debian-ad-network-ready.service samba-ad-dc.service

[Service]
Type=oneshot
ExecStart=${helper} 45 60
TimeoutStartSec=120

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable debian-ad-samba-health.service >/dev/null

    change APPLIED "Installed Samba AD/DC post-boot listener health guard"
    result PASS "Samba boot listener guard" \
        "53/88/389/445/464 + one conditional restart" \
        "enabled"
}

upgrade_samba_boot_health_guard_if_managed() {
    # Older assistant builds already own these files. Extend that managed boot
    # policy in-place; do not silently adopt unrelated/custom systemd units.
    if [[ -f /etc/systemd/system/debian-ad-network-ready.service &&
          -f /etc/systemd/system/samba-ad-dc.service.d/20-debian-ad-network.conf ]]; then
        if ! samba_boot_health_guard_installed; then
            install_samba_boot_health_guard
        fi
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
    addresses="$(/usr/sbin/ip -4 -o addr show dev "$iface" scope global 2>/dev/null || true)"
    if /usr/bin/grep -Fq " ${ip_addr}/" <<<"$addresses"; then
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

    install_samba_boot_health_guard

    # Verify current runtime too. Healthy Samba is untouched; an incomplete
    # instance receives at most one controlled restart.
    ensure_samba_runtime_health || true

    change APPLIED "Samba waits for $AD_IFACE/$DC_IP before boot"
    result PASS "Samba boot ordering" "$AD_IFACE $DC_IP" \
        "network guard + post-boot listener self-heal"
}

audit_samba_boot_persistence() {
    local enabled guard health missing=""
    enabled="$(safe_systemctl_enabled samba-ad-dc)"
    [[ "$enabled" == "enabled" ]] \
        && result PASS "samba-ad-dc boot" "$enabled" "enabled" \
        || result FAIL "samba-ad-dc boot" "$enabled" "enabled"

    guard="$(safe_systemctl_enabled debian-ad-network-ready.service)"
    if [[ "$guard" == "enabled" &&
          -f /etc/systemd/system/samba-ad-dc.service.d/20-debian-ad-network.conf ]]; then
        result PASS "AD network boot guard" "enabled" "wait before Samba"
    else
        result WARN "AD network boot guard" "$guard" "configure from Security menu"
    fi

    health="$(safe_systemctl_enabled debian-ad-samba-health.service)"
    if [[ "$health" == "enabled" &&
          -x "$SAMBA_HEALTH_HELPER" &&
          -f "$SAMBA_HEALTH_SERVICE" ]]; then
        result PASS "AD listener boot guard" \
            "enabled" \
            "conditional recovery for 53/88/389/445/464"
    else
        result WARN "AD listener boot guard" \
            "$health" \
            "repair Boot ordering to install listener self-heal"
    fi

    if systemctl is-active --quiet samba-ad-dc; then
        missing="$(samba_missing_required_ports "$(samba_listener_snapshot)" | paste -sd, -)"
        if [[ -z "$missing" ]]; then
            result PASS "AD runtime listeners" "53/88/389/445/464 present" "healthy"
        else
            result WARN "AD runtime listeners" \
                "missing: $missing" \
                "runtime self-heal available"
        fi
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


# ---------------------------------------------------------------------------
# Persistent resolver management for Samba AD DNS
# ---------------------------------------------------------------------------

resolv_conf_description() {
    local link_target=""
    if [[ -L /etc/resolv.conf ]]; then
        link_target="$(readlink /etc/resolv.conf 2>/dev/null || true)"
        if [[ -e /etc/resolv.conf ]]; then
            printf 'symlink -> %s' "$link_target"
        else
            printf 'BROKEN symlink -> %s' "$link_target"
        fi
    elif [[ -f /etc/resolv.conf ]]; then
        printf 'regular file'
    elif [[ -e /etc/resolv.conf ]]; then
        printf 'non-regular object'
    else
        printf 'missing'
    fi
}

resolv_conf_is_broken_or_stub_without_resolved() {
    local link_target="" resolved_state=""
    [[ -L /etc/resolv.conf ]] || return 1
    link_target="$(readlink /etc/resolv.conf 2>/dev/null || true)"
    [[ -e /etc/resolv.conf ]] || return 0
    resolved_state="$(safe_systemctl_state systemd-resolved)"
    [[ "$link_target" == *"/run/systemd/resolve/"* && "$resolved_state" != "active" ]]
}

write_regular_resolv_conf() {
    local nameserver="$1"
    local search_domain="${2:-}"
    local tmp="${RUN_ROOT}/resolv.conf.new"

    {
        printf '# Managed by %s %s\n' "$SCRIPT_NAME" "$SCRIPT_VERSION"
        printf '# Samba AD DC resolver. External DNS is forwarded by Samba.\n'
        printf 'nameserver %s\n' "$nameserver"
        [[ -n "$search_domain" ]] && printf 'search %s\n' "$search_domain"
        printf 'options timeout:2 attempts:2\n'
    } >"$tmp"

    chmod 0644 "$tmp"

    # Do not follow a systemd-resolved symlink into /run. Replace the pathname
    # itself so /etc/resolv.conf survives reboot as a normal file.
    rm -f /etc/resolv.conf
    install -o root -g root -m 0644 "$tmp" /etc/resolv.conf

    [[ -f /etc/resolv.conf && ! -L /etc/resolv.conf ]] || {
        fail_msg "/etc/resolv.conf was not converted to a persistent regular file."
        return 1
    }
}

write_ad_resolv_conf() {
    [[ -n "${DOMAIN:-}" ]] || {
        fail_msg "Cannot write AD resolver configuration without DOMAIN."
        return 1
    }
    write_regular_resolv_conf "127.0.0.1" "$DOMAIN"
}

validate_system_dc_locator() {
    [[ -n "${DOMAIN:-}" && -n "${DC_FQDN:-}" ]] || return 1
    command_exists dig || return 1

    local srv
    srv="$(dig +time=3 +tries=1 +short SRV "_ldap._tcp.dc._msdcs.${DOMAIN}" 2>/dev/null || true)"
    grep -Fiq "$DC_FQDN" <<<"$srv"
}

audit_local_resolver_state() {
    local desc resolved_state fail=0
    desc="$(resolv_conf_description)"
    resolved_state="$(safe_systemctl_state systemd-resolved)"

    if resolv_conf_is_broken_or_stub_without_resolved; then
        result FAIL "Local resolver file" "$desc; systemd-resolved=$resolved_state" \
            "regular /etc/resolv.conf -> 127.0.0.1"
        return 1
    fi

    if [[ ! -f /etc/resolv.conf ]]; then
        result FAIL "Local resolver file" "$desc" "readable regular file"
        return 1
    fi

    if [[ -L /etc/resolv.conf ]]; then
        result WARN "Local resolver file" "$desc" "regular file managed by assistant"
        fail=1
    elif grep -Eq '^[[:space:]]*nameserver[[:space:]]+127\.0\.0\.1([[:space:]]|$)' /etc/resolv.conf; then
        result PASS "Local resolver file" "regular; nameserver=127.0.0.1" "persistent Samba DNS"
    else
        result WARN "Local resolver file" "regular but not using 127.0.0.1" "nameserver 127.0.0.1"
        fail=1
    fi

    if [[ -n "${DOMAIN:-}" ]]; then
        if grep -Eiq "^[[:space:]]*(search|domain)[[:space:]].*${DOMAIN//./\\.}" /etc/resolv.conf; then
            result PASS "Resolver search domain" "$DOMAIN" "$DOMAIN"
        else
            result WARN "Resolver search domain" "missing/other" "$DOMAIN"
            fail=1
        fi
    fi

    return "$fail"
}

repair_local_resolver_only() {
    step "Repair local AD resolver"

    [[ -n "${DOMAIN:-}" && -n "${DC_FQDN:-}" && -n "${DC_IP:-}" ]] || {
        discover_network_topology
        discover_existing_identity
    }

    command_exists dig || {
        fail_msg "dig is required to validate Samba DNS."
        return 1
    }

    systemctl is-active --quiet samba-ad-dc || {
        fail_msg "samba-ad-dc is not active; resolver was not changed."
        return 1
    }

    dig +time=3 +tries=1 @127.0.0.1 "$DC_FQDN" A +short 2>/dev/null | grep -Fxq "$DC_IP" || {
        fail_msg "Samba DNS does not resolve $DC_FQDN to $DC_IP."
        return 1
    }

    local srv
    srv="$(dig +time=3 +tries=1 @127.0.0.1 +short SRV "_ldap._tcp.dc._msdcs.${DOMAIN}" 2>/dev/null || true)"
    if ! grep -Fiq "$DC_FQDN" <<<"$srv" && command_exists samba_dnsupdate; then
        msg_info "Refreshing Samba DNS registrations..."
        samba_dnsupdate --verbose >>"$LOG_FILE" 2>&1 || true
        srv="$(dig +time=3 +tries=1 @127.0.0.1 +short SRV "_ldap._tcp.dc._msdcs.${DOMAIN}" 2>/dev/null || true)"
    fi
    grep -Fiq "$DC_FQDN" <<<"$srv" || {
        fail_msg "AD DC locator SRV record is missing; resolver was not changed."
        return 1
    }

    capture_resolver_state
    DNS_TRANSACTION_ACTIVE=1

    systemctl disable --now systemd-resolved >/dev/null 2>&1 || true

    if ! write_ad_resolv_conf; then
        rollback_dns_transaction "failed to write persistent Samba resolver"
        return 1
    fi

    if ! getent ahostsv4 "$DC_FQDN" | awk '{print $1}' | grep -Fxq "$DC_IP"; then
        rollback_dns_transaction "system resolver cannot resolve the DC through Samba DNS"
        return 1
    fi

    if ! validate_system_dc_locator; then
        rollback_dns_transaction "system resolver cannot discover the AD DC SRV record"
        return 1
    fi

    if ! getent ahostsv4 raw.githubusercontent.com >/dev/null 2>&1; then
        rollback_dns_transaction "Samba DNS forwarding is unavailable through the system resolver"
        return 1
    fi

    DNS_TRANSACTION_ACTIVE=0
    change APPLIED "/etc/resolv.conf converted to persistent Samba AD resolver"
    result PASS "Local AD resolver" "regular /etc/resolv.conf -> 127.0.0.1" "persistent across reboot"
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
    if [[ -e "$RESOLV_SNAPSHOT" || -L "$RESOLV_SNAPSHOT" ]]; then
        cp -a --no-dereference "$RESOLV_SNAPSHOT" /etc/resolv.conf
    fi
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
    [[ -n "$DOMAIN" && -n "$DC_FQDN" && -n "$DC_IP" ]] || return 1

    [[ -f /etc/resolv.conf && ! -L /etc/resolv.conf ]] || return 1
    grep -Eq '^[[:space:]]*nameserver[[:space:]]+127\.0\.0\.1([[:space:]]|$)' /etc/resolv.conf || return 1
    grep -Eiq "^[[:space:]]*(search|domain)[[:space:]].*${DOMAIN//./\\.}" /etc/resolv.conf || return 1

    dig +time=3 +tries=1 @127.0.0.1 "$DC_FQDN" A +short 2>/dev/null | grep -Fxq "$DC_IP" || return 1

    local srv
    srv="$(dig +time=3 +tries=1 @127.0.0.1 +short SRV "_ldap._tcp.dc._msdcs.${DOMAIN}" 2>/dev/null || true)"
    grep -Fiq "$DC_FQDN" <<<"$srv" || return 1

    getent ahostsv4 "$DC_FQDN" | awk '{print $1}' | grep -Fxq "$DC_IP" || return 1
    validate_system_dc_locator || return 1
}

prepare_dns_transaction() {
    step "Prepare DNS transition"
    DNS_NEEDS_COMMIT=1

    if samba_dns_stack_healthy; then
        DNS_FORWARDER="${DNS_FORWARDER:-$(detect_dns_forwarder)}"
        DNS_NEEDS_COMMIT=0
        result SKIP "DNS transition" "Samba DNS + persistent host resolver already healthy" "retained"
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
    write_regular_resolv_conf "$DNS_FORWARDER" "" || return 1

    getent ahostsv4 raw.githubusercontent.com >/dev/null 2>&1 ||
        die "External DNS failed during temporary resolver transition."

    result PASS "Temporary resolver" "regular /etc/resolv.conf -> $DNS_FORWARDER" \
        "external DNS preserved without resolved stub"
}

wait_for_samba() {
    local timeout="${1:-60}" i

    for ((i=0; i<timeout; i++)); do
        if samba_required_listeners_ready; then
            return 0
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

    local srv
    srv="$(dig +time=3 +tries=1 @127.0.0.1 +short SRV "_ldap._tcp.dc._msdcs.${DOMAIN}" 2>/dev/null || true)"
    if ! grep -Fiq "$DC_FQDN" <<<"$srv"; then
        command_exists samba_dnsupdate && samba_dnsupdate --verbose >>"$LOG_FILE" 2>&1 || true
        srv="$(dig +time=3 +tries=1 @127.0.0.1 +short SRV "_ldap._tcp.dc._msdcs.${DOMAIN}" 2>/dev/null || true)"
    fi
    grep -Fiq "$DC_FQDN" <<<"$srv" ||
        die "Samba DNS is missing the AD DC locator SRV record for $DOMAIN."

    dig +time=4 +tries=1 @127.0.0.1 raw.githubusercontent.com A +short | grep -Eq '^[0-9]' ||
        die "Samba DNS forwarding is not working."

    systemctl disable --now systemd-resolved >/dev/null 2>&1 || true
    write_ad_resolv_conf || return 1

    getent ahostsv4 "$DC_FQDN" | awk '{print $1}' | grep -Fxq "$DC_IP" ||
        die "System resolver cannot resolve $DC_FQDN through /etc/resolv.conf."

    validate_system_dc_locator ||
        die "System resolver cannot discover _ldap._tcp.dc._msdcs.${DOMAIN}."

    getent ahostsv4 raw.githubusercontent.com >/dev/null 2>&1 ||
        die "System resolver cannot use Samba DNS forwarding."

    [[ -f /var/lib/samba/private/krb5.conf ]] || die "Missing Samba-generated krb5.conf."
    backup_file /etc/krb5.conf
    install -o root -g root -m 0644 /var/lib/samba/private/krb5.conf /etc/krb5.conf

    DNS_TRANSACTION_ACTIVE=0
    change APPLIED "Persistent /etc/resolv.conf -> Samba DNS (127.0.0.1)"
    result PASS "Samba DNS" "$DC_FQDN -> $DC_IP" "authoritative + forwarding"
    result PASS "Host resolver" "regular /etc/resolv.conf -> 127.0.0.1" "persistent after reboot"
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

    local fragment snapshot existed=0
    local default_cidr="" requested_cidr=""
    local config="" unit=""

    ensure_chrony_runtime || {
        fail_msg "Chrony runtime is unavailable; time configuration was not changed."
        return 1
    }

    config="$(chrony_main_config)" || {
        fail_msg "Unable to locate Chrony main configuration (/etc/chrony/chrony.conf or /etc/chrony.conf)."
        return 1
    }
    unit="$(chrony_service_unit)" || {
        fail_msg "Unable to identify Chrony systemd service."
        return 1
    }

    TIMEZONE="$(ask 'Timezone' "${TIMEZONE:-Europe/London}")"
    if command_exists timedatectl &&
       ! timedatectl list-timezones 2>/dev/null | grep -Fxq "$TIMEZONE"; then
        msg_warn "Unknown timezone: $TIMEZONE"
        return 1
    fi

    NTP_POOL="$(ask 'NTP pool/server' "${NTP_POOL:-pool.ntp.org}")"
    validate_ntp_source_token "$NTP_POOL" || {
        msg_warn "Invalid NTP source '$NTP_POOL'. Enter one hostname/IP only, e.g. pool.ntp.org or 192.0.2.10."
        return 1
    }

    default_cidr="$(resolve_ad_ntp_client_cidr 2>/dev/null || true)"
    if [[ -z "$default_cidr" ]]; then
        msg_warn "AD/NTP client CIDR could not be derived from the current AD interface."
        requested_cidr="$(ask 'AD/NTP client network (CIDR)' '192.168.1.0/24')"
    else
        requested_cidr="$(ask 'AD/NTP client network (CIDR)' "$default_cidr")"
    fi

    is_valid_ipv4 "$requested_cidr" && requested_cidr="${requested_cidr}/32"
    if ! is_valid_cidr "$requested_cidr"; then
        msg_warn "Invalid AD/NTP client CIDR: '$requested_cidr'."
        return 1
    fi
    AD_CLIENT_CIDR="$requested_cidr"

    timedatectl set-timezone "$TIMEZONE"

    ensure_chrony_conf_d_included || return 1

    fragment="$(chrony_managed_fragment)"
    mkdir -p "$(dirname "$fragment")"

    snapshot="${RUN_ROOT}/$(basename "$fragment").before"
    if [[ -e "$fragment" ]]; then
        cp -a "$fragment" "$snapshot"
        existed=1
    fi
    backup_file "$fragment"

    cat >"$fragment" <<EOF
# Managed by ${SCRIPT_NAME} ${SCRIPT_VERSION}
# Upstream synchronization source.
pool ${NTP_POOL} iburst maxsources 4

# Serve NTP only to the trusted Active Directory client network.
allow ${AD_CLIENT_CIDR}
EOF
    chmod 0644 "$fragment"

    printf '\n'
    printf '  %-24s %s\n' "Chrony config" "$config"
    printf '  %-24s %s\n' "systemd service" "$unit"
    printf '  %-24s %s\n' "managed fragment" "$fragment"
    printf '  %-24s %s\n' "NTP source" "$NTP_POOL"
    printf '  %-24s %s\n' "AD/NTP clients" "$AD_CLIENT_CIDR"

    if ! chrony_validate_config "time-configuration"; then
        chrony_restore_file_snapshot "$fragment" "$snapshot" "$existed"
        msg_warn "The previous Chrony fragment has been restored."

        if chrony_validate_config "time-rollback" yes; then
            result PASS "Chrony rollback" "previous configuration restored and valid" "valid"
        else
            result WARN "Chrony rollback" "previous configuration restored but parser still reports an error" \
                "inspect existing Chrony configuration"
        fi
        return 1
    fi

    if ! chrony_service_restart_safe; then
        chrony_restore_file_snapshot "$fragment" "$snapshot" "$existed"
        chrony_service_restart_safe >/dev/null 2>&1 || true
        msg_warn "Chrony changes were rolled back after restart failure."
        return 1
    fi

    result PASS "Chrony syntax" "$config" "valid"
    result PASS "Chrony service" "$unit active" "active"

    printf '\nWaiting up to 60 seconds for Chrony to select and synchronize a source...\n'
    chrony_report_sync_state "post-config" 12 5 || true

    change APPLIED "Configured Chrony source=$NTP_POOL clients=$AD_CLIENT_CIDR service=$unit"
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
    local -a target_args=()
    [[ -n "${DC_FQDN:-}" ]] && target_args=(-H "ldap://${DC_FQDN}")

    if samba-tool --help 2>&1 | grep -Fq -- '--use-krb5-ccache'; then
        KRB5CCNAME="$KRB5CCNAME" samba-tool --use-krb5-ccache="$KRB5CCNAME" \
            gpo "$@" "${target_args[@]}"
    else
        KRB5CCNAME="$KRB5CCNAME" samba-tool --use-kerberos=required \
            gpo "$@" "${target_args[@]}"
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
    audit_local_resolver_state || fail=1

    if ! ensure_samba_runtime_health; then
        fail=1
    fi

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
        && result PASS "Host resolver external" "external resolution works" "working" \
        || { result FAIL "Host resolver external" "failed" "working"; fail=1; }

    if validate_system_dc_locator; then
        result PASS "System DC locator" "_ldap._tcp.dc._msdcs.${DOMAIN}" "$DC_FQDN"
    else
        result FAIL "System DC locator" "SRV discovery failed via /etc/resolv.conf" "$DC_FQDN"
        fail=1
    fi

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

    if [[ "$SAMBA_ROLE" == ad-dc || "$SAMBA_ROLE" == ad-dc-config ]]; then
        audit_samba_transport_security
        audit_kerberos_client_config
        audit_signed_domain_time
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
    local -a rows=()
    mapfile -t rows < <(domain_computer_inventory_tsv)

    printf '\n%-6s %-24s %-36s %-16s %s\n' "#" "COMPUTER" "DNS NAME" "IP" "NETWORK HINT"
    printf '%s\n' "-----------------------------------------------------------------------------------------------------"

    local i account dns ip hint
    for i in "${!rows[@]}"; do
        IFS=$'\t' read -r account dns ip hint <<<"${rows[$i]}"
        printf '[%3d]  %-24s %-36s %-16s %s\n' \
            "$((i+1))" "$account" "$dns" "$ip" "$hint"
    done
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


select_enum_value() {
    local prompt="$1" default_index="$2"
    shift 2
    local -a entries=("$@")
    local i value label choice

    printf '\n' >&2
    ui_rule >&2
    printf '%b%b  %s%b\n' "$C_BOLD" "$C_WHITE" "$prompt" "$C_RESET" >&2
    ui_rule >&2
    for i in "${!entries[@]}"; do
        value="${entries[$i]%%|*}"
        label="${entries[$i]#*|}"
        printf '  %b[%2d]%b  %-18s %s\n' "$C_DIM" "$((i+1))" "$C_RESET" "$value" "$label" >&2
    done
    printf '  %b[0 ]%b  Cancel\n' "$C_RED" "$C_RESET" >&2
    ui_rule >&2

    choice="$(ask 'Select value' "$default_index")"
    [[ "$choice" =~ ^[0-9]+$ ]] || { msg_warn "Invalid selection."; return 1; }
    (( choice >= 1 && choice <= ${#entries[@]} )) || return 1
    printf '%s' "${entries[$((choice-1))]%%|*}"
}

list_domain_users_indexed() {
    local filter="${1:-}"
    local -a users=()
    mapfile -t users < <(
        samba-tool user list 2>/dev/null |
        sort |
        { if [[ -n "$filter" ]]; then grep -iF -- "$filter" || true; else cat; fi; }
    )

    local i
    printf '\n' >&2
    ui_rule >&2
    printf '%b%b  DOMAIN USERS%b\n' "$C_BOLD" "$C_WHITE" "$C_RESET" >&2
    ui_rule >&2
    if ((${#users[@]} == 0)); then
        printf '  %bNo users matched.%b\n' "$C_YELLOW" "$C_RESET" >&2
    else
        for i in "${!users[@]}"; do
            printf '  %b[%3d]%b  %s\n' "$C_DIM" "$((i+1))" "$C_RESET" "${users[$i]}" >&2
        done
    fi
    printf '  %b[S  ]%b  Search/filter\n' "$C_CYAN" "$C_RESET" >&2
    printf '  %b[M  ]%b  Enter user manually\n' "$C_CYAN" "$C_RESET" >&2
    printf '  %b[0  ]%b  Cancel\n' "$C_RED" "$C_RESET" >&2
    ui_rule >&2
}

select_domain_user() {
    local filter="" choice manual
    local -a users=()

    while true; do
        mapfile -t users < <(
            samba-tool user list 2>/dev/null |
            sort |
            { if [[ -n "$filter" ]]; then grep -iF -- "$filter" || true; else cat; fi; }
        )
        list_domain_users_indexed "$filter"

        choice="$(ask 'Select user' '0')"
        case "${choice^^}" in
            0|"") return 1 ;;
            S)
                filter="$(ask 'User filter' "$filter")"
                ;;
            M)
                manual="$(ask 'User identity / sAMAccountName')"
                [[ -n "$manual" ]] || return 1
                samba-tool user show "$manual" >/dev/null 2>&1 || {
                    msg_warn "User '$manual' does not exist."
                    continue
                }
                printf '%s' "$manual"
                return 0
                ;;
            *)
                [[ "$choice" =~ ^[0-9]+$ ]] || { msg_warn "Invalid user selection."; continue; }
                if (( choice >= 1 && choice <= ${#users[@]} )); then
                    printf '%s' "${users[$((choice-1))]}"
                    return 0
                fi
                msg_warn "User selection out of range."
                ;;
        esac
    done
}

domain_computer_inventory_tsv() {
    local account short dns ip hint
    while IFS= read -r account; do
        [[ -n "$account" ]] || continue
        short="${account%\$}"
        dns="$(
            samba-tool computer show "$account" --attributes=dNSHostName 2>/dev/null |
            awk -F': ' '/dNSHostName:/{print $2;exit}' |
            tr -d '\r' || true
        )"
        [[ -n "$dns" ]] || dns="${short,,}.${DOMAIN}"
        ip="$(getent ahostsv4 "$dns" 2>/dev/null | awk 'NR==1{print $1}' || true)"
        hint="NO_DNS"
        if [[ -n "$ip" ]]; then
            hint="NO_445"
            if command_exists timeout && timeout 1 bash -c "</dev/tcp/${ip}/445" >/dev/null 2>&1; then
                hint="SMB_OK"
            fi
        fi
        printf '%s\t%s\t%s\t%s\n' "$account" "$dns" "${ip:--}" "$hint"
    done < <(samba-tool computer list 2>/dev/null | sort)
}

list_domain_computers_indexed() {
    local filter="${1:-}"
    local -a rows=()
    mapfile -t rows < <(
        domain_computer_inventory_tsv |
        { if [[ -n "$filter" ]]; then grep -iF -- "$filter" || true; else cat; fi; }
    )

    local i account dns ip hint
    printf '\n' >&2
    ui_rule >&2
    printf '%b%b  DOMAIN COMPUTERS%b\n' "$C_BOLD" "$C_WHITE" "$C_RESET" >&2
    ui_rule >&2
    printf '  %-6s %-24s %-34s %-16s %s\n' "#" "ACCOUNT" "DNS NAME" "IP" "NETWORK" >&2
    for i in "${!rows[@]}"; do
        IFS=$'\t' read -r account dns ip hint <<<"${rows[$i]}"
        printf '  [%3d]  %-24s %-34s %-16s %s\n' "$((i+1))" "$account" "$dns" "$ip" "$hint" >&2
    done
    ((${#rows[@]})) || printf '  %bNo computers matched.%b\n' "$C_YELLOW" "$C_RESET" >&2
    printf '  %b[S  ]%b  Search/filter\n' "$C_CYAN" "$C_RESET" >&2
    printf '  %b[M  ]%b  Enter computer manually\n' "$C_CYAN" "$C_RESET" >&2
    printf '  %b[0  ]%b  Cancel\n' "$C_RED" "$C_RESET" >&2
    ui_rule >&2
}

select_domain_computer() {
    local filter="" choice manual
    local -a rows=()
    while true; do
        mapfile -t rows < <(
            domain_computer_inventory_tsv |
            { if [[ -n "$filter" ]]; then grep -iF -- "$filter" || true; else cat; fi; }
        )
        list_domain_computers_indexed "$filter"

        choice="$(ask 'Select computer' '0')"
        case "${choice^^}" in
            0|"") return 1 ;;
            S)
                filter="$(ask 'Computer filter' "$filter")"
                ;;
            M)
                manual="$(ask 'Computer account / name')"
                [[ -n "$manual" ]] || return 1
                samba-tool computer show "$manual" >/dev/null 2>&1 || {
                    samba-tool computer show "${manual}\$" >/dev/null 2>&1 || {
                        msg_warn "Computer '$manual' does not exist."
                        continue
                    }
                    manual="${manual}\$"
                }
                printf '%s' "$manual"
                return 0
                ;;
            *)
                [[ "$choice" =~ ^[0-9]+$ ]] || { msg_warn "Invalid computer selection."; continue; }
                if (( choice >= 1 && choice <= ${#rows[@]} )); then
                    printf '%s' "${rows[$((choice-1))]%%$'\t'*}"
                    return 0
                fi
                msg_warn "Computer selection out of range."
                ;;
        esac
    done
}

select_domain_principal() {
    local choice
    printf '\n' >&2
    ui_rule >&2
    printf '%b%b  SELECT DOMAIN PRINCIPAL%b\n' "$C_BOLD" "$C_WHITE" "$C_RESET" >&2
    ui_rule >&2
    printf '  %b[U]%b  User\n' "$C_CYAN" "$C_RESET" >&2
    printf '  %b[G]%b  Group\n' "$C_CYAN" "$C_RESET" >&2
    printf '  %b[C]%b  Computer\n' "$C_CYAN" "$C_RESET" >&2
    printf '  %b[M]%b  Enter identity manually\n' "$C_DIM" "$C_RESET" >&2
    printf '  %b[0]%b  Cancel\n' "$C_RED" "$C_RESET" >&2
    ui_rule >&2

    choice="$(ask 'Principal type' 'U')"
    case "${choice^^}" in
        U) select_domain_user ;;
        G) select_domain_group ;;
        C) select_domain_computer ;;
        M)
            local manual
            manual="$(ask 'User/group/computer identity')"
            [[ -n "$manual" ]] || return 1
            printf '%s' "$manual"
            ;;
        *) return 1 ;;
    esac
}

select_user_or_computer_account() {
    local choice
    printf '\n' >&2
    ui_rule >&2
    printf '%b%b  SELECT ACCOUNT%b\n' "$C_BOLD" "$C_WHITE" "$C_RESET" >&2
    ui_rule >&2
    printf '  %b[U]%b  Domain user\n' "$C_CYAN" "$C_RESET" >&2
    printf '  %b[C]%b  Domain computer\n' "$C_CYAN" "$C_RESET" >&2
    printf '  %b[M]%b  Enter account manually\n' "$C_DIM" "$C_RESET" >&2
    printf '  %b[0]%b  Cancel\n' "$C_RED" "$C_RESET" >&2
    ui_rule >&2

    choice="$(ask 'Account type' 'U')"
    case "${choice^^}" in
        U) select_domain_user ;;
        C) select_domain_computer ;;
        M)
            local manual
            manual="$(ask 'Domain user/computer account')"
            [[ -n "$manual" ]] || return 1
            printf '%s' "$manual"
            ;;
        *) return 1 ;;
    esac
}

select_group_member() {
    local group="$1" choice manual
    local -a members=()
    mapfile -t members < <(samba-tool group listmembers "$group" 2>/dev/null | sort)

    printf '\n' >&2
    ui_rule >&2
    printf '%b%b  CURRENT MEMBERS: %s%b\n' "$C_BOLD" "$C_WHITE" "$group" "$C_RESET" >&2
    ui_rule >&2

    local i
    for i in "${!members[@]}"; do
        printf '  %b[%3d]%b  %s\n' "$C_DIM" "$((i+1))" "$C_RESET" "${members[$i]}" >&2
    done
    ((${#members[@]})) || printf '  %bNo direct members returned.%b\n' "$C_YELLOW" "$C_RESET" >&2
    printf '  %b[M  ]%b  Enter member manually\n' "$C_DIM" "$C_RESET" >&2
    printf '  %b[0  ]%b  Cancel\n' "$C_RED" "$C_RESET" >&2
    ui_rule >&2

    choice="$(ask 'Select member' '0')"
    case "${choice^^}" in
        0|"") return 1 ;;
        M)
            manual="$(ask 'Existing member identity')"
            [[ -n "$manual" ]] || return 1
            printf '%s' "$manual"
            ;;
        *)
            [[ "$choice" =~ ^[0-9]+$ ]] || return 1
            (( choice >= 1 && choice <= ${#members[@]} )) || return 1
            printf '%s' "${members[$((choice-1))]}"
            ;;
    esac
}

directory_object_dn_from_samba() {
    local area="$1" identity="$2"
    samba-tool "$area" show "$identity" 2>/dev/null |
        awk -F': ' '/^dn: /{print $2;exit}'
}

select_directory_object_dn() {
    local choice identity dn
    printf '\n' >&2
    ui_rule >&2
    printf '%b%b  SELECT DIRECTORY OBJECT%b\n' "$C_BOLD" "$C_WHITE" "$C_RESET" >&2
    ui_rule >&2
    printf '  %b[U]%b  User\n' "$C_CYAN" "$C_RESET" >&2
    printf '  %b[G]%b  Group\n' "$C_CYAN" "$C_RESET" >&2
    printf '  %b[C]%b  Computer\n' "$C_CYAN" "$C_RESET" >&2
    printf '  %b[O]%b  Domain root / Organizational Unit\n' "$C_CYAN" "$C_RESET" >&2
    printf '  %b[M]%b  Enter distinguished name manually\n' "$C_DIM" "$C_RESET" >&2
    printf '  %b[0]%b  Cancel\n' "$C_RED" "$C_RESET" >&2
    ui_rule >&2

    choice="$(ask 'Object type' 'O')"
    case "${choice^^}" in
        U)
            identity="$(select_domain_user)" || return 1
            dn="$(directory_object_dn_from_samba user "$identity")"
            ;;
        G)
            identity="$(select_domain_group)" || return 1
            dn="$(directory_object_dn_from_samba group "$identity")"
            ;;
        C)
            identity="$(select_domain_computer)" || return 1
            dn="$(directory_object_dn_from_samba computer "$identity")"
            ;;
        O) select_directory_target_dn; return ;;
        M)
            dn="$(ask 'Object DN')"
            ;;
        *) return 1 ;;
    esac

    [[ -n "$dn" ]] || {
        msg_warn "Unable to resolve distinguished name for '$identity'."
        return 1
    }
    printf '%s' "$dn"
}

trusted_domain_list() {
    local base
    base="$(domain_dn "$DOMAIN")"
    ldbsearch -H /var/lib/samba/private/sam.ldb -b "CN=System,${base}" \
        '(objectClass=trustedDomain)' trustPartner 2>/dev/null |
        awk -F': ' '/^trustPartner: /{print $2}' |
        sort -fu
}

select_trusted_domain() {
    local -a trusts=()
    mapfile -t trusts < <(trusted_domain_list)
    local i choice manual

    printf '\n' >&2
    ui_rule >&2
    printf '%b%b  DOMAIN TRUSTS%b\n' "$C_BOLD" "$C_WHITE" "$C_RESET" >&2
    ui_rule >&2
    for i in "${!trusts[@]}"; do
        printf '  %b[%2d]%b  %s\n' "$C_DIM" "$((i+1))" "$C_RESET" "${trusts[$i]}" >&2
    done
    ((${#trusts[@]})) || printf '  %bNo trust objects found.%b\n' "$C_YELLOW" "$C_RESET" >&2
    printf '  %b[M ]%b  Enter trusted domain manually\n' "$C_DIM" "$C_RESET" >&2
    printf '  %b[0 ]%b  Cancel\n' "$C_RED" "$C_RESET" >&2
    ui_rule >&2

    choice="$(ask 'Select trust' '0')"
    case "${choice^^}" in
        0|"") return 1 ;;
        M)
            manual="$(ask 'Trusted domain DNS name')"
            [[ -n "$manual" ]] || return 1
            printf '%s' "$manual"
            ;;
        *)
            [[ "$choice" =~ ^[0-9]+$ ]] || return 1
            (( choice >= 1 && choice <= ${#trusts[@]} )) || return 1
            printf '%s' "${trusts[$((choice-1))]}"
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


user_has_effective_group_membership() {
    local user="$1" group="$2"
    samba-tool user getgroups "$user" 2>/dev/null |
        awk -v target="$group" '
            BEGIN { IGNORECASE=1 }
            $0 == target { found=1; exit }
            END { exit(found ? 0 : 1) }
        '
}

add_user_to_group_safe() {
    local user="$1" group="$2" output=""

    if user_has_effective_group_membership "$user" "$group"; then
        if [[ "${group,,}" == "domain users" ]]; then
            result SKIP "Group membership" \
                "$user -> $group (already effective; normally the user's primary group)" \
                "no change required"
        else
            result SKIP "Group membership" \
                "$user -> $group already effective" \
                "no duplicate membership"
        fi
        return 0
    fi

    if output="$(samba-tool group addmembers "$group" "$user" 2>&1)"; then
        change APPLIED "Added $user to group=$group"
        result PASS "Group membership" "$user -> $group" "added"
        return 0
    fi

    # Re-check after the command. This covers races and Samba versions that
    # return a non-zero status for an already-effective membership.
    if user_has_effective_group_membership "$user" "$group"; then
        result SKIP "Group membership" \
            "$user -> $group is already effective" \
            "no duplicate membership"
        return 0
    fi

    msg_warn "Unable to add '$user' to group '$group'."
    [[ -n "$output" ]] && printf '%s\n' "$output" >&2
    return 1
}

manage_user_memberships() {
    local user="$1" choice group
    while true; do
        (( MENU_MAIN_REQUESTED )) && return 0
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
                    if ! add_user_to_group_safe "$user" "$group"; then
                        msg_warn "Membership change was not applied; remaining operations can continue."
                    fi
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
            H|h) MENU_MAIN_REQUESTED=1; break ;;
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
        printf '
%bNote:%b new AD users already use "Domain Users" as their primary group; it does not need to be added again.
'             "$C_CYAN" "$C_RESET"
        while true; do
            group=""
            if group="$(select_domain_group)"; then
                if ! add_user_to_group_safe "$user" "$group"; then
                    msg_warn "Could not add the selected group; the user was created successfully and the wizard will continue."
                fi
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
        (( MENU_MAIN_REQUESTED )) && return 0
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
                    sensitive_choice="$(select_enum_value "ACCOUNT DELEGATION SENSITIVITY" 1                         "on|Mark account sensitive / not delegatable"                         "off|Allow delegation according to other policy")" || continue
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
            H|h) MENU_MAIN_REQUESTED=1; break ;;
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
    local i guid name flags
    printf '\n'
    ui_rule
    printf '%b%b  GROUP POLICY OBJECTS%b\n' "$C_BOLD" "$C_WHITE" "$C_RESET"
    ui_rule
    if ((${#entries[@]} == 0)); then
        printf '  %bNo GPOs returned.%b\n' "$C_YELLOW" "$C_RESET"
    else
        printf '  %-5s %-39s %-39s %s\n' "#" "NAME" "GUID" "STATUS"
        for i in "${!entries[@]}"; do
            guid="${entries[$i]%%$'\t'*}"
            name="${entries[$i]#*$'\t'}"
            flags="$(get_gpo_flags "$guid")"
            printf '  [%2d]  %-39s %-39s %s\n' \
                "$((i+1))" "$name" "$guid" "$(gpo_flags_label "$flags")"
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
    mkdir -p "$GPO_WINDOWS_DIR" "$GPO_CUSTOM_DIR"
    chmod 700 "$GPO_DIR" "$GPO_BUILTIN_DIR" "$GPO_WINDOWS_DIR" "$GPO_CUSTOM_DIR"

    cat >"${GPO_WINDOWS_DIR}/sec-powershell-logging.json" <<'EOF'
[
  {
    "keyname": "SOFTWARE\\Policies\\Microsoft\\Windows\\PowerShell\\ScriptBlockLogging",
    "valuename": "EnableScriptBlockLogging",
    "class": "MACHINE",
    "type": "REG_DWORD",
    "data": 1
  },
  {
    "keyname": "SOFTWARE\\Policies\\Microsoft\\Windows\\PowerShell\\ModuleLogging",
    "valuename": "EnableModuleLogging",
    "class": "MACHINE",
    "type": "REG_DWORD",
    "data": 1
  },
  {
    "keyname": "SOFTWARE\\Policies\\Microsoft\\Windows\\PowerShell\\ModuleLogging\\ModuleNames",
    "valuename": "*",
    "class": "MACHINE",
    "type": "REG_SZ",
    "data": "*"
  }
]
EOF

    cat >"${GPO_WINDOWS_DIR}/sec-disable-llmnr.json" <<'EOF'
[
  {
    "keyname": "SOFTWARE\\Policies\\Microsoft\\Windows NT\\DNSClient",
    "valuename": "EnableMulticast",
    "class": "MACHINE",
    "type": "REG_DWORD",
    "data": 0
  }
]
EOF

    cat >"${GPO_WINDOWS_DIR}/sec-smb-guest.json" <<'EOF'
[
  {
    "keyname": "SOFTWARE\\Policies\\Microsoft\\Windows\\LanmanWorkstation",
    "valuename": "AllowInsecureGuestAuth",
    "class": "MACHINE",
    "type": "REG_DWORD",
    "data": 0
  }
]
EOF

    cat >"${GPO_WINDOWS_DIR}/sec-rdp-nla.json" <<'EOF'
[
  {
    "keyname": "SOFTWARE\\Policies\\Microsoft\\Windows NT\\Terminal Services",
    "valuename": "UserAuthentication",
    "class": "MACHINE",
    "type": "REG_DWORD",
    "data": 1
  }
]
EOF

    cat >"${GPO_WINDOWS_DIR}/sec-screen-lock.json" <<'EOF'
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

    cat >"${GPO_WINDOWS_DIR}/sec-disable-alwaysinstallelevated.json" <<'EOF'
[
  {
    "keyname": "SOFTWARE\\Policies\\Microsoft\\Windows\\Installer",
    "valuename": "AlwaysInstallElevated",
    "class": "MACHINE",
    "type": "REG_DWORD",
    "data": 0
  },
  {
    "keyname": "Software\\Policies\\Microsoft\\Windows\\Installer",
    "valuename": "AlwaysInstallElevated",
    "class": "USER",
    "type": "REG_DWORD",
    "data": 0
  }
]
EOF

    cat >"${GPO_WINDOWS_DIR}/sec-legal-notice.json" <<EOF
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
  }
]
EOF

    # Combined starter file for administrators who prefer one GPO instead of
    # several narrowly-scoped GPOs. The catalog still deploys separate GPOs by
    # default because they are easier to troubleshoot and target independently.
    cat >"${GPO_WINDOWS_DIR}/sec-workstation-starter-combined.json" <<'EOF'
[
  {"keyname":"SOFTWARE\\Policies\\Microsoft\\Windows\\PowerShell\\ScriptBlockLogging","valuename":"EnableScriptBlockLogging","class":"MACHINE","type":"REG_DWORD","data":1},
  {"keyname":"SOFTWARE\\Policies\\Microsoft\\Windows\\PowerShell\\ModuleLogging","valuename":"EnableModuleLogging","class":"MACHINE","type":"REG_DWORD","data":1},
  {"keyname":"SOFTWARE\\Policies\\Microsoft\\Windows\\PowerShell\\ModuleLogging\\ModuleNames","valuename":"*","class":"MACHINE","type":"REG_SZ","data":"*"},
  {"keyname":"SOFTWARE\\Policies\\Microsoft\\Windows NT\\DNSClient","valuename":"EnableMulticast","class":"MACHINE","type":"REG_DWORD","data":0},
  {"keyname":"SOFTWARE\\Policies\\Microsoft\\Windows\\LanmanWorkstation","valuename":"AllowInsecureGuestAuth","class":"MACHINE","type":"REG_DWORD","data":0},
  {"keyname":"SOFTWARE\\Policies\\Microsoft\\Windows NT\\Terminal Services","valuename":"UserAuthentication","class":"MACHINE","type":"REG_DWORD","data":1},
  {"keyname":"Software\\Policies\\Microsoft\\Windows\\Control Panel\\Desktop","valuename":"ScreenSaveActive","class":"USER","type":"REG_SZ","data":"1"},
  {"keyname":"Software\\Policies\\Microsoft\\Windows\\Control Panel\\Desktop","valuename":"ScreenSaveTimeOut","class":"USER","type":"REG_SZ","data":"600"},
  {"keyname":"Software\\Policies\\Microsoft\\Windows\\Control Panel\\Desktop","valuename":"ScreenSaverIsSecure","class":"USER","type":"REG_SZ","data":"1"},
  {"keyname":"SOFTWARE\\Policies\\Microsoft\\Windows\\Installer","valuename":"AlwaysInstallElevated","class":"MACHINE","type":"REG_DWORD","data":0},
  {"keyname":"Software\\Policies\\Microsoft\\Windows\\Installer","valuename":"AlwaysInstallElevated","class":"USER","type":"REG_DWORD","data":0}
]
EOF

    chmod 600 "${GPO_WINDOWS_DIR}"/*.json

    local f
    for f in "${GPO_WINDOWS_DIR}"/*.json; do
        python3 -m json.tool "$f" >/dev/null || {
            fail_msg "Managed GPO JSON failed validation: $f"
            return 1
        }
    done
}

deploy_security_gpo_template() {
    local id="$1" target_dn="$2"
    local name file guid="" output=""

    case "$id" in
        1) name="SEC - PowerShell Logging"; file="${GPO_WINDOWS_DIR}/sec-powershell-logging.json" ;;
        2) name="SEC - Disable LLMNR"; file="${GPO_WINDOWS_DIR}/sec-disable-llmnr.json" ;;
        3) name="SEC - SMB Guest Hardening"; file="${GPO_WINDOWS_DIR}/sec-smb-guest.json" ;;
        4) name="SEC - RDP Network Level Authentication"; file="${GPO_WINDOWS_DIR}/sec-rdp-nla.json" ;;
        5) name="SEC - Secure Screen Lock"; file="${GPO_WINDOWS_DIR}/sec-screen-lock.json" ;;
        6) name="SEC - Disable AlwaysInstallElevated"; file="${GPO_WINDOWS_DIR}/sec-disable-alwaysinstallelevated.json" ;;
        7) name="SEC - Authorized Use Notice"; file="${GPO_WINDOWS_DIR}/sec-legal-notice.json" ;;
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



# ---------------------------------------------------------------------------
# Persistent GPO policy library
# ---------------------------------------------------------------------------

builtin_json_catalog_tsv() {
    cat <<EOF
1	SEC - PowerShell Logging	${GPO_WINDOWS_DIR}/sec-powershell-logging.json	MACHINE	PowerShell Script Block and Module Logging
2	SEC - Disable LLMNR	${GPO_WINDOWS_DIR}/sec-disable-llmnr.json	MACHINE	Disable LLMNR multicast name resolution
3	SEC - SMB Guest Hardening	${GPO_WINDOWS_DIR}/sec-smb-guest.json	MACHINE	Reject insecure SMB guest authentication
4	SEC - RDP Network Level Authentication	${GPO_WINDOWS_DIR}/sec-rdp-nla.json	MACHINE	Require RDP NLA
5	SEC - Secure Screen Lock	${GPO_WINDOWS_DIR}/sec-screen-lock.json	USER	Enable secure 10-minute screensaver lock
6	SEC - Disable AlwaysInstallElevated	${GPO_WINDOWS_DIR}/sec-disable-alwaysinstallelevated.json	BOTH	Disable elevated MSI policy for user and machine
7	SEC - Authorized Use Notice	${GPO_WINDOWS_DIR}/sec-legal-notice.json	MACHINE	Domain authorized-use logon notice
8	SEC - Workstation Starter Combined	${GPO_WINDOWS_DIR}/sec-workstation-starter-combined.json	BOTH	Combined JSON containing catalog items 1-6
EOF
}

write_gpo_manual() {
    mkdir -p "$GPO_DIR"

    cat >"$GPO_DOC_FILE" <<EOF
# DEBIAN AD Assistant - GPO Operations Guide

Generated by ${SCRIPT_NAME} ${SCRIPT_VERSION}

## 1. Persistent policy library

The assistant stores its GPO material under:

    ${GPO_DIR}/
    ├── builtin/windows/   Managed JSON shipped by the assistant
    ├── custom/            Administrator-owned editable JSON
    └── GPO-GUIDE.md       This guide

Built-in policies are regenerated by the assistant and should be treated as
read-only. Copy a built-in policy into custom/ before changing it.

Current Windows built-ins:

    sec-powershell-logging.json
    sec-disable-llmnr.json
    sec-smb-guest.json
    sec-rdp-nla.json
    sec-screen-lock.json
    sec-disable-alwaysinstallelevated.json
    sec-legal-notice.json
    sec-workstation-starter-combined.json

## 2. Samba JSON policy format

samba-tool gpo load consumes a JSON array. A Registry policy entry normally has:

    [
      {
        "keyname": "SOFTWARE\\\\Policies\\\\Vendor\\\\Product",
        "valuename": "SettingName",
        "class": "MACHINE",
        "type": "REG_DWORD",
        "data": 1
      }
    ]

class:
    MACHINE  -> Computer Configuration
    USER     -> User Configuration
    BOTH     -> both policy classes

Common examples used by this assistant:
    REG_DWORD
    REG_SZ
    REG_BINARY

For REG_BINARY, a JSON array is interpreted as bytes.

Validate a file before use:

    python3 -m json.tool my-policy.json

## 3. Merge versus replace

Merge policy data into an existing GPO:

    samba-tool gpo load {GUID} --content=/path/policy.json

Replace existing Registry policies in the selected GPO:

    samba-tool gpo load {GUID} --content=/path/policy.json --replace

The assistant always offers a backup before loading JSON.

## 4. Removing Registry policy values

samba-tool gpo remove accepts JSON entries containing keyname, valuename and class.
The assistant can derive this removal description from a full custom JSON file.

Conceptual removal input:

    [
      {
        "keyname": "SOFTWARE\\\\Policies\\\\Vendor\\\\Product",
        "valuename": "SettingName",
        "class": "MACHINE"
      }
    ]

## 5. Where the real GPO is stored

A GPO has two parts:

1. LDAP Group Policy Container:
       CN={GUID},CN=Policies,CN=System,<domain DN>

2. SYSVOL Group Policy Template:
       <SYSVOL>/${DOMAIN}/Policies/{GUID}/

Do not manually create or delete these directories. Use samba-tool so LDAP,
GPT.INI, Registry.pol and SYSVOL remain consistent.

The assistant's JSON library is only source material; loading the JSON writes
the actual policy into the selected GPO.

## 6. GPO status

The AD groupPolicyContainer "flags" attribute represents the GPO state:

    0 = Enabled
    1 = User Configuration disabled
    2 = Computer Configuration disabled
    3 = All settings disabled

This is different from GPO linking.

A GPO may be:
    enabled but not linked,
    linked but globally disabled,
    or enabled with only one policy class active.

Use:
    ad-gpo -> GPO status

## 7. Links and scope

A GPO is not normally applied until it is linked to a domain/OU (unless a
different inheritance path applies). The assistant keeps status and links as
separate operations.

Use:
    ad-gpo -> Link / update
    ad-gpo -> Remove link
    ad-gpo -> List containers

## 8. Windows policies

Windows Registry/CSE JSON lives under:

    ${GPO_WINDOWS_DIR}

The default Registry Client Side Extension used by Samba covers most Registry
policies. Policies requiring another CSE may need explicit machine/user
extension GUIDs; do not assume every Windows policy is only a Registry value.

## 9. Ubuntu ADSys

Ubuntu ADSys uses Ubuntu-specific administrative templates. Canonical
recommends keeping Ubuntu and Windows policy configuration separate.

Generate templates on an Ubuntu client whose ADSys version matches that client:

    mkdir -p ~/adsys-admx
    cd ~/adsys-admx
    adsysctl policy admx lts-only

or:

    adsysctl policy admx all

This generates:
    Ubuntu.admx
    Ubuntu.adml

The assistant detects the Samba SYSVOL path dynamically. The Central Store is:

    <SYSVOL>/${DOMAIN}/Policies/PolicyDefinitions/Ubuntu.admx
    <SYSVOL>/${DOMAIN}/Policies/PolicyDefinitions/en-US/Ubuntu.adml

Use:
    ad-gpo -> Platform GPO catalog -> Ubuntu ADSys clients

Important:
    Do not blindly reuse a Windows JSON policy as an Ubuntu ADSys policy.
    Ubuntu policy Registry paths and values must match the Ubuntu.admx generated
    for the ADSys version used by the client.

## 10. Samba Linux policies

Samba/winbind Linux policy types are normally managed with:

    samba-tool gpo manage ...

rather than generic Registry JSON.

Examples include smb_conf, access, OpenSSH, sudoers, scripts, MOTD, issue,
files and symlinks, depending on the Samba version installed.

Use:
    ad-gpo -> Platform GPO catalog -> Samba Linux clients

## 11. Recommended staging workflow

A safe production workflow is:

1. Create/load policy content.
2. Keep the GPO disabled and unlinked.
3. Review JSON / GPO contents.
4. Link to a test OU.
5. Enable the required machine/user portion.
6. Validate on a test client.
7. Expand scope only after validation.

The assistant can stage the recommended Windows starter GPOs in exactly this
disabled/unlinked state.

## 12. Useful commands

List GPOs:
    samba-tool gpo listall

Inspect:
    samba-tool gpo show {GUID}

Linked containers:
    samba-tool gpo listcontainers {GUID}

Load JSON:
    samba-tool gpo load {GUID} --content=/path/policy.json

Remove JSON-defined settings:
    samba-tool gpo remove {GUID} --content=/path/remove.json

Check LDAP/SYSVOL ACL consistency:
    samba-tool gpo aclcheck

SYSVOL ACL check:
    samba-tool ntacl sysvolcheck

Never run sysvolreset merely because a GPO operation failed. Diagnose DNS,
Kerberos, LDAP and GPO/SYSVOL ACL state first.
EOF

    chmod 600 "$GPO_DOC_FILE"
}

initialize_gpo_library() {
    mkdir -p "$GPO_WINDOWS_DIR" "$GPO_CUSTOM_DIR"
    chmod 700 "$GPO_DIR" "$GPO_BUILTIN_DIR" "$GPO_WINDOWS_DIR" "$GPO_CUSTOM_DIR"

    write_security_gpo_catalog_sources
    write_gpo_manual

    # A skeleton is created only once so administrators can keep editing it.
    if [[ ! -e "${GPO_CUSTOM_DIR}/example-custom-policy.json" ]]; then
        cat >"${GPO_CUSTOM_DIR}/example-custom-policy.json" <<'EOF'
[
  {
    "keyname": "SOFTWARE\\Policies\\Example\\Product",
    "valuename": "ExampleSetting",
    "class": "MACHINE",
    "type": "REG_DWORD",
    "data": 1
  }
]
EOF
        chmod 600 "${GPO_CUSTOM_DIR}/example-custom-policy.json"
    fi
}

show_gpo_library_paths() {
    initialize_gpo_library
    ui_menu_screen "GPO POLICY LIBRARY" "Persistent JSON sources and documentation paths"
    printf '  %-22s %s\n' "Library root" "$GPO_DIR"
    printf '  %-22s %s\n' "Windows built-ins" "$GPO_WINDOWS_DIR"
    printf '  %-22s %s\n' "Custom JSON" "$GPO_CUSTOM_DIR"
    printf '  %-22s %s\n' "Manual" "$GPO_DOC_FILE"
    printf '  %-22s %s\n' "SYSVOL" "$(get_sysvol_path 2>/dev/null || printf 'not detected')"
    printf '  %-22s %s\n' "PolicyDefinitions" "$(get_policy_definitions_path 2>/dev/null || printf 'not detected')"
    ui_rule
}

show_gpo_manual() {
    initialize_gpo_library
    if command_exists less && [[ -t 1 ]]; then
        LESS='-FRSX' less "$GPO_DOC_FILE"
    else
        cat "$GPO_DOC_FILE"
    fi
}

json_policy_files_tsv() {
    local scope="${1:-all}" f kind
    initialize_gpo_library

    if [[ "$scope" == "all" || "$scope" == "builtin" ]]; then
        while IFS= read -r f; do
            [[ -f "$f" ]] || continue
            printf 'builtin\t%s\t%s\n' "$(basename "$f")" "$f"
        done < <(find "$GPO_WINDOWS_DIR" -maxdepth 1 -type f -name '*.json' -print | sort)
    fi

    if [[ "$scope" == "all" || "$scope" == "custom" ]]; then
        while IFS= read -r f; do
            [[ -f "$f" ]] || continue
            printf 'custom\t%s\t%s\n' "$(basename "$f")" "$f"
        done < <(find "$GPO_CUSTOM_DIR" -maxdepth 1 -type f -name '*.json' -print | sort)
    fi
}

show_json_policy_inventory() {
    local scope="${1:-all}"
    local -a entries=()
    local i kind name path
    mapfile -t entries < <(json_policy_files_tsv "$scope")

    printf '\n'
    ui_rule
    printf '%b%b  JSON POLICY LIBRARY%b\n' "$C_BOLD" "$C_WHITE" "$C_RESET"
    ui_rule
    printf '  %-5s %-9s %-38s %s\n' "#" "TYPE" "FILE" "PATH"
    for i in "${!entries[@]}"; do
        IFS=$'\t' read -r kind name path <<<"${entries[$i]}"
        printf '  [%2d]  %-9s %-38s %s\n' "$((i+1))" "$kind" "$name" "$path"
    done
    ((${#entries[@]})) || printf '  %bNo JSON policies found.%b\n' "$C_YELLOW" "$C_RESET"
    ui_rule
}

select_json_policy_file() {
    local scope="${1:-all}"
    local -a entries=()
    local i kind name path choice
    mapfile -t entries < <(json_policy_files_tsv "$scope")

    printf '\n' >&2
    ui_rule >&2
    printf '%b%b  SELECT JSON POLICY%b\n' "$C_BOLD" "$C_WHITE" "$C_RESET" >&2
    ui_rule >&2

    for i in "${!entries[@]}"; do
        IFS=$'\t' read -r kind name path <<<"${entries[$i]}"
        printf '  %b[%2d]%b  %-9s %-38s\n' "$C_DIM" "$((i+1))" "$C_RESET" "$kind" "$name" >&2
    done
    printf '  %b[M ]%b  Enter path manually\n' "$C_CYAN" "$C_RESET" >&2
    printf '  %b[0 ]%b  Cancel\n' "$C_RED" "$C_RESET" >&2
    ui_rule >&2

    choice="$(ask 'Select JSON policy' '0')"
    case "${choice^^}" in
        0|"") return 1 ;;
        M)
            path="$(ask 'JSON policy path')"
            [[ -f "$path" ]] || { msg_warn "File not found: $path"; return 1; }
            printf '%s' "$path"
            ;;
        *)
            [[ "$choice" =~ ^[0-9]+$ ]] || { msg_warn "Invalid JSON selection."; return 1; }
            (( choice >= 1 && choice <= ${#entries[@]} )) || { msg_warn "JSON selection out of range."; return 1; }
            printf '%s' "${entries[$((choice-1))]##*$'\t'}"
            ;;
    esac
}

validate_gpo_json_file() {
    local file="$1"
    [[ -f "$file" ]] || { msg_warn "File not found: $file"; return 1; }

    if ! python3 -m json.tool "$file" >/dev/null 2>&1; then
        result FAIL "GPO JSON" "$file" "valid JSON"
        return 1
    fi

    if ! python3 -c '
import json,sys
p=sys.argv[1]
data=json.load(open(p,encoding="utf-8"))
if not isinstance(data,list) or not data:
    raise SystemExit(2)
for n,item in enumerate(data,1):
    if not isinstance(item,dict):
        raise SystemExit(3)
    for k in ("keyname","valuename","class"):
        if k not in item or not isinstance(item[k],str) or not item[k]:
            raise SystemExit(4)
    if item["class"] not in ("MACHINE","USER","BOTH"):
        raise SystemExit(5)
    if "type" in item and not isinstance(item["type"],str):
        raise SystemExit(6)
' "$file"; then
        result FAIL "GPO JSON schema" "$file" "array with keyname/valuename/class"
        return 1
    fi

    result PASS "GPO JSON" "$file" "valid"
}

copy_builtin_json_to_custom() {
    local src base dest stem n=1
    src="$(select_json_policy_file builtin)" || return 1
    base="$(basename "$src")"
    dest="${GPO_CUSTOM_DIR}/${base}"

    if [[ -e "$dest" ]]; then
        stem="${base%.json}"
        while [[ -e "${GPO_CUSTOM_DIR}/${stem}-${n}.json" ]]; do
            n=$((n+1))
        done
        dest="${GPO_CUSTOM_DIR}/${stem}-${n}.json"
    fi

    cp -a "$src" "$dest"
    chmod 600 "$dest"
    change APPLIED "Copied built-in GPO JSON to custom library: $dest"
    result PASS "Custom JSON copy" "$dest" "editable"
}

create_custom_json_skeleton() {
    local name file
    name="$(ask 'Custom JSON file name' 'custom-policy.json')"
    [[ "$name" == *.json ]] || name="${name}.json"
    name="$(basename "$name")"
    file="${GPO_CUSTOM_DIR}/${name}"

    [[ ! -e "$file" ]] || {
        msg_warn "Custom JSON already exists: $file"
        return 1
    }

    cat >"$file" <<'EOF'
[
  {
    "keyname": "SOFTWARE\\Policies\\Example\\Product",
    "valuename": "SettingName",
    "class": "MACHINE",
    "type": "REG_DWORD",
    "data": 1
  }
]
EOF
    chmod 600 "$file"
    result PASS "Custom JSON" "$file" "created"
}

edit_custom_json_file() {
    local file editor backup
    file="$(select_json_policy_file custom)" || return 1
    editor="${EDITOR:-}"
    if [[ -z "$editor" ]]; then
        if command_exists nano; then editor="nano"
        elif command_exists vim; then editor="vim"
        else editor="vi"
        fi
    fi

    backup="${RUN_ROOT}/$(basename "$file").before-edit"
    cp -a "$file" "$backup"

    "$editor" "$file"

    if validate_gpo_json_file "$file"; then
        change APPLIED "Edited custom GPO JSON: $file"
        return 0
    fi

    msg_warn "Edited JSON is invalid."
    if confirm "Restore the pre-edit copy?" Y; then
        cp -a "$backup" "$file"
        result PASS "Custom JSON rollback" "$file" "restored"
    fi
    return 1
}

select_or_create_gpo_guid() {
    local choice name guid
    printf '\n' >&2
    printf '  %b[E]%b Select existing GPO\n' "$C_CYAN" "$C_RESET" >&2
    printf '  %b[N]%b Create new GPO\n' "$C_GREEN" "$C_RESET" >&2
    printf '  %b[0]%b Cancel\n' "$C_RED" "$C_RESET" >&2

    choice="$(ask 'GPO target' 'E')"
    case "${choice^^}" in
        E) select_gpo_guid ;;
        N)
            name="$(ask 'New GPO display name')"
            [[ -n "$name" ]] || return 1
            create_gpo_safe "$name"
            ;;
        *) return 1 ;;
    esac
}

apply_json_policy_interactive() {
    local scope="${1:-all}"
    local file guid mode output=""
    file="$(select_json_policy_file "$scope")" || return 1
    validate_gpo_json_file "$file" || return 1
    guid="$(select_or_create_gpo_guid)" || return 1

    printf '\n  JSON : %s\n  GPO  : %s\n' "$file" "$guid"
    mode="$(select_enum_value "GPO JSON LOAD MODE" 1         "merge|Merge with existing Registry policy content"         "replace|Replace existing Registry policy content")" || return 1

    backup_gpo_safe "$guid" || true

    if [[ "$mode" == "replace" ]]; then
        confirm_high_risk "Replace Registry policy content in GPO $guid with $(basename "$file")" || return 1
        if ! capture_samba_gpo output load "$guid" --content="$file" --replace; then
            printf '%s\n' "$output" >&2
            msg_warn "GPO JSON replace failed."
            return 1
        fi
    else
        confirm "Merge $(basename "$file") into GPO $guid?" N || return 1
        if ! capture_samba_gpo output load "$guid" --content="$file"; then
            printf '%s\n' "$output" >&2
            msg_warn "GPO JSON merge failed."
            return 1
        fi
    fi

    change APPLIED "Loaded JSON $(basename "$file") into GPO=$guid mode=$mode"
    result PASS "GPO JSON load" "$(basename "$file") -> $guid" "$mode"
}

remove_json_policy_interactive() {
    local file guid remove_file output=""
    file="$(select_json_policy_file all)" || return 1
    validate_gpo_json_file "$file" || return 1
    guid="$(select_gpo_guid)" || return 1

    remove_file="${RUN_ROOT}/remove-$(basename "$file")"
    if ! python3 -c '
import json,sys
src,dst=sys.argv[1:3]
data=json.load(open(src,encoding="utf-8"))
out=[]
for item in data:
    out.append({
        "keyname": item["keyname"],
        "valuename": item["valuename"],
        "class": item["class"],
    })
json.dump(out,open(dst,"w",encoding="utf-8"),indent=2)
' "$file" "$remove_file"; then
        msg_warn "Unable to build GPO removal JSON."
        return 1
    fi

    backup_gpo_safe "$guid" || true
    confirm_high_risk "Remove settings described by $(basename "$file") from GPO $guid" || return 1

    if ! capture_samba_gpo output remove "$guid" --content="$remove_file"; then
        printf '%s\n' "$output" >&2
        msg_warn "GPO JSON removal failed."
        return 1
    fi

    change APPLIED "Removed JSON-described settings from GPO=$guid source=$(basename "$file")"
    result PASS "GPO JSON remove" "$(basename "$file") -> $guid" "removed"
}

gpo_dn_from_guid() {
    local guid="$1"
    printf 'CN=%s,CN=Policies,CN=System,%s' "$guid" "$(domain_dn "$DOMAIN")"
}

get_gpo_flags() {
    local guid="$1" dn flags=""
    dn="$(gpo_dn_from_guid "$guid")"

    if [[ -f /var/lib/samba/private/sam.ldb ]]; then
        flags="$(
            ldbsearch -H /var/lib/samba/private/sam.ldb -b "$dn" -s base flags 2>/dev/null |
            awk -F': ' '/^flags:/{print $2;exit}' || true
        )"
    fi

    [[ "$flags" =~ ^[0-3]$ ]] || flags=0
    printf '%s' "$flags"
}

gpo_flags_label() {
    case "${1:-0}" in
        0) printf 'ENABLED' ;;
        1) printf 'USER_DISABLED' ;;
        2) printf 'COMPUTER_DISABLED' ;;
        3) printf 'ALL_DISABLED' ;;
        *) printf 'UNKNOWN' ;;
    esac
}

set_gpo_flags() {
    local guid="$1" flags="$2" dn file actual
    [[ "$flags" =~ ^[0-3]$ ]] || return 1
    dn="$(gpo_dn_from_guid "$guid")"
    file="${RUN_ROOT}/gpo-${guid//[{}]/}-flags.ldif"

    cat >"$file" <<EOF
dn: $dn
changetype: modify
replace: flags
flags: $flags
-
EOF
    chmod 600 "$file"

    ensure_kerberos_ticket "${ADMIN_USER:-Administrator}"
    ldbmodify_with_assistant_ticket "$file" >/dev/null

    actual="$(get_gpo_flags "$guid")"
    [[ "$actual" == "$flags" ]] || {
        msg_warn "GPO status verification failed: requested=$flags actual=$actual"
        return 1
    }

    change APPLIED "GPO status guid=$guid flags=$flags ($(gpo_flags_label "$flags"))"
    result PASS "GPO status" "$guid -> $(gpo_flags_label "$flags")" "updated"
}

gpo_status_menu() {
    local guid flags choice newflags
    guid="$(select_gpo_guid)" || return 1
    flags="$(get_gpo_flags "$guid")"

    while true; do
        (( MENU_MAIN_REQUESTED )) && return 0
        ui_menu_screen "GPO STATUS" "Enable/disable the whole GPO or one policy class; links are managed separately"
        printf '  GUID           : %s\n' "$guid"
        printf '  Current flags  : %s\n' "$flags"
        printf '  Current state  : %s\n\n' "$(gpo_flags_label "$flags")"
        ui_menu_item "1" "Enabled" "Machine + user settings enabled"
        ui_menu_item "2" "Disable user settings" "Computer settings remain enabled"
        ui_menu_item "3" "Disable computer settings" "User settings remain enabled"
        ui_menu_item "4" "Disable all settings" "Keep GPO object/content but do not process settings" "$C_YELLOW"
        ui_menu_exit
        ui_rule

        choice="$(ask 'Select GPO state' '0')"
        case "$choice" in
            1) newflags=0 ;;
            2) newflags=1 ;;
            3) newflags=2 ;;
            4) newflags=3 ;;
            H|h) MENU_MAIN_REQUESTED=1; break ;;
            0) break ;;
            *) msg_warn "Invalid state."; ui_pause; continue ;;
        esac

        if [[ "$newflags" == "$flags" ]]; then
            result SKIP "GPO status" "$(gpo_flags_label "$flags")" "already selected"
        elif confirm "Change GPO status to $(gpo_flags_label "$newflags")?" N; then
            backup_gpo_safe "$guid" || true
            set_gpo_flags "$guid" "$newflags"
            flags="$(get_gpo_flags "$guid")"
        fi
        ui_pause
    done
}

stage_windows_starter_gpos() {
    local id name file guid output=""
    initialize_gpo_library

    printf '\nThis stages six Windows security GPOs with policy content loaded,\n'
    printf 'but leaves them ALL_DISABLED and UNLINKED for safe review/testing.\n\n'
    confirm "Stage the recommended Windows GPO set?" N || return 0

    for id in 1 2 3 4 5 6; do
        case "$id" in
            1) name="SEC - PowerShell Logging"; file="${GPO_WINDOWS_DIR}/sec-powershell-logging.json" ;;
            2) name="SEC - Disable LLMNR"; file="${GPO_WINDOWS_DIR}/sec-disable-llmnr.json" ;;
            3) name="SEC - SMB Guest Hardening"; file="${GPO_WINDOWS_DIR}/sec-smb-guest.json" ;;
            4) name="SEC - RDP Network Level Authentication"; file="${GPO_WINDOWS_DIR}/sec-rdp-nla.json" ;;
            5) name="SEC - Secure Screen Lock"; file="${GPO_WINDOWS_DIR}/sec-screen-lock.json" ;;
            6) name="SEC - Disable AlwaysInstallElevated"; file="${GPO_WINDOWS_DIR}/sec-disable-alwaysinstallelevated.json" ;;
        esac

        guid="$(find_gpo_guid "$name" || true)"
        if [[ -z "$guid" ]]; then
            guid="$(ensure_gpo "$name")" || {
                msg_warn "Could not create $name; continuing."
                continue
            }
        else
            backup_gpo_safe "$guid" || true
        fi

        if ! capture_samba_gpo output load "$guid" --content="$file"; then
            printf '%s\n' "$output" >&2
            msg_warn "Could not load $name; continuing."
            continue
        fi

        if ! set_gpo_flags "$guid" 3; then
            msg_warn "Could not disable staged GPO $name; review it manually."
            continue
        fi

        result PASS "Staged GPO" "$name / $guid" "ALL_DISABLED + unlinked"
    done
}

json_policy_library_menu() {
    initialize_gpo_library

    while true; do
        (( MENU_MAIN_REQUESTED )) && return 0
        ui_menu_screen "JSON POLICY LIBRARY" "Built-in policies, editable custom JSON, validation and deployment"
        ui_menu_item "1" "List JSON policies" "Show built-in and custom policy files"
        ui_menu_item "2" "Apply JSON policy" "Merge/replace JSON into existing or new GPO" "$C_GREEN"
        ui_menu_item "3" "Remove JSON settings" "Remove policy values described by a JSON file" "$C_YELLOW"
        ui_menu_item "4" "Copy built-in to custom" "Create an editable copy without modifying managed templates"
        ui_menu_item "5" "Create custom skeleton" "Create a new JSON policy source"
        ui_menu_item "6" "Edit custom JSON" "Open custom policy in \$EDITOR/nano/vi"
        ui_menu_item "7" "Validate JSON" "Syntax + minimal Samba policy schema validation"
        ui_menu_item "8" "Storage paths" "Show library, SYSVOL and PolicyDefinitions paths"
        ui_menu_item "9" "Read JSON/GPO manual" "Open generated GPO-GUIDE.md"
        ui_menu_exit
        ui_rule

        local choice file
        choice="$(ask 'Select operation' '1')"
        case "$choice" in
            1) show_json_policy_inventory all; ui_pause ;;
            2) apply_json_policy_interactive all; ui_pause ;;
            3) remove_json_policy_interactive; ui_pause ;;
            4) copy_builtin_json_to_custom; ui_pause ;;
            5) create_custom_json_skeleton; ui_pause ;;
            6) edit_custom_json_file; ui_pause ;;
            7)
                file="$(select_json_policy_file all)" || { ui_pause; continue; }
                validate_gpo_json_file "$file" || true
                ui_pause
                ;;
            8) show_gpo_library_paths; ui_pause ;;
            9) show_gpo_manual; ui_pause ;;
            H|h) MENU_MAIN_REQUESTED=1; break ;;
            0) break ;;
            *) msg_warn "Invalid menu option."; ui_pause ;;
        esac
    done
}


# ---------------------------------------------------------------------------
# Platform-aware Group Policy management
#
# GPO consumers are not interchangeable:
#   * Windows clients consume Windows CSE/Registry policies.
#   * Ubuntu ADSys clients consume Ubuntu-specific policies/templates.
#   * Samba/winbind Linux clients can consume Samba VGP/CSE policies.
#   * SSSD may use GPOs for access control, which is a separate concern.
# ---------------------------------------------------------------------------

get_sysvol_path() {
    local path=""

    if command_exists samba-tool; then
        path="$(
            samba-tool testparm \
                --section-name=sysvol \
                --parameter-name=path 2>/dev/null |
            tail -n1 |
            sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true
        )"
    fi

    if [[ -z "$path" ]] && command_exists testparm; then
        path="$(
            testparm -s \
                --section-name=sysvol \
                --parameter-name=path 2>/dev/null |
            tail -n1 |
            sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true
        )"
    fi

    if [[ -z "$path" ]]; then
        if [[ -d /var/lib/samba/sysvol ]]; then
            path="/var/lib/samba/sysvol"
        elif [[ -d /var/lib/samba/state/sysvol ]]; then
            path="/var/lib/samba/state/sysvol"
        fi
    fi

    [[ -n "$path" ]] || return 1
    printf '%s' "$path"
}

get_policy_definitions_path() {
    local sysvol
    sysvol="$(get_sysvol_path)" || return 1
    printf '%s/%s/Policies/PolicyDefinitions' "$sysvol" "${DOMAIN,,}"
}

audit_platform_gpo_readiness() {
    local store=""
    store="$(get_policy_definitions_path 2>/dev/null || true)"

    ui_menu_screen "GPO PLATFORM READINESS" "Central Store and client-policy capability inventory"

    if [[ -n "$store" ]]; then
        printf '  %-24s %s\n' "Central Store" "$store"
        if [[ -d "$store" ]]; then
            result PASS "PolicyDefinitions" "present" "$store"
        else
            result WARN "PolicyDefinitions" "missing" "$store"
        fi

        if [[ -f "$store/Ubuntu.admx" ]]; then
            result PASS "Ubuntu ADMX" "$store/Ubuntu.admx" "present"
        else
            result WARN "Ubuntu ADMX" "not installed" "Ubuntu.admx"
        fi

        if [[ -f "$store/en-US/Ubuntu.adml" ]]; then
            result PASS "Ubuntu ADML en-US" "$store/en-US/Ubuntu.adml" "present"
        else
            result WARN "Ubuntu ADML en-US" "not installed" "en-US/Ubuntu.adml"
        fi
    else
        result FAIL "SYSVOL path" "could not determine" "readable sysvol share"
    fi

    if samba-tool gpo admxload --help >/dev/null 2>&1; then
        result PASS "Samba ADMX loader" "available" "samba-tool gpo admxload"
    else
        result WARN "Samba ADMX loader" "unsupported" "modern Samba"
    fi

    if command_exists samba-gpupdate; then
        result PASS "Local samba-gpupdate" "installed on this host" "Samba Linux GPO client available"
    else
        result INFO "Local samba-gpupdate" "not installed on DC" "only needed on Samba/winbind clients"
    fi

    if command_exists adsysctl; then
        result PASS "ADSys tooling" "adsysctl available" "can generate Ubuntu ADMX/ADML locally"
    else
        result INFO "ADSys tooling" "not installed on DC" "templates may be copied from an Ubuntu ADSys client"
    fi

    printf '\n'
    printf '  %bClient policy families%b\n' "$C_BOLD" "$C_RESET"
    printf '    Windows       : Registry/CSE policies + Windows ADMX Central Store\n'
    printf '    Ubuntu ADSys  : Ubuntu.admx/Ubuntu.adml + ADSys client\n'
    printf '    Samba Linux   : samba-gpupdate + Samba VGP/CSE policy types\n'
    printf '    SSSD          : GPO-based access control; not a Windows desktop-policy engine\n'
}

install_ubuntu_adsys_templates_from_files() {
    local admx="$1" adml="$2" store=""

    [[ -f "$admx" ]] || { msg_warn "Ubuntu ADMX file not found: $admx"; return 1; }
    [[ -f "$adml" ]] || { msg_warn "Ubuntu ADML file not found: $adml"; return 1; }

    store="$(get_policy_definitions_path)" || {
        msg_warn "Unable to determine SYSVOL PolicyDefinitions path."
        return 1
    }

    mkdir -p "$store/en-US"

    [[ -e "$store/Ubuntu.admx" ]] && backup_file "$store/Ubuntu.admx"
    [[ -e "$store/en-US/Ubuntu.adml" ]] && backup_file "$store/en-US/Ubuntu.adml"

    install -o root -g root -m 0644 "$admx" "$store/Ubuntu.admx"
    install -o root -g root -m 0644 "$adml" "$store/en-US/Ubuntu.adml"

    result PASS "Ubuntu ADSys templates" "$store" "Ubuntu.admx + en-US/Ubuntu.adml"
    change APPLIED "Installed Ubuntu ADSys administrative templates into SYSVOL Central Store"
}

generate_and_install_ubuntu_adsys_templates() {
    command_exists adsysctl || {
        msg_warn "adsysctl is not installed. Generate Ubuntu.admx/Ubuntu.adml on an ADSys-capable Ubuntu client and use the local-file installer."
        return 1
    }

    local mode tmp
    mode="$(select_enum_value "UBUNTU ADSYS TEMPLATE SET" 1         "lts-only|Generate templates for supported LTS releases"         "all|Generate all available Ubuntu templates")" || return 1

    tmp="$(mktemp -d "${RUN_ROOT}/adsys-admx.XXXXXX")"
    (
        cd "$tmp"
        adsysctl policy admx "$mode"
    ) || {
        msg_warn "adsysctl could not generate the administrative templates."
        return 1
    }

    [[ -f "$tmp/Ubuntu.admx" && -f "$tmp/Ubuntu.adml" ]] || {
        msg_warn "adsysctl completed but Ubuntu.admx/Ubuntu.adml were not found."
        return 1
    }

    install_ubuntu_adsys_templates_from_files "$tmp/Ubuntu.admx" "$tmp/Ubuntu.adml"
}

create_platform_scoped_gpo() {
    local prefix="$1" description="$2"
    local name guid dn

    name="$(ask 'GPO display name' "${prefix} - New Policy")"
    [[ -n "$name" ]] || return 1

    printf '\n  Target family: %s\n' "$description"
    if ! guid="$(create_gpo_safe "$name")"; then
        msg_warn "GPO creation failed; no link was created."
        return 1
    fi

    printf '  Created GUID : %s\n' "$guid"

    if confirm "Link this GPO to a domain/OU now?" Y; then
        dn="$(select_directory_target_dn)" || return 0
        local output=""
        if ! capture_samba_gpo output setlink "$dn" "$guid"; then
            printf '%s\n' "$output" >&2
            msg_warn "GPO exists but linking failed."
            return 1
        fi
        result PASS "GPO link" "$name -> $dn" "linked"
    fi
}

ubuntu_adsys_gpo_menu() {
    initialize_gpo_library

    while true; do
        (( MENU_MAIN_REQUESTED )) && return 0
        ui_menu_screen "UBUNTU ADSYS POLICY CONTROL" "Ubuntu administrative templates and Ubuntu-scoped GPO preparation"
        ui_menu_item "1" "Audit ADSys readiness" "Check Central Store, Ubuntu ADMX/ADML and local tooling"
        ui_menu_item "2" "Install local templates" "Copy Ubuntu.admx + Ubuntu.adml into detected SYSVOL Central Store"
        ui_menu_item "3" "Generate templates" "Use local adsysctl to generate lts-only/all templates"
        ui_menu_item "4" "Create Ubuntu GPO" "Create/link an empty UBU-prefixed policy for ADSys clients" "$C_GREEN"
        ui_menu_item "5" "Stage Ubuntu GPO set" "Create disabled/unlinked UBU baseline/login/desktop GPO objects" "$C_YELLOW"
        ui_menu_item "6" "Show paths & workflow" "Display exact Central Store path and ADSys generation commands"
        ui_menu_item "7" "JSON/GPO manual" "Open persistent GPO-GUIDE.md"
        ui_menu_exit
        ui_rule

        local choice admx adml name guid
        choice="$(ask 'Select operation' '1')"
        case "$choice" in
            1) audit_platform_gpo_readiness; ui_pause ;;
            2)
                admx="$(ask 'Path to Ubuntu.admx')"
                adml="$(ask 'Path to Ubuntu.adml')"
                install_ubuntu_adsys_templates_from_files "$admx" "$adml"
                ui_pause
                ;;
            3) generate_and_install_ubuntu_adsys_templates; ui_pause ;;
            4)
                create_platform_scoped_gpo "UBU" "Ubuntu ADSys clients"
                ui_pause
                ;;
            5)
                printf '\nThe following GPOs will be created disabled and unlinked:\n'
                printf '  UBU - Baseline\n  UBU - Login Screen\n  UBU - Desktop Users\n\n'
                confirm "Stage these Ubuntu GPO objects?" N || { ui_pause; continue; }
                for name in "UBU - Baseline" "UBU - Login Screen" "UBU - Desktop Users"; do
                    guid="$(find_gpo_guid "$name" || true)"
                    [[ -n "$guid" ]] || guid="$(ensure_gpo "$name")" || continue
                    set_gpo_flags "$guid" 3 || true
                    result PASS "Staged Ubuntu GPO" "$name / $guid" "ALL_DISABLED + unlinked"
                done
                ui_pause
                ;;
            6)
                show_gpo_library_paths
                printf '\n'
                printf '  Generate matching templates on an Ubuntu ADSys client:\n'
                printf '    mkdir -p ~/adsys-admx && cd ~/adsys-admx\n'
                printf '    adsysctl policy admx lts-only\n'
                printf '\n'
                printf '  Then copy Ubuntu.admx and Ubuntu.adml to this DC and use menu option [2].\n'
                printf '  Do not guess ADSys Registry value names from Windows policies; use the\n'
                printf '  Ubuntu.admx generated by the ADSys version deployed to your clients.\n'
                ui_pause
                ;;
            7) show_gpo_manual; ui_pause ;;
            H|h) MENU_MAIN_REQUESTED=1; break ;;
            0) break ;;
            *) msg_warn "Invalid menu option."; ui_pause ;;
        esac
    done
}

samba_linux_gpo_menu() {
    while true; do
        (( MENU_MAIN_REQUESTED )) && return 0
        ui_menu_screen "SAMBA LINUX POLICY CONTROL" "Samba VGP/CSE policies for Linux clients using Samba/winbind and samba-gpupdate"
        ui_menu_item "1" "List local CSEs" "Show Samba Client Side Extensions registered on this host"
        ui_menu_item "2" "Effective GPOs" "List GPOs Samba resolves for a user/computer account"
        ui_menu_item "3" "Inspect smb.conf policy" "Show Samba smb.conf settings stored in a selected GPO"
        ui_menu_item "4" "Set smb.conf policy" "Set one Samba/winbind smb.conf GPO setting" "$C_YELLOW"
        ui_menu_item "5" "Create Samba Linux GPO" "Create/link an empty LNX-prefixed policy" "$C_GREEN"
        ui_menu_item "6" "Show native policy types" "Display Samba-supported manage/CSE families"
        ui_menu_exit
        ui_rule

        local choice guid account setting value output=""
        choice="$(ask 'Select operation' '1')"
        case "$choice" in
            1)
                samba-tool gpo cse list || true
                ui_pause
                ;;
            2)
                account="$(select_user_or_computer_account)" || { ui_pause; continue; }
                if capture_samba_gpo output list "$account"; then
                    printf '%s\n' "$output"
                else
                    printf '%s\n' "$output" >&2
                fi
                ui_pause
                ;;
            3)
                guid="$(select_gpo_guid)" || { ui_pause; continue; }
                if capture_samba_gpo output manage smb_conf list "$guid"; then
                    printf '%s\n' "$output"
                else
                    printf '%s\n' "$output" >&2
                fi
                ui_pause
                ;;
            4)
                guid="$(select_gpo_guid)" || { ui_pause; continue; }
                setting="$(ask 'smb.conf setting name' 'apply group policies')"
                value="$(ask 'Value' 'yes')"
                if confirm "Store Samba Linux smb.conf policy '$setting = $value' in $guid?" N; then
                    if ! capture_samba_gpo output manage smb_conf set "$guid" "$setting" "$value"; then
                        printf '%s\n' "$output" >&2
                        msg_warn "Samba Linux GPO setting failed."
                    fi
                fi
                ui_pause
                ;;
            5) create_platform_scoped_gpo "LNX" "Samba/winbind Linux clients"; ui_pause ;;
            6)
                printf '\n'
                ui_rule
                printf '%bNative Samba Linux GPO families%b\n' "$C_BOLD" "$C_RESET"
                ui_rule
                printf '  smb_conf        Samba/winbind smb.conf settings\n'
                printf '  scripts         Startup/logon-style scripts supported by Samba CSEs\n'
                printf '  motd / issue    Login banners\n'
                printf '  access          Host access policy\n'
                printf '  openssh         OpenSSH settings (when supported by installed Samba)\n'
                printf '  sudoers         Sudo policy (when supported)\n'
                printf '  files/symlink   File and symlink policy CSEs (when supported)\n'
                printf '\n  Client requirement: Samba/winbind policy support and samba-gpupdate/CSEs.\n'
                ui_pause
                ;;
            H|h) MENU_MAIN_REQUESTED=1; break ;;
            0) break ;;
            *) msg_warn "Invalid menu option."; ui_pause ;;
        esac
    done
}

sssd_gpo_compatibility_audit() {
    local sysvol="" entry guid name path gpt status
    local -a entries=()

    sysvol="$(get_sysvol_path)" || {
        msg_warn "Unable to determine SYSVOL path."
        return 1
    }

    mapfile -t entries < <(gpo_inventory_tsv)

    ui_menu_screen "SSSD GPO ACCESS-CONTROL COMPATIBILITY" "Read-only check that LDAP GPO objects have corresponding SYSVOL/GPT.INI data"
    printf '  %-42s %-39s %s\n' "GPO" "GUID" "SYSVOL"
    ui_rule

    for entry in "${entries[@]}"; do
        guid="${entry%%$'\t'*}"
        name="${entry#*$'\t'}"
        path="${sysvol}/${DOMAIN,,}/Policies/${guid}"
        gpt="${path}/GPT.INI"

        if [[ -f "$gpt" ]]; then
            status="GPT.INI OK"
            printf '  %-42s %-39s %b%s%b\n' "$name" "$guid" "$C_GREEN" "$status" "$C_RESET"
        elif [[ -d "$path" ]]; then
            status="GPT.INI MISSING"
            printf '  %-42s %-39s %b%s%b\n' "$name" "$guid" "$C_YELLOW" "$status" "$C_RESET"
        else
            status="SYSVOL DIR MISSING"
            printf '  %-42s %-39s %b%s%b\n' "$name" "$guid" "$C_RED" "$status" "$C_RESET"
        fi
    done

    printf '\n'
    printf '  This check is intentionally read-only. SSSD GPO access control is not the same\n'
    printf '  as applying Windows or Ubuntu desktop policies. Missing SYSVOL/GPT.INI data\n'
    printf '  should be diagnosed before attempting manual repair.\n'
    ui_rule
}

mixed_platform_gpo_guidance() {
    ui_menu_screen "MIXED WINDOWS / LINUX DOMAIN" "Recommended separation model for heterogeneous client policy"
    printf '  Recommended structure:\n\n'
    printf '    OU=Windows-Clients\n'
    printf '      -> WIN/SEC GPOs (Windows Registry/CSE policies)\n\n'
    printf '    OU=Ubuntu-Clients\n'
    printf '      -> UBU GPOs (Ubuntu ADSys administrative templates/policies)\n\n'
    printf '    OU=Samba-Linux\n'
    printf '      -> LNX GPOs (Samba VGP/CSE policies where appropriate)\n\n'
    printf '  SSSD GPO access control is evaluated separately and may inspect ordinary AD GPOs.\n'
    printf '  Avoid assuming that a Registry policy useful for Windows has meaning on Ubuntu,\n'
    printf '  or that an Ubuntu ADSys policy will be consumed by Windows clients.\n'
    ui_rule
}

platform_gpo_catalog_menu() {
    while true; do
        (( MENU_MAIN_REQUESTED )) && return 0
        ui_menu_screen "PLATFORM-AWARE GPO CONTROL" "Choose the policy consumer before creating or applying a Group Policy"
        ui_menu_item "1" "Windows clients" "Windows Registry/CSE security-policy catalog" "$C_GREEN"
        ui_menu_item "2" "Ubuntu ADSys clients" "Ubuntu.admx/ADML readiness and Ubuntu-scoped GPOs"
        ui_menu_item "3" "Samba Linux clients" "Samba/winbind VGP/CSE policies and samba-gpupdate"
        ui_menu_item "4" "SSSD access control" "Audit LDAP GPO objects vs SYSVOL/GPT.INI"
        ui_menu_item "5" "Mixed estate guidance" "Recommended OU/GPO separation for Windows + Linux"
        ui_menu_item "6" "Platform readiness" "Central Store and client-policy capability inventory"
        ui_menu_exit
        ui_rule

        local choice
        choice="$(ask 'Select target platform' '1')"
        case "$choice" in
            1) security_gpo_catalog_menu ;;
            2) ubuntu_adsys_gpo_menu ;;
            3) samba_linux_gpo_menu ;;
            4) sssd_gpo_compatibility_audit; ui_pause ;;
            5) mixed_platform_gpo_guidance; ui_pause ;;
            6) audit_platform_gpo_readiness; ui_pause ;;
            H|h) MENU_MAIN_REQUESTED=1; break ;;
            0) break ;;
            *) msg_warn "Invalid platform selection."; ui_pause ;;
        esac
    done
}

security_gpo_catalog_menu() {
    ensure_kerberos_ticket "${ADMIN_USER:-Administrator}"
    samba-tool gpo load --help >/dev/null 2>&1 ||
        { msg_warn "Installed Samba does not support gpo load."; return 1; }

    initialize_gpo_library

    while true; do
        (( MENU_MAIN_REQUESTED )) && return 0
        ui_menu_screen "WINDOWS SECURITY GPO CATALOG" "Registry-based policies for Windows domain clients; separate from Ubuntu ADSys"
        ui_menu_item "1" "PowerShell Logging" "Script Block + Module Logging"
        ui_menu_item "2" "Disable LLMNR" "Reduce multicast name-resolution poisoning exposure"
        ui_menu_item "3" "SMB Guest Hardening" "Disable insecure guest authentication"
        ui_menu_item "4" "RDP NLA" "Require Network Level Authentication"
        ui_menu_item "5" "Secure Screen Lock" "10-minute secure screensaver for users"
        ui_menu_item "6" "Disable AlwaysInstallElevated" "Disable elevated MSI policy for machine + user"
        ui_menu_item "7" "Authorized Use Notice" "Domain legal/authorized-use banner"
        ui_menu_item "8" "Combined starter JSON" "Load 1-6 into one GPO instead of separate GPOs"
        ui_menu_item "A" "Deploy starter pack" "Create/link policies 1-6 immediately" "$C_GREEN"
        ui_menu_item "S" "Stage starter pack" "Create/load 1-6 ALL_DISABLED and UNLINKED for testing" "$C_YELLOW"
        ui_menu_item "J" "JSON policy library" "Browse/edit/validate/load built-in and custom JSON"
        ui_menu_item "D" "Domain password policy" "Review/configure Samba complexity + lockout settings"
        ui_menu_exit
        ui_rule

        local choice target id guid output=""
        choice="$(ask 'Select policy' '0')"
        case "${choice^^}" in
            H|h) MENU_MAIN_REQUESTED=1; break ;;
            0) break ;;
            A)
                if target="$(select_directory_target_dn)"; then
                    for id in 1 2 3 4 5 6; do
                        if ! deploy_security_gpo_template "$id" "$target"; then
                            msg_warn "Starter-pack policy $id failed; remaining policies will still be attempted."
                        fi
                    done
                    samba-tool ntacl sysvolcheck >/dev/null 2>&1 ||
                        msg_warn "SYSVOL ACL differences detected after GPO deployment."
                fi
                ui_pause
                ;;
            S) stage_windows_starter_gpos; ui_pause ;;
            J) json_policy_library_menu ;;
            D) domain_password_policy_menu ;;
            8)
                guid="$(select_or_create_gpo_guid)" || { ui_pause; continue; }
                backup_gpo_safe "$guid" || true
                if confirm "Merge combined starter JSON into $guid?" N; then
                    if ! capture_samba_gpo output load "$guid" --content="${GPO_WINDOWS_DIR}/sec-workstation-starter-combined.json"; then
                        printf '%s\n' "$output" >&2
                        msg_warn "Combined starter load failed."
                    else
                        result PASS "Combined starter" "$guid" "loaded"
                    fi
                fi
                ui_pause
                ;;
            1|2|3|4|5|6|7)
                if target="$(select_directory_target_dn)"; then
                    deploy_security_gpo_template "$choice" "$target"
                    samba-tool ntacl sysvolcheck >/dev/null 2>&1 ||
                        msg_warn "SYSVOL ACL differences detected."
                fi
                ui_pause
                ;;
            *) msg_warn "Invalid catalog selection."; ui_pause ;;
        esac
    done
}

domain_password_policy_menu() {
    while true; do
        (( MENU_MAIN_REQUESTED )) && return 0
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
                complexity="$(select_enum_value "PASSWORD COMPLEXITY" 1                     "on|Require Samba password complexity"                     "off|Disable complexity requirement"                     "default|Use Samba/domain default")" || { ui_pause; continue; }
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
            H|h) MENU_MAIN_REQUESTED=1; break ;;
            0) break ;;
            *) msg_warn "Invalid menu option."; ui_pause ;;
        esac
    done
}

user_admin_menu() {
    while true; do
        (( MENU_MAIN_REQUESTED )) && return 0
        ui_menu_screen "USER DIRECTORY" "Selector-driven account lifecycle, profile, password and group operations"
        ui_menu_item "1" "List users" "Inventory all domain user accounts"
        ui_menu_item "2" "Inspect user" "Select an account then show directory attributes"
        ui_menu_item "3" "Create user" "Guided creation with first-logon password and groups" "$C_GREEN"
        ui_menu_item "4" "Edit user" "Select account; profile, OU, groups, password and state"
        ui_menu_item "5" "Reset password" "Select account; optionally require change at next logon"
        ui_menu_item "6" "Group memberships" "Select account then indexed add/remove membership workflow"
        ui_menu_item "7" "Enable user" "Select and re-enable a disabled identity" "$C_GREEN"
        ui_menu_item "8" "Disable user" "Select and block interactive authentication" "$C_YELLOW"
        ui_menu_item "9" "Unlock user" "Select account and clear supported lockout state"
        ui_menu_item "10" "Delete user" "Select and permanently remove an identity" "$C_RED"
        ui_menu_exit
        ui_rule

        local choice user
        choice="$(ask 'Select operation' '1')"
        case "$choice" in
            1) samba-tool user list | sort; ui_pause ;;
            2)
                user="$(select_domain_user)" || { ui_pause; continue; }
                samba-tool user show "$user"; ui_pause
                ;;
            3) create_user_interactive; ui_pause ;;
            4)
                user="$(select_domain_user)" || { ui_pause; continue; }
                edit_user_interactive_menu "$user"
                ;;
            5)
                user="$(select_domain_user)" || { ui_pause; continue; }
                reset_user_password_interactive "$user"
                ui_pause
                ;;
            6)
                user="$(select_domain_user)" || { ui_pause; continue; }
                manage_user_memberships "$user"
                ;;
            7)
                user="$(select_domain_user)" || { ui_pause; continue; }
                samba-tool user enable "$user"; ui_pause
                ;;
            8)
                user="$(select_domain_user)" || { ui_pause; continue; }
                case "${user,,}" in administrator|krbtgt) msg_warn "Protected built-in account."; ui_pause; continue ;; esac
                confirm_high_risk "Disable AD user '$user'" && samba-tool user disable "$user"
                ui_pause
                ;;
            9)
                user="$(select_domain_user)" || { ui_pause; continue; }
                samba-tool user unlock --help >/dev/null 2>&1 \
                    && samba-tool user unlock "$user" \
                    || msg_warn "user unlock is unsupported by installed Samba."
                ui_pause
                ;;
            10)
                user="$(select_domain_user)" || { ui_pause; continue; }
                case "${user,,}" in administrator|guest|krbtgt) msg_warn "Refusing protected built-in account deletion."; ui_pause; continue ;; esac
                confirm_high_risk "PERMANENTLY delete AD user '$user'" && samba-tool user delete "$user"
                ui_pause
                ;;
            H|h) MENU_MAIN_REQUESTED=1; break ;;
            0) break ;;
            *) msg_warn "Invalid menu option."; ui_pause ;;
        esac
    done
}

group_admin_menu() {
    while true; do
        (( MENU_MAIN_REQUESTED )) && return 0
        ui_menu_screen "GROUP DIRECTORY" "Indexed group and principal selection, membership management and delegation"
        ui_menu_item "1" "List groups" "Indexed inventory of domain groups"
        ui_menu_item "2" "Inspect group" "Select a group then show its directory object"
        ui_menu_item "3" "Create group" "Create a new domain group" "$C_GREEN"
        ui_menu_item "4" "Edit group" "Select group then open Samba object editor"
        ui_menu_item "5" "List members" "Select group then display membership"
        ui_menu_item "6" "Add member" "Select group and then select user/group/computer" "$C_GREEN"
        ui_menu_item "7" "Remove member" "Select group then select one of its current members" "$C_YELLOW"
        ui_menu_item "8" "Delete group" "Select and permanently delete non-core group" "$C_RED"
        ui_menu_exit
        ui_rule

        local choice group member
        choice="$(ask 'Select operation' '1')"
        case "$choice" in
            1) list_domain_groups_indexed; ui_pause ;;
            2)
                group="$(select_domain_group)" || { ui_pause; continue; }
                samba-tool group show "$group"; ui_pause
                ;;
            3) create_group_selector_item >/dev/null; ui_pause ;;
            4)
                group="$(select_domain_group)" || { ui_pause; continue; }
                samba-tool group edit "$group"; ui_pause
                ;;
            5)
                group="$(select_domain_group)" || { ui_pause; continue; }
                samba-tool group listmembers "$group"; ui_pause
                ;;
            6)
                group="$(select_domain_group)" || { ui_pause; continue; }
                member="$(select_domain_principal)" || { ui_pause; continue; }
                samba-tool group addmembers "$group" "$member"
                ui_pause
                ;;
            7)
                group="$(select_domain_group)" || { ui_pause; continue; }
                member="$(select_group_member "$group")" || { ui_pause; continue; }
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
            H|h) MENU_MAIN_REQUESTED=1; break ;;
            0) break ;;
            *) msg_warn "Invalid menu option."; ui_pause ;;
        esac
    done
}

computer_admin_menu() {
    while true; do
        (( MENU_MAIN_REQUESTED )) && return 0
        ui_menu_screen "DOMAIN COMPUTERS" "Joined computer accounts with selector-driven network presence and lifecycle operations"
        ui_menu_item "1" "List accounts" "Inventory computer objects joined to the domain"
        ui_menu_item "2" "Network presence" "Indexed DNS/IP/SMB readiness inventory"
        ui_menu_item "3" "Inspect computer" "Select a listed computer and show its attributes"
        ui_menu_item "4" "Edit computer" "Select a computer then open object editor when supported"
        ui_menu_item "5" "Delete stale account" "Select and remove an obsolete computer object" "$C_RED"
        ui_menu_exit
        ui_rule
        local choice computer
        choice="$(ask 'Select operation' '1')"
        case "$choice" in
            1) samba-tool computer list | sort; ui_pause ;;
            2) list_domain_computers_status; ui_pause ;;
            3)
                computer="$(select_domain_computer)" || { ui_pause; continue; }
                samba-tool computer show "$computer"; ui_pause
                ;;
            4)
                computer="$(select_domain_computer)" || { ui_pause; continue; }
                samba-tool computer edit --help >/dev/null 2>&1 \
                    && samba-tool computer edit "$computer" \
                    || msg_warn "computer edit is unsupported."
                ui_pause
                ;;
            5)
                computer="$(select_domain_computer)" || { ui_pause; continue; }
                confirm_high_risk "Delete computer account '$computer'" && samba-tool computer delete "$computer"
                ui_pause
                ;;
            H|h) MENU_MAIN_REQUESTED=1; break ;;
            0) break ;;
            *) msg_warn "Invalid menu option."; ui_pause ;;
        esac
    done
}

permissions_admin_menu() {
    while true; do
        (( MENU_MAIN_REQUESTED )) && return 0
        ui_menu_screen "ACCESS & DELEGATION" "Selector-driven memberships plus advanced directory-service ACL operations"
        ui_menu_item "1" "User groups" "Select a user and show direct memberships"
        ui_menu_item "2" "Group members" "Select group then enumerate principals"
        ui_menu_item "3" "Grant membership" "Select group and principal" "$C_GREEN"
        ui_menu_item "4" "Revoke membership" "Select group then one current member" "$C_YELLOW"
        ui_menu_item "5" "Manage user groups" "Select user then full indexed membership workflow"
        ui_menu_item "6" "Inspect DS ACL" "Select directory object or enter DN manually"
        ui_menu_item "7" "Add DS ACL ACE" "Select object; apply a raw SDDL ACE" "$C_YELLOW"
        ui_menu_item "8" "Delete DS ACL ACE" "Select object; remove raw SDDL ACE when supported" "$C_RED"
        ui_menu_exit
        ui_rule

        local choice user group member dn sddl
        choice="$(ask 'Select operation' '1')"
        case "$choice" in
            1)
                user="$(select_domain_user)" || { ui_pause; continue; }
                samba-tool user getgroups "$user"; ui_pause
                ;;
            2)
                group="$(select_domain_group)" || { ui_pause; continue; }
                samba-tool group listmembers "$group"; ui_pause
                ;;
            3)
                group="$(select_domain_group)" || { ui_pause; continue; }
                member="$(select_domain_principal)" || { ui_pause; continue; }
                samba-tool group addmembers "$group" "$member"; ui_pause
                ;;
            4)
                group="$(select_domain_group)" || { ui_pause; continue; }
                member="$(select_group_member "$group")" || { ui_pause; continue; }
                confirm "Remove '$member' from '$group'?" N && samba-tool group removemembers "$group" "$member"
                ui_pause
                ;;
            5)
                user="$(select_domain_user)" || { ui_pause; continue; }
                manage_user_memberships "$user"
                ;;
            6)
                dn="$(select_directory_object_dn)" || { ui_pause; continue; }
                samba-tool dsacl get --objectdn="$dn"; ui_pause
                ;;
            7)
                dn="$(select_directory_object_dn)" || { ui_pause; continue; }
                sddl="$(ask 'ACE SDDL')"
                confirm_high_risk "Add raw DS ACL ACE to '$dn'" &&
                    samba-tool dsacl set --objectdn="$dn" --sddl="$sddl"
                ui_pause
                ;;
            8)
                dn="$(select_directory_object_dn)" || { ui_pause; continue; }
                sddl="$(ask 'ACE SDDL')"
                samba-tool dsacl delete --help >/dev/null 2>&1 \
                    && { confirm_high_risk "Delete DS ACL ACE from '$dn'" &&
                         samba-tool dsacl delete --objectdn="$dn" --sddl="$sddl"; } \
                    || msg_warn "dsacl delete is unsupported."
                ui_pause
                ;;
            H|h) MENU_MAIN_REQUESTED=1; break ;;
            0) break ;;
            *) msg_warn "Invalid menu option."; ui_pause ;;
        esac
    done
}

gpo_admin_menu() {
    ensure_kerberos_ticket "${ADMIN_USER:-Administrator}"
    initialize_gpo_library

    while true; do
        (( MENU_MAIN_REQUESTED )) && return 0
        ui_menu_screen "GROUP POLICY CONTROL" "Lifecycle, platform catalogs, JSON library, state, scope, diagnostics and backup"
        ui_menu_item "1" "List GPOs + GUIDs" "Indexed inventory including enabled/disabled state"
        ui_menu_item "2" "Inspect GPO" "Select an existing GPO by index"
        ui_menu_item "3" "Create GPO" "Create an empty policy and optionally link it" "$C_GREEN"
        ui_menu_item "4" "Platform GPO catalog" "Windows, Ubuntu ADSys, Samba Linux and SSSD-aware flows" "$C_GREEN"
        ui_menu_item "5" "JSON policy library" "Built-ins, custom JSON, edit/validate/load/remove"
        ui_menu_item "6" "GPO status" "Enable GPO or disable user/computer/all settings" "$C_YELLOW"
        ui_menu_item "7" "List containers" "Select GPO then show linked containers"
        ui_menu_item "8" "Link / update" "Select GPO and domain/OU target" "$C_GREEN"
        ui_menu_item "9" "Remove link" "Select GPO and domain/OU target" "$C_YELLOW"
        ui_menu_item "10" "Backup GPO" "Select and export one GPO"
        ui_menu_item "11" "GPO readiness" "Kerberos, operator membership and SYSVOL/GPO ACL diagnostics"
        ui_menu_item "12" "Delete GPO" "Backup/domain-backup then permanently delete" "$C_RED"
        ui_menu_item "13" "Legacy baseline pair" "Create/update original assistant user+machine baselines"
        ui_menu_item "14" "GPO paths & manual" "Show policy library/SYSVOL paths and open generated guide"
        ui_menu_exit
        ui_rule

        local choice guid name dn output=""
        choice="$(ask 'Select operation' '1')"
        case "$choice" in
            1) show_gpo_inventory_indexed; ui_pause ;;
            2)
                guid="$(select_gpo_guid)" || { ui_pause; continue; }
                if capture_samba_gpo output show "$guid"; then
                    printf '%s\n' "$output"
                    printf '\n  Assistant status: %s\n' "$(gpo_flags_label "$(get_gpo_flags "$guid")")"
                else
                    printf '%s\n' "$output" >&2
                fi
                ui_pause
                ;;
            3)
                name="$(ask 'GPO display name')"
                [[ -n "$name" ]] || { msg_warn "GPO name is required."; ui_pause; continue; }
                if guid="$(create_gpo_safe "$name")"; then
                    printf '\nCreated GUID: %s\n' "$guid"
                    if confirm "Stage it disabled before linking/configuring?" Y; then
                        set_gpo_flags "$guid" 3 || true
                    fi
                    if confirm "Link this GPO now?" N && dn="$(select_directory_target_dn)"; then
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
            4) platform_gpo_catalog_menu ;;
            5) json_policy_library_menu ;;
            6) gpo_status_menu ;;
            7)
                guid="$(select_gpo_guid)" || { ui_pause; continue; }
                if capture_samba_gpo output listcontainers "$guid"; then printf '%s\n' "$output"; else printf '%s\n' "$output" >&2; fi
                ui_pause
                ;;
            8)
                guid="$(select_gpo_guid)" || { ui_pause; continue; }
                dn="$(select_directory_target_dn)" || { ui_pause; continue; }
                if ! capture_samba_gpo output setlink "$dn" "$guid"; then printf '%s\n' "$output" >&2; fi
                ui_pause
                ;;
            9)
                guid="$(select_gpo_guid)" || { ui_pause; continue; }
                dn="$(select_directory_target_dn)" || { ui_pause; continue; }
                if confirm "Remove link $guid from $dn?" N; then
                    if ! capture_samba_gpo output dellink "$dn" "$guid"; then printf '%s\n' "$output" >&2; fi
                fi
                ui_pause
                ;;
            10)
                guid="$(select_gpo_guid)" || { ui_pause; continue; }
                backup_gpo_safe "$guid" || true
                ui_pause
                ;;
            11) gpo_readiness_diagnostics "Manual GPO readiness check"; ui_pause ;;
            12)
                guid="$(select_gpo_guid)" || { ui_pause; continue; }
                printf 'A domain backup is strongly recommended before deleting a GPO.\n'
                confirm "Create domain backup first?" Y && create_domain_backup no
                backup_gpo_safe "$guid" || true
                if confirm_high_risk "PERMANENTLY delete GPO $guid"; then
                    if ! capture_samba_gpo output del "$guid"; then printf '%s\n' "$output" >&2; fi
                fi
                ui_pause
                ;;
            13) set_progress_plan 1; manage_gpos; ui_pause ;;
            14)
                show_gpo_library_paths
                printf '\n'
                if confirm "Open the GPO guide now?" Y; then show_gpo_manual; fi
                ui_pause
                ;;
            H|h) MENU_MAIN_REQUESTED=1; break ;;
            0) break ;;
            *) msg_warn "Invalid menu option."; ui_pause ;;
        esac
    done
}


migration_save_plan() {
    local type="$1" new_domain="${2:-}" new_netbios="${3:-}" note="${4:-}"
    mkdir -p "$MIGRATION_DIR"
    cat >"$MIGRATION_PLAN_FILE" <<EOF
MIGRATION_TYPE=$(printf '%q' "$type")
SOURCE_DOMAIN=$(printf '%q' "$DOMAIN")
SOURCE_REALM=$(printf '%q' "$REALM")
SOURCE_NETBIOS=$(printf '%q' "$NETBIOS_DOMAIN")
TARGET_DOMAIN=$(printf '%q' "$new_domain")
TARGET_NETBIOS=$(printf '%q' "$new_netbios")
NOTE=$(printf '%q' "$note")
UPDATED_AT=$(printf '%q' "$(date -Is)")
EOF
    chmod 600 "$MIGRATION_PLAN_FILE"
    result PASS "Migration plan" "$MIGRATION_PLAN_FILE" "saved"
}

migration_load_plan() {
    [[ -r "$MIGRATION_PLAN_FILE" ]] || return 1
    # shellcheck disable=SC1090
    source "$MIGRATION_PLAN_FILE"
}

migration_show_plan() {
    if ! migration_load_plan; then
        result INFO "Migration plan" "not configured" "run assessment first"
        return 0
    fi

    section "DOMAIN MIGRATION PLAN"
    printf '  %-18s %s\n' "Type" "${MIGRATION_TYPE:-unknown}"
    printf '  %-18s %s\n' "Source domain" "${SOURCE_DOMAIN:-$DOMAIN}"
    printf '  %-18s %s\n' "Target domain" "${TARGET_DOMAIN:-not applicable}"
    printf '  %-18s %s\n' "Target NetBIOS" "${TARGET_NETBIOS:-not applicable}"
    printf '  %-18s %s\n' "Notes" "${NOTE:-}"
    printf '  %-18s %s\n' "Updated" "${UPDATED_AT:-unknown}"
    printf '\n'

    case "${MIGRATION_TYPE:-}" in
        branding-only)
            printf '  AD membership normally remains unchanged for public web/mail branding changes.\n'
            ;;
        dc-replacement)
            printf '  Member computers remain joined to %s; migrate DC/DNS/FSMO services instead.\n' "$DOMAIN"
            ;;
        domain-migration|new-forest)
            printf '  Member computers require migration/rejoin to establish a new secure channel.\n'
            ;;
        renamed-backup-lab)
            printf '  Backup-rename is treated as an advanced restore/migration workflow, not a live rename.\n'
            ;;
    esac
    ui_rule
}

migration_assessment() {
    ui_menu_screen "MIGRATION ASSESSMENT" "Classify the requested change before touching production identity"
    printf '  Current AD DNS domain : %s\n' "$DOMAIN"
    printf '  Current realm         : %s\n' "$REALM"
    printf '  Current NetBIOS       : %s\n\n' "$NETBIOS_DOMAIN"
    ui_menu_item "1" "Branding / mail / web only" "Keep AD identity; change public names/services"
    ui_menu_item "2" "Replace Domain Controller" "Keep domain; add/replace DC infrastructure"
    ui_menu_item "3" "Migrate to new AD domain" "Coexistence/trust + identity/client migration" "$C_YELLOW"
    ui_menu_item "4" "New forest migration" "Build separate forest and migrate in controlled phases" "$C_YELLOW"
    ui_menu_item "5" "Renamed backup / lab" "Advanced Samba backup-rename workflow" "$C_RED"
    ui_menu_exit
    ui_rule

    local choice target netbios note
    choice="$(ask 'Select requested change' '1')"
    case "$choice" in
        1)
            note="$(ask 'Public/company naming note' 'AD domain remains unchanged')"
            migration_save_plan "branding-only" "" "" "$note"
            ;;
        2)
            migration_save_plan "dc-replacement" "$DOMAIN" "$NETBIOS_DOMAIN" "Domain identity remains unchanged"
            ;;
        3|4|5)
            target="$(ask 'Target AD DNS domain (example newcorp.example)')"
            [[ "$target" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]] || { msg_warn "Invalid target DNS domain."; return 1; }
            netbios="$(ask 'Target NetBIOS domain' "$(netbios_from_domain "$target")")"
            case "$choice" in
                3) migration_save_plan "domain-migration" "${target,,}" "${netbios^^}" "Coexistence and client rejoin required" ;;
                4) migration_save_plan "new-forest" "${target,,}" "${netbios^^}" "Separate forest migration" ;;
                5) migration_save_plan "renamed-backup-lab" "${target,,}" "${netbios^^}" "Advanced/lab workflow only" ;;
            esac
            ;;
        H|h) MENU_MAIN_REQUESTED=1; return 0 ;;
        0) return 0 ;;
        *) msg_warn "Invalid assessment option."; return 1 ;;
    esac
    migration_show_plan
}

migration_inventory_export() {
    local dir="${RUN_ROOT}/migration-inventory"
    mkdir -p "$dir"
    chmod 700 "$dir"
    msg_info "Exporting source-domain migration inventory..."

    samba-tool domain info "$DC_IP" >"${dir}/domain-info.txt" 2>&1 || true
    samba-tool user list | sort >"${dir}/users.txt" 2>&1 || true
    samba-tool group list | sort >"${dir}/groups.txt" 2>&1 || true
    samba-tool computer list | sort >"${dir}/computers.txt" 2>&1 || true
    samba-tool ou list --full-dn >"${dir}/ous.txt" 2>&1 || true
    samba_gpo listall >"${dir}/gpos.txt" 2>&1 || true
    samba-tool domain trust list >"${dir}/trusts.txt" 2>&1 || true
    samba-tool fsmo show >"${dir}/fsmo.txt" 2>&1 || true
    {
        printf 'Source domain: %s\n' "$DOMAIN"
        printf 'Controller   : %s (%s)\n' "$DC_FQDN" "$DC_IP"
        printf 'Generated    : %s\n' "$(date -Is)"
        printf 'Users        : %s\n' "$(wc -l <"${dir}/users.txt" 2>/dev/null || printf 0)"
        printf 'Groups       : %s\n' "$(wc -l <"${dir}/groups.txt" 2>/dev/null || printf 0)"
        printf 'Computers    : %s\n' "$(wc -l <"${dir}/computers.txt" 2>/dev/null || printf 0)"
    } >"${dir}/SUMMARY.txt"
    result PASS "Migration inventory" "$dir" "users/groups/computers/OUs/GPO/FSMO/trusts"
}

migration_computer_readiness() {
    local computer host ip count=0 resolved=0 smb=0
    section "COMPUTER MIGRATION READINESS"
    printf '  %-30s %-16s %-10s %-10s\n' "COMPUTER" "ADDRESS" "DNS" "SMB/445"
    ui_rule
    while IFS= read -r computer; do
        [[ -n "$computer" ]] || continue
        host="${computer%$}"
        ip="$(getent ahostsv4 "${host}.${DOMAIN}" 2>/dev/null | awk 'NR==1{print $1}' || true)"
        count=$((count+1))
        if [[ -n "$ip" ]]; then
            resolved=$((resolved+1))
            if timeout 2 bash -c "exec 3<>/dev/tcp/${ip}/445" 2>/dev/null; then
                smb=$((smb+1))
                printf '  %-30s %-16s %-10s %-10s\n' "$host" "$ip" "OK" "OPEN"
            else
                printf '  %-30s %-16s %-10s %-10s\n' "$host" "$ip" "OK" "CLOSED"
            fi
        else
            printf '  %-30s %-16s %-10s %-10s\n' "$host" "-" "MISS" "-"
        fi
    done < <(samba-tool computer list 2>/dev/null | sort)
    printf '\n  Total=%d  DNS-resolved=%d  SMB-reachable=%d\n' "$count" "$resolved" "$smb"
    printf '  Reachability is a readiness signal only; it does not prove migration success.\n'
    ui_rule
}

migration_trust_menu() {
    while true; do
        (( MENU_MAIN_REQUESTED )) && return 0
        ui_menu_screen "DOMAIN TRUSTS" "Inspect and validate coexistence relationships before migration"
        ui_menu_item "1" "List trusts" "Show configured domain/forest trusts"
        ui_menu_item "2" "Show trust" "Display details for a target domain"
        ui_menu_item "3" "Validate trust" "Validate an existing trust relationship"
        ui_menu_item "4" "Trust create help" "Show runtime Samba options before production creation"
        ui_menu_exit
        ui_rule
        local choice target
        choice="$(ask 'Select operation' '1')"
        case "$choice" in
            1) samba-tool domain trust list; ui_pause ;;
            2)
                target="$(select_trusted_domain)" || { ui_pause; continue; }
                samba-tool domain trust show "$target"; ui_pause
                ;;
            3)
                target="$(select_trusted_domain)" || { ui_pause; continue; }
                samba-tool domain trust validate "$target"; ui_pause
                ;;
            4) samba-tool domain trust create --help; ui_pause ;;
            H|h) MENU_MAIN_REQUESTED=1; break ;;
            0) break ;;
            *) msg_warn "Invalid menu option."; ui_pause ;;
        esac
    done
}

migration_generate_windows_package() {
    migration_load_plan || { msg_warn "Run Migration assessment first."; return 1; }
    [[ -n "${TARGET_DOMAIN:-}" ]] || { msg_warn "Current plan has no target AD domain."; return 1; }
    local dir="${MIGRATION_DIR}/packages/windows-${TIMESTAMP}"
    mkdir -p "$dir"; chmod 700 "$dir"
    cat >"${dir}/Move-To-NewDomain.ps1" <<EOF
# Generated by ${SCRIPT_NAME} ${SCRIPT_VERSION}
[CmdletBinding()]
param(
    [string]\$TargetDomain = '${TARGET_DOMAIN}',
    [string]\$TargetOU = '',
    [string]\$TargetDC = ''
)
\$ErrorActionPreference = 'Stop'
\$current = Get-CimInstance Win32_ComputerSystem
Write-Host "Computer       : \$env:COMPUTERNAME"
Write-Host "Current domain : \$([string]\$current.Domain)"
Write-Host "Target domain  : \$TargetDomain"
\$oldCredential = Get-Credential -Message 'Credential allowed to unjoin the current domain'
\$newCredential = Get-Credential -Message 'Credential delegated to join computers to the target domain'
\$params = @{
    DomainName = \$TargetDomain
    UnjoinDomainCredential = \$oldCredential
    Credential = \$newCredential
    Restart = \$true
    Force = \$true
    PassThru = \$true
}
if (\$TargetOU) { \$params.OUPath = \$TargetOU }
if (\$TargetDC) { \$params.Server = \$TargetDC }
Add-Computer @params
EOF
    cat >"${dir}/README.txt" <<EOF
WINDOWS DOMAIN MIGRATION PACKAGE
Source: ${DOMAIN}
Target: ${TARGET_DOMAIN}

Run Move-To-NewDomain.ps1 from an elevated Windows PowerShell session after
target-domain DNS and SRV discovery work. Credentials are prompted at runtime;
no passwords are stored in this package.
EOF
    chmod 600 "${dir}/Move-To-NewDomain.ps1" "${dir}/README.txt"
    result PASS "Windows migration package" "$dir" "credential-free Add-Computer workflow"
}

migration_generate_linux_package() {
    migration_load_plan || { msg_warn "Run Migration assessment first."; return 1; }
    [[ -n "${TARGET_DOMAIN:-}" ]] || { msg_warn "Current plan has no target AD domain."; return 1; }
    local dir="${MIGRATION_DIR}/packages/linux-${TIMESTAMP}"
    mkdir -p "$dir"; chmod 700 "$dir"
    cat >"${dir}/migrate-linux-domain.sh" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
SOURCE_DOMAIN='${DOMAIN}'
TARGET_DOMAIN='${TARGET_DOMAIN}'
echo "Source: \$SOURCE_DOMAIN"
echo "Target: \$TARGET_DOMAIN"
command -v realm >/dev/null 2>&1 || {
    echo "realmd is not installed; review Samba/winbind-specific migration separately." >&2
    exit 2
}
realm list || true
read -r -p "Type APPLY to continue with leave/join: " answer
[[ "\$answer" == APPLY ]] || exit 0
read -r -p "Old-domain account: " OLD_USER
sudo realm leave "\$SOURCE_DOMAIN" -U "\$OLD_USER"
echo "Ensure target AD DNS/SRV records resolve before join."
read -r -p "Target-domain join account: " NEW_USER
sudo realm join "\$TARGET_DOMAIN" -U "\$NEW_USER"
realm list
EOF
    chmod 700 "${dir}/migrate-linux-domain.sh"
    result PASS "Linux migration package" "$dir" "realmd/SSSD helper"
}

migration_renamed_backup_guidance() {
    section "ADVANCED RENAMED-DOMAIN BACKUP"
    printf '  Samba provides domain backup rename followed by domain backup restore.\n'
    printf '  The assistant does not present it as a transparent in-place production rename.\n'
    printf '  Existing clients still require migration/rejoin to the resulting domain identity.\n\n'
    samba-tool domain backup rename --help || true
}

domain_migration_menu() {
    while true; do
        (( MENU_MAIN_REQUESTED )) && return 0
        ui_menu_screen "DOMAIN MIGRATION CENTER" "Assessment, coexistence evidence, client readiness and migration packages"
        ui_menu_item "1" "Migration assessment" "Classify branding, DC replacement, new domain/forest or backup-rename"
        ui_menu_item "2" "Show migration plan" "Display the saved source/target migration intent"
        ui_menu_item "3" "Export source inventory" "Users, groups, computers, OUs, GPOs, FSMO and trusts"
        ui_menu_item "4" "Computer readiness" "DNS and SMB reachability for current domain computers"
        ui_menu_item "5" "Domain trusts" "List/show/validate coexistence trusts"
        ui_menu_item "6" "Windows migration package" "Generate credential-free Add-Computer PowerShell" "$C_GREEN"
        ui_menu_item "7" "Linux migration package" "Generate realmd/SSSD leave/join helper" "$C_GREEN"
        ui_menu_item "8" "GPO backup set" "Back up current GPOs before migration"
        ui_menu_item "9" "Renamed backup guidance" "Show Samba backup-rename capability/limitations" "$C_YELLOW"
        ui_menu_item "10" "Domain backup" "Create recoverable Samba backup before migration work"
        ui_menu_exit
        ui_rule
        local choice guid
        choice="$(ask 'Select migration module' '1')"
        case "$choice" in
            1) migration_assessment; ui_pause ;;
            2) migration_show_plan; ui_pause ;;
            3) migration_inventory_export; ui_pause ;;
            4) migration_computer_readiness; ui_pause ;;
            5) migration_trust_menu ;;
            6) migration_generate_windows_package; ui_pause ;;
            7) migration_generate_linux_package; ui_pause ;;
            8)
                while IFS=$'\t' read -r guid _; do
                    [[ -n "$guid" ]] || continue
                    backup_gpo_safe "$guid" || true
                done < <(gpo_inventory_tsv)
                result PASS "Migration GPO backup set" "${RUN_ROOT}/gpo-backups" "best-effort"
                ui_pause
                ;;
            9) migration_renamed_backup_guidance; ui_pause ;;
            10) set_progress_plan 1; create_domain_backup; ui_pause ;;
            H|h) MENU_MAIN_REQUESTED=1; break ;;
            0) break ;;
            *) msg_warn "Invalid migration option."; ui_pause ;;
        esac
    done
}



# ---------------------------------------------------------------------------
# Domain decommission / local factory reset
# ---------------------------------------------------------------------------

confirm_exact_text() {
    local prompt="$1" expected="$2" answer=""
    printf '%b›%b %s\n' "$C_RED" "$C_RESET" "$prompt" >&2
    printf '  Type exactly: %b%s%b\n  > ' "$C_BOLD" "$expected" "$C_RESET" >&2
    read -r answer <"$INPUT_FD" || return 1
    [[ "$answer" == "$expected" ]]
}

earliest_assistant_backup_for_path() {
    local target="$1" rel="${target#/}" found=""
    [[ -d "${STATE_DIR}/runs" ]] || return 1

    found="$(
        find "${STATE_DIR}/runs" \
            -path "*/backup/rootfs/${rel}" \
            -print 2>/dev/null |
        LC_ALL=C sort |
        head -n1
    )"

    [[ -n "$found" ]] || return 1
    printf '%s' "$found"
}

restore_earliest_assistant_backup() {
    local target="$1" source=""
    source="$(earliest_assistant_backup_for_path "$target" 2>/dev/null || true)"
    [[ -n "$source" ]] || return 1

    rm -rf -- "$target"
    mkdir -p "$(dirname "$target")"
    cp -a --no-dereference -- "$source" "$target"
    change APPLIED "Restored earliest assistant snapshot: $target"
    return 0
}

remove_assistant_hosts_block() {
    local file="/etc/hosts" tmp="${RUN_ROOT}/hosts.reset"
    [[ -f "$file" ]] || return 0

    awk '
        BEGIN { inblock=0 }
        $0=="# BEGIN DEBIAN-AD-ASSISTANT" { inblock=1; next }
        $0=="# END DEBIAN-AD-ASSISTANT" { inblock=0; next }
        !inblock { print }
    ' "$file" >"$tmp"

    install -o root -g root -m 0644 "$tmp" "$file"
}

remove_assistant_chrony_include_block() {
    local config=""
    config="$(chrony_main_config 2>/dev/null || true)"
    [[ -n "$config" && -f "$config" ]] || return 0

    local tmp="${RUN_ROOT}/chrony.main.reset"
    awk '
        BEGIN { inblock=0 }
        $0=="# BEGIN DEBIAN-AD-ASSISTANT CHRONY INCLUDE" { inblock=1; next }
        $0=="# END DEBIAN-AD-ASSISTANT CHRONY INCLUDE" { inblock=0; next }
        !inblock { print }
    ' "$config" >"$tmp"

    install -o root -g root -m 0644 "$tmp" "$config"
}

local_domain_dc_count() {
    local db="/var/lib/samba/private/sam.ldb"
    local config_dn=""

    command_exists ldbsearch || return 1
    [[ -f "$db" ]] || return 1

    config_dn="$(
        ldbsearch -H "$db" -s base -b "" configurationNamingContext 2>/dev/null |
            awk -F': ' '/^configurationNamingContext:/{print $2;exit}'
    )"
    [[ -n "$config_dn" ]] || return 1

    ldbsearch -H "$db" -b "$config_dn" '(objectClass=nTDSDSA)' dn 2>/dev/null |
        grep -c '^dn:' || true
}

custom_samba_shares() {
    command_exists testparm || return 0
    [[ -f /etc/samba/smb.conf ]] || return 0

    testparm -s 2>/dev/null |
        awk '
            /^\[[^]]+\]/ {
                s=$0
                gsub(/^\[|\]$/, "", s)
                low=tolower(s)
                if (low!="global" && low!="sysvol" && low!="netlogon") print s
            }
        '
}

domain_reset_assessment() {
    section "DOMAIN RESET ASSESSMENT"

    detect_samba_role
    discover_network_topology
    discover_existing_identity

    local dc_count="" custom="" resolver=""
    dc_count="$(local_domain_dc_count 2>/dev/null || true)"
    custom="$(custom_samba_shares 2>/dev/null || true)"
    resolver="$(resolv_conf_description 2>/dev/null || true)"

    printf '  %-28s %s\n' "Detected role" "$SAMBA_ROLE"
    printf '  %-28s %s\n' "Domain" "${DOMAIN:-unknown}"
    printf '  %-28s %s\n' "Realm" "${REALM:-unknown}"
    printf '  %-28s %s\n' "DC" "${DC_FQDN:-unknown}"
    printf '  %-28s %s\n' "Local AD database" \
        "$( [[ -f /var/lib/samba/private/sam.ldb ]] && printf 'present' || printf 'missing' )"
    printf '  %-28s %s\n' "DC objects in directory" "${dc_count:-unknown}"
    printf '  %-28s %s\n' "Resolver" "${resolver:-unknown}"
    printf '  %-28s %s\n' "samba-ad-dc" "$(safe_systemctl_state samba-ad-dc)"
    printf '  %-28s %s\n' "Assistant state" \
        "$( [[ -d "$STATE_DIR" ]] && printf 'present' || printf 'absent' )"
    printf '  %-28s %s\n' "Recovery root" "$RESET_RECOVERY_ROOT"

    printf '\n'
    if [[ -n "$custom" ]]; then
        printf '%bAdditional Samba shares detected:%b\n' "$C_YELLOW" "$C_RESET"
        printf '%s\n' "$custom" | sed 's/^/  - /'
        printf '  Their data directories are NOT deleted, but smb.conf will be restored/removed.\n'
    else
        printf '%bAdditional Samba shares:%b none detected beyond SYSVOL/NETLOGON.\n' "$C_GREEN" "$C_RESET"
    fi

    printf '\n%bReset scope:%b\n' "$C_BOLD" "$C_RESET"
    printf '  - stop and disable samba-ad-dc\n'
    printf '  - archive then remove local Samba AD databases/SYSVOL state\n'
    printf '  - restore earliest assistant snapshots for hostname/hosts/resolver/Kerberos/Samba config when available\n'
    printf '  - remove assistant systemd boot guards, Chrony fragments, Fail2ban fragment and sysctl file\n'
    printf '  - unmask smbd/nmbd/winbind without enabling them\n'
    printf '  - optionally reset ALL UFW policy (never automatic)\n'
    printf '  - remove ad-* shortcuts and assistant state/log directories\n'
    printf '  - keep installed packages and network interface/IP configuration\n'
    printf '  - require a reboot before considering runtime kernel/network state clean\n'

    printf '\n%bImportant:%b this is not an OS factory reset and it does not undo external client domain membership.\n' \
        "$C_YELLOW" "$C_RESET"
}

create_domain_reset_recovery_bundle() {
    local recovery="$1"
    local -a config_paths=()
    local p

    mkdir -p "$recovery"/{domain-backup,raw,evidence}
    chmod 700 "$recovery" "$recovery/domain-backup" "$recovery/raw" "$recovery/evidence"

    {
        printf 'Generated: %s\n' "$(date -Is)"
        printf 'Assistant: %s %s\n' "$SCRIPT_NAME" "$SCRIPT_VERSION"
        printf 'Host: %s\n' "$(hostname -f 2>/dev/null || hostname)"
        printf 'Domain: %s\n' "${DOMAIN:-unknown}"
        printf 'Realm: %s\n' "${REALM:-unknown}"
        printf 'DC: %s\n' "${DC_FQDN:-unknown}"
        printf 'DC count: %s\n' "$(local_domain_dc_count 2>/dev/null || printf 'unknown')"
        printf '\n-- IP --\n'; ip -br addr 2>&1 || true
        printf '\n-- routes --\n'; ip route 2>&1 || true
        printf '\n-- resolver --\n'; ls -l /etc/resolv.conf 2>&1 || true; cat /etc/resolv.conf 2>&1 || true
        printf '\n-- services --\n'
        systemctl status samba-ad-dc chrony systemd-resolved --no-pager --full 2>&1 || true
        printf '\n-- UFW --\n'; ufw status verbose 2>&1 || true
        printf '\n-- Samba role/config --\n'; testparm -s 2>&1 || true
        printf '\n-- FSMO --\n'; samba-tool fsmo show 2>&1 || true
        printf '\n-- functional level --\n'; samba-tool domain level show 2>&1 || true
    } >"${recovery}/evidence/pre-reset.txt"
    chmod 600 "${recovery}/evidence/pre-reset.txt"

    for p in \
        /etc/hostname \
        /etc/hosts \
        /etc/resolv.conf \
        /etc/krb5.conf \
        /etc/samba \
        /etc/chrony \
        /etc/fail2ban/jail.d/90-debian-ad-assistant.conf \
        /etc/sysctl.d/99-debian-ad-hardening.conf \
        /etc/systemd/system/debian-ad-network-ready.service \
        /etc/systemd/system/debian-ad-samba-health.service \
        /etc/systemd/system/samba-ad-dc.service.d/20-debian-ad-network.conf \
        /usr/local/libexec/debian-ad-wait-network \
        /usr/local/libexec/debian-ad-samba-health \
        /usr/local/libexec/debian-ad-assistant
    do
        [[ -e "$p" || -L "$p" ]] && config_paths+=("${p#/}")
    done

    if ((${#config_paths[@]})); then
        tar --acls --xattrs --numeric-owner -cpf "${recovery}/raw/system-config.tar" \
            -C / "${config_paths[@]}"
        chmod 600 "${recovery}/raw/system-config.tar"
    fi

    if [[ -d "$STATE_DIR" || -d "$LOG_DIR" ]]; then
        local -a assistant_paths=()
        [[ -d "$STATE_DIR" ]] && assistant_paths+=("${STATE_DIR#/}")
        [[ -d "$LOG_DIR" ]] && assistant_paths+=("${LOG_DIR#/}")
        if ((${#assistant_paths[@]})); then
            tar --acls --xattrs --numeric-owner -cpf "${recovery}/raw/assistant-state.tar" \
                -C / "${assistant_paths[@]}"
            chmod 600 "${recovery}/raw/assistant-state.tar"
        fi
    fi
}

create_offline_reset_domain_backup() {
    local recovery="$1" output="${recovery}/evidence/domain-backup-offline.txt"

    [[ -f /var/lib/samba/private/sam.ldb ]] || {
        msg_warn "No sam.ldb found; Samba domain backup skipped."
        return 2
    }

    if ! samba-tool domain backup offline --help 2>&1 | grep -Fq -- '--targetdir'; then
        msg_warn "Installed Samba does not expose domain backup offline --targetdir."
        return 2
    fi

    if samba-tool domain backup offline --targetdir="${recovery}/domain-backup" >"$output" 2>&1; then
        chmod -R go-rwx "${recovery}/domain-backup"
        result PASS "Pre-reset domain backup" "${recovery}/domain-backup" "offline backup completed"
        return 0
    fi

    msg_warn "Samba offline domain backup failed. Evidence: $output"
    tail -n 40 "$output" >&2 || true
    return 1
}

archive_local_samba_state_for_reset() {
    local recovery="$1"
    local -a paths=()
    local p

    for p in /var/lib/samba /var/cache/samba /var/log/samba; do
        [[ -e "$p" ]] && paths+=("${p#/}")
    done

    if ((${#paths[@]})); then
        tar --acls --xattrs --numeric-owner -cpf "${recovery}/raw/samba-state.tar" \
            -C / "${paths[@]}"
        chmod 600 "${recovery}/raw/samba-state.tar"
    fi
}

restore_resolver_after_domain_reset() {
    if restore_earliest_assistant_backup /etc/resolv.conf; then
        if [[ -L /etc/resolv.conf ]]; then
            local target=""
            target="$(readlink /etc/resolv.conf 2>/dev/null || true)"
            if [[ "$target" == *"/run/systemd/resolve/"* ]]; then
                systemctl enable systemd-resolved >/dev/null 2>&1 || true
                systemctl start systemd-resolved >/dev/null 2>&1 || true
            fi
        fi
        return 0
    fi

    msg_warn "No pre-assistant /etc/resolv.conf snapshot was found."

    if systemctl list-unit-files systemd-resolved.service --no-legend 2>/dev/null |
        grep -q '^systemd-resolved\.service'; then
        systemctl enable systemd-resolved >/dev/null 2>&1 || true
        systemctl start systemd-resolved >/dev/null 2>&1 || true

        local stub="/run/systemd/resolve/stub-resolv.conf"
        [[ -e "$stub" ]] || stub="/run/systemd/resolve/resolv.conf"
        if [[ -e "$stub" ]]; then
            rm -f /etc/resolv.conf
            ln -s "$stub" /etc/resolv.conf
            change APPLIED "Restored systemd-resolved resolver symlink"
            return 0
        fi
    fi

    local fallback="${DNS_FORWARDER:-}"
    is_valid_ipv4 "$fallback" || fallback="$(ask 'Fallback DNS nameserver for clean host' '1.1.1.1')"
    is_valid_ipv4 "$fallback" || {
        msg_warn "Invalid fallback DNS; /etc/resolv.conf left for manual configuration."
        return 1
    }

    rm -f /etc/resolv.conf
    {
        printf '# Resolver restored after Samba AD/DC reset.\n'
        printf 'nameserver %s\n' "$fallback"
    } >/etc/resolv.conf
    chmod 0644 /etc/resolv.conf
    change APPLIED "Configured fallback resolver $fallback"
}

restore_core_host_identity_after_reset() {
    local restored_hostname=0
    local samba_krb5_matches=0

    if [[ -f /etc/krb5.conf && -f /var/lib/samba/private/krb5.conf ]] &&
       cmp -s /etc/krb5.conf /var/lib/samba/private/krb5.conf; then
        samba_krb5_matches=1
    fi

    if restore_earliest_assistant_backup /etc/hostname; then
        restored_hostname=1
        local new_hostname=""
        new_hostname="$(head -n1 /etc/hostname 2>/dev/null | tr -d '[:space:]' || true)"
        if [[ -n "$new_hostname" ]]; then
            hostnamectl set-hostname "$new_hostname" >/dev/null 2>&1 || true
        fi
    else
        msg_warn "No pre-assistant hostname snapshot found; current hostname will be retained."
    fi

    restore_earliest_assistant_backup /etc/hosts || remove_assistant_hosts_block

    if ! restore_earliest_assistant_backup /etc/krb5.conf; then
        if (( samba_krb5_matches == 1 )); then
            rm -f /etc/krb5.conf
            change APPLIED "Removed Samba-generated /etc/krb5.conf (no earlier snapshot available)"
        else
            msg_warn "No pre-assistant krb5.conf snapshot found; custom/current Kerberos config retained."
        fi
    fi

    if ! restore_earliest_assistant_backup /etc/samba/smb.conf; then
        rm -f /etc/samba/smb.conf
        change APPLIED "Removed AD/DC smb.conf (no earlier snapshot available)"
    fi

    restore_resolver_after_domain_reset || true

    (( restored_hostname == 1 )) &&
        result INFO "Hostname restore" "$(hostname -s 2>/dev/null || true)" "earliest assistant snapshot"
}

remove_assistant_managed_host_files() {
    # Optional IDS integration: remove only assistant-managed overlays/timers.
    systemctl disable --now debian-ad-ids-daily.timer >/dev/null 2>&1 || true
    rm -f "$IDS_DAILY_TIMER" "$IDS_DAILY_SERVICE"
    systemctl disable --now suricata.service >/dev/null 2>&1 || true
    rm -f "$IDS_DROPIN" "$IDS_CONFIG"
    rmdir "$(dirname "$IDS_DROPIN")" >/dev/null 2>&1 || true

    local p source=""

    # Boot/network/listener guards.
    systemctl disable --now debian-ad-samba-health.service >/dev/null 2>&1 || true

    for p in \
        /usr/local/libexec/debian-ad-wait-network \
        /usr/local/libexec/debian-ad-samba-health \
        /etc/systemd/system/debian-ad-network-ready.service \
        /etc/systemd/system/debian-ad-samba-health.service \
        /etc/systemd/system/samba-ad-dc.service.d/20-debian-ad-network.conf
    do
        if ! restore_earliest_assistant_backup "$p"; then
            rm -f -- "$p"
        fi
    done
    rmdir /etc/systemd/system/samba-ad-dc.service.d >/dev/null 2>&1 || true

    # Chrony fragments.
    for p in \
        /etc/chrony/conf.d/90-debian-ad.conf \
        /etc/chrony/conf.d/91-samba-ad-signed-time.conf
    do
        if ! restore_earliest_assistant_backup "$p"; then
            rm -f -- "$p"
        fi
    done
    remove_assistant_chrony_include_block || true

    # Fail2ban fragment.
    p="/etc/fail2ban/jail.d/90-debian-ad-assistant.conf"
    if ! restore_earliest_assistant_backup "$p"; then
        rm -f -- "$p"
    fi

    # sysctl fragment.
    p="/etc/sysctl.d/99-debian-ad-hardening.conf"
    if ! restore_earliest_assistant_backup "$p"; then
        rm -f -- "$p"
    fi

    systemctl daemon-reload

    if command_exists chronyd && chrony_validate_config "post-reset" yes; then
        local cu=""
        cu="$(chrony_service_unit 2>/dev/null || true)"
        [[ -n "$cu" ]] && systemctl restart "$cu" >/dev/null 2>&1 || true
    fi

    if systemctl list-unit-files fail2ban.service --no-legend 2>/dev/null |
        grep -q '^fail2ban\.service'; then
        systemctl restart fail2ban >/dev/null 2>&1 || true
    fi
}

optional_reset_ufw_after_domain_reset() {
    command_exists ufw || return 0
    ufw status 2>/dev/null | grep -q '^Status: active' || return 0

    printf '\n'
    msg_warn "UFW rules are not tagged by older assistant versions, so individual AD rules cannot be proven to be assistant-owned."
    printf 'A full UFW reset would remove ALL current firewall rules, including custom rules.\n'

    if (( REMOTE_SESSION == 1 )); then
        msg_warn "Remote SSH session detected. Automatic UFW reset is disabled to protect management access."
        return 0
    fi

    if confirm "Reset ALL UFW rules to UFW defaults and disable UFW?" N; then
        if confirm_exact_text "This removes every UFW rule on the host." "RESET UFW"; then
            ufw --force reset >/dev/null
            change APPLIED "Reset all UFW policy by explicit operator authorization"
        else
            msg_warn "UFW reset cancelled."
        fi
    fi
}

remove_assistant_cli_and_state() {
    local target="/usr/local/libexec/debian-ad-assistant"
    local bindir="/usr/local/sbin"
    local name title description path resolved

    while IFS='|' read -r name title description; do
        [[ -n "$name" ]] || continue
        path="${bindir}/${name}"
        if [[ -L "$path" ]]; then
            resolved="$(readlink -f "$path" 2>/dev/null || true)"
            [[ "$resolved" == "$target" ]] && rm -f "$path"
        fi
    done < <(cli_command_catalog)

    rm -f "$target"

    # Preserve the active log in the recovery bundle before removing runtime state.
    if [[ -n "$RESET_RECOVERY_DIR" ]]; then
        cp -a "$LOG_FILE" "${RESET_RECOVERY_DIR}/evidence/assistant-reset.log" 2>/dev/null || true
    fi

    rm -rf "$STATE_DIR" "$LOG_DIR"
}

wipe_local_samba_ad_state() {
    systemctl stop samba-ad-dc >/dev/null 2>&1 || true
    systemctl disable samba-ad-dc >/dev/null 2>&1 || true

    rm -rf /var/lib/samba /var/cache/samba /run/samba
    mkdir -p /var/lib/samba /var/cache/samba /run/samba
    chmod 0755 /var/lib/samba /var/cache/samba /run/samba

    systemctl unmask samba-ad-dc smbd nmbd winbind >/dev/null 2>&1 || true
    systemctl disable smbd nmbd winbind >/dev/null 2>&1 || true

    result PASS "Local Samba AD state" "removed" "no sam.ldb / no SYSVOL"
}

domain_factory_reset() {
    section "FACTORY RESET LOCAL SAMBA AD/DC"

    detect_samba_role
    discover_network_topology
    discover_existing_identity

    [[ "$SAMBA_ROLE" == "ad-dc" || "$SAMBA_ROLE" == "ad-dc-config" ]] || {
        msg_warn "No Samba AD/DC configuration is currently detected."
        return 1
    }

    local dc_count="" custom="" domain_label="${DOMAIN:-unknown}"
    dc_count="$(local_domain_dc_count 2>/dev/null || true)"
    custom="$(custom_samba_shares 2>/dev/null || true)"

    if [[ "$dc_count" =~ ^[0-9]+$ ]] && (( dc_count > 1 )); then
        msg_error "Factory reset refused: $dc_count Domain Controller objects are present in the directory."
        printf 'This DC must be gracefully demoted from a surviving domain before local state is wiped.\n'
        printf 'Use: samba-tool domain demote --help\n'
        printf 'Samba documents domain demotion as the required path for removing a domain server.\n'
        return 1
    fi

    if [[ ! "$dc_count" =~ ^[0-9]+$ || "$dc_count" -eq 0 ]]; then
        msg_warn "DC topology could not be proven from the local directory."
        confirm_exact_text \
            "Proceed only if you accept possible stale metadata in another surviving DC." \
            "FORCE RESET UNKNOWN TOPOLOGY" || {
                msg_warn "Reset cancelled."
                return 1
            }
    fi

    printf '\n%bTHIS OPERATION DESTROYS THE LOCAL DOMAIN DATABASE.%b\n' "$C_RED" "$C_RESET"
    printf 'If this is the only DC, the domain %b%s%b will cease to exist.\n' \
        "$C_BOLD" "$domain_label" "$C_RESET"
    printf 'Domain-joined clients will NOT automatically become workgroup machines.\n'
    printf 'Installed packages and the host IP/Netplan configuration are intentionally retained.\n'

    if [[ -n "$custom" ]]; then
        printf '\n%bAdditional Samba shares are configured:%b\n' "$C_YELLOW" "$C_RESET"
        printf '%s\n' "$custom" | sed 's/^/  - /'
        printf 'Share data paths are not deleted, but Samba configuration/state will be reset.\n'
    fi

    confirm_exact_text \
        "Confirm the AD DNS domain that will be destroyed." \
        "$domain_label" || {
            msg_warn "Domain confirmation mismatch. Reset cancelled."
            return 1
        }

    confirm_exact_text \
        "Final authorization. This cannot be undone without the recovery bundle." \
        "ERASE DOMAIN ${domain_label}" || {
            msg_warn "Reset cancelled."
            return 1
        }

    RESET_RECOVERY_DIR="${RESET_RECOVERY_ROOT}/domain-reset-${TIMESTAMP}"
    mkdir -p "$RESET_RECOVERY_ROOT"
    chmod 700 "$RESET_RECOVERY_ROOT"

    create_domain_reset_recovery_bundle "$RESET_RECOVERY_DIR"

    # Stop Samba before the offline domain backup and raw state archive.
    systemctl stop samba-ad-dc >/dev/null 2>&1 || true

    local backup_rc=0
    create_offline_reset_domain_backup "$RESET_RECOVERY_DIR" || backup_rc=$?

    if (( backup_rc == 1 )); then
        if ! confirm_exact_text \
            "Official Samba offline backup failed. A raw state archive will still be created." \
            "RESET WITHOUT SAMBA BACKUP"; then
            systemctl start samba-ad-dc >/dev/null 2>&1 || true
            msg_warn "Reset aborted; Samba start was requested again."
            return 1
        fi
    fi

    archive_local_samba_state_for_reset "$RESET_RECOVERY_DIR"

    {
        printf 'Reset authorized: %s\n' "$(date -Is)"
        printf 'Domain: %s\n' "$domain_label"
        printf 'Original DC count: %s\n' "${dc_count:-unknown}"
        printf 'Official offline backup status: %s\n' "$backup_rc"
        printf 'Packages retained: yes\n'
        printf 'Network/IP configuration retained: yes\n'
        printf 'Reboot required: yes\n'
    } >"${RESET_RECOVERY_DIR}/RESET-MANIFEST.txt"
    chmod 600 "${RESET_RECOVERY_DIR}/RESET-MANIFEST.txt"

    # Restore host-level files while Samba's generated krb5.conf is still present
    # so we can identify whether /etc/krb5.conf was an assistant-installed copy.
    restore_core_host_identity_after_reset
    remove_assistant_managed_host_files

    wipe_local_samba_ad_state
    optional_reset_ufw_after_domain_reset

    systemctl daemon-reload

    # Validation before deleting assistant state.
    detect_samba_role
    if [[ "$SAMBA_ROLE" == "ad-dc" || -f /var/lib/samba/private/sam.ldb ]]; then
        msg_error "Reset validation failed: AD/DC state is still detected."
        printf 'Recovery bundle: %s\n' "$RESET_RECOVERY_DIR"
        return 1
    fi

    if systemctl is-active --quiet samba-ad-dc; then
        msg_error "Reset validation failed: samba-ad-dc is still active."
        return 1
    fi

    result PASS "Domain reset" "$domain_label removed from local host" "AD/DC state absent"
    result INFO "Recovery bundle" "$RESET_RECOVERY_DIR" "retain until reset/rebuild is verified"
    result WARN "Reboot required" "kernel/sysctl/runtime caches may retain previous values until reboot" "reboot before reuse"

    # Last operation: remove the assistant's installed control plane and state.
    # The currently running shell already has the script parsed in memory.
    remove_assistant_cli_and_state

    RESET_COMPLETED=1

    printf '\n'
    ui_rule
    printf '%b%b  DOMAIN RESET COMPLETE%b\n' "$C_BOLD" "$C_GREEN" "$C_RESET"
    printf '  Domain removed locally : %s\n' "$domain_label"
    printf '  Recovery bundle        : %s\n' "$RESET_RECOVERY_DIR"
    printf '  Samba AD service       : stopped / disabled\n'
    printf '  Assistant CLI/state    : removed\n'
    printf '  Packages               : retained\n'
    printf '  Network/IP             : retained\n'
    printf '  Next action            : reboot\n'
    printf '\n'
    printf 'After reboot, this host can be configured as a normal server or bootstrapped into a new domain.\n'
    printf 'Keep the recovery bundle until you have verified the new state.\n'
    ui_rule
}

domain_reset_menu() {
    while true; do
        (( RESET_COMPLETED )) && return 0
        (( MENU_MAIN_REQUESTED )) && return 0

        ui_menu_screen "DOMAIN DECOMMISSION / RESET" \
            "Destructive local AD/DC removal with external recovery bundle and host cleanup"
        ui_menu_item "1" "Reset assessment" \
            "Show topology, scope, custom shares and exactly what would be changed"
        ui_menu_item "2" "Factory reset local AD/DC" \
            "Destroy local domain state and remove assistant-managed AD configuration" "$C_RED"
        ui_menu_item "3" "Samba demotion guidance" \
            "Required path when other Domain Controllers survive"
        ui_menu_exit
        ui_rule

        local choice
        choice="$(ask 'Select reset operation' '1')"
        case "$choice" in
            1) domain_reset_assessment; ui_pause ;;
            2)
                if domain_factory_reset; then
                    (( RESET_COMPLETED )) && return 0
                fi
                ui_pause
                ;;
            3)
                section "GRACEFUL DEMOTION GUIDANCE"
                printf 'For a multi-DC domain, do not wipe local Samba state first.\n'
                printf 'Samba provides:\n\n'
                printf '  samba-tool domain demote --help\n\n'
                printf 'After successful demotion and replication/metadata validation on surviving DCs,\n'
                printf 'this reset center can be used for local host cleanup if necessary.\n'
                ui_pause
                ;;
            H|h) MENU_MAIN_REQUESTED=1; return 0 ;;
            0) return 0 ;;
            *) msg_warn "Invalid reset operation."; ui_pause ;;
        esac
    done
}


# ---------------------------------------------------------------------------
# Optional passive network IDS / Suricata integration
# ---------------------------------------------------------------------------

ids_prepare_state() {
    mkdir -p "$IDS_STATE_DIR" "$IDS_REPORT_DIR"
    chmod 700 "$IDS_STATE_DIR" "$IDS_REPORT_DIR"
}

ids_suricata_binary() {
    local p=""
    p="$(command -v suricata 2>/dev/null || true)"
    [[ -n "$p" && -x "$p" ]] && { printf '%s' "$p"; return 0; }
    for p in /usr/bin/suricata /usr/sbin/suricata /usr/local/bin/suricata; do
        [[ -x "$p" ]] && { printf '%s' "$p"; return 0; }
    done
    return 1
}

ids_suricata_update_binary() {
    local p=""
    p="$(command -v suricata-update 2>/dev/null || true)"
    [[ -n "$p" && -x "$p" ]] && { printf '%s' "$p"; return 0; }
    for p in /usr/bin/suricata-update /usr/local/bin/suricata-update; do
        [[ -x "$p" ]] && { printf '%s' "$p"; return 0; }
    done
    return 1
}

ids_suricata_config() {
    local p
    for p in /etc/suricata/suricata.yaml /usr/local/etc/suricata/suricata.yaml; do
        [[ -f "$p" ]] && { printf '%s' "$p"; return 0; }
    done
    return 1
}

ids_record_prestate() {
    ids_prepare_state
    local f="${IDS_STATE_DIR}/prestate.env"
    [[ -f "$f" ]] && return 0

    local pkg_suricata="no" pkg_update="no" enabled="unknown" active="unknown"
    package_installed suricata && pkg_suricata="yes"
    package_installed suricata-update && pkg_update="yes"
    enabled="$(safe_systemctl_enabled suricata.service)"
    active="$(safe_systemctl_state suricata.service)"

    cat >"$f" <<EOF
SURICATA_PREEXISTED=${pkg_suricata}
SURICATA_UPDATE_PREEXISTED=${pkg_update}
SURICATA_SERVICE_ENABLED_BEFORE=${enabled}
SURICATA_SERVICE_ACTIVE_BEFORE=${active}
EOF
    chmod 600 "$f"
}

ids_install_optional() {
    section "SURICATA OPTIONAL INSTALLATION"
    ids_record_prestate

    local -a pkgs=()
    package_installed suricata || pkgs+=(suricata)

    if package_available suricata-update; then
        package_installed suricata-update || pkgs+=(suricata-update)
    fi

    if ((${#pkgs[@]})); then
        printf 'The IDS module needs these optional distribution packages:\n'
        printf '  - %s\n' "${pkgs[@]}"
        confirm "Install optional passive IDS packages now?" Y || return 1
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}"
    fi

    local bin=""
    bin="$(ids_suricata_binary 2>/dev/null || true)"
    [[ -n "$bin" ]] || {
        fail_msg "Suricata package installation completed but the suricata binary is unavailable."
        return 1
    }

    result PASS "Suricata runtime" "$($bin -V 2>&1 | head -n1)" "installed"
    if ids_suricata_update_binary >/dev/null 2>&1; then
        result PASS "Rules updater" "$(ids_suricata_update_binary)" "available"
    else
        result WARN "Rules updater" "suricata-update unavailable" "recommended"
    fi
}

ids_list_interfaces() {
    ip -4 -o addr show scope global 2>/dev/null |
        awk '{print $2 "|" $4}' |
        sort -u
}

ids_select_interface() {
    local -a rows=()
    mapfile -t rows < <(ids_list_interfaces)
    ((${#rows[@]})) || {
        msg_warn "No interface with a global IPv4 address was found."
        return 1
    }

    printf '\n' >&2
    ui_rule >&2
    printf '%b%b  IDS CAPTURE INTERFACES%b\n' "$C_BOLD" "$C_WHITE" "$C_RESET" >&2
    ui_rule >&2

    local i iface cidr default_idx=0
    for i in "${!rows[@]}"; do
        IFS='|' read -r iface cidr <<<"${rows[$i]}"
        [[ "$iface" == "${AD_IFACE:-}" ]] && default_idx=$((i+1))
        printf '  %b[%2d]%b  %-18s %s%s\n' \
            "$C_DIM" "$((i+1))" "$C_RESET" "$iface" "$cidr" \
            "$( [[ "$iface" == "${AD_IFACE:-}" ]] && printf '  [AD interface]' || true )" >&2
    done
    printf '  %b[M ]%b  Enter interface manually\n' "$C_CYAN" "$C_RESET" >&2
    printf '  %b[0 ]%b  Cancel\n' "$C_RED" "$C_RESET" >&2
    ui_rule >&2

    local default_choice="1" choice manual
    (( default_idx > 0 )) && default_choice="$default_idx"
    choice="$(ask 'Select passive capture interface' "$default_choice")"

    case "$choice" in
        0) return 1 ;;
        M|m)
            manual="$(ask 'Interface name')"
            [[ "$manual" =~ ^[A-Za-z0-9_.:@-]+$ ]] || {
                msg_warn "Invalid interface name."
                return 1
            }
            ip link show dev "$manual" >/dev/null 2>&1 || {
                msg_warn "Interface '$manual' does not exist."
                return 1
            }
            printf '%s' "$manual"
            return 0
            ;;
    esac

    [[ "$choice" =~ ^[0-9]+$ ]] || return 1
    (( choice >= 1 && choice <= ${#rows[@]} )) || return 1
    IFS='|' read -r iface cidr <<<"${rows[$((choice-1))]}"
    printf '%s' "$iface"
}

ids_default_home_net() {
    local value=""
    if [[ -n "${AD_CLIENT_CIDR:-}" ]] && is_valid_cidr "$AD_CLIENT_CIDR"; then
        printf '%s' "$AD_CLIENT_CIDR"
        return 0
    fi

    if [[ -n "${AD_CIDR:-}" ]]; then
        value="$(cidr_from_interface "$AD_CIDR")"
        [[ -n "$value" ]] && is_valid_cidr "$value" && { printf '%s' "$value"; return 0; }
    fi

    if [[ -n "${AD_IFACE:-}" ]]; then
        value="$(ip -4 -o addr show dev "$AD_IFACE" scope global 2>/dev/null | awk 'NR==1{print $4}')"
        [[ -n "$value" ]] && value="$(cidr_from_interface "$value")"
        [[ -n "$value" ]] && is_valid_cidr "$value" && { printf '%s' "$value"; return 0; }
    fi

    return 1
}

ids_write_managed_config() {
    local iface="$1" home_net="$2"
    mkdir -p /etc/suricata
    backup_file "$IDS_CONFIG"

    cat >"$IDS_CONFIG" <<EOF
%YAML 1.1
---
# Managed by ${SCRIPT_NAME} ${SCRIPT_VERSION}
# Passive IDS overlay for the AD-facing interface.
# This fragment is loaded after the distribution suricata.yaml.

vars:
  address-groups:
    HOME_NET: "[${home_net}]"

default-rule-path: /var/lib/suricata/rules
rule-files:
  - suricata.rules

af-packet:
  - interface: ${iface}
    threads: auto
    cluster-id: 99
    cluster-type: cluster_flow
    defrag: yes

outputs:
  - eve-log:
      enabled: yes
      filetype: regular
      filename: eve.json
      community-id: true
      types:
        - alert
        - stats:
            totals: yes
            threads: no
        - dns
        - krb5
        - smb
        - tls
        - ssh
EOF
    chmod 0644 "$IDS_CONFIG"
}

ids_vendor_execstart() {
    local fragment=""
    fragment="$(systemctl show -p FragmentPath --value suricata.service 2>/dev/null || true)"
    [[ -n "$fragment" && -f "$fragment" ]] || return 1

    awk '
        /^[[:space:]]*ExecStart=/ {
            sub(/^[[:space:]]*ExecStart=/, "")
            print
            exit
        }
    ' "$fragment"
}

ids_install_systemd_dropin() {
    local vendor_exec="" config=""
    vendor_exec="$(ids_vendor_execstart 2>/dev/null || true)"
    config="$(ids_suricata_config 2>/dev/null || true)"

    [[ -n "$vendor_exec" ]] || {
        msg_warn "Unable to read vendor Suricata ExecStart; refusing to invent a service command."
        return 1
    }
    [[ -n "$config" ]] || {
        msg_warn "Unable to locate suricata.yaml."
        return 1
    }

    if grep -Eq '(^|[[:space:]])(-q|--nfq|--nfqueue)([=[:space:]]|$)|--af-xdp' <<<"$vendor_exec"; then
        msg_warn "The vendor/custom service appears configured for an active/alternate capture mode."
        printf '  ExecStart: %s\n' "$vendor_exec"
        printf 'The assistant will not overwrite an NFQUEUE/AF_XDP deployment with passive IDS settings.\n'
        return 1
    fi

    if ! grep -q -- '--af-packet' <<<"$vendor_exec"; then
        vendor_exec+=" --af-packet"
    fi

    # The overlay is appended on the command line, so it is processed after the
    # distribution YAML without rewriting vendor configuration.
    vendor_exec+=" --include ${IDS_CONFIG}"

    mkdir -p "$(dirname "$IDS_DROPIN")"
    backup_file "$IDS_DROPIN"
    cat >"$IDS_DROPIN" <<EOF
[Service]
ExecStart=
ExecStart=${vendor_exec}
EOF
    chmod 0644 "$IDS_DROPIN"
    systemctl daemon-reload
}

ids_validate_config() {
    local label="${1:-current}" bin="" config="" evidence=""
    bin="$(ids_suricata_binary 2>/dev/null || true)"
    config="$(ids_suricata_config 2>/dev/null || true)"
    evidence="${RUN_ROOT}/suricata-test-${label}.txt"

    [[ -n "$bin" && -n "$config" && -f "$IDS_CONFIG" ]] || return 1

    if "$bin" -T -c "$config" --include "$IDS_CONFIG" >"$evidence" 2>&1; then
        result PASS "Suricata config test" "$label" "valid"
        return 0
    fi

    result FAIL "Suricata config test" "$label; evidence=$evidence" "valid"
    tail -n 60 "$evidence" >&2 || true
    return 1
}

ids_rules_file() {
    local p
    for p in \
        /var/lib/suricata/rules/suricata.rules \
        /etc/suricata/rules/suricata.rules
    do
        [[ -f "$p" ]] && { printf '%s' "$p"; return 0; }
    done
    return 1
}

ids_update_rules() {
    section "SURICATA RULE UPDATE"
    local updater="" rules_root="/var/lib/suricata/rules"
    local backup="${RUN_ROOT}/suricata-rules-before.tar"

    updater="$(ids_suricata_update_binary 2>/dev/null || true)"
    [[ -n "$updater" ]] || {
        msg_warn "suricata-update is unavailable."
        return 1
    }

    if [[ -d "$rules_root" ]]; then
        tar -cpf "$backup" -C "$(dirname "$rules_root")" "$(basename "$rules_root")"
    fi

    printf 'Updating Suricata rules using: %s\n' "$updater"
    if ! "$updater" >"${RUN_ROOT}/suricata-update.txt" 2>&1; then
        msg_warn "suricata-update failed. Evidence: ${RUN_ROOT}/suricata-update.txt"
        tail -n 60 "${RUN_ROOT}/suricata-update.txt" >&2 || true
        return 1
    fi

    if ! ids_validate_config "after-rule-update"; then
        if [[ -f "$backup" ]]; then
            rm -rf "$rules_root"
            tar -xpf "$backup" -C "$(dirname "$rules_root")"
            msg_warn "Rule update was rolled back after configuration validation failure."
        fi
        return 1
    fi

    if systemctl is-active --quiet suricata.service; then
        if ! systemctl reload suricata.service; then
            msg_warn "Rule reload failed; attempting service restart."
            systemctl restart suricata.service || return 1
        fi
    fi

    local rule_file=""
    rule_file="$(ids_rules_file 2>/dev/null || true)"
    result PASS "Suricata rules" "${rule_file:-updated}" "updated and validated"
}

ids_configure_passive() {
    section "CONFIGURE PASSIVE SURICATA IDS"

    ids_install_optional || return 1
    ids_prepare_state

    local iface="" home_default="" home_net="" config=""
    iface="$(ids_select_interface)" || return 1
    home_default="$(ids_default_home_net 2>/dev/null || true)"
    [[ -n "$home_default" ]] || home_default="192.168.1.0/24"
    home_net="$(ask 'HOME_NET / monitored AD network (CIDR)' "$home_default")"
    is_valid_cidr "$home_net" || {
        msg_warn "Invalid HOME_NET CIDR: $home_net"
        return 1
    }

    printf '\n%bPassive IDS plan%b\n' "$C_CYAN" "$C_RESET"
    printf '  Capture interface : %s\n' "$iface"
    printf '  HOME_NET          : %s\n' "$home_net"
    printf '  Capture mode      : AF_PACKET / passive\n'
    printf '  EVE telemetry     : alert, stats, DNS, KRB5, SMB, TLS, SSH\n'
    printf '  Inline blocking   : disabled\n'
    printf '  Managed overlay   : %s\n' "$IDS_CONFIG"

    confirm "Apply this passive IDS configuration?" Y || return 0

    ids_write_managed_config "$iface" "$home_net"
    ids_install_systemd_dropin || return 1

    # A first ruleset is needed before the service can be considered useful.
    if ids_suricata_update_binary >/dev/null 2>&1; then
        ids_update_rules || {
            msg_warn "Initial rule update failed; Suricata configuration remains staged for inspection."
            return 1
        }
    else
        msg_warn "No rules updater is available; service start is deferred."
        return 1
    fi

    ids_validate_config "pre-start" || return 1

    systemctl enable suricata.service >/dev/null 2>&1 || true
    if ! systemctl restart suricata.service; then
        msg_error "Suricata service failed to start."
        systemctl status suricata.service --no-pager --full >&2 || true
        journalctl -u suricata.service -b --no-pager -n 80 >&2 || true
        return 1
    fi

    sleep 2
    if systemctl is-active --quiet suricata.service; then
        result PASS "Suricata service" "active on $iface" "passive IDS"
        change APPLIED "Configured passive Suricata IDS interface=$iface HOME_NET=$home_net"
    else
        result FAIL "Suricata service" "not active" "active"
        return 1
    fi
}

ids_eve_parser() {
    local hours="${1:-24}" view="${2:-summary}"
    IDS_HOURS="$hours" IDS_VIEW="$view" IDS_EVE_GLOB="$IDS_EVE_GLOB" python3 - <<'PY'
import os, sys, glob, json, gzip
from collections import Counter, deque
from datetime import datetime, timezone, timedelta

hours = float(os.environ.get("IDS_HOURS", "24"))
view = os.environ.get("IDS_VIEW", "summary")
pattern = os.environ.get("IDS_EVE_GLOB", "/var/log/suricata/eve.json*")
cutoff = datetime.now(timezone.utc) - timedelta(hours=hours)

def open_any(path):
    return gzip.open(path, "rt", encoding="utf-8", errors="replace") if path.endswith(".gz") else open(path, "rt", encoding="utf-8", errors="replace")

def parse_ts(value):
    if not value:
        return None
    try:
        v = str(value)
        if v.endswith("Z"):
            v = v[:-1] + "+00:00"
        dt = datetime.fromisoformat(v)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc)
    except Exception:
        return None

def inc(counter, key):
    if key not in (None, ""):
        counter[str(key)] += 1

files = [p for p in glob.glob(pattern) if os.path.isfile(p)]
files.sort(key=lambda p: os.path.getmtime(p))

events = Counter()
alert_sigs = Counter()
alert_src = Counter()
alert_sev = Counter()
dns_queries = 0
dns_nxdomain = 0
krb_encryption = Counter()
krb_weak = []
smb_dialects = Counter()
smb_ntlm = Counter()
smb_ntlm_hosts = Counter()
recent_alerts = deque(maxlen=80)
latest_stats = None
parsed = 0
bad = 0
latest_ts = None

for path in files:
    try:
        fh = open_any(path)
    except OSError:
        continue
    with fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                ev = json.loads(line)
            except Exception:
                bad += 1
                continue
            ts = parse_ts(ev.get("timestamp"))
            if ts and ts < cutoff:
                continue
            if ts and (latest_ts is None or ts > latest_ts):
                latest_ts = ts
            parsed += 1
            et = ev.get("event_type", "unknown")
            events[et] += 1

            if et == "alert":
                a = ev.get("alert") or {}
                inc(alert_sigs, a.get("signature"))
                inc(alert_src, ev.get("src_ip"))
                inc(alert_sev, a.get("severity"))
                recent_alerts.append((ev.get("timestamp",""), ev.get("src_ip","-"), ev.get("dest_ip","-"),
                                      a.get("severity","-"), a.get("signature","-")))

            if et == "dns":
                dns_queries += 1
                d = ev.get("dns") or {}
                rcode = str(d.get("rcode_name") or d.get("rcode") or "").upper()
                if "NXDOMAIN" in rcode or rcode == "3":
                    dns_nxdomain += 1

            if et == "krb5":
                k = ev.get("krb5") or {}
                enc = k.get("ticket_encryption") or k.get("encryption")
                inc(krb_encryption, enc)
                if k.get("weak_encryption") is True or k.get("ticket_weak_encryption") is True:
                    krb_weak.append((ev.get("timestamp",""), ev.get("src_ip","-"),
                                     k.get("cname","-"), k.get("sname","-"), enc or "-"))

            if et == "smb":
                s = ev.get("smb") or {}
                inc(smb_dialects, s.get("dialect"))
                nt = s.get("ntlmssp") or {}
                if nt:
                    user = nt.get("user") or "<unknown>"
                    host = nt.get("host") or ev.get("src_ip") or "<unknown>"
                    inc(smb_ntlm, user)
                    inc(smb_ntlm_hosts, host)

            if et == "stats":
                latest_stats = ev.get("stats") or {}

def print_counter(title, counter, limit=10):
    print(title)
    if not counter:
        print("  none observed")
        return
    for key, count in counter.most_common(limit):
        print(f"  {count:8d}  {key}")

def nested(d, *keys):
    cur = d
    for k in keys:
        if not isinstance(cur, dict):
            return None
        cur = cur.get(k)
    return cur

packets = nested(latest_stats or {}, "capture", "kernel_packets") or 0
drops = nested(latest_stats or {}, "capture", "kernel_drops") or 0
try:
    drop_pct = (float(drops) * 100.0 / float(packets)) if float(packets) else 0.0
except Exception:
    drop_pct = 0.0

if view == "alerts":
    print(f"RECENT SURICATA ALERTS — LAST {hours:g}H")
    print("=" * 88)
    if not recent_alerts:
        print("No alerts observed in the selected window.")
    else:
        for ts, src, dst, sev, sig in list(recent_alerts)[-50:]:
            print(f"{ts:30.30s} sev={str(sev):<3} {src:15.15s} -> {dst:15.15s}  {sig}")
    sys.exit(0)

if view == "ad":
    print(f"AD PROTOCOL INTELLIGENCE — LAST {hours:g}H")
    print("=" * 72)
    print_counter("Kerberos encryption:", krb_encryption, 20)
    print(f"\nWeak Kerberos observations: {len(krb_weak)}")
    for row in krb_weak[-20:]:
        print("  " + " | ".join(map(str, row)))
    print()
    print_counter("SMB dialects:", smb_dialects, 20)
    print()
    print_counter("SMB NTLMSSP users:", smb_ntlm, 15)
    print()
    print_counter("SMB NTLMSSP source hosts:", smb_ntlm_hosts, 15)
    smb1 = sum(v for k,v in smb_dialects.items() if "NT LM 0.12" in k.upper() or k.upper().startswith("SMB1"))
    print(f"\nSMB1 observations: {smb1}")
    sys.exit(0)

print(f"SECURITY OPERATIONS SUMMARY — LAST {hours:g}H")
print("=" * 72)
print(f"Parsed EVE events             {parsed}")
print(f"Malformed JSON lines          {bad}")
print(f"Latest event                  {latest_ts.isoformat() if latest_ts else 'none'}")
print(f"Kernel packets (latest stats) {packets}")
print(f"Kernel drops (latest stats)   {drops}")
print(f"Kernel drop rate              {drop_pct:.3f}%")
print()
print_counter("Event types:", events, 20)
print()
print_counter("Alert severity values:", alert_sev, 10)
print()
print_counter("Top alert signatures:", alert_sigs, 12)
print()
print_counter("Top alert source IPs:", alert_src, 12)
print()
print(f"DNS events                    {dns_queries}")
print(f"DNS NXDOMAIN observations     {dns_nxdomain}")
print(f"Weak Kerberos observations    {len(krb_weak)}")
print(f"SMB NTLMSSP observations      {sum(smb_ntlm.values())}")
smb1 = sum(v for k,v in smb_dialects.items() if "NT LM 0.12" in k.upper() or k.upper().startswith("SMB1"))
print(f"SMB1 observations             {smb1}")

print("\nACTIONABLE FINDINGS")
actions = []
if drop_pct > 1.0:
    actions.append(f"HIGH sensor packet loss: kernel drop rate {drop_pct:.3f}%")
elif drop_pct > 0.1:
    actions.append(f"REVIEW sensor packet loss: kernel drop rate {drop_pct:.3f}%")
if krb_weak:
    actions.append(f"REVIEW {len(krb_weak)} weak Kerberos observation(s) before AES-only enforcement")
if smb1:
    actions.append(f"REVIEW {smb1} SMB1 observation(s); identify legacy clients")
sev12 = sum(v for k,v in alert_sev.items() if str(k) in ("1","2"))
if sev12:
    actions.append(f"INVESTIGATE {sev12} alert(s) with severity value 1/2")
if not actions:
    actions.append("No automatic high-priority decision trigger detected in this window")
for item in actions:
    print(f"  - {item}")
PY
}

ids_summary() {
    local hours="${1:-24}"
    [[ "$hours" =~ ^[0-9]+([.][0-9]+)?$ ]] || hours=24
    ids_eve_parser "$hours" summary
}

ids_recent_alerts() {
    local hours="${1:-24}"
    ids_eve_parser "$hours" alerts
}

ids_ad_intelligence() {
    local hours="${1:-24}"
    ids_eve_parser "$hours" ad
}

ids_choose_window() {
    printf '\n' >&2
    ui_rule >&2
    printf '  [1] Last hour\n' >&2
    printf '  [2] Last 24 hours\n' >&2
    printf '  [3] Last 7 days\n' >&2
    printf '  [C] Custom hours\n' >&2
    printf '  [0] Cancel\n' >&2
    ui_rule >&2
    local choice hours
    choice="$(ask 'Select analysis window' '2')"
    case "$choice" in
        1) printf '1' ;;
        2) printf '24' ;;
        3) printf '168' ;;
        C|c)
            hours="$(ask 'Hours' '24')"
            [[ "$hours" =~ ^[0-9]+$ && "$hours" -ge 1 && "$hours" -le 8760 ]] || return 1
            printf '%s' "$hours"
            ;;
        *) return 1 ;;
    esac
}

ids_sensor_health() {
    section "SURICATA SENSOR HEALTH"
    local bin="" config="" rules="" eve="${IDS_EVE_DIR}/eve.json"
    bin="$(ids_suricata_binary 2>/dev/null || true)"
    config="$(ids_suricata_config 2>/dev/null || true)"
    rules="$(ids_rules_file 2>/dev/null || true)"

    result "$(systemctl is-active --quiet suricata.service && printf PASS || printf WARN)" \
        "Suricata service" "$(safe_systemctl_state suricata.service)" "active"

    [[ -n "$bin" ]] \
        && result PASS "Suricata binary" "$($bin -V 2>&1 | head -n1)" "available" \
        || result WARN "Suricata binary" "missing" "installed"

    [[ -f "$IDS_CONFIG" ]] \
        && result PASS "Managed IDS overlay" "$IDS_CONFIG" "present" \
        || result WARN "Managed IDS overlay" "not configured" "$IDS_CONFIG"

    if [[ -n "$bin" && -n "$config" && -f "$IDS_CONFIG" ]]; then
        ids_validate_config health || true
    fi

    if [[ -n "$rules" ]]; then
        local count=""
        count="$(grep -hcE '^[[:space:]]*(alert|drop|reject)[[:space:]]' "$rules" 2>/dev/null || true)"
        result PASS "Rules file" "$rules / ${count:-0} active rule lines" "loaded"
    else
        result WARN "Rules file" "not found" "suricata.rules"
    fi

    if [[ -f "$eve" ]]; then
        local age size
        age=$(( $(date +%s) - $(stat -c %Y "$eve") ))
        size="$(du -h "$eve" 2>/dev/null | awk '{print $1}')"
        if (( age < 600 )); then
            result PASS "EVE freshness" "${age}s old / ${size:-?}" "<600s"
        else
            result WARN "EVE freshness" "${age}s old / ${size:-?}" "<600s"
        fi
    else
        result WARN "EVE log" "missing: $eve" "present after sensor start"
    fi

    printf '\n'
    ids_summary 1 || true
}

ids_readiness() {
    section "NETWORK IDS READINESS"
    discover_network_topology

    printf '  %-28s %s\n' "Deployment" "Passive IDS on this server"
    printf '  %-28s %s\n' "Recommended interface" "${AD_IFACE:-unknown}"
    printf '  %-28s %s\n' "Recommended HOME_NET" "$(ids_default_home_net 2>/dev/null || printf 'manual')"
    printf '  %-28s %s\n' "Suricata package" "$(package_installed_version suricata)"
    printf '  %-28s %s\n' "suricata-update" "$(package_installed_version suricata-update)"
    printf '  %-28s %s\n' "Service" "$(safe_systemctl_state suricata.service)"
    printf '  %-28s %s\n' "Managed overlay" "$( [[ -f "$IDS_CONFIG" ]] && printf 'present' || printf 'absent' )"
    printf '  %-28s %s\n' "EVE log" "$( [[ -f "${IDS_EVE_DIR}/eve.json" ]] && printf 'present' || printf 'absent' )"

    local exec=""
    exec="$(ids_vendor_execstart 2>/dev/null || true)"
    if grep -Eq '(^|[[:space:]])(-q|--nfq|--nfqueue)([=[:space:]]|$)' <<<"$exec"; then
        result WARN "Capture mode" "NFQUEUE/inline indicators detected" "passive AF_PACKET for this workflow"
    else
        result PASS "Capture policy" "No inline blocking configured by assistant" "passive"
    fi

    printf '\n'
    printf 'Scope reminder: a sensor installed on this DC sees traffic reaching/leaving this host.\n'
    printf 'It does not automatically see lateral client-to-client traffic unless the host receives mirrored/TAP traffic.\n'
}

ids_generate_daily_report() {
    local hours="${1:-24}"
    ids_prepare_state
    local report="${IDS_REPORT_DIR}/ids-report-$(date +%Y%m%d-%H%M%S).txt"

    {
        printf 'DEBIAN AD ASSISTANT — SURICATA DAILY SECURITY REPORT\n'
        printf 'Generated: %s\n' "$(date -Is)"
        printf 'Host: %s\n' "$(hostname -f 2>/dev/null || hostname)"
        printf 'Window: %s hours\n\n' "$hours"
        ids_summary "$hours"
        printf '\n\n'
        ids_ad_intelligence "$hours"
        printf '\n\nRECENT ALERTS\n'
        ids_recent_alerts "$hours"
    } >"$report"

    chmod 600 "$report"
    printf '%s\n' "$report"
}

ids_show_reports() {
    ids_prepare_state
    local -a files=()
    mapfile -t files < <(find "$IDS_REPORT_DIR" -maxdepth 1 -type f -name 'ids-report-*.txt' -printf '%T@|%p\n' 2>/dev/null |
        sort -nr | cut -d'|' -f2- | head -50)

    ((${#files[@]})) || {
        msg_info "No generated IDS reports yet."
        return 0
    }

    printf '\n%bIDS REPORTS%b\n' "$C_BOLD" "$C_RESET"
    local i
    for i in "${!files[@]}"; do
        printf '  [%2d] %s\n' "$((i+1))" "$(basename "${files[$i]}")"
    done
    printf '  [0 ] Cancel\n'

    local choice
    choice="$(ask 'Select report' '1')"
    [[ "$choice" =~ ^[0-9]+$ ]] || return 1
    (( choice >= 1 && choice <= ${#files[@]} )) || return 0

    less -R "${files[$((choice-1))]}" 2>/dev/null || cat "${files[$((choice-1))]}"
}

ids_install_daily_timer() {
    ids_prepare_state

    local target="/usr/local/libexec/debian-ad-assistant"
    if [[ ! -x "$target" ]]; then
        msg_info "The daily timer needs the stable installed assistant path."
        confirm "Install/refresh ad-* CLI commands first?" Y || return 1
        install_cli_commands
    fi

    local when
    when="$(ask 'Daily local IDS report time (HH:MM)' '07:00')"
    [[ "$when" =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]] || {
        msg_warn "Invalid time. Expected HH:MM."
        return 1
    }

    cat >"$IDS_DAILY_SERVICE" <<EOF
[Unit]
Description=Debian AD Assistant daily Suricata security report
After=suricata.service

[Service]
Type=oneshot
ExecStart=${target} --ids-daily --no-color
EOF

    cat >"$IDS_DAILY_TIMER" <<EOF
[Unit]
Description=Schedule Debian AD Assistant daily Suricata security report

[Timer]
OnCalendar=*-*-* ${when}:00
Persistent=true
RandomizedDelaySec=120
Unit=debian-ad-ids-daily.service

[Install]
WantedBy=timers.target
EOF

    chmod 0644 "$IDS_DAILY_SERVICE" "$IDS_DAILY_TIMER"
    systemctl daemon-reload
    systemctl enable --now debian-ad-ids-daily.timer
    result PASS "Daily IDS report timer" "$when local time" "enabled"
}

ids_export_evidence() {
    ids_prepare_state
    local bundle="${RUN_ROOT}/suricata-evidence-${TIMESTAMP}"
    mkdir -p "$bundle"

    [[ -f "$IDS_CONFIG" ]] && cp -a "$IDS_CONFIG" "$bundle/"
    systemctl status suricata.service --no-pager --full >"$bundle/service-status.txt" 2>&1 || true
    journalctl -u suricata.service -b --no-pager -n 200 >"$bundle/journal.txt" 2>&1 || true
    ids_summary 24 >"$bundle/summary-24h.txt" 2>&1 || true
    ids_ad_intelligence 24 >"$bundle/ad-intelligence-24h.txt" 2>&1 || true
    ids_recent_alerts 24 >"$bundle/alerts-24h.txt" 2>&1 || true
    ids_validate_config evidence >"$bundle/config-test.txt" 2>&1 || true

    local out="${RUN_ROOT}/suricata-evidence-${TIMESTAMP}.tar.gz"
    tar -czf "$out" -C "$RUN_ROOT" "$(basename "$bundle")"
    chmod 600 "$out"
    result PASS "IDS evidence bundle" "$out" "generated without raw EVE payload"
}

ids_disable_integration() {
    section "DISABLE SURICATA IDS INTEGRATION"
    printf 'This removes assistant-managed IDS configuration and timers.\n'
    printf 'Suricata packages are retained to avoid deleting pre-existing software.\n'

    confirm_high_risk "Disable Suricata and remove assistant-managed IDS configuration" || return 0

    systemctl disable --now debian-ad-ids-daily.timer >/dev/null 2>&1 || true
    rm -f "$IDS_DAILY_TIMER" "$IDS_DAILY_SERVICE"

    systemctl disable --now suricata.service >/dev/null 2>&1 || true
    rm -f "$IDS_DROPIN" "$IDS_CONFIG"
    rmdir "$(dirname "$IDS_DROPIN")" >/dev/null 2>&1 || true
    systemctl daemon-reload

    change APPLIED "Disabled assistant-managed Suricata IDS integration"
    result PASS "IDS integration" "disabled; packages retained" "clean host integration"
}

ids_menu() {
    while true; do
        (( MENU_MAIN_REQUESTED )) && return 0

        ui_menu_screen "NETWORK IDS / SURICATA" \
            "Optional passive network detection, AD protocol telemetry and local daily reporting"
        ui_menu_item "1" "IDS readiness assessment" "Packages, capture scope, interface and passive/inline posture"
        ui_menu_item "2" "Install / repair Suricata" "Distribution packages only: suricata + suricata-update" "$C_GREEN"
        ui_menu_item "3" "Configure passive IDS" "AF_PACKET on a selected interface; no packet blocking" "$C_GREEN"
        ui_menu_item "4" "Sensor health" "Service, config test, rules, EVE freshness and packet-drop telemetry"
        ui_menu_item "5" "Security summary" "Alerts, DNS, Kerberos, SMB/NTLM and decision triggers"
        ui_menu_item "6" "Recent alerts" "Human-readable alert timeline for a selected time window"
        ui_menu_item "7" "AD protocol intelligence" "Kerberos encryption, weak crypto, SMB dialects and NTLMSSP"
        ui_menu_item "8" "Update rules" "suricata-update -> config test -> safe reload" "$C_YELLOW"
        ui_menu_item "9" "Daily local reports" "Generate/view reports or enable a systemd timer"
        ui_menu_item "10" "Export evidence" "Config/health/summary bundle without raw EVE payload"
        ui_menu_item "11" "Disable IDS integration" "Remove assistant config/timer; retain packages" "$C_RED"
        ui_menu_exit
        ui_rule

        local choice hours report
        choice="$(ask 'Select IDS operation' '1')"
        case "$choice" in
            1) ids_readiness; ui_pause ;;
            2) ids_install_optional; ui_pause ;;
            3) ids_configure_passive; ui_pause ;;
            4) ids_sensor_health; ui_pause ;;
            5)
                hours="$(ids_choose_window)" || { ui_pause; continue; }
                ids_summary "$hours"; ui_pause
                ;;
            6)
                hours="$(ids_choose_window)" || { ui_pause; continue; }
                ids_recent_alerts "$hours"; ui_pause
                ;;
            7)
                hours="$(ids_choose_window)" || { ui_pause; continue; }
                ids_ad_intelligence "$hours"; ui_pause
                ;;
            8)
                ids_update_rules
                ui_pause
                ;;
            9)
                printf '\n  [1] Generate report now\n  [2] View generated reports\n  [3] Enable/refresh daily timer\n  [4] Disable daily timer\n  [0] Cancel\n'
                local daily_choice
                daily_choice="$(ask 'Select report operation' '1')"
                case "$daily_choice" in
                    1) report="$(ids_generate_daily_report 24)"; printf '\nReport: %s\n' "$report" ;;
                    2) ids_show_reports ;;
                    3) ids_install_daily_timer ;;
                    4)
                        systemctl disable --now debian-ad-ids-daily.timer >/dev/null 2>&1 || true
                        rm -f "$IDS_DAILY_TIMER" "$IDS_DAILY_SERVICE"
                        systemctl daemon-reload
                        result PASS "Daily IDS timer" "disabled" "manual reporting only"
                        ;;
                esac
                ui_pause
                ;;
            10) ids_export_evidence; ui_pause ;;
            11) ids_disable_integration; ui_pause ;;
            H|h) MENU_MAIN_REQUESTED=1; return 0 ;;
            0) return 0 ;;
            *) msg_warn "Invalid IDS operation."; ui_pause ;;
        esac
    done
}

ids_daily_mode() {
    # Non-interactive target for the systemd timer. Never installs or changes
    # packages/configuration; it only reads EVE and writes a local report.
    ids_prepare_state
    if [[ ! -f "${IDS_EVE_DIR}/eve.json" ]]; then
        msg_warn "No Suricata EVE log is available; daily report skipped."
        return 0
    fi
    ids_generate_daily_report 24 >/dev/null
}

cli_command_catalog() {
    cat <<'EOF'
adctl|Main control plane|Open the full AD/DC Main Control Plane: maintenance, operations, security, backup and migration.
ad-ops|Directory operations|Open the reduced daily users/groups/computers/permissions/GPO operations console.
ad-users|Users|Create, inspect, edit, enable/disable, reset passwords and manage group memberships.
ad-groups|Groups|Create, inspect and manage domain groups and their members.
ad-computers|Computers|List/inspect domain computer accounts and show best-effort network presence.
ad-permissions|Access & delegation|Manage memberships and advanced directory-service ACL operations.
ad-gpo|Group Policy|Platform-aware GPO lifecycle, built-in/custom JSON library, status, scope, Ubuntu ADSys and Samba Linux.
ad-security|Host security|Boot ordering, UFW, Fail2ban, sysctl, delegated-admin and Samba/Kerberos hardening.
ad-samba|Samba security|Samba transport/authentication hardening, signed time and Kerberos crypto posture.
ad-kerberos|Kerberos security|Kerberos config integrity, encryption readiness, AES-only enforcement and rollback.
ad-migrate|Domain migration|Assess domain changes, inventory scope and generate client migration packages.
ad-reset|Domain reset|Destructive local Samba AD/DC decommission/reset with external recovery bundle.
ad-deps|Dependencies|Audit/install/update the minimal official distribution package set used by the control plane.
ad-ids|Network IDS|Optional passive Suricata IDS, AD protocol telemetry, daily summaries and evidence export.
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
    printf '    sudo adctl        %b# full main control plane%b\n' "$C_DIM" "$C_RESET"
    printf '    sudo ad-ops       %b# reduced daily directory operations console%b\n' "$C_DIM" "$C_RESET"
    printf '    sudo ad-users     %b# user administration%b\n' "$C_DIM" "$C_RESET"
    printf '    sudo ad-gpo       %b# Group Policy console%b\n' "$C_DIM" "$C_RESET"
    printf '    sudo ad-samba     %b# Samba/Kerberos security center%b\n' "$C_DIM" "$C_RESET"
    printf '    sudo ad-kerberos  %b# Kerberos security center%b\n' "$C_DIM" "$C_RESET"
    printf '    sudo ad-ids       %b# passive Suricata IDS / daily security summary%b\n' "$C_DIM" "$C_RESET"
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
        (( MENU_MAIN_REQUESTED )) && return 0
        ui_menu_screen "SECURITY & BOOT RESILIENCE" "Host controls protecting availability, management access and the AD service plane"
        ui_menu_item "1" "Boot persistence audit" "Verify Samba startup and network readiness dependency"
        ui_menu_item "2" "Repair boot ordering" "Make Samba wait for the AD interface/IP" "$C_GREEN"
        ui_menu_item "3" "Fail2ban / SSH" "Configure brute-force mitigation for SSH"
        ui_menu_item "4" "Kernel network hardening" "Apply conservative sysctl protections"
        ui_menu_item "5" "Firewall policy" "Restrict AD and SSH exposure to trusted networks"
        ui_menu_item "6" "Delegated administrator" "Verify admin, promote it, optionally disable built-in Administrator"
        ui_menu_item "7" "Full AD/DC validation" "Run DNS, Kerberos, LDAP, SMB, database and SYSVOL checks"
        ui_menu_item "8" "Repair local resolver" "Replace broken resolved stub with persistent Samba DNS /etc/resolv.conf" "$C_GREEN"
        ui_menu_item "9" "Samba & Kerberos security" "Protocol hardening, crypto readiness and signed domain time" "$C_GREEN"
        ui_menu_item "10" "Network IDS / Suricata" "Passive network detection and AD protocol telemetry" "$C_GREEN"
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
            7) set_progress_plan 1; validate_ad || true; ui_pause ;;
            8) set_progress_plan 1; repair_local_resolver_only; ui_pause ;;
            9) samba_kerberos_security_menu ;;
            10) ids_menu ;;
            H|h) MENU_MAIN_REQUESTED=1; break ;;
            0) break ;;
            *) msg_warn "Invalid menu option."; ui_pause ;;
        esac
    done
}

domain_admin_console() {
    while true; do
        MENU_MAIN_REQUESTED=0
        ui_menu_screen "AD/DC DAILY OPERATIONS" "Focused users, groups, computers, permissions, GPOs and routine administration"
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
        ui_menu_item "11" "Domain migration" "Assessment, trusts, inventory and client migration packages" "$C_YELLOW"
        ui_menu_root_exit
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
            9) set_progress_plan 1; validate_ad || true; ui_pause ;;
            10) set_progress_plan 1; create_domain_backup; ui_pause ;;
            11) domain_migration_menu ;;
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
  [ ] systemctl is-enabled debian-ad-samba-health.service
  [ ] systemctl status debian-ad-samba-health.service --no-pager -l
  [ ] journalctl -u debian-ad-samba-health.service -b --no-pager
  [ ] ss -lntup | grep -E ':(53|88|389|445|464)([[:space:]]|$)'
  [ ] systemd-analyze critical-chain samba-ad-dc.service

[AD/DNS/KERBEROS]
  [ ] sudo ${0} --validate
  [ ] sudo ad-samba -> Full security audit
  [ ] dig @127.0.0.1 ${DC_FQDN}
  [ ] kinit ${ADMIN_USER}@${REALM}
  [ ] kvno ldap/${DC_FQDN}
  [ ] klist -e and review ticket encryption
  [ ] /usr/sbin/chronyd -p -f /etc/chrony/chrony.conf
  [ ] systemctl status chrony.service
  [ ] chronyc waitsync 12 0 0 5
  [ ] chronyc tracking / chronyc sources -v / signed domain time

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

    # Samba creates ntp_signd as part of the AD/DC runtime. Configure Chrony
    # only after provisioning/startup so permissions and socket path can be
    # validated without making first-boot time service fragile.
    if chrony_supports_ntp_signd; then
        configure_signed_domain_time || warn_msg "Signed MS-SNTP could not be finalized; review ad-samba."
    fi

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
        ui_menu_screen "AD/DC MAIN CONTROL PLANE" "Maintenance, daily operations, security, recovery and migration"
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
        ui_menu_item "15" "Repair local resolver" "Fix /etc/resolv.conf stub/symlink and validate AD DC discovery"
        ui_menu_item "16" "Domain migration center" "Assess domain changes and prepare coexistence/client migration"
        ui_menu_item "17" "Samba & Kerberos security" "LDAP/SMB hardening, KDC crypto, krb5 integrity and signed time" "$C_GREEN"
        ui_menu_item "18" "Domain decommission / reset" "Destroy local AD/DC state and remove assistant-managed configuration" "$C_RED"
        ui_menu_item "19" "Dependencies & packages" "Minimal required packages, repair missing tools and scoped updates" "$C_GREEN"
        ui_menu_item "20" "Network IDS / Suricata" "Optional passive IDS, AD protocol telemetry and daily security summaries" "$C_GREEN"
        ui_menu_root_exit
        ui_rule
        local choice
        choice="$(ask 'Select module' '1')"
        case "$choice" in
            1) set_progress_plan 2; audit_existing; audit_security_baseline; ui_pause ;;
            2) set_progress_plan 1; validate_ad || true; ui_pause ;;
            3) repair_dns_stack; ui_pause ;;
            4)
                set_progress_plan 1
                if ! configure_time; then
                    msg_warn "Chrony configuration was not applied. Previous configuration was preserved where possible."
                fi
                ui_pause
                ;;
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
            15) set_progress_plan 1; repair_local_resolver_only; ui_pause ;;
            16) domain_migration_menu ;;
            17) samba_kerberos_security_menu ;;
            18) domain_reset_menu; (( RESET_COMPLETED )) && return 0 ;;
            19) dependency_menu ;;
            20) ids_menu ;;
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
    ensure_existing_dependency_preflight

    upgrade_samba_boot_health_guard_if_managed

    if ! ensure_samba_runtime_health; then
        msg_warn "Samba AD/DC is still degraded after one recovery attempt. The console will remain open; Kerberos/LDAP-dependent operations may fail until the service issue is resolved."
    fi

    [[ -n "$ADMIN_USER" ]] || ADMIN_USER="$(ask 'AD admin account' 'Administrator')"
}

manage_mode() {
    prepare_existing_ad_context
    snapshot_system
    manage_menu
    (( RESET_COMPLETED )) || save_config
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
    validate_ad || true
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
        samba-security) prepare_existing_ad_context; samba_kerberos_security_menu; save_config ;;
        kerberos-security) prepare_existing_ad_context; kerberos_security_menu; save_config ;;
        migration) prepare_existing_ad_context; domain_migration_menu; save_config ;;
        reset-domain) prepare_existing_ad_context; domain_reset_menu ;;
        dependencies) detect_samba_role; load_config || true; dependency_menu ;;
        ids) prepare_existing_ad_context; ids_menu; save_config ;;
        ids-daily) load_config || true; ids_daily_mode ;;
        install-cli) install_cli_commands ;;
        cli-info) show_cli_commands ;;
        interactive) interactive_mode ;;
        *) die "Unknown mode: $MODE" ;;
    esac

    if (( RESET_COMPLETED )); then
        return 0
    fi

    if (( MENU_MAIN_REQUESTED )); then
        MENU_MAIN_REQUESTED=0
        manage_menu
        (( RESET_COMPLETED )) || save_config
    fi

    if (( RESET_COMPLETED )); then
        return 0
    fi

    write_report
    summary
}

main "$@"

