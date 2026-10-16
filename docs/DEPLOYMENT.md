# Launching and deploying on target hosts

[Español](DEPLOYMENT_ES.md) · [Overview](../README.md) · [Operations](OPERATIONS.md)

The six root assistants remain standalone: copy an individual script without cloning the repository or installing Python. RabbitMole is a separate project; these assistants need neither its server nor its PWA.

## Select the target

| Target | Script | Non-elevated check | Next step, elevated |
|---|---|---|---|
| Debian/Ubuntu Samba DC | `debian-ad-assistant.sh` | `bash ./debian-ad-assistant.sh --preflight` | `sudo bash ./debian-ad-assistant.sh --audit` |
| Rocky/AlmaLinux Samba DC | `rhel-ad-assistant.sh` | `bash ./rhel-ad-assistant.sh --preflight` | `sudo bash ./rhel-ad-assistant.sh --audit` |
| Linux AD client | `linux-ad-client-assistant.sh` | `bash ./linux-ad-client-assistant.sh --preflight` | `sudo bash ./linux-ad-client-assistant.sh --audit` |
| RHEL-branded Linux client | `rhel-ad-client-assistant.sh` | `bash ./rhel-ad-client-assistant.sh --preflight` | `sudo bash ./rhel-ad-client-assistant.sh --audit` |
| Windows Server / AD DS | `windows-ad-assistant.ps1` | `powershell.exe -NoProfile -File .\windows-ad-assistant.ps1 -Mode Preflight` | `powershell.exe -NoProfile -File .\windows-ad-assistant.ps1 -Mode Audit` |
| Windows client / member server | `windows-ad-client-assistant.ps1` | `powershell.exe -NoProfile -File .\windows-ad-client-assistant.ps1 -Mode Preflight` | `powershell.exe -NoProfile -File .\windows-ad-client-assistant.ps1 -Mode Audit` |

Run the script on the host it manages; a client requires the client assistant. Linux lifecycle operations require Bash and a running systemd host, not a minimal container. Windows requires Windows PowerShell 5.1 or PowerShell 7 and the components used by the selected operation. The existing unsupported Samba AD DC provisioning gate on RHEL remains in place.

`Preflight` checks platform and local command availability without elevation, installation, configuration changes, logs or credentials. Exit **0** means no detected blockers; **1** means blockers. Role dependency warnings do not change that status and must be reviewed. This is not a DNS, AD permission or membership test. `Audit` inspects real host/domain state and may write logs/reports and perform network queries.

## Obtain an approved revision

In **GitHub Actions → sysadmin standalone verification**, select a successful run for your approved commit and download `sysadmin-<SHA>`. Its ZIP contains scripts, documentation, `release.json` and `SHA256SUMS`. Packaging runs only after both Linux and Windows checks pass. Extract to a dedicated directory, check the revision and retain it with your change evidence.

On Linux:

```bash
sha256sum -c SHA256SUMS
bash -n ./linux-ad-client-assistant.sh
bash ./linux-ad-client-assistant.sh --preflight
```

On Windows, validate the selected script before running it:

```powershell
$file = 'windows-ad-client-assistant.ps1'
$line = Get-Content .\SHA256SUMS | Where-Object { $_.EndsWith("  $file") }
if (@($line).Count -ne 1) { throw 'Missing or duplicate checksum' }
if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $line.Substring(0,64)) {
    throw 'File does not match the package'
}
$tokens = $null; $errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path $file).Path, [ref]$tokens, [ref]$errors)
if ($errors) { $errors | Format-List; throw 'Syntax errors' }
powershell.exe -NoProfile -File .\windows-ad-client-assistant.ps1 -Mode Preflight
```

Checksums detect differences from the package; they do not replace a trusted source or signing. Follow your organization's approved execution/signing policy. These instructions require neither a policy change nor `ExecutionPolicy Bypass`.

To download one file, replace the full 40-character revision below:

```bash
revision='REPLACE_WITH_APPROVED_40_CHARACTER_COMMIT_SHA'
curl --fail --show-error --location --proto '=https' \
  "https://raw.githubusercontent.com/sempitern0/sysadmin/${revision}/linux-ad-client-assistant.sh" \
  --output linux-ad-client-assistant.sh
# Review and compare its hash with your approved reference before execution.
bash -n ./linux-ad-client-assistant.sh
bash ./linux-ad-client-assistant.sh --preflight
```

A `main` URL can change between hosts; it is not an approved release identifier. Download to a file instead of piping network content into Bash or `Invoke-Expression`.

## Local and remote operation

After preflight, run the elevated audit, inspect its findings, then open the menu:

```bash
sudo bash ./linux-ad-client-assistant.sh --manage --lang en
```

For SSH, transfer the verified file and preserve a terminal for menus, sudo and credentials:

```bash
scp ./linux-ad-client-assistant.sh operator@client:/home/operator/linux-ad-client-assistant.sh
ssh -t operator@client 'bash /home/operator/linux-ad-client-assistant.sh --preflight'
ssh -t operator@client 'sudo bash /home/operator/linux-ad-client-assistant.sh --audit'
# After reviewing the audit:
ssh -t operator@client 'sudo bash /home/operator/linux-ad-client-assistant.sh --manage --lang en'
```

Adapt users and paths. Keep SSH host-key verification; do not embed passwords. Interactive launch paths now reject a missing terminal before initializing administrative runtime state.

On Windows, copy to an administrator-managed tools directory and use an elevated Windows PowerShell console:

```powershell
powershell.exe -NoProfile -File C:\AdminTools\windows-ad-client-assistant.ps1 -Mode Audit -Language en
powershell.exe -NoProfile -File C:\AdminTools\windows-ad-client-assistant.ps1 -Mode Interactive -Language en
```

Menus and credential dialogs need an interactive session. Existing fleet tooling can copy the approved revision and collect `Preflight` output/exit codes. Do not treat Join, Reset, hardening or repairs as unattended audits. Preflight does not configure WinRM or deploy agents.

## Scheduled operations and upgrades

Use stable absolute paths and an appropriately privileged account. Built-in task/service registration references the script path: do not register from Downloads or a temporary directory. Inspect tasks and services before relocating the script. Do not run simultaneous membership/configuration operations on a host.

Windows Server modes `IDSReport`, `IDSResponseCleanup` and `IDSAwarenessCheck` now propagate caught failures to the process. Review task status and logs. Audit findings are not universally mapped to failing exit codes; inspect reports too.

For upgrades, retain the previous revision, review the diff and CI result, replace the file during your maintenance window and repeat preflight → audit. Preserve state, snapshots and local keys.

## Lab acceptance

1. Use a disposable VM matching the destination OS family/version.
2. Run preflight/audit; review DNS, time, permissions and alternate console access.
3. Exercise the intended change against a lab domain and test credentials.
4. Reboot and validate DNS, authentication, services and remote access.
5. Rehearse recovery from snapshot/backup; retain results and script revision.

CI validates syntax, static errors and isolated behavior. It does not provision a domain or certify recovery, hardening or target connectivity. See [maintenance and coverage](MAINTENANCE.md).
