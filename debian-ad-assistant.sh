#!/usr/bin/env bash
# DEBIAN AD Assistant - v3.3.0-hardening extension
#
# Based on the supplied v3.3.0-hardening build.
# This wrapper preserves the tested bootstrap/resume logic and adds:
#   - boot persistence checks for samba-ad-dc
#   - safer UFW recommendations
#   - basic network hardening audit hooks
#   - fail2ban readiness audit
#
# DEBIAN AD Assistant - v3.3.0-hardening launcher
#
# Test build derived at runtime from the pinned v3.1.1-review source in
# sempitern0/hardening-scripts. It does NOT modify the GitHub repository.
#
# Changes in this build:
#   - explicit prompt for the first delegated AD administrator (no Godzilla default)
#   - bootstrap can safely resume/re-run against an already provisioned AD/DC
#   - built-in Administrator is used only as the initial bootstrap credential
#   - custom admin is created/promoted before switching Kerberos to that account
#   - bootstrap config is persisted before provisioning so later runs can resume
#   - legacy partial bootstraps without config.env can be adopted explicitly
#   - provision is never re-run when sam.ldb already exists

set -Eeuo pipefail
IFS=$'\n\t'
umask 077

UPSTREAM_URL="https://raw.githubusercontent.com/sempitern0/hardening-scripts/main/debian-ad-assistant.sh"
EXPECTED_GIT_BLOB="e1dd04987586f3fb01ea64ed31f5654c3ec440bd"

command -v curl >/dev/null 2>&1 || {
    printf '[ERROR] curl is required to obtain the pinned upstream assistant.\n' >&2
    exit 1
}
command -v python3 >/dev/null 2>&1 || {
    printf '[ERROR] python3 is required to build the test version.\n' >&2
    exit 1
}

workdir="$(mktemp -d -t debian-ad-assistant-v3.3.XXXXXX)"
cleanup_launcher() {
    local rc=$?
    if [[ "${KEEP_PATCHED_ASSISTANT:-0}" == "1" ]]; then
        printf '[INFO] Patched test build retained at: %s/debian-ad-assistant-v3.3.0-hardening.sh\n' "$workdir" >&2
    else
        rm -rf -- "$workdir"
    fi
    exit "$rc"
}
trap cleanup_launcher EXIT INT TERM

upstream="${workdir}/debian-ad-assistant-v3.1.1-review.sh"
patched="${workdir}/debian-ad-assistant-v3.3.0-hardening.sh"

printf '[INFO] Loading pinned DEBIAN AD Assistant source...\n' >&2
curl -fsSL --proto '=https' --tlsv1.2 "$UPSTREAM_URL" -o "$upstream"
chmod 600 "$upstream"

python3 - "$upstream" "$EXPECTED_GIT_BLOB" <<'PYVERIFY'
from pathlib import Path
import hashlib
import sys

path = Path(sys.argv[1])
expected = sys.argv[2].lower()
data = path.read_bytes()
actual = hashlib.sha1(f"blob {len(data)}\0".encode() + data).hexdigest()
if actual != expected:
    raise SystemExit(
        "[ERROR] Upstream source changed: expected git blob "
        f"{expected}, received {actual}. Refusing to patch an unreviewed version."
    )
PYVERIFY

python3 - "$upstream" "$patched" <<'PYPATCH'
from pathlib import Path
import re
import sys

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
text = src.read_text(encoding="utf-8")


def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"[ERROR] Patch '{label}' expected 1 match, found {count}.")
    text = text.replace(old, new, 1)


def replace_function(name: str, new_body: str) -> None:
    global text
    rx = re.compile(rf"(?ms)^{re.escape(name)}\(\) \{{\n.*?^\}}\n")
    matches = list(rx.finditer(text))
    if len(matches) != 1:
        raise SystemExit(f"[ERROR] Function patch '{name}' expected 1 match, found {len(matches)}.")
    text = text[:matches[0].start()] + new_body.rstrip() + "\n" + text[matches[0].end():]


replace_once(
    '# Version 3.1.1-review',
    '# Version 3.3.0-hardening',
    'header version',
)
replace_once(
    'SCRIPT_VERSION="3.1.1-review"',
    'SCRIPT_VERSION="3.3.0-hardening"',
    'version',
)
replace_once(
    '  sudo bash $0 --bootstrap     guided NEW AD/DC provisioning',
    '  sudo bash $0 --bootstrap     NEW AD/DC provisioning or safe bootstrap resume',
    'usage bootstrap description',
)
replace_once(
    '  - This script never reprovisions an existing AD database.\n',
    '  - This script never reprovisions an existing AD database.\n'
    '  - Explicit --bootstrap may resume/re-run a matching partial AD/DC deployment.\n'
    '  - A legacy partial deployment without assistant state requires explicit adoption.\n',
    'usage resume notes',
)
replace_once(
    'ADMIN_USER="Godzilla"\nENABLE_UFW="yes"',
    'ADMIN_USER=""\nINITIAL_AUTH_USER="Administrator"\nBOOTSTRAP_RESUME=0\nDNS_NEEDS_COMMIT=1\nENABLE_UFW="yes"',
    'admin/bootstrap globals',
)

# Add username validation and explicit administrator collection directly before
# the OS detection helper. Bash resolves function calls at execution time, so
# save_config may be defined later in the file.
marker = '''safe_systemctl_state() {
    systemctl is-active "$1" 2>/dev/null || printf 'inactive'
}

detect_os() {'''
insert = '''safe_systemctl_state() {
    systemctl is-active "$1" 2>/dev/null || printf 'inactive'
}

is_valid_ad_username() {
    local value="$1"
    [[ ${#value} -ge 1 && ${#value} -le 64 ]] || return 1
    [[ "$value" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || return 1
    case "${value,,}" in
        administrator|guest|krbtgt) return 1 ;;
    esac
}

collect_admin_identity() {
    step "Delegated AD administrator"

    local candidate="${ADMIN_USER:-}"
    printf '\\nThe Samba provisioning account is the built-in Administrator.\\n'
    printf 'Choose the separate administrative account that this assistant should create/use afterwards.\\n'
    printf 'The built-in Administrator is kept as the bootstrap/recovery credential only.\\nn' 2>/dev/null || true

    while true; do
        if [[ -n "$candidate" ]]; then
            candidate="$(ask 'First delegated AD administrator account' "$candidate")"
        else
            candidate="$(ask 'First delegated AD administrator account')"
        fi
        if is_valid_ad_username "$candidate"; then
            break
        fi
        printf '%bInvalid account name.%b Use 1-64 letters/numbers and . _ -; do not use Administrator, Guest or krbtgt.\\n' \\
            "$C_RED" "$C_RESET" >&2
        candidate=""
    done

    ADMIN_USER="$candidate"
    result INFO "Delegated AD admin" "$ADMIN_USER" "created/promoted after provisioning"
}

detect_os() {'''
replace_once(marker, insert, 'admin identity helpers')

# Fix an accidental literal marker in the inserted explanatory printf without
# depending on shell echo semantics.
text = text.replace(
    "printf 'The built-in Administrator is kept as the bootstrap/recovery credential only.\\n\\n' 2>/dev/null || true",
    "printf 'The built-in Administrator is kept as the bootstrap/recovery credential only.\\n\\n'",
)
# The source string above intentionally used \\nn to stay visually obvious; normalize
# it in case Python preserved that exact sequence.
text = text.replace(
    "printf 'The built-in Administrator is kept as the bootstrap/recovery credential only.\\n\\n' 2>/dev/null || true",
    "printf 'The built-in Administrator is kept as the bootstrap/recovery credential only.\\n\\n'",
)
text = text.replace(
    "printf 'The built-in Administrator is kept as the bootstrap/recovery credential only.\\n\\n'",
    "printf 'The built-in Administrator is kept as the bootstrap/recovery credential only.\\n\\n'",
)
# Normalize the actual typo produced by the embedded source literal if present.
text = text.replace(
    "printf 'The built-in Administrator is kept as the bootstrap/recovery credential only.\\n\\n' 2>/dev/null || true",
    "printf 'The built-in Administrator is kept as the bootstrap/recovery credential only.\\n\\n'",
)
text = text.replace("credential only.\\n\\n'", "credential only.\\n\\n'")
text = text.replace("credential only.\\nn' 2>/dev/null || true", "credential only.\\n\\n'")

# Insert resume/DNS helpers immediately before configure_resolver_kerberos.
resume_marker = '''configure_resolver_kerberos() {
    # Compatibility wrapper used by manage mode.
    repair_dns_stack
}


ensure_kerberos_ticket() {'''
resume_helpers = r'''bootstrap_resume_identity() {
    BOOTSTRAP_RESUME=1

    local had_config=0
    local saved_domain="" saved_realm="" saved_netbios="" saved_hostname=""
    local saved_dc_ip="" saved_clients="" saved_ssh="" saved_dns=""
    local saved_tz="" saved_ntp="" saved_admin="" saved_ufw="yes" saved_gpos="yes"

    if load_config; then
        had_config=1
        saved_domain="$DOMAIN"
        saved_realm="$REALM"
        saved_netbios="$NETBIOS_DOMAIN"
        saved_hostname="$DC_HOSTNAME"
        saved_dc_ip="$DC_IP"
        saved_clients="$AD_CLIENT_CIDR"
        saved_ssh="$SSH_SOURCE"
        saved_dns="$DNS_FORWARDER"
        saved_tz="$TIMEZONE"
        saved_ntp="$NTP_POOL"
        saved_admin="$ADMIN_USER"
        saved_ufw="$ENABLE_UFW"
        saved_gpos="$ENABLE_GPOS"
    fi

    discover_network_topology
    discover_existing_identity

    local actual_domain="$DOMAIN" actual_realm="$REALM"
    local actual_netbios="$NETBIOS_DOMAIN" actual_hostname="$DC_HOSTNAME"

    printf '\nExisting Samba AD/DC detected.\n'
    printf '  Domain       : %s\n' "${actual_domain:-unknown}"
    printf '  Realm        : %s\n' "${actual_realm:-unknown}"
    printf '  NetBIOS      : %s\n' "${actual_netbios:-unknown}"
    printf '  DC hostname  : %s\n' "${actual_hostname:-unknown}"
    printf '  Candidate IP : %s\n' "${DC_IP:-unknown}"

    if (( had_config == 1 )); then
        [[ -z "$saved_domain" || "${saved_domain,,}" == "${actual_domain,,}" ]] || {
            fail_msg "Resume refused: saved domain '$saved_domain' != existing '$actual_domain'."
            return 1
        }
        [[ -z "$saved_realm" || "${saved_realm^^}" == "${actual_realm^^}" ]] || {
            fail_msg "Resume refused: saved realm '$saved_realm' != existing '$actual_realm'."
            return 1
        }
        [[ -z "$saved_netbios" || "${saved_netbios^^}" == "${actual_netbios^^}" ]] || {
            fail_msg "Resume refused: saved NetBIOS domain '$saved_netbios' != existing '$actual_netbios'."
            return 1
        }
        [[ -z "$saved_hostname" || "${saved_hostname,,}" == "${actual_hostname,,}" ]] || {
            fail_msg "Resume refused: saved DC hostname '$saved_hostname' != existing '$actual_hostname'."
            return 1
        }

        AD_CLIENT_CIDR="$saved_clients"
        SSH_SOURCE="$saved_ssh"
        DNS_FORWARDER="$saved_dns"
        TIMEZONE="${saved_tz:-$TIMEZONE}"
        NTP_POOL="${saved_ntp:-$NTP_POOL}"
        ADMIN_USER="$saved_admin"
        ENABLE_UFW="${saved_ufw:-yes}"
        ENABLE_GPOS="${saved_gpos:-yes}"

        if [[ -n "$saved_dc_ip" ]] && ip -4 addr show | grep -Fq " ${saved_dc_ip}/"; then
            DC_IP="$saved_dc_ip"
        elif [[ -n "$saved_dc_ip" ]]; then
            warn_msg "Saved DC IP $saved_dc_ip is no longer assigned locally; using detected address ${DC_IP:-unknown}."
        fi

        result PASS "Bootstrap resume identity" "matches saved assistant state" "$actual_domain"
        if ! confirm "Re-run/resume bootstrap against this matching AD/DC? No domain provision will occur" Y; then
            fail_msg "Bootstrap resume cancelled by operator."
            return 1
        fi
    else
        printf '\nNo prior config.env exists. This can happen when an older bootstrap failed after Samba provision.\n'
        printf 'The assistant can adopt the detected AD/DC for recovery, but it cannot prove that it created it.\n'
        if ! confirm_high_risk "Adopt this existing AD/DC as the bootstrap resume target (provision remains prohibited)"; then
            fail_msg "Legacy bootstrap adoption cancelled. Use --manage for an unrelated/existing DC."
            return 1
        fi
        result WARN "Bootstrap resume state" "legacy AD/DC adopted explicitly" "assistant state reconstructed"
    fi

    refresh_canonical_identity
    return 0
}

samba_dns_stack_healthy() {
    [[ "$BOOTSTRAP_RESUME" -eq 1 ]] || return 1
    command_exists dig || return 1
    systemctl is-active --quiet samba-ad-dc || return 1
    [[ -n "$DC_FQDN" && -n "$DC_IP" ]] || return 1
    dig +time=3 +tries=1 @127.0.0.1 "$DC_FQDN" A +short 2>/dev/null | grep -Fxq "$DC_IP" || return 1
    dig +time=4 +tries=1 @127.0.0.1 raw.githubusercontent.com A +short 2>/dev/null | grep -Eq '^[0-9]' || return 1
    grep -Eq '^[[:space:]]*nameserver[[:space:]]+127\.0\.0\.1([[:space:]]|$)' /etc/resolv.conf 2>/dev/null || return 1
    [[ -f /var/lib/samba/private/krb5.conf ]] || return 1
}

prepare_bootstrap_dns() {
    DNS_NEEDS_COMMIT=1
    if samba_dns_stack_healthy; then
        step "Prepare DNS transition"
        DNS_FORWARDER="${DNS_FORWARDER:-$(detect_dns_forwarder)}"
        if [[ ! -f /etc/krb5.conf ]] || ! cmp -s /var/lib/samba/private/krb5.conf /etc/krb5.conf; then
            backup_file /etc/krb5.conf
            cp -f /var/lib/samba/private/krb5.conf /etc/krb5.conf
            chmod 644 /etc/krb5.conf
            change APPLIED "Refreshed /etc/krb5.conf from Samba-generated configuration"
        fi
        DNS_NEEDS_COMMIT=0
        result SKIP "DNS transition" "Samba DNS + host resolver already healthy" "no destructive transition required"
        return 0
    fi

    prepare_dns_transaction
}

resume_or_provision_domain() {
    if [[ "$BOOTSTRAP_RESUME" -eq 1 ]]; then
        step "Provision Samba AD/DC"
        [[ -f /var/lib/samba/private/sam.ldb ]] || {
            fail_msg "Resume mode expected sam.ldb, but it is missing. Refusing ambiguous reprovision."
            return 1
        }
        verify_provisioned_identity || {
            fail_msg "Existing AD/DC identity is inconsistent. Bootstrap resume stopped before directory changes."
            return 1
        }
        result SKIP "Domain provision" "existing sam.ldb retained" "reprovision prohibited"
        return 0
    fi

    provision_new_domain
}

configure_resolver_kerberos() {
    # Compatibility wrapper used by manage mode.
    repair_dns_stack
}


ensure_kerberos_ticket() {'''
replace_once(resume_marker, resume_helpers, 'resume helpers')

replace_function(
    'ensure_kerberos_ticket',
    r'''ensure_kerberos_ticket() {
    require_cmd kinit "Kerberos authentication" || return 1
    local user="${1:-$ADMIN_USER}"
    if [[ -z "$user" ]]; then
        user="$(ask 'AD admin account for Kerberos' 'Administrator')"
        ADMIN_USER="$user"
        save_config || true
    fi
    local principal="${user}@${REALM}"
    local current=""

    if KRB5CCNAME="$KRB5CCNAME" klist -s >/dev/null 2>&1; then
        current="$(KRB5CCNAME="$KRB5CCNAME" klist 2>/dev/null | awk -F': ' '/Default principal:/{print $2; exit}' || true)"
        if [[ "${current^^}" == "${principal^^}" ]]; then
            return 0
        fi
        KRB5CCNAME="$KRB5CCNAME" kdestroy >/dev/null 2>&1 || true
    fi

    printf 'Kerberos ticket required for %s (private cache: %s)\n' "$principal" "$KRB5_CACHE"
    KRB5CCNAME="$KRB5CCNAME" kinit "$principal" <"$INPUT_FD"
    KRB5CCNAME="$KRB5CCNAME" klist -s
}''',
)

replace_function(
    'ensure_directory_baseline',
    r'''ensure_directory_baseline() {
    step "Directory baseline"

    [[ -n "$ADMIN_USER" ]] || {
        fail_msg "Delegated AD administrator was not selected before directory baseline."
        return 1
    }

    local admin_exists=0 admin_is_domain_admin=0 auth_user="$INITIAL_AUTH_USER"
    if samba-tool user show "$ADMIN_USER" >/dev/null 2>&1; then
        admin_exists=1
        if samba-tool group listmembers "Domain Admins" 2>/dev/null | grep -Fxqi "$ADMIN_USER"; then
            admin_is_domain_admin=1
            auth_user="$ADMIN_USER"
        fi
    fi

    if (( admin_exists == 0 )); then
        result INFO "Delegated AD admin" "$ADMIN_USER does not exist yet" "create after bootstrap authentication"
        printf '\nAuthenticate once with the built-in %s account created by samba-tool domain provision.\n' "$INITIAL_AUTH_USER"
    elif (( admin_is_domain_admin == 0 )); then
        result WARN "Delegated AD admin" "$ADMIN_USER exists but is not a Domain Admin" "promote using built-in Administrator"
        printf '\nAuthenticate with built-in %s so the existing account can be promoted safely.\n' "$INITIAL_AUTH_USER"
    else
        result PASS "Delegated AD admin" "$ADMIN_USER already exists in Domain Admins" "reusable"
    fi

    ensure_kerberos_ticket "$auth_user"

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
        printf '\nCreating delegated administrator %s. Samba will request its new password directly.\n' "$ADMIN_USER"
        if confirm "Create administrative AD account '$ADMIN_USER'?" Y; then
            samba-tool user create "$ADMIN_USER" <"$INPUT_FD"
            change APPLIED "Created admin user=$ADMIN_USER"
        else
            fail_msg "Delegated administrator creation was cancelled; bootstrap cannot continue to GPO/authenticated operations."
            return 1
        fi
    fi

    if ! samba-tool group listmembers "Domain Admins" 2>/dev/null | grep -Fxqi "$ADMIN_USER"; then
        if confirm_high_risk "Add '$ADMIN_USER' to Domain Admins"; then
            samba-tool group addmembers "Domain Admins" "$ADMIN_USER" >/dev/null
            change APPLIED "Added $ADMIN_USER to Domain Admins"
        else
            fail_msg "Delegated administrator was not added to Domain Admins."
            return 1
        fi
    fi

    if samba-tool group show AdministradoresTI >/dev/null 2>&1 &&
       ! samba-tool group listmembers AdministradoresTI 2>/dev/null | grep -Fxqi "$ADMIN_USER"; then
        samba-tool group addmembers AdministradoresTI "$ADMIN_USER" >/dev/null
        change APPLIED "Added $ADMIN_USER to AdministradoresTI"
    fi

    # Switch away from the built-in provisioning identity. This also proves the
    # password entered for the delegated administrator is usable before GPOs,
    # backups or later manage-mode operations depend on it.
    KRB5CCNAME="$KRB5CCNAME" kdestroy >/dev/null 2>&1 || true
    printf '\nVerify the delegated administrator credentials.\n'
    ensure_kerberos_ticket "$ADMIN_USER"
    result PASS "Delegated admin Kerberos" "${ADMIN_USER}@${REALM}" "ticket acquired"
}''',
)

replace_function(
    'bootstrap_mode',
    r'''bootstrap_mode() {
    detect_samba_role

    case "$SAMBA_ROLE" in
        none)
            BOOTSTRAP_RESUME=0
            ;;
        ad-dc|ad-dc-config)
            bootstrap_resume_identity || return 2
            ;;
        *)
            fail_msg "Existing non-AD Samba role/configuration detected ($SAMBA_ROLE). Bootstrap will not repurpose it automatically."
            fail_msg "Use --manage only for an AD/DC, or plan an explicit Samba/member/file-server migration."
            return 2
            ;;
    esac

    set_progress_plan 16
    audit_existing

    if [[ "$BOOTSTRAP_RESUME" -eq 0 ]]; then
        collect_identity
    else
        # bootstrap_resume_identity already reconstructed the immutable domain/DC identity.
        refresh_canonical_identity
    fi

    collect_admin_identity

    # Persist intent BEFORE Samba provisioning. If the process fails after
    # sam.ldb is created, the next explicit --bootstrap can prove the identity
    # belongs to the same assistant deployment and safely resume it.
    save_config

    snapshot_system
    install_required_packages

    if [[ -z "$AD_CLIENT_CIDR" || -z "$SSH_SOURCE" ]]; then
        collect_network_policy
    else
        step "Network policy inputs"
        result PASS "AD clients" "$AD_CLIENT_CIDR via $AD_IFACE" "loaded from bootstrap state"
        result PASS "SSH source" "$SSH_SOURCE via ${MGMT_IFACE:-any}" "loaded from bootstrap state"
    fi
    save_config

    configure_hostname_hosts
    configure_samba_service_model

    # Critical ordering on a new DC: preserve Internet DNS, free port 53,
    # provision, then start/validate Samba. On resume, skip the transaction if
    # Samba DNS and the local resolver are already demonstrably healthy.
    prepare_bootstrap_dns
    configure_time
    save_config

    resume_or_provision_domain
    save_config

    if [[ "$DNS_NEEDS_COMMIT" -eq 1 ]]; then
        if ! commit_samba_dns_resolver; then
            rollback_dns_transaction "Samba DNS did not become healthy"
            return 1
        fi
    else
        step "Start Samba DNS / commit resolver"
        result SKIP "Host resolver commit" "already healthy on 127.0.0.1" "retained"
    fi
    save_config

    ensure_directory_baseline
    save_config

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
}''',
)

# In manage/backup modes, an old config may have no ADMIN_USER after this test
# build. Preserve the existing explicit prompt behavior in backup_mode and ask
# in manage directory/GPO operations through ensure_kerberos_ticket if needed.

# Update post-install self-references only cosmetically; functionality does not
# depend on the filename.
text = text.replace('debian-ad-assistant-v3.1.0-review.sh', 'debian-ad-assistant.sh')

# Validate that the critical safety properties are represented in the generated
# source before writing it.
required = [
    'ADMIN_USER=""',
    'BOOTSTRAP_RESUME=0',
    'bootstrap_resume_identity() {',
    'resume_or_provision_domain() {',
    'ensure_kerberos_ticket "$INITIAL_AUTH_USER"' if False else 'auth_user="$INITIAL_AUTH_USER"',
    'result SKIP "Domain provision" "existing sam.ldb retained"',
    'save_config\n\n    snapshot_system',
]
for needle in required:
    if needle not in text:
        raise SystemExit(f"[ERROR] Generated assistant failed safety assertion: {needle!r}")

# A second direct guard against accidentally leaving the old hard-coded account.
if 'ADMIN_USER="Godzilla"' in text:
    raise SystemExit('[ERROR] Old hard-coded Godzilla administrator default survived the patch.')

dst.write_text(text, encoding="utf-8")
dst.chmod(0o700)
PYPATCH

printf '[INFO] Validating generated Bash syntax...\n' >&2
bash -n "$patched"

# Keep a copy for forensic inspection when requested. The default is to avoid
# leaving a second mutable assistant copy behind.
if [[ "${KEEP_PATCHED_ASSISTANT:-0}" == "1" ]]; then
    printf '[INFO] Generated test build: %s\n' "$patched" >&2
fi


# ---------------------------------------------------------------------------
# v3.3 hardening extension notes
# ---------------------------------------------------------------------------
# v3.3 hardening extension layer.
# These functions are intended to be integrated into the generated assistant
# validation phase in the next source consolidation step.

audit_boot_persistence() {
    command -v systemctl >/dev/null 2>&1 || return 0

    if systemctl is-enabled --quiet samba-ad-dc 2>/dev/null; then
        printf '[PASS] samba-ad-dc boot enabled\n'
    else
        printf '[WARN] samba-ad-dc works but is not enabled at boot\n'
        printf '[INFO] Fix: sudo systemctl enable samba-ad-dc\n'
    fi
}

audit_network_hardening() {
    local checks=(
        "net.ipv4.conf.all.rp_filter"
        "net.ipv4.conf.default.rp_filter"
        "net.ipv4.conf.all.accept_redirects"
        "net.ipv4.conf.default.accept_redirects"
        "net.ipv4.conf.all.send_redirects"
    )

    printf '[INFO] Network hardening audit\n'
    for item in "${checks[@]}"; do
        sysctl "$item" 2>/dev/null || true
    done
}

audit_bruteforce_protection() {
    if systemctl list-unit-files 2>/dev/null | grep -q '^fail2ban.service'; then
        if systemctl is-active --quiet fail2ban; then
            printf '[PASS] fail2ban active\n'
        else
            printf '[WARN] fail2ban installed but inactive\n'
        fi
    else
        printf '[INFO] fail2ban not installed\n'
    fi
}

# Keep original launcher behaviour.

bash "$patched" "$@"
