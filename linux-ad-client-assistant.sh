#!/usr/bin/env bash
# linux-ad-client-assistant.sh
# Version 1.3.0-it-admin-toolkit
#
# Reversible Active Directory client join assistant for Linux.
#
# Primary supported package families:
#   - Debian / Ubuntu and derivatives using APT
#   - RHEL / Fedora / Rocky / Alma and derivatives using DNF/YUM
#
# Generic mode:
#   - Other systemd distributions can continue when the required commands already exist.
#   - Non-systemd automated lifecycle is intentionally not supported.
#
# Core design:
#   detect -> snapshot -> packages -> DNS -> discover -> join -> validate
#   leave  -> restore pre-join state -> optional package cleanup
#
# No passwords are stored. No third-party repository is added.

set -uo pipefail
IFS=$'\n\t'

SCRIPT_VERSION="1.3.0-it-admin-toolkit"
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
NM_CONNECTION_UUID=""
PRIVATE_KRB5CCACHE="${STATE_ROOT}/krb5cc-${RUN_ID}"
JOIN_COMPUTER_NAME=""
JOIN_REALM_NAME=""
JOIN_TRANSACTION_ACTIVE=0
JOIN_TRANSACTION_COMMITTED=0
JOIN_TRANSACTION_SNAPSHOT=""
JOIN_TRANSACTION_ROLLBACK=0
SYSTEM_RESOLVER_BACKEND=""
RESOLV_CONF_TARGET=""
AD_DNS_FORWARDING_OK=0
UI_LANG="${AD_ASSISTANT_LANG:-en}"
PRESET_DOMAIN=""
PRESET_DNS=""
PRESET_HOSTNAME=""
PRESET_COMPUTER=""
PRESET_OU=""
PRESET_ID_MAPPING=""
PRESET_SWITCH_MODE=0

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
    detect_system_resolver

    trap on_exit_cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
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
    detect_system_resolver
    printf 'Network: %s / config=%s / resolver=%s\n' \
        "${ACTIVE_IFACE:-unknown}" "${DNS_BACKEND:-unknown}" "${SYSTEM_RESOLVER_BACKEND:-unknown}"
    printf '%s\n\n' '------------------------------------------------------------------------'
}

normalize_ui_language() {
    case "${1,,}" in en|es) printf '%s' "${1,,}" ;; *) printf 'en' ;; esac
}

set_ui_language() {
    case "${1,,}" in
        en|es) UI_LANG="${1,,}" ;;
        *) err "Unsupported language: $1 (expected en or es)."; return 1 ;;
    esac
}

toggle_ui_language() {
    [[ "$UI_LANG" == "en" ]] && UI_LANG="es" || UI_LANG="en"
}

ui_text() {
    local t="$1"
    [[ "$UI_LANG" == "es" ]] || { printf '%s' "$t"; return; }
    case "$t" in
        'Press Enter to continue...') printf 'Pulsa Enter para continuar...' ;;
        'Select operation') printf 'Selecciona una operación' ;;
        'Readiness audit') printf 'Auditoría de preparación' ;;
        'Guided domain join') printf 'Unión guiada al dominio' ;;
        'Domain client status') printf 'Estado del cliente de dominio' ;;
        'Leave domain cleanly') printf 'Salir limpiamente del dominio' ;;
        'Switch to another domain') printf 'Cambiar a otro dominio' ;;
        'AD connectivity test') printf 'Prueba de conectividad AD' ;;
        'Troubleshoot / repair') printf 'Diagnóstico / reparación' ;;
        'Export diagnostic bundle') printf 'Exportar paquete de diagnóstico' ;;
        'Restore pre-join state') printf 'Restaurar estado previo a la unión' ;;
        'List snapshots') printf 'Listar snapshots' ;;
        'Language / Idioma') printf 'Idioma / Language' ;;
        'Exit') printf 'Salir' ;;
        'AD DNS domain (for example corp.example.com)') printf 'Dominio DNS de AD (por ejemplo corp.example.com)' ;;
        'AD DNS server IPv4 addresses (comma separated)') printf 'Direcciones IPv4 de los DNS de AD (separadas por comas)' ;;
        'Target AD DNS domain (for example corp.example.com)') printf 'Dominio DNS de AD destino (por ejemplo corp.example.com)' ;;
        'Target AD DNS server IPv4 addresses (comma separated)') printf 'Direcciones IPv4 de los DNS AD destino (separadas por comas)' ;;
        'System hostname') printf 'Hostname del sistema' ;;
        'AD computer name (NetBIOS, max 15 chars)') printf 'Nombre del equipo en AD (NetBIOS, máximo 15 caracteres)' ;;
        'Computer OU DN (optional)') printf 'DN de la OU del equipo (opcional)' ;;
        'Optional domain user for identity lookup validation (blank to skip)') printf 'Usuario de dominio opcional para validar identidad (vacío para omitir)' ;;
        'Reboot now?') printf '¿Reiniciar ahora?' ;;
        *) printf '%s' "$t" ;;
    esac
}

UI_LANG="$(normalize_ui_language "$UI_LANG")"

pause_ui() {
    printf '\n%s' "$(ui_text 'Press Enter to continue...')" >&${INPUT_FD}
    read -r -u "$INPUT_FD" _ || true
}

ask() {
    local prompt="$(ui_text "$1")" default="${2:-}" value=""
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
    local prompt="$(ui_text "$1")" default="${2:-N}" answer="" shown="$default"
    [[ "$UI_LANG" == "es" && "${default^^}" == "Y" ]] && shown="S"
    printf '%s [%s]: ' "$prompt" "$shown" >&${INPUT_FD}
    IFS= read -r -u "$INPUT_FD" answer || return 1
    [[ -n "$answer" ]] || answer="$default"
    [[ "${answer,,}" == "y" || "${answer,,}" == "yes" || "${answer,,}" == "s" || "${answer,,}" == "si" || "${answer,,}" == "sí" ]]
}

confirm_literal() {
    local prompt="$1" literal="$2" answer=""
    if [[ "$UI_LANG" == "es" ]]; then
        printf '%s\nEscribe %s para continuar: ' "$prompt" "$literal" >&${INPUT_FD}
    else
        printf '%s\nType %s to continue: ' "$prompt" "$literal" >&${INPUT_FD}
    fi
    IFS= read -r -u "$INPUT_FD" answer || return 1
    [[ "$answer" == "$literal" ]]
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}


valid_dns_domain() {
    local name="$1" label=""
    local -a labels=()
    (( ${#name} >= 3 && ${#name} <= 253 )) || return 1
    [[ "$name" == *.* && "$name" != .* && "$name" != *. && "$name" != *..* ]] || return 1
    local old_ifs="$IFS"
    IFS='.'
    read -r -a labels <<<"$name"
    IFS="$old_ifs"
    ((${#labels[@]} >= 2)) || return 1
    for label in "${labels[@]}"; do
        (( ${#label} >= 1 && ${#label} <= 63 )) || return 1
        [[ "$label" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || return 1
    done
}

valid_system_hostname() {
    local name="$1" label=""
    local -a labels=()
    (( ${#name} >= 1 && ${#name} <= 64 )) || return 1
    [[ "$name" != .* && "$name" != *. && "$name" != *..* ]] || return 1
    local old_ifs="$IFS"
    IFS='.'
    read -r -a labels <<<"$name"
    IFS="$old_ifs"
    for label in "${labels[@]}"; do
        (( ${#label} >= 1 && ${#label} <= 63 )) || return 1
        [[ "$label" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || return 1
    done
}

valid_ad_computer_name() {
    local name="$1"
    (( ${#name} >= 1 && ${#name} <= 15 )) || return 1
    [[ "$name" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,13}[A-Za-z0-9])?$ ]]
}


current_boot_id() {
    cat /proc/sys/kernel/random/boot_id 2>/dev/null || printf 'unknown'
}

cleanup_private_ccache() {
    if command_exists kdestroy; then
        kdestroy -c "FILE:${PRIVATE_KRB5CCACHE}" >/dev/null 2>&1 || true
    fi
    rm -f -- "$PRIVATE_KRB5CCACHE" >/dev/null 2>&1 || true
}

join_transaction_mark() {
    local snap="$1" phase="$2"
    [[ -n "$snap" && -d "$snap" ]] || return 0
    printf 'PHASE=%q\nUPDATED_AT=%q\nPID=%q\n' \
        "$phase" "$(date -Is)" "$$" >"${snap}/join-transaction.env"
    chmod 0600 "${snap}/join-transaction.env" 2>/dev/null || true
}

on_exit_cleanup() {
    local rc=$?
    cleanup_private_ccache

    if (( JOIN_TRANSACTION_ACTIVE == 1 &&
          JOIN_TRANSACTION_COMMITTED == 0 &&
          JOIN_TRANSACTION_ROLLBACK == 0 )) &&
       [[ -n "$JOIN_TRANSACTION_SNAPSHOT" &&
          -d "$JOIN_TRANSACTION_SNAPSHOT" ]]; then
        JOIN_TRANSACTION_ROLLBACK=1
        JOIN_TRANSACTION_ACTIVE=0

        printf '\n%b[RECOVERY]%b Interrupted pre-membership join detected; restoring local pre-join configuration.\n' \
            "$C_YELLOW" "$C_RESET" >&2
        rollback_failed_join_local_state "$JOIN_TRANSACTION_SNAPSHOT" "noninteractive" || true
        join_transaction_mark "$JOIN_TRANSACTION_SNAPSHOT" "INTERRUPTED_ROLLBACK"
    fi

    return "$rc"
}

latest_assistant_snapshot() {
    local newest="" newest_mtime=0 dir mtime
    [[ -d "$BACKUP_ROOT" ]] || return 1

    for dir in "$BACKUP_ROOT"/*; do
        [[ -d "$dir" && -f "$dir/snapshot.env" ]] || continue
        mtime="$(stat -c '%Y' "$dir" 2>/dev/null || printf 0)"
        if [[ "$mtime" =~ ^[0-9]+$ ]] && (( mtime > newest_mtime )); then
            newest_mtime="$mtime"
            newest="$dir"
        fi
    done

    [[ -n "$newest" ]] || return 1
    printf '%s' "$newest"
}

snapshot_domain() {
    local snap="$1" DOMAIN=""
    [[ -f "$snap/snapshot.env" ]] || return 1
    # shellcheck disable=SC1090
    . "$snap/snapshot.env"
    printf '%s' "${DOMAIN:-}"
}

incomplete_sssd_residue_present() {
    command_exists sss_cache || return 1
    [[ ! -s /etc/sssd/sssd.conf ]] || return 1
    [[ ! -s /var/lib/sss/db/config.ldb ]] || return 1

    local realms=""
    if command_exists realm; then
        realms="$(realm list --name-only 2>/dev/null || true)"
        [[ -z "$realms" ]] || return 1
    fi

    return 0
}

recover_incomplete_previous_join() {
    incomplete_sssd_residue_present || return 0

    local snap="" domain=""
    snap="$(latest_assistant_snapshot || true)"
    [[ -n "$snap" ]] || {
        warn "SSSD tools are installed but SSSD has no configuration database."
        warn "No assistant snapshot is available for automatic recovery."
        return 0
    }

    domain="$(snapshot_domain "$snap" || true)"
    if command_exists adcli && [[ -n "$domain" ]] &&
       adcli testjoin -D "$domain" >/dev/null 2>&1; then
        warn "The machine account still validates against AD, but local SSSD is incomplete."
        warn "Do not remove AD client packages automatically; repair SSSD or perform a clean domain leave."
        return 0
    fi

    printf '\n%bINCOMPLETE PREVIOUS JOIN DETECTED%b\n' "$C_BOLD" "$C_RESET"
    warn "SSSD client tools are installed, but /etc/sssd/sssd.conf and config.ldb are not initialized."
    info "This matches a previous join that stopped before membership completed."
    info "Latest assistant snapshot: $snap"
    printf '\n'
    printf '  [1] Repair local identity state from the snapshot (recommended)\n'
    printf '  [2] Keep the current residue and continue\n'
    printf '  [0] Cancel\n'

    local choice=""
    choice="$(ask 'Recovery action' '1')"
    case "$choice" in
        1)
            restore_identity_files "$snap"
            restore_sssd_runtime_from_snapshot "$snap"

            if [[ -s "$snap/packages-installed-by-assistant.txt" ]]; then
                printf '\n'
                warn "Packages added by the failed attempt are still installed."
                info "Keeping them is useful for an immediate retry, but sss_cache may keep warning until SSSD is configured."
                if confirm "Remove only packages added by that failed attempt and return to the pre-join package baseline?" Y; then
                    remove_assistant_packages_now "$snap" || \
                        warn "Some assistant-installed packages could not be removed."
                fi
            fi

            ok "Incomplete previous join residue repaired."
            ;;
        2)
            warn "Continuing with the previous SSSD residue in place."
            ;;
        0)
            return 1
            ;;
        *)
            warn "Invalid recovery selection."
            return 1
            ;;
    esac
}


require_supported_init() {
    if ! command_exists systemctl || [[ ! -d /run/systemd/system ]]; then
        err "Automated join/leave requires a systemd-based Linux client."
        warn "This build intentionally does not modify OpenRC/runit/SysV identity configuration."
        return 1
    fi
}

route_interface_for_target() {
    local target="$1" route=""
    [[ -n "$target" ]] || return 1
    route="$(ip -4 route get "$target" 2>/dev/null || true)"
    awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}' <<<"$route"
}

active_ipv4_interfaces() {
    local data=""
    data="$(ip -4 -o addr show scope global 2>/dev/null || true)"
    awk '{print $2}' <<<"$data" | awk '!seen[$0]++'
}

show_network_candidates() {
    local iface addr route metric manager
    while IFS= read -r iface; do
        [[ -n "$iface" ]] || continue
        addr="$(ip -4 -o addr show dev "$iface" scope global 2>/dev/null | awk 'NR==1{print $4}')"
        route="$(ip -4 route show default dev "$iface" 2>/dev/null | awk 'NR==1{print}')"
        metric="$(awk '{for(i=1;i<=NF;i++) if($i=="metric"){print $(i+1); exit}}' <<<"$route")"
        [[ -n "$metric" ]] || metric="-"
        manager="kernel"
        if command_exists nmcli && systemctl is-active --quiet NetworkManager.service 2>/dev/null; then
            local state=""
            state="$(nmcli -g GENERAL.STATE device show "$iface" 2>/dev/null || true)"
            [[ -n "$state" ]] && manager="NetworkManager"
        elif command_exists networkctl && systemctl is-active --quiet systemd-networkd.service 2>/dev/null; then
            manager="systemd-networkd"
        fi
        printf '%s\t%s\t%s\t%s\n' "$iface" "${addr:--}" "$metric" "$manager"
    done < <(active_ipv4_interfaces)
}

select_join_interface() {
    local target_ip="${1:-}" suggested="" rows="" count=0

    if [[ -n "$target_ip" ]]; then
        suggested="$(route_interface_for_target "$target_ip" || true)"
    fi
    if [[ -z "$suggested" && $REMOTE_SESSION -eq 1 ]]; then
        local ssh_ip=""
        ssh_ip="${SSH_CLIENT:-}"
        ssh_ip="${ssh_ip%% *}"
        if [[ -z "$ssh_ip" ]]; then
            ssh_ip="${SSH_CONNECTION:-}"
            ssh_ip="${ssh_ip%% *}"
        fi
        [[ -n "$ssh_ip" ]] && suggested="$(route_interface_for_target "$ssh_ip" || true)"
    fi
    [[ -n "$suggested" ]] || suggested="$ACTIVE_IFACE"

    rows="$(show_network_candidates)"
    count="$(awk 'NF{n++}END{print n+0}' <<<"$rows")"
    if (( count == 0 )); then
        err "No active global IPv4 interface was detected."
        return 1
    fi

    if (( count == 1 )); then
        ACTIVE_IFACE="$(awk 'NF{print $1; exit}' <<<"$rows")"
        detect_dns_backend
        return 0
    fi

    printf '\nNETWORK INTERFACES\n'
    local i=0 iface addr metric manager default_choice=1 line
    while IFS=$'\t' read -r iface addr metric manager; do
        [[ -n "$iface" ]] || continue
        ((i++))
        [[ "$iface" == "$suggested" ]] && default_choice="$i"
        printf '  [%d] %-16s %-20s metric=%-6s %s' "$i" "$iface" "$addr" "$metric" "$manager"
        [[ "$iface" == "$suggested" ]] && printf '  <- suggested route'
        printf '\n'
    done <<<"$rows"

    local choice=""
    choice="$(ask 'Select interface used to reach Active Directory' "$default_choice")" || return 1
    [[ "$choice" =~ ^[0-9]+$ ]] || { err "Invalid interface selection."; return 1; }
    ACTIVE_IFACE="$(awk -v n="$choice" 'NF{c++; if(c==n){print $1; exit}}' <<<"$rows")"
    [[ -n "$ACTIVE_IFACE" ]] || { err "Invalid interface selection."; return 1; }

    if [[ -n "$suggested" && "$ACTIVE_IFACE" != "$suggested" ]]; then
        warn "Selected interface '$ACTIVE_IFACE' differs from the kernel route to the AD target ('$suggested')."
        confirm "Continue without changing routing?" N || return 1
    fi

    detect_dns_backend
    ok "Selected AD interface: $ACTIVE_IFACE ($DNS_BACKEND)."
}

identity_precheck() {
    local findings=0
    printf '\nIDENTITY PRECHECK\n'
    if [[ -s /etc/sssd/sssd.conf ]]; then
        warn "Existing /etc/sssd/sssd.conf detected."
        findings=1
    fi
    if [[ -s /etc/krb5.keytab ]]; then
        warn "Existing /etc/krb5.keytab detected. It will be snapshotted before join."
        findings=1
    fi
    if grep -Eq '(^|[[:space:]])sss([[:space:]]|$)' /etc/nsswitch.conf 2>/dev/null; then
        info "NSS already references SSSD."
        findings=1
    fi
    if (( findings )); then
        confirm "Existing identity configuration was found. Continue only after snapshot/review?" N || return 1
    else
        ok "No conflicting pre-existing identity configuration detected."
    fi
}

record_assistant_package() {
    local snap="$1" pkg="$2" file="${snap}/packages-installed-by-assistant.txt"
    touch "$file"
    grep -Fxq "$pkg" "$file" 2>/dev/null || printf '%s\n' "$pkg" >>"$file"
}

set_current_phase() {
    local phase="$1"
    [[ -f "$CURRENT_STATE" ]] || return 1
    local tmp="${CURRENT_STATE}.tmp.$$"
    awk -v q="PHASE=$(printf '%q' "$phase")" '
        BEGIN{done=0}
        /^PHASE=/{if(!done){print q; done=1}; next}
        {print}
        END{if(!done) print q}
    ' "$CURRENT_STATE" >"$tmp" && mv "$tmp" "$CURRENT_STATE"
    chmod 0600 "$CURRENT_STATE"
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
    local preferred="" ssh_ip=""

    if [[ -n "${SSH_CLIENT:-}" || -n "${SSH_CONNECTION:-}" ]]; then
        ssh_ip="${SSH_CLIENT:-}"
        ssh_ip="${ssh_ip%% *}"
        if [[ -z "$ssh_ip" ]]; then
            ssh_ip="${SSH_CONNECTION:-}"
            ssh_ip="${ssh_ip%% *}"
        fi
        [[ -n "$ssh_ip" ]] && preferred="$(route_interface_for_target "$ssh_ip" || true)"
    fi

    if [[ -z "$preferred" ]]; then
        local routes=""
        routes="$(ip -4 route show default 2>/dev/null || true)"
        preferred="$(awk '
            NR==1 {best=$0; bestm=2147483647}
            {
                m=0
                for(i=1;i<=NF;i++) if($i=="metric") m=$(i+1)
                if(m < bestm){best=$0; bestm=m}
            }
            END{
                n=split(best,a," ")
                for(i=1;i<=n;i++) if(a[i]=="dev"){print a[i+1]; exit}
            }
        ' <<<"$routes")"
    fi

    if [[ -z "$preferred" ]]; then
        preferred="$(active_ipv4_interfaces | awk 'NR==1{print}')"
    fi
    ACTIVE_IFACE="$preferred"
}

detect_dns_backend() {
    DNS_BACKEND="resolv.conf"
    NM_CONNECTION=""
    NM_CONNECTION_UUID=""

    if command_exists nmcli &&
       systemctl is-active --quiet NetworkManager.service 2>/dev/null &&
       [[ -n "$ACTIVE_IFACE" ]]; then
        local con="" uuid=""
        con="$(nmcli -g GENERAL.CONNECTION device show "$ACTIVE_IFACE" 2>/dev/null || true)"
        if [[ -n "$con" && "$con" != "--" ]]; then
            uuid="$(nmcli -g connection.uuid connection show "$con" 2>/dev/null || true)"
            DNS_BACKEND="NetworkManager"
            NM_CONNECTION="$con"
            NM_CONNECTION_UUID="$uuid"
            return
        fi
    fi

    if command_exists resolvectl &&
       systemctl is-active --quiet systemd-resolved.service 2>/dev/null; then
        DNS_BACKEND="systemd-resolved"
        return
    fi
}


detect_system_resolver() {
    SYSTEM_RESOLVER_BACKEND="resolv.conf"
    RESOLV_CONF_TARGET="$(readlink -f /etc/resolv.conf 2>/dev/null || true)"
    [[ -n "$RESOLV_CONF_TARGET" ]] || RESOLV_CONF_TARGET="/etc/resolv.conf"

    if command_exists resolvectl &&
       systemctl is-active --quiet systemd-resolved.service 2>/dev/null; then
        SYSTEM_RESOLVER_BACKEND="systemd-resolved"
        return 0
    fi

    if [[ "$RESOLV_CONF_TARGET" == "/run/NetworkManager/resolv.conf" ||
          "$RESOLV_CONF_TARGET" == "/run/NetworkManager/no-stub-resolv.conf" ]]; then
        SYSTEM_RESOLVER_BACKEND="NetworkManager-resolv.conf"
    fi
}

wait_for_system_ad_dns() {
    local domain="$1" attempts="${2:-8}" i output=""
    for ((i=1; i<=attempts; i++)); do
        output="$(domain_srv_query "$domain" "" || true)"
        [[ -n "$output" ]] && return 0
        sleep 1
    done
    return 1
}

resolved_can_discover_ad() {
    local domain="$1" output=""
    command_exists resolvectl || return 1
    systemctl is-active --quiet systemd-resolved.service 2>/dev/null || return 1
    output="$(resolvectl query --type=SRV "_ldap._tcp.dc._msdcs.${domain}" 2>/dev/null || true)"
    grep -Fqi "${domain}" <<<"$output" || grep -Fqi 'service:' <<<"$output"
}

resolver_diagnostics() {
    local domain="$1"
    detect_system_resolver
    printf '\nSYSTEM RESOLVER DIAGNOSTICS\n'
    printf '  Network owner   : %s\n' "$DNS_BACKEND"
    printf '  System resolver : %s\n' "$SYSTEM_RESOLVER_BACKEND"
    printf '  /etc/resolv.conf: %s\n' "$RESOLV_CONF_TARGET"
    printf '  Interface       : %s\n' "${ACTIVE_IFACE:-unknown}"

    if [[ -r /etc/resolv.conf ]]; then
        printf '  resolv.conf nameservers:\n'
        awk '/^[[:space:]]*nameserver[[:space:]]+/{print "    "$2}' /etc/resolv.conf
    fi

    if command_exists nmcli && [[ -n "${ACTIVE_IFACE:-}" ]]; then
        local nm_dns=""
        nm_dns="$(nmcli -g IP4.DNS device show "$ACTIVE_IFACE" 2>/dev/null || true)"
        printf '  NetworkManager IP4.DNS:\n'
        if [[ -n "$nm_dns" ]]; then sed 's/^/    /' <<<"$nm_dns"; else printf '    (none)\n'; fi
    fi

    if command_exists resolvectl &&
       systemctl is-active --quiet systemd-resolved.service 2>/dev/null; then
        printf '  systemd-resolved link DNS:\n'
        resolvectl dns "$ACTIVE_IFACE" 2>/dev/null | sed 's/^/    /' || true
        printf '  systemd-resolved link domains:\n'
        resolvectl domain "$ACTIVE_IFACE" 2>/dev/null | sed 's/^/    /' || true
    fi
}

apply_resolved_runtime_dns() {
    local domain="$1" dns_csv="$2" iface="$3"
    command_exists resolvectl || return 1
    systemctl is-active --quiet systemd-resolved.service 2>/dev/null || return 1

    local -a dns_array=()
    mapfile -t dns_array < <(parse_dns_csv "$dns_csv")
    ((${#dns_array[@]})) || return 1

    # Standard AD client policy: the AD DNS servers are the resolver path for
    # all names. They are authoritative for AD and must forward external names.
    # "~." prevents public/DHCP DNS from racing AD lookups.
    resolvectl dns "$iface" "${dns_array[@]}" || return 1
    resolvectl domain "$iface" "$domain" "~." || return 1
    resolvectl default-route "$iface" yes >/dev/null 2>&1 || true
    resolvectl flush-caches >/dev/null 2>&1 || true
}

repair_resolver_convergence() {
    local domain="$1" dns_csv="$2" iface="$3"
    detect_system_resolver
    wait_for_system_ad_dns "$domain" 5 && return 0

    warn "AD DNS is reachable directly, but the host system resolver has not converged."
    resolver_diagnostics "$domain"

    if command_exists resolvectl &&
       systemctl is-active --quiet systemd-resolved.service 2>/dev/null; then
        info "Applying the AD DNS to systemd-resolved on '$iface' for live convergence."
        if apply_resolved_runtime_dns "$domain" "$dns_csv" "$iface" &&
           wait_for_system_ad_dns "$domain" 5; then
            ok "System resolver converged through systemd-resolved."
            return 0
        fi

        if resolved_can_discover_ad "$domain"; then
            detect_system_resolver
            case "$RESOLV_CONF_TARGET" in
                /run/systemd/resolve/stub-resolv.conf|/run/systemd/resolve/resolv.conf|/run/NetworkManager/resolv.conf)
                    ;;
                *)
                    warn "systemd-resolved can discover AD, but /etc/resolv.conf is detached from the active resolver."
                    if [[ -e /run/systemd/resolve/stub-resolv.conf ]] &&
                       confirm "Repair /etc/resolv.conf to the systemd-resolved stub? Snapshot rollback remains available." Y; then
                        rm -f /etc/resolv.conf || return 1
                        ln -s /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf || return 1
                        resolvectl flush-caches >/dev/null 2>&1 || true
                        if wait_for_system_ad_dns "$domain" 5; then
                            detect_system_resolver
                            ok "System resolver repaired through systemd-resolved."
                            return 0
                        fi
                    fi
                    ;;
            esac
        fi
    fi

    if [[ "$DNS_BACKEND" == "NetworkManager" &&
          -e /run/NetworkManager/resolv.conf ]]; then
        detect_system_resolver
        if grep -Fq "$(dns_first "$dns_csv")" /run/NetworkManager/resolv.conf 2>/dev/null &&
           ! wait_for_system_ad_dns "$domain" 1; then
            case "$RESOLV_CONF_TARGET" in
                /run/NetworkManager/resolv.conf)
                    ;;
                *)
                    warn "NetworkManager generated the correct AD resolver file, but /etc/resolv.conf is using another source."
                    if confirm "Attach /etc/resolv.conf to NetworkManager's runtime resolver file? Snapshot rollback remains available." Y; then
                        rm -f /etc/resolv.conf || return 1
                        ln -s /run/NetworkManager/resolv.conf /etc/resolv.conf || return 1
                        if wait_for_system_ad_dns "$domain" 5; then
                            detect_system_resolver
                            ok "System resolver repaired through NetworkManager."
                            return 0
                        fi
                    fi
                    ;;
            esac
        fi
    fi

    resolver_diagnostics "$domain"
    return 1
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
    snapshot_copy /etc/hosts "$snap"
    snapshot_copy /etc/krb5.conf "$snap"
    snapshot_copy /etc/krb5.keytab "$snap"
    snapshot_copy /etc/realmd.conf "$snap"
    snapshot_copy /etc/sssd/sssd.conf "$snap"
    snapshot_copy /etc/sssd/conf.d "$snap"
    snapshot_copy /etc/nsswitch.conf "$snap"
    snapshot_copy /etc/pam.d/common-session "$snap"
    snapshot_copy /etc/pam.d/common-session-noninteractive "$snap"
    snapshot_copy /etc/systemd/resolved.conf.d/90-ad-client-assistant.conf "$snap"

    : >"$meta"
    write_env_kv "$meta" SNAPSHOT_VERSION "2"
    write_env_kv "$meta" SNAPSHOT_PATH "$snap"
    write_env_kv "$meta" CREATED_AT "$(date -Is)"
    write_env_kv "$meta" DOMAIN "$domain"
    write_env_kv "$meta" OLD_HOSTNAME "$(hostnamectl --static 2>/dev/null || hostname)"
    write_env_kv "$meta" ACTIVE_IFACE "$iface"
    write_env_kv "$meta" DNS_BACKEND "$DNS_BACKEND"
    write_env_kv "$meta" PKG_FAMILY "$PKG_FAMILY"
    write_env_kv "$meta" NM_CONNECTION "$NM_CONNECTION"
    write_env_kv "$meta" NM_CONNECTION_UUID "$NM_CONNECTION_UUID"
    write_env_kv "$meta" REMOTE_SESSION "$REMOTE_SESSION"
    write_env_kv "$meta" PREJOIN_BOOT_ID "$(current_boot_id)"
    local sssd_active="0" sssd_enabled="0"
    systemctl is-active --quiet sssd.service 2>/dev/null && sssd_active="1"
    systemctl is-enabled --quiet sssd.service 2>/dev/null && sssd_enabled="1"
    write_env_kv "$meta" PREJOIN_SSSD_ACTIVE "$sssd_active"
    write_env_kv "$meta" PREJOIN_SSSD_ENABLED "$sssd_enabled"
    write_env_kv "$meta" PREJOIN_SSSD_CONF_PRESENT "$([[ -s /etc/sssd/sssd.conf ]] && printf 1 || printf 0)"
    write_env_kv "$meta" PREJOIN_SSSD_CONFDB_PRESENT "$([[ -s /var/lib/sss/db/config.ldb ]] && printf 1 || printf 0)"

    if [[ "$DNS_BACKEND" == "NetworkManager" && -n "$NM_CONNECTION" ]]; then
        write_env_kv "$meta" NM_IPV4_IGNORE_AUTO_DNS \
            "$(nmcli -g ipv4.ignore-auto-dns connection show "$NM_CONNECTION" 2>/dev/null || true)"
        write_env_kv "$meta" NM_IPV4_DNS \
            "$(nmcli -g ipv4.dns connection show "$NM_CONNECTION" 2>/dev/null || true)"
        write_env_kv "$meta" NM_IPV4_DNS_SEARCH \
            "$(nmcli -g ipv4.dns-search connection show "$NM_CONNECTION" 2>/dev/null || true)"
        write_env_kv "$meta" NM_IPV4_DNS_PRIORITY \
            "$(nmcli -g ipv4.dns-priority connection show "$NM_CONNECTION" 2>/dev/null || true)"
        write_env_kv "$meta" NM_IPV6_IGNORE_AUTO_DNS \
            "$(nmcli -g ipv6.ignore-auto-dns connection show "$NM_CONNECTION" 2>/dev/null || true)"
        write_env_kv "$meta" NM_IPV6_DNS \
            "$(nmcli -g ipv6.dns connection show "$NM_CONNECTION" 2>/dev/null || true)"
        write_env_kv "$meta" NM_IPV6_DNS_SEARCH \
            "$(nmcli -g ipv6.dns-search connection show "$NM_CONNECTION" 2>/dev/null || true)"
    fi

    if command_exists authselect; then
        local authselect_state="" backup_name="ad-client-assistant-${RUN_ID}"
        authselect_state="$(authselect current --raw 2>/dev/null || authselect current 2>/dev/null || true)"
        printf '%s\n' "$authselect_state" >"${snap}/authselect-before.txt"
        if authselect backup "$backup_name" >/dev/null 2>&1; then
            write_env_kv "$meta" AUTHSELECT_BACKUP "$backup_name"
        fi
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
    local snap="$1" domain="$2" realm="$3" iface="$4" dns_csv="$5" hostname_changed="$6" computer_name="${7:-}"
    : >"$CURRENT_STATE"
    chmod 0600 "$CURRENT_STATE"
    write_env_kv "$CURRENT_STATE" STATE_VERSION "2"
    write_env_kv "$CURRENT_STATE" PHASE "JOIN_PENDING_REBOOT"
    write_env_kv "$CURRENT_STATE" SNAPSHOT_PATH "$snap"
    write_env_kv "$CURRENT_STATE" DOMAIN "$domain"
    write_env_kv "$CURRENT_STATE" REALM "$realm"
    write_env_kv "$CURRENT_STATE" ACTIVE_IFACE "$iface"
    write_env_kv "$CURRENT_STATE" AD_DNS_SERVERS "$dns_csv"
    write_env_kv "$CURRENT_STATE" HOSTNAME_CHANGED "$hostname_changed"
    write_env_kv "$CURRENT_STATE" COMPUTER_NAME "$computer_name"
    write_env_kv "$CURRENT_STATE" JOIN_BOOT_ID "$(current_boot_id)"
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
                libpam-sss
            ;;
        dnf)
            printf '%s\n' \
                realmd \
                sssd \
                adcli \
                krb5-workstation \
                oddjob \
                oddjob-mkhomedir \
                samba-common-tools
            ;;
        *)
            return 0
            ;;
    esac
}


dns_tools_package_name() {
    # dig is the actual capability required by this assistant. Do not treat
    # transitional/virtual package names such as dnsutils as missing when a
    # real provider already supplies dig.
    command_exists dig && return 0

    case "$PKG_FAMILY" in
        apt)
            if apt-cache show bind9-dnsutils >/dev/null 2>&1; then
                printf '%s' "bind9-dnsutils"
            elif apt-cache show dnsutils >/dev/null 2>&1; then
                printf '%s' "dnsutils"
            else
                return 1
            fi
            ;;
        dnf)
            printf '%s' "bind-utils"
            ;;
        *)
            return 1
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
    local record="${snap}/packages-installed-by-assistant.txt"
    mapfile -t required < <(required_packages)
    : >"$record"

    if [[ "$PKG_FAMILY" == "generic" ]]; then
        warn "Unsupported package family. No repository/package configuration will be changed."
        validate_required_commands
        return $?
    fi

    local pkg dns_pkg=""
    for pkg in "${required[@]}"; do
        [[ -n "$pkg" ]] || continue
        pkg_installed "$pkg" || missing+=("$pkg")
    done

    # DNS tooling is capability-based. Ubuntu/Debian may satisfy "dnsutils"
    # through bind9-dnsutils, so never ask to install a package merely because
    # a transitional package name is absent.
    if ! command_exists dig; then
        dns_pkg="$(dns_tools_package_name 2>/dev/null || true)"
        [[ -n "$dns_pkg" ]] || {
            err "dig is unavailable and no distribution DNS tools package could be identified."
            return 1
        }
        pkg_installed "$dns_pkg" || missing+=("$dns_pkg")
    else
        ok "DNS diagnostic capability already available: $(command -v dig)."
    fi

    if ((${#missing[@]} == 0)); then
        ok "Required AD client packages are already installed."
        validate_required_commands
        return $?
    fi

    info "Packages required from the distribution repositories:"
    printf '  %s\n' "${missing[@]}"
    confirm "Install these packages from the currently configured official/system repositories?" Y || return 1

    case "$PKG_FAMILY" in
        apt)
            apt-get update || { err "apt-get update failed."; return 1; }
            if ! DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${missing[@]}"; then
                for pkg in "${missing[@]}"; do
                    pkg_installed "$pkg" && record_assistant_package "$snap" "$pkg"
                done
                err "APT package installation failed; any packages actually added were recorded for rollback."
                return 1
            fi
            ;;
        dnf)
            local pm="dnf"
            command_exists dnf || pm="yum"
            if ! "$pm" install -y "${missing[@]}"; then
                for pkg in "${missing[@]}"; do
                    pkg_installed "$pkg" && record_assistant_package "$snap" "$pkg"
                done
                err "$pm package installation failed; any packages actually added were recorded for rollback."
                return 1
            fi
            ;;
    esac

    for pkg in "${missing[@]}"; do
        pkg_installed "$pkg" && record_assistant_package "$snap" "$pkg"
    done

    validate_required_commands
}

validate_required_commands() {
    local -a commands=(realm adcli kinit klist getent systemctl hostnamectl ip)
    local missing=0 cmd
    for cmd in "${commands[@]}"; do
        if command_exists "$cmd"; then
            ok "Command available: $cmd"
        else
            err "Missing required command: $cmd"
            missing=1
        fi
    done

    if [[ "$PKG_FAMILY" == "apt" || "$PKG_FAMILY" == "dnf" ]]; then
        if command_exists dig; then
            ok "Command available: dig"
        else
            err "Missing required DNS diagnostic command: dig"
            missing=1
        fi
    else
        command_exists dig || warn "dig is unavailable; generic-mode DNS validation will be reduced."
    fi

    require_supported_init || missing=1
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

    remove_assistant_packages_now "$snap"
}

remove_assistant_packages_now() {
    local snap="$1"
    local file="${snap}/packages-installed-by-assistant.txt"
    [[ -s "$file" ]] || return 0

    local -a pkgs=() installed=()
    mapfile -t pkgs <"$file"

    local pkg
    for pkg in "${pkgs[@]}"; do
        [[ -n "$pkg" ]] || continue
        pkg_installed "$pkg" && installed+=("$pkg")
    done

    ((${#installed[@]})) || {
        info "Packages recorded for this attempt are already absent."
        return 0
    }

    case "$PKG_FAMILY" in
        apt)
            apt-get remove -y "${installed[@]}" || {
                warn "APT could not remove every recorded package."
                return 1
            }
            ;;
        dnf)
            local pm="dnf"
            command_exists dnf || pm="yum"
            "$pm" remove -y "${installed[@]}" || {
                warn "$pm could not remove every recorded package."
                return 1
            }
            ;;
        *)
            warn "Package removal is not automated for this package family."
            return 1
            ;;
    esac

    ok "Packages added only by the failed join attempt were removed. No autoremove was executed."
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

    [[ -n "$dns_space" ]] || { err "No DNS servers supplied."; return 1; }
    (( AD_DNS_FORWARDING_OK == 1 )) || {
        err "AD DNS external forwarding was not validated. Refusing to replace the client resolver and risk losing Internet access."
        return 1
    }

    if (( REMOTE_SESSION )); then
        warn "Remote session detected. DNS changes should not interrupt an existing IP-based SSH session,"
        warn "but a bad DNS choice can prevent reconnecting by hostname."
    fi

    case "$DNS_BACKEND" in
        NetworkManager)
            [[ -n "$NM_CONNECTION" ]] || { err "NetworkManager connection could not be determined."; return 1; }

            # DHCP still owns IP/gateway/routes. Only DNS is overridden.
            # Negative priority excludes DNS from other active connections with
            # a worse priority and "~." makes this the default DNS route.
            nmcli connection modify "$NM_CONNECTION" \
                ipv4.ignore-auto-dns yes \
                ipv4.dns "$dns_space" \
                ipv4.dns-search "$domain,~." \
                ipv4.dns-priority -100 || return 1

            nmcli connection modify "$NM_CONNECTION" \
                ipv6.ignore-auto-dns yes \
                ipv6.dns-priority -100 || true

            if ! nmcli device reapply "$iface" >/dev/null 2>&1; then
                warn "NetworkManager could not reapply DNS live."
                if confirm "Reconnect the NetworkManager connection now? This can interrupt remote sessions." N; then
                    nmcli connection up "$NM_CONNECTION" || return 1
                else
                    return 1
                fi
            fi

            if command_exists resolvectl &&
               systemctl is-active --quiet systemd-resolved.service 2>/dev/null; then
                apply_resolved_runtime_dns "$domain" "$dns_csv" "$iface" || \
                    warn "NetworkManager was updated, but systemd-resolved did not accept the live AD DNS policy."
            fi
            ;;
        systemd-resolved)
            local -a dns_array=()
            mapfile -t dns_array < <(parse_dns_csv "$dns_csv")
            local iface_count=""
            iface_count="$(active_ipv4_interfaces | awk 'NF{n++}END{print n+0}')"
            if (( iface_count > 1 )); then
                warn "Multiple IPv4 interfaces are active and systemd-resolved is not owned by NetworkManager."
                warn "The persistent resolved.conf.d fallback is global; per-link runtime settings are also applied."
                confirm "Apply this global AD DNS fallback on a multi-NIC host?" N || return 1
            fi

            mkdir -p /etc/systemd/resolved.conf.d
            cat >/etc/systemd/resolved.conf.d/90-ad-client-assistant.conf <<EOF
# Managed by Linux AD Client Assistant
# AD DNS is authoritative for the domain and forwards external DNS.
[Resolve]
DNS=${dns_space}
Domains=${domain} ~.
EOF
            systemctl restart systemd-resolved.service || return 1
            apply_resolved_runtime_dns "$domain" "$dns_csv" "$iface" || return 1
            ;;
        resolv.conf)
            warn "No supported persistent DNS manager was detected."
            warn "The assistant will manage /etc/resolv.conf directly and restore it on rollback."
            confirm "Continue with direct /etc/resolv.conf management?" N || return 1

            local tmp="/etc/resolv.conf.ad-client-assistant.$$"
            {
                local ip
                while IFS= read -r ip; do
                    [[ -n "$ip" ]] && printf 'nameserver %s\n' "$ip"
                done < <(parse_dns_csv "$dns_csv")
                printf 'search %s\n' "$domain"
                printf 'options timeout:2 attempts:2\n'
            } >"$tmp" || return 1
            chmod 0644 "$tmp"
            mv -Tf "$tmp" /etc/resolv.conf || return 1
            ;;
    esac

    sleep 1
    ok "AD DNS configuration applied via $DNS_BACKEND; DHCP/static IP addressing was left unchanged."
}

restore_network_from_snapshot() {
    local snap="$1" meta="${snap}/snapshot.env"
    [[ -f "$meta" ]] || { err "Snapshot metadata missing: $meta"; return 1; }

    unset DNS_BACKEND NM_CONNECTION NM_CONNECTION_UUID ACTIVE_IFACE
    load_state_file "$meta" || return 1

    case "${DNS_BACKEND:-}" in
        NetworkManager)
            if command_exists nmcli; then
                local con_ref="${NM_CONNECTION_UUID:-${NM_CONNECTION:-}}"
                if [[ -n "$con_ref" ]] && nmcli connection show "$con_ref" >/dev/null 2>&1; then
                    nmcli connection modify "$con_ref" \
                        ipv4.ignore-auto-dns "${NM_IPV4_IGNORE_AUTO_DNS:-no}" \
                        ipv4.dns "${NM_IPV4_DNS:-}" \
                        ipv4.dns-search "${NM_IPV4_DNS_SEARCH:-}" \
                        ipv4.dns-priority "${NM_IPV4_DNS_PRIORITY:-0}" || true
                    nmcli connection modify "$con_ref" \
                        ipv6.ignore-auto-dns "${NM_IPV6_IGNORE_AUTO_DNS:-no}" \
                        ipv6.dns "${NM_IPV6_DNS:-}" \
                        ipv6.dns-search "${NM_IPV6_DNS_SEARCH:-}" || true
                    [[ -n "${ACTIVE_IFACE:-}" ]] && nmcli device reapply "$ACTIVE_IFACE" >/dev/null 2>&1 || true
                else
                    warn "Original NetworkManager connection is no longer present; automatic DNS rollback is incomplete."
                fi
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

    detect_active_interface
    detect_dns_backend
    detect_system_resolver
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


preflight_ad_dns_servers() {
    local domain="$1" dns_csv="$2" ip="" output="" external="" failures=0 forwarding_failures=0
    AD_DNS_FORWARDING_OK=0

    if ! command_exists dig; then
        warn "dig is unavailable before dependency installation; direct DNS preflight is deferred."
        return 0
    fi

    while IFS= read -r ip; do
        [[ -n "$ip" ]] || continue

        output="$(domain_srv_query "$domain" "$ip" || true)"
        if [[ -n "$output" ]]; then
            ok "Preflight: $ip is an AD-capable DNS server for $domain."
        else
            err "Preflight: $ip does not answer the AD DC locator SRV query."
            failures=1
            continue
        fi

        # A normal AD client should use only AD DNS. Therefore each configured
        # AD DNS must also be able to resolve/forward external names.
        external="$(dig +time=3 +tries=1 @"$ip" example.com A +short 2>/dev/null || true)"
        if grep -Eq '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' <<<"$external"; then
            ok "Preflight: $ip forwards external DNS queries."
        else
            err "Preflight: $ip is authoritative for AD but cannot resolve external DNS."
            forwarding_failures=1
        fi
    done < <(parse_dns_csv "$dns_csv")

    (( failures == 0 )) || return 1

    if (( forwarding_failures != 0 )); then
        printf '\n%bAD DNS FORWARDING DIAGNOSTIC%b\n' "$C_BOLD" "$C_RESET"
        warn "The AD DNS server can resolve the domain but cannot resolve Internet names."
        info "The client IP may remain DHCP; do not add public DNS as a fallback because it can break AD/Kerberos discovery."
        info "Repair the Samba/AD DNS forwarder on the DC, then retry. No client DNS change has been committed."
        return 2
    fi

    AD_DNS_FORWARDING_OK=1
    return 0
}

ad_dc_targets_from_dns() {
    local domain="$1" dns_csv="$2" first="" output=""
    first="$(dns_first "$dns_csv")"
    output="$(domain_srv_query "$domain" "$first" || true)"
    awk '{host=$4; sub(/\.$/,"",host); if(host!="" && !seen[host]++) print host}' <<<"$output"
}

tcp_port_open() {
    local host="$1" port="$2"
    command_exists timeout || return 2
    timeout 3 bash -c 'exec 3<>"/dev/tcp/${1}/${2}"' _ "$host" "$port" >/dev/null 2>&1
}

validate_ad_network_ports() {
    local domain="$1" dns_csv="$2" dc="" first_dc="" hard_fail=0
    first_dc="$(ad_dc_targets_from_dns "$domain" "$dns_csv" | awk 'NR==1{print}')"
    if [[ -z "$first_dc" ]]; then
        warn "No DC hostname could be extracted from DNS SRV answers; port readiness skipped."
        return 0
    fi
    dc="$first_dc"
    printf '\nAD NETWORK READINESS (%s)\n' "$dc"
    local item port required rc
    for item in 'DNS:53:yes' 'Kerberos:88:yes' 'LDAP:389:yes' 'SMB:445:no'; do
        IFS=: read -r item port required <<<"$item"
        if tcp_port_open "$dc" "$port"; then
            ok "$item/TCP $port reachable."
        else
            rc=$?
            if (( rc == 2 )); then
                warn "timeout command unavailable; TCP readiness cannot be tested without adding dependencies."
                return 0
            fi
            if [[ "$required" == yes ]]; then
                err "$item/TCP $port is not reachable on $dc."
                hard_fail=1
            else
                warn "$item/TCP $port is not reachable; domain join may work but SMB/GPO operations can be limited."
            fi
        fi
    done
    (( hard_fail == 0 ))
}

prompt_domain_admin_account() {
    local purpose="${1:-join}" default_account="${2:-Administrator}" account=""

    printf '\n%bDOMAIN CREDENTIAL%b\n' "$C_BOLD" "$C_RESET"
    printf '  Default account: %s\n' "$default_account"
    printf '  Press Enter to use the default, or type another delegated/enabled AD account.\n'
    printf '  Accepted forms: user | user@%s | DOMAIN\\user\n\n' "${JOIN_REALM_NAME:-REALM}"

    account="$(ask "AD account authorized to ${purpose}" "$default_account")"
    [[ -n "$account" ]] || account="$default_account"
    printf '%s' "$account"
}

analyze_realm_join_failure() {
    local log_file="$1" computer_name="$2"
    [[ -r "$log_file" ]] || return 0

    if grep -Fiq 'Insufficient permissions to modify computer account' "$log_file" ||
       grep -Fiq 'unable to get access to CN=' "$log_file"; then
        printf '\n%bJOIN PERMISSION DIAGNOSTIC%b\n' "$C_BOLD" "$C_RESET"
        warn "The AD computer account '${computer_name}' appears to exist already, or the selected account cannot modify/create it."
        info "Use an account with delegated computer-join rights, or inspect the existing computer object from the AD control plane."
        info "If the object is stale, delete/reset it only after confirming it is not an active machine account."
    fi

    if grep -Fiq "Client's credentials have been revoked" "$log_file"; then
        warn "The credential used by realmd/adcli is disabled, expired or otherwise rejected by Kerberos."
        info "Retry with Administrator or select another enabled/delegated AD account at the credential step."
    fi
}

kerberos_preflight_ticket() {
    local join_user="$1" realm="$2" principal=""
    principal="$join_user"
    if [[ "$principal" == *\\* ]]; then
        principal="${principal##*\\}"
    fi
    [[ "$principal" == *@* ]] || principal="${principal}@${realm}"

    rm -f -- "$PRIVATE_KRB5CCACHE"
    info "Kerberos authentication preflight for $principal."
    info "Credential cache is isolated and will be removed after the join attempt."
    if kinit -c "FILE:${PRIVATE_KRB5CCACHE}" "$principal"; then
        ok "Kerberos credentials accepted."
        return 0
    fi
    err "Kerberos authentication failed before realm join."
    return 1
}

validate_domain_dns() {
    local domain="$1" dns_csv="$2" ip="" direct="" failed=0

    if command_exists dig; then
        while IFS= read -r ip; do
            [[ -n "$ip" ]] || continue
            direct="$(domain_srv_query "$domain" "$ip" || true)"
            if [[ -n "$direct" ]]; then
                ok "AD DNS $ip returns DC locator SRV records."
            else
                err "AD DNS $ip did not return _ldap._tcp.dc._msdcs.${domain}."
                failed=1
            fi
        done < <(parse_dns_csv "$dns_csv")
        (( failed == 0 )) || return 1

        if wait_for_system_ad_dns "$domain" 5; then
            ok "System resolver can discover AD DC locator SRV records."
        else
            warn "Direct AD DNS queries pass, but the system resolver cannot yet discover the domain."
            if repair_resolver_convergence "$domain" "$dns_csv" "$ACTIVE_IFACE"; then
                ok "System resolver can now discover AD DC locator SRV records."
            else
                err "System resolver still cannot discover the domain after resolver convergence repair."
                return 1
            fi
        fi
    else
        warn "dig is unavailable; relying on realmd discovery."
    fi

    local discovery=""
    discovery="$(realm discover --server-software=active-directory "$domain" 2>&1 || true)"
    if grep -Fiq 'server-software: active-directory' <<<"$discovery"; then
        ok "realmd discovered Active Directory."
        JOIN_REALM_NAME="$(awk -F': *' 'tolower($1) ~ /^[[:space:]]*realm-name$/ {print $2; exit}' <<<"$discovery")"
        [[ -n "$JOIN_REALM_NAME" ]] || JOIN_REALM_NAME="${domain^^}"
    else
        err "realmd could not discover Active Directory."
        printf '%s\n' "$discovery"
        resolver_diagnostics "$domain"
        return 1
    fi
    return 0
}

audit_time_sync() {
    local healthy=0
    if command_exists timedatectl; then
        local synced=""
        synced="$(timedatectl show -p NTPSynchronized --value 2>/dev/null || true)"
        if [[ "$synced" == "yes" ]]; then
            ok "System time reports synchronized."
            healthy=1
        fi
    fi
    if (( ! healthy )) && command_exists chronyc; then
        local leap=""
        leap="$(chronyc tracking 2>/dev/null | awk -F': *' '/Leap status/{print $2; exit}')"
        if [[ "${leap,,}" == normal ]]; then
            ok "Chrony reports Leap status: Normal."
            healthy=1
        fi
    fi
    if (( ! healthy )); then
        warn "System time is not reporting a healthy synchronization state."
        warn "Kerberos is sensitive to clock skew; correct time before treating credential failures as AD issues."
        return 1
    fi
    return 0
}

configure_hostname_if_requested() {
    local requested="$1" old=""
    HOSTNAME_CHANGED_RESULT=0
    old="$(hostnamectl --static 2>/dev/null || hostname)"

    if [[ -z "$requested" || "$requested" == "$old" ]]; then return 0; fi
    if ! valid_system_hostname "$requested"; then
        err "Invalid system hostname: $requested"
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
        local pam_module=""
        pam_module="$(find /lib /usr/lib -path '*/security/pam_mkhomedir.so' -print -quit 2>/dev/null || true)"
        if [[ -z "$pam_module" ]]; then
            warn "pam_mkhomedir.so is not available in the current base installation."
            warn "No extra package will be added only for this optional feature. Home creation remains unchanged."
            return 1
        fi

        local pamfile
        for pamfile in /etc/pam.d/common-session /etc/pam.d/common-session-noninteractive; do
            [[ -f "$pamfile" ]] || continue
            if ! grep -Fq 'pam_mkhomedir.so' "$pamfile"; then
                printf '\nsession optional pam_mkhomedir.so skel=/etc/skel/ umask=0022\n' >>"$pamfile"
            fi
        done
        ok "pam_mkhomedir enabled idempotently using the existing PAM stack."
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


postjoin_acceptance() {
    local domain="$1" test_user="${2:-}" failures=0
    printf '\nPOST-JOIN ACCEPTANCE\n'

    local realm_names=""
    realm_names="$(realm list --name-only 2>/dev/null || true)"
    if grep -Fiqx "$domain" <<<"$realm_names"; then
        ok "Realm membership is present."
    else
        err "Realm membership is not reported for $domain."
        failures=1
    fi

    if command_exists sssctl; then
        if sssctl config-check >/dev/null 2>&1; then
            ok "SSSD configuration check passed."
        else
            err "SSSD configuration check failed."
            sssctl config-check 2>&1 | sed 's/^/  /' || true
            failures=1
        fi
    fi

    if systemctl is-active --quiet sssd.service 2>/dev/null; then
        ok "SSSD service is active."
    else
        err "SSSD service is not active."
        journalctl -u sssd.service -n 40 --no-pager 2>/dev/null | sed 's/^/  /' || true
        failures=1
    fi

    if adcli testjoin -D "$domain" >/dev/null 2>&1; then
        ok "adcli secure machine join passed."
    else
        err "adcli testjoin failed."
        failures=1
    fi

    local keytab_listing=""
    keytab_listing="$(klist -k /etc/krb5.keytab 2>/dev/null || true)"
    if [[ -s /etc/krb5.keytab ]] && grep -Eqi '(^|[[:space:]])host/' <<<"$keytab_listing"; then
        ok "Machine keytab contains a host principal."
    else
        err "Machine keytab host principal is missing or unreadable."
        failures=1
    fi

    if domain_srv_query "$domain" "" >/dev/null 2>&1; then
        ok "System resolver still returns AD DC locator SRV records."
    else
        err "System resolver no longer returns AD DC locator SRV records."
        failures=1
    fi

    if [[ -n "$test_user" ]]; then
        if getent passwd "$test_user" >/dev/null 2>&1 || id "$test_user" >/dev/null 2>&1; then
            ok "Domain identity lookup succeeded for $test_user."
        else
            warn "Domain identity lookup did not resolve $test_user."
            failures=1
        fi
    fi

    (( failures == 0 ))
}

join_domain_guided() {
    header
    printf '%bGUIDED DOMAIN JOIN%b\n\n' "$C_BOLD" "$C_RESET"

    require_supported_init || return 1
    if (( PRESET_SWITCH_MODE == 0 )); then
        recover_incomplete_previous_join || return 1
    fi

    local existing_realms=""
    existing_realms="$(realm list --name-only 2>/dev/null || true)"
    if [[ -n "$existing_realms" ]]; then
        warn "This machine already reports realm membership:"
        printf '%s\n' "$existing_realms"
        return 1
    fi

    if (( PRESET_SWITCH_MODE == 0 )); then
        identity_precheck || return 1
    fi

    local domain="" dns_csv="" join_user="Administrator" ou="" requested_hostname="" computer_name="" test_user=""
    local id_mapping="yes"

    if [[ -n "$PRESET_DOMAIN" ]]; then domain="$PRESET_DOMAIN"; else domain="$(ask 'AD DNS domain (for example corp.example.com)' '')"; fi
    domain="${domain,,}"
    valid_dns_domain "$domain" || {
        err "A valid DNS domain with RFC-style labels is required."
        return 1
    }

    if [[ -n "$PRESET_DNS" ]]; then dns_csv="$PRESET_DNS"; else dns_csv="$(ask 'AD DNS server IPv4 addresses (comma separated)' '')"; fi
    validate_dns_list "$dns_csv" || {
        err "At least one valid IPv4 AD DNS server is required."
        return 1
    }

    local first_dns=""
    first_dns="$(dns_first "$dns_csv")"
    select_join_interface "$first_dns" || return 1

    printf '\nSelected interface: %s\n' "$ACTIVE_IFACE"
    printf 'DNS backend      : %s\n' "$DNS_BACKEND"
    printf 'Current DNS      :\n'
    current_dns_summary | sed 's/^/  /'

    preflight_ad_dns_servers "$domain" "$dns_csv" || return 1

    if [[ -n "$PRESET_HOSTNAME" ]]; then requested_hostname="$PRESET_HOSTNAME"; else requested_hostname="$(ask 'System hostname' "$(hostnamectl --static 2>/dev/null || hostname)")"; fi
    local short_default="${requested_hostname%%.*}"
    if ((${#short_default} > 15)); then short_default=""; fi

    if [[ -n "$PRESET_COMPUTER" ]]; then computer_name="$PRESET_COMPUTER"; else computer_name="$(ask 'AD computer name (NetBIOS, max 15 chars)' "$short_default")"; fi
    valid_ad_computer_name "$computer_name" || {
        err "AD computer name must be 1-15 characters, start/end alphanumeric, with hyphens only inside."
        return 1
    }
    JOIN_COMPUTER_NAME="${computer_name^^}"

    if (( PRESET_SWITCH_MODE == 1 )); then ou="$PRESET_OU"; else ou="$(ask 'Computer OU DN (optional)' '')"; fi
    if [[ -n "$ou" && ! "$ou" =~ ^(OU|CN)= ]]; then
        warn "OU path does not look like a distinguished name beginning with OU= or CN=."
        confirm "Use this OU value anyway?" N || return 1
    fi

    printf '\nPOSIX identity model:\n'
    printf '  [1] Automatic SSSD SID -> UID/GID mapping (recommended default)\n'
    printf '  [2] Use RFC2307/POSIX attributes already stored in AD\n'
    local map_choice=""
    if [[ -n "$PRESET_ID_MAPPING" ]]; then
        id_mapping="$PRESET_ID_MAPPING"
    else
        map_choice="$(ask 'Select identity model' '1')"
        [[ "$map_choice" == "2" ]] && id_mapping="no"
    fi

    printf '\nPlan:\n'
    printf '  Domain       : %s\n' "$domain"
    printf '  DNS          : %s\n' "$dns_csv"
    printf '  Interface    : %s\n' "$ACTIVE_IFACE"
    printf '  DNS backend  : %s\n' "$DNS_BACKEND"
    printf '  Hostname     : %s\n' "$requested_hostname"
    printf '  AD computer  : %s\n' "$JOIN_COMPUTER_NAME"
    printf '  Join account : Administrator by default; changeable at the final credential step\n'
    printf '  OU           : %s\n' "${ou:-(default Computers container)}"
    printf '  ID mapping   : %s\n' "$id_mapping"

    if (( PRESET_SWITCH_MODE == 0 )); then
        confirm "Create a reversible snapshot and continue?" Y || return 0
    fi

    local snap=""
    snap="$(create_prejoin_snapshot "$domain" "$ACTIVE_IFACE")"
    info "Pre-join snapshot: $snap"

    JOIN_TRANSACTION_SNAPSHOT="$snap"
    JOIN_TRANSACTION_ACTIVE=1
    JOIN_TRANSACTION_COMMITTED=0
    JOIN_TRANSACTION_ROLLBACK=0
    join_transaction_mark "$snap" "SNAPSHOT_READY"

    if ! install_required_packages "$snap"; then
        err "Dependency preparation failed."
        rollback_failed_join_local_state "$snap" "interactive"
        return 1
    fi
    join_transaction_mark "$snap" "PACKAGES_READY"

    if ! preflight_ad_dns_servers "$domain" "$dns_csv"; then
        err "AD DNS preflight failed after dependency preparation."
        rollback_failed_join_local_state "$snap" "interactive"
        return 1
    fi

    local hostname_changed="0"
    if ! configure_hostname_if_requested "$requested_hostname"; then
        rollback_failed_join_local_state "$snap" "interactive"
        return 1
    fi
    hostname_changed="$HOSTNAME_CHANGED_RESULT"

    if ! apply_domain_dns "$domain" "$dns_csv" "$ACTIVE_IFACE"; then
        err "AD DNS configuration failed."
        rollback_failed_join_local_state "$snap" "interactive"
        return 1
    fi
    join_transaction_mark "$snap" "DNS_APPLIED"

    if ! validate_domain_dns "$domain" "$dns_csv"; then
        err "Domain discovery failed."
        rollback_failed_join_local_state "$snap" "interactive"
        return 1
    fi

    audit_time_sync || {
        warn "Time readiness is not healthy."
        confirm "Continue to Kerberos authentication anyway?" N || {
            rollback_failed_join_local_state "$snap" "interactive"
            return 1
        }
    }

    validate_ad_network_ports "$domain" "$dns_csv" || {
        err "Required AD network ports are not reachable."
        rollback_failed_join_local_state "$snap" "interactive"
        return 1
    }

    [[ -n "$JOIN_REALM_NAME" ]] || JOIN_REALM_NAME="${domain^^}"

    join_user="$(prompt_domain_admin_account 'join this computer to the domain' 'Administrator')"
    info "Selected AD join identity: $join_user"

    if ! kerberos_preflight_ticket "$join_user" "$JOIN_REALM_NAME"; then
        rollback_failed_join_local_state "$snap" "interactive"
        return 1
    fi
    join_transaction_mark "$snap" "KERBEROS_READY"

    local -a join_args=(
        join
        --verbose
        --server-software=active-directory
        --client-software=sssd
        "--automatic-id-mapping=${id_mapping}"
        "--computer-name=${JOIN_COMPUTER_NAME}"
    )
    [[ -n "$ou" ]] && join_args+=("--computer-ou=$ou")
    join_args+=("$domain")

    info "Joining with the isolated Kerberos ticket for '$join_user'; no password is stored."
    local join_log="${snap}/realm-join.log" join_rc=0

    KRB5CCNAME="FILE:${PRIVATE_KRB5CCACHE}" \
    KRB5_CCACHE="FILE:${PRIVATE_KRB5CCACHE}" \
        realm "${join_args[@]}" 2>&1 | tee "$join_log"
    join_rc=${PIPESTATUS[0]}

    if (( join_rc != 0 )); then
        err "realm join failed."
        analyze_realm_join_failure "$join_log" "$JOIN_COMPUTER_NAME"
        rollback_failed_join_local_state "$snap" "interactive"
        return 1
    fi

    cleanup_private_ccache

    JOIN_TRANSACTION_COMMITTED=1
    JOIN_TRANSACTION_ACTIVE=0
    join_transaction_mark "$snap" "MEMBERSHIP_COMMITTED"

    record_current_state \
        "$snap" "$domain" "$JOIN_REALM_NAME" "$ACTIVE_IFACE" \
        "$dns_csv" "$hostname_changed" "$JOIN_COMPUTER_NAME"

    if ! systemctl enable --now sssd.service; then
        set_current_phase "JOINED_DEGRADED" || true
        err "Domain join succeeded, but SSSD failed to start. AD DNS and snapshot are retained for repair/clean leave."
        journalctl -u sssd.service -n 60 --no-pager 2>/dev/null |
            tee "${snap}/sssd-failure.txt" || true
        return 1
    fi

    configure_mkhomedir "$snap" || \
        warn "Home-directory automation could not be fully configured."
    apply_access_policy "$domain" || \
        warn "Login authorization policy was not changed."

    test_user="$(ask 'Optional domain user for identity lookup validation (blank to skip)' '')"
    if postjoin_acceptance "$domain" "$test_user"; then
        set_current_phase "JOIN_PENDING_REBOOT" || true
        join_transaction_mark "$snap" "JOIN_PENDING_REBOOT"
        ok "Domain join passed immediate acceptance checks."
    else
        set_current_phase "JOINED_DEGRADED" || true
        join_transaction_mark "$snap" "JOINED_DEGRADED"
        err "The machine account was joined, but one or more acceptance checks failed."
        warn "Do not force local rollback. Repair the issue or use a clean domain leave."
        journalctl -u sssd.service -n 80 --no-pager 2>/dev/null \
            >"${snap}/sssd-postjoin-journal.txt" || true
        return 1
    fi

    info "Snapshot retained at: $snap"
    info "A reboot is required for final acceptance and lifecycle completion."
    if confirm "Reboot now?" N; then
        systemctl reboot
    fi
}

# ---------------------------------------------------------------------------
# IT administrator diagnostics / domain transition
# ---------------------------------------------------------------------------

collect_target_plan() {
    PRESET_DOMAIN="$(ask 'Target AD DNS domain (for example corp.example.com)' '')"
    PRESET_DOMAIN="${PRESET_DOMAIN,,}"
    valid_dns_domain "$PRESET_DOMAIN" || { err "A valid target DNS domain is required."; return 1; }

    PRESET_DNS="$(ask 'Target AD DNS server IPv4 addresses (comma separated)' '')"
    validate_dns_list "$PRESET_DNS" || { err "At least one valid target AD DNS IPv4 address is required."; return 1; }

    PRESET_HOSTNAME="$(ask 'System hostname' "$(hostnamectl --static 2>/dev/null || hostname)")"
    valid_system_hostname "$PRESET_HOSTNAME" || { err "Invalid system hostname."; return 1; }

    local short_default="${PRESET_HOSTNAME%%.*}"
    ((${#short_default} <= 15)) || short_default=""
    PRESET_COMPUTER="$(ask 'AD computer name (NetBIOS, max 15 chars)' "$short_default")"
    valid_ad_computer_name "$PRESET_COMPUTER" || { err "Invalid AD computer name."; return 1; }
    PRESET_COMPUTER="${PRESET_COMPUTER^^}"

    PRESET_OU="$(ask 'Computer OU DN (optional)' '')"
    if [[ -n "$PRESET_OU" && ! "$PRESET_OU" =~ ^(OU|CN)= ]]; then
        warn "OU path does not look like a distinguished name."
        confirm "Use this OU value anyway?" N || return 1
    fi

    printf '\nPOSIX identity model:\n  [1] Automatic SSSD SID -> UID/GID mapping\n  [2] RFC2307/POSIX attributes from AD\n'
    local map_choice="$(ask 'Select identity model' '1')"
    PRESET_ID_MAPPING="yes"
    [[ "$map_choice" == "2" ]] && PRESET_ID_MAPPING="no"

    local first_dns="$(dns_first "$PRESET_DNS")"
    select_join_interface "$first_dns" || return 1
    preflight_ad_dns_servers "$PRESET_DOMAIN" "$PRESET_DNS" || return 1
    validate_ad_network_ports "$PRESET_DOMAIN" "$PRESET_DNS" || return 1
    return 0
}

switch_domain_guided() {
    header
    printf '%bDOMAIN SWITCH%b\n\n' "$C_BOLD" "$C_RESET"

    local source="$(realm list --name-only 2>/dev/null | awk 'NR==1{print}')"
    if [[ -z "$source" ]]; then
        info "No current domain membership was detected; starting a normal join."
        join_domain_guided
        return $?
    fi

    collect_target_plan || return 1
    if [[ "${source,,}" == "${PRESET_DOMAIN,,}" ]]; then
        err "Source and target domains are the same."
        return 1
    fi

    printf '\nSource domain : %s\nTarget domain : %s\nTarget DNS    : %s\nComputer      : %s\n' \
        "$source" "$PRESET_DOMAIN" "$PRESET_DNS" "$PRESET_COMPUTER"
    confirm_literal "The source membership will be removed only after the target passed DNS/network preflight. The target join then starts immediately." "SWITCH" || return 0

    local leave_user="$(prompt_domain_admin_account 'remove this computer from the source domain' 'Administrator')"
    if ! realm leave -v -U "$leave_user" "$source"; then
        err "Source-domain leave failed. Target join was not attempted."
        return 1
    fi

    # Restore identity/DNS baseline when available, but preserve current hostname
    # and packages so the target join can proceed immediately.
    if [[ -f "$CURRENT_STATE" ]]; then
        local SNAPSHOT_PATH=""
        load_state_file "$CURRENT_STATE" || true
        if [[ -n "${SNAPSHOT_PATH:-}" && -d "$SNAPSHOT_PATH" ]]; then
            restore_network_from_snapshot "$SNAPSHOT_PATH" || warn "Source DNS restoration reported a problem."
            restore_identity_files "$SNAPSHOT_PATH"
            restore_sssd_runtime_from_snapshot "$SNAPSHOT_PATH"
        fi
        rm -f "$CURRENT_STATE"
    fi

    PRESET_SWITCH_MODE=1
    JOIN_TRANSACTION_ACTIVE=0
    JOIN_TRANSACTION_COMMITTED=0
    JOIN_TRANSACTION_ROLLBACK=0
    JOIN_TRANSACTION_SNAPSHOT=""
    join_domain_guided
    local rc=$?
    PRESET_SWITCH_MODE=0
    PRESET_DOMAIN="" PRESET_DNS="" PRESET_HOSTNAME="" PRESET_COMPUTER="" PRESET_OU="" PRESET_ID_MAPPING=""
    return "$rc"
}

ad_connectivity_test() {
    header
    printf '%bAD CONNECTIVITY TEST%b\n\n' "$C_BOLD" "$C_RESET"

    local domain="" dns_csv=""
    if [[ -f "$CURRENT_STATE" ]]; then
        local DOMAIN="" AD_DNS_SERVERS=""
        load_state_file "$CURRENT_STATE" || true
        domain="${DOMAIN:-}"
        dns_csv="${AD_DNS_SERVERS:-}"
    fi
    domain="$(ask 'AD DNS domain (for example corp.example.com)' "$domain")"
    dns_csv="$(ask 'AD DNS server IPv4 addresses (comma separated)' "$dns_csv")"
    valid_dns_domain "$domain" || { err "Invalid AD DNS domain."; return 1; }
    validate_dns_list "$dns_csv" || { err "Invalid AD DNS list."; return 1; }

    select_join_interface "$(dns_first "$dns_csv")" || return 1
    printf '\nNETWORK / DNS\n'
    local dns_rc=0 ports_rc=0 time_rc=0
    preflight_ad_dns_servers "$domain" "$dns_csv" || dns_rc=$?
    validate_ad_network_ports "$domain" "$dns_csv" || ports_rc=$?
    audit_time_sync || time_rc=$?

    printf '\nSYSTEM RESOLVER\n'
    if domain_srv_query "$domain" "" >/dev/null 2>&1; then
        ok "System resolver can locate AD domain controllers."
    else
        warn "System resolver cannot currently locate AD; direct AD DNS results above may still pass."
        resolver_diagnostics "$domain"
    fi

    printf '\nMEMBERSHIP\n'
    local memberships="$(realm list --name-only 2>/dev/null || true)"
    if [[ -n "$memberships" ]]; then
        ok "Realm membership: $memberships"
        if command_exists adcli && adcli testjoin -D "$domain" >/dev/null 2>&1; then
            ok "Secure machine channel validates with adcli."
        else
            warn "Secure machine channel did not validate for $domain."
        fi
    else
        info "Machine is not currently joined to a realm."
    fi

    printf '\nRESULT\n'
    if (( dns_rc == 0 && ports_rc == 0 && time_rc == 0 )); then
        ok "READY: DNS, required TCP ports and time synchronization are healthy."
        return 0
    fi
    err "BLOCKED/DEGRADED: one or more readiness checks failed. Review the diagnostics above."
    return 1
}

troubleshoot_ad() {
    header
    printf '%bAD TROUBLESHOOTER%b\n\n' "$C_BOLD" "$C_RESET"
    detect_active_interface
    detect_dns_backend
    detect_system_resolver

    printf '  Interface : %s\n  DNS owner : %s\n  Resolver  : %s\n  resolv.conf: %s\n\n' \
        "${ACTIVE_IFACE:-unknown}" "$DNS_BACKEND" "$SYSTEM_RESOLVER_BACKEND" "$RESOLV_CONF_TARGET"

    local domain=""
    if [[ -f "$CURRENT_STATE" ]]; then
        local DOMAIN=""
        load_state_file "$CURRENT_STATE" || true
        domain="${DOMAIN:-}"
    fi
    domain="$(ask 'AD DNS domain (for example corp.example.com)' "$domain")"
    [[ -n "$domain" ]] && resolver_diagnostics "$domain"

    printf '\nSERVICES\n'
    systemctl --no-pager --full status sssd.service 2>/dev/null | sed -n '1,12p' || true
    printf '\nRECENT SSSD LOGS\n'
    journalctl -u sssd.service -n 50 --no-pager 2>/dev/null | sed 's/^/  /' || true

    if [[ -s /etc/sssd/sssd.conf ]] && command_exists sssctl; then
        sssctl config-check 2>&1 | sed 's/^/  /' || true
    fi

    if incomplete_sssd_residue_present; then
        warn "Incomplete SSSD residue detected. Guided join can restore the previous snapshot before retrying."
    fi

    if [[ -n "$domain" && -f "$CURRENT_STATE" ]]; then
        local AD_DNS_SERVERS=""
        load_state_file "$CURRENT_STATE" || true
        if [[ -n "${AD_DNS_SERVERS:-}" ]] && ! domain_srv_query "$domain" "" >/dev/null 2>&1; then
            warn "Direct configuration exists but system AD discovery is failing."
            if confirm "Attempt safe resolver convergence repair using the assistant-managed AD DNS?" N; then
                repair_resolver_convergence "$domain" "$AD_DNS_SERVERS" "$ACTIVE_IFACE" || warn "Resolver repair did not fully converge."
            fi
        fi
    fi
}

export_diagnostic_bundle() {
    header
    local out="${LOG_ROOT}/diagnostic-${RUN_ID}.tar.gz"
    local tmp="${STATE_ROOT}/diagnostic-${RUN_ID}"
    rm -rf "$tmp" && mkdir -p "$tmp"
    {
        printf 'Generated: %s\n' "$(date -Is)"
        printf 'Host: %s\n' "$(hostname -f 2>/dev/null || hostname)"
        printf 'OS: %s\n' "$DISTRO_ID"
        printf 'Interface: %s\nDNS backend: %s\nResolver: %s\n' "$ACTIVE_IFACE" "$DNS_BACKEND" "$SYSTEM_RESOLVER_BACKEND"
        printf '\nRealm:\n'; realm list 2>&1 || true
        printf '\nRoutes:\n'; ip -4 route 2>&1 || true
        printf '\nAddresses:\n'; ip -4 addr 2>&1 || true
        printf '\nResolver:\n'; cat /etc/resolv.conf 2>&1 || true
    } >"$tmp/summary.txt"
    cp -a "$CURRENT_STATE" "$tmp/current.env" 2>/dev/null || true
    journalctl -u sssd.service -n 200 --no-pager >"$tmp/sssd-journal.txt" 2>&1 || true
    command_exists sssctl && sssctl config-check >"$tmp/sssd-config-check.txt" 2>&1 || true
    tar -C "$tmp" -czf "$out" . || { err "Could not create diagnostic bundle."; rm -rf "$tmp"; return 1; }
    rm -rf "$tmp"
    chmod 0600 "$out" 2>/dev/null || true
    ok "Diagnostic bundle created: $out"
    warn "Review the bundle before sharing; network/domain metadata is included. Passwords are never collected by this assistant."
}

# ---------------------------------------------------------------------------
# Audit / status / leave / restore
# ---------------------------------------------------------------------------

audit_readiness() {
    header
    printf '%bCLIENT READINESS%b\n\n' "$C_BOLD" "$C_RESET"

    printf 'Distribution    : %s\n' "$DISTRO_ID"
    printf 'Package family  : %s\n' "$PKG_FAMILY"
    printf 'Init/systemd    : %s\n' "$(command_exists systemctl && [[ -d /run/systemd/system ]] && printf supported || printf unsupported)"
    printf 'Suggested iface : %s\n' "${ACTIVE_IFACE:-unknown}"
    detect_system_resolver
    printf 'DNS config owner: %s\n' "$DNS_BACKEND"
    printf 'System resolver : %s\n' "$SYSTEM_RESOLVER_BACKEND"
    printf 'resolv.conf      : %s\n' "$RESOLV_CONF_TARGET"
    printf 'Remote session  : %s\n\n' "$REMOTE_SESSION"

    printf 'Active IPv4 interfaces:\n'
    show_network_candidates | while IFS=$'\t' read -r iface addr metric manager; do
        printf '  %-16s %-20s metric=%-6s %s\n' "$iface" "$addr" "$metric" "$manager"
    done

    printf '\nCurrent DNS:\n'
    current_dns_summary | sed 's/^/  /'
    printf '\n'

    validate_required_commands || true
    if incomplete_sssd_residue_present; then
        warn "Incomplete previous join residue detected: sss_cache is installed but SSSD is not initialized."
        info "Run the guided join again; it will offer snapshot-based recovery before continuing."
    fi
    audit_time_sync || true

    local realms=""
    realms="$(realm list --name-only 2>/dev/null || true)"
    if [[ -n "$realms" ]]; then ok "Realm membership detected: $realms"; else info "No realm membership detected."; fi

    [[ -s /etc/krb5.keytab ]] && info "Existing Kerberos keytab detected: /etc/krb5.keytab"
    [[ -s /etc/sssd/sssd.conf ]] && info "Existing SSSD configuration detected."

    if [[ -f "$CURRENT_STATE" ]]; then ok "Assistant-managed state exists: $CURRENT_STATE"; else info "No assistant-managed join state exists."; fi
}

status_domain() {
    header
    printf '%bDOMAIN CLIENT STATUS%b\n\n' "$C_BOLD" "$C_RESET"

    realm list 2>/dev/null || info "No realm membership reported."

    if [[ -f "$CURRENT_STATE" ]]; then
        local SNAPSHOT_PATH="" DOMAIN="" REALM="" AD_DNS_SERVERS="" HOSTNAME_CHANGED="" PHASE="" JOIN_BOOT_ID="" COMPUTER_NAME=""
        load_state_file "$CURRENT_STATE" || true
        printf '\nAssistant state:\n'
        printf '  Phase    : %s\n' "${PHASE:-legacy/unknown}"
        printf '  Domain   : %s\n' "${DOMAIN:-unknown}"
        printf '  Realm    : %s\n' "${REALM:-unknown}"
        printf '  Computer : %s\n' "${COMPUTER_NAME:-unknown}"
        printf '  DNS      : %s\n' "${AD_DNS_SERVERS:-unknown}"
        printf '  Snapshot : %s\n' "${SNAPSHOT_PATH:-unknown}"

        if [[ "${PHASE:-}" == "JOIN_PENDING_REBOOT" && -n "${JOIN_BOOT_ID:-}" && "$(current_boot_id)" != "$JOIN_BOOT_ID" ]]; then
            info "Post-reboot lifecycle transition detected; running final acceptance."
            if postjoin_acceptance "$DOMAIN" ""; then
                set_current_phase "JOINED" || true
                PHASE="JOINED"
                ok "Post-reboot domain acceptance passed."
            else
                set_current_phase "JOINED_DEGRADED" || true
                PHASE="JOINED_DEGRADED"
                warn "Post-reboot acceptance is degraded."
            fi
        elif [[ "${PHASE:-}" == "JOIN_PENDING_REBOOT" ]]; then
            warn "Final lifecycle acceptance is pending a reboot."
        elif [[ "${PHASE:-}" == "JOINED_DEGRADED" ]]; then
            info "Re-checking previously degraded join state."
            if postjoin_acceptance "$DOMAIN" ""; then
                set_current_phase "JOINED" || true
                PHASE="JOINED"
                ok "The repaired client now passes domain acceptance."
            fi
        fi

        if [[ -n "${DOMAIN:-}" ]] && command_exists adcli; then
            adcli testjoin -D "$DOMAIN" >/dev/null 2>&1 \
                && ok "Secure machine join validated by adcli." \
                || warn "adcli testjoin failed."
        fi
    fi

    printf '\nResolver:\n'
    current_dns_summary | sed 's/^/  /'
    audit_time_sync || true
}

restore_identity_files() {
    local snap="$1"
    restore_snapshot_file "$snap" /etc/krb5.conf
    restore_snapshot_file "$snap" /etc/krb5.keytab
    restore_snapshot_file "$snap" /etc/realmd.conf
    restore_snapshot_file "$snap" /etc/sssd/sssd.conf
    restore_snapshot_file "$snap" /etc/sssd/conf.d
    restore_snapshot_file "$snap" /etc/nsswitch.conf
    restore_snapshot_file "$snap" /etc/pam.d/common-session
    restore_snapshot_file "$snap" /etc/pam.d/common-session-noninteractive

    if command_exists authselect && [[ -f "${snap}/snapshot.env" ]]; then
        local AUTHSELECT_BACKUP="" AUTHSELECT_HAD_MKHOMEDIR=""
        load_state_file "${snap}/snapshot.env" || true
        if [[ -n "${AUTHSELECT_BACKUP:-}" ]]; then
            authselect backup-restore "$AUTHSELECT_BACKUP" >/dev/null 2>&1 || \
                warn "authselect backup restore failed; file-level snapshot was still restored."
        elif [[ "${AUTHSELECT_HAD_MKHOMEDIR:-0}" == "0" ]]; then
            authselect disable-feature with-mkhomedir >/dev/null 2>&1 || true
        fi
    fi
}

restore_sssd_runtime_from_snapshot() {
    local snap="$1"
    local PREJOIN_SSSD_ACTIVE="0" PREJOIN_SSSD_ENABLED="0"

    [[ -f "$snap/snapshot.env" ]] || return 0
    # shellcheck disable=SC1090
    . "$snap/snapshot.env"

    local sssd_units=""
    sssd_units="$(systemctl list-unit-files sssd.service --no-legend 2>/dev/null || true)"
    if ! grep -Fq 'sssd.service' <<<"$sssd_units"; then
        return 0
    fi

    if [[ "${PREJOIN_SSSD_ENABLED:-0}" == "1" ]]; then
        systemctl enable sssd.service >/dev/null 2>&1 || true
    else
        systemctl disable sssd.service >/dev/null 2>&1 || true
    fi

    if [[ "${PREJOIN_SSSD_ACTIVE:-0}" == "1" ]]; then
        systemctl restart sssd.service >/dev/null 2>&1 || \
            warn "Pre-join SSSD service state could not be restored completely."
    else
        systemctl stop sssd.service >/dev/null 2>&1 || true
    fi
}

rollback_failed_join_local_state() {
    local snap="$1" mode="${2:-interactive}"
    [[ -n "$snap" && -d "$snap" ]] || return 1

    JOIN_TRANSACTION_ROLLBACK=1
    JOIN_TRANSACTION_ACTIVE=0
    cleanup_private_ccache

    warn "Restoring local state because AD membership was not committed."
    restore_network_from_snapshot "$snap" || warn "DNS/network rollback reported a problem."
    restore_identity_files "$snap"
    restore_hostname_from_snapshot "$snap" || warn "Hostname rollback reported a problem."
    restore_sssd_runtime_from_snapshot "$snap"
    rm -f "$CURRENT_STATE" 2>/dev/null || true
    join_transaction_mark "$snap" "LOCAL_STATE_ROLLED_BACK"

    if [[ "$mode" == "interactive" &&
          -s "$snap/packages-installed-by-assistant.txt" ]]; then
        printf '\n'
        info "The failed attempt installed AD client packages that were absent before the snapshot."
        warn "If SSSD was never configured, keeping sssd-tools can produce sss_cache/config.ldb warnings on local user operations."
        if confirm "Remove only packages added by this failed attempt and fully return to the pre-join package baseline?" Y; then
            remove_assistant_packages_now "$snap" || \
                warn "Package rollback was incomplete; review the package manager output."
        else
            warn "Packages were retained for retry. SSSD-related tools may warn until a later join configures SSSD."
        fi
    fi

    JOIN_TRANSACTION_ROLLBACK=0
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
    leave_user="$(prompt_domain_admin_account 'remove this computer from the domain' 'Administrator')"

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
        ok "Pre-join local state restored, including DNS, identity files and keytab."

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

    [[ -f "$CURRENT_STATE" ]] || { err "No current assistant state exists."; return 1; }

    local SNAPSHOT_PATH="" DOMAIN=""
    load_state_file "$CURRENT_STATE" || return 1
    [[ -n "${SNAPSHOT_PATH:-}" && -d "$SNAPSHOT_PATH" ]] || { err "Recorded snapshot is unavailable."; return 1; }

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

    if [[ -s /etc/sssd/sssd.conf ]]; then
        systemctl restart sssd.service >/dev/null 2>&1 || true
    else
        systemctl stop sssd.service >/dev/null 2>&1 || true
    fi
    rm -f "$CURRENT_STATE"

    ok "Local pre-join state restored, including the pre-join Kerberos keytab state."
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
        printf '%bAD CLIENT OPERATIONS%b\n\n' "$C_BOLD" "$C_RESET"
        printf '  [1] %s\n' "$(ui_text 'Readiness audit')"
        printf '  [2] %s\n' "$(ui_text 'Guided domain join')"
        printf '  [3] %s\n' "$(ui_text 'Domain client status')"
        printf '  [4] %s\n' "$(ui_text 'Leave domain cleanly')"
        printf '  [5] %s\n' "$(ui_text 'Switch to another domain')"
        printf '  [6] %s\n' "$(ui_text 'AD connectivity test')"
        printf '  [7] %s\n' "$(ui_text 'Troubleshoot / repair')"
        printf '  [8] %s\n' "$(ui_text 'Export diagnostic bundle')"
        printf '  [9] %s\n' "$(ui_text 'Restore pre-join state')"
        printf '  [10] %s\n' "$(ui_text 'List snapshots')"
        printf '  [L] %s [%s]\n' "$(ui_text 'Language / Idioma')" "${UI_LANG^^}"
        printf '  [0] %s\n\n' "$(ui_text 'Exit')"

        local choice=""
        choice="$(ask 'Select operation' '1')" || return 0

        case "${choice^^}" in
            1) audit_readiness || true; pause_ui ;;
            2) join_domain_guided || warn "Join operation did not complete."; pause_ui ;;
            3) status_domain || true; pause_ui ;;
            4) leave_domain_cleanly || warn "Leave operation did not complete."; pause_ui ;;
            5) switch_domain_guided || warn "Domain switch did not complete."; pause_ui ;;
            6) ad_connectivity_test || true; pause_ui ;;
            7) troubleshoot_ad || true; pause_ui ;;
            8) export_diagnostic_bundle || true; pause_ui ;;
            9) restore_prejoin_state || warn "Restore operation did not complete."; pause_ui ;;
            10) list_snapshots || true; pause_ui ;;
            L) toggle_ui_language ;;
            0) return 0 ;;
            *) warn "Unknown option."; pause_ui ;;
        esac

        detect_os
        detect_active_interface
        detect_dns_backend
        detect_system_resolver
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
  --switch                  Preflight target, leave source, join target
  --connectivity            AD DNS/network/time connectivity test
  --troubleshoot            Guided local AD troubleshooting
  --diagnostics             Export a local diagnostic bundle
  --restore                 Restore pre-join local state
  --snapshots               List local snapshots
  --lang en|es              UI language
  --no-color                Disable ANSI color
  --help                    Show this help

State:
  $STATE_ROOT

Recovery snapshots:
  $BACKUP_ROOT

Logs:
  $LOG_ROOT

Administrator is the default join/leave account but can be overridden at the credential step.
DHCP addressing is supported; a static client IP is not required. AD DNS must also forward external DNS before the assistant replaces the client resolver.
No password is persisted, no third-party repository is added, and supported joins use a private Kerberos cache.
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
            --switch) mode="switch" ;;
            --connectivity) mode="connectivity" ;;
            --troubleshoot) mode="troubleshoot" ;;
            --diagnostics) mode="diagnostics" ;;
            --lang)
                shift
                (($#)) || { printf "Missing value for --lang (en|es).\n" >&2; return 2; }
                set_ui_language "$1" || return 2
                ;;
            --lang=*) set_ui_language "${1#*=}" || return 2 ;;
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
        switch) switch_domain_guided ;;
        connectivity) ad_connectivity_test ;;
        troubleshoot) troubleshoot_ad ;;
        diagnostics) export_diagnostic_bundle ;;
        restore) restore_prejoin_state ;;
        snapshots) list_snapshots ;;
    esac
}

main "$@"
