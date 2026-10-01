#!/usr/bin/env bash
# rhel-ad-client-assistant.sh
# Version 1.1.0-rhel-parity
#
# Reversible, transaction-aware Active Directory client assistant for
# Enterprise Linux systems using SSSD/realmd/adcli.
#
# Primary targets:
#   - Red Hat Enterprise Linux 9 / 10
#   - Rocky Linux 9 / 10
#   - AlmaLinux 9 / 10
#
# Core flow:
#   detect -> preflight -> snapshot -> packages -> DNS -> discover -> join -> validate
#   recover interrupted transactions without guessing membership state
#   leave -> restore pre-join DNS/hostname -> optional package cleanup
#
# No password is stored. No third-party repository is added.

set -Eeuo pipefail
IFS=$'\n\t'
umask 077

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

SCRIPT_VERSION="1.1.0-rhel-parity"
PRODUCT_NAME="RHEL AD Client Assistant"

STATE_ROOT="/var/lib/rhel-ad-client-assistant"
BACKUP_ROOT="/var/backups/rhel-ad-client-assistant"
LOG_ROOT="/var/log/rhel-ad-client-assistant"
REPORT_ROOT="${STATE_ROOT}/reports"
CURRENT_STATE="${STATE_ROOT}/current.env"
LOCK_FILE="${STATE_ROOT}/assistant.lock"
RUN_ID="$(date +%Y%m%d-%H%M%S)-$$"
RUN_LOG=""
RUN_REPORT=""
RUN_EVENT_FILE=""
MODE="interactive"
NO_COLOR_FLAG=0
ALLOW_ISOLATED_DNS=0
EXTERNAL_DNS_PROBE="www.redhat.com"
INPUT_FD=0

DISTRO_ID=""
DISTRO_NAME=""
DISTRO_VERSION=""
DISTRO_MAJOR=""
ACTIVE_IFACE=""
NM_CONNECTION=""
NM_CONNECTION_UUID=""
REMOTE_SESSION=0
PRIVATE_KRB5CCACHE="${STATE_ROOT}/krb5cc-${RUN_ID}"
TRANSACTION_ACTIVE=0
TRANSACTION_COMMITTED=0
TRANSACTION_SNAPSHOT=""
TRANSACTION_PHASE=""
TRANSACTION_ROLLBACK=0
RUN_OUTCOME="COMPLETE"

USE_COLOR=1
RESULTS_PASS=0
RESULTS_WARN=0
RESULTS_FAIL=0

C_RESET=$'\033[0m'
C_BOLD=$'\033[1m'
C_DIM=$'\033[2m'
C_RED=$'\033[31m'
C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'
C_CYAN=$'\033[36m'

command_exists() { command -v "$1" >/dev/null 2>&1; }

log() {
    [[ -n "$RUN_LOG" ]] || return 0
    printf '%s %s\n' "$(date -Is)" "$*" >>"$RUN_LOG"
}

record_event() {
    local level="$1"; shift
    [[ -n "$RUN_EVENT_FILE" ]] || return 0
    local message="$*"
    message="${message//$'\t'/ }"; message="${message//$'\n'/ }"
    printf '%s\t%s\t%s\n' "$(date -Is)" "$level" "$message" >>"$RUN_EVENT_FILE"
}

info() { printf '%b[INFO]%b %s\n' "$C_CYAN" "$C_RESET" "$*"; log "INFO $*"; record_event INFO "$*"; }
ok()   { printf '%b[ OK ]%b %s\n' "$C_GREEN" "$C_RESET" "$*"; log "OK $*"; record_event OK "$*"; ((RESULTS_PASS+=1)); }
warn() { printf '%b[WARN]%b %s\n' "$C_YELLOW" "$C_RESET" "$*"; log "WARN $*"; record_event WARN "$*"; ((RESULTS_WARN+=1)); }
err()  { printf '%b[ERROR]%b %s\n' "$C_RED" "$C_RESET" "$*" >&2; log "ERROR $*"; record_event ERROR "$*"; ((RESULTS_FAIL+=1)); }

ask() {
    local prompt="$1" default="${2:-}" value=""
    if [[ -n "$default" ]]; then
        printf '%s [%s]: ' "$prompt" "$default" >&${INPUT_FD}
    else
        printf '%s: ' "$prompt" >&${INPUT_FD}
    fi
    IFS= read -r -u "$INPUT_FD" value || return 1
    [[ -n "$value" ]] || value="$default"
    printf '%s' "$value"
}

confirm() {
    local prompt="$1" default="${2:-N}" answer=""
    printf '%s [%s]: ' "$prompt" "$default" >&${INPUT_FD}
    IFS= read -r -u "$INPUT_FD" answer || return 1
    [[ -n "$answer" ]] || answer="$default"
    [[ "${answer,,}" =~ ^(y|yes|s|si|sí)$ ]]
}

confirm_literal() {
    local prompt="$1" literal="$2" answer=""
    printf '%s\nType %s to continue: ' "$prompt" "$literal" >&${INPUT_FD}
    IFS= read -r -u "$INPUT_FD" answer || return 1
    [[ "$answer" == "$literal" ]]
}

pause_ui() {
    [[ -t "$INPUT_FD" ]] || return 0
    printf '\nPress Enter to continue...' >&${INPUT_FD}
    read -r -u "$INPUT_FD" _ || true
}

valid_domain() {
    local name="${1,,}" label
    [[ ${#name} -ge 3 && ${#name} -le 253 && "$name" == *.* && "$name" != .* && "$name" != *. && "$name" != *..* ]] || return 1
    IFS='.' read -r -a _labels <<<"$name"
    for label in "${_labels[@]}"; do
        [[ ${#label} -ge 1 && ${#label} -le 63 ]] || return 1
        [[ "$label" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || return 1
    done
}

valid_ipv4() {
    local ip="$1" a b c d extra octet
    [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
    IFS='.' read -r a b c d extra <<<"$ip"
    [[ -z "${extra:-}" ]] || return 1
    for octet in "$a" "$b" "$c" "$d"; do
        ((10#$octet >= 0 && 10#$octet <= 255)) || return 1
    done
}

parse_dns_list() { tr ',;' '  ' <<<"$1" | awk '{for(i=1;i<=NF;i++) print $i}'; }

validate_dns_list() {
    local ip count=0
    while IFS= read -r ip; do
        [[ -n "$ip" ]] || continue
        valid_ipv4 "$ip" || return 1
        ((count+=1))
    done < <(parse_dns_list "$1")
    ((count > 0))
}

atomic_write() {
    local path="$1" tmp="${path}.tmp.$$"
    cat >"$tmp"
    chmod 0600 "$tmp" 2>/dev/null || true
    mv -f "$tmp" "$path"
}

state_get() {
    local key="$1"
    [[ -r "$CURRENT_STATE" ]] || return 1
    awk -F= -v k="$key" '$1==k{gsub(/^"|"$/, "", $2); print substr($0,index($0,"=")+1); exit}' "$CURRENT_STATE" | sed -e "s/^'//" -e "s/'$//"
}

write_state() {
    local phase="$1" snapshot="$2" domain="${3:-}" iface="${4:-}" joined_at="${5:-}"
    {
        printf 'STATE_VERSION=%q\n' '2'
        printf 'PHASE=%q\n' "$phase"
        printf 'UPDATED_AT=%q\n' "$(date -Is)"
        printf 'RUN_ID=%q\n' "$RUN_ID"
        printf 'SNAPSHOT=%q\n' "$snapshot"
        printf 'DOMAIN=%q\n' "$domain"
        printf 'INTERFACE=%q\n' "$iface"
        printf 'JOINED_AT=%q\n' "$joined_at"
    } | atomic_write "$CURRENT_STATE"
    TRANSACTION_PHASE="$phase"
}

load_state_file() {
    local path="$1"
    [[ -r "$path" ]] || return 1
    # State files are generated exclusively by this script with %q.
    # shellcheck disable=SC1090
    . "$path"
}

current_boot_id() { cat /proc/sys/kernel/random/boot_id 2>/dev/null || printf unknown; }

cleanup_private_ccache() {
    if command_exists kdestroy; then
        KRB5CCNAME="FILE:${PRIVATE_KRB5CCACHE}" kdestroy >/dev/null 2>&1 || true
    fi
    rm -f -- "$PRIVATE_KRB5CCACHE" >/dev/null 2>&1 || true
}

snapshot_file() {
    local snap="$1" path="$2" key
    key="$(printf '%s' "$path" | sed 's#^/##; s#/#__#g')"
    if [[ -e "$path" || -L "$path" ]]; then
        mkdir -p "$snap/files"
        cp -a -- "$path" "$snap/files/$key"
        printf '%s\tpresent\t%s\n' "$path" "$key" >>"$snap/file-manifest.tsv"
    else
        printf '%s\tabsent\t%s\n' "$path" "$key" >>"$snap/file-manifest.tsv"
    fi
}

restore_snapshot_file() {
    local snap="$1" path="$2" line state key
    line="$(awk -F'\t' -v p="$path" '$1==p{print; exit}' "$snap/file-manifest.tsv" 2>/dev/null || true)"
    [[ -n "$line" ]] || return 0
    IFS=$'\t' read -r _ state key <<<"$line"
    if [[ "$state" == present && -e "$snap/files/$key" || "$state" == present && -L "$snap/files/$key" ]]; then
        rm -rf -- "$path"
        cp -a -- "$snap/files/$key" "$path"
    else
        rm -rf -- "$path"
    fi
}

write_json_report() {
    local outcome="${1:-$RUN_OUTCOME}" domain="" phase="" snapshot="" selinux crypto realm_name secure_channel
    domain="$(state_get DOMAIN 2>/dev/null || true)"
    phase="$(state_get PHASE 2>/dev/null || true)"
    snapshot="$(state_get SNAPSHOT 2>/dev/null || true)"
    selinux="$(getenforce 2>/dev/null || printf unavailable)"
    crypto="$(update-crypto-policies --show 2>/dev/null || printf unavailable)"
    realm_name="$(realm list --name-only 2>/dev/null | head -n1 || true)"
    secure_channel="unknown"
    if command_exists adcli && [[ -n "$realm_name" ]]; then
        adcli testjoin -D "$realm_name" >/dev/null 2>&1 && secure_channel="valid" || secure_channel="invalid"
    fi
    python3 - "$RUN_REPORT" "$RUN_EVENT_FILE" "$PRODUCT_NAME" "$SCRIPT_VERSION" "$RUN_ID" "$outcome" "$domain" "$phase" "$snapshot" "$DISTRO_NAME" "$ACTIVE_IFACE" "$NM_CONNECTION" "$realm_name" "$secure_channel" "$selinux" "$crypto" "$RESULTS_PASS" "$RESULTS_WARN" "$RESULTS_FAIL" "$RUN_LOG" <<'PYREPORT' 2>/dev/null || true
import json,sys,datetime,os
(path,eventfile,product,version,run_id,outcome,domain,phase,snapshot,os_name,iface,nm,realm,secure,selinux,crypto,p,w,f,logfile)=sys.argv[1:]
events=[]
if eventfile and os.path.exists(eventfile):
    with open(eventfile,encoding='utf-8',errors='replace') as fh:
        for raw in fh:
            parts=raw.rstrip('\n').split('\t',2)
            if len(parts)==3:
                events.append({'Time':parts[0],'Type':parts[1],'Message':parts[2]})
data={
  'SchemaVersion':2,
  'Assistant':product,
  'Version':version,
  'RunId':run_id,
  'GeneratedAt':datetime.datetime.now(datetime.timezone.utc).astimezone().isoformat(),
  'Outcome':outcome,
  'Host':{'OS':os_name,'Interface':iface,'NetworkManagerConnection':nm},
  'Membership':{'Domain':domain,'Realm':realm,'Phase':phase,'SecureChannel':secure,'Snapshot':snapshot},
  'Security':{'SELinux':selinux,'CryptoPolicy':crypto},
  'BaselineClaim':'Operational AD integration checks; not a CIS or vendor-support certification',
  'Counts':{'Pass':int(p),'Warn':int(w),'Fail':int(f)},
  'Log':logfile,
  'Events':events[-300:]
}
with open(path,'w',encoding='utf-8') as fh:
    json.dump(data,fh,indent=2); fh.write('\n')
PYREPORT
}

on_exit() {
    local rc=$?
    cleanup_private_ccache

    # Automatic rollback is safe only before realm join was submitted.
    # JOIN_SUBMITTED is intentionally ambiguous and must be reconciled using
    # realm/adcli evidence rather than by blindly restoring DNS/identity files.
    if ((TRANSACTION_ACTIVE == 1 && TRANSACTION_COMMITTED == 0 && TRANSACTION_ROLLBACK == 0)) &&
       [[ -n "$TRANSACTION_SNAPSHOT" && -d "$TRANSACTION_SNAPSHOT" ]]; then
        if [[ "$TRANSACTION_PHASE" =~ ^(STARTED|SNAPSHOT_CREATED|PACKAGES_READY|DNS_VALIDATED|DNS_APPLIED|DISCOVERED)$ ]]; then
            TRANSACTION_ROLLBACK=1
            printf '\n%b[RECOVERY]%b Interrupted pre-membership transaction detected; restoring local state.\n' "$C_YELLOW" "$C_RESET" >&2
            restore_prejoin_snapshot "$TRANSACTION_SNAPSHOT" noninteractive || true
            write_state "INTERRUPTED_ROLLBACK" "$TRANSACTION_SNAPSHOT" "$(snapshot_value "$TRANSACTION_SNAPSHOT" DOMAIN)" "$(snapshot_value "$TRANSACTION_SNAPSHOT" ACTIVE_IFACE)"
        elif [[ "$TRANSACTION_PHASE" == "JOIN_SUBMITTED" ]]; then
            RUN_OUTCOME="RECOVERY_REQUIRED"
            warn "Join was interrupted after submission. DNS is intentionally preserved until membership is reconciled with --recover."
        fi
    fi

    [[ -n "$RUN_REPORT" ]] && write_json_report "$RUN_OUTCOME"
    return "$rc"
}

init_runtime() {
    ((EUID == 0)) || { printf 'Run this assistant as root (sudo).\n' >&2; exit 1; }
    mkdir -p "$STATE_ROOT" "$BACKUP_ROOT" "$LOG_ROOT" "$REPORT_ROOT"
    chmod 0700 "$STATE_ROOT" "$BACKUP_ROOT" "$LOG_ROOT" "$REPORT_ROOT" 2>/dev/null || true

    exec 9>"$LOCK_FILE"
    flock -n 9 || { printf 'Another RHEL AD Client Assistant process appears to be running.\n' >&2; exit 2; }

    RUN_LOG="${LOG_ROOT}/${RUN_ID}.log"
    RUN_REPORT="${REPORT_ROOT}/${RUN_ID}.json"
    RUN_EVENT_FILE="${LOG_ROOT}/${RUN_ID}.events.tsv"
    : >"$RUN_LOG"; : >"$RUN_EVENT_FILE"
    chmod 0600 "$RUN_LOG" "$RUN_EVENT_FILE"

    if [[ -r /dev/tty && -w /dev/tty ]]; then exec {INPUT_FD}<>/dev/tty; fi
    [[ -n "${SSH_CONNECTION:-}" || -n "${SSH_CLIENT:-}" ]] && REMOTE_SESSION=1

    detect_os
    detect_network
    trap on_exit EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
}

detect_os() {
    [[ -r /etc/os-release ]] || { err "/etc/os-release is unavailable."; return 1; }
    # shellcheck disable=SC1091
    . /etc/os-release
    DISTRO_ID="${ID:-unknown}"
    DISTRO_NAME="${PRETTY_NAME:-$DISTRO_ID}"
    DISTRO_VERSION="${VERSION_ID:-unknown}"
    DISTRO_MAJOR="${DISTRO_VERSION%%.*}"

    case "$DISTRO_ID" in
        rhel|rocky|almalinux|centos) ;;
        *)
            err "Unsupported distribution for this specialized build: $DISTRO_NAME"
            warn "Use linux-ad-client-assistant.sh for Debian/Ubuntu or generic systemd clients."
            return 1
            ;;
    esac

    if [[ ! "$DISTRO_MAJOR" =~ ^(9|10)$ ]]; then
        warn "This build is validated conceptually for Enterprise Linux 9/10; detected $DISTRO_NAME."
        confirm "Continue in compatibility mode?" N || return 1
    fi

    command_exists systemctl && [[ -d /run/systemd/system ]] || {
        err "systemd is required for the automated lifecycle."
        return 1
    }
}

route_iface_for() {
    local target="$1"
    ip -4 route get "$target" 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}'
}

detect_network() {
    ACTIVE_IFACE=""
    if ((REMOTE_SESSION)); then
        local remote="${SSH_CLIENT%% *}"
        [[ -n "$remote" ]] || remote="${SSH_CONNECTION%% *}"
        [[ -n "$remote" ]] && ACTIVE_IFACE="$(route_iface_for "$remote" || true)"
    fi
    [[ -n "$ACTIVE_IFACE" ]] || ACTIVE_IFACE="$(ip -4 route show default 2>/dev/null | awk 'NR==1{for(i=1;i<=NF;i++)if($i=="dev"){print $(i+1);exit}}')"
    [[ -n "$ACTIVE_IFACE" ]] || ACTIVE_IFACE="$(ip -4 -o addr show scope global 2>/dev/null | awk 'NR==1{print $2}')"

    NM_CONNECTION=""
    NM_CONNECTION_UUID=""
    if command_exists nmcli && systemctl is-active --quiet NetworkManager.service 2>/dev/null && [[ -n "$ACTIVE_IFACE" ]]; then
        NM_CONNECTION="$(nmcli -g GENERAL.CONNECTION device show "$ACTIVE_IFACE" 2>/dev/null || true)"
        [[ "$NM_CONNECTION" == "--" ]] && NM_CONNECTION=""
        [[ -n "$NM_CONNECTION" ]] && NM_CONNECTION_UUID="$(nmcli -g connection.uuid connection show "$NM_CONNECTION" 2>/dev/null || true)"
    fi
}

header() {
    clear 2>/dev/null || true
    printf '%b%s%b\n' "$C_BOLD" "$PRODUCT_NAME" "$C_RESET"
    printf 'Version : %s\n' "$SCRIPT_VERSION"
    printf 'Host    : %s\n' "$(hostname -f 2>/dev/null || hostname)"
    printf 'OS      : %s\n' "$DISTRO_NAME"
    printf 'Network : %s / %s\n' "${ACTIVE_IFACE:-unknown}" "${NM_CONNECTION:-unmanaged}"
    local realm_name="" phase="none" sssd="n/a" selinux="" crypto="" dns=""
    command_exists realm && realm_name="$(realm list --name-only 2>/dev/null | head -n1 || true)"
    [[ -r "$CURRENT_STATE" ]] && phase="$(state_get PHASE 2>/dev/null || printf unknown)"
    systemctl is-active --quiet sssd.service 2>/dev/null && sssd="online" || { command_exists sssd && sssd="offline" || true; }
    selinux="$(getenforce 2>/dev/null || printf unavailable)"
    crypto="$(update-crypto-policies --show 2>/dev/null || printf unavailable)"
    dns="$(nmcli -g IP4.DNS device show "$ACTIVE_IFACE" 2>/dev/null | paste -sd, - || true)"
    printf 'Domain  : %s\n' "${realm_name:-not joined}"
    printf 'State   : %s / SSSD=%s\n' "$phase" "$sssd"
    printf 'DNS     : %s\n' "${dns:-unknown}"
    printf 'Security: SELinux=%s / crypto=%s\n' "$selinux" "$crypto"
    printf '%s\n\n' '------------------------------------------------------------------------'
}

required_packages() {
    # Core set follows Red Hat's documented direct-AD integration path.
    # bind-utils/authselect are platform-native capabilities used for diagnostics.
    printf '%s\n' realmd oddjob oddjob-mkhomedir sssd adcli krb5-workstation samba-common-tools bind-utils authselect
}

pkg_installed() { rpm -q "$1" >/dev/null 2>&1; }

install_dependencies() {
    local snap="$1" pkg
    local -a missing=()
    : >"$snap/packages-installed-by-assistant.txt"
    while IFS= read -r pkg; do
        pkg_installed "$pkg" || missing+=("$pkg")
    done < <(required_packages)

    if ((${#missing[@]})); then
        local unavailable=0
        for pkg in "${missing[@]}"; do
            if ! dnf -q list --available "$pkg" >/dev/null 2>&1; then
                err "Required package is not available from configured repositories: $pkg"
                unavailable=1
            fi
        done
        ((unavailable == 0)) || return 1
        info "Required packages missing from the configured system repositories:"
        printf '  %s\n' "${missing[@]}"
        confirm "Install these packages with dnf?" Y || return 1
        if ! dnf install -y "${missing[@]}"; then
            for pkg in "${missing[@]}"; do pkg_installed "$pkg" && printf '%s\n' "$pkg" >>"$snap/packages-installed-by-assistant.txt"; done
            err "dnf dependency installation failed; packages actually added were recorded for rollback."
            return 1
        fi
        for pkg in "${missing[@]}"; do pkg_installed "$pkg" && printf '%s\n' "$pkg" >>"$snap/packages-installed-by-assistant.txt"; done
    else
        ok "Required AD client packages are already installed."
    fi

    for pkg in realm adcli kinit getent nmcli dig authselect; do
        command_exists "$pkg" || { err "Required command unavailable after installation: $pkg"; return 1; }
    done

    systemctl enable --now oddjobd.service >/dev/null 2>&1 || warn "oddjobd could not be enabled; automatic home creation may be unavailable."
}

snapshot_value() {
    local snap="$1" key="$2"
    [[ -r "$snap/snapshot.env" ]] || return 1
    (unset "$key"; load_state_file "$snap/snapshot.env"; eval "printf '%s' \"\${$key:-}\"")
}

create_snapshot() {
    local domain="$1" iface="$2" snap="${BACKUP_ROOT}/$(date +%Y%m%d-%H%M%S)-${domain//./_}"
    mkdir -p "$snap"
    chmod 0700 "$snap"
    : >"$snap/file-manifest.tsv"

    detect_network
    {
        printf 'SNAPSHOT_VERSION=%q\n' '3'
        printf 'CREATED_AT=%q\n' "$(date -Is)"
        printf 'DOMAIN=%q\n' "$domain"
        printf 'HOSTNAME=%q\n' "$(hostnamectl --static 2>/dev/null || hostname -s)"
        printf 'ACTIVE_IFACE=%q\n' "$iface"
        printf 'NM_CONNECTION=%q\n' "$NM_CONNECTION"
        printf 'NM_CONNECTION_UUID=%q\n' "$NM_CONNECTION_UUID"
        printf 'BOOT_ID=%q\n' "$(current_boot_id)"
        if [[ -n "$NM_CONNECTION" ]]; then
            printf 'NM_IPV4_METHOD=%q\n' "$(nmcli -g ipv4.method connection show "$NM_CONNECTION" 2>/dev/null || true)"
            printf 'NM_IPV4_IGNORE_AUTO_DNS=%q\n' "$(nmcli -g ipv4.ignore-auto-dns connection show "$NM_CONNECTION" 2>/dev/null || true)"
            printf 'NM_IPV4_DNS=%q\n' "$(nmcli -g ipv4.dns connection show "$NM_CONNECTION" 2>/dev/null || true)"
            printf 'NM_IPV4_DNS_SEARCH=%q\n' "$(nmcli -g ipv4.dns-search connection show "$NM_CONNECTION" 2>/dev/null || true)"
            printf 'NM_IPV4_DNS_PRIORITY=%q\n' "$(nmcli -g ipv4.dns-priority connection show "$NM_CONNECTION" 2>/dev/null || true)"
            printf 'NM_IPV6_IGNORE_AUTO_DNS=%q\n' "$(nmcli -g ipv6.ignore-auto-dns connection show "$NM_CONNECTION" 2>/dev/null || true)"
            printf 'NM_IPV6_DNS=%q\n' "$(nmcli -g ipv6.dns connection show "$NM_CONNECTION" 2>/dev/null || true)"
            printf 'NM_IPV6_DNS_SEARCH=%q\n' "$(nmcli -g ipv6.dns-search connection show "$NM_CONNECTION" 2>/dev/null || true)"
        fi
        printf 'AUTHSELECT_CURRENT=%q\n' "$(authselect current -r 2>/dev/null | tr '\n' ';' || true)"
        printf 'REALM_BEFORE=%q\n' "$(realm list --name-only 2>/dev/null | paste -sd, - || true)"
    } >"$snap/snapshot.env"
    chmod 0600 "$snap/snapshot.env"

    snapshot_file "$snap" /etc/krb5.conf
    snapshot_file "$snap" /etc/krb5.keytab
    snapshot_file "$snap" /etc/realmd.conf
    snapshot_file "$snap" /etc/sssd/sssd.conf
    snapshot_file "$snap" /etc/authselect
    snapshot_file "$snap" /var/lib/authselect
    snapshot_file "$snap" /etc/nsswitch.conf
    snapshot_file "$snap" /etc/pam.d/system-auth
    snapshot_file "$snap" /etc/pam.d/password-auth
    snapshot_file "$snap" /etc/resolv.conf

    TRANSACTION_SNAPSHOT="$snap"
    printf '%s' "$snap"
}

restore_network() {
    local snap="$1"
    load_state_file "$snap/snapshot.env"
    local con_ref="${NM_CONNECTION_UUID:-${NM_CONNECTION:-}}"
    if [[ -n "$con_ref" ]] && command_exists nmcli && nmcli connection show "$con_ref" >/dev/null 2>&1; then
        nmcli connection modify "$con_ref" \
            ipv4.ignore-auto-dns "${NM_IPV4_IGNORE_AUTO_DNS:-no}" \
            ipv4.dns "${NM_IPV4_DNS:-}" \
            ipv4.dns-search "${NM_IPV4_DNS_SEARCH:-}" \
            ipv4.dns-priority "${NM_IPV4_DNS_PRIORITY:-0}" || true
        nmcli connection modify "$con_ref" \
            ipv6.ignore-auto-dns "${NM_IPV6_IGNORE_AUTO_DNS:-no}" \
            ipv6.dns "${NM_IPV6_DNS:-}" \
            ipv6.dns-search "${NM_IPV6_DNS_SEARCH:-}" || true
        nmcli device reapply "${ACTIVE_IFACE:-}" >/dev/null 2>&1 || nmcli connection up "$con_ref" >/dev/null 2>&1 || true
        ok "Pre-join NetworkManager DNS configuration restored."
    else
        warn "Original NetworkManager connection is unavailable; restoring /etc/resolv.conf snapshot only."
        restore_snapshot_file "$snap" /etc/resolv.conf
    fi
}

restore_identity() {
    local snap="$1"
    restore_snapshot_file "$snap" /etc/krb5.conf
    restore_snapshot_file "$snap" /etc/krb5.keytab
    restore_snapshot_file "$snap" /etc/realmd.conf
    restore_snapshot_file "$snap" /etc/sssd/sssd.conf
    restore_snapshot_file "$snap" /etc/authselect
    restore_snapshot_file "$snap" /var/lib/authselect
    restore_snapshot_file "$snap" /etc/nsswitch.conf
    restore_snapshot_file "$snap" /etc/pam.d/system-auth
    restore_snapshot_file "$snap" /etc/pam.d/password-auth
    command_exists authselect && authselect check >/dev/null 2>&1 || true
    systemctl restart sssd.service >/dev/null 2>&1 || true
}

restore_hostname() {
    local snap="$1" original
    original="$(snapshot_value "$snap" HOSTNAME || true)"
    [[ -n "$original" ]] || return 0
    if [[ "$(hostnamectl --static 2>/dev/null || hostname -s)" != "$original" ]]; then
        hostnamectl set-hostname "$original"
        ok "Original hostname restored: $original"
    fi
}

restore_prejoin_snapshot() {
    local snap="$1" mode="${2:-interactive}"
    [[ -d "$snap" && -r "$snap/snapshot.env" ]] || { err "Invalid snapshot: $snap"; return 1; }
    restore_network "$snap"
    restore_identity "$snap"
    restore_hostname "$snap"
    [[ "$mode" == noninteractive ]] || ok "Pre-join snapshot restored."
}

remove_assistant_packages() {
    local snap="$1" file="$snap/packages-installed-by-assistant.txt"
    [[ -s "$file" ]] || { info "No packages were recorded as newly installed by this assistant."; return 0; }
    mapfile -t pkgs <"$file"
    confirm_literal "Only packages recorded as newly installed for this snapshot will be removed. No autoremove is used." "REMOVE-PACKAGES" || return 0
    dnf remove -y --noautoremove "${pkgs[@]}" || warn "Some recorded packages could not be removed."
}

select_interface() {
    local dns_first="$1" suggested="" line i=0 default=1 choice
    suggested="$(route_iface_for "$dns_first" || true)"
    mapfile -t rows < <(ip -4 -o addr show scope global | awk '{print $2"\t"$4}' | awk -F'\t' '!seen[$1]++')
    ((${#rows[@]})) || { err "No active global IPv4 interface detected."; return 1; }
    if ((${#rows[@]} == 1)); then ACTIVE_IFACE="${rows[0]%%$'\t'*}"; detect_network; return 0; fi

    printf '\nNETWORK INTERFACES\n'
    for line in "${rows[@]}"; do
        ((i+=1)); local iface="${line%%$'\t'*}"; [[ "$iface" == "$suggested" ]] && default="$i"
        printf '  [%d] %s%s\n' "$i" "$line" "$([[ "$iface" == "$suggested" ]] && printf ' <- route to AD DNS')"
    done
    choice="$(ask 'Select interface used for AD' "$default")"
    [[ "$choice" =~ ^[0-9]+$ && "$choice" -ge 1 && "$choice" -le ${#rows[@]} ]] || { err "Invalid interface selection."; return 1; }
    ACTIVE_IFACE="${rows[$((choice-1))]%%$'\t'*}"
    detect_network
    [[ -n "$NM_CONNECTION" ]] || { err "No active NetworkManager connection owns $ACTIVE_IFACE."; return 1; }
}

preflight_dns() {
    local domain="$1" dns_csv="$2" ip srv external failures=0 forward_fail=0
    while IFS= read -r ip; do
        [[ -n "$ip" ]] || continue
        srv="$(dig +time=3 +tries=1 @"$ip" "_ldap._tcp.dc._msdcs.${domain}" SRV +short 2>/dev/null || true)"
        if [[ -z "$srv" ]]; then err "$ip does not answer the AD DC locator SRV query for $domain."; failures=1; continue; fi
        ok "$ip answers the AD DC locator query."
        external="$(dig +time=3 +tries=1 @"$ip" "$EXTERNAL_DNS_PROBE" A +short 2>/dev/null || true)"
        if [[ -n "$external" ]]; then ok "$ip resolves the external probe $EXTERNAL_DNS_PROBE."; else warn "$ip cannot resolve the external probe $EXTERNAL_DNS_PROBE."; forward_fail=1; fi
    done < <(parse_dns_list "$dns_csv")

    ((failures == 0)) || return 1
    if ((forward_fail)); then
        if ((ALLOW_ISOLATED_DNS)); then
            warn "External DNS resolution requirement explicitly waived for this run."
        else
            err "At least one AD DNS lacks external resolution. Refusing to replace the client resolver."
            warn "Repair the AD DNS forwarder or rerun with --allow-isolated-dns only for an intentionally isolated domain."
            return 1
        fi
    fi
}

apply_ad_dns() {
    local domain="$1" dns_csv="$2" dns_space
    [[ -n "$NM_CONNECTION" ]] || { err "NetworkManager connection unavailable."; return 1; }
    dns_space="$(parse_dns_list "$dns_csv" | paste -sd' ' -)"
    ((REMOTE_SESSION)) && warn "Remote session detected: DNS changes preserve IP/routing but can affect hostname-based reconnection."

    nmcli connection modify "$NM_CONNECTION" \
        ipv4.ignore-auto-dns yes \
        ipv4.dns "$dns_space" \
        ipv4.dns-search "$domain,~." \
        ipv4.dns-priority -100
    nmcli connection modify "$NM_CONNECTION" ipv6.ignore-auto-dns yes ipv6.dns-priority -100 || true
    if ! nmcli device reapply "$ACTIVE_IFACE" >/dev/null 2>&1; then
        warn "NetworkManager could not reapply DNS live."
        confirm "Reconnect the connection now? This can interrupt a remote session." N || return 1
        nmcli connection up "$NM_CONNECTION"
    fi
    sleep 1
    dig +time=3 +tries=1 "_ldap._tcp.dc._msdcs.${domain}" SRV +short | grep -q . || { err "System resolver did not converge to AD DNS."; return 1; }
    ok "AD DNS applied through NetworkManager; IP address, gateway and routes were not changed."
}

ad_dc_targets() {
    local domain="$1"
    dig +short "_ldap._tcp.dc._msdcs.${domain}" SRV 2>/dev/null | awk '{gsub(/\.$/,"",$4); print $4}' | awk 'NF&&!seen[$0]++'
}

tcp_probe() {
    local host="$1" port="$2"
    timeout 3 bash -c "</dev/tcp/${host}/${port}" >/dev/null 2>&1
}

network_preflight() {
    local domain="$1" dc="" port fail=0
    dc="$(ad_dc_targets "$domain" | head -n1)"
    [[ -n "$dc" ]] || { err "No domain controller discovered through the active resolver."; return 1; }
    info "Connectivity target: $dc"
    for port in 53 88 389; do
        if tcp_probe "$dc" "$port"; then ok "$dc TCP/$port reachable."; else err "$dc TCP/$port unreachable."; fail=1; fi
    done
    tcp_probe "$dc" 445 && ok "$dc TCP/445 reachable." || warn "$dc TCP/445 (SMB/SYSVOL) is not reachable; basic SSSD join may still work but GPO/SMB workflows can be degraded."
    tcp_probe "$dc" 464 && ok "$dc TCP/464 reachable." || warn "$dc TCP/464 (kpasswd) is not reachable."
    ((fail == 0))
}

kerberos_preflight() {
    local domain="$1" user="$2" realm="${domain^^}"
    if ! timedatectl show -p NTPSynchronized --value 2>/dev/null | grep -Fqx yes; then
        warn "System clock does not report synchronized; Kerberos is time-sensitive."
    fi
    info "Kerberos preflight uses an isolated credential cache; the password is not stored."
    export KRB5CCNAME="FILE:${PRIVATE_KRB5CCACHE}"
    if kinit "${user}@${realm}"; then
        klist -s && ok "Kerberos ticket acquired for ${user}@${realm}." || { err "Kerberos cache validation failed."; return 1; }
        kdestroy >/dev/null 2>&1 || true
        return 0
    fi
    err "Kerberos authentication failed. Verify account, DNS and time synchronization."
    return 1
}

identity_precheck() {
    local found=0
    [[ -s /etc/sssd/sssd.conf ]] && { warn "Existing /etc/sssd/sssd.conf detected."; found=1; }
    [[ -s /etc/krb5.keytab ]] && { warn "Existing /etc/krb5.keytab detected."; found=1; }
    [[ -n "$(realm list --name-only 2>/dev/null || true)" ]] && { warn "realm already reports configured membership."; found=1; }
    ((found == 0)) || confirm "Existing identity configuration will be snapshotted. Continue?" N
}

validate_join() {
    local domain="$1" fail=0
    realm list --name-only 2>/dev/null | grep -Fxiq "$domain" && ok "realmd reports membership in $domain." || { err "realmd does not report membership in $domain."; fail=1; }
    adcli testjoin -D "$domain" >/dev/null 2>&1 && ok "adcli secure-channel test succeeded." || { err "adcli testjoin failed."; fail=1; }
    systemctl is-active --quiet sssd.service && ok "SSSD is active." || { err "SSSD is not active."; fail=1; }
    dig +short "_ldap._tcp.dc._msdcs.${domain}" SRV | grep -q . && ok "AD DC locator works through the system resolver." || { err "AD SRV resolution failed."; fail=1; }

    local probe_user=""
    probe_user="$(ask 'Optional AD user to resolve with getent (blank to skip)' '')" || true
    if [[ -n "$probe_user" ]]; then
        getent passwd "${probe_user}@${domain}" >/dev/null 2>&1 && ok "NSS resolves ${probe_user}@${domain}." || warn "NSS could not resolve ${probe_user}@${domain}."
    fi
    ((fail == 0))
}

join_domain() {
    local domain dns_csv dns_first join_user ou new_host snap prior_phase
    prior_phase="$(state_get PHASE 2>/dev/null || true)"
    if [[ -n "$prior_phase" && ! "$prior_phase" =~ ^(RESTORED|LEFT_RESTORED|RECOVERED_NOT_JOINED|INTERRUPTED_ROLLBACK)$ ]]; then
        err "Assistant lifecycle state is '$prior_phase'. Reconcile it with --recover/--status before starting another join."
        return 1
    fi
    if [[ -n "$(realm list --name-only 2>/dev/null || true)" ]]; then
        err "This host already has configured realm membership. Use --status or leave the current realm first."
        return 1
    fi

    domain="$(ask 'AD DNS domain' '')"; domain="${domain,,}"
    valid_domain "$domain" || { err "Invalid DNS domain."; return 1; }
    dns_csv="$(ask 'AD DNS server(s), comma separated' '')"
    validate_dns_list "$dns_csv" || { err "Invalid IPv4 DNS list."; return 1; }
    dns_first="$(parse_dns_list "$dns_csv" | head -n1)"
    select_interface "$dns_first" || return 1
    identity_precheck || return 1

    new_host="$(ask 'Computer hostname (blank keeps current; AD-safe max 15 chars)' '')"
    if [[ -n "$new_host" && ! "$new_host" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,13}[A-Za-z0-9])?$ ]]; then err "Invalid AD computer hostname; use 1-15 DNS-safe characters."; return 1; fi
    if [[ -z "$new_host" ]]; then
        local current_short="$(hostname -s)"
        if ((${#current_short} > 15)); then
            err "Current short hostname '$current_short' exceeds the conservative 15-character AD computer-name limit."
            return 1
        fi
    fi
    join_user="$(ask 'AD join account' 'Administrator')"
    ou="$(ask 'Optional computer OU DN (blank for default Computers container)' '')"

    snap="$(create_snapshot "$domain" "$ACTIVE_IFACE")"
    TRANSACTION_ACTIVE=1
    TRANSACTION_SNAPSHOT="$snap"
    TRANSACTION_PHASE="STARTED"
    write_state "STARTED" "$snap" "$domain" "$ACTIVE_IFACE"
    write_state "SNAPSHOT_CREATED" "$snap" "$domain" "$ACTIVE_IFACE"

    install_dependencies "$snap" || return 1
    write_state "PACKAGES_READY" "$snap" "$domain" "$ACTIVE_IFACE"

    preflight_dns "$domain" "$dns_csv" || return 1
    write_state "DNS_VALIDATED" "$snap" "$domain" "$ACTIVE_IFACE"

    apply_ad_dns "$domain" "$dns_csv" || return 1
    write_state "DNS_APPLIED" "$snap" "$domain" "$ACTIVE_IFACE"

    if [[ -n "$new_host" && "$new_host" != "$(hostnamectl --static 2>/dev/null || hostname -s)" ]]; then
        hostnamectl set-hostname "$new_host"
        ok "Hostname changed to $new_host before domain join."
    fi

    realm discover --server-software=active-directory "$domain" >/dev/null || { err "realmd could not discover $domain after DNS change."; return 1; }
    network_preflight "$domain" || return 1
    kerberos_preflight "$domain" "$join_user" || return 1
    write_state "DISCOVERED" "$snap" "$domain" "$ACTIVE_IFACE"

    # From this point interruption is ambiguous. Never restore DNS automatically
    # until realm/adcli evidence confirms whether membership committed.
    write_state "JOIN_SUBMITTED" "$snap" "$domain" "$ACTIVE_IFACE"
    TRANSACTION_PHASE="JOIN_SUBMITTED"

    local -a realm_args=(join --client-software=sssd --server-software=active-directory -U "$join_user")
    [[ -n "$ou" ]] && realm_args+=(--computer-ou="$ou")
    realm_args+=("$domain")

    if ! realm "${realm_args[@]}"; then
        RUN_OUTCOME="RECOVERY_REQUIRED"
        warn "realm join returned failure after submission. Membership will be reconciled instead of rolled back blindly."
        recover_transaction "$domain" "$snap" || true
        return 1
    fi

    TRANSACTION_COMMITTED=1
    TRANSACTION_ACTIVE=0
    write_state "JOINED" "$snap" "$domain" "$ACTIVE_IFACE" "$(date -Is)"

    # realm join owns the supported authselect/SSSD integration on RHEL.
    # Do not layer an independent authselect profile mutation on top of it.
    if ! authselect current 2>/dev/null | grep -Fq 'with-mkhomedir'; then
        warn "authselect does not report with-mkhomedir; review home-directory creation policy if interactive AD logins are required."
    fi
    systemctl restart sssd.service >/dev/null 2>&1 || true

    if validate_join "$domain"; then
        write_state "JOINED" "$snap" "$domain" "$ACTIVE_IFACE" "$(date -Is)"
        RUN_OUTCOME="JOINED"
        ok "Domain join completed and validated."
    else
        write_state "JOINED_DEGRADED" "$snap" "$domain" "$ACTIVE_IFACE" "$(date -Is)"
        RUN_OUTCOME="JOINED_DEGRADED"
        warn "AD accepted membership, but post-join validation is degraded. DNS is intentionally preserved."
    fi
}

recover_transaction() {
    local domain="${1:-}" snap="${2:-}"
    if [[ -z "$domain" ]]; then domain="$(state_get DOMAIN 2>/dev/null || true)"; fi
    if [[ -z "$snap" ]]; then snap="$(state_get SNAPSHOT 2>/dev/null || true)"; fi
    [[ -n "$domain" && -d "$snap" ]] || { err "No recoverable transaction state is available."; return 1; }

    printf '\nRECOVERY / MEMBERSHIP RECONCILIATION\n'
    if realm list --name-only 2>/dev/null | grep -Fxiq "$domain" && adcli testjoin -D "$domain" >/dev/null 2>&1; then
        ok "Membership in $domain is committed and the secure channel validates."
        TRANSACTION_COMMITTED=1
        TRANSACTION_ACTIVE=0
        write_state "JOINED" "$snap" "$domain" "$(snapshot_value "$snap" ACTIVE_IFACE)" "$(date -Is)"
        systemctl restart sssd.service >/dev/null 2>&1 || true
        validate_join "$domain" || { write_state "JOINED_DEGRADED" "$snap" "$domain" "$(snapshot_value "$snap" ACTIVE_IFACE)" "$(date -Is)"; return 1; }
        return 0
    fi

    if ! realm list --name-only 2>/dev/null | grep -Fxiq "$domain" && ! adcli testjoin -D "$domain" >/dev/null 2>&1; then
        warn "No committed local realm membership or valid machine secure channel was detected."
        confirm "Restore the pre-join snapshot now?" Y || return 1
        restore_prejoin_snapshot "$snap"
        write_state "RECOVERED_NOT_JOINED" "$snap" "$domain" "$(snapshot_value "$snap" ACTIVE_IFACE)"
        return 0
    fi

    err "Membership evidence is inconsistent: one subsystem reports membership while another does not."
    warn "DNS and identity files are intentionally left unchanged. Repair or perform a controlled realm leave before restore."
    write_state "JOIN_AMBIGUOUS" "$snap" "$domain" "$(snapshot_value "$snap" ACTIVE_IFACE)"
    return 1
}

status_domain() {
    header
    printf 'REALMD\n'
    realm list 2>/dev/null || true
    printf '\nSSSD\n'
    systemctl --no-pager --full status sssd.service 2>/dev/null | sed -n '1,8p' || true
    printf '\nDNS\n'
    nmcli -g IP4.DNS device show "$ACTIVE_IFACE" 2>/dev/null || cat /etc/resolv.conf
    if [[ -r "$CURRENT_STATE" ]]; then
        printf '\nASSISTANT STATE\n'
        sed 's/^/  /' "$CURRENT_STATE"
    fi
}

audit_client() {
    header
    local domain="" fail=0
    domain="$(realm list --name-only 2>/dev/null | head -n1 || true)"
    [[ -n "$domain" ]] && ok "Configured realm: $domain" || warn "No configured realm detected."
    command_exists nmcli && ok "NetworkManager tooling available." || { err "nmcli unavailable."; fail=1; }
    systemctl is-active --quiet NetworkManager.service && ok "NetworkManager active." || { err "NetworkManager inactive."; fail=1; }
    timedatectl show -p NTPSynchronized --value 2>/dev/null | grep -Fqx yes && ok "System clock reports synchronized." || warn "System clock does not report synchronized."
    getenforce 2>/dev/null | grep -Fqx Enforcing && ok "SELinux is enforcing." || warn "SELinux is not enforcing."
    systemctl is-active --quiet firewalld.service && ok "firewalld active." || warn "firewalld is not active."
    if [[ -n "$domain" ]]; then
        adcli testjoin -D "$domain" >/dev/null 2>&1 && ok "Machine secure channel validates." || { err "Machine secure channel validation failed."; fail=1; }
        dig +short "_ldap._tcp.dc._msdcs.${domain}" SRV | grep -q . && ok "AD locator DNS works." || { err "AD locator DNS failed."; fail=1; }
        systemctl is-active --quiet sssd.service && ok "SSSD active." || { err "SSSD inactive."; fail=1; }
    fi
    ((fail == 0))
}

leave_domain() {
    local domain snap leave_user
    domain="$(realm list --name-only 2>/dev/null | head -n1 || true)"
    [[ -n "$domain" ]] || { err "This host is not currently joined according to realmd."; return 1; }
    snap="$(state_get SNAPSHOT 2>/dev/null || true)"
    [[ -d "$snap" ]] || warn "Assistant snapshot is unavailable; post-leave restoration will be limited."
    leave_user="$(ask 'AD account authorized to remove/disable the computer account' 'Administrator')"
    confirm_literal "This leaves the Active Directory domain $domain." "LEAVE" || return 1

    if ! realm leave -U "$leave_user" "$domain"; then
        err "realm leave failed. Local state has not been restored."
        return 1
    fi
    ok "Realm membership removed."

    if [[ -d "$snap" ]]; then
        restore_prejoin_snapshot "$snap"
        write_state "LEFT_RESTORED" "$snap" "$domain" "$(snapshot_value "$snap" ACTIVE_IFACE)"
        if confirm "Remove packages that this assistant originally installed for the join?" N; then remove_assistant_packages "$snap"; fi
    fi
    RUN_OUTCOME="LEFT"
}

restore_mode() {
    local snap phase domain
    snap="$(state_get SNAPSHOT 2>/dev/null || true)"
    phase="$(state_get PHASE 2>/dev/null || true)"
    domain="$(state_get DOMAIN 2>/dev/null || true)"
    [[ -d "$snap" ]] || { err "No current assistant snapshot is available."; return 1; }

    if [[ -n "$domain" ]] && { realm list --name-only 2>/dev/null | grep -Fxiq "$domain" || adcli testjoin -D "$domain" >/dev/null 2>&1; }; then
        err "Membership in $domain still appears active. Refusing to restore pre-join identity/DNS over a joined host."
        warn "Use --leave first, or --recover if the transaction is ambiguous."
        return 1
    fi
    confirm_literal "Restore the complete pre-join snapshot associated with state $phase?" "RESTORE" || return 1
    restore_prejoin_snapshot "$snap"
    write_state "RESTORED" "$snap" "$domain" "$(snapshot_value "$snap" ACTIVE_IFACE)"
}

list_snapshots() {
    printf '%-24s %-30s %-18s %-16s\n' 'SNAPSHOT' 'DOMAIN' 'HOSTNAME' 'INTERFACE'
    local snap domain host iface
    for snap in "$BACKUP_ROOT"/*; do
        [[ -d "$snap" && -r "$snap/snapshot.env" ]] || continue
        domain="$(snapshot_value "$snap" DOMAIN || true)"
        host="$(snapshot_value "$snap" HOSTNAME || true)"
        iface="$(snapshot_value "$snap" ACTIVE_IFACE || true)"
        printf '%-24s %-30s %-18s %-16s\n' "$(basename "$snap")" "$domain" "$host" "$iface"
    done
}


# ---------------------------------------------------------------------------
# RHEL-specific recovery, diagnostics and access controls
# ---------------------------------------------------------------------------

latest_snapshot() {
    local newest="" newest_mtime=0 d m
    for d in "$BACKUP_ROOT"/*; do
        [[ -d "$d" && -r "$d/snapshot.env" ]] || continue
        m="$(stat -c %Y "$d" 2>/dev/null || printf 0)"
        [[ "$m" =~ ^[0-9]+$ ]] || continue
        if ((m > newest_mtime)); then newest_mtime="$m"; newest="$d"; fi
    done
    [[ -n "$newest" ]] || return 1
    printf '%s' "$newest"
}

previous_transaction_notice() {
    [[ -r "$CURRENT_STATE" ]] || return 0
    local phase domain snap
    phase="$(state_get PHASE 2>/dev/null || true)"
    domain="$(state_get DOMAIN 2>/dev/null || true)"
    snap="$(state_get SNAPSHOT 2>/dev/null || true)"
    case "$phase" in
        JOIN_SUBMITTED|JOIN_AMBIGUOUS|JOINED_DEGRADED|STARTED|SNAPSHOT_CREATED|PACKAGES_READY|DNS_VALIDATED|DNS_APPLIED|DISCOVERED)
            printf '\n%bRECOVERY ATTENTION%b\n' "$C_BOLD" "$C_RESET"
            warn "Previous assistant state is $phase for ${domain:-unknown-domain}."
            [[ -d "$snap" ]] && info "Snapshot: $snap"
            if [[ "$MODE" == interactive ]] && confirm "Reconcile the previous transaction now?" Y; then recover_transaction "$domain" "$snap" || true; fi
            ;;
    esac
}

incomplete_identity_residue() {
    local realm_name=""
    realm_name="$(realm list --name-only 2>/dev/null | head -1 || true)"
    [[ -z "$realm_name" ]] || return 1
    [[ -e /etc/sssd/sssd.conf || -e /etc/krb5.keytab ]] || return 1
    if [[ -r "$CURRENT_STATE" ]]; then
        local phase="$(state_get PHASE 2>/dev/null || true)"
        [[ "$phase" =~ ^(JOIN_SUBMITTED|JOIN_AMBIGUOUS|JOINED_DEGRADED|STARTED|SNAPSHOT_CREATED|PACKAGES_READY|DNS_VALIDATED|DNS_APPLIED|DISCOVERED)$ ]] && return 0
    fi
    return 1
}

repair_incomplete_identity_residue() {
    incomplete_identity_residue || return 0
    local snap domain
    snap="$(state_get SNAPSHOT 2>/dev/null || true)"
    [[ -d "$snap" ]] || snap="$(latest_snapshot || true)"
    [[ -d "$snap" ]] || { warn "Identity residue exists but no assistant snapshot is available for safe repair."; return 1; }
    domain="$(snapshot_value "$snap" DOMAIN || true)"
    printf '\nINCOMPLETE IDENTITY RESIDUE\n'
    warn "No active realmd membership is present, but SSSD/keytab state remains from an unfinished lifecycle."
    info "Candidate snapshot: $snap (${domain:-unknown-domain})"
    confirm "Restore identity/network state from this snapshot?" Y || return 1
    restore_prejoin_snapshot "$snap"
    write_state "RECOVERED_NOT_JOINED" "$snap" "$domain" "$(snapshot_value "$snap" ACTIVE_IFACE)"
    ok "Incomplete identity residue repaired from assistant snapshot."
}

client_security_evidence() {
    printf '\nRHEL CLIENT SECURITY EVIDENCE\n'
    printf 'SELinux       : %s\n' "$(getenforce 2>/dev/null || printf unavailable)"
    printf 'Crypto policy : %s\n' "$(update-crypto-policies --show 2>/dev/null || printf unavailable)"
    printf 'FIPS          : %s\n' "$(cat /proc/sys/crypto/fips_enabled 2>/dev/null || printf unknown)"
    printf 'firewalld     : %s\n' "$(systemctl is-active firewalld.service 2>/dev/null || printf unavailable)"
    printf 'NetworkManager: %s\n' "$(systemctl is-active NetworkManager.service 2>/dev/null || printf unavailable)"
    if command_exists ausearch; then
        printf '\nRecent SELinux AVCs mentioning SSSD/Kerberos/realmd\n'
        ausearch -m AVC,USER_AVC -ts recent 2>/dev/null | grep -Ei 'sssd|krb5|realmd|oddjob' | tail -n 60 || true
    fi
    local cp="$(update-crypto-policies --show 2>/dev/null || true)"
    [[ "$cp" == LEGACY* ]] && warn "LEGACY crypto policy broadens cryptographic compatibility system-wide; review why it is enabled."
    [[ "$cp" == *AD-SUPPORT* ]] && info "AD-SUPPORT crypto subpolicy is active. Confirm it is still required by legacy AD cryptography."
}

network_diagnostics() {
    detect_network
    printf '\nNETWORK / DNS DIAGNOSTICS\n'
    printf 'Interface : %s\nConnection: %s\n' "$ACTIVE_IFACE" "${NM_CONNECTION:-unmanaged}"
    ip -brief address show "$ACTIVE_IFACE" 2>/dev/null || true
    ip route 2>/dev/null || true
    if [[ -n "$NM_CONNECTION" ]]; then
        nmcli -f ipv4.method,ipv4.addresses,ipv4.gateway,ipv4.dns,ipv4.dns-search,ipv4.ignore-auto-dns,ipv4.dns-priority connection show "$NM_CONNECTION" 2>/dev/null || true
    fi
    printf '\n/etc/resolv.conf -> %s\n' "$(readlink -f /etc/resolv.conf 2>/dev/null || printf /etc/resolv.conf)"
    sed -n '1,80p' /etc/resolv.conf 2>/dev/null || true
}

sssd_diagnostics() {
    local domain="$(realm list --name-only 2>/dev/null | head -1 || true)"
    printf '\nSSSD / AUTHSELECT DIAGNOSTICS\n'
    authselect current 2>/dev/null || true
    authselect check 2>/dev/null || warn "authselect check reports configuration drift or unavailable state."
    systemctl --no-pager --full status sssd.service 2>/dev/null | sed -n '1,40p' || true
    if command_exists sssctl; then
        sssctl config-check 2>/dev/null || true
        [[ -n "$domain" ]] && sssctl domain-status "$domain" 2>/dev/null || true
    else
        warn "sssctl is unavailable. The optional sssd-tools package provides deeper SSSD diagnostics."
    fi
    printf '\nRecent SSSD journal\n'
    journalctl -u sssd.service -n 120 --no-pager 2>/dev/null || true
}

sssd_gpo_evidence() {
    local domain="$(realm list --name-only 2>/dev/null | head -1 || true)"
    printf '\nSSSD GPO ACCESS-CONTROL EVIDENCE\n'
    if [[ -r /etc/sssd/sssd.conf ]]; then
        grep -En '^[[:space:]]*(access_provider|ad_gpo_|ldap_id_mapping|use_fully_qualified_names|fallback_homedir|default_shell)[[:space:]]*=' /etc/sssd/sssd.conf || true
    fi
    printf '\nRecent GPO-related SSSD messages\n'
    journalctl -u sssd.service --no-pager -n 400 2>/dev/null | grep -Ei 'gpo|access.*denied|policy' | tail -n 100 || true
    [[ -n "$domain" ]] && info "Domain: $domain"
    warn "This view is diagnostic. The assistant does not weaken ad_gpo_access_control automatically to bypass denied logons."
}

user_resolution_test() {
    local domain user
    domain="$(realm list --name-only 2>/dev/null | head -1 || true)"
    [[ -n "$domain" ]] || { err "No configured AD realm."; return 1; }
    user="$(ask 'AD user (without domain or full UPN)' '')"; [[ -n "$user" ]] || return 1
    [[ "$user" == *@* ]] || user="${user}@${domain}"
    getent passwd "$user" && ok "NSS resolves $user." || warn "NSS does not resolve $user."
    id "$user" 2>/dev/null || true
    if command_exists sssctl; then sssctl user-checks "$user" 2>/dev/null || true; fi
}

access_control_menu() {
    local domain user group c
    domain="$(realm list --name-only 2>/dev/null | head -1 || true)"
    [[ -n "$domain" ]] || { err "No configured AD realm."; return 1; }
    while true; do
        printf '\nREALMD LOGIN POLICY\n  [1] Show current realm policy\n  [2] Permit AD user\n  [3] Permit AD group\n  [4] Deny AD user\n  [5] Deny AD group\n  [6] Permit all domain users (broad)\n  [7] Deny all domain users\n  [0] Back\n'
        c="$(ask 'Action' '1')"
        case "$c" in
            1) realm list "$domain" ;;
            2) user="$(ask 'User (user@domain)' '')"; [[ "$user" == *@* ]] || user="${user}@${domain}"; realm permit "$user" ;;
            3) group="$(ask 'Group (group@domain)' '')"; [[ "$group" == *@* ]] || group="${group}@${domain}"; realm permit -g "$group" ;;
            4) user="$(ask 'User (user@domain)' '')"; [[ "$user" == *@* ]] || user="${user}@${domain}"; realm deny "$user" ;;
            5) group="$(ask 'Group (group@domain)' '')"; [[ "$group" == *@* ]] || group="${group}@${domain}"; realm deny -g "$group" ;;
            6) confirm_literal "Permit every domain user to pass the realmd login-policy layer? SSSD/GPO/PAM may still impose controls." "PERMIT-ALL" && realm permit --all ;;
            7) confirm_literal "Deny all domain users through realmd login policy?" "DENY-ALL" && realm deny --all ;;
            0) return 0 ;;
        esac
        pause_ui
    done
}

client_dependency_audit() {
    printf '\nRHEL AD CLIENT DEPENDENCIES\n'
    local pkg ver
    for pkg in realmd oddjob oddjob-mkhomedir sssd sssd-tools adcli krb5-workstation samba-common-tools bind-utils authselect; do
        if rpm -q "$pkg" >/dev/null 2>&1; then ver="$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}' "$pkg")"; printf '  [OK] %-25s %s\n' "$pkg" "$ver"; else printf '  [--] %s\n' "$pkg"; fi
    done
    printf '\nAvailable relevant updates\n'
    dnf -q check-update realmd sssd\* adcli krb5\* samba-common-tools NetworkManager 2>/dev/null | sed -n '1,100p' || true
}

install_optional_diagnostics() {
    rpm -q sssd-tools >/dev/null 2>&1 && { ok "sssd-tools already installed."; return 0; }
    dnf -q list --available sssd-tools >/dev/null 2>&1 || { warn "sssd-tools is not available from configured repositories."; return 1; }
    confirm "Install optional sssd-tools from configured repositories?" Y || return 0
    dnf install -y sssd-tools
}

snapshot_details() {
    local rows selected snap
    rows="$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort -r)"
    [[ -n "$rows" ]] || { warn "No snapshots available."; return 0; }
    printf '\nSNAPSHOTS\n'; nl -w3 -s'  ' <<<"$rows"
    local n="$(ask 'Snapshot number' '1')"; [[ "$n" =~ ^[0-9]+$ ]] || return 1
    selected="$(sed -n "${n}p" <<<"$rows")"; [[ -n "$selected" ]] || return 1
    snap="${BACKUP_ROOT}/${selected}"
    printf '\n%s\n' "$snap"
    sed 's/^/  /' "$snap/snapshot.env" 2>/dev/null || true
    printf '\nFiles captured\n'; cat "$snap/file-manifest.tsv" 2>/dev/null || true
    printf '\nAssistant-installed packages\n'; cat "$snap/packages-installed-by-assistant.txt" 2>/dev/null || true
}

diagnostics_menu() {
    while true; do
        printf '\nDIAGNOSTICS / OPERATIONS\n  [1] Full membership audit\n  [2] Network / DNS\n  [3] SSSD / authselect / journal\n  [4] SSSD GPO evidence\n  [5] Security / SELinux / crypto\n  [6] Resolve/test AD user\n  [7] Dependency audit\n  [8] Install optional sssd-tools\n  [9] Login policy\n  [0] Back\n'
        local c
        c="$(ask 'Action' '1')"
        case "$c" in
            1) audit_client || true ;;
            2) network_diagnostics ;;
            3) sssd_diagnostics ;;
            4) sssd_gpo_evidence ;;
            5) client_security_evidence ;;
            6) user_resolution_test ;;
            7) client_dependency_audit ;;
            8) install_optional_diagnostics ;;
            9) access_control_menu ;;
            0) return 0 ;;
        esac
        pause_ui
    done
}

interactive_menu() {
    previous_transaction_notice
    repair_incomplete_identity_residue || true
    while true; do
        header
        printf '  [1] Readiness / membership audit\n'
        printf '  [2] Guided domain join\n'
        printf '  [3] Status\n'
        printf '  [4] Recover interrupted/ambiguous join\n'
        printf '  [5] Leave domain and restore pre-join state\n'
        printf '  [6] Restore pre-join snapshot (host must not be joined)\n'
        printf '  [7] Snapshot inventory\n'
        printf '  [8] Snapshot details\n'
        printf '  [9] Diagnostics / GPO / access policy\n'
        printf '  [0] Exit\n\n'
        local choice
        choice="$(ask 'Select action' '1')"
        case "$choice" in
            1) audit_client || true; pause_ui ;;
            2) join_domain || true; pause_ui ;;
            3) status_domain; pause_ui ;;
            4) recover_transaction || true; pause_ui ;;
            5) leave_domain || true; pause_ui ;;
            6) restore_mode || true; pause_ui ;;
            7) list_snapshots; pause_ui ;;
            8) snapshot_details; pause_ui ;;
            9) diagnostics_menu ;;
            0) return 0 ;;
            *) warn "Invalid selection."; pause_ui ;;
        esac
    done
}

usage() {
    cat <<EOF_USAGE
$PRODUCT_NAME $SCRIPT_VERSION

Reversible RHEL/Rocky/Alma Active Directory client assistant using the
Red Hat-supported SSSD + realmd + adcli integration path.

Usage: sudo ./rhel-ad-client-assistant.sh [mode] [options]

Modes:
  --manage, --interactive   Interactive lifecycle console (default)
  --audit                   Read-only readiness/membership audit
  --join                    Guided transaction-aware AD join
  --status                  Membership, SSSD and DNS status
  --recover                 Reconcile interrupted/ambiguous join state
  --leave                   Leave AD and restore the assistant snapshot
  --restore                 Restore pre-join snapshot when membership is absent
  --snapshots               List assistant snapshots
  --diagnostics             SSSD/network/GPO/security diagnostics console
  --access                  realmd login-policy console
  --gpo-status              Read-only SSSD GPO evidence
  --dependencies            Package/capability audit

Options:
  --external-dns-probe NAME External DNS name required from every AD DNS
  --allow-isolated-dns      Explicitly allow AD DNS without external resolution
  --no-color                Disable ANSI colors
  -h, --help                Show this help

Safety model:
  - DNS is changed only after every configured AD DNS answers AD locator queries
    and, by default, external forwarding queries.
  - pre-join local changes are automatically reversible.
  - after JOIN_SUBMITTED, membership is reconciled with realmd/adcli evidence;
    DNS/identity state is never rolled back blindly.
  - snapshots include NetworkManager, Kerberos, SSSD, authselect/PAM/NSS and
    package ownership evidence.
  - no third-party repository is added and no domain password is stored.
  - realm join owns authselect/SSSD integration; this assistant does not layer a
    conflicting authselect profile on top of it.
EOF_USAGE
}

parse_args() {
    while (($#)); do
        case "$1" in
            --manage|--interactive) MODE=interactive ;;
            --audit) MODE=audit ;;
            --join) MODE=join ;;
            --status) MODE=status ;;
            --recover) MODE=recover ;;
            --leave) MODE=leave ;;
            --restore) MODE=restore ;;
            --snapshots) MODE=snapshots ;;
            --diagnostics) MODE=diagnostics ;;
            --access) MODE=access ;;
            --gpo-status) MODE=gpo-status ;;
            --dependencies) MODE=dependencies ;;
            --external-dns-probe) shift; [[ $# -gt 0 ]] || { printf 'Missing value for --external-dns-probe\n' >&2; exit 2; }; EXTERNAL_DNS_PROBE="$1" ;;
            --allow-isolated-dns) ALLOW_ISOLATED_DNS=1 ;;
            --no-color) NO_COLOR_FLAG=1 ;;
            -h|--help) usage; exit 0 ;;
            *) printf 'Unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
        esac
        shift
    done
}

main() {
    parse_args "$@"
    if ((NO_COLOR_FLAG)) || [[ ! -t 1 || -n "${NO_COLOR:-}" ]]; then
        C_RESET="" C_BOLD="" C_DIM="" C_RED="" C_GREEN="" C_YELLOW="" C_CYAN=""
    fi
    init_runtime
    case "$MODE" in
        interactive) interactive_menu ;;
        audit) audit_client ;;
        join) join_domain ;;
        status) status_domain ;;
        recover) recover_transaction ;;
        leave) leave_domain ;;
        restore) restore_mode ;;
        snapshots) list_snapshots ;;
        diagnostics) diagnostics_menu ;;
        access) access_control_menu ;;
        gpo-status) sssd_gpo_evidence ;;
        dependencies) client_dependency_audit ;;
        *) err "Internal mode dispatch error: $MODE"; exit 2 ;;
    esac
}

main "$@"
