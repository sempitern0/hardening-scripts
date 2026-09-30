#!/usr/bin/env bash
# linux-ad-client-assistant.sh
# Version 1.0.2
#
# Reversible Active Directory client join assistant for Linux.
#
# Primary supported package families:
#   - Debian / Ubuntu and derivatives using APT
#   - RHEL / Fedora / Rocky / Alma and derivatives using DNF/YUM
#
# Generic mode:
#   - Other distributions can continue when the required commands already exist.
#
# Core design:
#   detect -> snapshot -> packages -> DNS -> discover -> join -> validate
#   leave  -> restore pre-join state -> optional package cleanup
#
# No passwords are stored. No third-party repository is added.

set -uo pipefail
IFS=$'\n\t'

SCRIPT_VERSION="1.0.2"
PRODUCT_NAME="Linux AD Client Assistant"

STATE_ROOT="/var/lib/ad-client-assistant"
BACKUP_ROOT="/var/backups/ad-client-assistant"
LOG_ROOT="/var/log/ad-client-assistant"
CURRENT_STATE="${STATE_ROOT}/current.env"
INPUT_FD=0

USE_COLOR=1
[[ -t 1 && -z "${NO_COLOR:-}" ]] || USE_COLOR=0

if (( USE_COLOR )); then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_CYAN=$'\033[36m'
else
    C_RESET=""
    C_BOLD=""
    C_DIM=""
    C_RED=""
    C_GREEN=""
    C_YELLOW=""
    C_CYAN=""
fi

RUN_ID="$(date +%Y%m%d-%H%M%S)-$$"
RUN_LOG=""
DISTRO_ID=""
DISTRO_LIKE=""
PKG_FAMILY="generic"
ACTIVE_IFACE=""
DNS_BACKEND=""
NM_CONNECTION=""
REMOTE_SESSION=0
HOSTNAME_CHANGED_RESULT=0

# ---------------------------------------------------------------------------
# UI / logging
# ---------------------------------------------------------------------------

init_runtime() {
    (( EUID == 0 )) || {
        printf 'Run this assistant as root (sudo).\n' >&2
        exit 1
    }

    mkdir -p "$STATE_ROOT" "$BACKUP_ROOT" "$LOG_ROOT"
    chmod 0700 "$STATE_ROOT" "$BACKUP_ROOT" "$LOG_ROOT" 2>/dev/null || true

    RUN_LOG="${LOG_ROOT}/${RUN_ID}.log"
    : >"$RUN_LOG"
    chmod 0600 "$RUN_LOG"

    if [[ -r /dev/tty && -w /dev/tty ]]; then
        exec {INPUT_FD}<>/dev/tty
    fi

    [[ -n "${SSH_CONNECTION:-}" || -n "${SSH_CLIENT:-}" ]] && REMOTE_SESSION=1

    detect_os
    detect_active_interface
    detect_dns_backend
}

log() {
    printf '%s %s\n' "$(date -Is)" "$*" >>"$RUN_LOG"
}

info() {
    printf '%b[INFO]%b %s\n' "$C_CYAN" "$C_RESET" "$*"
    log "INFO $*"
}

ok() {
    printf '%b[ OK ]%b %s\n' "$C_GREEN" "$C_RESET" "$*"
    log "OK $*"
}

warn() {
    printf '%b[WARN]%b %s\n' "$C_YELLOW" "$C_RESET" "$*"
    log "WARN $*"
}

err() {
    printf '%b[ERROR]%b %s\n' "$C_RED" "$C_RESET" "$*" >&2
    log "ERROR $*"
}

header() {
    clear 2>/dev/null || true
    printf '%b%s%b\n' "$C_BOLD" "$PRODUCT_NAME" "$C_RESET"
    printf 'Version: %s\n' "$SCRIPT_VERSION"
    printf 'Host   : %s\n' "$(hostname 2>/dev/null || printf unknown)"
    printf 'OS     : %s\n' "${DISTRO_ID:-unknown}"
    printf 'Network: %s / %s\n' "${ACTIVE_IFACE:-unknown}" "${DNS_BACKEND:-unknown}"
    printf '%s\n\n' '------------------------------------------------------------------------'
}

pause_ui() {
    printf '\nPress Enter to continue...' >&${INPUT_FD}
    read -r -u "$INPUT_FD" _ || true
}

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
    [[ "${answer,,}" == "y" || "${answer,,}" == "yes" || "${answer,,}" == "s" || "${answer,,}" == "si" || "${answer,,}" == "sí" ]]
}

confirm_literal() {
    local prompt="$1" literal="$2" answer=""
    printf '%s\nType %s to continue: ' "$prompt" "$literal" >&${INPUT_FD}
    IFS= read -r -u "$INPUT_FD" answer || return 1
    [[ "$answer" == "$literal" ]]
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Platform detection
# ---------------------------------------------------------------------------

detect_os() {
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        DISTRO_ID="${ID:-unknown}"
        DISTRO_LIKE="${ID_LIKE:-}"
    else
        DISTRO_ID="unknown"
        DISTRO_LIKE=""
    fi

    if command_exists apt-get ||
       [[ "$DISTRO_ID" =~ ^(debian|ubuntu|linuxmint|pop)$ ]] ||
       [[ "$DISTRO_LIKE" == *debian* ]]; then
        PKG_FAMILY="apt"
    elif command_exists dnf || command_exists yum ||
         [[ "$DISTRO_ID" =~ ^(rhel|fedora|rocky|almalinux|centos)$ ]] ||
         [[ "$DISTRO_LIKE" == *rhel* || "$DISTRO_LIKE" == *fedora* ]]; then
        PKG_FAMILY="dnf"
    else
        PKG_FAMILY="generic"
    fi
}

detect_active_interface() {
    local routes="" first=""
    routes="$(ip -4 route show default 2>/dev/null || true)"
    first="$(awk 'NR==1{print}' <<<"$routes")"
    ACTIVE_IFACE="$(awk '{
        for(i=1;i<=NF;i++) {
            if($i=="dev") { print $(i+1); break }
        }
    }' <<<"$first")"

    if [[ -z "$ACTIVE_IFACE" ]]; then
        local addrs=""
        addrs="$(ip -4 -o addr show scope global 2>/dev/null || true)"
        ACTIVE_IFACE="$(awk 'NR==1{print $2}' <<<"$addrs")"
    fi
}

detect_dns_backend() {
    DNS_BACKEND="resolv.conf"
    NM_CONNECTION=""

    if command_exists nmcli &&
       systemctl is-active --quiet NetworkManager.service 2>/dev/null &&
       [[ -n "$ACTIVE_IFACE" ]]; then
        local con=""
        con="$(nmcli -g GENERAL.CONNECTION device show "$ACTIVE_IFACE" 2>/dev/null || true)"
        if [[ -n "$con" && "$con" != "--" ]]; then
            DNS_BACKEND="NetworkManager"
            NM_CONNECTION="$con"
            return
        fi
    fi

    if command_exists resolvectl &&
       systemctl is-active --quiet systemd-resolved.service 2>/dev/null; then
        DNS_BACKEND="systemd-resolved"
        return
    fi
}

# ---------------------------------------------------------------------------
# State serialization / snapshots
# ---------------------------------------------------------------------------

write_env_kv() {
    local file="$1" key="$2" value="${3:-}"
    printf '%s=%q\n' "$key" "$value" >>"$file"
}

load_state_file() {
    local file="$1"
    [[ -f "$file" ]] || return 1
    # Values are written with printf %q by this assistant.
    # shellcheck disable=SC1090
    . "$file"
}

snapshot_copy() {
    local src="$1" dest_root="$2"
    [[ -e "$src" || -L "$src" ]] || return 0
    local rel="${src#/}"
    mkdir -p "${dest_root}/files/$(dirname "$rel")"
    cp -a -- "$src" "${dest_root}/files/${rel}"
}

create_prejoin_snapshot() {
    local domain="$1" iface="$2"
    local snap="${BACKUP_ROOT}/${RUN_ID}"
    local meta="${snap}/snapshot.env"

    mkdir -p "$snap/files"
    chmod 0700 "$snap"

    snapshot_copy /etc/resolv.conf "$snap"
    snapshot_copy /etc/krb5.conf "$snap"
    snapshot_copy /etc/sssd/sssd.conf "$snap"
    snapshot_copy /etc/nsswitch.conf "$snap"
    snapshot_copy /etc/pam.d/common-session "$snap"
    snapshot_copy /etc/pam.d/common-session-noninteractive "$snap"
    snapshot_copy /etc/systemd/resolved.conf.d/90-ad-client-assistant.conf "$snap"

    : >"$meta"
    write_env_kv "$meta" SNAPSHOT_VERSION "1"
    write_env_kv "$meta" SNAPSHOT_PATH "$snap"
    write_env_kv "$meta" CREATED_AT "$(date -Is)"
    write_env_kv "$meta" DOMAIN "$domain"
    write_env_kv "$meta" OLD_HOSTNAME "$(hostnamectl --static 2>/dev/null || hostname)"
    write_env_kv "$meta" ACTIVE_IFACE "$iface"
    write_env_kv "$meta" DNS_BACKEND "$DNS_BACKEND"
    write_env_kv "$meta" PKG_FAMILY "$PKG_FAMILY"
    write_env_kv "$meta" NM_CONNECTION "$NM_CONNECTION"
    write_env_kv "$meta" REMOTE_SESSION "$REMOTE_SESSION"

    if [[ "$DNS_BACKEND" == "NetworkManager" && -n "$NM_CONNECTION" ]]; then
        write_env_kv "$meta" NM_IPV4_IGNORE_AUTO_DNS \
            "$(nmcli -g ipv4.ignore-auto-dns connection show "$NM_CONNECTION" 2>/dev/null || true)"
        write_env_kv "$meta" NM_IPV4_DNS \
            "$(nmcli -g ipv4.dns connection show "$NM_CONNECTION" 2>/dev/null || true)"
        write_env_kv "$meta" NM_IPV4_DNS_SEARCH \
            "$(nmcli -g ipv4.dns-search connection show "$NM_CONNECTION" 2>/dev/null || true)"
        write_env_kv "$meta" NM_IPV6_IGNORE_AUTO_DNS \
            "$(nmcli -g ipv6.ignore-auto-dns connection show "$NM_CONNECTION" 2>/dev/null || true)"
        write_env_kv "$meta" NM_IPV6_DNS \
            "$(nmcli -g ipv6.dns connection show "$NM_CONNECTION" 2>/dev/null || true)"
        write_env_kv "$meta" NM_IPV6_DNS_SEARCH \
            "$(nmcli -g ipv6.dns-search connection show "$NM_CONNECTION" 2>/dev/null || true)"
    fi

    if command_exists authselect; then
        local authselect_state=""
        authselect_state="$(authselect current 2>/dev/null || true)"
        printf '%s\n' "$authselect_state" >"${snap}/authselect-before.txt"
        if grep -Fq 'with-mkhomedir' <<<"$authselect_state"; then
            write_env_kv "$meta" AUTHSELECT_HAD_MKHOMEDIR "1"
        else
            write_env_kv "$meta" AUTHSELECT_HAD_MKHOMEDIR "0"
        fi
    fi

    printf '%s\n' "$snap"
}

restore_snapshot_file() {
    local snap="$1" target="$2"
    local stored="${snap}/files/${target#/}"

    if [[ -e "$stored" || -L "$stored" ]]; then
        rm -rf -- "$target"
        mkdir -p "$(dirname "$target")"
        cp -a -- "$stored" "$target"
    else
        rm -rf -- "$target"
    fi
}

record_current_state() {
    local snap="$1" domain="$2" realm="$3" iface="$4" dns_csv="$5" hostname_changed="$6"
    : >"$CURRENT_STATE"
    chmod 0600 "$CURRENT_STATE"
    write_env_kv "$CURRENT_STATE" SNAPSHOT_PATH "$snap"
    write_env_kv "$CURRENT_STATE" DOMAIN "$domain"
    write_env_kv "$CURRENT_STATE" REALM "$realm"
    write_env_kv "$CURRENT_STATE" ACTIVE_IFACE "$iface"
    write_env_kv "$CURRENT_STATE" AD_DNS_SERVERS "$dns_csv"
    write_env_kv "$CURRENT_STATE" HOSTNAME_CHANGED "$hostname_changed"
    write_env_kv "$CURRENT_STATE" JOINED_AT "$(date -Is)"
}

# ---------------------------------------------------------------------------
# Package management
# ---------------------------------------------------------------------------

required_packages() {
    case "$PKG_FAMILY" in
        apt)
            printf '%s\n' \
                realmd \
                sssd-ad \
                sssd-tools \
                adcli \
                krb5-user \
                libnss-sss \
                libpam-sss \
                dnsutils
            ;;
        dnf)
            printf '%s\n' \
                realmd \
                sssd \
                adcli \
                krb5-workstation \
                oddjob \
                oddjob-mkhomedir \
                samba-common-tools \
                bind-utils
            ;;
        *)
            return 0
            ;;
    esac
}

pkg_installed() {
    local pkg="$1"
    case "$PKG_FAMILY" in
        apt)
            local status=""
            status="$(dpkg-query -W -f='${db:Status-Abbrev}' "$pkg" 2>/dev/null || true)"
            [[ "$status" == "ii " ]]
            ;;
        dnf)
            rpm -q "$pkg" >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

install_required_packages() {
    local snap="$1"
    local -a required=() missing=()
    mapfile -t required < <(required_packages)

    if [[ "$PKG_FAMILY" == "generic" ]]; then
        warn "Unsupported package family. No repository/package configuration will be changed."
        validate_required_commands
        return $?
    fi

    local pkg
    for pkg in "${required[@]}"; do
        [[ -n "$pkg" ]] || continue
        pkg_installed "$pkg" || missing+=("$pkg")
    done

    printf '%s\n' "${missing[@]}" >"${snap}/packages-installed-by-assistant.txt"

    if ((${#missing[@]} == 0)); then
        ok "Required AD client packages are already installed."
        return 0
    fi

    info "Packages required from the distribution repositories:"
    printf '  %s\n' "${missing[@]}"

    confirm "Install these packages from the currently configured official/system repositories?" Y ||
        return 1

    case "$PKG_FAMILY" in
        apt)
            apt-get update || {
                err "apt-get update failed."
                return 1
            }
            DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${missing[@]}" || {
                err "APT package installation failed."
                return 1
            }
            ;;
        dnf)
            local pm="dnf"
            command_exists dnf || pm="yum"
            "$pm" install -y "${missing[@]}" || {
                err "$pm package installation failed."
                return 1
            }
            ;;
    esac

    validate_required_commands
}

validate_required_commands() {
    local -a commands=(realm adcli kinit klist getent)
    local missing=0 cmd
    for cmd in "${commands[@]}"; do
        if command_exists "$cmd"; then
            ok "Command available: $cmd"
        else
            err "Missing required command: $cmd"
            missing=1
        fi
    done

    command_exists dig || warn "dig is unavailable; DNS validation will be reduced."
    (( missing == 0 ))
}

remove_assistant_packages() {
    local snap="$1"
    local file="${snap}/packages-installed-by-assistant.txt"
    [[ -s "$file" ]] || {
        info "No packages were recorded as newly installed by this assistant."
        return 0
    }

    local -a pkgs=()
    mapfile -t pkgs <"$file"
    ((${#pkgs[@]})) || return 0

    printf '\nPackages originally added by the assistant:\n'
    printf '  %s\n' "${pkgs[@]}"

    confirm_literal \
        "Package removal can also remove dependent packages. No autoremove will be executed." \
        "REMOVE-PACKAGES" || return 0

    case "$PKG_FAMILY" in
        apt)
            apt-get remove -y "${pkgs[@]}" || {
                warn "APT could not remove every recorded package."
                return 1
            }
            ;;
        dnf)
            local pm="dnf"
            command_exists dnf || pm="yum"
            "$pm" remove -y "${pkgs[@]}" || {
                warn "$pm could not remove every recorded package."
                return 1
            }
            ;;
        *)
            warn "Package removal is not automated for this package family."
            return 1
            ;;
    esac
}

# ---------------------------------------------------------------------------
# DNS / network
# ---------------------------------------------------------------------------

parse_dns_csv() {
    local raw="$1"
    tr ',;' '  ' <<<"$raw" |
        awk '{
            for(i=1;i<=NF;i++) print $i
        }'
}

valid_ip() {
    # Keep the baseline dependency-free. The assistant currently accepts
    # IPv4 DNS servers because IPv4 is the primary interoperability path for
    # the supported AD client workflow.
    local ip="$1" a b c d extra
    [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
    IFS='.' read -r a b c d extra <<<"$ip"
    [[ -z "${extra:-}" ]] || return 1

    local octet
    for octet in "$a" "$b" "$c" "$d"; do
        [[ "$octet" =~ ^[0-9]+$ ]] || return 1
        (( 10#$octet >= 0 && 10#$octet <= 255 )) || return 1
    done
}

validate_dns_list() {
    local raw="$1" count=0 ip
    while IFS= read -r ip; do
        [[ -n "$ip" ]] || continue
        valid_ip "$ip" || return 1
        ((count++))
    done < <(parse_dns_csv "$raw")
    (( count >= 1 ))
}

dns_space_list() {
    local raw="$1"
    parse_dns_csv "$raw" | paste -sd' ' -
}

dns_first() {
    local raw="$1"
    parse_dns_csv "$raw" | awk 'NR==1{print}'
}

current_dns_summary() {
    case "$DNS_BACKEND" in
        NetworkManager)
            nmcli -g IP4.DNS device show "$ACTIVE_IFACE" 2>/dev/null || true
            ;;
        systemd-resolved)
            resolvectl dns "$ACTIVE_IFACE" 2>/dev/null || true
            ;;
        *)
            awk '/^[[:space:]]*nameserver[[:space:]]+/{print $2}' /etc/resolv.conf 2>/dev/null || true
            ;;
    esac
}

apply_domain_dns() {
    local domain="$1" dns_csv="$2" iface="$3"
    local dns_space=""
    dns_space="$(dns_space_list "$dns_csv")"

    [[ -n "$dns_space" ]] || {
        err "No DNS servers supplied."
        return 1
    }

    if (( REMOTE_SESSION )); then
        warn "Remote session detected. DNS changes should not interrupt an existing IP-based SSH session,"
        warn "but a bad DNS choice can prevent reconnecting by hostname."
    fi

    case "$DNS_BACKEND" in
        NetworkManager)
            [[ -n "$NM_CONNECTION" ]] || {
                err "NetworkManager connection could not be determined."
                return 1
            }

            nmcli connection modify "$NM_CONNECTION" \
                ipv4.ignore-auto-dns yes \
                ipv4.dns "$dns_space" \
                ipv4.dns-search "$domain" || return 1

            # Prevent DHCP-provided IPv6 resolvers from bypassing AD DNS.
            nmcli connection modify "$NM_CONNECTION" \
                ipv6.ignore-auto-dns yes || true

            if ! nmcli device reapply "$iface" >/dev/null 2>&1; then
                warn "NetworkManager could not reapply DNS live."
                if confirm "Reconnect the NetworkManager connection now? This can interrupt remote sessions." N; then
                    nmcli connection up "$NM_CONNECTION" || return 1
                else
                    return 1
                fi
            fi
            ;;
        systemd-resolved)
            local -a dns_array=()
            mapfile -t dns_array < <(parse_dns_csv "$dns_csv")

            mkdir -p /etc/systemd/resolved.conf.d
            cat >/etc/systemd/resolved.conf.d/90-ad-client-assistant.conf <<EOF
# Managed by Linux AD Client Assistant
[Resolve]
DNS=${dns_space}
Domains=${domain} ~${domain}
EOF
            systemctl restart systemd-resolved.service || return 1
            resolvectl dns "$iface" "${dns_array[@]}" || return 1
            resolvectl domain "$iface" "$domain" "~$domain" || return 1
            resolvectl flush-caches >/dev/null 2>&1 || true
            ;;
        resolv.conf)
            warn "No supported persistent DNS manager was detected."
            warn "The assistant will manage /etc/resolv.conf directly and restore it on rollback."
            confirm "Continue with direct /etc/resolv.conf management?" N || return 1

            rm -f /etc/resolv.conf
            {
                local ip
                while IFS= read -r ip; do
                    [[ -n "$ip" ]] && printf 'nameserver %s\n' "$ip"
                done < <(parse_dns_csv "$dns_csv")
                printf 'search %s\n' "$domain"
                printf 'options timeout:2 attempts:2\n'
            } >/etc/resolv.conf
            chmod 0644 /etc/resolv.conf
            ;;
    esac

    sleep 1
    ok "AD DNS configuration applied via $DNS_BACKEND."
}

restore_network_from_snapshot() {
    local snap="$1"
    local meta="${snap}/snapshot.env"
    [[ -f "$meta" ]] || {
        err "Snapshot metadata missing: $meta"
        return 1
    }

    unset DNS_BACKEND NM_CONNECTION ACTIVE_IFACE
    load_state_file "$meta" || return 1

    case "${DNS_BACKEND:-}" in
        NetworkManager)
            if command_exists nmcli && [[ -n "${NM_CONNECTION:-}" ]]; then
                nmcli connection modify "$NM_CONNECTION" \
                    ipv4.ignore-auto-dns "${NM_IPV4_IGNORE_AUTO_DNS:-no}" \
                    ipv4.dns "${NM_IPV4_DNS:-}" \
                    ipv4.dns-search "${NM_IPV4_DNS_SEARCH:-}" || true

                nmcli connection modify "$NM_CONNECTION" \
                    ipv6.ignore-auto-dns "${NM_IPV6_IGNORE_AUTO_DNS:-no}" \
                    ipv6.dns "${NM_IPV6_DNS:-}" \
                    ipv6.dns-search "${NM_IPV6_DNS_SEARCH:-}" || true

                nmcli device reapply "${ACTIVE_IFACE:-}" >/dev/null 2>&1 || true
            fi
            ;;
        systemd-resolved)
            restore_snapshot_file "$snap" /etc/systemd/resolved.conf.d/90-ad-client-assistant.conf
            systemctl restart systemd-resolved.service >/dev/null 2>&1 || true
            if command_exists resolvectl && [[ -n "${ACTIVE_IFACE:-}" ]]; then
                resolvectl revert "$ACTIVE_IFACE" >/dev/null 2>&1 || true
                resolvectl flush-caches >/dev/null 2>&1 || true
            fi
            ;;
        resolv.conf)
            restore_snapshot_file "$snap" /etc/resolv.conf
            ;;
    esac

    # Re-detect because sourcing the snapshot intentionally overwrote globals.
    detect_active_interface
    detect_dns_backend
    ok "Pre-join DNS/network resolver state restored."
}

# ---------------------------------------------------------------------------
# Domain validation / join
# ---------------------------------------------------------------------------

domain_srv_query() {
    local domain="$1" server="${2:-}" output=""
    command_exists dig || return 1

    if [[ -n "$server" ]]; then
        output="$(dig +time=3 +tries=1 @"$server" \
            "_ldap._tcp.dc._msdcs.${domain}" SRV +short 2>/dev/null || true)"
    else
        output="$(dig +time=3 +tries=1 \
            "_ldap._tcp.dc._msdcs.${domain}" SRV +short 2>/dev/null || true)"
    fi

    printf '%s\n' "$output"
    [[ -n "$output" ]]
}

validate_domain_dns() {
    local domain="$1" dns_csv="$2"
    local first="" direct="" system=""

    first="$(dns_first "$dns_csv")"

    if command_exists dig; then
        direct="$(domain_srv_query "$domain" "$first" || true)"
        if [[ -n "$direct" ]]; then
            ok "Direct AD DNS SRV query succeeded via $first."
        else
            err "The selected DNS server $first did not return AD DC locator SRV records."
            return 1
        fi

        system="$(domain_srv_query "$domain" "" || true)"
        if [[ -n "$system" ]]; then
            ok "System resolver can discover AD DC locator SRV records."
        else
            err "System resolver cannot discover the domain after DNS configuration."
            return 1
        fi
    else
        warn "dig is unavailable; relying on realmd discovery."
    fi

    local discovery=""
    discovery="$(realm discover --server-software=active-directory "$domain" 2>&1 || true)"
    if grep -Fiq 'server-software: active-directory' <<<"$discovery"; then
        ok "realmd discovered Active Directory."
    else
        err "realmd could not discover Active Directory."
        printf '%s\n' "$discovery"
        return 1
    fi

    return 0
}

audit_time_sync() {
    if command_exists timedatectl; then
        local synced=""
        synced="$(timedatectl show -p NTPSynchronized --value 2>/dev/null || true)"
        if [[ "$synced" == "yes" ]]; then
            ok "System time reports synchronized."
        else
            warn "System time is not reporting NTPSynchronized=yes."
            warn "Kerberos is sensitive to clock skew; verify NTP before troubleshooting credentials."
        fi
    fi
}

configure_hostname_if_requested() {
    local requested="$1"
    local old=""

    HOSTNAME_CHANGED_RESULT=0
    old="$(hostnamectl --static 2>/dev/null || hostname)"

    if [[ -z "$requested" || "$requested" == "$old" ]]; then
        return 0
    fi

    if [[ ! "$requested" =~ ^[A-Za-z0-9][A-Za-z0-9.-]{0,62}$ ]]; then
        err "Invalid hostname: $requested"
        return 1
    fi

    confirm "Change hostname from '$old' to '$requested' before joining?" Y || return 1
    hostnamectl set-hostname "$requested" || return 1

    HOSTNAME_CHANGED_RESULT=1
    ok "Hostname changed to $requested."
}

configure_mkhomedir() {
    local snap="$1"

    confirm "Enable automatic home-directory creation for domain users?" Y || return 0

    if [[ "$PKG_FAMILY" == "apt" ]]; then
        local pamfile="/etc/pam.d/common-session"
        if [[ -f "$pamfile" ]] &&
           ! grep -Fq 'pam_mkhomedir.so' "$pamfile"; then
            printf '\nsession required pam_mkhomedir.so skel=/etc/skel/ umask=0022\n' >>"$pamfile"
            ok "pam_mkhomedir enabled in common-session."
        else
            info "pam_mkhomedir already present or common-session unavailable."
        fi
    elif command_exists authselect; then
        if authselect enable-feature with-mkhomedir >/dev/null 2>&1; then
            systemctl enable --now oddjobd.service >/dev/null 2>&1 || true
            ok "authselect with-mkhomedir enabled."
        else
            warn "authselect could not enable with-mkhomedir automatically."
        fi
    else
        warn "Automatic home-directory configuration is not supported on this platform."
    fi
}

apply_access_policy() {
    local domain="$1"
    printf '\nLogin authorization policy:\n'
    printf '  [1] Keep realmd/default policy unchanged\n'
    printf '  [2] Permit one domain user\n'
    printf '  [3] Permit one domain group\n'
    printf '  [4] Permit all domain users (broad access)\n'

    local choice=""
    choice="$(ask 'Select policy' '1')"

    case "$choice" in
        2)
            local user=""
            user="$(ask 'User (for example user@domain)' '')"
            [[ -n "$user" ]] && realm permit "$user"
            ;;
        3)
            local group=""
            group="$(ask 'Group (for example linux-login@domain)' '')"
            [[ -n "$group" ]] && realm permit -g "$group"
            ;;
        4)
            confirm_literal \
                "This allows every domain user to attempt login on this Linux host." \
                "PERMIT-ALL" || return 0
            realm permit --all
            ;;
        *)
            info "Login authorization policy left unchanged."
            ;;
    esac
}

join_domain_guided() {
    header
    printf '%bGUIDED DOMAIN JOIN%b\n\n' "$C_BOLD" "$C_RESET"

    local existing_realms=""
    existing_realms="$(realm list --name-only 2>/dev/null || true)"
    if [[ -n "$existing_realms" ]]; then
        warn "This machine already reports realm membership:"
        printf '%s\n' "$existing_realms"
        return 1
    fi

    printf 'Active interface : %s\n' "${ACTIVE_IFACE:-unknown}"
    printf 'DNS backend      : %s\n' "$DNS_BACKEND"
    printf 'Current DNS      :\n'
    current_dns_summary | sed 's/^/  /'

    local domain="" realm_name="" dns_csv="" join_user="" ou="" requested_hostname=""
    local id_mapping="yes"

    domain="$(ask 'AD DNS domain (for example corp.example.com)' '')"
    [[ "$domain" =~ ^[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] || {
        err "A valid DNS domain is required."
        return 1
    }
    domain="${domain,,}"

    realm_name="$(ask 'Kerberos realm' "${domain^^}")"
    dns_csv="$(ask 'AD DNS server IPv4 addresses (comma separated)' '')"
    validate_dns_list "$dns_csv" || {
        err "At least one valid DNS server IP is required."
        return 1
    }

    requested_hostname="$(ask 'Computer hostname' "$(hostnamectl --static 2>/dev/null || hostname)")"
    join_user="$(ask 'Join account' 'Administrator')"
    ou="$(ask 'Computer OU DN (optional)' '')"

    printf '\nPOSIX identity model:\n'
    printf '  [1] Automatic SSSD SID -> UID/GID mapping (recommended default)\n'
    printf '  [2] Use RFC2307/POSIX attributes already stored in AD\n'
    local map_choice=""
    map_choice="$(ask 'Select identity model' '1')"
    [[ "$map_choice" == "2" ]] && id_mapping="no"

    printf '\nPlan:\n'
    printf '  Domain       : %s\n' "$domain"
    printf '  Realm        : %s\n' "$realm_name"
    printf '  DNS          : %s\n' "$dns_csv"
    printf '  Interface    : %s\n' "$ACTIVE_IFACE"
    printf '  DNS backend  : %s\n' "$DNS_BACKEND"
    printf '  Hostname     : %s\n' "$requested_hostname"
    printf '  Join account : %s\n' "$join_user"
    printf '  OU           : %s\n' "${ou:-(default Computers container)}"
    printf '  ID mapping   : %s\n' "$id_mapping"

    confirm "Create a reversible snapshot and continue?" Y || return 0

    local snap=""
    snap="$(create_prejoin_snapshot "$domain" "$ACTIVE_IFACE")"
    info "Pre-join snapshot: $snap"

    if ! install_required_packages "$snap"; then
        err "Dependency preparation failed. Restoring resolver/network state."
        restore_network_from_snapshot "$snap" || true
        return 1
    fi

    local hostname_changed="0"
    if ! configure_hostname_if_requested "$requested_hostname"; then
        restore_network_from_snapshot "$snap" || true
        return 1
    fi
    hostname_changed="$HOSTNAME_CHANGED_RESULT"

    if ! apply_domain_dns "$domain" "$dns_csv" "$ACTIVE_IFACE"; then
        err "AD DNS configuration failed. Restoring pre-join state."
        restore_network_from_snapshot "$snap" || true
        [[ "$hostname_changed" == "1" ]] &&
            hostnamectl set-hostname "$(bash -c "source '$snap/snapshot.env'; printf '%s' \"\$OLD_HOSTNAME\"")" || true
        return 1
    fi

    audit_time_sync

    if ! validate_domain_dns "$domain" "$dns_csv"; then
        err "Domain discovery failed. Restoring DNS and hostname."
        restore_network_from_snapshot "$snap" || true
        if [[ "$hostname_changed" == "1" ]]; then
            local old=""
            old="$(bash -c "source '$snap/snapshot.env'; printf '%s' \"\$OLD_HOSTNAME\"")"
            [[ -n "$old" ]] && hostnamectl set-hostname "$old" || true
        fi
        return 1
    fi

    printf '\nKerberos/join credentials will be requested interactively by realmd.\n'
    printf 'No password is written to disk.\n\n'

    local -a join_args=(
        join
        --verbose
        --server-software=active-directory
        --client-software=sssd
        "--automatic-id-mapping=${id_mapping}"
        -U "$join_user"
    )

    [[ -n "$ou" ]] && join_args+=("--computer-ou=$ou")
    join_args+=("$domain")

    if ! realm "${join_args[@]}"; then
        err "realm join failed. Rolling back network and hostname."
        restore_network_from_snapshot "$snap" || true
        if [[ "$hostname_changed" == "1" ]]; then
            local old=""
            old="$(bash -c "source '$snap/snapshot.env'; printf '%s' \"\$OLD_HOSTNAME\"")"
            [[ -n "$old" ]] && hostnamectl set-hostname "$old" || true
        fi
        warn "Installed packages are retained. They can be removed later from Restore pre-join state."
        return 1
    fi

    systemctl enable --now sssd.service >/dev/null 2>&1 || true
    configure_mkhomedir "$snap" || true
    apply_access_policy "$domain" || true

    record_current_state "$snap" "$domain" "$realm_name" "$ACTIVE_IFACE" "$dns_csv" "$hostname_changed"

    printf '\nValidation:\n'
    realm list || true

    if adcli testjoin -D "$domain" >/dev/null 2>&1; then
        ok "adcli testjoin passed."
    else
        warn "adcli testjoin did not pass. Review keytab/DNS/time before considering the client healthy."
    fi

    if getent hosts "$domain" >/dev/null 2>&1; then
        ok "System resolver can resolve the domain name."
    else
        info "The domain apex itself has no resolvable host record; this is not necessarily an AD failure."
    fi

    ok "Domain join completed."
    info "Snapshot retained at: $snap"
    info "A reboot is recommended before final login/GPO validation."

    if confirm "Reboot now?" N; then
        systemctl reboot
    fi
}

# ---------------------------------------------------------------------------
# Audit / status / leave / restore
# ---------------------------------------------------------------------------

audit_readiness() {
    header
    printf '%bCLIENT READINESS%b\n\n' "$C_BOLD" "$C_RESET"

    printf 'Distribution    : %s\n' "$DISTRO_ID"
    printf 'Package family  : %s\n' "$PKG_FAMILY"
    printf 'Active interface: %s\n' "${ACTIVE_IFACE:-unknown}"
    printf 'DNS backend     : %s\n' "$DNS_BACKEND"
    printf 'Remote session  : %s\n\n' "$REMOTE_SESSION"

    printf 'Current DNS:\n'
    current_dns_summary | sed 's/^/  /'
    printf '\n'

    validate_required_commands || true
    audit_time_sync

    local realms=""
    realms="$(realm list --name-only 2>/dev/null || true)"
    if [[ -n "$realms" ]]; then
        ok "Realm membership detected: $realms"
    else
        info "No realm membership detected."
    fi

    if [[ -f "$CURRENT_STATE" ]]; then
        ok "Assistant-managed state exists: $CURRENT_STATE"
    else
        info "No assistant-managed join state exists."
    fi
}

status_domain() {
    header
    printf '%bDOMAIN CLIENT STATUS%b\n\n' "$C_BOLD" "$C_RESET"

    realm list 2>/dev/null || info "No realm membership reported."

    if [[ -f "$CURRENT_STATE" ]]; then
        local SNAPSHOT_PATH="" DOMAIN="" REALM="" AD_DNS_SERVERS="" HOSTNAME_CHANGED=""
        load_state_file "$CURRENT_STATE" || true
        printf '\nAssistant state:\n'
        printf '  Domain   : %s\n' "${DOMAIN:-unknown}"
        printf '  Realm    : %s\n' "${REALM:-unknown}"
        printf '  DNS      : %s\n' "${AD_DNS_SERVERS:-unknown}"
        printf '  Snapshot : %s\n' "${SNAPSHOT_PATH:-unknown}"

        if [[ -n "${DOMAIN:-}" ]] && command_exists adcli; then
            if adcli testjoin -D "$DOMAIN" >/dev/null 2>&1; then
                ok "Secure machine join validated by adcli."
            else
                warn "adcli testjoin failed."
            fi
        fi
    fi

    printf '\nResolver:\n'
    current_dns_summary | sed 's/^/  /'
    audit_time_sync
}

restore_identity_files() {
    local snap="$1"
    restore_snapshot_file "$snap" /etc/krb5.conf
    restore_snapshot_file "$snap" /etc/sssd/sssd.conf
    restore_snapshot_file "$snap" /etc/nsswitch.conf
    restore_snapshot_file "$snap" /etc/pam.d/common-session
    restore_snapshot_file "$snap" /etc/pam.d/common-session-noninteractive

    if command_exists authselect &&
       [[ -f "${snap}/snapshot.env" ]]; then
        local AUTHSELECT_HAD_MKHOMEDIR=""
        load_state_file "${snap}/snapshot.env" || true
        if [[ "${AUTHSELECT_HAD_MKHOMEDIR:-0}" == "0" ]]; then
            authselect disable-feature with-mkhomedir >/dev/null 2>&1 || true
        fi
    fi
}

restore_hostname_from_snapshot() {
    local snap="$1"
    local OLD_HOSTNAME=""
    load_state_file "${snap}/snapshot.env" || return 1
    [[ -n "${OLD_HOSTNAME:-}" ]] || return 0

    local current=""
    current="$(hostnamectl --static 2>/dev/null || hostname)"
    if [[ "$current" != "$OLD_HOSTNAME" ]]; then
        hostnamectl set-hostname "$OLD_HOSTNAME" || return 1
        ok "Hostname restored to $OLD_HOSTNAME."
    fi
}

leave_domain_cleanly() {
    header
    printf '%bLEAVE DOMAIN CLEANLY%b\n\n' "$C_BOLD" "$C_RESET"

    local realm_names=""
    realm_names="$(realm list --name-only 2>/dev/null || true)"
    [[ -n "$realm_names" ]] || {
        info "This machine is not reporting realm membership."
        return 0
    }

    local domain=""
    domain="$(awk 'NR==1{print}' <<<"$realm_names")"
    local leave_user=""
    leave_user="$(ask 'Account authorized to remove the computer from AD' 'Administrator')"

    printf '\nDomain: %s\n' "$domain"
    confirm_literal \
        "The machine will leave Active Directory. A reboot will be required." \
        "LEAVE" || return 0

    if ! realm leave -v -U "$leave_user" "$domain"; then
        err "Clean realm leave failed."
        warn "No local rollback was forced, because that can leave a stale AD computer account."
        warn "Use Restore pre-join state only if the domain is unavailable and you accept that risk."
        return 1
    fi

    local snap=""
    if [[ -f "$CURRENT_STATE" ]]; then
        local SNAPSHOT_PATH=""
        load_state_file "$CURRENT_STATE" || true
        snap="${SNAPSHOT_PATH:-}"
    fi

    if [[ -n "$snap" && -d "$snap" ]]; then
        restore_network_from_snapshot "$snap" || warn "DNS restore reported a problem."
        restore_identity_files "$snap"
        restore_hostname_from_snapshot "$snap" || warn "Hostname restore reported a problem."
        rm -f "$CURRENT_STATE"
        ok "Pre-join local state restored."

        if confirm "Also offer removal of packages installed only for the AD client?" N; then
            remove_assistant_packages "$snap" || true
        fi
    else
        warn "No assistant snapshot was found. Domain membership was removed, but local DNS/config was not rewritten."
    fi

    if confirm "Reboot now?" N; then
        systemctl reboot
    fi
}

restore_prejoin_state() {
    header
    printf '%bRESTORE PRE-JOIN STATE%b\n\n' "$C_BOLD" "$C_RESET"

    [[ -f "$CURRENT_STATE" ]] || {
        err "No current assistant state exists."
        return 1
    }

    local SNAPSHOT_PATH="" DOMAIN=""
    load_state_file "$CURRENT_STATE" || return 1
    [[ -n "${SNAPSHOT_PATH:-}" && -d "$SNAPSHOT_PATH" ]] || {
        err "Recorded snapshot is unavailable."
        return 1
    }

    local memberships=""
    memberships="$(realm list --name-only 2>/dev/null || true)"
    if [[ -n "$memberships" ]]; then
        warn "The machine still reports domain membership: $memberships"
        warn "Preferred path: use Leave domain cleanly so the AD computer account is handled properly."
        confirm_literal \
            "Force-local restore may leave a stale computer account in Active Directory." \
            "FORCE-LOCAL-RESTORE" || return 0

        realm leave "${DOMAIN:-}" >/dev/null 2>&1 || true
    fi

    restore_network_from_snapshot "$SNAPSHOT_PATH" || return 1
    restore_identity_files "$SNAPSHOT_PATH"
    restore_hostname_from_snapshot "$SNAPSHOT_PATH" || true

    systemctl restart sssd.service >/dev/null 2>&1 || true
    rm -f "$CURRENT_STATE"

    ok "Local pre-join state restored."
    warn "If a forced local restore was used, check Active Directory for a stale computer account."

    if confirm "Also offer removal of packages installed only for the AD client?" N; then
        remove_assistant_packages "$SNAPSHOT_PATH" || true
    fi
}

list_snapshots() {
    header
    printf '%bSNAPSHOTS%b\n\n' "$C_BOLD" "$C_RESET"

    local dirs=""
    dirs="$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort -r || true)"
    [[ -n "$dirs" ]] || {
        info "No snapshots found."
        return 0
    }

    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        printf '  %s\n' "$name"
    done <<<"$dirs"
}

# ---------------------------------------------------------------------------
# Interactive control plane
# ---------------------------------------------------------------------------

main_menu() {
    while true; do
        header
        printf '%bCLIENT JOIN CONTROL PLANE%b\n\n' "$C_BOLD" "$C_RESET"
        printf '  [1] Readiness audit\n'
        printf '  [2] Guided domain join\n'
        printf '  [3] Domain client status\n'
        printf '  [4] Leave domain cleanly\n'
        printf '  [5] Restore pre-join state\n'
        printf '  [6] List snapshots\n'
        printf '  [0] Exit\n\n'

        local choice=""
        choice="$(ask 'Select operation' '1')" || return 0

        case "$choice" in
            1) audit_readiness || true; pause_ui ;;
            2) join_domain_guided || warn "Join operation did not complete."; pause_ui ;;
            3) status_domain || true; pause_ui ;;
            4) leave_domain_cleanly || warn "Leave operation did not complete."; pause_ui ;;
            5) restore_prejoin_state || warn "Restore operation did not complete."; pause_ui ;;
            6) list_snapshots || true; pause_ui ;;
            0) return 0 ;;
            *) warn "Unknown option."; pause_ui ;;
        esac

        # Functions that source snapshot metadata may overwrite globals.
        detect_os
        detect_active_interface
        detect_dns_backend
    done
}

usage() {
    cat <<EOF
$PRODUCT_NAME v$SCRIPT_VERSION

Usage:
  sudo $0 [mode]

Modes:
  --manage, --interactive   Interactive control plane
  --audit                   Readiness audit
  --join                    Guided domain join
  --status                  Domain client status
  --leave                   Clean domain leave + restore
  --restore                 Restore pre-join local state
  --snapshots               List local snapshots
  --no-color                Disable ANSI color
  --help                    Show this help

State:
  $STATE_ROOT

Recovery snapshots:
  $BACKUP_ROOT

Logs:
  $LOG_ROOT

No password is persisted and no third-party repository is added.
EOF
}

main() {
    local mode="manage"

    while (($#)); do
        case "$1" in
            --manage|--interactive) mode="manage" ;;
            --audit) mode="audit" ;;
            --join) mode="join" ;;
            --status) mode="status" ;;
            --leave) mode="leave" ;;
            --restore) mode="restore" ;;
            --snapshots) mode="snapshots" ;;
            --no-color)
                USE_COLOR=0
                C_RESET="" C_BOLD="" C_DIM="" C_RED="" C_GREEN="" C_YELLOW="" C_CYAN=""
                ;;
            --help|-h)
                usage
                return 0
                ;;
            *)
                printf 'Unknown argument: %s\n\n' "$1" >&2
                usage >&2
                return 2
                ;;
        esac
        shift
    done

    init_runtime

    case "$mode" in
        manage) main_menu ;;
        audit) audit_readiness ;;
        join) join_domain_guided ;;
        status) status_domain ;;
        leave) leave_domain_cleanly ;;
        restore) restore_prejoin_state ;;
        snapshots) list_snapshots ;;
    esac
}

main "$@"
