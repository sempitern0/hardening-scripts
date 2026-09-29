#requires -RunAsAdministrator
<#
.SYNOPSIS
    Windows Server AD Control Plane - v1.0.0-professional

.DESCRIPTION
    Professional, audit-first assistant for Windows Server and Active Directory.

    Primary targets:
      - Windows Server 2019
      - Windows Server 2022
      - Windows Server 2025
      - Windows PowerShell 5.1+

    Core principles:
      - Detect before modify.
      - Preserve remote administration paths.
      - Create a change-set before remediation.
      - Require explicit confirmation for every material change.
      - Require the literal word APPLY for destructive/high-impact actions.
      - Prefer Microsoft-native modules and tools.
      - Be role-aware: Domain Controller != member server.
      - Keep host hardening separate from directory administration.
      - Re-audit after hardening.
      - Never claim blanket CIS compliance.
      - Provide a professional console UI with clear operational context.

    Modes:
      Interactive  Full control-plane menu
      Audit        Read-only host + AD audit
      Validate     Domain Controller functional validation
      Harden       Audit + interactive host hardening
      Backup       Create configuration change-set
      ADAdmin      Active Directory operations console
      Provision    Guided NEW forest provisioning

.EXAMPLE
    .\windows-server-ad-v1.0.0-professional.ps1

.EXAMPLE
    .\windows-server-ad-v1.0.0-professional.ps1 -Mode Audit

.EXAMPLE
    .\windows-server-ad-v1.0.0-professional.ps1 -Mode ADAdmin

.EXAMPLE
    .\windows-server-ad-v1.0.0-professional.ps1 -Mode Validate

.NOTES
    Validate in a lab before production deployment.
#>

[CmdletBinding()]
param(
    [ValidateSet('Interactive','Audit','Validate','Harden','Backup','ADAdmin','Provision')]
    [string]$Mode = 'Interactive',

    [string]$ExportPath = "$env:ProgramData\WindowsADControlPlane",

    [switch]$NoColor,

    # Firewall default-policy changes during RDP/WinRM are skipped unless this
    # switch is supplied. HIGH-impact confirmation is still required.
    [switch]$AllowRemoteFirewallChange
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# ===========================================================================
# Runtime state
# ===========================================================================

$script:ProductName = 'Windows Server AD Control Plane'
$script:Version = '1.0.0-professional'
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
$script:DomainInfo = $null
$script:ForestInfo = $null

$script:UiWidth = 96

function Test-IsInteractiveConsole {
    try {
        return (-not [Console]::IsOutputRedirected)
    }
    catch {
        return $true
    }
}

$script:UseColor = (-not $NoColor) -and (Test-IsInteractiveConsole) -and (-not $env:NO_COLOR)

# ===========================================================================
# Console UI
# ===========================================================================

function Write-Console {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Text,
        [ValidateSet('Default','Cyan','Green','Yellow','Red','Magenta','Gray','White','DarkCyan')]
        [string]$Color = 'Default',
        [switch]$NoNewline
    )

    if (-not $script:UseColor -or $Color -eq 'Default') {
        if ($NoNewline) { Write-Host $Text -NoNewline }
        else { Write-Host $Text }
        return
    }

    if ($NoNewline) {
        Write-Host $Text -ForegroundColor $Color -NoNewline
    }
    else {
        Write-Host $Text -ForegroundColor $Color
    }
}

function Clear-ControlPlane {
    if (Test-IsInteractiveConsole) {
        try { Clear-Host } catch {}
    }
}

function Write-Rule {
    Write-Console ('─' * $script:UiWidth) Gray
}

function Write-Section {
    param([Parameter(Mandatory=$true)][string]$Title)

    Write-Console ''
    Write-Rule
    Write-Console ('  {0}' -f $Title.ToUpperInvariant()) White
    Write-Rule
}

function Get-ServiceBadge {
    param([Parameter(Mandatory=$true)][string]$Name)

    try {
        $svc = Get-Service -Name $Name -ErrorAction Stop
        if ($svc.Status -eq 'Running') { return 'ONLINE' }
        return ([string]$svc.Status).ToUpperInvariant()
    }
    catch {
        return 'N/A'
    }
}

function Write-Badge {
    param(
        [Parameter(Mandatory=$true)][string]$Text,
        [ValidateSet('Good','Warn','Bad','Info')]
        [string]$Kind = 'Info',
        [switch]$NoNewline
    )

    $color = switch ($Kind) {
        'Good' { 'Green' }
        'Warn' { 'Yellow' }
        'Bad'  { 'Red' }
        default { 'Cyan' }
    }

    Write-Console ('[{0}]' -f $Text) $color -NoNewline:$NoNewline
}

function Write-ContextPanel {
    $hostName = if ($script:ServerInfo) { $script:ServerInfo.ComputerName } else { $env:COMPUTERNAME }
    $osText = if ($script:ServerInfo) {
        '{0} / build {1}' -f (Get-WindowsServerGeneration -Info $script:ServerInfo), $script:ServerInfo.Build
    } else {
        'discovering'
    }

    $domain = if ($script:ServerInfo -and $script:ServerInfo.PartOfDomain) {
        $script:ServerInfo.Domain
    } else {
        'WORKGROUP / unjoined'
    }

    $role = if ($script:IsDomainController) { 'Domain Controller' } else { 'Member / standalone server' }

    Write-Console ('  {0,-14} {1,-31} {2,-14} {3}' -f 'Server', $hostName, 'Role', $role)
    Write-Console ('  {0,-14} {1,-31} {2,-14} {3}' -f 'Domain', $domain, 'OS', $osText)
    Write-Console ('  {0,-14} {1,-31} {2,-14} {3}' -f 'Session', $script:RemoteKind, 'PowerShell', $PSVersionTable.PSVersion)

    if ($script:IsDomainController) {
        Write-Console '  Services       ' -NoNewline
        foreach ($svcName in @('NTDS','DNS','Netlogon','Kdc','ADWS')) {
            $state = Get-ServiceBadge -Name $svcName
            $kind = if ($state -eq 'ONLINE') { 'Good' } elseif ($state -eq 'N/A') { 'Info' } else { 'Bad' }
            Write-Console ('{0}=' -f $svcName) Gray -NoNewline
            Write-Badge -Text $state -Kind $kind -NoNewline
            Write-Console ' ' -NoNewline
        }
        Write-Console ''
    }
}

function Write-MenuHeader {
    param(
        [Parameter(Mandatory=$true)][string]$Title,
        [string]$Subtitle = ''
    )

    Clear-ControlPlane
    Write-Console '  WINDOWS SERVER AD CONTROL PLANE' Cyan
    Write-Console ('  v{0}  |  Native Microsoft tooling  |  Audit-first operations' -f $script:Version) Gray
    Write-Rule
    Write-ContextPanel
    Write-Rule
    Write-Console ('  {0}' -f $Title.ToUpperInvariant()) White
    if ($Subtitle) {
        Write-Console ('  {0}' -f $Subtitle) Gray
    }
    Write-Console ''
}

function Write-MenuItem {
    param(
        [Parameter(Mandatory=$true)][string]$Key,
        [Parameter(Mandatory=$true)][string]$Title,
        [Parameter(Mandatory=$true)][string]$Description,
        [ValidateSet('Normal','Good','Warn','Danger')]
        [string]$Kind = 'Normal'
    )

    $color = switch ($Kind) {
        'Good' { 'Green' }
        'Warn' { 'Yellow' }
        'Danger' { 'Red' }
        default { 'Cyan' }
    }

    Write-Console ('  [{0,2}]  ' -f $Key) Gray -NoNewline
    Write-Console ('{0,-31}' -f $Title) $color -NoNewline
    Write-Console $Description Gray
}

function Read-MenuChoice {
    param(
        [string]$Prompt = 'Select operation',
        [string]$Default = ''
    )

    if ($Default) {
        $value = (Read-Host ('{0} [{1}]' -f $Prompt, $Default)).Trim()
        if ([string]::IsNullOrWhiteSpace($value)) {
            return $Default
        }
        return $value
    }

    return (Read-Host $Prompt).Trim()
}

function Pause-ControlPlane {
    if (Test-IsInteractiveConsole) {
        Write-Console ''
        Write-Rule
        [void](Read-Host 'Press ENTER to continue')
    }
}

function Write-Banner {
    Clear-ControlPlane

    Write-Console @'
       ██╗    ██╗██╗███╗   ██╗    █████╗ ██████╗
       ██║    ██║██║████╗  ██║   ██╔══██╗██╔══██╗
       ██║ █╗ ██║██║██╔██╗ ██║   ███████║██║  ██║
       ██║███╗██║██║██║╚██╗██║   ██╔══██║██║  ██║
       ╚███╔███╔╝██║██║ ╚████║   ██║  ██║██████╔╝
        ╚══╝╚══╝ ╚═╝╚═╝  ╚═══╝   ╚═╝  ╚═╝╚═════╝
'@ Cyan

    Write-Console '                     WINDOWS SERVER AD CONTROL PLANE' White
    Write-Console '              Provisioning · security · operations · recovery' Gray
    Write-Rule
    Write-Console ('  Version       {0}' -f $script:Version) Cyan
    Write-Console ('  Mode          {0}' -f $Mode)
    Write-Console ('  Session       {0}' -f $script:RemoteKind)
    Write-Console ('  PowerShell    {0}' -f $PSVersionTable.PSVersion)
    Write-Rule
    Write-Console ''
}

# ===========================================================================
# Runtime / logging / reporting
# ===========================================================================

function Initialize-Runtime {
    if (-not (Test-Path -LiteralPath $ExportPath)) {
        New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $script:RunPath = Join-Path $ExportPath "runs\$timestamp-$PID"
    $script:BackupPath = Join-Path $script:RunPath 'backup'

    New-Item -ItemType Directory -Path $script:BackupPath -Force | Out-Null

    $script:LogFile = Join-Path $ExportPath "control-plane-$timestamp-$PID.log"
    $script:ReportFile = Join-Path $ExportPath "control-plane-report-$timestamp-$PID.json"

    New-Item -ItemType File -Path $script:LogFile -Force | Out-Null
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

function Add-Warning {
    param([Parameter(Mandatory=$true)][string]$Message)

    [void]$script:Warnings.Add($Message)
    Write-Log $Message WARN
}

function Add-Change {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [ValidateSet('APPLIED','SKIPPED','FAILED')]
        [Parameter(Mandatory=$true)][string]$Status,
        [Parameter(Mandatory=$true)][string]$Reason,
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

    [void]$script:Results.Add([pscustomobject]@{
        Category    = $Category
        Control     = $Control
        Status      = $Status
        Current     = $Current
        Expected    = $Expected
        Remediation = $Remediation
        Reference   = $Reference
    })

    $prefix = switch ($Status) {
        'PASS'    { '[ OK ]' }
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
        'SKIP'    { 'Gray' }
        'MANAGED' { 'Cyan' }
        default   { 'Gray' }
    }

    Write-Console ('  {0,-6}  {1,-35} {2}' -f $prefix, $Control, $Current) $color
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
        Write-Progress -Activity $script:ProductName -Status $Title -PercentComplete $percent
    }

    Write-Console ''
    Write-Console ('  [{0:d2}/{1:d2}] {2}' -f $script:Step, $script:TotalSteps, $Title) Cyan
}

function Complete-Progress {
    try { Write-Progress -Activity $script:ProductName -Completed } catch {}
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

    if ($Mode -eq 'Audit' -or $Mode -eq 'Backup' -or $Mode -eq 'Validate') {
        return $false
    }

    Write-Console ''
    Write-Rule

    $color = if ($Impact -eq 'HIGH') { 'Red' } elseif ($Impact -eq 'MEDIUM') { 'Yellow' } else { 'Cyan' }
    Write-Console ('  {0} IMPACT OPERATION' -f $Impact) $color
    Write-Console ('  Action : {0}' -f $Action)
    Write-Console ('  Reason : {0}' -f $Reason)
    Write-Rule

    if ($Impact -eq 'HIGH') {
        $answer = Read-Host 'Type APPLY to authorize'
        return ($answer -ceq 'APPLY')
    }

    do {
        $answer = (Read-Host 'Apply this change? [Y/N]').Trim().ToUpperInvariant()
    } while ($answer -notin @('Y','N'))

    return ($answer -eq 'Y')
}

function Invoke-Change {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Reason,
        [Parameter(Mandatory=$true)][scriptblock]$Action,
        [ValidateSet('LOW','MEDIUM','HIGH')]
        [string]$Impact = 'LOW',
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

# ===========================================================================
# Discovery
# ===========================================================================

function Get-ServerInfo {
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem

    return [pscustomobject]@{
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

    return [pscustomobject]@{
        IsRemote = $remote
        Kind     = $kind
    }
}

function Get-WindowsServerGeneration {
    param([Parameter(Mandatory=$true)]$Info)

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
                        'AD-Domain-Services',
                        'DNS',
                        'DHCP',
                        'FS-FileServer',
                        'Hyper-V',
                        'Web-Server',
                        'RDS-RD-Server',
                        'Failover-Clustering',
                        'Windows-Server-Backup'
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

function Import-ADModules {
    if (-not $script:IsDomainController -and -not (Test-Command 'Get-ADDomain')) {
        return $false
    }

    try {
        if (-not (Get-Module -Name ActiveDirectory)) {
            Import-Module ActiveDirectory -ErrorAction Stop
        }
        return $true
    }
    catch {
        Add-Warning ("ActiveDirectory module unavailable: {0}" -f $_.Exception.Message)
        return $false
    }
}

function Initialize-Discovery {
    $ctx = Get-SessionContext
    $script:IsRemoteSession = $ctx.IsRemote
    $script:RemoteKind = $ctx.Kind
    $script:ServerInfo = Get-ServerInfo
    $script:IsDomainController = Test-IsDomainController
    $script:RoleInfo = @(Get-InstalledServerRoles)

    if ($script:IsDomainController -and (Import-ADModules)) {
        try { $script:DomainInfo = Get-ADDomain -ErrorAction Stop } catch {}
        try { $script:ForestInfo = Get-ADForest -ErrorAction Stop } catch {}
    }
}

function Assert-DomainController {
    if (-not $script:IsDomainController) {
        throw 'This operation requires a Domain Controller.'
    }

    if (-not (Import-ADModules)) {
        throw 'The ActiveDirectory PowerShell module is required.'
    }
}

# ===========================================================================
# Change-set / recovery
# ===========================================================================

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

    $script:ServerInfo | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath (Join-Path $script:BackupPath 'server-info.json') -Encoding UTF8

    $script:RoleInfo | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath (Join-Path $script:BackupPath 'server-roles.json') -Encoding UTF8

    try {
        Get-NetIPConfiguration |
            Select-Object InterfaceAlias, InterfaceIndex, IPv4Address, IPv4DefaultGateway, DnsServer |
            ConvertTo-Json -Depth 8 |
            Set-Content -LiteralPath (Join-Path $script:BackupPath 'network.json') -Encoding UTF8
    }
    catch {
        Add-Warning ("Network snapshot failed: {0}" -f $_.Exception.Message)
    }

    if (Test-Command 'netsh.exe') {
        & netsh.exe advfirewall export (Join-Path $script:BackupPath 'firewall.wfw') *> $null
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

    if ($script:IsDomainController) {
        if (Import-ADModules) {
            try {
                Get-ADDomain | ConvertTo-Json -Depth 6 |
                    Set-Content -LiteralPath (Join-Path $script:BackupPath 'ad-domain.json') -Encoding UTF8
                Get-ADForest | ConvertTo-Json -Depth 6 |
                    Set-Content -LiteralPath (Join-Path $script:BackupPath 'ad-forest.json') -Encoding UTF8
            }
            catch {
                Add-Warning ("AD metadata snapshot failed: {0}" -f $_.Exception.Message)
            }
        }

        if (Test-Command 'Get-GPO') {
            try {
                Get-GPO -All |
                    Select-Object DisplayName, Id, GpoStatus, CreationTime, ModificationTime |
                    ConvertTo-Json -Depth 5 |
                    Set-Content -LiteralPath (Join-Path $script:BackupPath 'gpo-inventory.json') -Encoding UTF8
            }
            catch {
                Add-Warning ("GPO inventory snapshot failed: {0}" -f $_.Exception.Message)
            }
        }

        if (Test-Command 'Get-DnsServerZone') {
            try {
                Get-DnsServerZone |
                    Select-Object ZoneName, ZoneType, IsDsIntegrated, IsReverseLookupZone |
                    ConvertTo-Json -Depth 5 |
                    Set-Content -LiteralPath (Join-Path $script:BackupPath 'dns-zones.json') -Encoding UTF8
            }
            catch {
                Add-Warning ("DNS inventory snapshot failed: {0}" -f $_.Exception.Message)
            }
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

    @'
CHANGE-SET RESTORE NOTES
========================

This directory is a safety snapshot, not a one-click full restore.

Firewall:
  netsh advfirewall import .\firewall.wfw

Registry:
  Review .reg files before importing.

SMB / Defender:
  JSON files capture previous state. Restore deliberately with native cmdlets.

Active Directory:
  AD/GPO/DNS JSON files are inventory evidence only.
  Use supported AD backup/recovery procedures for actual directory recovery.

For a Domain Controller, a verified Windows Server system-state backup remains
the recovery-grade backup mechanism.

Always validate connectivity, DNS, authentication, replication and SYSVOL
after rollback or recovery.
'@ | Set-Content -LiteralPath (Join-Path $script:BackupPath 'RESTORE.txt') -Encoding UTF8

    $script:SnapshotCreated = $true
    Write-Log 'Change-set backup completed.' OK
}

function Invoke-ConfigurationBackup {
    Write-Step 'Configuration change-set'
    New-ChangeSet
    Add-Result 'Recovery' 'Configuration change-set' 'PASS' $script:BackupPath 'Snapshot available before changes'
}

function Invoke-SystemStateBackup {
    Assert-DomainController

    if (-not (Test-Command 'wbadmin.exe')) {
        Add-Result 'Recovery' 'System-state backup' 'ERROR' 'wbadmin.exe unavailable' 'Windows Server Backup available'
        return
    }

    $target = Read-Host 'Backup target (example F: or \\server\share)'
    if ([string]::IsNullOrWhiteSpace($target)) {
        Write-Console 'Backup cancelled: target is required.' Yellow
        return
    }

    if (-not (Confirm-Action `
        -Action ("Create Domain Controller system-state backup at {0}" -f $target) `
        -Reason 'Create recovery-grade backup of AD DS/SYSVOL/system state.' `
        -Impact LOW)) {
        return
    }

    Write-Console ''
    Write-Console 'Starting wbadmin system-state backup...' Cyan

    & wbadmin.exe start systemstatebackup "-backupTarget:$target" -quiet

    if ($LASTEXITCODE -eq 0) {
        Add-Result 'Recovery' 'System-state backup' 'PASS' $target 'Completed'
    }
    else {
        Add-Result 'Recovery' 'System-state backup' 'FAIL' ("wbadmin exit={0}" -f $LASTEXITCODE) 'Completed'
    }
}

# ===========================================================================
# Registry helpers
# ===========================================================================

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

# ===========================================================================
# Host audit
# ===========================================================================

function Audit-Compatibility {
    Write-Step 'Compatibility / runtime'

    $generation = Get-WindowsServerGeneration -Info $script:ServerInfo
    $supported = $generation -in @('2019','2022','2025')

    Add-Result 'System' 'Windows Server generation' `
        $(if ($supported) { 'PASS' } else { 'WARN' }) `
        ("{0}; build {1}" -f $generation, $script:ServerInfo.Build) `
        'Windows Server 2019/2022/2025'

    Add-Result 'System' 'Windows PowerShell' `
        $(if ($script:PowerShellMajor -ge 5) { 'PASS' } else { 'WARN' }) `
        $PSVersionTable.PSVersion.ToString() `
        '5.1+'

    Add-Result 'System' 'Session context' 'INFO' $script:RemoteKind 'Known before network changes'

    Add-Result 'System' 'Domain Controller role' 'INFO' `
        $(if ($script:IsDomainController) { 'YES' } else { 'NO' }) `
        'Role-aware configuration'

    foreach ($role in $script:RoleInfo) {
        Add-Result 'System' ("Role {0}" -f $role.Name) 'INFO' 'Installed' 'Role-aware hardening'
    }

    if ($generation -eq '2025') {
        $osConfig = if (Get-Module -ListAvailable -Name Microsoft.OSConfig -ErrorAction SilentlyContinue) {
            'Microsoft.OSConfig module available'
        } else {
            'OSConfig module not detected'
        }
        Add-Result 'Baseline' 'Windows Server 2025 OSConfig' 'INFO' $osConfig 'Evaluate role-aware Microsoft baseline'
    }
}

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
                'Documented expected configuration'
        }
    }
    catch {
        Add-Result 'Network' 'Network configuration' 'ERROR' $_.Exception.Message 'Readable'
    }

    if (-not (Test-Command 'Get-NetFirewallProfile')) {
        Add-Result 'Network' 'Firewall cmdlets' 'ERROR' 'Unavailable' 'Available'
        return
    }

    try {
        foreach ($p in Get-NetFirewallProfile) {
            $status = if ($p.Enabled -and $p.DefaultInboundAction -eq 'Block') { 'PASS' } else { 'FAIL' }

            Add-Result 'Network' ("Firewall {0}" -f $p.Name) $status `
                ("Enabled={0}; Inbound={1}; Outbound={2}" -f $p.Enabled, $p.DefaultInboundAction, $p.DefaultOutboundAction) `
                'Enabled; default inbound Block'
        }
    }
    catch {
        Add-Result 'Network' 'Firewall profiles' 'ERROR' $_.Exception.Message 'Readable'
    }
}

function Audit-Defender {
    Write-Step 'Microsoft Defender'

    if (-not (Test-Command 'Get-MpComputerStatus')) {
        Add-Result 'Endpoint' 'Microsoft Defender' 'WARN' 'Cmdlets unavailable' 'Managed AV/EDR known'
        return
    }

    try {
        $d = Get-MpComputerStatus

        $runningMode = 'Unknown'
        if ($d.PSObject.Properties.Name -contains 'AMRunningMode') {
            $runningMode = [string]$d.AMRunningMode
        }

        Add-Result 'Endpoint' 'Defender running mode' 'INFO' $runningMode 'Understand active/passive/managed state'

        $managedOrPassive = $runningMode -match 'Passive|EDR Block|SxS'

        foreach ($check in @(
            @{ Name='Defender service'; Property='AMServiceEnabled' },
            @{ Name='Realtime protection'; Property='RealTimeProtectionEnabled' },
            @{ Name='Behavior monitoring'; Property='BehaviorMonitorEnabled' },
            @{ Name='IOAV protection'; Property='IOAVProtectionEnabled' }
        )) {
            $value = $d.($check.Property)
            $status = if ($value) { 'PASS' } elseif ($managedOrPassive) { 'MANAGED' } else { 'FAIL' }

            Add-Result 'Endpoint' $check.Name $status `
                ("{0}={1}" -f $check.Property, $value) `
                'Enabled or intentionally managed'
        }

        if ($d.PSObject.Properties.Name -contains 'IsTamperProtected') {
            Add-Result 'Endpoint' 'Tamper protection' `
                $(if ($d.IsTamperProtected) { 'PASS' } else { 'WARN' }) `
                ("IsTamperProtected={0}" -f $d.IsTamperProtected) `
                'Enabled where supported/managed'
        }

        if (Test-Command 'Get-MpPreference') {
            $p = Get-MpPreference
            Add-Result 'Endpoint' 'PUA protection' `
                $(if ([int]$p.PUAProtection -eq 1) { 'PASS' } else { 'WARN' }) `
                ("PUAProtection={0}" -f $p.PUAProtection) `
                'Enabled'
        }
    }
    catch {
        Add-Result 'Endpoint' 'Defender state' 'ERROR' $_.Exception.Message 'Readable'
    }
}

function Audit-StoragePlatform {
    Write-Step 'BitLocker / TPM / Secure Boot'

    if (Test-Command 'Get-BitLockerVolume') {
        try {
            foreach ($v in Get-BitLockerVolume) {
                $encrypted = $v.VolumeStatus -eq 'FullyEncrypted'
                $protected = $v.ProtectionStatus -eq 'On'
                $status = if ($encrypted -and $protected) { 'PASS' } else { 'WARN' }

                Add-Result 'Storage' ("BitLocker {0}" -f $v.MountPoint) $status `
                    ("Status={0}; Protection={1}; Method={2}" -f $v.VolumeStatus, $v.ProtectionStatus, $v.EncryptionMethod) `
                    'Encrypted and protected where policy requires'
            }
        }
        catch {
            Add-Result 'Storage' 'BitLocker' 'ERROR' $_.Exception.Message 'Readable'
        }
    }

    if (Test-Command 'Get-Tpm') {
        try {
            $tpm = Get-Tpm
            Add-Result 'Platform' 'TPM' `
                $(if ($tpm.TpmPresent -and $tpm.TpmReady) { 'PASS' } else { 'WARN' }) `
                ("Present={0}; Ready={1}" -f $tpm.TpmPresent, $tpm.TpmReady) `
                'Present and ready where supported'
        }
        catch {}
    }

    if (Test-Command 'Confirm-SecureBootUEFI') {
        try {
            $secure = Confirm-SecureBootUEFI -ErrorAction Stop
            Add-Result 'Platform' 'Secure Boot' `
                $(if ($secure) { 'PASS' } else { 'WARN' }) `
                ([string]$secure) `
                'Enabled where supported'
        }
        catch {
            Add-Result 'Platform' 'Secure Boot' 'INFO' 'Unavailable/legacy/unsupported' 'Hardware dependent'
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
                ("State={0}" -f $smb1.State) `
                'Disabled'
        }
        catch {
            Add-Result 'Network' 'SMBv1 feature' 'INFO' 'Feature query unavailable' 'Disabled'
        }
    }

    if (Test-Command 'Get-SmbServerConfiguration') {
        try {
            $smb = Get-SmbServerConfiguration

            Add-Result 'Network' 'SMB server signing enabled' `
                $(if ($smb.EnableSecuritySignature) { 'PASS' } else { 'WARN' }) `
                ("Enable={0}; Require={1}" -f $smb.EnableSecuritySignature, $smb.RequireSecuritySignature) `
                'Enabled; requirement role/baseline dependent'

            Add-Result 'Network' 'SMB server signing required' `
                $(if ($smb.RequireSecuritySignature) { 'PASS' } elseif ($smb.EnableSecuritySignature) { 'WARN' } else { 'FAIL' }) `
                ("RequireSecuritySignature={0}" -f $smb.RequireSecuritySignature) `
                'Evaluate against role/version baseline'
        }
        catch {
            Add-Result 'Network' 'SMB server configuration' 'ERROR' $_.Exception.Message 'Readable'
        }
    }

    if (Test-Command 'Get-SmbClientConfiguration') {
        try {
            $c = Get-SmbClientConfiguration
            Add-Result 'Network' 'SMB insecure guest logons' `
                $(if (-not $c.EnableInsecureGuestLogons) { 'PASS' } else { 'FAIL' }) `
                ("EnableInsecureGuestLogons={0}" -f $c.EnableInsecureGuestLogons) `
                'False'
        }
        catch {}
    }
}

function Audit-RemoteAccess {
    Write-Step 'Remote access'

    try {
        $ts = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
        $rdpEnabled = ($ts.fDenyTSConnections -eq 0)

        Add-Result 'Remote Access' 'RDP enabled' 'INFO' `
            ("Enabled={0}" -f $rdpEnabled) `
            'Documented and network-restricted'

        $nlaPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
        $nla = Get-RegistryValueSafe -Path $nlaPath -Name 'UserAuthentication'

        Add-Result 'Remote Access' 'RDP NLA' `
            $(if ($nla -eq 1) { 'PASS' } else { 'FAIL' }) `
            ("UserAuthentication={0}" -f $nla) `
            '1'
    }
    catch {
        Add-Result 'Remote Access' 'RDP configuration' 'ERROR' $_.Exception.Message 'Readable'
    }

    foreach ($svcName in @('WinRM','TermService')) {
        try {
            $svc = Get-Service -Name $svcName -ErrorAction Stop
            Add-Result 'Remote Access' ("Service {0}" -f $svcName) 'INFO' ([string]$svc.Status) 'Documented'
        }
        catch {}
    }
}

function Audit-Administrators {
    Write-Step 'Administrative access / LAPS'

    if ($script:IsDomainController) {
        if (Import-ADModules) {
            foreach ($groupName in @('Domain Admins','Enterprise Admins','Schema Admins','Administrators')) {
                try {
                    $members = @(Get-ADGroupMember -Identity $groupName -Recursive:$false -ErrorAction Stop)
                    Add-Result 'Identity' $groupName 'INFO' `
                        ("{0} direct member(s)" -f $members.Count) `
                        'Minimum necessary membership'
                }
                catch {
                    Add-Result 'Identity' $groupName 'WARN' $_.Exception.Message 'Review privileged membership'
                }
            }
        }
    }
    elseif (Test-Command 'Get-LocalGroupMember') {
        try {
            $members = @(Get-LocalGroupMember -SID 'S-1-5-32-544')
            Add-Result 'Identity' 'Local Administrators' 'INFO' `
                ("{0} member(s)" -f $members.Count) `
                'Minimum necessary membership'
        }
        catch {}
    }

    if (Test-Command 'Get-LapsADPasswordPolicy') {
        try {
            $null = Get-LapsADPasswordPolicy -ErrorAction Stop
            Add-Result 'Identity' 'Windows LAPS' 'INFO' 'AD LAPS policy cmdlets available' 'Managed and verified'
        }
        catch {
            Add-Result 'Identity' 'Windows LAPS' 'WARN' 'Policy query failed' 'Managed and verified'
        }
    }
    else {
        Add-Result 'Identity' 'Windows LAPS' 'INFO' 'LAPS cmdlets not detected' 'Evaluate where applicable'
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

    $moduleNamesPresent = Test-Path -LiteralPath "$psBase\ModuleLogging\ModuleNames"

    Add-Result 'Logging' 'PowerShell Script Block Logging' `
        $(if ($scriptBlock) { 'PASS' } else { 'WARN' }) `
        $(if ($scriptBlock) { 'Enabled' } else { 'Not detected' }) `
        'Enabled where logging/privacy policy permits'

    Add-Result 'Logging' 'PowerShell Module Logging' `
        $(if ($moduleEnabled -and $moduleNamesPresent) { 'PASS' } else { 'WARN' }) `
        ("Enabled={0}; ModuleNames={1}" -f $moduleEnabled, $moduleNamesPresent) `
        'Enabled + module list configured'

    $llmnrPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'
    $llmnrValue = Get-RegistryValueSafe -Path $llmnrPath -Name 'EnableMulticast'

    Add-Result 'Network' 'LLMNR' `
        $(if ($llmnrValue -eq 0) { 'PASS' } else { 'WARN' }) `
        ("EnableMulticast={0}" -f $(if ($null -eq $llmnrValue) { '<not set>' } else { $llmnrValue })) `
        '0 (disabled)'
}

function Audit-Updates {
    Write-Step 'Updates / baseline context'

    try {
        $latest = Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 1
        $current = if ($latest) {
            '{0} - {1}' -f $latest.HotFixID, $latest.InstalledOn
        }
        else {
            'No Get-HotFix data'
        }

        Add-Result 'Maintenance' 'Most recent installed hotfix' 'INFO' $current 'Managed patch compliance'
    }
    catch {
        Add-Result 'Maintenance' 'Hotfix evidence' 'WARN' $_.Exception.Message 'Readable'
    }

    $generation = Get-WindowsServerGeneration -Info $script:ServerInfo
    $reference = switch ($generation) {
        '2025' { 'Microsoft Windows Server 2025 role-aware OSConfig baseline' }
        '2022' { 'Microsoft Windows Server 2022 Security Compliance Toolkit baseline' }
        '2019' { 'Microsoft Windows Server 2019 Security Compliance Toolkit baseline' }
        default { 'Vendor baseline matching OS version' }
    }

    Add-Result 'Baseline' 'Baseline reference' 'INFO' $reference 'External baseline tooling required for compliance claims'
}

function Invoke-HostAudit {
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

# ===========================================================================
# Domain Controller health
# ===========================================================================

function Test-RequiredDcServices {
    foreach ($serviceName in @('NTDS','DNS','Netlogon','Kdc','ADWS')) {
        try {
            $svc = Get-Service -Name $serviceName -ErrorAction Stop
            Add-Result 'AD Health' ("Service {0}" -f $serviceName) `
                $(if ($svc.Status -eq 'Running') { 'PASS' } else { 'FAIL' }) `
                ([string]$svc.Status) `
                'Running'
        }
        catch {
            Add-Result 'AD Health' ("Service {0}" -f $serviceName) 'ERROR' $_.Exception.Message 'Running'
        }
    }
}

function Test-DcDiag {
    if (-not (Test-Command 'dcdiag.exe')) {
        Add-Result 'AD Health' 'DCDiag' 'ERROR' 'dcdiag.exe unavailable' 'Available'
        return
    }

    $output = & dcdiag.exe /q 2>&1
    if ($LASTEXITCODE -eq 0 -and @($output).Count -eq 0) {
        Add-Result 'AD Health' 'DCDiag /q' 'PASS' 'No failures reported' 'No failures'
    }
    else {
        $path = Join-Path $script:RunPath 'dcdiag.txt'
        $output | Set-Content -LiteralPath $path -Encoding UTF8
        Add-Result 'AD Health' 'DCDiag /q' 'FAIL' ("Issues reported; saved to {0}" -f $path) 'No failures'
    }
}

function Test-ReplicationHealth {
    if (Import-ADModules -and (Test-Command 'Get-ADReplicationFailure')) {
        try {
            $failures = @(Get-ADReplicationFailure -Target * -Scope Forest -ErrorAction Stop)
            Add-Result 'AD Replication' 'Replication failures' `
                $(if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }) `
                ("{0} failure object(s)" -f $failures.Count) `
                '0 failures'

            if ($failures.Count -gt 0) {
                $failures |
                    Select-Object Server, Partner, FirstFailureTime, FailureCount, LastError |
                    Export-Csv -LiteralPath (Join-Path $script:RunPath 'replication-failures.csv') -NoTypeInformation -Encoding UTF8
            }
        }
        catch {
            Add-Result 'AD Replication' 'Replication PowerShell query' 'WARN' $_.Exception.Message 'Readable'
        }
    }

    if (Test-Command 'repadmin.exe') {
        $summary = & repadmin.exe /replsummary 2>&1
        $summary | Set-Content -LiteralPath (Join-Path $script:RunPath 'repadmin-replsummary.txt') -Encoding UTF8

        if ($LASTEXITCODE -eq 0) {
            Add-Result 'AD Replication' 'Repadmin summary' 'PASS' 'Command completed' 'Review saved summary'
        }
        else {
            Add-Result 'AD Replication' 'Repadmin summary' 'WARN' ("Exit={0}" -f $LASTEXITCODE) 'Review saved summary'
        }
    }
}

function Test-DcDnsHealth {
    if (-not (Test-Command 'Resolve-DnsName')) {
        Add-Result 'DNS' 'Resolve-DnsName' 'ERROR' 'Cmdlet unavailable' 'Available'
        return
    }

    try {
        $domainName = if ($script:DomainInfo) { $script:DomainInfo.DNSRoot } else { $script:ServerInfo.Domain }

        $ldap = Resolve-DnsName -Name ("_ldap._tcp.dc._msdcs.{0}" -f $domainName) -Type SRV -ErrorAction Stop
        Add-Result 'DNS' 'LDAP DC locator SRV' `
            $(if (@($ldap).Count -gt 0) { 'PASS' } else { 'FAIL' }) `
            ("{0} record(s)" -f @($ldap).Count) `
            'At least one SRV record'

        $kerberos = Resolve-DnsName -Name ("_kerberos._tcp.{0}" -f $domainName) -Type SRV -ErrorAction Stop
        Add-Result 'DNS' 'Kerberos SRV' `
            $(if (@($kerberos).Count -gt 0) { 'PASS' } else { 'FAIL' }) `
            ("{0} record(s)" -f @($kerberos).Count) `
            'At least one SRV record'
    }
    catch {
        Add-Result 'DNS' 'AD DNS records' 'FAIL' $_.Exception.Message 'Resolvable SRV records'
    }

    if (Test-Command 'Get-DnsServerZone') {
        try {
            $zones = @(Get-DnsServerZone -ErrorAction Stop)
            Add-Result 'DNS' 'DNS zones' 'PASS' ("{0} zone(s)" -f $zones.Count) 'Readable'
        }
        catch {
            Add-Result 'DNS' 'DNS zones' 'WARN' $_.Exception.Message 'Readable'
        }
    }
}

function Test-SysvolNetlogonShares {
    if (-not (Test-Command 'Get-SmbShare')) {
        Add-Result 'AD Health' 'SYSVOL / NETLOGON shares' 'SKIP' 'Get-SmbShare unavailable' 'Readable'
        return
    }

    $shares = @(Get-SmbShare -Name 'SYSVOL','NETLOGON' -ErrorAction SilentlyContinue)
    foreach ($name in @('SYSVOL','NETLOGON')) {
        Add-Result 'AD Health' ("Share {0}" -f $name) `
            $(if ($shares.Name -contains $name) { 'PASS' } else { 'FAIL' }) `
            $(if ($shares.Name -contains $name) { 'Present' } else { 'Missing' }) `
            'Present'
    }
}

function Show-FsmoRoles {
    Assert-DomainController

    $forest = Get-ADForest
    $domain = Get-ADDomain

    [pscustomobject]@{
        SchemaMaster         = $forest.SchemaMaster
        DomainNamingMaster   = $forest.DomainNamingMaster
        PDCEmulator          = $domain.PDCEmulator
        RIDMaster            = $domain.RIDMaster
        InfrastructureMaster = $domain.InfrastructureMaster
    } | Format-List
}

function Invoke-DcValidation {
    Assert-DomainController

    $script:Results.Clear()
    Set-StepPlan 5

    Write-Step 'Required DC services'
    Test-RequiredDcServices

    Write-Step 'DCDiag'
    Test-DcDiag

    Write-Step 'Replication'
    Test-ReplicationHealth

    Write-Step 'DNS / DC locator'
    Test-DcDnsHealth

    Write-Step 'SYSVOL / NETLOGON'
    Test-SysvolNetlogonShares

    Complete-Progress
}

# ===========================================================================
# Host remediation
# ===========================================================================

function Remediate-Firewall {
    if ($script:IsRemoteSession -and -not $AllowRemoteFirewallChange) {
        Add-Result 'Network' 'Firewall remediation' 'SKIP' `
            ("Remote session detected ({0})" -f $script:RemoteKind) `
            'Run locally/out-of-band or explicitly allow remote firewall change'

        Write-Log 'Firewall remediation skipped to preserve remote availability.' WARN
        return
    }

    $impact = if ($script:IsRemoteSession) { 'HIGH' } else { 'MEDIUM' }

    [void](Invoke-Change `
        -Name 'Enable Windows Firewall and block inbound by default' `
        -Reason 'Reduce unsolicited inbound exposure while preserving existing allow rules.' `
        -Impact $impact `
        -Action {
            Set-NetFirewallProfile -Profile Domain,Private,Public -Enabled True -DefaultInboundAction Block
        } `
        -PostCheck {
            $profiles = @(Get-NetFirewallProfile)
            return (($profiles | Where-Object {
                -not $_.Enabled -or $_.DefaultInboundAction -ne 'Block'
            }).Count -eq 0)
        })
}

function Remediate-Defender {
    if (-not (Test-Command 'Get-MpComputerStatus') -or -not (Test-Command 'Set-MpPreference')) {
        Write-Log 'Defender remediation unavailable.' WARN
        return
    }

    $d = Get-MpComputerStatus
    $runningMode = if ($d.PSObject.Properties.Name -contains 'AMRunningMode') {
        [string]$d.AMRunningMode
    } else {
        'Unknown'
    }

    if ($runningMode -match 'Passive|SxS') {
        Write-Log ("Defender mode is '{0}'. Core remediation skipped to avoid EDR/AV conflict." -f $runningMode) WARN
        return
    }

    [void](Invoke-Change `
        -Name 'Enable core Microsoft Defender protections' `
        -Reason 'Enable realtime, behavior, IOAV and script scanning.' `
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
        -Reason 'Require authentication before a full RDP session is established.' `
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
        Write-Log 'Automated SMBv1 feature removal is intentionally skipped on a DC.' WARN
        return
    }

    [void](Invoke-Change `
        -Name 'Disable/remove SMBv1' `
        -Reason 'SMBv1 is obsolete; remove after validating legacy compatibility.' `
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
        })
}

function Remediate-Llmnr {
    [void](Invoke-Change `
        -Name 'Disable LLMNR' `
        -Reason 'Reduce multicast name-resolution spoofing exposure.' `
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
        -Name 'Enable PowerShell Module Logging' `
        -Reason 'Improve visibility into PowerShell module activity.' `
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
    Write-Console 'Host hardening changes are proposed individually; the first applied change creates a change-set.' Cyan

    Remediate-Firewall
    Remediate-Defender
    Remediate-RdpNla
    Remediate-Smb
    Remediate-Llmnr
    Remediate-PowerShellLogging

    Write-Log 'Hardening pass complete; re-running host audit.' INFO
    $script:Results.Clear()
    Invoke-HostAudit
}

# ===========================================================================
# Active Directory user management
# ===========================================================================

function Show-AdUsers {
    Assert-DomainController

    Get-ADUser -Filter * -Properties Enabled, DisplayName, LastLogonDate, PasswordLastSet |
        Sort-Object SamAccountName |
        Select-Object SamAccountName, DisplayName, Enabled, LastLogonDate, PasswordLastSet |
        Format-Table -AutoSize
}

function Show-AdUserDetail {
    Assert-DomainController

    $identity = Read-Host 'User identity / sAMAccountName'
    Get-ADUser -Identity $identity -Properties * |
        Select-Object SamAccountName, UserPrincipalName, DisplayName, GivenName, Surname,
            Enabled, LockedOut, PasswordLastSet, PasswordNeverExpires, LastLogonDate,
            Mail, Department, Title, DistinguishedName |
        Format-List
}

function New-AdUserInteractive {
    Assert-DomainController

    $sam = (Read-Host 'sAMAccountName').Trim()
    if ([string]::IsNullOrWhiteSpace($sam)) { return }

    if (Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue) {
        Write-Console 'User already exists.' Yellow
        return
    }

    $given = Read-Host 'Given name'
    $surname = Read-Host 'Surname'
    $display = Read-Host 'Display name'
    if ([string]::IsNullOrWhiteSpace($display)) {
        $display = ("{0} {1}" -f $given, $surname).Trim()
    }

    $path = Read-Host 'Target OU distinguished name (blank = default Users container)'
    $password = Read-Host 'Initial password' -AsSecureString

    if (-not (Confirm-Action `
        -Action ("Create enabled AD user '{0}'" -f $sam) `
        -Reason 'Create a new domain identity.' `
        -Impact LOW)) {
        return
    }

    New-ChangeSet

    $params = @{
        SamAccountName        = $sam
        Name                  = $display
        DisplayName           = $display
        GivenName             = $given
        Surname               = $surname
        Enabled               = $true
        AccountPassword       = $password
        ChangePasswordAtLogon = $true
    }

    if (-not [string]::IsNullOrWhiteSpace($path)) {
        $params.Path = $path
    }

    New-ADUser @params
    Write-Log ("Created AD user: {0}" -f $sam) CHANGE
}

function Edit-AdUserInteractive {
    Assert-DomainController

    $identity = Read-Host 'User identity / sAMAccountName'
    $user = Get-ADUser -Identity $identity -Properties DisplayName, Mail, Department, Title

    Write-Console 'Leave a value blank to keep the existing value.' Gray

    $display = Read-Host ("Display name [{0}]" -f $user.DisplayName)
    $mail = Read-Host ("Email [{0}]" -f $user.Mail)
    $department = Read-Host ("Department [{0}]" -f $user.Department)
    $title = Read-Host ("Title [{0}]" -f $user.Title)

    if (-not (Confirm-Action `
        -Action ("Update AD user '{0}'" -f $identity) `
        -Reason 'Modify selected directory attributes.' `
        -Impact LOW)) {
        return
    }

    New-ChangeSet

    $params = @{ Identity = $identity }
    if ($display) { $params.DisplayName = $display }
    if ($mail) { $params.EmailAddress = $mail }
    if ($department) { $params.Department = $department }
    if ($title) { $params.Title = $title }

    if ($params.Count -gt 1) {
        Set-ADUser @params
        Write-Log ("Updated AD user: {0}" -f $identity) CHANGE
    }
}

function Reset-AdUserPassword {
    Assert-DomainController

    $identity = Read-Host 'User identity / sAMAccountName'
    $password = Read-Host 'New password' -AsSecureString

    if (-not (Confirm-Action `
        -Action ("Reset password for '{0}'" -f $identity) `
        -Reason 'Administrative password reset.' `
        -Impact MEDIUM)) {
        return
    }

    New-ChangeSet
    Set-ADAccountPassword -Identity $identity -Reset -NewPassword $password
    Set-ADUser -Identity $identity -ChangePasswordAtLogon $true
}

function Set-AdUserEnabledState {
    param([Parameter(Mandatory=$true)][bool]$Enabled)

    Assert-DomainController

    $identity = Read-Host 'User identity / sAMAccountName'
    $verb = if ($Enabled) { 'Enable' } else { 'Disable' }
    $impact = if ($Enabled) { 'LOW' } else { 'MEDIUM' }

    if (-not (Confirm-Action `
        -Action ("{0} AD user '{1}'" -f $verb, $identity) `
        -Reason 'Change authentication eligibility for this account.' `
        -Impact $impact)) {
        return
    }

    New-ChangeSet

    if ($Enabled) {
        Enable-ADAccount -Identity $identity
    }
    else {
        Disable-ADAccount -Identity $identity
    }
}

function Unlock-AdUserInteractive {
    Assert-DomainController

    $identity = Read-Host 'User identity / sAMAccountName'

    if (Confirm-Action `
        -Action ("Unlock AD user '{0}'" -f $identity) `
        -Reason 'Clear the account lockout state.' `
        -Impact LOW) {

        Unlock-ADAccount -Identity $identity
    }
}

function Remove-AdUserInteractive {
    Assert-DomainController

    $identity = Read-Host 'User identity / sAMAccountName'

    if (-not (Confirm-Action `
        -Action ("PERMANENTLY delete AD user '{0}'" -f $identity) `
        -Reason 'Delete the directory object. This is destructive.' `
        -Impact HIGH)) {
        return
    }

    New-ChangeSet
    Remove-ADUser -Identity $identity -Confirm:$false
    Write-Log ("Deleted AD user: {0}" -f $identity) CHANGE
}

# ===========================================================================
# AD groups / access
# ===========================================================================

function Show-AdGroups {
    Assert-DomainController

    Get-ADGroup -Filter * |
        Sort-Object Name |
        Select-Object Name, GroupScope, GroupCategory, DistinguishedName |
        Format-Table -AutoSize
}

function New-AdGroupInteractive {
    Assert-DomainController

    $name = Read-Host 'Group name'
    $scope = Read-Host 'Scope [Global/Universal/DomainLocal]'
    if ([string]::IsNullOrWhiteSpace($scope)) { $scope = 'Global' }

    $category = Read-Host 'Category [Security/Distribution]'
    if ([string]::IsNullOrWhiteSpace($category)) { $category = 'Security' }

    $path = Read-Host 'Target OU distinguished name (blank = default)'

    if (-not (Confirm-Action `
        -Action ("Create AD group '{0}'" -f $name) `
        -Reason 'Create a new group object.' `
        -Impact LOW)) {
        return
    }

    New-ChangeSet

    $params = @{
        Name          = $name
        GroupScope    = $scope
        GroupCategory = $category
    }

    if ($path) { $params.Path = $path }

    New-ADGroup @params
}

function Show-AdGroupMembers {
    Assert-DomainController

    $group = Read-Host 'Group name'
    Get-ADGroupMember -Identity $group |
        Select-Object Name, SamAccountName, ObjectClass, DistinguishedName |
        Format-Table -AutoSize
}

function Add-AdGroupMemberInteractive {
    Assert-DomainController

    $group = Read-Host 'Group'
    $member = Read-Host 'User/group/computer identity'

    if (Confirm-Action `
        -Action ("Add '{0}' to '{1}'" -f $member, $group) `
        -Reason 'Grant group membership.' `
        -Impact MEDIUM) {

        New-ChangeSet
        Add-ADGroupMember -Identity $group -Members $member
    }
}

function Remove-AdGroupMemberInteractive {
    Assert-DomainController

    $group = Read-Host 'Group'
    $member = Read-Host 'User/group/computer identity'

    if (Confirm-Action `
        -Action ("Remove '{0}' from '{1}'" -f $member, $group) `
        -Reason 'Revoke group membership.' `
        -Impact MEDIUM) {

        New-ChangeSet
        Remove-ADGroupMember -Identity $group -Members $member -Confirm:$false
    }
}

function Remove-AdGroupInteractive {
    Assert-DomainController

    $group = Read-Host 'Group name'

    if ($group -in @('Domain Admins','Enterprise Admins','Schema Admins','Domain Users','Domain Controllers','Administrators')) {
        Write-Console 'Protected/core AD group: deletion refused.' Red
        return
    }

    if (Confirm-Action `
        -Action ("PERMANENTLY delete AD group '{0}'" -f $group) `
        -Reason 'Delete the directory group object.' `
        -Impact HIGH) {

        New-ChangeSet
        Remove-ADGroup -Identity $group -Confirm:$false
    }
}

function Show-PrivilegedGroups {
    Assert-DomainController

    foreach ($group in @('Domain Admins','Enterprise Admins','Schema Admins','Administrators','Account Operators','Backup Operators','Server Operators')) {
        Write-Console ''
        Write-Console ("{0}:" -f $group) Cyan
        try {
            Get-ADGroupMember -Identity $group -Recursive:$false |
                Select-Object Name, SamAccountName, ObjectClass |
                Format-Table -AutoSize
        }
        catch {
            Write-Console $_.Exception.Message Yellow
        }
    }
}

# ===========================================================================
# AD computers / OUs
# ===========================================================================

function Show-AdComputers {
    Assert-DomainController

    Get-ADComputer -Filter * -Properties Enabled, LastLogonDate, OperatingSystem, IPv4Address |
        Sort-Object Name |
        Select-Object Name, Enabled, OperatingSystem, IPv4Address, LastLogonDate |
        Format-Table -AutoSize
}

function Show-AdComputerDetail {
    Assert-DomainController

    $identity = Read-Host 'Computer name / identity'
    Get-ADComputer -Identity $identity -Properties * |
        Select-Object Name, Enabled, DNSHostName, IPv4Address, OperatingSystem,
            OperatingSystemVersion, LastLogonDate, PasswordLastSet, DistinguishedName |
        Format-List
}

function Set-AdComputerEnabledState {
    param([Parameter(Mandatory=$true)][bool]$Enabled)

    Assert-DomainController

    $identity = Read-Host 'Computer name / identity'
    $verb = if ($Enabled) { 'Enable' } else { 'Disable' }

    if (-not (Confirm-Action `
        -Action ("{0} computer account '{1}'" -f $verb, $identity) `
        -Reason 'Change whether the machine account can authenticate.' `
        -Impact MEDIUM)) {
        return
    }

    New-ChangeSet

    if ($Enabled) {
        Enable-ADAccount -Identity $identity
    }
    else {
        Disable-ADAccount -Identity $identity
    }
}

function Remove-AdComputerInteractive {
    Assert-DomainController

    $identity = Read-Host 'Computer name / identity'

    if (Confirm-Action `
        -Action ("PERMANENTLY delete computer account '{0}'" -f $identity) `
        -Reason 'Remove an obsolete machine object from Active Directory.' `
        -Impact HIGH) {

        New-ChangeSet
        Remove-ADComputer -Identity $identity -Confirm:$false
    }
}

function Show-AdOrganizationalUnits {
    Assert-DomainController

    Get-ADOrganizationalUnit -Filter * -Properties ProtectedFromAccidentalDeletion |
        Sort-Object DistinguishedName |
        Select-Object Name, ProtectedFromAccidentalDeletion, DistinguishedName |
        Format-Table -AutoSize
}

function New-AdOrganizationalUnitInteractive {
    Assert-DomainController

    $name = Read-Host 'OU name'
    $path = Read-Host 'Parent DN (blank = domain root)'

    if ([string]::IsNullOrWhiteSpace($path)) {
        $path = (Get-ADDomain).DistinguishedName
    }

    if (Confirm-Action `
        -Action ("Create OU '{0}' under '{1}'" -f $name, $path) `
        -Reason 'Create an organizational container protected from accidental deletion.' `
        -Impact LOW) {

        New-ChangeSet
        New-ADOrganizationalUnit -Name $name -Path $path -ProtectedFromAccidentalDeletion $true
    }
}

function Move-AdObjectInteractive {
    Assert-DomainController

    $identity = Read-Host 'Object distinguished name or identity'
    $target = Read-Host 'Target OU distinguished name'

    if (Confirm-Action `
        -Action ("Move object to '{0}'" -f $target) `
        -Reason 'Change the directory location and therefore potentially its GPO/delegation scope.' `
        -Impact MEDIUM) {

        New-ChangeSet
        Move-ADObject -Identity $identity -TargetPath $target
    }
}

function Remove-AdOrganizationalUnitInteractive {
    Assert-DomainController

    $identity = Read-Host 'OU distinguished name'

    if (-not (Confirm-Action `
        -Action ("PERMANENTLY delete OU '{0}'" -f $identity) `
        -Reason 'Delete an organizational container. It must be empty and unprotected.' `
        -Impact HIGH)) {
        return
    }

    New-ChangeSet
    Set-ADOrganizationalUnit -Identity $identity -ProtectedFromAccidentalDeletion $false
    Remove-ADOrganizationalUnit -Identity $identity -Confirm:$false
}

# ===========================================================================
# Group Policy operations
# ===========================================================================

function Import-GroupPolicyModule {
    if (-not (Test-Command 'Get-GPO')) {
        try {
            Import-Module GroupPolicy -ErrorAction Stop
        }
        catch {
            throw ("GroupPolicy module unavailable: {0}" -f $_.Exception.Message)
        }
    }
}

function Show-Gpos {
    Assert-DomainController
    Import-GroupPolicyModule

    Get-GPO -All |
        Sort-Object DisplayName |
        Select-Object DisplayName, Id, GpoStatus, CreationTime, ModificationTime |
        Format-Table -AutoSize
}

function Show-GpoDetail {
    Assert-DomainController
    Import-GroupPolicyModule

    $name = Read-Host 'GPO display name'
    Get-GPO -Name $name | Format-List *
}

function New-GpoInteractive {
    Assert-DomainController
    Import-GroupPolicyModule

    $name = Read-Host 'New GPO display name'
    $comment = Read-Host 'Comment / purpose'

    if (Confirm-Action `
        -Action ("Create GPO '{0}'" -f $name) `
        -Reason 'Create an empty Group Policy Object.' `
        -Impact LOW) {

        New-ChangeSet
        New-GPO -Name $name -Comment $comment | Format-List DisplayName, Id
    }
}

function Backup-GpoInteractive {
    Assert-DomainController
    Import-GroupPolicyModule

    $name = Read-Host 'GPO display name'
    $path = Join-Path $script:RunPath 'gpo-backups'
    New-Item -ItemType Directory -Path $path -Force | Out-Null

    Backup-GPO -Name $name -Path $path |
        Format-List DisplayName, Id, BackupId, BackupDirectory

    Write-Console ("Backup directory: {0}" -f $path) Green
}

function Set-GpoRegistryValueInteractive {
    Assert-DomainController
    Import-GroupPolicyModule

    $name = Read-Host 'GPO display name'
    $key = Read-Host 'Registry key (example HKLM\Software\Policies\...)'
    $valueName = Read-Host 'Value name'
    $type = Read-Host 'Type [String/ExpandString/Binary/DWord/MultiString/QWord]'
    if ([string]::IsNullOrWhiteSpace($type)) { $type = 'DWord' }
    $rawValue = Read-Host 'Value'

    $value = $rawValue
    if ($type -in @('DWord','QWord')) {
        $number = 0L
        if (-not [Int64]::TryParse($rawValue, [ref]$number)) {
            Write-Console 'Numeric value required for DWord/QWord.' Red
            return
        }
        $value = $number
    }

    if (Confirm-Action `
        -Action ("Set registry policy '{0}' in GPO '{1}'" -f $valueName, $name) `
        -Reason 'Edit a registry-based Group Policy setting.' `
        -Impact MEDIUM) {

        New-ChangeSet

        Set-GPRegistryValue `
            -Name $name `
            -Key $key `
            -ValueName $valueName `
            -Type $type `
            -Value $value
    }
}

function Link-GpoInteractive {
    Assert-DomainController
    Import-GroupPolicyModule

    $name = Read-Host 'GPO display name'
    $target = Read-Host 'Target DN (domain or OU)'

    if (Confirm-Action `
        -Action ("Link GPO '{0}' to '{1}'" -f $name, $target) `
        -Reason 'Change Group Policy scope.' `
        -Impact MEDIUM) {

        New-ChangeSet

        try {
            New-GPLink -Name $name -Target $target -LinkEnabled Yes -ErrorAction Stop | Out-Null
        }
        catch {
            Set-GPLink -Name $name -Target $target -LinkEnabled Yes | Out-Null
        }
    }
}

function Unlink-GpoInteractive {
    Assert-DomainController
    Import-GroupPolicyModule

    $name = Read-Host 'GPO display name'
    $target = Read-Host 'Target DN'

    if (Confirm-Action `
        -Action ("Remove link for GPO '{0}' from '{1}'" -f $name, $target) `
        -Reason 'Remove Group Policy scope from a container.' `
        -Impact MEDIUM) {

        New-ChangeSet
        Remove-GPLink -Name $name -Target $target -Confirm:$false
    }
}

function Set-GpoPermissionInteractive {
    Assert-DomainController
    Import-GroupPolicyModule

    $name = Read-Host 'GPO display name'
    $principal = Read-Host 'Target user/group/computer'
    $targetType = Read-Host 'Target type [User/Group/Computer]'
    if ([string]::IsNullOrWhiteSpace($targetType)) { $targetType = 'Group' }

    $permission = Read-Host 'Permission [GpoRead/GpoApply/GpoEdit/GpoEditDeleteModifySecurity/None]'

    if (Confirm-Action `
        -Action ("Set GPO permission for '{0}' on '{1}'" -f $principal, $name) `
        -Reason 'Modify GPO delegation/security filtering permissions.' `
        -Impact MEDIUM) {

        New-ChangeSet

        Set-GPPermission `
            -Name $name `
            -TargetName $principal `
            -TargetType $targetType `
            -PermissionLevel $permission `
            -Replace
    }
}

function Remove-GpoInteractive {
    Assert-DomainController
    Import-GroupPolicyModule

    $name = Read-Host 'GPO display name'

    Write-Console 'A backup will be created before deletion.' Yellow
    $gpoBackupPath = Join-Path $script:RunPath 'gpo-backups'
    New-Item -ItemType Directory -Path $gpoBackupPath -Force | Out-Null
    Backup-GPO -Name $name -Path $gpoBackupPath -ErrorAction SilentlyContinue | Out-Null

    if (Confirm-Action `
        -Action ("PERMANENTLY delete GPO '{0}'" -f $name) `
        -Reason 'Delete the Group Policy Object after creating a best-effort backup.' `
        -Impact HIGH) {

        New-ChangeSet
        Remove-GPO -Name $name -Confirm:$false
    }
}

function Export-GpoReportInteractive {
    Assert-DomainController
    Import-GroupPolicyModule

    $name = Read-Host 'GPO display name'
    $safe = ($name -replace '[^A-Za-z0-9._-]', '_')
    $path = Join-Path $script:RunPath ("gpo-{0}.html" -f $safe)

    Get-GPOReport -Name $name -ReportType Html -Path $path
    Write-Console ("HTML report: {0}" -f $path) Green
}

# ===========================================================================
# DNS operations
# ===========================================================================

function Assert-DnsServerModule {
    if (-not (Test-Command 'Get-DnsServerZone')) {
        try {
            Import-Module DnsServer -ErrorAction Stop
        }
        catch {
            throw ("DnsServer module unavailable: {0}" -f $_.Exception.Message)
        }
    }
}

function Show-DnsZones {
    Assert-DomainController
    Assert-DnsServerModule

    Get-DnsServerZone |
        Sort-Object ZoneName |
        Select-Object ZoneName, ZoneType, IsDsIntegrated, IsReverseLookupZone, DynamicUpdate |
        Format-Table -AutoSize
}

function Show-DnsRecords {
    Assert-DomainController
    Assert-DnsServerModule

    $zone = Read-Host 'DNS zone'
    $name = Read-Host 'Record/node name (blank = all records)'

    if ($name) {
        Get-DnsServerResourceRecord -ZoneName $zone -Name $name |
            Format-Table HostName, RecordType, TimeToLive, Timestamp, RecordData -AutoSize
    }
    else {
        Get-DnsServerResourceRecord -ZoneName $zone |
            Format-Table HostName, RecordType, TimeToLive, Timestamp, RecordData -AutoSize
    }
}

function Add-DnsARecordInteractive {
    Assert-DomainController
    Assert-DnsServerModule

    $zone = Read-Host 'DNS zone'
    $name = Read-Host 'Host name'
    $ip = Read-Host 'IPv4 address'

    if (Confirm-Action `
        -Action ("Create A record {0}.{1} -> {2}" -f $name, $zone, $ip) `
        -Reason 'Add a DNS host record.' `
        -Impact LOW) {

        New-ChangeSet
        Add-DnsServerResourceRecordA -ZoneName $zone -Name $name -IPv4Address $ip
    }
}

function Remove-DnsRecordInteractive {
    Assert-DomainController
    Assert-DnsServerModule

    $zone = Read-Host 'DNS zone'
    $name = Read-Host 'Record/node name'
    $type = Read-Host 'Record type [A/CNAME/TXT/PTR/AAAA/etc.]'

    $records = @(Get-DnsServerResourceRecord -ZoneName $zone -Name $name -RRType $type -ErrorAction Stop)

    if ($records.Count -eq 0) {
        Write-Console 'No matching record found.' Yellow
        return
    }

    $records | Format-Table HostName, RecordType, TimeToLive, RecordData -AutoSize

    if ($records.Count -gt 1) {
        Write-Console 'Multiple records matched. Refusing ambiguous deletion.' Yellow
        return
    }

    if (Confirm-Action `
        -Action ("PERMANENTLY delete DNS record {0} ({1}) in {2}" -f $name, $type, $zone) `
        -Reason 'Remove a DNS resource record.' `
        -Impact HIGH) {

        New-ChangeSet
        Remove-DnsServerResourceRecord -ZoneName $zone -InputObject $records[0] -Force
    }
}

# ===========================================================================
# Forest provisioning
# ===========================================================================

function Get-PrimaryIpv4Configuration {
    try {
        return Get-NetIPConfiguration |
            Where-Object {
                $_.IPv4Address -and
                $_.IPv4DefaultGateway -and
                $_.NetAdapter.Status -eq 'Up'
            } |
            Select-Object -First 1
    }
    catch {
        return $null
    }
}

function Test-StaticIpv4 {
    $config = Get-PrimaryIpv4Configuration
    if ($null -eq $config) { return $false }

    try {
        $iface = Get-NetIPInterface -InterfaceIndex $config.InterfaceIndex -AddressFamily IPv4 -ErrorAction Stop
        return ($iface.Dhcp -eq 'Disabled')
    }
    catch {
        return $false
    }
}

function Invoke-NewForestProvisioning {
    if ($script:IsDomainController) {
        Write-Console 'This server is already a Domain Controller. Provisioning is blocked.' Red
        return
    }

    if ($script:ServerInfo.PartOfDomain) {
        Write-Console 'This server is already joined to a domain. New-forest provisioning is blocked.' Red
        return
    }

    Write-MenuHeader 'NEW ACTIVE DIRECTORY FOREST' 'Guided first-DC provisioning with prechecks and explicit high-impact authorization'

    $primary = Get-PrimaryIpv4Configuration
    if ($primary) {
        Write-Console ("  Interface      {0}" -f $primary.InterfaceAlias)
        Write-Console ("  IPv4           {0}" -f (@($primary.IPv4Address.IPAddress) -join ', '))
        Write-Console ("  Gateway        {0}" -f (@($primary.IPv4DefaultGateway.NextHop) -join ', '))
        Write-Console ("  DNS            {0}" -f (@($primary.DnsServer.ServerAddresses) -join ', '))
    }

    $static = Test-StaticIpv4
    Write-Console ("  Static IPv4    {0}" -f $static) $(if ($static) { 'Green' } else { 'Yellow' })

    if (-not $static) {
        Write-Console ''
        Write-Console 'A production Domain Controller should use a persistent/static address.' Yellow
        Write-Console 'This assistant deliberately does not rewrite live network configuration.' Yellow
        Write-Console 'Configure networking first, then rerun provisioning.' Yellow
        return
    }

    $domainName = (Read-Host 'New forest DNS domain (example corp.example.com)').Trim()
    if ([string]::IsNullOrWhiteSpace($domainName) -or $domainName -notmatch '^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$') {
        Write-Console 'Invalid DNS domain name.' Red
        return
    }

    $defaultNetbios = ($domainName.Split('.')[0]).ToUpperInvariant()
    if ($defaultNetbios.Length -gt 15) { $defaultNetbios = $defaultNetbios.Substring(0,15) }

    $netbios = Read-Host ("NetBIOS domain [{0}]" -f $defaultNetbios)
    if ([string]::IsNullOrWhiteSpace($netbios)) { $netbios = $defaultNetbios }

    $dsrm = Read-Host 'Directory Services Restore Mode password' -AsSecureString

    Write-Console ''
    Write-Console 'Provisioning plan:' Cyan
    Write-Console ("  Forest/domain : {0}" -f $domainName)
    Write-Console ("  NetBIOS       : {0}" -f $netbios)
    Write-Console ("  DC hostname   : {0}" -f $env:COMPUTERNAME)
    Write-Console '  DNS           : Install integrated DNS server'
    Write-Console '  Reboot        : Deferred; operator decides after completion'

    if (-not (Confirm-Action `
        -Action ("Create NEW Active Directory forest '{0}'" -f $domainName) `
        -Reason 'Promote this server as the first Domain Controller of a new forest.' `
        -Impact HIGH)) {
        return
    }

    New-ChangeSet

    if (-not (Test-Command 'Install-WindowsFeature')) {
        throw 'Install-WindowsFeature is unavailable.'
    }

    $feature = Get-WindowsFeature -Name AD-Domain-Services
    if (-not $feature.Installed) {
        Write-Console 'Installing AD DS role and management tools...' Cyan
        Install-WindowsFeature AD-Domain-Services -IncludeManagementTools | Out-Host
    }

    Import-Module ADDSDeployment -ErrorAction Stop

    Write-Console 'Running AD DS prerequisite checks...' Cyan

    Test-ADDSForestInstallation `
        -DomainName $domainName `
        -DomainNetbiosName $netbios `
        -InstallDns `
        -SafeModeAdministratorPassword $dsrm `
        -ErrorAction Stop | Out-Host

    Write-Console 'Prerequisite checks completed.' Green
    Write-Console ''
    Write-Console 'The server will reboot automatically when AD DS promotion completes.' Yellow
    Write-Console 'The control-plane process will therefore terminate during promotion.' Yellow

    if (-not (Confirm-Action `
        -Action ("Start final forest promotion for '{0}' and allow automatic reboot" -f $domainName) `
        -Reason 'Complete AD DS forest creation using the supported reboot behavior.' `
        -Impact HIGH)) {
        return
    }

    Install-ADDSForest `
        -DomainName $domainName `
        -DomainNetbiosName $netbios `
        -InstallDns `
        -SafeModeAdministratorPassword $dsrm `
        -Force `
        -ErrorAction Stop
}

# ===========================================================================
# Interactive menus
# ===========================================================================

function Show-UserMenu {
    while ($true) {
        Write-MenuHeader 'USER DIRECTORY' 'Identity lifecycle, credentials and account state'
        Write-MenuItem '1' 'List users' 'Inventory users, state and recent logon metadata'
        Write-MenuItem '2' 'Inspect user' 'Show detailed attributes for one identity'
        Write-MenuItem '3' 'Create user' 'Create enabled domain identity' Good
        Write-MenuItem '4' 'Edit user' 'Update display/email/department/title'
        Write-MenuItem '5' 'Reset password' 'Administrative reset + change at next logon' Warn
        Write-MenuItem '6' 'Enable account' 'Restore authentication eligibility' Good
        Write-MenuItem '7' 'Disable account' 'Block authentication without deleting identity' Warn
        Write-MenuItem '8' 'Unlock account' 'Clear account lockout'
        Write-MenuItem '9' 'Delete user' 'Permanently remove directory object' Danger
        Write-MenuItem '0' 'Back' 'Return to AD operations console' Danger
        Write-Rule

        switch (Read-MenuChoice -Default '1') {
            '1' { Show-AdUsers; Pause-ControlPlane }
            '2' { Show-AdUserDetail; Pause-ControlPlane }
            '3' { New-AdUserInteractive; Pause-ControlPlane }
            '4' { Edit-AdUserInteractive; Pause-ControlPlane }
            '5' { Reset-AdUserPassword; Pause-ControlPlane }
            '6' { Set-AdUserEnabledState -Enabled $true; Pause-ControlPlane }
            '7' { Set-AdUserEnabledState -Enabled $false; Pause-ControlPlane }
            '8' { Unlock-AdUserInteractive; Pause-ControlPlane }
            '9' { Remove-AdUserInteractive; Pause-ControlPlane }
            '0' { return }
            default { Write-Console 'Invalid option.' Yellow; Pause-ControlPlane }
        }
    }
}

function Show-GroupMenu {
    while ($true) {
        Write-MenuHeader 'GROUPS & ACCESS' 'Security groups, membership and privileged access review'
        Write-MenuItem '1' 'List groups' 'Inventory domain groups'
        Write-MenuItem '2' 'List members' 'Inspect direct membership of one group'
        Write-MenuItem '3' 'Create group' 'Create security/distribution group' Good
        Write-MenuItem '4' 'Add member' 'Grant group membership' Good
        Write-MenuItem '5' 'Remove member' 'Revoke group membership' Warn
        Write-MenuItem '6' 'Privileged groups' 'Review Domain/Enterprise/Schema/Admin operators'
        Write-MenuItem '7' 'Delete group' 'Delete non-core group object' Danger
        Write-MenuItem '0' 'Back' 'Return to AD operations console' Danger
        Write-Rule

        switch (Read-MenuChoice -Default '1') {
            '1' { Show-AdGroups; Pause-ControlPlane }
            '2' { Show-AdGroupMembers; Pause-ControlPlane }
            '3' { New-AdGroupInteractive; Pause-ControlPlane }
            '4' { Add-AdGroupMemberInteractive; Pause-ControlPlane }
            '5' { Remove-AdGroupMemberInteractive; Pause-ControlPlane }
            '6' { Show-PrivilegedGroups; Pause-ControlPlane }
            '7' { Remove-AdGroupInteractive; Pause-ControlPlane }
            '0' { return }
            default { Write-Console 'Invalid option.' Yellow; Pause-ControlPlane }
        }
    }
}

function Show-ComputerOuMenu {
    while ($true) {
        Write-MenuHeader 'COMPUTERS & ORGANIZATIONAL UNITS' 'Machine accounts, OU structure and directory placement'
        Write-MenuItem '1' 'List computers' 'Inventory machine accounts and last-logon metadata'
        Write-MenuItem '2' 'Inspect computer' 'Show detailed computer attributes'
        Write-MenuItem '3' 'Enable computer' 'Restore machine authentication' Good
        Write-MenuItem '4' 'Disable computer' 'Disable stale/suspect machine account' Warn
        Write-MenuItem '5' 'Delete computer' 'Remove obsolete machine object' Danger
        Write-MenuItem '6' 'List OUs' 'Inventory organizational units and protection state'
        Write-MenuItem '7' 'Create OU' 'Create protected OU' Good
        Write-MenuItem '8' 'Move AD object' 'Move user/group/computer between OUs' Warn
        Write-MenuItem '9' 'Delete OU' 'Unprotect and delete empty OU' Danger
        Write-MenuItem '0' 'Back' 'Return to AD operations console' Danger
        Write-Rule

        switch (Read-MenuChoice -Default '1') {
            '1' { Show-AdComputers; Pause-ControlPlane }
            '2' { Show-AdComputerDetail; Pause-ControlPlane }
            '3' { Set-AdComputerEnabledState -Enabled $true; Pause-ControlPlane }
            '4' { Set-AdComputerEnabledState -Enabled $false; Pause-ControlPlane }
            '5' { Remove-AdComputerInteractive; Pause-ControlPlane }
            '6' { Show-AdOrganizationalUnits; Pause-ControlPlane }
            '7' { New-AdOrganizationalUnitInteractive; Pause-ControlPlane }
            '8' { Move-AdObjectInteractive; Pause-ControlPlane }
            '9' { Remove-AdOrganizationalUnitInteractive; Pause-ControlPlane }
            '0' { return }
            default { Write-Console 'Invalid option.' Yellow; Pause-ControlPlane }
        }
    }
}

function Show-GpoMenu {
    while ($true) {
        Write-MenuHeader 'GROUP POLICY CONTROL' 'Native GroupPolicy module: lifecycle, scope, registry settings and delegation'
        Write-MenuItem '1' 'List GPOs' 'Inventory Group Policy Objects'
        Write-MenuItem '2' 'Inspect GPO' 'Show metadata for one GPO'
        Write-MenuItem '3' 'Create GPO' 'Create an empty GPO' Good
        Write-MenuItem '4' 'Edit registry policy' 'Set a registry-based policy value' Warn
        Write-MenuItem '5' 'Link GPO' 'Apply GPO to a domain/OU target' Good
        Write-MenuItem '6' 'Remove link' 'Detach GPO from target' Warn
        Write-MenuItem '7' 'GPO permission' 'Modify GPO delegation/security permissions' Warn
        Write-MenuItem '8' 'Backup GPO' 'Export one GPO to run backup directory'
        Write-MenuItem '9' 'HTML report' 'Export human-readable GPO report'
        Write-MenuItem '10' 'Delete GPO' 'Backup best-effort then permanently delete GPO' Danger
        Write-MenuItem '0' 'Back' 'Return to AD operations console' Danger
        Write-Rule

        switch (Read-MenuChoice -Default '1') {
            '1' { Show-Gpos; Pause-ControlPlane }
            '2' { Show-GpoDetail; Pause-ControlPlane }
            '3' { New-GpoInteractive; Pause-ControlPlane }
            '4' { Set-GpoRegistryValueInteractive; Pause-ControlPlane }
            '5' { Link-GpoInteractive; Pause-ControlPlane }
            '6' { Unlink-GpoInteractive; Pause-ControlPlane }
            '7' { Set-GpoPermissionInteractive; Pause-ControlPlane }
            '8' { Backup-GpoInteractive; Pause-ControlPlane }
            '9' { Export-GpoReportInteractive; Pause-ControlPlane }
            '10' { Remove-GpoInteractive; Pause-ControlPlane }
            '0' { return }
            default { Write-Console 'Invalid option.' Yellow; Pause-ControlPlane }
        }
    }
}

function Show-DnsMenu {
    while ($true) {
        Write-MenuHeader 'ACTIVE DIRECTORY DNS' 'Integrated zones and resource-record lifecycle'
        Write-MenuItem '1' 'List zones' 'Inventory DNS zones and integration state'
        Write-MenuItem '2' 'List records' 'Display records in one zone/node'
        Write-MenuItem '3' 'Create A record' 'Add IPv4 host record' Good
        Write-MenuItem '4' 'Delete record' 'Delete one unambiguous resource record' Danger
        Write-MenuItem '5' 'AD DNS health' 'Validate locator and Kerberos SRV records'
        Write-MenuItem '0' 'Back' 'Return to AD operations console' Danger
        Write-Rule

        switch (Read-MenuChoice -Default '1') {
            '1' { Show-DnsZones; Pause-ControlPlane }
            '2' { Show-DnsRecords; Pause-ControlPlane }
            '3' { Add-DnsARecordInteractive; Pause-ControlPlane }
            '4' { Remove-DnsRecordInteractive; Pause-ControlPlane }
            '5' { $script:Results.Clear(); Test-DcDnsHealth; Pause-ControlPlane }
            '0' { return }
            default { Write-Console 'Invalid option.' Yellow; Pause-ControlPlane }
        }
    }
}

function Show-DcHealthMenu {
    while ($true) {
        Write-MenuHeader 'DC HEALTH & REPLICATION' 'Service state, DCDiag, DNS, SYSVOL, replication and FSMO ownership'
        Write-MenuItem '1' 'Full validation' 'Run all Domain Controller health checks' Good
        Write-MenuItem '2' 'DCDiag' 'Run dcdiag /q and persist failures'
        Write-MenuItem '3' 'Replication' 'PowerShell replication failures + repadmin summary'
        Write-MenuItem '4' 'DNS health' 'Validate AD locator/Kerberos SRV records'
        Write-MenuItem '5' 'SYSVOL / NETLOGON' 'Verify required SMB shares'
        Write-MenuItem '6' 'FSMO roles' 'Display forest/domain FSMO holders'
        Write-MenuItem '0' 'Back' 'Return to AD operations console' Danger
        Write-Rule

        switch (Read-MenuChoice -Default '1') {
            '1' { Invoke-DcValidation; Pause-ControlPlane }
            '2' { $script:Results.Clear(); Test-DcDiag; Pause-ControlPlane }
            '3' { $script:Results.Clear(); Test-ReplicationHealth; Pause-ControlPlane }
            '4' { $script:Results.Clear(); Test-DcDnsHealth; Pause-ControlPlane }
            '5' { $script:Results.Clear(); Test-SysvolNetlogonShares; Pause-ControlPlane }
            '6' { Show-FsmoRoles; Pause-ControlPlane }
            '0' { return }
            default { Write-Console 'Invalid option.' Yellow; Pause-ControlPlane }
        }
    }
}

function Show-RecoveryMenu {
    while ($true) {
        Write-MenuHeader 'BACKUP & RECOVERY' 'Configuration evidence, GPO backup and Domain Controller system-state protection'
        Write-MenuItem '1' 'Configuration change-set' 'Capture firewall, registry, SMB, Defender, AD/GPO/DNS evidence'
        Write-MenuItem '2' 'DC system-state backup' 'Use wbadmin for AD DS/SYSVOL recovery-grade backup' Good
        Write-MenuItem '3' 'GPO backup' 'Back up one Group Policy Object'
        Write-MenuItem '4' 'Open run directory' 'Print current run/backup paths'
        Write-MenuItem '0' 'Back' 'Return to previous console' Danger
        Write-Rule

        switch (Read-MenuChoice -Default '1') {
            '1' { Set-StepPlan 1; Invoke-ConfigurationBackup; Complete-Progress; Pause-ControlPlane }
            '2' { Invoke-SystemStateBackup; Pause-ControlPlane }
            '3' { Backup-GpoInteractive; Pause-ControlPlane }
            '4' {
                Write-Console ("Run path    : {0}" -f $script:RunPath)
                Write-Console ("Backup path : {0}" -f $script:BackupPath)
                Pause-ControlPlane
            }
            '0' { return }
            default { Write-Console 'Invalid option.' Yellow; Pause-ControlPlane }
        }
    }
}

function Show-SecurityMenu {
    while ($true) {
        Write-MenuHeader 'HOST SECURITY & HARDENING' 'Firewall, Defender, SMB, RDP, PowerShell logging and name-resolution controls'
        Write-MenuItem '1' 'Full host audit' 'Read-only selected security controls'
        Write-MenuItem '2' 'Interactive hardening' 'Propose supported remediations one by one' Good
        Write-MenuItem '3' 'Firewall only' 'Enable profiles and default inbound block' Warn
        Write-MenuItem '4' 'Defender only' 'Core protections + PUA where locally managed'
        Write-MenuItem '5' 'RDP NLA' 'Require Network Level Authentication'
        Write-MenuItem '6' 'SMB controls' 'Signing capability, guest logons, SMBv1 member-server handling'
        Write-MenuItem '7' 'LLMNR' 'Disable multicast name resolution' Warn
        Write-MenuItem '8' 'PowerShell logging' 'Script block + module logging'
        Write-MenuItem '0' 'Back' 'Return to previous console' Danger
        Write-Rule

        switch (Read-MenuChoice -Default '1') {
            '1' { $script:Results.Clear(); Invoke-HostAudit; Pause-ControlPlane }
            '2' { Invoke-Hardening; Pause-ControlPlane }
            '3' { Remediate-Firewall; Pause-ControlPlane }
            '4' { Remediate-Defender; Pause-ControlPlane }
            '5' { Remediate-RdpNla; Pause-ControlPlane }
            '6' { Remediate-Smb; Pause-ControlPlane }
            '7' { Remediate-Llmnr; Pause-ControlPlane }
            '8' { Remediate-PowerShellLogging; Pause-ControlPlane }
            '0' { return }
            default { Write-Console 'Invalid option.' Yellow; Pause-ControlPlane }
        }
    }
}

function Show-AdOperationsMenu {
    Assert-DomainController

    while ($true) {
        Write-MenuHeader 'ACTIVE DIRECTORY OPERATIONS' 'Daily directory administration without leaving PowerShell'
        Write-MenuItem '1' 'Users' 'Identity lifecycle, credentials and account state'
        Write-MenuItem '2' 'Groups & access' 'Memberships and privileged groups'
        Write-MenuItem '3' 'Computers & OUs' 'Machine accounts and organizational structure'
        Write-MenuItem '4' 'Group Policy' 'Create, edit, link, back up and delete GPOs'
        Write-MenuItem '5' 'AD DNS' 'Zones and resource records'
        Write-MenuItem '6' 'DC health' 'DCDiag, replication, DNS, SYSVOL and FSMO'
        Write-MenuItem '7' 'Backup & recovery' 'Change-set, GPO and system-state backup'
        Write-MenuItem '8' 'Host security' 'Role-aware server hardening'
        Write-MenuItem '0' 'Back / Exit' 'Return to main control plane' Danger
        Write-Rule

        switch (Read-MenuChoice -Prompt 'Select module' -Default '1') {
            '1' { Show-UserMenu }
            '2' { Show-GroupMenu }
            '3' { Show-ComputerOuMenu }
            '4' { Show-GpoMenu }
            '5' { Show-DnsMenu }
            '6' { Show-DcHealthMenu }
            '7' { Show-RecoveryMenu }
            '8' { Show-SecurityMenu }
            '0' { return }
            default { Write-Console 'Invalid option.' Yellow; Pause-ControlPlane }
        }
    }
}

function Show-MainMenu {
    while ($true) {
        Write-MenuHeader 'WINDOWS SERVER CONTROL PLANE' 'Audit, harden, administer Active Directory and maintain recovery readiness'

        Write-MenuItem '1' 'Host security audit' 'Read-only server security inventory'
        Write-MenuItem '2' 'Interactive hardening' 'Apply selected host security changes' Good

        if ($script:IsDomainController) {
            Write-MenuItem '3' 'AD operations' 'Users, groups, computers, OUs, GPOs, DNS and health' Good
            Write-MenuItem '4' 'Validate Domain Controller' 'DCDiag, replication, DNS and SYSVOL'
            Write-MenuItem '5' 'Backup & recovery' 'Change-set, GPO and system-state backup'
        }
        else {
            Write-MenuItem '3' 'AD operations' 'Unavailable: this server is not a Domain Controller' Warn
            Write-MenuItem '4' 'Validate Domain Controller' 'Unavailable until server is promoted' Warn
            Write-MenuItem '5' 'Backup & recovery' 'Configuration change-set'
        }

        Write-MenuItem '6' 'Provision new AD forest' 'First-DC workflow; static IPv4 required' Warn
        Write-MenuItem '7' 'Current findings' 'Display latest audit/validation results'
        Write-MenuItem '0' 'Exit' 'Close control plane' Danger
        Write-Rule

        switch (Read-MenuChoice -Prompt 'Select module' -Default '1') {
            '1' {
                $script:Results.Clear()
                Invoke-HostAudit
                if ($script:IsDomainController) {
                    Invoke-DcValidation
                }
                Pause-ControlPlane
            }
            '2' { Invoke-Hardening; Pause-ControlPlane }
            '3' {
                if ($script:IsDomainController) { Show-AdOperationsMenu }
                else { Write-Console 'AD operations require a Domain Controller.' Yellow; Pause-ControlPlane }
            }
            '4' {
                if ($script:IsDomainController) { Invoke-DcValidation; Pause-ControlPlane }
                else { Write-Console 'This server is not a Domain Controller.' Yellow; Pause-ControlPlane }
            }
            '5' {
                if ($script:IsDomainController) { Show-RecoveryMenu }
                else {
                    Set-StepPlan 1
                    Invoke-ConfigurationBackup
                    Complete-Progress
                    Pause-ControlPlane
                }
            }
            '6' { Invoke-NewForestProvisioning; Pause-ControlPlane }
            '7' {
                $script:Results |
                    Select-Object Category, Control, Status, Current |
                    Format-Table -AutoSize
                Pause-ControlPlane
            }
            '0' { return }
            default { Write-Console 'Invalid option.' Yellow; Pause-ControlPlane }
        }
    }
}

# ===========================================================================
# Report / summary
# ===========================================================================

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
        SchemaVersion = 2
        Assistant     = $script:ProductName
        Version       = $script:Version
        GeneratedAt   = Get-Date
        StartedAt     = $script:Started
        Mode          = $Mode
        Session       = $script:RemoteKind
        Server        = $script:ServerInfo
        Roles         = $script:RoleInfo
        IsDC          = $script:IsDomainController
        Domain        = $script:DomainInfo
        Forest        = $script:ForestInfo
        BaselineClaim = 'Selected baseline-oriented controls; not a CIS certification'
        Counts        = $counts
        Results       = @($script:Results)
        Changes       = @($script:Changes)
        Warnings      = @($script:Warnings)
        BackupPath    = $(if ($script:SnapshotCreated) { $script:BackupPath } else { $null })
    }

    $state |
        ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath $script:ReportFile -Encoding UTF8
}

function Show-Summary {
    Complete-Progress

    $pass = @($script:Results | Where-Object { $_.Status -eq 'PASS' }).Count
    $warn = @($script:Results | Where-Object { $_.Status -eq 'WARN' }).Count
    $fail = @($script:Results | Where-Object { $_.Status -in @('FAIL','ERROR') }).Count
    $applied = @($script:Changes | Where-Object { $_.Status -eq 'APPLIED' }).Count
    $skipped = @($script:Changes | Where-Object { $_.Status -eq 'SKIPPED' }).Count
    $failedChanges = @($script:Changes | Where-Object { $_.Status -eq 'FAILED' }).Count

    Write-Section 'Execution summary'

    Write-Console ('  PASS={0}  WARN={1}  FAIL/ERROR={2}' -f $pass, $warn, $fail)
    Write-Console ('  Changes: applied={0}; skipped={1}; failed={2}' -f $applied, $skipped, $failedChanges)
    Write-Console ''
    Write-Console ('  Log      : {0}' -f $script:LogFile)
    Write-Console ('  Report   : {0}' -f $script:ReportFile)
    Write-Console ('  Run path : {0}' -f $script:RunPath)

    if ($script:SnapshotCreated) {
        Write-Console ('  Backup   : {0}' -f $script:BackupPath)
    }

    Write-Console ''

    if ($fail -gt 0) {
        Write-Console '  STATUS: ATTENTION REQUIRED' Red
    }
    elseif ($warn -gt 0) {
        Write-Console '  STATUS: COMPLETE WITH WARNINGS' Yellow
    }
    else {
        Write-Console '  STATUS: OPERATION COMPLETE' Green
    }

    Write-Rule
}

# ===========================================================================
# Main
# ===========================================================================

try {
    Initialize-Runtime
    Initialize-Discovery
    Write-Banner

    Write-Log 'Starting Windows Server AD Control Plane.'
    Write-Log ("Export directory: {0}" -f $ExportPath)

    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Administrator privileges are required.'
    }

    switch ($Mode) {
        'Audit' {
            $script:Results.Clear()
            Invoke-HostAudit

            if ($script:IsDomainController) {
                Invoke-DcValidation
            }
        }

        'Validate' {
            Invoke-DcValidation
        }

        'Harden' {
            $script:Results.Clear()
            Invoke-HostAudit
            Invoke-Hardening
        }

        'Backup' {
            Set-StepPlan 1
            Invoke-ConfigurationBackup
            Complete-Progress
        }

        'ADAdmin' {
            Show-AdOperationsMenu
        }

        'Provision' {
            Invoke-NewForestProvisioning
        }

        default {
            $script:Results.Clear()
            Invoke-HostAudit

            if ($script:IsDomainController) {
                Invoke-DcValidation
            }

            Show-MainMenu
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
        Write-Log 'Windows Server AD Control Plane finished.'
    }
}
