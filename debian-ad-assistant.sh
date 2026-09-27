#!/usr/bin/env bash
#
# CIP AD Assistant - Debian/Ubuntu
# Version 2.1.0
#
# One-shot interactive bootstrap/audit assistant for a Samba Active Directory
# Domain Controller on Debian-family systems.
#
# Intended invocation:
#   curl -fsSL https://raw.githubusercontent.com/ORG/REPO/main/debian-ad-assistant.sh | sudo bash
#
# Supported targets:
#   - Debian 13 (trixie) and compatible Debian-family releases
#   - Ubuntu 26.04 LTS (and compatible Ubuntu releases)
#
# Design goals:
#   - Audit first.
#   - Never re-provision an existing AD silently.
#   - Interactive confirmation for impactful changes.
#   - Safe with piped stdin (curl | sudo bash): prompts use /dev/tty.
#   - Preserve backups before destructive/configuration changes.
#   - Keep UFW restricted by source network/IP when enabled.
#   - Explicit Kerberos context for GPO administration.
#   - Validate DNS, Kerberos, AD database and SYSVOL before finishing.
#   - Safe to re-run for audit/validation; bootstrap refuses an existing AD.
#
# NOTE:
#   The script does NOT configure a static IP via Netplan/ifupdown/networkd.
#   A Samba AD DC should have a stable IP, but changing network configuration
#   during a remote one-shot run can disconnect the administrator.
#

set -Eeuo pipefail
IFS=$'\n\t'
umask 077

SCRIPT_NAME="CIP AD Assistant"
SCRIPT_VERSION="2.1.0"
STATE_DIR="/var/lib/cip-ad-assistant"
LOG_DIR="/var/log/cip-ad-assistant"
RUN_LOCK="/run/lock/cip-ad-assistant.lock"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${LOG_DIR}/assistant-${TIMESTAMP}.log"
REPORT_FILE="${LOG_DIR}/report-${TIMESTAMP}.txt"
BACKUP_DIR="${STATE_DIR}/backups/${TIMESTAMP}"
BACKUP_SEQ=0
GPO_DIR="${STATE_DIR}/gpo"
CONFIG_FILE="${STATE_DIR}/config.env"

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
NTP_POOL="uk.pool.ntp.org"
ADMIN_USER="Godzilla"
ENABLE_UFW="yes"
ENABLE_GPOS="yes"
DISABLE_BUILTIN_ADMIN="no"

DISTRO_ID=""
DISTRO_LIKE=""
DISTRO_VERSION=""
DISTRO_CODENAME=""

INPUT_FD=""

RESULTS=()
CHANGES=()
WARNINGS=()
FAILURES=()

C_RESET='\033[0m'
C_CYAN='\033[36m'
C_GREEN='\033[32m'
C_YELLOW='\033[33m'
C_RED='\033[31m'
C_MAGENTA='\033[35m'
C_DIM='\033[2m'

mkdir -p "$STATE_DIR" "$LOG_DIR" "$BACKUP_DIR" "$GPO_DIR"
touch "$LOG_FILE" "$REPORT_FILE"
chmod 600 "$LOG_FILE" "$REPORT_FILE"

exec 9>"$RUN_LOCK"
flock -n 9 || {
    echo "Another ${SCRIPT_NAME} instance is already running." >&2
    exit 1
}

# ---------------------------------------------------------------------------
# Runtime / safety
# ---------------------------------------------------------------------------

on_error() {
    local rc=$?
    printf '[FATAL] rc=%s command=%s\n' "$rc" "$BASH_COMMAND" >> "$LOG_FILE" || true
    printf '\n%s\n' "Assistant stopped. Review: $LOG_FILE" >&2
    exit "$rc"
}
trap on_error ERR

require_root() {
    [[ ${EUID:-$(id -u)} -eq 0 ]] || {
        echo "Run as root, for example:" >&2
        echo "  curl -fsSL <URL> | sudo bash" >&2
        exit 1
    }
}

ensure_prompt_source() {
    # Critical for: curl | sudo bash. Bash consumes stdin for the script itself,
    # so interactive prompts must explicitly read from the controlling TTY.
    if [[ -r /dev/tty ]]; then
        INPUT_FD="/dev/tty"
        return 0
    fi
    echo "Interactive mode requires a controlling /dev/tty." >&2
    echo "Use a local file or run with --audit/--validate for non-interactive checks." >&2
    exit 1
}

log() {
    local level="$1"; shift
    local line="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
    printf '%s\n' "$line" >> "$LOG_FILE"
    case "$level" in
        OK)     printf '%b%s%b\n' "$C_GREEN" "$line" "$C_RESET" ;;
        WARN)   printf '%b%s%b\n' "$C_YELLOW" "$line" "$C_RESET" ;;
        ERROR)  printf '%b%s%b\n' "$C_RED" "$line" "$C_RESET" ;;
        CHANGE) printf '%b%s%b\n' "$C_MAGENTA" "$line" "$C_RESET" ;;
        DEBUG)  printf '%b%s%b\n' "$C_DIM" "$line" "$C_RESET" ;;
        *)      printf '%s\n' "$line" ;;
    esac
}

section() {
    local title="$1"
    printf '\n%b%s%b\n' "$C_CYAN" '============================================================================== ' "$C_RESET"
    printf '%b %s%b\n' "$C_CYAN" "$title" "$C_RESET"
    printf '%b%s%b\n' "$C_CYAN" '============================================================================== ' "$C_RESET"
}

result() {
    local status="$1" name="$2" current="$3" expected="${4:-}"
    RESULTS+=("${status}|${name}|${current}|${expected}")
    case "$status" in
        PASS) printf '%b[PASS]%b %-38s %s\n' "$C_GREEN" "$C_RESET" "$name" "$current" ;;
        WARN) printf '%b[WARN]%b %-38s %s\n' "$C_YELLOW" "$C_RESET" "$name" "$current" ;;
        FAIL) printf '%b[FAIL]%b %-38s %s\n' "$C_RED" "$C_RESET" "$name" "$current" ;;
        SKIP) printf '%b[SKIP]%b %-38s %s\n' "$C_YELLOW" "$C_RESET" "$name" "$current" ;;
        *)    printf '[INFO] %-38s %s\n' "$name" "$current" ;;
    esac
}

change() { CHANGES+=("$1|${*:2}"); }
warn_msg() { WARNINGS+=("$*"); log WARN "$*"; }
fail_msg() { FAILURES+=("$*"); log ERROR "$*"; }

confirm() {
    local prompt="$1" default="${2:-N}" answer
    while true; do
        if [[ "$default" == "Y" ]]; then
            read -r -p "$prompt [Y/n]: " answer < "$INPUT_FD" || return 1
            answer="${answer:-Y}"
        else
            read -r -p "$prompt [y/N]: " answer < "$INPUT_FD" || return 1
            answer="${answer:-N}"
        fi
        answer="${answer^^}"
        case "$answer" in
            Y|YES) return 0 ;;
            N|NO)  return 1 ;;
        esac
    done
}

ask() {
    local prompt="$1" default="${2:-}" answer
    if [[ -n "$default" ]]; then
        read -r -p "$prompt [$default]: " answer < "$INPUT_FD" || exit 1
        printf '%s' "${answer:-$default}"
    else
        read -r -p "$prompt: " answer < "$INPUT_FD" || exit 1
        printf '%s' "$answer"
    fi
}

ask_secret() {
    local prompt="$1" value
    read -r -s -p "$prompt: " value < "$INPUT_FD" || exit 1
    printf '\n' >&2
    printf '%s' "$value"
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

is_valid_ipv4() {
    local ip="$1" octet
    local -a o
    IFS=. read -r -a o <<< "$ip"
    [[ ${#o[@]} -eq 4 ]] || return 1
    for octet in "${o[@]}"; do
        [[ "$octet" =~ ^[0-9]{1,3}$ ]] || return 1
        (( octet >= 0 && octet <= 255 )) || return 1
    done
}

is_valid_cidr() {
    local cidr="$1" ip prefix
    [[ "$cidr" == */* ]] || return 1
    ip="${cidr%/*}"; prefix="${cidr#*/}"
    is_valid_ipv4 "$ip" || return 1
    [[ "$prefix" =~ ^[0-9]{1,2}$ ]] || return 1
    (( prefix >= 0 && prefix <= 32 ))
}

is_valid_dns_name() {
    [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?\.[A-Za-z]{2,}$ ]]
}

is_valid_netbios() {
    [[ "$1" =~ ^[A-Za-z0-9._-]{1,15}$ ]]
}

primary_iface() { ip route show default 2>/dev/null | awk 'NR==1{print $5}'; }
primary_cidr() { ip -4 -o addr show dev "$1" scope global 2>/dev/null | awk 'NR==1{print $4}'; }
primary_ip() { primary_cidr "$1" | cut -d/ -f1; }
default_gateway() { ip route show default 2>/dev/null | awk 'NR==1{print $3}'; }

domain_dn() {
    printf '%s' "$1" | awk -F. '{for(i=1;i<=NF;i++){printf "DC=%s%s", $i, (i<NF?",":"")}}'
}

netbios_from_domain() {
    printf '%s' "$1" | tr -cd '[:alnum:]' | tr '[:lower:]' '[:upper:]' | cut -c1-15
}

backup_file() {
    local file="$1" dest base
    [[ -e "$file" || -L "$file" ]] || return 0
    BACKUP_SEQ=$((BACKUP_SEQ + 1))
    base="$(basename -- "$file")"
    dest="${BACKUP_DIR}/$(printf '%03d' "$BACKUP_SEQ")-${base}"
    cp -a -- "$file" "$dest"
    log DEBUG "Backup: $file -> $dest"
}

save_config() {
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
        printf 'DISABLE_BUILTIN_ADMIN=%q\n' "$DISABLE_BUILTIN_ADMIN"
    } > "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
}

load_config() {
    [[ -f "$CONFIG_FILE" ]] || return 1
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
    return 0
}

ad_exists() { [[ -f /var/lib/samba/private/sam.ldb ]]; }

ad_dc_configured() {
    [[ -f /etc/samba/smb.conf ]] && grep -Eqi '^\s*server role\s*=\s*active directory domain controller' /etc/samba/smb.conf
}

# ---------------------------------------------------------------------------
# OS detection / packages
# ---------------------------------------------------------------------------

detect_os() {
    section "OPERATING SYSTEM"
    [[ -r /etc/os-release ]] || { echo "Missing /etc/os-release" >&2; exit 1; }
    # shellcheck disable=SC1091
    source /etc/os-release
    DISTRO_ID="$ID"
    DISTRO_LIKE="${ID_LIKE:-}"
    DISTRO_VERSION="${VERSION_ID:-unknown}"
    DISTRO_CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-unknown}}"

    case "$DISTRO_ID" in
        debian|ubuntu) ;;
        *)
            if [[ "$DISTRO_LIKE" == *debian* ]]; then
                warn_msg "Untested Debian derivative detected: $DISTRO_ID. Package/service behavior may differ."
            else
                echo "Unsupported OS: $DISTRO_ID ($DISTRO_LIKE)" >&2
                exit 1
            fi
            ;;
    esac

    result INFO "Distribution" "$PRETTY_NAME" "Debian-family"
    result INFO "Codename" "$DISTRO_CODENAME" "current/stable or supported release"
}

package_available() { apt-cache show "$1" >/dev/null 2>&1; }

install_packages() {
    section "INSTALL REQUIRED PACKAGES"
    apt-get update

    local dns_tools=""
    if package_available bind9-dnsutils; then
        dns_tools="bind9-dnsutils"
    elif package_available dnsutils; then
        dns_tools="dnsutils"
    else
        echo "Cannot find DNS query tools package (bind9-dnsutils/dnsutils)." >&2
        exit 1
    fi

    local pkgs=(samba-ad-dc samba-ad-provision krb5-user chrony acl attr ldb-tools smbclient python3 "$dns_tools")
    if [[ "$ENABLE_UFW" == yes ]] && package_available ufw; then
        pkgs+=(ufw)
    fi

    DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}"
    result PASS "Packages" "Installed/updated" "Samba AD/DC, Kerberos, DNS, Chrony, ACL tooling"
}

configure_samba_services() {
    section "SAMBA AD/DC SERVICE MODEL"
    local unit
    for unit in smbd nmbd winbind; do
        systemctl disable --now "$unit" >/dev/null 2>&1 || true
        systemctl mask "$unit" >/dev/null 2>&1 || true
    done
    systemctl unmask samba-ad-dc >/dev/null 2>&1 || true
    systemctl enable samba-ad-dc >/dev/null
    result PASS "Samba service" "samba-ad-dc enabled" "dedicated AD/DC service"
}

# ---------------------------------------------------------------------------
# Identity / network
# ---------------------------------------------------------------------------

configure_identity() {
    section "DOMAIN / SERVER IDENTITY"

    local iface detected detected_cidr
    iface="$(primary_iface || true)"
    detected="$(primary_ip "$iface" || true)"
    detected_cidr="$(primary_cidr "$iface" || true)"

    DC_HOSTNAME="$(ask 'Short hostname for the DC' "${DC_HOSTNAME:-dc01}")"
    DOMAIN="$(ask 'AD DNS domain' "${DOMAIN:-example.internal}")"
    REALM="$(printf '%s' "$DOMAIN" | tr '[:lower:]' '[:upper:]')"
    DC_FQDN="${DC_HOSTNAME}.${DOMAIN}"
    DC_IP="$(ask 'DC IPv4 address' "${DC_IP:-${detected:-192.168.1.162}}")"
    NETBIOS_DOMAIN="$(ask 'NetBIOS domain' "${NETBIOS_DOMAIN:-$(netbios_from_domain "$DOMAIN")}")"
    NETBIOS_DOMAIN="${NETBIOS_DOMAIN^^}"
    DC_NETBIOS="$(ask 'NetBIOS name of DC' "${DC_NETBIOS:-$(printf '%s' "$DC_HOSTNAME" | tr '[:lower:]' '[:upper:]' | cut -c1-15)}")"
    DC_NETBIOS="${DC_NETBIOS^^}"

    is_valid_dns_name "$DOMAIN" || { echo "Invalid AD DNS domain: $DOMAIN" >&2; exit 1; }
    is_valid_ipv4 "$DC_IP" || { echo "Invalid IPv4: $DC_IP" >&2; exit 1; }
    is_valid_netbios "$NETBIOS_DOMAIN" || { echo "Invalid NetBIOS domain: $NETBIOS_DOMAIN" >&2; exit 1; }
    is_valid_netbios "$DC_NETBIOS" || { echo "Invalid NetBIOS DC name: $DC_NETBIOS" >&2; exit 1; }

    result INFO "Domain" "$DOMAIN" "$DOMAIN"
    result INFO "Kerberos realm" "$REALM" "$REALM"
    result INFO "NetBIOS domain" "$NETBIOS_DOMAIN" "$NETBIOS_DOMAIN"
    result INFO "DC FQDN" "$DC_FQDN" "$DC_FQDN"
    result INFO "DC IP" "$DC_IP" "stable/static IPv4"

    if [[ "$DC_HOSTNAME.$DOMAIN" == "$DOMAIN" ]]; then
        warn_msg "DC hostname equals domain name; choose a distinct hostname for a cleaner FQDN."
    fi

    if [[ -n "$detected_cidr" && "$detected_cidr" != "${DC_IP}/"* ]]; then
        warn_msg "Configured DC IP $DC_IP is not the detected IPv4 on $iface ($detected_cidr)."
    fi
    if ! ip -4 addr show | grep -Fq " ${DC_IP}/"; then
        echo "The configured DC IP $DC_IP is not currently assigned to this server." >&2
        echo "Configure a stable IP before provisioning an AD DC." >&2
        exit 1
    fi

    if [[ "$(hostname -s)" != "$DC_HOSTNAME" ]]; then
        if confirm "Set hostname to $DC_HOSTNAME and update /etc/hosts?" Y; then
            backup_file /etc/hostname
            hostnamectl set-hostname "$DC_HOSTNAME"
            write_hosts
            change APPLIED "Hostname and /etc/hosts configured"
        else
            change SKIPPED "Hostname change"
        fi
    else
        if ! grep -Eq "^[[:space:]]*${DC_IP//./\.}[[:space:]]+${DC_FQDN//./\.}([[:space:]]|$)" /etc/hosts; then
            if confirm "Add $DC_FQDN -> $DC_IP to /etc/hosts?" Y; then
                write_hosts
                change APPLIED "/etc/hosts updated"
            fi
        fi
    fi
}

write_hosts() {
    local begin="# BEGIN CIP-AD-ASSISTANT" end="# END CIP-AD-ASSISTANT" tmp
    backup_file /etc/hosts
    tmp="$(mktemp)"
    trap 'rm -f -- "$tmp"' RETURN
    awk -v begin="$begin" -v end="$end" '
        $0 == begin {skip=1; next}
        $0 == end {skip=0; next}
        !skip {print}
    ' /etc/hosts > "$tmp"
    {
        cat "$tmp"
        printf '%s\n' "$begin"
        printf '%s\t%s %s\n' "$DC_IP" "$DC_FQDN" "$DC_HOSTNAME"
        printf '%s\n' "$end"
    } > /etc/hosts
    rm -f -- "$tmp"
    trap - RETURN
    chmod 644 /etc/hosts
}

# ---------------------------------------------------------------------------
# Time
# ---------------------------------------------------------------------------

configure_time() {
    section "TIME / CHRONY"
    TIMEZONE="$(ask 'Timezone' "${TIMEZONE:-Europe/London}")"
    NTP_POOL="$(ask 'NTP pool/server' "${NTP_POOL:-uk.pool.ntp.org}")"

    timedatectl set-timezone "$TIMEZONE"
    timedatectl set-local-rtc 0 >/dev/null 2>&1 || true

    mkdir -p /etc/chrony/conf.d
    backup_file /etc/chrony/chrony.conf
    cat > /etc/chrony/conf.d/90-cip-ad.conf <<EOF_CHRONY
# Managed by CIP AD Assistant.
# NTP synchronises UTC; timezone controls local display.
pool ${NTP_POOL} iburst maxsources 4
EOF_CHRONY
    if [[ -n "$AD_CLIENT_CIDR" ]]; then
        printf 'allow %s\n' "$AD_CLIENT_CIDR" >> /etc/chrony/conf.d/90-cip-ad.conf
    fi

    systemctl enable --now chrony >/dev/null
    systemctl restart chrony >/dev/null
    chronyc makestep >/dev/null 2>&1 || true

    result PASS "Timezone" "$(timedatectl show -p Timezone --value)" "$TIMEZONE"
    result PASS "Chrony" "$(systemctl is-active chrony)" "active"
}

# ---------------------------------------------------------------------------
# Samba provisioning / DNS / Kerberos
# ---------------------------------------------------------------------------

set_admin_password() {
    echo
    echo "Set the AD Administrator password now." >&2
    echo "The password is entered interactively and is NOT stored by this script." >&2
    samba-tool user setpassword Administrator
}


provision_ad() {
    section "PROVISION SAMBA ACTIVE DIRECTORY"

    if ad_exists; then
        if ad_dc_configured; then
            result PASS "Existing AD" "Detected; provisioning skipped" "preserve existing directory"
            return 0
        fi
        echo "sam.ldb exists but smb.conf is not an AD/DC configuration." >&2
        echo "Manual review required; refusing to continue automatically." >&2
        exit 1
    fi

    if [[ -f /etc/samba/smb.conf ]]; then
        backup_file /etc/samba/smb.conf
        mv /etc/samba/smb.conf "${BACKUP_DIR}/smb.conf.pre-ad"
        change APPLIED "Moved pre-existing smb.conf before AD provisioning"
    fi

    samba-tool domain provision \
        --domain="$NETBIOS_DOMAIN" \
        --realm="$REALM" \
        --server-role=dc \
        --use-rfc2307 \
        --dns-backend=SAMBA_INTERNAL

    result PASS "AD provisioning" "Created ${DOMAIN}" "Samba AD/DC"

    set_admin_password
    result PASS "Administrator password" "Reset interactively; not stored" "known secure password"
}

# Detect an upstream resolver BEFORE replacing the local resolver.
detect_dns_forwarder() {
    local candidates
    if command_exists resolvectl && systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        candidates="$(resolvectl dns 2>/dev/null | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' || true)"
    else
        candidates="$(awk '/^[[:space:]]*nameserver[[:space:]]+/{print $2}' /etc/resolv.conf 2>/dev/null || true)"
    fi
    printf '%s\n' "$candidates" | grep -Ev '^(127\.0\.0\.1|127\.0\.0\.53)$' | head -n1 || true
}

configure_local_resolver() {
    section "DNS / KERBEROS POST-PROVISION"

    if [[ -z "$DNS_FORWARDER" ]]; then
        DNS_FORWARDER="$(detect_dns_forwarder || true)"
        [[ -n "$DNS_FORWARDER" ]] || DNS_FORWARDER="$(ask 'External DNS forwarder' '1.1.1.1')"
    else
        DNS_FORWARDER="$(ask 'External DNS forwarder' "$DNS_FORWARDER")"
    fi
    is_valid_ipv4 "$DNS_FORWARDER" || { echo "Invalid DNS forwarder IP: $DNS_FORWARDER" >&2; exit 1; }

    backup_file /etc/samba/smb.conf
    if grep -Eq '^\s*dns forwarder\s*=' /etc/samba/smb.conf; then
        sed -i -E "s|^\s*dns forwarder\s*=.*|\tdns forwarder = ${DNS_FORWARDER}|" /etc/samba/smb.conf
    else
        sed -i "/^\[global\]/a\\tdns forwarder = ${DNS_FORWARDER}" /etc/samba/smb.conf
    fi
    testparm -s >/dev/null

    local resolver_managed="no"
    local nm_iface="" nm_conn=""

    # Ubuntu's dedicated AD/DC guide disables systemd-resolved and uses Samba DNS directly.
    # Debian normally has no systemd-resolved; NetworkManager/resolver managers can be present.
    if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        if confirm "Disable systemd-resolved and use Samba DNS directly?" Y; then
            systemctl disable --now systemd-resolved
        else
            echo "Cannot safely continue without controlling the host resolver." >&2
            echo "Configure systemd-resolved to use 127.0.0.1 manually, then rerun the validation." >&2
            exit 1
        fi
    fi

    if systemctl is-active --quiet NetworkManager 2>/dev/null; then
        nm_iface="$(primary_iface || true)"
        nm_conn="$(nmcli -g GENERAL.CONNECTION dev show "$nm_iface" 2>/dev/null || true)"
        if [[ -n "$nm_conn" && "$nm_conn" != "--" ]]; then
            if confirm "Configure NetworkManager connection '$nm_conn' to use local Samba DNS 127.0.0.1?" Y; then
                nmcli connection modify "$nm_conn" ipv4.ignore-auto-dns yes ipv4.dns "127.0.0.1"
                nmcli device reapply "$nm_iface" >/dev/null 2>&1 || true
                resolver_managed="yes"
                change APPLIED "NetworkManager DNS -> 127.0.0.1"
            else
                echo "Cannot safely continue while NetworkManager may overwrite /etc/resolv.conf." >&2
                echo "Configure its DNS manually for 127.0.0.1, then rerun validation." >&2
                exit 1
            fi
        fi
    fi

    if [[ "$resolver_managed" != yes ]]; then
        backup_file /etc/resolv.conf
        if [[ -L /etc/resolv.conf ]]; then
            unlink /etc/resolv.conf
        fi
        cat > /etc/resolv.conf <<EOF_RESOLV
nameserver 127.0.0.1
search ${DOMAIN}
EOF_RESOLV
        chmod 644 /etc/resolv.conf
        change APPLIED "/etc/resolv.conf -> Samba DNS"
    fi

    [[ -f /var/lib/samba/private/krb5.conf ]] || { echo "Missing Samba-generated krb5.conf" >&2; exit 1; }
    backup_file /etc/krb5.conf
    cp -f /var/lib/samba/private/krb5.conf /etc/krb5.conf
    chmod 644 /etc/krb5.conf

    systemctl restart samba-ad-dc
    sleep 2

    if ! dig @127.0.0.1 +short -t A "$DC_FQDN" | grep -Fxq "$DC_IP"; then
        echo "Samba DNS did not resolve $DC_FQDN to $DC_IP after resolver configuration." >&2
        exit 1
    fi

    result PASS "DNS forwarder" "$DNS_FORWARDER" "external resolver"
    result PASS "Local resolver" "127.0.0.1" "$DOMAIN"
    result PASS "Kerberos config" "/etc/krb5.conf from Samba" "Samba-generated"
}

# ---------------------------------------------------------------------------
# UFW
# ---------------------------------------------------------------------------

ufw_allow_once() {
    local args=("$@")
    # UFW itself detects duplicate rules and reports success; suppress that noise.
    ufw "${args[@]}" >/dev/null
}

configure_ufw() {
    section "UFW / NETWORK POLICY"
    [[ "$ENABLE_UFW" == yes ]] || { result SKIP "UFW" "Disabled by configuration" "manual review"; return 0; }
    command_exists ufw || { warn_msg "UFW package is unavailable; firewall step skipped."; result WARN "UFW" "Unavailable" "manual firewall configuration"; return 0; }

    local iface route_cidr ssh_ip
    iface="$(primary_iface || true)"
    route_cidr="$(ip -4 route show dev "$iface" proto kernel scope link 2>/dev/null | awk 'NR==1{print $1}')"
    AD_CLIENT_CIDR="$(ask 'AD client source network (CIDR)' "${AD_CLIENT_CIDR:-${route_cidr:-192.168.1.0/24}}")"
    is_valid_cidr "$AD_CLIENT_CIDR" || { echo "Invalid AD client CIDR: $AD_CLIENT_CIDR" >&2; exit 1; }

    if [[ -z "$SSH_SOURCE" ]]; then
        ssh_ip="${SSH_CLIENT%% *}"
        if [[ "$ssh_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            SSH_SOURCE="${ssh_ip}/32"
        else
            SSH_SOURCE="$(ask 'SSH management source (CIDR or IP/32)' "$AD_CLIENT_CIDR")"
        fi
    else
        SSH_SOURCE="$(ask 'SSH management source (CIDR or IP/32)' "$SSH_SOURCE")"
    fi
    is_valid_cidr "$SSH_SOURCE" || { echo "Invalid SSH source: $SSH_SOURCE" >&2; exit 1; }

    echo
    echo "UFW plan:"
    echo "  AD clients : $AD_CLIENT_CIDR"
    echo "  SSH source : $SSH_SOURCE"
    echo "  DC         : $DC_IP"
    echo
    warn_msg "Incoming traffic defaults to DENY. Existing UFW rules are preserved."

    if ! confirm "Apply UFW rules and enable firewall?" Y; then
        result SKIP "UFW" "Not enabled" "manual configuration required"
        return 0
    fi

    # Put the management rule in place before changing the default policy.
    ufw_allow_once allow from "$SSH_SOURCE" to "$DC_IP" port 22 proto tcp
    ufw default deny incoming >/dev/null
    ufw default allow outgoing >/dev/null

    local p
    local tcp_ports=(53 88 135 139 389 445 464 3268)
    local udp_ports=(53 88 123 137 138 389 464)
    for p in "${tcp_ports[@]}"; do
        ufw_allow_once allow from "$AD_CLIENT_CIDR" to "$DC_IP" port "$p" proto tcp
    done
    for p in "${udp_ports[@]}"; do
        ufw_allow_once allow from "$AD_CLIENT_CIDR" to "$DC_IP" port "$p" proto udp
    done
    ufw_allow_once allow from "$AD_CLIENT_CIDR" to "$DC_IP" port 49152:65535 proto tcp
    ufw --force enable >/dev/null

    result PASS "UFW" "active" "default deny inbound"
    result INFO "AD clients" "$AD_CLIENT_CIDR" "restricted"
    result INFO "SSH" "$SSH_SOURCE" "restricted"
}

# ---------------------------------------------------------------------------
# Directory objects
# ---------------------------------------------------------------------------

ensure_kerberos_ticket() {
    local expected="Default principal: ${ADMIN_USER}@${REALM}"
    if klist 2>/dev/null | grep -Fq "$expected"; then
        return 0
    fi
    echo "Kerberos ticket required for ${ADMIN_USER}@${REALM}."
    kinit "${ADMIN_USER}@${REALM}"
    klist >/dev/null
}

ensure_ou() {
    local dn="$1" name="$2"
    if ldbsearch -H /var/lib/samba/private/sam.ldb -b "$dn" -s base dn >/dev/null 2>&1; then
        result PASS "OU=$name" "Already exists" "present"
    else
        samba-tool ou create "$dn" >/dev/null
        result PASS "OU=$name" "Created" "present"
    fi
}

ensure_group() {
    local group="$1"
    if samba-tool group show "$group" >/dev/null 2>&1; then
        result PASS "Group $group" "Already exists" "present"
    else
        samba-tool group add "$group" >/dev/null
        result PASS "Group $group" "Created" "present"
    fi
}

ensure_godzilla() {
    if samba-tool user show "$ADMIN_USER" >/dev/null 2>&1; then
        result PASS "User $ADMIN_USER" "Already exists" "present"
    else
        echo
        echo "Creating AD administrative account: $ADMIN_USER"
        samba-tool user create "$ADMIN_USER"
        result PASS "User $ADMIN_USER" "Created" "present"
    fi

    if ! samba-tool group listmembers "Domain Admins" 2>/dev/null | grep -Fxqi -- "$ADMIN_USER"; then
        samba-tool group addmembers "Domain Admins" "$ADMIN_USER" >/dev/null
    fi
    if ! samba-tool group listmembers AdministradoresTI 2>/dev/null | grep -Fxqi -- "$ADMIN_USER"; then
        samba-tool group addmembers AdministradoresTI "$ADMIN_USER" >/dev/null
    fi
    result PASS "$ADMIN_USER / Domain Admins" "Membership ensured" "administrator"
    result PASS "$ADMIN_USER / AdministradoresTI" "Membership ensured" "custom admin group"

    # Verify Kerberos before offering to disable the built-in account.
    kdestroy >/dev/null 2>&1 || true
    ensure_kerberos_ticket
    result PASS "Kerberos $ADMIN_USER" "Ticket obtained" "authentication works"

    if confirm "Disable the built-in Administrator account now that $ADMIN_USER has a working Kerberos ticket?" N; then
        samba-tool user disable Administrator >/dev/null
        DISABLE_BUILTIN_ADMIN="yes"
        result PASS "Built-in Administrator" "Disabled" "recovery account only"
    else
        DISABLE_BUILTIN_ADMIN="no"
        result INFO "Built-in Administrator" "Left enabled" "disable after successful client test"
    fi
}

configure_directory_objects() {
    section "DIRECTORY STRUCTURE"
    local base_dn
    base_dn="$(domain_dn "$DOMAIN")"
    ensure_ou "OU=Usuarios,${base_dn}" "Usuarios"
    ensure_ou "OU=Equipos,${base_dn}" "Equipos"
    ensure_ou "OU=Grupos,${base_dn}" "Grupos"
    ensure_group Empleados
    ensure_group AdministradoresTI
    ensure_godzilla
}

# ---------------------------------------------------------------------------
# GPO source / management
# ---------------------------------------------------------------------------

write_gpo_sources() {
    cat > "${GPO_DIR}/user-baseline.json" <<'EOF_USER_GPO'
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
EOF_USER_GPO

    cat > "${GPO_DIR}/machine-baseline.json" <<EOF_MACHINE_GPO
[
  {
    "keyname": "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\System",
    "valuename": "LegalNoticeCaption",
    "class": "MACHINE",
    "type": "REG_SZ",
    "data": "${DOMAIN}"
  },
  {
    "keyname": "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\System",
    "valuename": "LegalNoticeText",
    "class": "MACHINE",
    "type": "REG_SZ",
    "data": "Sistema perteneciente al dominio ${DOMAIN}. El acceso esta restringido a usuarios autorizados."
  },
  {
    "keyname": "SOFTWARE\\Policies\\Microsoft\\Windows NT\\DNSClient",
    "valuename": "EnableMulticast",
    "class": "MACHINE",
    "type": "REG_DWORD",
    "data": 0
  }
]
EOF_MACHINE_GPO

    python3 -m json.tool "${GPO_DIR}/user-baseline.json" >/dev/null
    python3 -m json.tool "${GPO_DIR}/machine-baseline.json" >/dev/null
    chmod 600 "${GPO_DIR}/"*.json
    result PASS "GPO source" "JSON files valid" "$GPO_DIR"
}

find_gpo_guid() {
    local name="$1" output
    output="$(samba-tool gpo listall --use-kerberos=required 2>/dev/null || true)"
    printf '%s\n' "$output" | awk -v target="$name" '
        BEGIN { guid="" }
        /^GPO[[:space:]]*:/ { guid=$3 }
        /display name[[:space:]]*:/ {
            sub(/^.*display name[[:space:]]*:[[:space:]]*/, "")
            if ($0 == target) { print guid; exit }
        }
    ' | grep -oE '\{[0-9A-Fa-f-]{36}\}' | head -n1 || true
}

ensure_gpo() {
    local name="$1" output guid
    guid="$(find_gpo_guid "$name")"
    if [[ -n "$guid" ]]; then
        printf '%s' "$guid"
        return 0
    fi
    output="$(samba-tool gpo create "$name" --use-kerberos=required 2>&1)"
    printf '%s\n' "$output" >> "$LOG_FILE"
    guid="$(printf '%s\n' "$output" | grep -oE '\{[0-9A-Fa-f-]{36}\}' | head -n1 || true)"
    [[ -n "$guid" ]] || { printf '%s\n' "$output" >&2; return 1; }
    printf '%s' "$guid"
}

configure_gpos() {
    section "GROUP POLICY OBJECTS"
    [[ "$ENABLE_GPOS" == yes ]] || { result SKIP "GPOs" "Disabled by configuration" "manual administration"; return 0; }

    write_gpo_sources
    echo "A Kerberos ticket for ${ADMIN_USER}@${REALM} is required for GPO administration."
    ensure_kerberos_ticket

    local user_guid machine_guid base_dn
    user_guid="$(ensure_gpo 'CIP - User Baseline')"
    machine_guid="$(ensure_gpo 'CIP - Computer Baseline')"

    # gpo load supports JSON content. {} around the GUID are intentional.
    samba-tool gpo load "$user_guid" --content="${GPO_DIR}/user-baseline.json" --use-kerberos=required >/dev/null
    samba-tool gpo load "$machine_guid" --content="${GPO_DIR}/machine-baseline.json" --use-kerberos=required >/dev/null

    base_dn="$(domain_dn "$DOMAIN")"
    samba-tool gpo setlink "$base_dn" "$user_guid" --use-kerberos=required >/dev/null
    samba-tool gpo setlink "$base_dn" "$machine_guid" --use-kerberos=required >/dev/null

    # Re-validate SYSVOL. Do NOT silently reset ACLs on an existing installation.
    local sysvol_check="${STATE_DIR}/sysvolcheck-${TIMESTAMP}.txt"
    if ! samba-tool ntacl sysvolcheck >"$sysvol_check" 2>&1; then
        warn_msg "SYSVOL/GPO ACL check reported differences; review $sysvol_check."
        if confirm "Run samba-tool ntacl sysvolreset to restore default SYSVOL/GPO ACLs?" N; then
            samba-tool ntacl sysvolreset
            samba-tool ntacl sysvolcheck >/dev/null
            result PASS "SYSVOL ACL repair" "sysvolreset completed" "sysvolcheck clean"
        else
            result WARN "SYSVOL ACL repair" "Skipped" "review before production"
        fi
    else
        result PASS "SYSVOL ACL" "clean after GPO load" "consistent"
    fi

    local acl_check="${STATE_DIR}/gpo-aclcheck-${TIMESTAMP}.txt"
    if ! samba-tool gpo aclcheck >"$acl_check" 2>&1; then
        warn_msg "GPO LDAP/DS ACL consistency check reported differences; inspect $acl_check."
        result WARN "GPO LDAP/DS ACL" "differences reported" "review"
    else
        result PASS "GPO LDAP/DS ACL" "consistent" "matching"
    fi

    cat > "${GPO_DIR}/README.txt" <<EOF_GPO_README
CIP AD Assistant GPOs

User GPO:
  Name: CIP - User Baseline
  GUID: ${user_guid}
  Source: ${GPO_DIR}/user-baseline.json

Computer GPO:
  Name: CIP - Computer Baseline
  GUID: ${machine_guid}
  Source: ${GPO_DIR}/machine-baseline.json

Scope:
  Linked to domain root: ${base_dn}

The sources are registry-based and loaded with samba-tool gpo load.
Domain-root linking is intentionally broad for the lab and is not the same as
security filtering to the Domain Users group.
EOF_GPO_README
    chmod 600 "${GPO_DIR}/README.txt"

    result PASS "User GPO" "$user_guid" "linked to domain root"
    result PASS "Computer GPO" "$machine_guid" "linked to domain root"
}

# ---------------------------------------------------------------------------
# Validation / reporting
# ---------------------------------------------------------------------------

validate_all() {
    section "VALIDATION"
    local base_dn srv ans
    base_dn="$(domain_dn "$DOMAIN")"

    if systemctl is-active --quiet samba-ad-dc; then
        result PASS "samba-ad-dc" "active" "running"
    else
        result FAIL "samba-ad-dc" "inactive" "running"
    fi

    if testparm -s >/dev/null 2>&1; then
        result PASS "smb.conf" "valid" "testparm clean"
    else
        result FAIL "smb.conf" "testparm failed" "valid"
    fi

    if dig @127.0.0.1 +short -t A "$DC_FQDN" | grep -Fxq "$DC_IP"; then
        result PASS "DNS A" "$DC_FQDN -> $DC_IP" "correct"
    else
        result FAIL "DNS A" "unexpected" "$DC_FQDN -> $DC_IP"
    fi

    for srv in _ldap._tcp _kerberos._tcp _kerberos._udp _kpasswd._udp; do
        ans="$(dig @127.0.0.1 +short -t SRV "${srv}.${DOMAIN}" | tr '\n' ' ')"
        if [[ -n "$ans" ]]; then
            result PASS "DNS SRV $srv" "$ans" "present"
        else
            result FAIL "DNS SRV $srv" "no answer" "present"
        fi
    done

    if samba-tool domain info 127.0.0.1 >"${STATE_DIR}/domaininfo-${TIMESTAMP}.txt" 2>&1; then
        result PASS "Domain info" "reachable" "$DOMAIN"
    else
        result FAIL "Domain info" "command failed" "reachable"
    fi

    if samba-tool dbcheck --cross-ncs >"${STATE_DIR}/dbcheck-${TIMESTAMP}.txt" 2>&1; then
        result PASS "AD dbcheck" "completed" "no fatal errors"
    else
        warn_msg "samba-tool dbcheck reported issues; inspect ${STATE_DIR}/dbcheck-${TIMESTAMP}.txt."
        result WARN "AD dbcheck" "reported issues" "review"
    fi

    if samba-tool ntacl sysvolcheck >"${STATE_DIR}/sysvolcheck-${TIMESTAMP}.txt" 2>&1; then
        result PASS "SYSVOL ACL" "clean" "consistent"
    else
        warn_msg "SYSVOL ACL check reported differences; inspect ${STATE_DIR}/sysvolcheck-${TIMESTAMP}.txt."
        result WARN "SYSVOL ACL" "differences reported" "review"
    fi

    if klist >"${STATE_DIR}/klist-${TIMESTAMP}.txt" 2>&1; then
        result PASS "Kerberos" "ccache available" "valid ticket"
    else
        result INFO "Kerberos" "no active ticket cache" "sudo kinit ${ADMIN_USER}@${REALM}"
    fi

    result INFO "Users" "$(samba-tool user list 2>/dev/null | wc -l | tr -d ' ')" "directory objects"
    result INFO "Computers" "$(samba-tool computer list 2>/dev/null | wc -l | tr -d ' ')" "directory objects"
    result INFO "Groups" "$(samba-tool group list 2>/dev/null | wc -l | tr -d ' ')" "directory objects"
    result INFO "GPOs" "$(samba-tool gpo listall 2>/dev/null | grep -cE '\{[0-9A-Fa-f-]{36}\}' || true)" "policy objects"

    if command_exists ufw && ufw status | grep -q 'Status: active'; then
        result PASS "UFW" "active" "reviewed"
    else
        result INFO "UFW" "inactive/unavailable" "review firewall"
    fi
    result INFO "Domain DN" "$base_dn" "$base_dn"
}

write_report() {
    {
        echo "${SCRIPT_NAME} ${SCRIPT_VERSION}"
        echo "Generated: $(date -Is)"
        echo
        echo "=== CONFIG ==="
        printf 'Distribution: %s %s\nDomain: %s\nRealm: %s\nNetBIOS: %s\nDC: %s (%s)\nDC IP: %s\nAD clients: %s\nSSH source: %s\nDNS forwarder: %s\nTimezone: %s\nNTP: %s\n' \
            "$DISTRO_ID" "$DISTRO_VERSION" "$DOMAIN" "$REALM" "$NETBIOS_DOMAIN" "$DC_FQDN" "$DC_NETBIOS" "$DC_IP" "$AD_CLIENT_CIDR" "$SSH_SOURCE" "$DNS_FORWARDER" "$TIMEZONE" "$NTP_POOL"
        echo
        echo "=== RESULTS ==="
        printf '%s\n' "${RESULTS[@]}"
        echo
        echo "=== CHANGES ==="
        printf '%s\n' "${CHANGES[@]}"
        echo
        echo "=== WARNINGS ==="
        printf '%s\n' "${WARNINGS[@]}"
        echo
        echo "=== FAILURES ==="
        printf '%s\n' "${FAILURES[@]}"
        echo
        echo "=== SAMBA DOMAIN INFO ==="
        samba-tool domain info 127.0.0.1 2>&1 || true
        echo
        echo "=== USERS ==="
        samba-tool user list 2>&1 || true
        echo
        echo "=== COMPUTERS ==="
        samba-tool computer list 2>&1 || true
        echo
        echo "=== GROUPS ==="
        samba-tool group list 2>&1 || true
        echo
        echo "=== GPOS ==="
        samba-tool gpo listall 2>&1 || true
        echo
        echo "=== UFW ==="
        ufw status verbose 2>&1 || true
    } > "$REPORT_FILE"
    chmod 600 "$REPORT_FILE"
}

summary() {
    section "FINAL SUMMARY"
    local pass warn fail applied skipped
    pass=$(printf '%s\n' "${RESULTS[@]}" | grep -c '^PASS|' || true)
    warn=$(printf '%s\n' "${RESULTS[@]}" | grep -c '^WARN|' || true)
    fail=$(printf '%s\n' "${RESULTS[@]}" | grep -c '^FAIL|' || true)
    applied=$(printf '%s\n' "${CHANGES[@]}" | grep -c '^APPLIED|' || true)
    skipped=$(printf '%s\n' "${CHANGES[@]}" | grep -c '^SKIPPED|' || true)
    printf '%bPASS :%b %s\n' "$C_GREEN" "$C_RESET" "$pass"
    printf '%bWARN :%b %s\n' "$C_YELLOW" "$C_RESET" "$warn"
    printf '%bFAIL :%b %s\n' "$C_RED" "$C_RESET" "$fail"
    printf '%bApplied:%b %s   %bSkipped:%b %s\n' "$C_MAGENTA" "$C_RESET" "$applied" "$C_YELLOW" "$C_RESET" "$skipped"
    echo
    printf 'Log    : %s\nReport : %s\nConfig : %s\nBackups: %s\nGPOs   : %s\n' "$LOG_FILE" "$REPORT_FILE" "$CONFIG_FILE" "$BACKUP_DIR" "$GPO_DIR"
    if (( fail == 0 )); then
        printf '\n%bNo recorded FAIL results.%b\n' "$C_GREEN" "$C_RESET"
    else
        printf '\n%bReview FAIL results before production use.%b\n' "$C_RED" "$C_RESET"
    fi
}

show_help() {
    cat <<EOF_HELP
${SCRIPT_NAME} v${SCRIPT_VERSION}

Usage:
  sudo bash $0                 Interactive guided setup
  sudo bash $0 --audit         Audit only
  sudo bash $0 --validate      Validate an existing installation
  sudo bash $0 --help          Show this help

One-shot remote usage:
  curl -fsSL <RAW_URL> | sudo bash
  wget -qO- <RAW_URL> | sudo bash

Important:
  - The script does not configure a static network address.
  - Existing AD databases are never re-provisioned automatically.
  - GPO administration uses a root Kerberos ticket for the configured AD admin.
  - UFW is restricted by source network/IP and requires confirmation.
  - Interactive bootstrap requires a controlling TTY.
  - Existing AD databases are refused by the bootstrap path; use --validate.
EOF_HELP
}

main() {
    require_root

    case "${1:-}" in
        --help|-h) show_help; exit 0 ;;
        --audit)
            detect_os
            load_config || true
            if [[ -z "$DOMAIN" ]] && ad_exists; then
                DOMAIN="$(samba-tool domain info 127.0.0.1 2>/dev/null | awk -F': ' '/^Domain:/ {print $2; exit}')"
                REALM="${DOMAIN^^}"
                DC_FQDN="$(hostname -f)"
                DC_HOSTNAME="$(hostname -s)"
                DC_IP="$(primary_ip "$(primary_iface)")"
            fi
            audit_existing
            write_report
            summary
            exit 0
            ;;
        --validate)
            detect_os
            load_config || true
            if [[ -z "$DOMAIN" ]] && ad_exists; then
                DOMAIN="$(samba-tool domain info 127.0.0.1 2>/dev/null | awk -F': ' '/^Domain:/ {print $2; exit}')"
                REALM="${DOMAIN^^}"
                DC_FQDN="$(hostname -f)"
                DC_HOSTNAME="$(hostname -s)"
                DC_IP="$(primary_ip "$(primary_iface)")"
            fi
            [[ -n "$DOMAIN" ]] || { echo "No AD domain detected." >&2; exit 1; }
            validate_all
            write_report
            summary
            exit 0
            ;;
    esac

    ensure_prompt_source
    section "${SCRIPT_NAME} v${SCRIPT_VERSION}"
    echo "Debian/Ubuntu + Samba AD/DC | interactive | audited | safe-bootstrap"
    echo

    detect_os
    audit_existing

    if ad_exists; then
        echo
        echo "An existing Samba AD database was detected." >&2
        echo "For safety, bootstrap will not modify an existing AD installation." >&2
        echo "Use: $0 --validate" >&2
        exit 2
    fi

    echo
    echo "  [1] Guided bootstrap / configure everything"
    echo "  [2] Validate an existing AD/DC"
    echo "  [3] Exit"
    echo

    local choice
    choice="$(ask 'Choice' '1')"
    case "$choice" in
        1)
            confirm "Start the guided setup?" Y || { log INFO "Bootstrap cancelled."; exit 0; }
            configure_identity
            INSTALL_UFW="$(ask 'Enable/configure UFW' "$ENABLE_UFW")"
            [[ "$INSTALL_UFW" =~ ^([Yy]|[Yy][Ee][Ss])$ ]] && ENABLE_UFW=yes || ENABLE_UFW=no
            ENABLE_GPOS="$(ask 'Create and link the baseline GPOs' "$ENABLE_GPOS")"
            [[ "$ENABLE_GPOS" =~ ^([Yy]|[Yy][Ee][Ss])$ ]] && ENABLE_GPOS=yes || ENABLE_GPOS=no
            install_packages
            configure_samba_services
            configure_ufw
            configure_time
            provision_ad
            configure_local_resolver
            configure_directory_objects
            configure_gpos
            validate_all
            save_config
            write_report
            summary
            ;;
        2)
            validate_all
            write_report
            summary
            ;;
        3)
            log INFO "Exit requested."
            ;;
        *)
            echo "Invalid choice." >&2
            exit 2
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Existing-system audit helper (defined after main for readability).
# ---------------------------------------------------------------------------

audit_existing() {
    section "AUDIT / CURRENT STATE"
    local iface cidr gw
    iface="$(primary_iface || true)"
    cidr="$(primary_cidr "$iface" || true)"
    gw="$(default_gateway || true)"
    result INFO "OS" "${PRETTY_NAME:-unknown}" "Debian-family"
    result INFO "Hostname" "$(hostname -f 2>/dev/null || hostname)" "FQDN"
    result INFO "Primary interface" "${iface:-unknown}" "configured"
    result INFO "IPv4" "${cidr:-unknown}" "stable address recommended"
    result INFO "Gateway" "${gw:-unknown}" "configured"
    result "$(ad_exists && echo PASS || echo INFO)" "Samba AD database" "$(ad_exists && echo present || echo not-found)" "AD state"
    result "$(systemctl is-active --quiet samba-ad-dc && echo PASS || echo INFO)" "samba-ad-dc" "$(systemctl is-active samba-ad-dc 2>/dev/null || echo inactive)" "active"
    result "$(systemctl is-active --quiet chrony && echo PASS || echo INFO)" "chrony" "$(systemctl is-active chrony 2>/dev/null || echo inactive)" "active"
    if command_exists ufw; then
        result INFO "UFW" "$(ufw status 2>/dev/null | head -n1)" "reviewed"
    else
        result INFO "UFW" "not installed" "optional"
    fi
}

main "$@"
