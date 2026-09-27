#requires -RunAsAdministrator
<#
.SYNOPSIS
    PyME Windows Server Security Assistant - v0.3.0-review

.DESCRIPTION
    Audit-first, role-aware Windows Server security assistant.

    Primary targets:
      - Windows Server 2019
      - Windows Server 2022
      - Windows Server 2025
      - Windows PowerShell 5.1+

    Design:
      - Audit before modification.
      - No blanket "CIS compliant" claim: controls are baseline-oriented.
      - Snapshot/change-set before remediation.
      - Explicit confirmation per change.
      - Remote-session-aware firewall protection.
      - Re-audit after remediation.
      - Built-in Microsoft tooling first; no mandatory third-party modules.
      - Console progress with fallback to normal log lines.

    Examples:
      .\pymes-windows-server-security-v0.3.0-review.ps1
      .\pymes-windows-server-security-v0.3.0-review.ps1 -Mode Audit
      .\pymes-windows-server-security-v0.3.0-review.ps1 -Mode Harden
      .\pymes-windows-server-security-v0.3.0-review.ps1 -Mode Backup
      .\pymes-windows-server-security-v0.3.0-review.ps1 -Mode Audit -NoColor

.NOTES
    Review candidate. Validate in a lab before production deployment.
#>

[CmdletBinding()]
param(
    [ValidateSet('Interactive','Audit','Harden','Backup')]
    [string]$Mode = 'Interactive',

    [string]$ExportPath = "$env:ProgramData\PyMESecurity",

    [switch]$NoColor,

    # Firewall default-policy changes during RDP/WinRM are skipped unless this
    # switch is explicitly supplied. Even then, HIGH-impact confirmation is required.
    [switch]$AllowRemoteFirewallChange
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Runtime state
# ---------------------------------------------------------------------------

$script:Version = '0.3.0-review'
$script:Started = Get-Date
$script:Results = New-Object 'System.Collections.Generic.List[object]'
$script:Changes = New-Object 'System.Collections.Generic.List[object]'
$script:Warnings = New-Object 'System.Collections.Generic.List[string]'
$script:Step = 0
$script:TotalSteps = 1
$script:LogFile = $null
$script:ReportFile = $null
$script:RunPath = $null
$script:BackupPath = $null
$script:SnapshotCreated = $false
$script:IsRemoteSession = $false
$script:RemoteKind = 'Local/Console'
$script:IsDomainController = $false
$script:ServerInfo = $null
$script:RoleInfo = @()
$script:PowerShellMajor = $PSVersionTable.PSVersion.Major

function Test-IsInteractiveConsole {
    try {
        return (-not [Console]::IsOutputRedirected)
    }
    catch {
        return $true
    }
}

$script:UseColor = (-not $NoColor) -and (Test-IsInteractiveConsole) -and (-not $env:NO_COLOR)

function Initialize-Runtime {
    if (-not (Test-Path -LiteralPath $ExportPath)) {
        New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $script:RunPath = Join-Path $ExportPath "runs\$timestamp-$PID"
    $script:BackupPath = Join-Path $script:RunPath 'backup'
    New-Item -ItemType Directory -Path $script:BackupPath -Force | Out-Null

    $script:LogFile = Join-Path $ExportPath "security-assistant-$timestamp-$PID.log"
    $script:ReportFile = Join-Path $ExportPath "security-report-$timestamp-$PID.json"

    New-Item -ItemType File -Path $script:LogFile -Force | Out-Null
}

function Write-Console {
    param(
        [Parameter(Mandatory=$true)][string]$Text,
        [ValidateSet('Default','Cyan','Green','Yellow','Red','Magenta','Gray')]
        [string]$Color = 'Default',
        [switch]$NoNewline
    )

    if (-not $script:UseColor -or $Color -eq 'Default') {
        if ($NoNewline) { Write-Host $Text -NoNewline }
        else { Write-Host $Text }
        return
    }

    if ($NoNewline) { Write-Host $Text -ForegroundColor $Color -NoNewline }
    else { Write-Host $Text -ForegroundColor $Color }
}

function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('INFO','OK','WARN','ERROR','CHANGE','DEBUG')]
        [string]$Level = 'INFO'
    )

    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8

    switch ($Level) {
        'OK'     { Write-Console $line Green }
        'WARN'   { Write-Console $line Yellow }
        'ERROR'  { Write-Console $line Red }
        'CHANGE' { Write-Console $line Magenta }
        'DEBUG'  { Write-Console $line Gray }
        default  { Write-Console $line }
    }
}

function Write-Banner {
    Write-Console ('=' * 78) Cyan
    Write-Console (' PyME Windows Server Security Assistant v{0}' -f $script:Version) Cyan
    Write-Console (' Mode={0} | PowerShell={1} | Session={2}' -f $Mode, $PSVersionTable.PSVersion, $script:RemoteKind) Cyan
    Write-Console ('=' * 78) Cyan
}

function Set-StepPlan {
    param([Parameter(Mandatory=$true)][int]$Total)
    $script:TotalSteps = [Math]::Max(1, $Total)
    $script:Step = 0
}

function Write-Step {
    param([Parameter(Mandatory=$true)][string]$Title)

    $script:Step++
    $percent = [Math]::Min(100, [int](($script:Step / $script:TotalSteps) * 100))

    if (Test-IsInteractiveConsole) {
        Write-Progress -Activity 'Windows Server Security Assistant' -Status $Title -PercentComplete $percent
    }

    Write-Console ''
    Write-Console ('[{0:d2}/{1:d2}] {2}' -f $script:Step, $script:TotalSteps, $Title) Cyan
}

function Complete-Progress {
    try { Write-Progress -Activity 'Windows Server Security Assistant' -Completed } catch {}
}

function Add-Result {
    param(
        [Parameter(Mandatory=$true)][string]$Category,
        [Parameter(Mandatory=$true)][string]$Control,
        [ValidateSet('PASS','WARN','FAIL','INFO','SKIP','ERROR','MANAGED')]
        [Parameter(Mandatory=$true)][string]$Status,
        [Parameter(Mandatory=$true)][string]$Current,
        [Parameter(Mandatory=$true)][string]$Expected,
        [string]$Remediation = '',
        [string]$Reference = ''
    )

    $obj = [pscustomobject]@{
        Category    = $Category
        Control     = $Control
        Status      = $Status
        Current     = $Current
        Expected    = $Expected
        Remediation = $Remediation
        Reference   = $Reference
    }
    [void]$script:Results.Add($obj)

    $prefix = switch ($Status) {
        'PASS'    { '[PASS]' }
        'WARN'    { '[WARN]' }
        'FAIL'    { '[FAIL]' }
        'ERROR'   { '[ERR ]' }
        'SKIP'    { '[SKIP]' }
        'MANAGED' { '[MGMT]' }
        default   { '[INFO]' }
    }
    $color = switch ($Status) {
        'PASS'    { 'Green' }
        'WARN'    { 'Yellow' }
        'FAIL'    { 'Red' }
        'ERROR'   { 'Red' }
        'SKIP'    { 'Yellow' }
        'MANAGED' { 'Cyan' }
        default   { 'Gray' }
    }

    Write-Console ('{0,-7} {1,-34} {2}' -f $prefix, $Control, $Current) $color
}

function Add-Warning {
    param([string]$Message)
    [void]$script:Warnings.Add($Message)
    Write-Log $Message WARN
}

function Test-Command {
    param([Parameter(Mandatory=$true)][string]$Name)
    return [bool](Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

function Confirm-Action {
    param(
        [Parameter(Mandatory=$true)][string]$Action,
        [Parameter(Mandatory=$true)][string]$Reason,
        [ValidateSet('LOW','MEDIUM','HIGH')]
        [string]$Impact = 'LOW'
    )

    if ($Mode -eq 'Audit' -or $Mode -eq 'Backup') {
        return $false
    }

    Write-Console ''
    Write-Console 'ACTION REQUIRES CONFIRMATION' Yellow
    Write-Console ('  Action : {0}' -f $Action)
    Write-Console ('  Reason : {0}' -f $Reason)
    Write-Console ('  Impact : {0}' -f $Impact)

    if ($Impact -eq 'HIGH') {
        $answer = Read-Host 'Type APPLY to continue'
        return ($answer -ceq 'APPLY')
    }

    do {
        $answer = (Read-Host 'Apply this change? [Y/N]').Trim().ToUpperInvariant()
    } while ($answer -notin @('Y','N'))

    return ($answer -eq 'Y')
}

function Add-Change {
    param(
        [string]$Name,
        [ValidateSet('APPLIED','SKIPPED','FAILED')][string]$Status,
        [string]$Reason,
        [string]$ErrorMessage = ''
    )

    [void]$script:Changes.Add([pscustomobject]@{
        Time   = Get-Date
        Name   = $Name
        Status = $Status
        Reason = $Reason
        Error  = $ErrorMessage
    })
}

function Invoke-Change {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Reason,
        [Parameter(Mandatory=$true)][scriptblock]$Action,
        [ValidateSet('LOW','MEDIUM','HIGH')][string]$Impact = 'LOW',
        [scriptblock]$PostCheck
    )

    if (-not (Confirm-Action -Action $Name -Reason $Reason -Impact $Impact)) {
        Add-Change -Name $Name -Status SKIPPED -Reason $Reason
        Write-Log "Skipped: $Name" WARN
        return $false
    }

    if (-not $script:SnapshotCreated) {
        New-ChangeSet
    }

    try {
        & $Action

        if ($PostCheck) {
            $ok = & $PostCheck
            if (-not $ok) {
                throw 'Post-change validation failed.'
            }
        }

        Add-Change -Name $Name -Status APPLIED -Reason $Reason
        Write-Log "Applied: $Name" CHANGE
        return $true
    }
    catch {
        Add-Change -Name $Name -Status FAILED -Reason $Reason -ErrorMessage $_.Exception.Message
        Write-Log ("Failed: {0} :: {1}" -f $Name, $_.Exception.Message) ERROR
        return $false
    }
}

# ---------------------------------------------------------------------------
# Discovery / compatibility
# ---------------------------------------------------------------------------

function Get-ServerInfo {
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem

    [pscustomobject]@{
        ComputerName = $env:COMPUTERNAME
        Domain       = $cs.Domain
        PartOfDomain = [bool]$cs.PartOfDomain
        DomainRole   = [int]$cs.DomainRole
        Manufacturer = $cs.Manufacturer
        Model        = $cs.Model
        OS           = $os.Caption
        Version      = $os.Version
        Build        = [int]$os.BuildNumber
        InstallDate  = $os.InstallDate
        LastBoot     = $os.LastBootUpTime
        Architecture = $os.OSArchitecture
    }
}

function Test-IsDomainController {
    param($Info = $script:ServerInfo)
    if ($null -eq $Info) { return $false }
    return ($Info.DomainRole -in @(4,5))
}

function Get-SessionContext {
    $remote = $false
    $kind = 'Local/Console'

    if ($env:SESSIONNAME -like 'RDP-*') {
        $remote = $true
        $kind = 'RDP'
    }

    $sender = Get-Variable -Name PSSenderInfo -ErrorAction SilentlyContinue
    if ($sender -and $sender.Value) {
        $remote = $true
        $kind = 'PowerShell Remoting'
    }

    [pscustomobject]@{
        IsRemote = $remote
        Kind     = $kind
    }
}

function Get-WindowsServerGeneration {
    param($Info)

    # Windows Server build families:
    # 17763 -> 2019, 20348 -> 2022, 26100+ -> 2025 generation.
    if ($Info.Build -ge 26100) { return '2025' }
    if ($Info.Build -ge 20348) { return '2022' }
    if ($Info.Build -ge 17763) { return '2019' }
    return 'UNTESTED'
}

function Get-InstalledServerRoles {
    $roles = @()

    if (Test-Command 'Get-WindowsFeature') {
        try {
            $roles = @(Get-WindowsFeature | Where-Object {
                $_.Installed -and (
                    $_.Name -in @(
                        'AD-Domain-Services','DNS','DHCP','FS-FileServer',
                        'Hyper-V','Web-Server','RDS-RD-Server','Failover-Clustering'
                    )
                )
            } | Select-Object Name, DisplayName, Installed)
        }
        catch {
            Add-Warning ("Role discovery failed: {0}" -f $_.Exception.Message)
        }
    }

    return $roles
}

function Initialize-Discovery {
    $ctx = Get-SessionContext
    $script:IsRemoteSession = $ctx.IsRemote
    $script:RemoteKind = $ctx.Kind
    $script:ServerInfo = Get-ServerInfo
    $script:IsDomainController = Test-IsDomainController
    $script:RoleInfo = @(Get-InstalledServerRoles)
}

function Audit-Compatibility {
    Write-Step 'Compatibility / runtime'

    $generation = Get-WindowsServerGeneration -Info $script:ServerInfo
    $supported = $generation -in @('2019','2022','2025')

    Add-Result 'System' 'Windows Server generation' `
        $(if ($supported) { 'PASS' } else { 'WARN' }) `
        ("{0}; build {1}" -f $generation, $script:ServerInfo.Build) `
        'Windows Server 2019/2022/2025' `
        'Treat untested builds conservatively.'

    Add-Result 'System' 'Windows PowerShell' `
        $(if ($script:PowerShellMajor -ge 5) { 'PASS' } else { 'WARN' }) `
        $PSVersionTable.PSVersion.ToString() `
        '5.1+ preferred' `
        'Some built-in security cmdlets require modern Windows PowerShell.'

    Add-Result 'System' 'Session context' 'INFO' $script:RemoteKind 'Known before network changes' ''

    if ($script:IsDomainController) {
        Add-Result 'System' 'Domain Controller role' 'INFO' 'YES' 'Role-aware baseline' `
            'DC-specific policy must be distinguished from member-server policy.'
    }
    else {
        Add-Result 'System' 'Domain Controller role' 'INFO' 'NO' 'Role-aware baseline' ''
    }

    if ($script:RoleInfo.Count -gt 0) {
        foreach ($role in $script:RoleInfo) {
            Add-Result 'System' ("Role {0}" -f $role.Name) 'INFO' 'Installed' 'Role-aware hardening' ''
        }
    }
    else {
        Add-Result 'System' 'Server role inventory' 'INFO' 'No tracked roles / cmdlet unavailable' 'Inventory before hardening' ''
    }
}

# ---------------------------------------------------------------------------
# Backups / change-set
# ---------------------------------------------------------------------------

function Export-RegistryKey {
    param(
        [Parameter(Mandatory=$true)][string]$RegistryPath,
        [Parameter(Mandatory=$true)][string]$FileName
    )

    if (-not (Test-Command 'reg.exe')) { return }

    $dest = Join-Path $script:BackupPath $FileName
    & reg.exe export $RegistryPath $dest /y *> $null
}

function New-ChangeSet {
    if ($script:SnapshotCreated) {
        return
    }

    Write-Log ("Creating change-set backup: {0}" -f $script:BackupPath) INFO

    # Basic system evidence
    $script:ServerInfo | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath (Join-Path $script:BackupPath 'server-info.json') -Encoding UTF8

    $script:RoleInfo | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath (Join-Path $script:BackupPath 'server-roles.json') -Encoding UTF8

    try {
        Get-NetIPConfiguration | Select-Object InterfaceAlias, InterfaceIndex, IPv4Address, IPv4DefaultGateway, DnsServer |
            ConvertTo-Json -Depth 8 |
            Set-Content -LiteralPath (Join-Path $script:BackupPath 'network.json') -Encoding UTF8
    }
    catch {
        Add-Warning ("Network snapshot failed: {0}" -f $_.Exception.Message)
    }

    # Firewall export is Microsoft-native and restorable with netsh advfirewall import.
    if (Test-Command 'netsh.exe') {
        $firewallFile = Join-Path $script:BackupPath 'firewall.wfw'
        & netsh.exe advfirewall export $firewallFile *> $null
    }

    if (Test-Command 'Get-NetFirewallProfile') {
        Get-NetFirewallProfile |
            Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction, NotifyOnListen, LogFileName |
            ConvertTo-Json -Depth 5 |
            Set-Content -LiteralPath (Join-Path $script:BackupPath 'firewall-profiles.json') -Encoding UTF8
    }

    if (Test-Command 'Get-SmbServerConfiguration') {
        Get-SmbServerConfiguration |
            ConvertTo-Json -Depth 5 |
            Set-Content -LiteralPath (Join-Path $script:BackupPath 'smb-server.json') -Encoding UTF8
    }
    if (Test-Command 'Get-SmbClientConfiguration') {
        Get-SmbClientConfiguration |
            ConvertTo-Json -Depth 5 |
            Set-Content -LiteralPath (Join-Path $script:BackupPath 'smb-client.json') -Encoding UTF8
    }

    if (Test-Command 'Get-MpPreference') {
        try {
            Get-MpPreference |
                ConvertTo-Json -Depth 8 |
                Set-Content -LiteralPath (Join-Path $script:BackupPath 'defender-preference.json') -Encoding UTF8
        }
        catch {
            Add-Warning ("Defender preference snapshot failed: {0}" -f $_.Exception.Message)
        }
    }

    Export-RegistryKey 'HKLM\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' 'reg-dnsclient.reg'
    Export-RegistryKey 'HKLM\SOFTWARE\Policies\Microsoft\Windows\PowerShell' 'reg-powershell.reg'
    Export-RegistryKey 'HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server' 'reg-terminal-server.reg'

    if (Test-Command 'secedit.exe') {
        try {
            & secedit.exe /export /cfg (Join-Path $script:BackupPath 'local-security-policy.inf') /quiet *> $null
        }
        catch {
            Add-Warning ("secedit export failed: {0}" -f $_.Exception.Message)
        }
    }

    $restore = @'
CHANGE-SET RESTORE NOTES
========================

This folder is a safety snapshot, not an automatic full-system restore point.

Firewall:
  netsh advfirewall import .\firewall.wfw

Registry:
  Review each .reg file and import only if rollback is required:
  reg import .\reg-dnsclient.reg
  reg import .\reg-powershell.reg
  reg import .\reg-terminal-server.reg

SMB / Defender:
  JSON files are evidence of the previous state. Restore deliberately with
  Set-Smb* / Set-MpPreference commands after reviewing the captured values.

Local security policy:
  local-security-policy.inf is evidence/export. Importing security policy can
  have broad impact and is intentionally not automated by this assistant.

Always validate connectivity and role health after rollback.
'@
    Set-Content -LiteralPath (Join-Path $script:BackupPath 'RESTORE.txt') -Value $restore -Encoding UTF8

    $script:SnapshotCreated = $true
    Write-Log 'Change-set backup completed.' OK
}

function Run-BackupOnly {
    Write-Step 'Create configuration change-set'
    New-ChangeSet
    Add-Result 'Recovery' 'Configuration backup' 'PASS' $script:BackupPath 'Backup created before changes' ''
}

# ---------------------------------------------------------------------------
# Registry helpers
# ---------------------------------------------------------------------------

function Get-RegistryValueSafe {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Name
    )

    try {
        $item = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction Stop
        return $item.$Name
    }
    catch {
        return $null
    }
}

function Test-RegistryEquals {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)]$ExpectedValue
    )

    $value = Get-RegistryValueSafe -Path $Path -Name $Name
    if ($null -eq $value) { return $false }
    return ($value -eq $ExpectedValue)
}

# ---------------------------------------------------------------------------
# Audit controls
# ---------------------------------------------------------------------------

function Audit-Network {
    Write-Step 'Network / Firewall'

    try {
        $adapters = @(Get-NetIPConfiguration | Where-Object {
            $_.IPv4Address -and $_.NetAdapter.Status -eq 'Up'
        })

        foreach ($a in $adapters) {
            $ips = @($a.IPv4Address | ForEach-Object { $_.IPv4Address }) -join ', '
            $dns = @($a.DnsServer.ServerAddresses) -join ', '
            $gw = @($a.IPv4DefaultGateway | ForEach-Object { $_.NextHop }) -join ', '
            Add-Result 'Network' ("Adapter {0}" -f $a.InterfaceAlias) 'INFO' `
                ("IPv4={0}; Gateway={1}; DNS={2}" -f $ips, $gw, $dns) `
                'Documented expected configuration' ''
        }
    }
    catch {
        Add-Result 'Network' 'Network configuration' 'ERROR' $_.Exception.Message 'Readable' ''
    }

    if (-not (Test-Command 'Get-NetFirewallProfile')) {
        Add-Result 'Network' 'Firewall cmdlets' 'ERROR' 'Unavailable' 'Available' ''
        return
    }

    try {
        foreach ($p in Get-NetFirewallProfile) {
            $status = if ($p.Enabled -and $p.DefaultInboundAction -eq 'Block') { 'PASS' } else { 'FAIL' }
            Add-Result 'Network' ("Firewall {0}" -f $p.Name) $status `
                ("Enabled={0}, Inbound={1}, Outbound={2}" -f $p.Enabled, $p.DefaultInboundAction, $p.DefaultOutboundAction) `
                'Enabled; default inbound Block' `
                'Review exceptions and management paths before remediation.'
        }
    }
    catch {
        Add-Result 'Network' 'Firewall profiles' 'ERROR' $_.Exception.Message 'Readable' ''
    }
}

function Audit-Defender {
    Write-Step 'Microsoft Defender'

    if (-not (Test-Command 'Get-MpComputerStatus')) {
        Add-Result 'Endpoint' 'Microsoft Defender' 'WARN' 'Cmdlets unavailable' 'Managed AV/EDR known' ''
        return
    }

    try {
        $d = Get-MpComputerStatus

        $mode = 'Unknown'
        if ($d.PSObject.Properties.Name -contains 'AMRunningMode') {
            $mode = [string]$d.AMRunningMode
        }

        Add-Result 'Endpoint' 'Defender running mode' 'INFO' $mode `
            'Understand active/passive/EDR state' `
            'Do not force Defender settings blindly when another managed AV/EDR owns protection.'

        $managedOrPassive = $mode -match 'Passive|EDR Block|SxS'

        foreach ($check in @(
            @{ Name='Defender service'; Property='AMServiceEnabled' },
            @{ Name='Realtime protection'; Property='RealTimeProtectionEnabled' },
            @{ Name='Behavior monitoring'; Property='BehaviorMonitorEnabled' },
            @{ Name='IOAV protection'; Property='IOAVProtectionEnabled' }
        )) {
            $value = $d.($check.Property)
            $status = if ($value) { 'PASS' } elseif ($managedOrPassive) { 'MANAGED' } else { 'FAIL' }
            Add-Result 'Endpoint' $check.Name $status ("{0}={1}" -f $check.Property, $value) 'Enabled or intentionally managed' ''
        }

        if ($d.PSObject.Properties.Name -contains 'IsTamperProtected') {
            Add-Result 'Endpoint' 'Tamper protection' `
                $(if ($d.IsTamperProtected) { 'PASS' } else { 'WARN' }) `
                ("IsTamperProtected={0}" -f $d.IsTamperProtected) `
                'Enabled where supported/managed' ''
        }

        if (Test-Command 'Get-MpPreference') {
            $p = Get-MpPreference
            Add-Result 'Endpoint' 'PUA protection' `
                $(if ([int]$p.PUAProtection -eq 1) { 'PASS' } else { 'WARN' }) `
                ("PUAProtection={0}" -f $p.PUAProtection) `
                'Enabled' 'Enable if compatible with application policy.'
        }
    }
    catch {
        Add-Result 'Endpoint' 'Defender state' 'ERROR' $_.Exception.Message 'Readable' ''
    }
}

function Audit-StoragePlatform {
    Write-Step 'BitLocker / TPM / Secure Boot'

    if (Test-Command 'Get-BitLockerVolume') {
        try {
            foreach ($v in Get-BitLockerVolume) {
                $encrypted = $v.VolumeStatus -eq 'FullyEncrypted'
                $protected = $v.ProtectionStatus -eq 'On'
                $protectors = @($v.KeyProtector | ForEach-Object { $_.KeyProtectorType }) -join ', '
                $status = if ($encrypted -and $protected) { 'PASS' } else { 'WARN' }

                Add-Result 'Storage' ("BitLocker {0}" -f $v.MountPoint) $status `
                    ("VolumeStatus={0}; Protection={1}; Method={2}; Protectors={3}" -f `
                        $v.VolumeStatus, $v.ProtectionStatus, $v.EncryptionMethod, $protectors) `
                    'Encrypted + protection on + recovery process documented' `
                    'Verify recovery-key escrow according to AD/Entra/enterprise policy.'
            }
        }
        catch {
            Add-Result 'Storage' 'BitLocker' 'ERROR' $_.Exception.Message 'Readable' ''
        }
    }
    else {
        Add-Result 'Storage' 'BitLocker cmdlets' 'SKIP' 'Unavailable' 'Role/feature dependent' ''
    }

    if (Test-Command 'Get-Tpm') {
        try {
            $tpm = Get-Tpm
            Add-Result 'Platform' 'TPM' `
                $(if ($tpm.TpmPresent -and $tpm.TpmReady) { 'PASS' } else { 'WARN' }) `
                ("Present={0}; Ready={1}" -f $tpm.TpmPresent, $tpm.TpmReady) `
                'Present and ready where hardware supports it' ''
        }
        catch {
            Add-Result 'Platform' 'TPM' 'WARN' $_.Exception.Message 'Hardware dependent' ''
        }
    }

    if (Test-Command 'Confirm-SecureBootUEFI') {
        try {
            $secure = Confirm-SecureBootUEFI -ErrorAction Stop
            Add-Result 'Platform' 'Secure Boot' $(if ($secure) { 'PASS' } else { 'WARN' }) `
                ([string]$secure) 'Enabled where supported' ''
        }
        catch {
            Add-Result 'Platform' 'Secure Boot' 'INFO' 'Unavailable/legacy/unsupported' 'Hardware dependent' ''
        }
    }
}

function Audit-SMB {
    Write-Step 'SMB / legacy protocols'

    if (Test-Command 'Get-WindowsOptionalFeature') {
        try {
            $smb1 = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction Stop
            Add-Result 'Network' 'SMBv1 feature' `
                $(if ($smb1.State -eq 'Disabled') { 'PASS' } else { 'FAIL' }) `
                ("State={0}" -f $smb1.State) 'Disabled' `
                'Disable/remove after validating legacy dependencies.'
        }
        catch {
            Add-Result 'Network' 'SMBv1 feature' 'INFO' 'Feature query unavailable' 'Disabled' ''
        }
    }

    if (Test-Command 'Get-SmbServerConfiguration') {
        try {
            $smb = Get-SmbServerConfiguration
            Add-Result 'Network' 'SMB server signing enabled' `
                $(if ($smb.EnableSecuritySignature) { 'PASS' } else { 'WARN' }) `
                ("Enable={0}; Require={1}" -f $smb.EnableSecuritySignature, $smb.RequireSecuritySignature) `
                'Enabled; requirement role/baseline dependent' ''

            Add-Result 'Network' 'SMB server signing required' `
                $(if ($smb.RequireSecuritySignature) { 'PASS' } elseif ($smb.EnableSecuritySignature) { 'WARN' } else { 'FAIL' }) `
                ("RequireSecuritySignature={0}" -f $smb.RequireSecuritySignature) `
                'Evaluate against role/version baseline' `
                'For Server 2025, prefer Microsoft baseline guidance and audit compatibility first.'
        }
        catch {
            Add-Result 'Network' 'SMB server configuration' 'ERROR' $_.Exception.Message 'Readable' ''
        }
    }

    if (Test-Command 'Get-SmbClientConfiguration') {
        try {
            $c = Get-SmbClientConfiguration
            Add-Result 'Network' 'SMB insecure guest logons' `
                $(if (-not $c.EnableInsecureGuestLogons) { 'PASS' } else { 'FAIL' }) `
                ("EnableInsecureGuestLogons={0}" -f $c.EnableInsecureGuestLogons) `
                'False' ''
        }
        catch {
            Add-Result 'Network' 'SMB client configuration' 'ERROR' $_.Exception.Message 'Readable' ''
        }
    }
}

function Audit-RemoteAccess {
    Write-Step 'Remote access'

    try {
        $ts = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
        $rdpEnabled = ($ts.fDenyTSConnections -eq 0)

        Add-Result 'Remote Access' 'RDP enabled' 'INFO' `
            ("Enabled={0}" -f $rdpEnabled) `
            'Documented and network-restricted' `
            'Prefer VPN/jump host; avoid direct Internet exposure.'

        $nlaPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
        $nla = Get-RegistryValueSafe -Path $nlaPath -Name 'UserAuthentication'
        Add-Result 'Remote Access' 'RDP NLA' `
            $(if ($nla -eq 1) { 'PASS' } else { 'FAIL' }) `
            ("UserAuthentication={0}" -f $nla) '1' 'Enable NLA after compatibility validation.'
    }
    catch {
        Add-Result 'Remote Access' 'RDP configuration' 'ERROR' $_.Exception.Message 'Readable' ''
    }

    if (Test-Command 'Get-Service') {
        foreach ($svc in @('WinRM','TermService')) {
            try {
                $s = Get-Service -Name $svc -ErrorAction Stop
                Add-Result 'Remote Access' ("Service {0}" -f $svc) 'INFO' ([string]$s.Status) 'Documented' ''
            }
            catch {}
        }
    }
}

function Audit-Administrators {
    Write-Step 'Administrative access / LAPS'

    if ($script:IsDomainController) {
        Add-Result 'Identity' 'Local Administrators' 'SKIP' `
            'Domain Controller: no normal local SAM administration model' `
            'Audit domain privileged groups instead' `
            'Use AD tooling to review Domain Admins, Enterprise Admins, Administrators, delegated groups.'
    }
    elseif (Test-Command 'Get-LocalGroupMember') {
        try {
            $members = @(Get-LocalGroupMember -SID 'S-1-5-32-544')
            $rendered = @($members | ForEach-Object {
                '{0} [{1}] SID={2}' -f $_.Name, $_.ObjectClass, $_.SID
            })

            $rendered | ForEach-Object { Write-Console ("  {0}" -f $_) Gray }

            # Do not guess "allowed admins" from localized names. Human review is safer.
            Add-Result 'Identity' 'Local Administrators' 'INFO' `
                ("{0} member(s); SID-based inventory captured" -f $members.Count) `
                'Minimum necessary membership' `
                'Compare member SIDs against an explicit allow-list for the organization.'
        }
        catch {
            Add-Result 'Identity' 'Local Administrators' 'ERROR' $_.Exception.Message 'Readable' ''
        }
    }
    else {
        Add-Result 'Identity' 'Local Administrators' 'SKIP' 'LocalAccounts cmdlets unavailable' 'Inventory' ''
    }

    if (Test-Command 'Get-LapsADPasswordPolicy') {
        try {
            $null = Get-LapsADPasswordPolicy -ErrorAction Stop
            Add-Result 'Identity' 'Windows LAPS (AD)' 'INFO' 'Policy cmdlets available/readable' 'Managed policy verified' `
                'Capability is not proof of successful password backup/rotation.'
        }
        catch {
            Add-Result 'Identity' 'Windows LAPS (AD)' 'WARN' 'Cmdlets available; policy query failed' 'Managed' ''
        }
    }
    elseif (Test-Command 'Get-LapsAADPasswordPolicy') {
        try {
            $null = Get-LapsAADPasswordPolicy -ErrorAction Stop
            Add-Result 'Identity' 'Windows LAPS (Entra)' 'INFO' 'Policy cmdlets available/readable' 'Managed policy verified' ''
        }
        catch {
            Add-Result 'Identity' 'Windows LAPS (Entra)' 'WARN' 'Cmdlets available; policy query failed' 'Managed' ''
        }
    }
    else {
        Add-Result 'Identity' 'Windows LAPS' 'WARN' 'LAPS cmdlets not detected' 'Evaluate Windows LAPS' ''
    }
}

function Audit-LoggingNameResolution {
    Write-Step 'PowerShell logging / name resolution'

    $psBase = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell'
    $scriptBlock = Test-RegistryEquals `
        -Path "$psBase\ScriptBlockLogging" `
        -Name 'EnableScriptBlockLogging' `
        -ExpectedValue 1

    $moduleEnabled = Test-RegistryEquals `
        -Path "$psBase\ModuleLogging" `
        -Name 'EnableModuleLogging' `
        -ExpectedValue 1

    $moduleNamesPath = "$psBase\ModuleLogging\ModuleNames"
    $moduleNamesPresent = Test-Path -LiteralPath $moduleNamesPath

    Add-Result 'Logging' 'PowerShell Script Block Logging' `
        $(if ($scriptBlock) { 'PASS' } else { 'WARN' }) `
        $(if ($scriptBlock) { 'Enabled' } else { 'Not detected' }) `
        'Enabled where log handling/privacy policy permits' `
        'Script block logs can contain sensitive data; plan retention and SIEM access.'

    $moduleStatus = if ($moduleEnabled -and $moduleNamesPresent) { 'PASS' } elseif ($moduleEnabled) { 'WARN' } else { 'WARN' }
    Add-Result 'Logging' 'PowerShell Module Logging' $moduleStatus `
        ("Enabled={0}; ModuleNamesConfigured={1}" -f $moduleEnabled, $moduleNamesPresent) `
        'Enabled + module list configured' `
        'Enabling the policy alone is incomplete without ModuleNames.'

    # FIX from v0.2.0: EnableMulticast=0 means LLMNR is disabled.
    $llmnrPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'
    $llmnrValue = Get-RegistryValueSafe -Path $llmnrPath -Name 'EnableMulticast'
    $llmnrDisabled = ($llmnrValue -eq 0)

    Add-Result 'Network' 'LLMNR' `
        $(if ($llmnrDisabled) { 'PASS' } else { 'WARN' }) `
        ("EnableMulticast={0}" -f $(if ($null -eq $llmnrValue) { '<not set>' } else { $llmnrValue })) `
        '0 (disabled)' `
        'Disable after validating legacy name-resolution dependencies.'
}

function Audit-Updates {
    Write-Step 'Update evidence / baseline context'

    try {
        $latest = Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 1
        $current = if ($latest) {
            '{0} - {1}' -f $latest.HotFixID, $latest.InstalledOn
        }
        else {
            'No Get-HotFix data'
        }

        Add-Result 'Maintenance' 'Most recent installed hotfix' 'INFO' $current `
            'Evidence only; use managed update/compliance platform' `
            'Get-HotFix alone does not determine patch compliance.'
    }
    catch {
        Add-Result 'Maintenance' 'Hotfix evidence' 'WARN' $_.Exception.Message 'Readable' ''
    }

    $generation = Get-WindowsServerGeneration -Info $script:ServerInfo
    $reference = switch ($generation) {
        '2025' { 'Microsoft Windows Server 2025 baseline (SCT/OSConfig) + optional CIS benchmark' }
        '2022' { 'Microsoft Windows Server 2022 baseline (SCT) + optional CIS benchmark' }
        '2019' { 'Microsoft Windows Server 2019 baseline (SCT) + optional CIS benchmark' }
        default { 'Vendor baseline matching OS version' }
    }

    Add-Result 'Baseline' 'Baseline reference' 'INFO' $reference `
        'Full baseline tooling required for compliance claim' `
        'This assistant audits selected controls; it does not certify CIS compliance.'
}

function Invoke-FullAudit {
    $script:Results.Clear()

    Set-StepPlan 9
    Audit-Compatibility
    Audit-Network
    Audit-Defender
    Audit-StoragePlatform
    Audit-SMB
    Audit-RemoteAccess
    Audit-Administrators
    Audit-LoggingNameResolution
    Audit-Updates

    Complete-Progress
}

# ---------------------------------------------------------------------------
# Remediation
# ---------------------------------------------------------------------------

function Remediate-Firewall {
    if ($script:IsRemoteSession -and -not $AllowRemoteFirewallChange) {
        Add-Result 'Network' 'Firewall remediation' 'SKIP' `
            ("Remote session detected ({0})" -f $script:RemoteKind) `
            'Run locally/out-of-band or pass -AllowRemoteFirewallChange deliberately' `
            'Default inbound changes can cut the administrator session.'
        Write-Log 'Firewall remediation skipped to preserve remote availability.' WARN
        return
    }

    $impact = if ($script:IsRemoteSession) { 'HIGH' } else { 'MEDIUM' }

    [void](Invoke-Change `
        -Name 'Enable Windows Firewall and block inbound by default' `
        -Reason 'Reduce unsolicited inbound exposure. Existing allow rules are preserved.' `
        -Impact $impact `
        -Action {
            Set-NetFirewallProfile -Profile Domain,Private,Public -Enabled True -DefaultInboundAction Block
        } `
        -PostCheck {
            $profiles = @(Get-NetFirewallProfile)
            return (($profiles | Where-Object { -not $_.Enabled -or $_.DefaultInboundAction -ne 'Block' }).Count -eq 0)
        })
}

function Remediate-Defender {
    if (-not (Test-Command 'Get-MpComputerStatus') -or -not (Test-Command 'Set-MpPreference')) {
        Write-Log 'Defender remediation unavailable on this host.' WARN
        return
    }

    $d = Get-MpComputerStatus
    $mode = if ($d.PSObject.Properties.Name -contains 'AMRunningMode') { [string]$d.AMRunningMode } else { 'Unknown' }

    if ($mode -match 'Passive|SxS') {
        Write-Log ("Defender mode is '{0}'. Core remediation skipped to avoid conflicting with managed AV/EDR." -f $mode) WARN
        return
    }

    [void](Invoke-Change `
        -Name 'Enable core Microsoft Defender protections' `
        -Reason 'Enable realtime, behavior, IOAV and script scanning protections.' `
        -Impact MEDIUM `
        -Action {
            Set-MpPreference `
                -DisableRealtimeMonitoring $false `
                -DisableBehaviorMonitoring $false `
                -DisableIOAVProtection $false `
                -DisableScriptScanning $false
        })

    [void](Invoke-Change `
        -Name 'Enable Microsoft Defender PUA protection' `
        -Reason 'Block potentially unwanted applications.' `
        -Impact MEDIUM `
        -Action {
            Set-MpPreference -PUAProtection Enabled
        })
}

function Remediate-RdpNla {
    [void](Invoke-Change `
        -Name 'Enable RDP Network Level Authentication' `
        -Reason 'Require authentication before the full RDP session is established.' `
        -Impact MEDIUM `
        -Action {
            Set-ItemProperty `
                -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' `
                -Name 'UserAuthentication' `
                -Type DWord `
                -Value 1
        } `
        -PostCheck {
            return (Test-RegistryEquals `
                -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' `
                -Name 'UserAuthentication' `
                -ExpectedValue 1)
        })
}

function Remediate-Smb {
    if (Test-Command 'Set-SmbServerConfiguration') {
        [void](Invoke-Change `
            -Name 'Enable SMB server signing capability' `
            -Reason 'Provide integrity protection for SMB traffic.' `
            -Impact MEDIUM `
            -Action {
                Set-SmbServerConfiguration -EnableSecuritySignature $true -Force
            })
    }

    if (Test-Command 'Set-SmbClientConfiguration') {
        [void](Invoke-Change `
            -Name 'Disable insecure SMB guest logons' `
            -Reason 'Reduce anonymous/guest SMB exposure.' `
            -Impact MEDIUM `
            -Action {
                Set-SmbClientConfiguration -EnableInsecureGuestLogons $false -Force
            })
    }

    if ($script:IsDomainController) {
        Write-Log 'SMBv1 feature removal on a DC is not automated by this assistant.' WARN
        return
    }

    [void](Invoke-Change `
        -Name 'Disable/remove SMBv1' `
        -Reason 'SMBv1 is obsolete and should be removed after legacy compatibility testing.' `
        -Impact HIGH `
        -Action {
            if (Test-Command 'Get-WindowsFeature') {
                $feature = Get-WindowsFeature -Name 'FS-SMB1' -ErrorAction SilentlyContinue
                if ($feature -and $feature.Installed) {
                    Uninstall-WindowsFeature -Name 'FS-SMB1' -Restart:$false | Out-Null
                }
                elseif (Test-Command 'Disable-WindowsOptionalFeature') {
                    Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart | Out-Null
                }
            }
            elseif (Test-Command 'Disable-WindowsOptionalFeature') {
                Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart | Out-Null
            }
            else {
                throw 'No supported SMBv1 feature-management cmdlet is available.'
            }
        })
}

function Remediate-Llmnr {
    [void](Invoke-Change `
        -Name 'Disable LLMNR' `
        -Reason 'Reduce multicast name-resolution spoofing/poisoning exposure.' `
        -Impact MEDIUM `
        -Action {
            $path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'
            New-Item -Path $path -Force | Out-Null
            New-ItemProperty -Path $path -Name 'EnableMulticast' -PropertyType DWord -Value 0 -Force | Out-Null
        } `
        -PostCheck {
            return (Test-RegistryEquals `
                -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' `
                -Name 'EnableMulticast' `
                -ExpectedValue 0)
        })
}

function Remediate-PowerShellLogging {
    [void](Invoke-Change `
        -Name 'Enable PowerShell Script Block Logging' `
        -Reason 'Improve visibility into PowerShell execution.' `
        -Impact MEDIUM `
        -Action {
            $path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging'
            New-Item -Path $path -Force | Out-Null
            New-ItemProperty -Path $path -Name 'EnableScriptBlockLogging' -PropertyType DWord -Value 1 -Force | Out-Null
        })

    [void](Invoke-Change `
        -Name 'Enable PowerShell Module Logging for all modules' `
        -Reason 'Improve visibility into module activity. This can significantly increase event volume.' `
        -Impact MEDIUM `
        -Action {
            $base = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging'
            $names = Join-Path $base 'ModuleNames'
            New-Item -Path $base -Force | Out-Null
            New-ItemProperty -Path $base -Name 'EnableModuleLogging' -PropertyType DWord -Value 1 -Force | Out-Null
            New-Item -Path $names -Force | Out-Null
            New-ItemProperty -Path $names -Name '*' -PropertyType String -Value '*' -Force | Out-Null
        })
}

function Invoke-Hardening {
    Write-Console ''
    Write-Console 'The assistant will propose controls one by one. A change-set is created before the first applied change.' Cyan

    Remediate-Firewall
    Remediate-Defender
    Remediate-RdpNla
    Remediate-Smb
    Remediate-Llmnr
    Remediate-PowerShellLogging

    Write-Log 'Hardening pass completed; re-running audit.' INFO
    Invoke-FullAudit
}

# ---------------------------------------------------------------------------
# Summary / report
# ---------------------------------------------------------------------------

function Write-Report {
    $counts = [ordered]@{
        PASS    = @($script:Results | Where-Object { $_.Status -eq 'PASS' }).Count
        WARN    = @($script:Results | Where-Object { $_.Status -eq 'WARN' }).Count
        FAIL    = @($script:Results | Where-Object { $_.Status -eq 'FAIL' }).Count
        ERROR   = @($script:Results | Where-Object { $_.Status -eq 'ERROR' }).Count
        INFO    = @($script:Results | Where-Object { $_.Status -eq 'INFO' }).Count
        SKIP    = @($script:Results | Where-Object { $_.Status -eq 'SKIP' }).Count
        MANAGED = @($script:Results | Where-Object { $_.Status -eq 'MANAGED' }).Count
    }

    $state = [pscustomobject]@{
        SchemaVersion   = 1
        Assistant       = 'PyME Windows Server Security Assistant'
        Version         = $script:Version
        GeneratedAt     = Get-Date
        StartedAt       = $script:Started
        Mode            = $Mode
        Session         = $script:RemoteKind
        Server          = $script:ServerInfo
        Roles           = $script:RoleInfo
        BaselineClaim   = 'Selected baseline-oriented controls; not a CIS certification'
        Counts          = $counts
        Results         = @($script:Results)
        Changes         = @($script:Changes)
        Warnings        = @($script:Warnings)
        BackupPath      = $(if ($script:SnapshotCreated) { $script:BackupPath } else { $null })
    }

    $state | ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath $script:ReportFile -Encoding UTF8
}

function Show-Summary {
    Complete-Progress
    Write-Console ''
    Write-Console 'FINAL SUMMARY' Cyan
    Write-Console ('-' * 78) Cyan

    $pass = @($script:Results | Where-Object { $_.Status -eq 'PASS' }).Count
    $warn = @($script:Results | Where-Object { $_.Status -eq 'WARN' }).Count
    $fail = @($script:Results | Where-Object { $_.Status -in @('FAIL','ERROR') }).Count
    $applied = @($script:Changes | Where-Object { $_.Status -eq 'APPLIED' }).Count
    $skipped = @($script:Changes | Where-Object { $_.Status -eq 'SKIPPED' }).Count
    $failedChanges = @($script:Changes | Where-Object { $_.Status -eq 'FAILED' }).Count

    Write-Console ("PASS={0}" -f $pass) Green
    Write-Console ("WARN={0}" -f $warn) Yellow
    Write-Console ("FAIL/ERROR={0}" -f $fail) Red
    Write-Console ("Changes: applied={0}; skipped={1}; failed={2}" -f $applied, $skipped, $failedChanges) Magenta

    $priority = @($script:Results | Where-Object { $_.Status -in @('FAIL','ERROR','WARN') })
    if ($priority.Count -gt 0) {
        Write-Console ''
        Write-Console 'Priority findings:' Cyan
        $priority | Select-Object Category, Control, Status, Current | Format-Table -AutoSize
    }

    Write-Console ("Log    : {0}" -f $script:LogFile)
    Write-Console ("Report : {0}" -f $script:ReportFile)
    if ($script:SnapshotCreated) {
        Write-Console ("Backup : {0}" -f $script:BackupPath)
    }
}

function Show-Menu {
    Write-Console ''
    Write-Console 'Select an action:' Cyan
    Write-Console '  [1] Audit only'
    Write-Console '  [2] Audit + interactive hardening'
    Write-Console '  [3] Create configuration backup/change-set'
    Write-Console '  [4] Show current findings'
    Write-Console '  [0] Exit'
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

try {
    Initialize-Runtime
    Initialize-Discovery
    Write-Banner

    Write-Log 'Starting security assistant.'
    Write-Log ("Export directory: {0}" -f $ExportPath)

    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Administrator privileges are required.'
    }

    switch ($Mode) {
        'Audit' {
            Invoke-FullAudit
        }

        'Harden' {
            Invoke-FullAudit
            Invoke-Hardening
        }

        'Backup' {
            Set-StepPlan 1
            Run-BackupOnly
        }

        default {
            Invoke-FullAudit

            while ($true) {
                Show-Menu
                $choice = Read-Host 'Choice'

                switch ($choice) {
                    '1' {
                        Invoke-FullAudit
                    }
                    '2' {
                        Invoke-Hardening
                    }
                    '3' {
                        Set-StepPlan 1
                        Run-BackupOnly
                        Complete-Progress
                    }
                    '4' {
                        $script:Results | Format-Table Category, Control, Status, Current -AutoSize
                    }
                    '0' {
                        break
                    }
                    default {
                        Write-Console 'Invalid choice.' Yellow
                    }
                }

                if ($choice -eq '0') { break }
            }
        }
    }

    Write-Report
    Show-Summary
}
catch {
    if ($script:LogFile) {
        Write-Log ("FATAL: {0}" -f $_.Exception.Message) ERROR
    }
    else {
        Write-Error $_.Exception.Message
    }
    throw
}
finally {
    Complete-Progress
    if ($script:LogFile) {
        Write-Log 'Security assistant finished.'
    }
}
