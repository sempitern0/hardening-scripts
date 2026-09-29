#requires -RunAsAdministrator
<#
.SYNOPSIS
    Windows Server AD Control Plane - v1.2.0-migration-nav

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
      Migration    Domain migration assessment and tooling
      DirectorySecurity  Kerberos/LDAP/SMB protocol security center

.EXAMPLE
    .\windows-server-ad-v1.3.0-directory-security-hardening.ps1

.EXAMPLE
    .\windows-server-ad-v1.3.0-directory-security-hardening.ps1 -Mode Audit

.EXAMPLE
    .\windows-server-ad-v1.3.0-directory-security-hardening.ps1 -Mode ADAdmin

.EXAMPLE
    .\windows-server-ad-v1.3.0-directory-security-hardening.ps1 -Mode Validate

.NOTES
    Validate in a lab before production deployment.
#>

[CmdletBinding()]
param(
    [ValidateSet('Interactive','Audit','Validate','Harden','Backup','ADAdmin','Provision','Migration','DirectorySecurity')]
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
$script:Version = '1.2.0-migration-nav'
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
$script:MainMenuRequested = $false

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


function Write-MenuNavigation {
    param([string]$BackDescription = 'Return to previous console')

    Write-MenuItem '0' 'Back' $BackDescription Danger
    Write-MenuItem 'H' 'Main menu' 'Jump directly to the Windows Server Control Plane' Warn
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


function Read-BooleanChoice {
    param(
        [Parameter(Mandatory=$true)][string]$Prompt,
        [bool]$Default = $false
    )

    $suffix = if ($Default) { '[Y/n]' } else { '[y/N]' }

    while ($true) {
        $answer = (Read-Host ("{0} {1}" -f $Prompt, $suffix)).Trim().ToUpperInvariant()
        if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
        if ($answer -in @('Y','YES','S','SI','SÍ')) { return $true }
        if ($answer -in @('N','NO')) { return $false }
        Write-Console 'Please answer yes or no.' Yellow
    }
}

function Read-OptionalBooleanChoice {
    param([Parameter(Mandatory=$true)][string]$Prompt)

    while ($true) {
        $answer = (Read-Host ("{0} [K/y/n]" -f $Prompt)).Trim().ToUpperInvariant()
        if ([string]::IsNullOrWhiteSpace($answer) -or $answer -eq 'K') { return $null }
        if ($answer -in @('Y','YES','S','SI','SÍ')) { return $true }
        if ($answer -in @('N','NO')) { return $false }
        Write-Console 'Use K to keep, Y for yes, or N for no.' Yellow
    }
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
                $previousProgress = $ProgressPreference
                $ProgressPreference = 'SilentlyContinue'
                Get-GPO -All |
                    Select-Object DisplayName, Id, GpoStatus, CreationTime, ModificationTime |
                    ConvertTo-Json -Depth 5 |
                    Set-Content -LiteralPath (Join-Path $script:BackupPath 'gpo-inventory.json') -Encoding UTF8
            }
            catch {
                Add-Warning ("GPO inventory snapshot failed: {0}" -f $_.Exception.Message)
            }
            finally {
                $ProgressPreference = $previousProgress
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


function Get-KerberosCryptoInventory {
    Assert-DomainController
    if (-not (Import-ADModules)) { return @() }

    $objects = @()
    try {
        $objects += @(Get-ADComputer -Filter * -Properties msDS-SupportedEncryptionTypes,ServicePrincipalName,PasswordLastSet,DNSHostName)
    }
    catch {}

    try {
        $objects += @(Get-ADUser -LDAPFilter '(&(objectCategory=person)(objectClass=user)(servicePrincipalName=*))' `
            -Properties msDS-SupportedEncryptionTypes,ServicePrincipalName,PasswordLastSet)
    }
    catch {}

    foreach ($obj in $objects) {
        $mask = 0
        $raw = $obj.'msDS-SupportedEncryptionTypes'
        if ($null -ne $raw) {
            try { $mask = [int]$raw } catch { $mask = 0 }
        }

        $hasRc4 = (($mask -band 0x4) -ne 0)
        $hasAes = (($mask -band 0x18) -ne 0)

        $classification = if ($mask -eq 0) {
            'IMPLICIT_DEFAULT'
        }
        elseif ($hasRc4 -and $hasAes) {
            'RC4_AND_AES'
        }
        elseif ($hasRc4) {
            'RC4_ONLY'
        }
        elseif ($hasAes) {
            'AES_READY'
        }
        else {
            'OTHER'
        }

        [pscustomobject]@{
            Account                    = $obj.SamAccountName
            ObjectClass                = $obj.ObjectClass
            SupportedEncryptionTypes   = $raw
            Classification             = $classification
            PasswordLastSet            = $obj.PasswordLastSet
            SPNCount                   = @($obj.ServicePrincipalName).Count
        }
    }
}

function Get-KdcHardeningEvents {
    param([int]$Days = 30)

    if (-not $script:IsDomainController) { return @() }

    $ids = 201..209
    try {
        return @(Get-WinEvent -FilterHashtable @{
            LogName      = 'System'
            ProviderName = 'Kdcsvc'
            StartTime    = (Get-Date).AddDays(-1 * $Days)
        } -ErrorAction Stop | Where-Object { $_.Id -in $ids })
    }
    catch {
        return @()
    }
}

function Audit-DirectoryProtocolSecurity {
    Write-Step 'Directory protocol security'

    if (-not $script:IsDomainController) {
        Add-Result 'AD Security' 'Directory protocol security' 'SKIP' 'Not a Domain Controller' 'DC only'
        return
    }

    $generation = Get-WindowsServerGeneration -Info $script:ServerInfo

    # SMB signing - both directions matter for a DC.
    if (Test-Command 'Get-SmbServerConfiguration') {
        try {
            $s = Get-SmbServerConfiguration
            Add-Result 'AD Security' 'SMB server signing required' `
                $(if ($s.RequireSecuritySignature) { 'PASS' } else { 'FAIL' }) `
                ("RequireSecuritySignature={0}" -f $s.RequireSecuritySignature) `
                'True on a Domain Controller'
        }
        catch {}
    }

    if (Test-Command 'Get-SmbClientConfiguration') {
        try {
            $c = Get-SmbClientConfiguration
            Add-Result 'AD Security' 'SMB client signing required' `
                $(if ($c.RequireSecuritySignature) { 'PASS' } else { 'WARN' }) `
                ("RequireSecuritySignature={0}" -f $c.RequireSecuritySignature) `
                'True for privileged/DC outbound SMB'
        }
        catch {}
    }

    # LDAP signing and channel binding.
    $ntds = 'HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters'
    $ldapSigning = Get-RegistryValueSafe -Path $ntds -Name 'LDAPServerIntegrity'
    $ldapCbt = Get-RegistryValueSafe -Path $ntds -Name 'LdapEnforceChannelBinding'

    if ($null -eq $ldapSigning -and $generation -eq '2025') {
        Add-Result 'AD Security' 'LDAP server signing' 'INFO' `
            'No explicit LDAPServerIntegrity value; Server 2025 enforcement/default policy may apply' `
            'Require signing'
    }
    else {
        Add-Result 'AD Security' 'LDAP server signing' `
            $(if ($ldapSigning -eq 2) { 'PASS' } elseif ($null -eq $ldapSigning) { 'WARN' } else { 'FAIL' }) `
            ("LDAPServerIntegrity={0}" -f $(if ($null -eq $ldapSigning) { '<not set>' } else { $ldapSigning })) `
            '2 (Require signing)'
    }

    Add-Result 'AD Security' 'LDAP channel binding' `
        $(if ($ldapCbt -eq 2) { 'PASS' } elseif ($ldapCbt -eq 1) { 'WARN' } elseif ($null -eq $ldapCbt) { 'INFO' } else { 'FAIL' }) `
        ("LdapEnforceChannelBinding={0}" -f $(if ($null -eq $ldapCbt) { '<not set>' } else { $ldapCbt })) `
        '2 after compatibility validation'

    # LAN Manager / NTLMv1 posture.
    $lsaPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
    $lm = Get-RegistryValueSafe -Path $lsaPath -Name 'LmCompatibilityLevel'
    Add-Result 'AD Security' 'LAN Manager authentication level' `
        $(if ($lm -ge 5) { 'PASS' } elseif ($null -eq $lm) { 'INFO' } else { 'WARN' }) `
        ("LmCompatibilityLevel={0}" -f $(if ($null -eq $lm) { '<not set>' } else { $lm })) `
        '5 where legacy NTLMv1 compatibility is not required'

    # 2026 Kerberos RC4 enforcement / explicit overrides.
    $kdcPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Kdc'
    $ddset = Get-RegistryValueSafe -Path $kdcPath -Name 'DefaultDomainSupportedEncTypes'
    if ($null -eq $ddset) {
        Add-Result 'Kerberos' 'DefaultDomainSupportedEncTypes' 'INFO' `
            'Not explicitly configured; current Windows Update KDC default applies' `
            'AES-first/AES-only on current patched DCs'
    }
    else {
        $ddsetInt = [int]$ddset
        $hasRc4 = (($ddsetInt -band 0x4) -ne 0)
        $hasAes = (($ddsetInt -band 0x18) -ne 0)
        Add-Result 'Kerberos' 'DefaultDomainSupportedEncTypes' `
            $(if (-not $hasRc4 -and $hasAes) { 'PASS' } elseif ($hasRc4) { 'WARN' } else { 'INFO' }) `
            ('0x{0:X}' -f $ddsetInt) `
            'AES128/AES256 without RC4 (0x18) unless an explicit exception is required'
    }

    $phase = Get-RegistryValueSafe -Path $kdcPath -Name 'RC4DefaultDisablementPhase'
    if ($null -ne $phase) {
        Add-Result 'Kerberos' 'RC4DefaultDisablementPhase' 'WARN' `
            ("Explicit legacy transition value={0}" -f $phase) `
            'Removed/obsolete after July 2026 enforcement on current patched DCs'
    }

    $events = @(Get-KdcHardeningEvents -Days 30)
    $eventPath = Join-Path $script:RunPath 'kdc-hardening-events-30d.csv'
    if ($events.Count -gt 0) {
        $events |
            Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, Message |
            Export-Csv -LiteralPath $eventPath -NoTypeInformation -Encoding UTF8
        Add-Result 'Kerberos' 'KDC hardening events 201-209' 'WARN' `
            ("{0} event(s); {1}" -f $events.Count, $eventPath) `
            '0 unresolved compatibility events'
    }
    else {
        Add-Result 'Kerberos' 'KDC hardening events 201-209' 'PASS' `
            'No events found in last 30 days' `
            'No unresolved RC4 compatibility events'
    }

    $inventory = @(Get-KerberosCryptoInventory)
    if ($inventory.Count -gt 0) {
        $inventoryPath = Join-Path $script:RunPath 'kerberos-crypto-inventory.csv'
        $inventory | Export-Csv -LiteralPath $inventoryPath -NoTypeInformation -Encoding UTF8

        $rc4Only = @($inventory | Where-Object Classification -eq 'RC4_ONLY').Count
        $mixed = @($inventory | Where-Object Classification -eq 'RC4_AND_AES').Count
        $implicit = @($inventory | Where-Object Classification -eq 'IMPLICIT_DEFAULT').Count
        $aesReady = @($inventory | Where-Object Classification -eq 'AES_READY').Count

        Add-Result 'Kerberos' 'Explicit RC4-only principals' `
            $(if ($rc4Only -eq 0) { 'PASS' } else { 'FAIL' }) `
            ("Count={0}" -f $rc4Only) `
            '0 before AES-only enforcement'

        Add-Result 'Kerberos' 'Explicit RC4+AES principals' `
            $(if ($mixed -eq 0) { 'PASS' } else { 'WARN' }) `
            ("Count={0}" -f $mixed) `
            'Remove RC4 after validation'

        Add-Result 'Kerberos' 'Implicit/default enctype principals' 'INFO' `
            ("Count={0}" -f $implicit) `
            'Validate against current KDC enforcement and third-party clients'

        Add-Result 'Kerberos' 'Explicit AES-ready principals' 'INFO' `
            ("Count={0}; report={1}" -f $aesReady, $inventoryPath) `
            'Informational'
    }
}

function Remediate-SmbSigningStrict {
    $impact = if ($script:IsDomainController) { 'MEDIUM' } else { 'HIGH' }

    if (Test-Command 'Set-SmbServerConfiguration') {
        [void](Invoke-Change `
            -Name 'Require SMB server signing' `
            -Reason 'Reject unsigned inbound SMB and reduce relay/tampering exposure.' `
            -Impact $impact `
            -Action {
                Set-SmbServerConfiguration -EnableSecuritySignature $true -RequireSecuritySignature $true -Force
            } `
            -PostCheck {
                $s = Get-SmbServerConfiguration
                return ($s.EnableSecuritySignature -and $s.RequireSecuritySignature)
            })
    }

    if (Test-Command 'Set-SmbClientConfiguration') {
        [void](Invoke-Change `
            -Name 'Require SMB client signing' `
            -Reason 'Require integrity protection for outbound SMB from this privileged server/DC.' `
            -Impact $impact `
            -Action {
                Set-SmbClientConfiguration -RequireSecuritySignature $true -Force
            } `
            -PostCheck {
                return [bool](Get-SmbClientConfiguration).RequireSecuritySignature
            })
    }
}

function Remediate-LdapSigning {
    Assert-DomainController
    $path = 'HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters'

    [void](Invoke-Change `
        -Name 'Require LDAP server signing' `
        -Reason 'Reject unsigned LDAP binds to the Domain Controller. Validate legacy LDAP clients first.' `
        -Impact HIGH `
        -Action {
            New-Item -Path $path -Force | Out-Null
            New-ItemProperty -Path $path -Name 'LDAPServerIntegrity' -PropertyType DWord -Value 2 -Force | Out-Null
        } `
        -PostCheck {
            return ((Get-RegistryValueSafe -Path $path -Name 'LDAPServerIntegrity') -eq 2)
        })
}

function Remediate-LdapChannelBinding {
    Assert-DomainController
    $path = 'HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters'

    [void](Invoke-Change `
        -Name 'Enforce LDAP channel binding' `
        -Reason 'Require valid TLS channel binding for LDAP over TLS. This can break legacy LDAP clients.' `
        -Impact HIGH `
        -Action {
            New-Item -Path $path -Force | Out-Null
            New-ItemProperty -Path $path -Name 'LdapEnforceChannelBinding' -PropertyType DWord -Value 2 -Force | Out-Null
        } `
        -PostCheck {
            return ((Get-RegistryValueSafe -Path $path -Name 'LdapEnforceChannelBinding') -eq 2)
        })
}

function Remediate-KerberosAesDefault {
    Assert-DomainController

    $inventory = @(Get-KerberosCryptoInventory)
    $rc4Only = @($inventory | Where-Object Classification -eq 'RC4_ONLY')
    $events = @(Get-KdcHardeningEvents -Days 30)

    Write-Console ''
    Write-Console ('RC4-only principals : {0}' -f $rc4Only.Count) $(if ($rc4Only.Count -gt 0) { 'Red' } else { 'Green' })
    Write-Console ('KDC 201-209 events  : {0} in last 30 days' -f $events.Count) $(if ($events.Count -gt 0) { 'Yellow' } else { 'Green' })

    if ($rc4Only.Count -gt 0) {
        $path = Join-Path $script:RunPath 'kerberos-rc4-only-principals.csv'
        $rc4Only | Export-Csv -LiteralPath $path -NoTypeInformation -Encoding UTF8
        Write-Console ("AES-only change blocked. Remediate explicit RC4-only principals first: {0}" -f $path) Red
        return
    }

    if ($events.Count -gt 0) {
        Write-Console 'Recent KDC compatibility events exist. Review them before enforcement.' Yellow
    }

    $path = 'HKLM:\SYSTEM\CurrentControlSet\Services\Kdc'
    [void](Invoke-Change `
        -Name 'Set Kerberos KDC default to AES128 + AES256 (0x18)' `
        -Reason 'Remove RC4 from the default KDC service-ticket encryption assumption after compatibility review.' `
        -Impact HIGH `
        -Action {
            New-Item -Path $path -Force | Out-Null
            New-ItemProperty -Path $path -Name 'DefaultDomainSupportedEncTypes' -PropertyType DWord -Value 0x18 -Force | Out-Null
        } `
        -PostCheck {
            return ((Get-RegistryValueSafe -Path $path -Name 'DefaultDomainSupportedEncTypes') -eq 0x18)
        })
}

function Show-DirectorySecurityMenu {
    Assert-DomainController

    while ($true) {
        if ($script:MainMenuRequested) { return }
        Write-MenuHeader 'DIRECTORY PROTOCOL SECURITY' 'Kerberos RC4/AES posture, LDAP signing/channel binding and strict SMB integrity'
        Write-MenuItem '1' 'Full protocol audit' 'Kerberos principal inventory, KDC events, LDAP and SMB signing'
        Write-MenuItem '2' 'Require SMB signing' 'Require inbound + outbound SMB signing on this server/DC' Good
        Write-MenuItem '3' 'Require LDAP signing' 'Reject unsigned LDAP binds after client compatibility review' Warn
        Write-MenuItem '4' 'LDAP channel binding' 'Require TLS channel binding; high compatibility impact' Danger
        Write-MenuItem '5' 'Kerberos RC4 readiness' 'Show service/computer encryption inventory and KDC events'
        Write-MenuItem '6' 'Explicit AES-only KDC default' 'Set DefaultDomainSupportedEncTypes=0x18 after readiness scan' Danger
        Write-MenuNavigation
        Write-Rule

        switch (Read-MenuChoice -Default '1') {
            '1' { Audit-DirectoryProtocolSecurity; Pause-ControlPlane }
            '2' { Remediate-SmbSigningStrict; Pause-ControlPlane }
            '3' { Remediate-LdapSigning; Pause-ControlPlane }
            '4' { Remediate-LdapChannelBinding; Pause-ControlPlane }
            '5' {
                $script:Results.Clear()
                Audit-DirectoryProtocolSecurity
                Pause-ControlPlane
            }
            '6' { Remediate-KerberosAesDefault; Pause-ControlPlane }
            'H' { $script:MainMenuRequested = $true; return }
            '0' { return }
            default { Write-Console 'Invalid option.' Yellow; Pause-ControlPlane }
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
    Set-StepPlan 10

    Audit-Compatibility
    Audit-Network
    Audit-Defender
    Audit-StoragePlatform
    Audit-SMB
    Audit-RemoteAccess
    Audit-Administrators
    Audit-LoggingNameResolution
    Audit-DirectoryProtocolSecurity
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
    Remediate-SmbSigningStrict

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


function Select-EnumeratedValue {
    param(
        [Parameter(Mandatory=$true)][string]$Title,
        [Parameter(Mandatory=$true)][object[]]$Options,
        [int]$DefaultIndex = 1
    )

    Write-Console ''
    Write-Console $Title Cyan
    for ($i = 0; $i -lt $Options.Count; $i++) {
        Write-Console ('  [{0}] {1,-22} {2}' -f ($i + 1), $Options[$i].Value, $Options[$i].Description)
    }
    Write-Console '  [0] Cancel' Gray

    while ($true) {
        $choice = Read-MenuChoice -Prompt 'Select value' -Default ([string]$DefaultIndex)
        if ($choice -eq '0') { return $null }

        $number = 0
        if ([int]::TryParse($choice, [ref]$number)) {
            $index = $number - 1
            if ($index -ge 0 -and $index -lt $Options.Count) {
                return [string]$Options[$index].Value
            }
        }
        Write-Console 'Invalid selection.' Yellow
    }
}

function Select-AdUserIdentity {
    param([string]$Prompt = 'Select user')

    Assert-DomainController
    $filterText = ''

    while ($true) {
        $users = @(Get-ADUser -Filter * -Properties DisplayName,Enabled |
            Sort-Object SamAccountName)

        if ($filterText) {
            $users = @($users | Where-Object {
                $_.SamAccountName -like ("*{0}*" -f $filterText) -or
                $_.DisplayName -like ("*{0}*" -f $filterText)
            })
        }

        Write-Console ''
        Write-Console 'Domain users:' Cyan
        for ($i = 0; $i -lt $users.Count; $i++) {
            Write-Console ('  [{0,3}] {1,-28} {2,-34} Enabled={3}' -f
                ($i + 1), $users[$i].SamAccountName, $users[$i].DisplayName, $users[$i].Enabled)
        }
        if ($users.Count -eq 0) { Write-Console '  No users matched.' Yellow }

        Write-Console '  [S] Search/filter' Gray
        Write-Console '  [M] Enter identity manually' Gray
        Write-Console '  [0] Cancel' Gray

        $choice = (Read-Host $Prompt).Trim()
        if ($choice -eq '0' -or [string]::IsNullOrWhiteSpace($choice)) { return $null }

        switch ($choice.ToUpperInvariant()) {
            'S' { $filterText = (Read-Host 'User filter').Trim(); continue }
            'M' {
                $manual = (Read-Host 'User identity / sAMAccountName').Trim()
                if (-not $manual) { continue }
                try { return (Get-ADUser -Identity $manual -ErrorAction Stop).SamAccountName }
                catch { Write-Console $_.Exception.Message Red; continue }
            }
        }

        $number = 0
        if ([int]::TryParse($choice, [ref]$number)) {
            $index = $number - 1
            if ($index -ge 0 -and $index -lt $users.Count) { return $users[$index].SamAccountName }
        }
        Write-Console 'Invalid user selection.' Yellow
    }
}

function Select-AdGroupIdentity {
    param([string]$Prompt = 'Select group')

    Assert-DomainController
    $filterText = ''

    while ($true) {
        $groups = @(Get-ADGroup -Filter * | Sort-Object Name)
        if ($filterText) {
            $groups = @($groups | Where-Object {
                $_.Name -like ("*{0}*" -f $filterText) -or
                $_.SamAccountName -like ("*{0}*" -f $filterText)
            })
        }

        Write-Console ''
        Write-Console 'Domain groups:' Cyan
        for ($i = 0; $i -lt $groups.Count; $i++) {
            Write-Console ('  [{0,3}] {1,-38} {2,-12} {3}' -f
                ($i + 1), $groups[$i].Name, $groups[$i].GroupScope, $groups[$i].GroupCategory)
        }
        if ($groups.Count -eq 0) { Write-Console '  No groups matched.' Yellow }

        Write-Console '  [S] Search/filter' Gray
        Write-Console '  [M] Enter group manually' Gray
        Write-Console '  [0] Cancel' Gray

        $choice = (Read-Host $Prompt).Trim()
        if ($choice -eq '0' -or [string]::IsNullOrWhiteSpace($choice)) { return $null }

        switch ($choice.ToUpperInvariant()) {
            'S' { $filterText = (Read-Host 'Group filter').Trim(); continue }
            'M' {
                $manual = (Read-Host 'Group identity').Trim()
                if (-not $manual) { continue }
                try { return (Get-ADGroup -Identity $manual -ErrorAction Stop).SamAccountName }
                catch { Write-Console $_.Exception.Message Red; continue }
            }
        }

        $number = 0
        if ([int]::TryParse($choice, [ref]$number)) {
            $index = $number - 1
            if ($index -ge 0 -and $index -lt $groups.Count) { return $groups[$index].SamAccountName }
        }
        Write-Console 'Invalid group selection.' Yellow
    }
}

function Select-AdComputerIdentity {
    param([string]$Prompt = 'Select computer')

    Assert-DomainController
    $filterText = ''

    while ($true) {
        $computers = @(Get-ADComputer -Filter * -Properties Enabled,DNSHostName,IPv4Address,OperatingSystem,LastLogonDate |
            Sort-Object Name)

        if ($filterText) {
            $computers = @($computers | Where-Object {
                $_.Name -like ("*{0}*" -f $filterText) -or
                $_.DNSHostName -like ("*{0}*" -f $filterText) -or
                $_.IPv4Address -like ("*{0}*" -f $filterText)
            })
        }

        Write-Console ''
        Write-Console 'Domain computers:' Cyan
        Write-Console ('  {0,-6} {1,-22} {2,-34} {3,-16} {4}' -f '#','NAME','DNS','IP','OS') Gray
        for ($i = 0; $i -lt $computers.Count; $i++) {
            Write-Console ('  [{0,3}]  {1,-22} {2,-34} {3,-16} {4}' -f
                ($i + 1), $computers[$i].Name, $computers[$i].DNSHostName,
                $computers[$i].IPv4Address, $computers[$i].OperatingSystem)
        }
        if ($computers.Count -eq 0) { Write-Console '  No computers matched.' Yellow }

        Write-Console '  [S] Search/filter' Gray
        Write-Console '  [M] Enter computer manually' Gray
        Write-Console '  [0] Cancel' Gray

        $choice = (Read-Host $Prompt).Trim()
        if ($choice -eq '0' -or [string]::IsNullOrWhiteSpace($choice)) { return $null }

        switch ($choice.ToUpperInvariant()) {
            'S' { $filterText = (Read-Host 'Computer filter').Trim(); continue }
            'M' {
                $manual = (Read-Host 'Computer name / identity').Trim()
                if (-not $manual) { continue }
                try { return (Get-ADComputer -Identity $manual -ErrorAction Stop).SamAccountName }
                catch { Write-Console $_.Exception.Message Red; continue }
            }
        }

        $number = 0
        if ([int]::TryParse($choice, [ref]$number)) {
            $index = $number - 1
            if ($index -ge 0 -and $index -lt $computers.Count) { return $computers[$index].SamAccountName }
        }
        Write-Console 'Invalid computer selection.' Yellow
    }
}

function Select-AdPrincipalIdentity {
    Assert-DomainController

    Write-Console ''
    Write-Console 'Security principal type:' Cyan
    Write-Console '  [1] User'
    Write-Console '  [2] Group'
    Write-Console '  [3] Computer'
    Write-Console '  [M] Enter identity manually'
    Write-Console '  [0] Cancel'

    $choice = Read-MenuChoice -Prompt 'Select principal type' -Default '1'
    switch ($choice.ToUpperInvariant()) {
        '1' {
            $id = Select-AdUserIdentity
            if ($id) { return [pscustomobject]@{ Identity=$id; TargetType='User' } }
        }
        '2' {
            $id = Select-AdGroupIdentity
            if ($id) { return [pscustomobject]@{ Identity=$id; TargetType='Group' } }
        }
        '3' {
            $id = Select-AdComputerIdentity
            if ($id) { return [pscustomobject]@{ Identity=$id; TargetType='Computer' } }
        }
        'M' {
            $id = (Read-Host 'User/group/computer identity').Trim()
            if (-not $id) { return $null }
            $kind = Select-EnumeratedValue -Title 'PRINCIPAL TYPE' -DefaultIndex 2 -Options @(
                [pscustomobject]@{ Value='User'; Description='User account' },
                [pscustomobject]@{ Value='Group'; Description='Group object' },
                [pscustomobject]@{ Value='Computer'; Description='Computer account' }
            )
            if ($kind) { return [pscustomobject]@{ Identity=$id; TargetType=$kind } }
        }
    }
    return $null
}

function Select-AdGroupMemberIdentity {
    param([Parameter(Mandatory=$true)][string]$Group)

    $members = @(Get-ADGroupMember -Identity $Group -ErrorAction Stop | Sort-Object Name)
    Write-Console ''
    Write-Console ("Current members of '{0}':" -f $Group) Cyan
    for ($i = 0; $i -lt $members.Count; $i++) {
        Write-Console ('  [{0,3}] {1,-36} {2,-12} {3}' -f
            ($i + 1), $members[$i].Name, $members[$i].ObjectClass, $members[$i].SamAccountName)
    }
    if ($members.Count -eq 0) {
        Write-Console '  No direct members returned.' Yellow
        return $null
    }

    Write-Console '  [M] Enter member manually' Gray
    Write-Console '  [0] Cancel' Gray

    while ($true) {
        $choice = (Read-Host 'Select member').Trim()
        if ($choice -eq '0' -or [string]::IsNullOrWhiteSpace($choice)) { return $null }
        if ($choice.ToUpperInvariant() -eq 'M') {
            $manual = (Read-Host 'Existing member identity').Trim()
            if ($manual) { return $manual }
            continue
        }

        $number = 0
        if ([int]::TryParse($choice, [ref]$number)) {
            $index = $number - 1
            if ($index -ge 0 -and $index -lt $members.Count) {
                return $members[$index].DistinguishedName
            }
        }
        Write-Console 'Invalid member selection.' Yellow
    }
}

function Select-AdOuDn {
    param(
        [string]$Prompt = 'Select OU',
        [switch]$IncludeDomainRoot,
        [switch]$AllowDefault
    )

    Assert-DomainController
    $domain = Get-ADDomain
    $ous = @(Get-ADOrganizationalUnit -Filter * | Sort-Object DistinguishedName)
    $offset = 1

    Write-Console ''
    Write-Console 'Directory containers:' Cyan
    if ($AllowDefault) { Write-Console '  [D] Use default container' Green }
    if ($IncludeDomainRoot) {
        Write-Console ('  [1] DOMAIN ROOT  {0}' -f $domain.DistinguishedName) Green
        $offset = 2
    }
    for ($i = 0; $i -lt $ous.Count; $i++) {
        Write-Console ('  [{0,3}] OU  {1}' -f ($i + $offset), $ous[$i].DistinguishedName)
    }
    Write-Console '  [M] Enter DN manually' Gray
    Write-Console '  [0] Cancel' Gray

    while ($true) {
        $choice = (Read-Host $Prompt).Trim()
        if ($choice -eq '0' -or [string]::IsNullOrWhiteSpace($choice)) { return $null }
        if ($AllowDefault -and $choice.ToUpperInvariant() -eq 'D') { return '__DEFAULT__' }
        if ($choice.ToUpperInvariant() -eq 'M') {
            $manual = (Read-Host 'Container distinguished name').Trim()
            if ($manual) { return $manual }
            continue
        }

        $number = 0
        if ([int]::TryParse($choice, [ref]$number)) {
            if ($IncludeDomainRoot -and $number -eq 1) { return $domain.DistinguishedName }
            $index = $number - $offset
            if ($index -ge 0 -and $index -lt $ous.Count) { return $ous[$index].DistinguishedName }
        }
        Write-Console 'Invalid OU/container selection.' Yellow
    }
}

function Select-AdDirectoryObjectIdentity {
    Assert-DomainController

    Write-Console ''
    Write-Console 'Directory object type:' Cyan
    Write-Console '  [1] User'
    Write-Console '  [2] Group'
    Write-Console '  [3] Computer'
    Write-Console '  [4] Organizational Unit'
    Write-Console '  [M] Enter DN/identity manually'
    Write-Console '  [0] Cancel'

    $choice = Read-MenuChoice -Prompt 'Select object type' -Default '1'
    switch ($choice.ToUpperInvariant()) {
        '1' {
            $id = Select-AdUserIdentity
            if ($id) { return (Get-ADUser -Identity $id).DistinguishedName }
        }
        '2' {
            $id = Select-AdGroupIdentity
            if ($id) { return (Get-ADGroup -Identity $id).DistinguishedName }
        }
        '3' {
            $id = Select-AdComputerIdentity
            if ($id) { return (Get-ADComputer -Identity $id).DistinguishedName }
        }
        '4' { return (Select-AdOuDn -Prompt 'Select OU') }
        'M' { return (Read-Host 'Object distinguished name or identity').Trim() }
    }
    return $null
}

function Select-DnsZoneName {
    Assert-DomainController
    Assert-DnsServerModule

    $zones = @(Get-DnsServerZone | Sort-Object ZoneName)
    Write-Console ''
    Write-Console 'DNS zones:' Cyan
    for ($i = 0; $i -lt $zones.Count; $i++) {
        Write-Console ('  [{0,3}] {1,-42} {2,-10} AD-integrated={3}' -f
            ($i + 1), $zones[$i].ZoneName, $zones[$i].ZoneType, $zones[$i].IsDsIntegrated)
    }
    Write-Console '  [M] Enter zone manually' Gray
    Write-Console '  [0] Cancel' Gray

    while ($true) {
        $choice = (Read-Host 'Select DNS zone').Trim()
        if ($choice -eq '0' -or [string]::IsNullOrWhiteSpace($choice)) { return $null }
        if ($choice.ToUpperInvariant() -eq 'M') {
            $manual = (Read-Host 'DNS zone').Trim()
            if ($manual) { return $manual }
            continue
        }
        $number = 0
        if ([int]::TryParse($choice, [ref]$number)) {
            $index = $number - 1
            if ($index -ge 0 -and $index -lt $zones.Count) { return $zones[$index].ZoneName }
        }
        Write-Console 'Invalid DNS zone selection.' Yellow
    }
}


function Select-DnsRecordInteractive {
    param([Parameter(Mandatory=$true)][string]$ZoneName)

    Assert-DomainController
    Assert-DnsServerModule

    $filterText = ''

    while ($true) {
        $records = @(Get-DnsServerResourceRecord -ZoneName $ZoneName -ErrorAction Stop |
            Sort-Object HostName,RecordType)

        if ($filterText) {
            $records = @($records | Where-Object {
                $_.HostName -like ("*{0}*" -f $filterText) -or
                $_.RecordType -like ("*{0}*" -f $filterText)
            })
        }

        $displayRecords = @($records | Select-Object -First 150)

        Write-Console ''
        Write-Console ("DNS records in {0}:" -f $ZoneName) Cyan
        if ($records.Count -gt 150) {
            Write-Console ("  Showing first 150 of {0}. Use [S] to filter before selecting." -f $records.Count) Yellow
        }

        for ($i = 0; $i -lt $displayRecords.Count; $i++) {
            Write-Console ('  [{0,3}] {1,-36} {2,-8} TTL={3}' -f
                ($i + 1), $displayRecords[$i].HostName, $displayRecords[$i].RecordType, $displayRecords[$i].TimeToLive)
        }

        if ($displayRecords.Count -eq 0) { Write-Console '  No records matched.' Yellow }
        Write-Console '  [S] Search/filter by node name or record type' Gray
        Write-Console '  [0] Cancel' Gray

        $choice = (Read-Host 'Select DNS record').Trim()
        if ($choice -eq '0' -or [string]::IsNullOrWhiteSpace($choice)) { return $null }
        if ($choice.ToUpperInvariant() -eq 'S') {
            $filterText = (Read-Host 'Record filter').Trim()
            continue
        }

        $number = 0
        if ([int]::TryParse($choice, [ref]$number)) {
            $index = $number - 1
            if ($index -ge 0 -and $index -lt $displayRecords.Count) {
                return $displayRecords[$index]
            }
        }
        Write-Console 'Invalid DNS record selection.' Yellow
    }
}

function Select-AdTrustName {
    Assert-DomainController
    if (-not (Test-Command 'Get-ADTrust')) { return $null }

    $trusts = @(Get-ADTrust -Filter * | Sort-Object Name)
    Write-Console ''
    Write-Console 'Domain/forest trusts:' Cyan
    for ($i = 0; $i -lt $trusts.Count; $i++) {
        Write-Console ('  [{0,3}] {1,-36} {2,-14} {3}' -f
            ($i + 1), $trusts[$i].Name, $trusts[$i].Direction, $trusts[$i].TrustType)
    }
    if ($trusts.Count -eq 0) { Write-Console '  No trusts found.' Yellow }
    Write-Console '  [M] Enter trusted domain manually' Gray
    Write-Console '  [0] Cancel' Gray

    while ($true) {
        $choice = (Read-Host 'Select trust').Trim()
        if ($choice -eq '0' -or [string]::IsNullOrWhiteSpace($choice)) { return $null }
        if ($choice.ToUpperInvariant() -eq 'M') {
            $manual = (Read-Host 'Trusted domain/forest DNS name').Trim()
            if ($manual) { return $manual }
            continue
        }
        $number = 0
        if ([int]::TryParse($choice, [ref]$number)) {
            $index = $number - 1
            if ($index -ge 0 -and $index -lt $trusts.Count) { return $trusts[$index].Name }
        }
        Write-Console 'Invalid trust selection.' Yellow
    }
}

function Show-AdUserDetail {
    Assert-DomainController

    $identity = Select-AdUserIdentity -Prompt 'Select user to inspect'
    if (-not $identity) { return }
    Get-ADUser -Identity $identity -Properties * |
        Select-Object SamAccountName, UserPrincipalName, DisplayName, GivenName, Surname,
            Enabled, LockedOut, PasswordLastSet, PasswordNeverExpires, LastLogonDate,
            Mail, Department, Title, DistinguishedName |
        Format-List
}


function Select-AdOuPathInteractive {
    Assert-DomainController

    $domain = Get-ADDomain
    $ous = @(Get-ADOrganizationalUnit -Filter * | Sort-Object DistinguishedName)

    Write-Console ''
    Write-Console 'Available user containers / OUs:' Cyan
    Write-Console ('  [1] {0}  (default Users container)' -f $domain.UsersContainer)

    for ($i = 0; $i -lt $ous.Count; $i++) {
        Write-Console ('  [{0}] {1}' -f ($i + 2), $ous[$i].DistinguishedName)
    }

    Write-Console '  [M] Enter distinguished name manually' Gray
    Write-Console '  [0] Cancel' Gray

    while ($true) {
        $choice = (Read-Host 'Select target container [1]').Trim()
        if ([string]::IsNullOrWhiteSpace($choice)) { return $domain.UsersContainer }
        if ($choice -eq '0') { return $null }
        if ($choice.ToUpperInvariant() -eq 'M') {
            $manual = (Read-Host 'Container distinguished name').Trim()
            if ($manual) { return $manual }
            continue
        }

        $number = 0
        if ([int]::TryParse($choice, [ref]$number)) {
            if ($number -eq 1) { return $domain.UsersContainer }
            $ouIndex = $number - 2
            if ($ouIndex -ge 0 -and $ouIndex -lt $ous.Count) {
                return $ous[$ouIndex].DistinguishedName
            }
        }

        Write-Console 'Invalid container selection.' Yellow
    }
}

function New-AdGroupForSelector {
    Assert-DomainController

    $name = (Read-Host 'New group name').Trim()
    if ([string]::IsNullOrWhiteSpace($name)) { return $null }

    $scope = Select-EnumeratedValue -Title 'GROUP SCOPE' -DefaultIndex 1 -Options @(
        [pscustomobject]@{ Value='Global'; Description='Typical domain role/application group' },
        [pscustomobject]@{ Value='Universal'; Description='Forest-wide group' },
        [pscustomobject]@{ Value='DomainLocal'; Description='Resource permission scope in this domain' }
    )
    if (-not $scope) { return $null }

    $category = Select-EnumeratedValue -Title 'GROUP CATEGORY' -DefaultIndex 1 -Options @(
        [pscustomobject]@{ Value='Security'; Description='Can be used for access control' },
        [pscustomobject]@{ Value='Distribution'; Description='Distribution-only group' }
    )
    if (-not $category) { return $null }

    $path = Select-AdOuDn -Prompt 'Select group container' -AllowDefault
    if ($null -eq $path) { return $null }

    if (-not (Confirm-Action `
        -Action ("Create AD group '{0}'" -f $name) `
        -Reason 'Create a group requested during user membership assignment.' `
        -Impact LOW)) {
        return $null
    }

    New-ChangeSet

    $params = @{
        Name          = $name
        GroupScope    = $scope
        GroupCategory = $category
        PassThru      = $true
    }
    if ($path -and $path -ne '__DEFAULT__') { $params.Path = $path }

    try {
        return (New-ADGroup @params)
    }
    catch {
        Write-Console ("Group creation failed: {0}" -f $_.Exception.Message) Red
        return $null
    }
}

function Select-AdGroupsInteractive {
    param([switch]$AllowCreate)

    Assert-DomainController
    $selected = New-Object 'System.Collections.Generic.List[object]'

    while ($true) {
        $filterText = (Read-Host 'Filter group names (blank = all)').Trim()
        $groups = @(Get-ADGroup -Filter * | Sort-Object Name)

        if ($filterText) {
            $groups = @($groups | Where-Object { $_.Name -like ("*{0}*" -f $filterText) })
        }

        if ($groups.Count -eq 0) {
            Write-Console 'No groups matched the filter.' Yellow
        }
        else {
            Write-Console ''
            Write-Console 'Available groups:' Cyan
            for ($i = 0; $i -lt $groups.Count; $i++) {
                Write-Console ('  [{0,3}] {1,-38} {2}/{3}' -f ($i + 1), $groups[$i].Name, $groups[$i].GroupScope, $groups[$i].GroupCategory)
            }
        }

        Write-Console ''
        Write-Console 'Enter one or more indexes separated by commas.' Gray
        Write-Console '  [S] Search/filter again' Gray
        Write-Console '  [M] Add an existing group by name/GUID/DN manually' Gray
        if ($AllowCreate) { Write-Console '  [N] Create a new group and select it' Green }
        Write-Console '  [0] Finish selection' Gray

        $choice = (Read-Host 'Group selection').Trim()
        if ([string]::IsNullOrWhiteSpace($choice) -or $choice -eq '0') { break }

        switch ($choice.ToUpperInvariant()) {
            'S' { continue }
            'M' {
                $manual = (Read-Host 'Existing group identity').Trim()
                if ($manual) {
                    try {
                        $group = Get-ADGroup -Identity $manual -ErrorAction Stop
                        if (-not ($selected | Where-Object { $_.DistinguishedName -eq $group.DistinguishedName })) {
                            [void]$selected.Add($group)
                        }
                    }
                    catch { Write-Console $_.Exception.Message Red }
                }
                continue
            }
            'N' {
                if (-not $AllowCreate) {
                    Write-Console 'Group creation is disabled in this selector.' Yellow
                    continue
                }
                $group = New-AdGroupForSelector
                if ($group -and -not ($selected | Where-Object { $_.DistinguishedName -eq $group.DistinguishedName })) {
                    [void]$selected.Add($group)
                }
                continue
            }
        }

        foreach ($part in ($choice -split ',')) {
            $number = 0
            if ([int]::TryParse($part.Trim(), [ref]$number)) {
                $index = $number - 1
                if ($index -ge 0 -and $index -lt $groups.Count) {
                    $group = $groups[$index]
                    if (-not ($selected | Where-Object { $_.DistinguishedName -eq $group.DistinguishedName })) {
                        [void]$selected.Add($group)
                    }
                }
                else {
                    Write-Console ("Index out of range: {0}" -f $number) Yellow
                }
            }
            else {
                Write-Console ("Invalid group index: {0}" -f $part) Yellow
            }
        }

        if ($selected.Count -gt 0) {
            Write-Console ''
            Write-Console ('Selected groups: {0}' -f (($selected | ForEach-Object { $_.Name }) -join ', ')) Green
        }

        if (-not (Read-BooleanChoice -Prompt 'Add more groups?' -Default $false)) { break }
    }

    return @($selected)
}


function Test-AdUserEffectiveGroupMembership {
    param(
        [Parameter(Mandatory)][Microsoft.ActiveDirectory.Management.ADUser]$User,
        [Parameter(Mandatory)][Microsoft.ActiveDirectory.Management.ADGroup]$Group
    )

    try {
        $memberships = @(Get-ADPrincipalGroupMembership -Identity $User -ErrorAction Stop)
        return [bool]($memberships | Where-Object { $_.DistinguishedName -eq $Group.DistinguishedName })
    }
    catch {
        Write-Log ("Could not verify existing membership {0} -> {1}: {2}" -f
            $User.SamAccountName, $Group.Name, $_.Exception.Message) WARN
        return $false
    }
}

function Add-AdUserGroupMembershipSafe {
    param(
        [Parameter(Mandatory)]$User,
        [Parameter(Mandatory)]$Group
    )

    if ($User -isnot [Microsoft.ActiveDirectory.Management.ADUser]) {
        $User = Get-ADUser -Identity $User -ErrorAction Stop
    }
    if ($Group -isnot [Microsoft.ActiveDirectory.Management.ADGroup]) {
        $Group = Get-ADGroup -Identity $Group -ErrorAction Stop
    }

    if (Test-AdUserEffectiveGroupMembership -User $User -Group $Group) {
        if ($Group.Name -eq 'Domain Users') {
            Write-Console ("SKIP: {0} already has effective membership in Domain Users (normally its primary group)." -f
                $User.SamAccountName) Yellow
        }
        else {
            Write-Console ("SKIP: {0} is already a member of {1}." -f
                $User.SamAccountName, $Group.Name) Yellow
        }
        Write-Log ("Skipped duplicate/effective membership: {0} -> {1}" -f
            $User.SamAccountName, $Group.Name) INFO
        return $true
    }

    try {
        Add-ADGroupMember -Identity $Group -Members $User -ErrorAction Stop
        Write-Log ("Added {0} to group {1}" -f $User.SamAccountName, $Group.Name) CHANGE
        return $true
    }
    catch {
        # Re-check to tolerate races or provider-specific "already a member"
        # errors without treating an idempotent end state as a failure.
        if (Test-AdUserEffectiveGroupMembership -User $User -Group $Group) {
            Write-Console ("SKIP: {0} already has effective membership in {1}." -f
                $User.SamAccountName, $Group.Name) Yellow
            return $true
        }

        Write-Console ("Could not add {0} to {1}: {2}" -f
            $User.SamAccountName, $Group.Name, $_.Exception.Message) Red
        Write-Log ("Failed group membership: {0} -> {1}: {2}" -f
            $User.SamAccountName, $Group.Name, $_.Exception.Message) ERROR
        return $false
    }
}

function Manage-AdUserGroupsInteractive {
    param([string]$Identity)

    Assert-DomainController

    if ([string]::IsNullOrWhiteSpace($Identity)) {
        $Identity = Select-AdUserIdentity -Prompt 'Select user'
    }
    if ([string]::IsNullOrWhiteSpace($Identity)) { return }

    $user = Get-ADUser -Identity $Identity -ErrorAction Stop

    while ($true) {
        if ($script:MainMenuRequested) { return }
        $current = @(Get-ADPrincipalGroupMembership -Identity $user | Sort-Object Name)

        Write-MenuHeader 'USER GROUP MEMBERSHIP' ("Account: {0}" -f $user.SamAccountName)
        if ($current.Count -eq 0) {
            Write-Console '  No direct group memberships returned.' Yellow
        }
        else {
            for ($i = 0; $i -lt $current.Count; $i++) {
                Write-Console ('  [{0,3}] {1,-42} {2}' -f ($i + 1), $current[$i].Name, $current[$i].GroupScope)
            }
        }
        Write-Console ''
        Write-MenuItem 'A' 'Add memberships' 'Choose existing groups or create a new one' Good
        Write-MenuItem 'R' 'Remove memberships' 'Choose one or more current memberships' Warn
        Write-MenuNavigation -BackDescription 'Return to user directory'
        Write-Rule

        $choice = (Read-Host 'Select operation').Trim().ToUpperInvariant()
        switch ($choice) {
            'H' { $script:MainMenuRequested = $true; return }
            'A' {
                $groups = @(Select-AdGroupsInteractive -AllowCreate)
                foreach ($group in $groups) {
                    if (-not (Confirm-Action `
                        -Action ("Add '{0}' to group '{1}'" -f $user.SamAccountName, $group.Name) `
                        -Reason 'Grant domain group membership.' `
                        -Impact MEDIUM)) { continue }

                    New-ChangeSet
                    [void](Add-AdUserGroupMembershipSafe -User $user -Group $group)
                }
            }
            'R' {
                if ($current.Count -eq 0) {
                    Write-Console 'No memberships are available to remove.' Yellow
                    Pause-ControlPlane
                    continue
                }

                $raw = (Read-Host 'Indexes to remove (comma-separated)').Trim()
                foreach ($part in ($raw -split ',')) {
                    $number = 0
                    if (-not [int]::TryParse($part.Trim(), [ref]$number)) { continue }
                    $index = $number - 1
                    if ($index -lt 0 -or $index -ge $current.Count) { continue }
                    $group = $current[$index]

                    if (Confirm-Action `
                        -Action ("Remove '{0}' from group '{1}'" -f $user.SamAccountName, $group.Name) `
                        -Reason 'Revoke domain group membership.' `
                        -Impact MEDIUM) {

                        New-ChangeSet
                        Remove-ADGroupMember -Identity $group -Members $user -Confirm:$false
                        Write-Log ("Removed {0} from group {1}" -f $user.SamAccountName, $group.Name) CHANGE
                    }
                }
            }
            '0' { return }
            default { Write-Console 'Invalid option.' Yellow; Pause-ControlPlane }
        }
    }
}

function New-AdUserInteractive {
    Assert-DomainController

    $sam = (Read-Host 'sAMAccountName').Trim()
    if ([string]::IsNullOrWhiteSpace($sam)) { return }

    if (Get-ADUser -Identity $sam -ErrorAction SilentlyContinue) {
        Write-Console 'User already exists.' Yellow
        return
    }

    $domain = Get-ADDomain
    $given = Read-Host 'Given name'
    $surname = Read-Host 'Surname'
    $display = Read-Host 'Display name'
    if ([string]::IsNullOrWhiteSpace($display)) {
        $display = ("{0} {1}" -f $given, $surname).Trim()
    }

    $defaultUpn = "{0}@{1}" -f $sam, $domain.DNSRoot
    $upn = (Read-Host ("User principal name [{0}]" -f $defaultUpn)).Trim()
    if ([string]::IsNullOrWhiteSpace($upn)) { $upn = $defaultUpn }

    $description = Read-Host 'Description / purpose'
    $mail = Read-Host 'Email address'
    $department = Read-Host 'Department'
    $title = Read-Host 'Title / role'
    $company = Read-Host 'Company'
    $office = Read-Host 'Office'
    $phone = Read-Host 'Office phone'

    $path = Select-AdOuPathInteractive
    if (-not $path) { return }

    $password = Read-Host 'Initial password' -AsSecureString

    $enabled = Read-BooleanChoice -Prompt 'Enable account immediately?' -Default $true
    $changeAtLogon = Read-BooleanChoice -Prompt 'Require password change at first logon?' -Default $true
    $passwordNeverExpires = Read-BooleanChoice -Prompt 'Password never expires?' -Default $false
    $cannotChangePassword = Read-BooleanChoice -Prompt 'Prevent user from changing password?' -Default $false

    if ($passwordNeverExpires -and $changeAtLogon) {
        Write-Console 'PasswordNeverExpires conflicts with ChangePasswordAtLogon; first-logon change has been disabled.' Yellow
        $changeAtLogon = $false
    }

    Write-Console ''
    Write-Console 'User creation plan:' Cyan
    Write-Console ("  Account       : {0}" -f $sam)
    Write-Console ("  UPN           : {0}" -f $upn)
    Write-Console ("  Display name  : {0}" -f $display)
    Write-Console ("  Container     : {0}" -f $path)
    Write-Console ("  Enabled       : {0}" -f $enabled)
    Write-Console ("  Change @ logon: {0}" -f $changeAtLogon)
    Write-Console ("  Never expires : {0}" -f $passwordNeverExpires)
    Write-Console ("  Cannot change : {0}" -f $cannotChangePassword)

    if (-not (Confirm-Action `
        -Action ("Create AD user '{0}'" -f $sam) `
        -Reason 'Create the configured domain identity.' `
        -Impact LOW)) {
        return
    }

    New-ChangeSet

    $params = @{
        SamAccountName        = $sam
        UserPrincipalName     = $upn
        Name                  = $display
        DisplayName           = $display
        GivenName             = $given
        Surname               = $surname
        Enabled               = $enabled
        AccountPassword       = $password
        ChangePasswordAtLogon = $changeAtLogon
        PasswordNeverExpires  = $passwordNeverExpires
        CannotChangePassword  = $cannotChangePassword
        Path                  = $path
    }

    if ($description) { $params.Description = $description }
    if ($mail) { $params.EmailAddress = $mail }
    if ($department) { $params.Department = $department }
    if ($title) { $params.Title = $title }
    if ($company) { $params.Company = $company }
    if ($office) { $params.Office = $office }
    if ($phone) { $params.OfficePhone = $phone }

    New-ADUser @params
    Write-Log ("Created AD user: {0}" -f $sam) CHANGE

    if (Read-BooleanChoice -Prompt 'Assign domain group memberships now?' -Default $true) {
        Write-Console 'Note: new AD users already use Domain Users as their primary group; it does not need to be added again.' Cyan
        $createdUser = Get-ADUser -Identity $sam -ErrorAction Stop
        $groups = @(Select-AdGroupsInteractive -AllowCreate)
        foreach ($group in $groups) {
            [void](Add-AdUserGroupMembershipSafe -User $createdUser -Group $group)
        }
    }
}

function Edit-AdUserInteractive {
    Assert-DomainController

    $identity = Select-AdUserIdentity -Prompt 'Select user to edit'
    if ([string]::IsNullOrWhiteSpace($identity)) { return }

    $user = Get-ADUser -Identity $identity -Properties DisplayName, Mail, Department, Title, Company,
        Office, OfficePhone, Description, UserPrincipalName, PasswordNeverExpires, CannotChangePassword, Enabled

    Write-Console 'Leave text values blank to keep the current value.' Gray
    Write-Console 'For boolean options use K=keep, Y=yes, N=no.' Gray

    $display = Read-Host ("Display name [{0}]" -f $user.DisplayName)
    $upn = Read-Host ("User principal name [{0}]" -f $user.UserPrincipalName)
    $mail = Read-Host ("Email [{0}]" -f $user.Mail)
    $description = Read-Host ("Description [{0}]" -f $user.Description)
    $department = Read-Host ("Department [{0}]" -f $user.Department)
    $title = Read-Host ("Title [{0}]" -f $user.Title)
    $company = Read-Host ("Company [{0}]" -f $user.Company)
    $office = Read-Host ("Office [{0}]" -f $user.Office)
    $phone = Read-Host ("Office phone [{0}]" -f $user.OfficePhone)

    $changeAtLogon = Read-OptionalBooleanChoice -Prompt 'Require password change at next logon?'
    $passwordNeverExpires = Read-OptionalBooleanChoice -Prompt 'Password never expires?'
    $cannotChangePassword = Read-OptionalBooleanChoice -Prompt 'Prevent user from changing password?'
    $enabled = Read-OptionalBooleanChoice -Prompt ("Account enabled? (currently {0})" -f $user.Enabled)

    if ($passwordNeverExpires -eq $true -and $changeAtLogon -eq $true) {
        Write-Console 'PasswordNeverExpires conflicts with ChangePasswordAtLogon; first-logon change will be disabled.' Yellow
        $changeAtLogon = $false
    }

    if (-not (Confirm-Action `
        -Action ("Update AD user '{0}'" -f $identity) `
        -Reason 'Modify selected directory attributes and account controls.' `
        -Impact LOW)) {
        return
    }

    New-ChangeSet

    $params = @{ Identity = $identity }
    if ($display) { $params.DisplayName = $display }
    if ($upn) { $params.UserPrincipalName = $upn }
    if ($mail) { $params.EmailAddress = $mail }
    if ($description) { $params.Description = $description }
    if ($department) { $params.Department = $department }
    if ($title) { $params.Title = $title }
    if ($company) { $params.Company = $company }
    if ($office) { $params.Office = $office }
    if ($phone) { $params.OfficePhone = $phone }
    if ($null -ne $changeAtLogon) { $params.ChangePasswordAtLogon = [bool]$changeAtLogon }
    if ($null -ne $passwordNeverExpires) { $params.PasswordNeverExpires = [bool]$passwordNeverExpires }
    if ($null -ne $cannotChangePassword) { $params.CannotChangePassword = [bool]$cannotChangePassword }

    if ($params.Count -gt 1) {
        Set-ADUser @params
        Write-Log ("Updated AD user: {0}" -f $identity) CHANGE
    }

    if ($null -ne $enabled) {
        if ([bool]$enabled) { Enable-ADAccount -Identity $identity }
        else { Disable-ADAccount -Identity $identity }
    }

    if (Read-BooleanChoice -Prompt 'Manage this user''s group memberships now?' -Default $false) {
        Manage-AdUserGroupsInteractive -Identity $identity
    }
}

function Reset-AdUserPassword {
    Assert-DomainController

    $identity = Select-AdUserIdentity -Prompt 'Select user for password reset'
    if (-not $identity) { return }
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

    $identity = Select-AdUserIdentity -Prompt $(if ($Enabled) { 'Select user to enable' } else { 'Select user to disable' })
    if (-not $identity) { return }
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

    $identity = Select-AdUserIdentity -Prompt 'Select user to unlock'
    if (-not $identity) { return }

    if (Confirm-Action `
        -Action ("Unlock AD user '{0}'" -f $identity) `
        -Reason 'Clear the account lockout state.' `
        -Impact LOW) {

        Unlock-ADAccount -Identity $identity
    }
}

function Remove-AdUserInteractive {
    Assert-DomainController

    $identity = Select-AdUserIdentity -Prompt 'Select user to delete'
    if (-not $identity) { return }

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
    $scope = Select-EnumeratedValue -Title 'GROUP SCOPE' -DefaultIndex 1 -Options @(
        [pscustomobject]@{ Value='Global'; Description='Typical domain role/application group' },
        [pscustomobject]@{ Value='Universal'; Description='Forest-wide group' },
        [pscustomobject]@{ Value='DomainLocal'; Description='Resource permission scope in this domain' }
    )
    if (-not $scope) { return $null }

    $category = Select-EnumeratedValue -Title 'GROUP CATEGORY' -DefaultIndex 1 -Options @(
        [pscustomobject]@{ Value='Security'; Description='Can be used for access control' },
        [pscustomobject]@{ Value='Distribution'; Description='Distribution-only group' }
    )
    if (-not $category) { return $null }

    $path = Select-AdOuDn -Prompt 'Select group container' -AllowDefault
    if ($null -eq $path) { return $null }

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

    if ($path -and $path -ne '__DEFAULT__') { $params.Path = $path }

    New-ADGroup @params
}

function Show-AdGroupMembers {
    Assert-DomainController

    $group = Select-AdGroupIdentity -Prompt 'Select group to inspect'
    if (-not $group) { return }
    Get-ADGroupMember -Identity $group |
        Select-Object Name, SamAccountName, ObjectClass, DistinguishedName |
        Format-Table -AutoSize
}

function Add-AdGroupMemberInteractive {
    Assert-DomainController

    $group = Select-AdGroupIdentity -Prompt 'Select target group'
    if (-not $group) { return }
    $principal = Select-AdPrincipalIdentity
    if (-not $principal) { return }
    $member = $principal.Identity

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

    $group = Select-AdGroupIdentity -Prompt 'Select target group'
    if (-not $group) { return }
    $member = Select-AdGroupMemberIdentity -Group $group
    if (-not $member) { return }

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

    $group = Select-AdGroupIdentity -Prompt 'Select group to delete'
    if (-not $group) { return }

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

    $identity = Select-AdComputerIdentity -Prompt 'Select computer to inspect'
    if (-not $identity) { return }
    Get-ADComputer -Identity $identity -Properties * |
        Select-Object Name, Enabled, DNSHostName, IPv4Address, OperatingSystem,
            OperatingSystemVersion, LastLogonDate, PasswordLastSet, DistinguishedName |
        Format-List
}

function Set-AdComputerEnabledState {
    param([Parameter(Mandatory=$true)][bool]$Enabled)

    Assert-DomainController

    $identity = Select-AdComputerIdentity -Prompt $(if ($Enabled) { 'Select computer to enable' } else { 'Select computer to disable' })
    if (-not $identity) { return }
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

    $identity = Select-AdComputerIdentity -Prompt 'Select computer to delete'
    if (-not $identity) { return }

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
    $path = Select-AdOuDn -Prompt 'Select parent container' -IncludeDomainRoot
    if (-not $path) { return }

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

    $identity = Select-AdDirectoryObjectIdentity
    if (-not $identity) { return }
    $target = Select-AdOuDn -Prompt 'Select destination OU' -IncludeDomainRoot
    if (-not $target) { return }

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

    $identity = Select-AdOuDn -Prompt 'Select OU to delete'
    if (-not $identity) { return }

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
        $previousProgress = $ProgressPreference
        try {
            $ProgressPreference = 'SilentlyContinue'
            Import-Module GroupPolicy -ErrorAction Stop -DisableNameChecking
        }
        catch {
            throw ("GroupPolicy module unavailable: {0}" -f $_.Exception.Message)
        }
        finally {
            $ProgressPreference = $previousProgress
        }
    }
}


function Get-GpoInventory {
    Assert-DomainController
    Import-GroupPolicyModule

    $previousProgress = $ProgressPreference
    try {
        # GroupPolicy cmdlets can render a progress UI that behaves badly in
        # redirected/embedded consoles. Inventory is intentionally quiet.
        $ProgressPreference = 'SilentlyContinue'
        return @(Get-GPO -All -ErrorAction Stop | Sort-Object DisplayName)
    }
    finally {
        $ProgressPreference = $previousProgress
    }
}

function Show-GpoInventoryIndexed {
    $gpos = @(Get-GpoInventory)

    Write-Console ''
    Write-Console 'Existing GPOs:' Cyan
    if ($gpos.Count -eq 0) {
        Write-Console '  No GPOs returned.' Yellow
        return @()
    }

    for ($i = 0; $i -lt $gpos.Count; $i++) {
        Write-Console ('  [{0,3}] {1,-38} {2}  {3}' -f `
            ($i + 1), $gpos[$i].DisplayName, $gpos[$i].Id, $gpos[$i].GpoStatus)
    }

    return $gpos
}

function Select-GpoInteractive {
    param([string]$Prompt = 'Select GPO')

    $gpos = @(Show-GpoInventoryIndexed)
    Write-Console ''
    Write-Console '  [M] Enter a GPO name or GUID manually' Gray
    Write-Console '  [0] Cancel' Gray

    while ($true) {
        $choice = (Read-Host $Prompt).Trim()
        if ($choice -eq '0' -or [string]::IsNullOrWhiteSpace($choice)) { return $null }

        if ($choice.ToUpperInvariant() -eq 'M') {
            $manual = (Read-Host 'GPO display name or GUID').Trim()
            if (-not $manual) { continue }

            try {
                $parsed = [guid]::Empty
                if ([guid]::TryParse($manual, [ref]$parsed)) {
                    return (Get-GPO -Guid $parsed -ErrorAction Stop)
                }
                return (Get-GPO -Name $manual -ErrorAction Stop)
            }
            catch {
                Write-Console ("GPO not found: {0}" -f $_.Exception.Message) Red
                continue
            }
        }

        $number = 0
        if ([int]::TryParse($choice, [ref]$number)) {
            $index = $number - 1
            if ($index -ge 0 -and $index -lt $gpos.Count) {
                return $gpos[$index]
            }
        }

        Write-Console 'Invalid GPO selection.' Yellow
    }
}

function Select-GpoTargetInteractive {
    Assert-DomainController

    $domain = Get-ADDomain
    $ous = @(Get-ADOrganizationalUnit -Filter * | Sort-Object DistinguishedName)

    Write-Console ''
    Write-Console 'GPO link targets:' Cyan
    Write-Console ('  [1] DOMAIN ROOT  {0}' -f $domain.DistinguishedName) Green

    for ($i = 0; $i -lt $ous.Count; $i++) {
        Write-Console ('  [{0,3}] OU  {1}' -f ($i + 2), $ous[$i].DistinguishedName)
    }

    Write-Console '  [M] Enter target distinguished name manually' Gray
    Write-Console '  [0] Cancel' Gray

    while ($true) {
        $choice = (Read-Host 'Select GPO target [1]').Trim()
        if ([string]::IsNullOrWhiteSpace($choice)) { return $domain.DistinguishedName }
        if ($choice -eq '0') { return $null }
        if ($choice.ToUpperInvariant() -eq 'M') {
            $manual = (Read-Host 'Target distinguished name').Trim()
            if ($manual) { return $manual }
            continue
        }

        $number = 0
        if ([int]::TryParse($choice, [ref]$number)) {
            if ($number -eq 1) { return $domain.DistinguishedName }
            $index = $number - 2
            if ($index -ge 0 -and $index -lt $ous.Count) {
                return $ous[$index].DistinguishedName
            }
        }

        Write-Console 'Invalid target selection.' Yellow
    }
}

function Get-SecurityGpoCatalog {
    return @(
        [pscustomobject]@{
            Key='1'; Name='SEC - PowerShell Logging'; Impact='LOW'; Scope='Computer';
            Description='Script block and module logging for administrative visibility.';
            Settings=@(
                @{ Key='HKLM\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging'; ValueName='EnableScriptBlockLogging'; Type='DWord'; Value=1 },
                @{ Key='HKLM\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging'; ValueName='EnableModuleLogging'; Type='DWord'; Value=1 },
                @{ Key='HKLM\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging\ModuleNames'; ValueName='*'; Type='String'; Value='*' }
            )
        },
        [pscustomobject]@{
            Key='2'; Name='SEC - Disable LLMNR'; Impact='MEDIUM'; Scope='Computer';
            Description='Disable multicast name resolution; prefer AD DNS.';
            Settings=@(
                @{ Key='HKLM\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'; ValueName='EnableMulticast'; Type='DWord'; Value=0 }
            )
        },
        [pscustomobject]@{
            Key='3'; Name='SEC - SMB Guest Hardening'; Impact='MEDIUM'; Scope='Computer';
            Description='Reject insecure unauthenticated SMB guest logons.';
            Settings=@(
                @{ Key='HKLM\SOFTWARE\Policies\Microsoft\Windows\LanmanWorkstation'; ValueName='AllowInsecureGuestAuth'; Type='DWord'; Value=0 }
            )
        },
        [pscustomobject]@{
            Key='4'; Name='SEC - RDP Network Level Authentication'; Impact='MEDIUM'; Scope='Computer';
            Description='Require NLA for Remote Desktop Session Host connections.';
            Settings=@(
                @{ Key='HKLM\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'; ValueName='UserAuthentication'; Type='DWord'; Value=1 }
            )
        },
        [pscustomobject]@{
            Key='5'; Name='SEC - Microsoft Defender Core'; Impact='MEDIUM'; Scope='Computer';
            Description='Enable PUA protection and core Defender realtime policy values; review third-party EDR coexistence first.';
            Settings=@(
                @{ Key='HKLM\SOFTWARE\Policies\Microsoft\Windows Defender'; ValueName='PUAProtection'; Type='DWord'; Value=1 },
                @{ Key='HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection'; ValueName='DisableRealtimeMonitoring'; Type='DWord'; Value=0 },
                @{ Key='HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection'; ValueName='DisableBehaviorMonitoring'; Type='DWord'; Value=0 },
                @{ Key='HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection'; ValueName='DisableIOAVProtection'; Type='DWord'; Value=0 },
                @{ Key='HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection'; ValueName='DisableScriptScanning'; Type='DWord'; Value=0 }
            )
        },
        [pscustomobject]@{
            Key='6'; Name='SEC - Windows Firewall Baseline'; Impact='HIGH'; Scope='Computer';
            Description='Enable Domain/Private/Public firewalls; block inbound by default and allow outbound by default.';
            Settings=@(
                @{ Key='HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\DomainProfile'; ValueName='EnableFirewall'; Type='DWord'; Value=1 },
                @{ Key='HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\DomainProfile'; ValueName='DefaultInboundAction'; Type='DWord'; Value=1 },
                @{ Key='HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\DomainProfile'; ValueName='DefaultOutboundAction'; Type='DWord'; Value=0 },
                @{ Key='HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\PrivateProfile'; ValueName='EnableFirewall'; Type='DWord'; Value=1 },
                @{ Key='HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\PrivateProfile'; ValueName='DefaultInboundAction'; Type='DWord'; Value=1 },
                @{ Key='HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\PrivateProfile'; ValueName='DefaultOutboundAction'; Type='DWord'; Value=0 },
                @{ Key='HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\PublicProfile'; ValueName='EnableFirewall'; Type='DWord'; Value=1 },
                @{ Key='HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\PublicProfile'; ValueName='DefaultInboundAction'; Type='DWord'; Value=1 },
                @{ Key='HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\PublicProfile'; ValueName='DefaultOutboundAction'; Type='DWord'; Value=0 }
            )
        },
        [pscustomobject]@{
            Key='7'; Name='SEC - Secure Screen Lock'; Impact='LOW'; Scope='User';
            Description='Enable password-protected screen saver with a 15-minute timeout.';
            Settings=@(
                @{ Key='HKCU\Software\Policies\Microsoft\Windows\Control Panel\Desktop'; ValueName='ScreenSaveActive'; Type='String'; Value='1' },
                @{ Key='HKCU\Software\Policies\Microsoft\Windows\Control Panel\Desktop'; ValueName='ScreenSaveTimeOut'; Type='String'; Value='900' },
                @{ Key='HKCU\Software\Policies\Microsoft\Windows\Control Panel\Desktop'; ValueName='ScreenSaverIsSecure'; Type='String'; Value='1' }
            )
        },
        [pscustomobject]@{
            Key='8'; Name='SEC - Disable AlwaysInstallElevated'; Impact='LOW'; Scope='Computer + User';
            Description='Explicitly disable the risky AlwaysInstallElevated Windows Installer policy in both scopes.';
            Settings=@(
                @{ Key='HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer'; ValueName='AlwaysInstallElevated'; Type='DWord'; Value=0 },
                @{ Key='HKCU\SOFTWARE\Policies\Microsoft\Windows\Installer'; ValueName='AlwaysInstallElevated'; Type='DWord'; Value=0 }
            )
        }
    )
}

function Show-SecurityGpoCatalog {
    $catalog = @(Get-SecurityGpoCatalog)

    Write-Console ''
    Write-Console 'Curated security GPO templates:' Cyan
    foreach ($item in $catalog) {
        $color = if ($item.Impact -eq 'HIGH') { 'Red' } elseif ($item.Impact -eq 'MEDIUM') { 'Yellow' } else { 'Green' }
        Write-Console ('  [{0}] {1,-42} {2,-15} Impact={3}' -f $item.Key, $item.Name, $item.Scope, $item.Impact) $color
        Write-Console ('      {0}' -f $item.Description) Gray
    }

    Write-Console ''
    Write-Console '  [A] Recommended starter pack: 1,2,3,4,7,8' Green
    Write-Console '  [M] Microsoft baseline guidance only (SCT / OSConfig; no automatic import)' Cyan
    Write-Console '  [H] Main menu' Yellow
    Write-Console '  [0] Cancel' Gray

    return $catalog
}

function Apply-SecurityGpoTemplate {
    param(
        [Parameter(Mandatory=$true)]$Template,
        [Parameter(Mandatory=$true)][string]$Target
    )

    Import-GroupPolicyModule
    $previousProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'

    try {
        $gpo = $null
        try {
            $gpo = Get-GPO -Name $Template.Name -ErrorAction Stop
            Write-Console ("Updating existing GPO: {0} [{1}]" -f $gpo.DisplayName, $gpo.Id) Yellow

            $backupPath = Join-Path $script:RunPath 'gpo-backups'
            New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
            Backup-GPO -Guid $gpo.Id -Path $backupPath -ErrorAction SilentlyContinue | Out-Null
        }
        catch {
            $gpo = New-GPO -Name $Template.Name -Comment $Template.Description -ErrorAction Stop
            Write-Console ("Created GPO: {0} [{1}]" -f $gpo.DisplayName, $gpo.Id) Green
        }

        foreach ($setting in $Template.Settings) {
            Set-GPRegistryValue `
                -Guid $gpo.Id `
                -Key $setting.Key `
                -ValueName $setting.ValueName `
                -Type $setting.Type `
                -Value $setting.Value `
                -ErrorAction Stop | Out-Null
        }

        try {
            New-GPLink -Guid $gpo.Id -Target $Target -LinkEnabled Yes -ErrorAction Stop | Out-Null
        }
        catch {
            Set-GPLink -Guid $gpo.Id -Target $Target -LinkEnabled Yes -ErrorAction Stop | Out-Null
        }

        Write-Log ("Applied security GPO template: {0} -> {1}" -f $Template.Name, $Target) CHANGE
        return $gpo
    }
    finally {
        $ProgressPreference = $previousProgress
    }
}

function Invoke-SecurityGpoWizard {
    Assert-DomainController
    Import-GroupPolicyModule

    Write-MenuHeader 'SECURITY GPO CATALOG' 'Curated common domain GPOs; choose templates and target scope instead of typing GUIDs'
    $catalog = @(Show-SecurityGpoCatalog)

    $raw = (Read-Host 'Template selection (comma-separated)').Trim().ToUpperInvariant()
    if ([string]::IsNullOrWhiteSpace($raw) -or $raw -eq '0') { return }
    if ($raw -eq 'H') { $script:MainMenuRequested = $true; return }

    if ($raw -eq 'M') {
        Write-Console ''
        Write-Console 'For a complete vendor baseline, use Microsoft Security Compliance Toolkit (Server 2019/2022/2025)' Cyan
        Write-Console 'or Windows Server 2025 OSConfig role-aware baselines. This assistant intentionally does not fabricate' Gray
        Write-Console 'a complete Microsoft baseline from a handful of registry values.' Gray
        Pause-ControlPlane
        return
    }

    $keys = if ($raw -eq 'A') { @('1','2','3','4','7','8') } else { @($raw -split ',' | ForEach-Object { $_.Trim() }) }
    $selected = @($catalog | Where-Object { $_.Key -in $keys })

    if ($selected.Count -eq 0) {
        Write-Console 'No valid templates selected.' Yellow
        return
    }

    $target = Select-GpoTargetInteractive
    if (-not $target) { return }

    Write-Console ''
    Write-Console 'GPO deployment plan:' Cyan
    foreach ($template in $selected) {
        Write-Console ('  - {0}  [Impact={1}]' -f $template.Name, $template.Impact)
    }
    Write-Console ("  Target: {0}" -f $target)

    $impact = if (@($selected | Where-Object { $_.Impact -eq 'HIGH' }).Count -gt 0) { 'HIGH' } `
        elseif (@($selected | Where-Object { $_.Impact -eq 'MEDIUM' }).Count -gt 0) { 'MEDIUM' } `
        else { 'LOW' }

    if (-not (Confirm-Action `
        -Action ("Create/update {0} security GPO template(s) and link them to '{1}'" -f $selected.Count, $target) `
        -Reason 'Deploy selected common domain security policies.' `
        -Impact $impact)) {
        return
    }

    New-ChangeSet

    foreach ($template in $selected) {
        try {
            [void](Apply-SecurityGpoTemplate -Template $template -Target $target)
        }
        catch {
            Write-Console ("Failed template '{0}': {1}" -f $template.Name, $_.Exception.Message) Red
        }
    }

    Write-Console ''
    Write-Console 'Security GPO deployment pass completed.' Green
    Show-GpoInventoryIndexed | Out-Null
}

function Show-Gpos {
    Assert-DomainController
    [void](Show-GpoInventoryIndexed)
}

function Show-GpoDetail {
    Assert-DomainController
    Import-GroupPolicyModule

    $gpo = Select-GpoInteractive -Prompt 'Select GPO to inspect'
    if (-not $gpo) { return }

    $gpo | Format-List DisplayName, Id, DomainName, Owner, GpoStatus, CreationTime, ModificationTime, Description
}

function New-GpoInteractive {
    Assert-DomainController
    Import-GroupPolicyModule

    $name = (Read-Host 'New GPO display name').Trim()
    if ([string]::IsNullOrWhiteSpace($name)) { return }

    $comment = Read-Host 'Comment / purpose'

    if (-not (Confirm-Action `
        -Action ("Create GPO '{0}'" -f $name) `
        -Reason 'Create an empty Group Policy Object.' `
        -Impact LOW)) {
        return
    }

    New-ChangeSet

    $previousProgress = $ProgressPreference
    try {
        $ProgressPreference = 'SilentlyContinue'
        $gpo = New-GPO -Name $name -Comment $comment -ErrorAction Stop
    }
    finally {
        $ProgressPreference = $previousProgress
    }

    Write-Console ("Created GPO: {0}" -f $gpo.DisplayName) Green
    Write-Console ("GUID       : {0}" -f $gpo.Id) Cyan

    if (Read-BooleanChoice -Prompt 'Link this GPO now?' -Default $true) {
        $target = Select-GpoTargetInteractive
        if ($target) {
            try {
                New-GPLink -Guid $gpo.Id -Target $target -LinkEnabled Yes -ErrorAction Stop | Out-Null
                Write-Console ("Linked to: {0}" -f $target) Green
            }
            catch {
                Write-Console ("GPO created but link failed: {0}" -f $_.Exception.Message) Yellow
            }
        }
    }
}

function Backup-GpoInteractive {
    Assert-DomainController
    Import-GroupPolicyModule

    $gpo = Select-GpoInteractive -Prompt 'Select GPO to back up'
    if (-not $gpo) { return }

    $path = Join-Path $script:RunPath 'gpo-backups'
    New-Item -ItemType Directory -Path $path -Force | Out-Null

    $previousProgress = $ProgressPreference
    try {
        $ProgressPreference = 'SilentlyContinue'
        $backup = Backup-GPO -Guid $gpo.Id -Path $path -ErrorAction Stop
    }
    finally {
        $ProgressPreference = $previousProgress
    }

    Write-Console ("GPO        : {0}" -f $backup.DisplayName) Green
    Write-Console ("GPO GUID   : {0}" -f $backup.Id) Cyan
    Write-Console ("Backup GUID: {0}" -f $backup.BackupId) Cyan
    Write-Console ("Directory  : {0}" -f $backup.BackupDirectory)
}

function Set-GpoRegistryValueInteractive {
    Assert-DomainController
    Import-GroupPolicyModule

    $gpo = Select-GpoInteractive -Prompt 'Select GPO to edit'
    if (-not $gpo) { return }

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
        -Action ("Set registry policy '{0}' in GPO '{1}' [{2}]" -f $valueName, $gpo.DisplayName, $gpo.Id) `
        -Reason 'Edit a registry-based Group Policy setting.' `
        -Impact MEDIUM) {

        New-ChangeSet
        Set-GPRegistryValue -Guid $gpo.Id -Key $key -ValueName $valueName -Type $type -Value $value | Out-Null
    }
}

function Link-GpoInteractive {
    Assert-DomainController
    Import-GroupPolicyModule

    $gpo = Select-GpoInteractive -Prompt 'Select GPO to link'
    if (-not $gpo) { return }

    $target = Select-GpoTargetInteractive
    if (-not $target) { return }

    if (Confirm-Action `
        -Action ("Link GPO '{0}' [{1}] to '{2}'" -f $gpo.DisplayName, $gpo.Id, $target) `
        -Reason 'Change Group Policy scope.' `
        -Impact MEDIUM) {

        New-ChangeSet

        try {
            New-GPLink -Guid $gpo.Id -Target $target -LinkEnabled Yes -ErrorAction Stop | Out-Null
        }
        catch {
            Set-GPLink -Guid $gpo.Id -Target $target -LinkEnabled Yes | Out-Null
        }
    }
}

function Unlink-GpoInteractive {
    Assert-DomainController
    Import-GroupPolicyModule

    $gpo = Select-GpoInteractive -Prompt 'Select GPO link to remove'
    if (-not $gpo) { return }

    $target = Select-GpoTargetInteractive
    if (-not $target) { return }

    if (Confirm-Action `
        -Action ("Remove link for GPO '{0}' [{1}] from '{2}'" -f $gpo.DisplayName, $gpo.Id, $target) `
        -Reason 'Remove Group Policy scope from a container.' `
        -Impact MEDIUM) {

        New-ChangeSet
        Remove-GPLink -Guid $gpo.Id -Target $target -Confirm:$false
    }
}

function Set-GpoPermissionInteractive {
    Assert-DomainController
    Import-GroupPolicyModule

    $gpo = Select-GpoInteractive -Prompt 'Select GPO for delegation/security filtering'
    if (-not $gpo) { return }

    $principal = Select-AdPrincipalIdentity
    if (-not $principal) { return }

    $permission = Select-EnumeratedValue -Title 'GPO PERMISSION LEVEL' -DefaultIndex 1 -Options @(
        [pscustomobject]@{ Value='GpoRead'; Description='Read the GPO' },
        [pscustomobject]@{ Value='GpoApply'; Description='Read and apply policy' },
        [pscustomobject]@{ Value='GpoEdit'; Description='Edit settings' },
        [pscustomobject]@{ Value='GpoEditDeleteModifySecurity'; Description='Full GPO administration' },
        [pscustomobject]@{ Value='None'; Description='Remove explicit permission' }
    )
    if (-not $permission) { return }

    if (Confirm-Action `
        -Action ("Set GPO permission for '{0}' on '{1}' [{2}]" -f $principal.Identity, $gpo.DisplayName, $gpo.Id) `
        -Reason 'Modify GPO delegation/security filtering permissions.' `
        -Impact MEDIUM) {

        New-ChangeSet
        Set-GPPermission `
            -Guid $gpo.Id `
            -TargetName $principal.Identity `
            -TargetType $principal.TargetType `
            -PermissionLevel $permission `
            -Replace
    }
}

function Remove-GpoInteractive {
    Assert-DomainController
    Import-GroupPolicyModule

    $gpo = Select-GpoInteractive -Prompt 'Select GPO to delete'
    if (-not $gpo) { return }

    Write-Console 'A best-effort backup will be created before deletion.' Yellow
    $gpoBackupPath = Join-Path $script:RunPath 'gpo-backups'
    New-Item -ItemType Directory -Path $gpoBackupPath -Force | Out-Null

    $previousProgress = $ProgressPreference
    try {
        $ProgressPreference = 'SilentlyContinue'
        Backup-GPO -Guid $gpo.Id -Path $gpoBackupPath -ErrorAction SilentlyContinue | Out-Null
    }
    finally {
        $ProgressPreference = $previousProgress
    }

    if (Confirm-Action `
        -Action ("PERMANENTLY delete GPO '{0}' [{1}]" -f $gpo.DisplayName, $gpo.Id) `
        -Reason 'Delete the Group Policy Object after creating a best-effort backup.' `
        -Impact HIGH) {

        New-ChangeSet
        Remove-GPO -Guid $gpo.Id -Confirm:$false
    }
}

function Export-GpoReportInteractive {
    Assert-DomainController
    Import-GroupPolicyModule

    $gpo = Select-GpoInteractive -Prompt 'Select GPO for HTML report'
    if (-not $gpo) { return }

    $safe = ($gpo.DisplayName -replace '[^A-Za-z0-9._-]', '_')
    $path = Join-Path $script:RunPath ("gpo-{0}.html" -f $safe)

    $previousProgress = $ProgressPreference
    try {
        $ProgressPreference = 'SilentlyContinue'
        Get-GPOReport -Guid $gpo.Id -ReportType Html -Path $path
    }
    finally {
        $ProgressPreference = $previousProgress
    }

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

    $zone = Select-DnsZoneName
    if (-not $zone) { return }
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

    $zone = Select-DnsZoneName
    if (-not $zone) { return }
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

    $zone = Select-DnsZoneName
    if (-not $zone) { return }

    $record = Select-DnsRecordInteractive -ZoneName $zone
    if (-not $record) { return }

    $record | Format-List HostName,RecordType,TimeToLive,Timestamp,RecordData

    if (Confirm-Action `
        -Action ("Delete DNS record {0} [{1}] from {2}" -f $record.HostName, $record.RecordType, $zone) `
        -Reason 'Delete the selected DNS resource record.' `
        -Impact HIGH) {

        New-ChangeSet
        $record | Remove-DnsServerResourceRecord -ZoneName $zone -Force
    }
}

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
# Domain migration center
# ===========================================================================

function Get-MigrationRoot {
    $path = Join-Path $ExportPath 'migration'
    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
    return $path
}

function Get-MigrationPlanPath {
    return (Join-Path (Get-MigrationRoot) 'migration-plan.json')
}

function Show-MigrationPlan {
    $path = Get-MigrationPlanPath
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Console 'No migration plan has been saved yet.' Yellow
        return
    }

    $plan = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    Write-Section 'Domain migration plan'
    Write-Console ('  Type          : {0}' -f $plan.Type)
    Write-Console ('  Source domain : {0}' -f $plan.SourceDomain)
    Write-Console ('  Target domain : {0}' -f $plan.TargetDomain)
    Write-Console ('  Target NetBIOS: {0}' -f $plan.TargetNetBIOS)
    Write-Console ('  Notes         : {0}' -f $plan.Notes)
    Write-Console ('  Updated       : {0}' -f $plan.UpdatedAt)

    switch ($plan.Type) {
        'BrandingOnly' {
            Write-Console '  AD membership normally remains unchanged for web/mail/public-brand changes.' Gray
        }
        'DcReplacement' {
            Write-Console '  Member computers stay in the same AD domain; migrate DC/DNS/FSMO services instead.' Gray
        }
        'DomainMigration' {
            Write-Console '  Member computers need migration/rejoin to establish a secure channel with the target domain.' Yellow
        }
        'NewForest' {
            Write-Console '  Treat the destination as a separate forest and migrate in controlled batches.' Yellow
        }
        'DomainRenameAssessment' {
            Write-Console '  Domain rename is an advanced change and is not performed automatically by this assistant.' Red
        }
    }
}

function Invoke-MigrationAssessment {
    Write-MenuHeader 'MIGRATION ASSESSMENT' 'Classify the business request before changing Active Directory identity'

    $source = if ($script:DomainInfo) { [string]$script:DomainInfo.DNSRoot } else { [string]$script:ServerInfo.Domain }
    Write-Console ('  Current domain : {0}' -f $source)
    Write-Console ''
    Write-MenuItem '1' 'Branding / mail / web only' 'Keep AD domain identity; change public names/services'
    Write-MenuItem '2' 'Replace Domain Controller' 'Keep domain; add/replace DC infrastructure'
    Write-MenuItem '3' 'Migrate to new AD domain' 'Coexistence/trust + identity/client migration' Warn
    Write-MenuItem '4' 'New forest migration' 'Build a separate forest and migrate in phases' Warn
    Write-MenuItem '5' 'AD domain rename assessment' 'Advanced assessment only; no automatic rendom execution' Danger
    Write-MenuNavigation
    Write-Rule

    $choice = Read-MenuChoice -Default '1'
    if ($choice -eq 'H') { $script:MainMenuRequested = $true; return }
    if ($choice -eq '0') { return }

    $type = ''
    $target = ''
    $netbios = ''
    $notes = ''

    switch ($choice) {
        '1' {
            $type = 'BrandingOnly'
            $notes = Read-Host 'Public/company naming note'
        }
        '2' {
            $type = 'DcReplacement'
            $target = $source
            if ($script:DomainInfo) { $netbios = [string]$script:DomainInfo.NetBIOSName }
            $notes = 'Domain identity remains unchanged'
        }
        '3' {
            $type = 'DomainMigration'
            $target = (Read-Host 'Target AD DNS domain').Trim()
            $netbios = (Read-Host 'Target NetBIOS domain').Trim().ToUpperInvariant()
            $notes = 'Coexistence and client rejoin required'
        }
        '4' {
            $type = 'NewForest'
            $target = (Read-Host 'Target forest root DNS domain').Trim()
            $netbios = (Read-Host 'Target NetBIOS domain').Trim().ToUpperInvariant()
            $notes = 'Separate forest migration'
        }
        '5' {
            $type = 'DomainRenameAssessment'
            $target = (Read-Host 'Requested target AD DNS domain').Trim()
            $netbios = (Read-Host 'Requested target NetBIOS domain').Trim().ToUpperInvariant()
            $notes = 'Advanced domain rename assessment only'
        }
        default {
            Write-Console 'Invalid assessment option.' Yellow
            return
        }
    }

    if ($target -and $target -notmatch '^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$') {
        Write-Console 'Invalid target DNS domain syntax.' Red
        return
    }

    $plan = [pscustomobject]@{
        Type          = $type
        SourceDomain  = $source
        TargetDomain  = $target
        TargetNetBIOS = $netbios
        Notes         = $notes
        UpdatedAt     = Get-Date
    }
    $plan | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Get-MigrationPlanPath) -Encoding UTF8
    Write-Console ('Migration plan saved: {0}' -f (Get-MigrationPlanPath)) Green
    Show-MigrationPlan
}

function Export-DomainMigrationInventory {
    Assert-DomainController

    $root = Join-Path (Get-MigrationRoot) ('inventory-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Path $root -Force | Out-Null

    Get-ADDomain | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath (Join-Path $root 'domain.json') -Encoding UTF8
    Get-ADForest | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath (Join-Path $root 'forest.json') -Encoding UTF8

    Get-ADUser -Filter * -Properties Enabled,UserPrincipalName,Mail,LastLogonDate |
        Select-Object SamAccountName,UserPrincipalName,Mail,Enabled,LastLogonDate,DistinguishedName |
        Export-Csv -LiteralPath (Join-Path $root 'users.csv') -NoTypeInformation -Encoding UTF8

    Get-ADGroup -Filter * |
        Select-Object Name,SamAccountName,GroupScope,GroupCategory,DistinguishedName |
        Export-Csv -LiteralPath (Join-Path $root 'groups.csv') -NoTypeInformation -Encoding UTF8

    Get-ADComputer -Filter * -Properties Enabled,OperatingSystem,LastLogonDate,DNSHostName |
        Select-Object Name,DNSHostName,Enabled,OperatingSystem,LastLogonDate,DistinguishedName |
        Export-Csv -LiteralPath (Join-Path $root 'computers.csv') -NoTypeInformation -Encoding UTF8

    Get-ADOrganizationalUnit -Filter * -Properties ProtectedFromAccidentalDeletion |
        Select-Object Name,ProtectedFromAccidentalDeletion,DistinguishedName |
        Export-Csv -LiteralPath (Join-Path $root 'ous.csv') -NoTypeInformation -Encoding UTF8

    if (Test-Command 'Get-ADTrust') {
        Get-ADTrust -Filter * |
            Select-Object Name,Direction,TrustType,ForestTransitive,SelectiveAuthentication |
            Export-Csv -LiteralPath (Join-Path $root 'trusts.csv') -NoTypeInformation -Encoding UTF8
    }

    if (Test-Command 'Get-GPO') {
        Get-GPO -All |
            Select-Object DisplayName,Id,GpoStatus,CreationTime,ModificationTime |
            Export-Csv -LiteralPath (Join-Path $root 'gpos.csv') -NoTypeInformation -Encoding UTF8
    }

    if (Test-Command 'Get-DnsServerZone') {
        Get-DnsServerZone |
            Select-Object ZoneName,ZoneType,IsDsIntegrated,IsReverseLookupZone,DynamicUpdate |
            Export-Csv -LiteralPath (Join-Path $root 'dns-zones.csv') -NoTypeInformation -Encoding UTF8
    }

    [pscustomobject]@{
        Generated = Get-Date
        Domain = $script:DomainInfo.DNSRoot
        Forest = $script:ForestInfo.Name
        Users = @(Get-ADUser -Filter *).Count
        Groups = @(Get-ADGroup -Filter *).Count
        Computers = @(Get-ADComputer -Filter *).Count
        OUs = @(Get-ADOrganizationalUnit -Filter *).Count
        Output = $root
    } | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath (Join-Path $root 'summary.json') -Encoding UTF8

    Write-Console ('Migration inventory: {0}' -f $root) Green
}

function Show-ComputerMigrationReadiness {
    Assert-DomainController

    $computers = @(Get-ADComputer -Filter * -Properties DNSHostName,Enabled,LastLogonDate |
        Sort-Object Name)

    Write-Section 'Computer migration readiness'
    Write-Console ('  {0,-24} {1,-34} {2,-10} {3}' -f 'COMPUTER','DNS HOST','PING','LAST LOGON') Cyan

    foreach ($computer in $computers) {
        $target = if ($computer.DNSHostName) { $computer.DNSHostName } else { $computer.Name }
        $alive = $false
        try {
            $alive = Test-Connection -ComputerName $target -Count 1 -Quiet -ErrorAction SilentlyContinue
        }
        catch {}

        Write-Console ('  {0,-24} {1,-34} {2,-10} {3}' -f
            $computer.Name,
            $target,
            $(if ($alive) { 'ONLINE' } else { 'NO REPLY' }),
            $computer.LastLogonDate)
    }

    Write-Console ''
    Write-Console 'Ping is a readiness hint only. Firewall policy can block ICMP on otherwise healthy clients.' Gray
}

function Show-DomainTrusts {
    Assert-DomainController

    if (-not (Test-Command 'Get-ADTrust')) {
        Write-Console 'Get-ADTrust is unavailable.' Yellow
        return
    }

    Get-ADTrust -Filter * |
        Sort-Object Name |
        Select-Object Name,Direction,TrustType,ForestTransitive,SelectiveAuthentication,Source,Target |
        Format-Table -AutoSize
}

function Test-DomainTrustInteractive {
    Assert-DomainController

    $name = Select-AdTrustName
    if (-not $name) { return }

    try {
        $trust = Get-ADTrust -Identity $name -ErrorAction Stop
        $trust | Format-List Name,Direction,TrustType,ForestTransitive,SelectiveAuthentication,Source,Target
        Write-Console 'The trust object is readable. Validate authentication/resource access from both sides before migration.' Green
    }
    catch {
        Write-Console ("Trust lookup failed: {0}" -f $_.Exception.Message) Red
    }
}

function New-WindowsMigrationPackage {
    Assert-DomainController

    $planPath = Get-MigrationPlanPath
    if (-not (Test-Path -LiteralPath $planPath)) {
        Write-Console 'Run Migration assessment first.' Yellow
        return
    }

    $plan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
    if (-not $plan.TargetDomain) {
        Write-Console 'The saved migration plan does not define a target AD domain.' Yellow
        return
    }

    $dir = Join-Path (Get-MigrationRoot) ('windows-package-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null

    $scriptPath = Join-Path $dir 'Move-ToNewDomain.ps1'
    @"
[CmdletBinding()]
param(
    [string]`$TargetDomain = '$($plan.TargetDomain)',
    [string]`$TargetOU = '',
    [string]`$TargetDC = ''
)

`$ErrorActionPreference = 'Stop'
`$computer = Get-CimInstance Win32_ComputerSystem

Write-Host "Computer       : `$env:COMPUTERNAME"
Write-Host "Current domain : `$(`$computer.Domain)"
Write-Host "Target domain  : `$TargetDomain"

`$oldCredential = Get-Credential -Message 'Credential allowed to unjoin the current domain'
`$newCredential = Get-Credential -Message 'Credential delegated to join computers to the target domain'

`$params = @{
    DomainName = `$TargetDomain
    UnjoinDomainCredential = `$oldCredential
    Credential = `$newCredential
    Restart = `$true
    Force = `$true
    PassThru = `$true
}
if (`$TargetOU) { `$params.OUPath = `$TargetOU }
if (`$TargetDC) { `$params.Server = `$TargetDC }

Add-Computer @params
"@ | Set-Content -LiteralPath $scriptPath -Encoding UTF8

    $netdomPath = Join-Path $dir 'netdom-move-template.cmd'
    @"
@echo off
REM No passwords are stored. Replace TARGET-OUDN if required.
netdom move %COMPUTERNAME% /domain:$($plan.TargetDomain) /userd:* /passwordd:* /usero:* /passwordo:* /reboot:30
"@ | Set-Content -LiteralPath $netdomPath -Encoding ASCII

    @"
WINDOWS DOMAIN MIGRATION PACKAGE
================================
Source domain : $($plan.SourceDomain)
Target domain : $($plan.TargetDomain)

Move-ToNewDomain.ps1 uses Add-Computer and prompts for credentials at runtime.
No password is written into the generated files.

Run only after target-domain DNS/SRV discovery works and after testing on a
pilot OU/batch.
"@ | Set-Content -LiteralPath (Join-Path $dir 'README.txt') -Encoding UTF8

    Write-Console ("Windows migration package: {0}" -f $dir) Green
}

function Export-GpoMigrationSet {
    Assert-DomainController
    Import-GroupPolicyModule

    $dir = Join-Path (Get-MigrationRoot) ('gpo-backup-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null

    Backup-GPO -All -Path $dir | Out-Null
    Get-GPO -All |
        Select-Object DisplayName,Id,GpoStatus,CreationTime,ModificationTime |
        Export-Csv -LiteralPath (Join-Path $dir 'gpo-inventory.csv') -NoTypeInformation -Encoding UTF8

    Write-Console ("GPO migration backup set: {0}" -f $dir) Green
}

function Show-DomainRenameAssessment {
    Write-Section 'AD domain rename assessment'

    Write-Console 'A domain DNS-name change is not equivalent to changing a DNS alias.' Yellow
    Write-Console 'Clients, Kerberos/SPNs, applications, certificates, trusts and management systems require validation.'
    Write-Console ''

    if (Test-Command 'rendom.exe') {
        Write-Console 'rendom.exe: AVAILABLE on this server' Green
    }
    else {
        Write-Console 'rendom.exe: not detected' Yellow
    }

    Write-Console ''
    Write-Console 'This control plane deliberately does not execute rendom automatically.' Gray
    Write-Console 'For most business migrations, a parallel target domain/forest plus staged client migration is easier to test and roll back.' Gray
}

function Show-DomainMigrationMenu {
    Assert-DomainController

    while ($true) {
        if ($script:MainMenuRequested) { return }

        Write-MenuHeader 'DOMAIN MIGRATION CENTER' 'Assessment, inventory, coexistence evidence and credential-free client migration tooling'
        Write-MenuItem '1' 'Migration assessment' 'Classify branding, DC replacement, new domain/forest or rename'
        Write-MenuItem '2' 'Show migration plan' 'Display saved source/target intent'
        Write-MenuItem '3' 'Export source inventory' 'Users, groups, computers, OUs, GPOs, DNS and trusts'
        Write-MenuItem '4' 'Computer readiness' 'Current-domain computer DNS/ping readiness'
        Write-MenuItem '5' 'List trusts' 'Inventory configured domain/forest trusts'
        Write-MenuItem '6' 'Inspect trust' 'Read one trust and its direction/type'
        Write-MenuItem '7' 'Windows migration package' 'Generate Add-Computer/netdom templates without stored secrets' Good
        Write-MenuItem '8' 'GPO migration backup' 'Back up all GPOs plus inventory' Good
        Write-MenuItem '9' 'Domain rename assessment' 'Inspect advanced rename capability without executing it' Warn
        Write-MenuItem '10' 'System-state backup' 'Create recovery-grade DC backup before migration work'
        Write-MenuNavigation
        Write-Rule

        switch (Read-MenuChoice -Prompt 'Select migration module' -Default '1') {
            '1' { Invoke-MigrationAssessment; Pause-ControlPlane }
            '2' { Show-MigrationPlan; Pause-ControlPlane }
            '3' { Export-DomainMigrationInventory; Pause-ControlPlane }
            '4' { Show-ComputerMigrationReadiness; Pause-ControlPlane }
            '5' { Show-DomainTrusts; Pause-ControlPlane }
            '6' { Test-DomainTrustInteractive; Pause-ControlPlane }
            '7' { New-WindowsMigrationPackage; Pause-ControlPlane }
            '8' { Export-GpoMigrationSet; Pause-ControlPlane }
            '9' { Show-DomainRenameAssessment; Pause-ControlPlane }
            '10' { Invoke-SystemStateBackup; Pause-ControlPlane }
            'H' { $script:MainMenuRequested = $true; return }
            '0' { return }
            default { Write-Console 'Invalid option.' Yellow; Pause-ControlPlane }
        }
    }
}


# ===========================================================================
# Interactive menus
# ===========================================================================

function Show-UserMenu {
    while ($true) {
        if ($script:MainMenuRequested) { return }
        Write-MenuHeader 'USER DIRECTORY' 'Identity lifecycle, credentials, attributes and group membership'
        Write-MenuItem '1' 'List users' 'Inventory users, state and recent logon metadata'
        Write-MenuItem '2' 'Inspect user' 'Show detailed attributes for one identity'
        Write-MenuItem '3' 'Create user' 'Full user wizard + OU + password policy flags + groups' Good
        Write-MenuItem '4' 'Edit user' 'Identity fields, password behavior and account state'
        Write-MenuItem '5' 'Group memberships' 'List/add/remove groups with professional selectors' Good
        Write-MenuItem '6' 'Reset password' 'Administrative reset + change at next logon' Warn
        Write-MenuItem '7' 'Enable account' 'Restore authentication eligibility' Good
        Write-MenuItem '8' 'Disable account' 'Block authentication without deleting identity' Warn
        Write-MenuItem '9' 'Unlock account' 'Clear account lockout'
        Write-MenuItem '10' 'Delete user' 'Permanently remove directory object' Danger
        Write-MenuNavigation
        Write-Rule

        switch (Read-MenuChoice -Default '1') {
            '1' { Show-AdUsers; Pause-ControlPlane }
            '2' { Show-AdUserDetail; Pause-ControlPlane }
            '3' { New-AdUserInteractive; Pause-ControlPlane }
            '4' { Edit-AdUserInteractive; Pause-ControlPlane }
            '5' { Manage-AdUserGroupsInteractive; Pause-ControlPlane }
            '6' { Reset-AdUserPassword; Pause-ControlPlane }
            '7' { Set-AdUserEnabledState -Enabled $true; Pause-ControlPlane }
            '8' { Set-AdUserEnabledState -Enabled $false; Pause-ControlPlane }
            '9' { Unlock-AdUserInteractive; Pause-ControlPlane }
            '10' { Remove-AdUserInteractive; Pause-ControlPlane }
            'H' { $script:MainMenuRequested = $true; return }
            '0' { return }
            default { Write-Console 'Invalid option.' Yellow; Pause-ControlPlane }
        }
    }
}

function Show-GroupMenu {
    while ($true) {
        if ($script:MainMenuRequested) { return }
        Write-MenuHeader 'GROUPS & ACCESS' 'Security groups, membership and privileged access review'
        Write-MenuItem '1' 'List groups' 'Inventory domain groups'
        Write-MenuItem '2' 'List members' 'Inspect direct membership of one group'
        Write-MenuItem '3' 'Create group' 'Create security/distribution group' Good
        Write-MenuItem '4' 'Add member' 'Select group and user/group/computer principal' Good
        Write-MenuItem '5' 'Remove member' 'Select group then one current member' Warn
        Write-MenuItem '6' 'Privileged groups' 'Review Domain/Enterprise/Schema/Admin operators'
        Write-MenuItem '7' 'Delete group' 'Delete non-core group object' Danger
        Write-MenuNavigation
        Write-Rule

        switch (Read-MenuChoice -Default '1') {
            '1' { Show-AdGroups; Pause-ControlPlane }
            '2' { Show-AdGroupMembers; Pause-ControlPlane }
            '3' { New-AdGroupInteractive; Pause-ControlPlane }
            '4' { Add-AdGroupMemberInteractive; Pause-ControlPlane }
            '5' { Remove-AdGroupMemberInteractive; Pause-ControlPlane }
            '6' { Show-PrivilegedGroups; Pause-ControlPlane }
            '7' { Remove-AdGroupInteractive; Pause-ControlPlane }
            'H' { $script:MainMenuRequested = $true; return }
            '0' { return }
            default { Write-Console 'Invalid option.' Yellow; Pause-ControlPlane }
        }
    }
}

function Show-ComputerOuMenu {
    while ($true) {
        if ($script:MainMenuRequested) { return }
        Write-MenuHeader 'COMPUTERS & ORGANIZATIONAL UNITS' 'Machine accounts, OU structure and directory placement'
        Write-MenuItem '1' 'List computers' 'Inventory machine accounts and last-logon metadata'
        Write-MenuItem '2' 'Inspect computer' 'Select from indexed computer inventory and show attributes'
        Write-MenuItem '3' 'Enable computer' 'Restore machine authentication' Good
        Write-MenuItem '4' 'Disable computer' 'Disable stale/suspect machine account' Warn
        Write-MenuItem '5' 'Delete computer' 'Remove obsolete machine object' Danger
        Write-MenuItem '6' 'List OUs' 'Inventory organizational units and protection state'
        Write-MenuItem '7' 'Create OU' 'Create protected OU' Good
        Write-MenuItem '8' 'Move AD object' 'Move user/group/computer between OUs' Warn
        Write-MenuItem '9' 'Delete OU' 'Unprotect and delete empty OU' Danger
        Write-MenuNavigation
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
            'H' { $script:MainMenuRequested = $true; return }
            '0' { return }
            default { Write-Console 'Invalid option.' Yellow; Pause-ControlPlane }
        }
    }
}

function Show-GpoMenu {
    while ($true) {
        if ($script:MainMenuRequested) { return }
        Write-MenuHeader 'GROUP POLICY CONTROL' 'Selector-driven GPO lifecycle, common security templates, scope and delegation'
        Write-MenuItem '1' 'List GPOs + GUIDs' 'Indexed inventory; no manual GUID lookup required'
        Write-MenuItem '2' 'Inspect GPO' 'Select existing GPO by index or manual name/GUID'
        Write-MenuItem '3' 'Create empty GPO' 'Create a custom Group Policy Object' Good
        Write-MenuItem '4' 'Security GPO catalog' 'Deploy common curated security GPO templates' Good
        Write-MenuItem '5' 'Edit registry policy' 'Select GPO then set registry-based policy value' Warn
        Write-MenuItem '6' 'Link GPO' 'Select GPO and domain/OU target' Good
        Write-MenuItem '7' 'Remove link' 'Select GPO and domain/OU target' Warn
        Write-MenuItem '8' 'GPO permission' 'Select GPO and security principal' Warn
        Write-MenuItem '9' 'Backup GPO' 'Select and export one GPO'
        Write-MenuItem '10' 'HTML report' 'Select GPO and export human-readable report'
        Write-MenuItem '11' 'Delete GPO' 'Backup best-effort then permanently delete selected GPO' Danger
        Write-MenuNavigation
        Write-Rule

        switch (Read-MenuChoice -Default '1') {
            '1' { Show-Gpos; Pause-ControlPlane }
            '2' { Show-GpoDetail; Pause-ControlPlane }
            '3' { New-GpoInteractive; Pause-ControlPlane }
            '4' { Invoke-SecurityGpoWizard; Pause-ControlPlane }
            '5' { Set-GpoRegistryValueInteractive; Pause-ControlPlane }
            '6' { Link-GpoInteractive; Pause-ControlPlane }
            '7' { Unlink-GpoInteractive; Pause-ControlPlane }
            '8' { Set-GpoPermissionInteractive; Pause-ControlPlane }
            '9' { Backup-GpoInteractive; Pause-ControlPlane }
            '10' { Export-GpoReportInteractive; Pause-ControlPlane }
            '11' { Remove-GpoInteractive; Pause-ControlPlane }
            'H' { $script:MainMenuRequested = $true; return }
            '0' { return }
            default { Write-Console 'Invalid option.' Yellow; Pause-ControlPlane }
        }
    }
}

function Show-DnsMenu {
    while ($true) {
        if ($script:MainMenuRequested) { return }
        Write-MenuHeader 'ACTIVE DIRECTORY DNS' 'Integrated zones and resource-record lifecycle'
        Write-MenuItem '1' 'List zones' 'Inventory DNS zones and integration state'
        Write-MenuItem '2' 'List records' 'Display records in one zone/node'
        Write-MenuItem '3' 'Create A record' 'Add IPv4 host record' Good
        Write-MenuItem '4' 'Delete record' 'Delete one unambiguous resource record' Danger
        Write-MenuItem '5' 'AD DNS health' 'Validate locator and Kerberos SRV records'
        Write-MenuNavigation
        Write-Rule

        switch (Read-MenuChoice -Default '1') {
            '1' { Show-DnsZones; Pause-ControlPlane }
            '2' { Show-DnsRecords; Pause-ControlPlane }
            '3' { Add-DnsARecordInteractive; Pause-ControlPlane }
            '4' { Remove-DnsRecordInteractive; Pause-ControlPlane }
            '5' { $script:Results.Clear(); Test-DcDnsHealth; Pause-ControlPlane }
            'H' { $script:MainMenuRequested = $true; return }
            '0' { return }
            default { Write-Console 'Invalid option.' Yellow; Pause-ControlPlane }
        }
    }
}

function Show-DcHealthMenu {
    while ($true) {
        if ($script:MainMenuRequested) { return }
        Write-MenuHeader 'DC HEALTH & REPLICATION' 'Service state, DCDiag, DNS, SYSVOL, replication and FSMO ownership'
        Write-MenuItem '1' 'Full validation' 'Run all Domain Controller health checks' Good
        Write-MenuItem '2' 'DCDiag' 'Run dcdiag /q and persist failures'
        Write-MenuItem '3' 'Replication' 'PowerShell replication failures + repadmin summary'
        Write-MenuItem '4' 'DNS health' 'Validate AD locator/Kerberos SRV records'
        Write-MenuItem '5' 'SYSVOL / NETLOGON' 'Verify required SMB shares'
        Write-MenuItem '6' 'FSMO roles' 'Display forest/domain FSMO holders'
        Write-MenuNavigation
        Write-Rule

        switch (Read-MenuChoice -Default '1') {
            '1' { Invoke-DcValidation; Pause-ControlPlane }
            '2' { $script:Results.Clear(); Test-DcDiag; Pause-ControlPlane }
            '3' { $script:Results.Clear(); Test-ReplicationHealth; Pause-ControlPlane }
            '4' { $script:Results.Clear(); Test-DcDnsHealth; Pause-ControlPlane }
            '5' { $script:Results.Clear(); Test-SysvolNetlogonShares; Pause-ControlPlane }
            '6' { Show-FsmoRoles; Pause-ControlPlane }
            'H' { $script:MainMenuRequested = $true; return }
            '0' { return }
            default { Write-Console 'Invalid option.' Yellow; Pause-ControlPlane }
        }
    }
}

function Show-RecoveryMenu {
    while ($true) {
        if ($script:MainMenuRequested) { return }
        Write-MenuHeader 'BACKUP & RECOVERY' 'Configuration evidence, GPO backup and Domain Controller system-state protection'
        Write-MenuItem '1' 'Configuration change-set' 'Capture firewall, registry, SMB, Defender, AD/GPO/DNS evidence'
        Write-MenuItem '2' 'DC system-state backup' 'Use wbadmin for AD DS/SYSVOL recovery-grade backup' Good
        Write-MenuItem '3' 'GPO backup' 'Back up one Group Policy Object'
        Write-MenuItem '4' 'Open run directory' 'Print current run/backup paths'
        Write-MenuNavigation
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
            'H' { $script:MainMenuRequested = $true; return }
            '0' { return }
            default { Write-Console 'Invalid option.' Yellow; Pause-ControlPlane }
        }
    }
}

function Show-SecurityMenu {
    while ($true) {
        if ($script:MainMenuRequested) { return }
        Write-MenuHeader 'HOST SECURITY & HARDENING' 'Firewall, Defender, SMB, RDP, PowerShell logging and name-resolution controls'
        Write-MenuItem '1' 'Full host audit' 'Read-only selected security controls'
        Write-MenuItem '2' 'Interactive hardening' 'Propose supported remediations one by one' Good
        Write-MenuItem '3' 'Firewall only' 'Enable profiles and default inbound block' Warn
        Write-MenuItem '4' 'Defender only' 'Core protections + PUA where locally managed'
        Write-MenuItem '5' 'RDP NLA' 'Require Network Level Authentication'
        Write-MenuItem '6' 'SMB controls' 'Signing capability, guest logons, SMBv1 member-server handling'
        Write-MenuItem '7' 'LLMNR' 'Disable multicast name resolution' Warn
        Write-MenuItem '8' 'PowerShell logging' 'Script block + module logging'
        if ($script:IsDomainController) {
            Write-MenuItem '9' 'Directory protocol security' 'Kerberos AES/RC4, LDAP signing/channel binding and strict SMB' Good
        }
        Write-MenuNavigation
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
            '9' {
                if ($script:IsDomainController) { Show-DirectorySecurityMenu }
                else { Write-Console 'Directory protocol security requires a Domain Controller.' Yellow; Pause-ControlPlane }
            }
            'H' { $script:MainMenuRequested = $true; return }
            '0' { return }
            default { Write-Console 'Invalid option.' Yellow; Pause-ControlPlane }
        }
    }
}

function Show-AdOperationsMenu {
    Assert-DomainController

    while ($true) {
        if ($script:MainMenuRequested) { return }
        Write-MenuHeader 'ACTIVE DIRECTORY OPERATIONS' 'Daily directory administration without leaving PowerShell'
        Write-MenuItem '1' 'Users' 'Identity lifecycle, credentials and account state'
        Write-MenuItem '2' 'Groups & access' 'Memberships and privileged groups'
        Write-MenuItem '3' 'Computers & OUs' 'Machine accounts and organizational structure'
        Write-MenuItem '4' 'Group Policy' 'Create, edit, link, back up and delete GPOs'
        Write-MenuItem '5' 'AD DNS' 'Zones and resource records'
        Write-MenuItem '6' 'DC health' 'DCDiag, replication, DNS, SYSVOL and FSMO'
        Write-MenuItem '7' 'Backup & recovery' 'Change-set, GPO and system-state backup'
        Write-MenuItem '8' 'Host security' 'Role-aware server hardening'
        Write-MenuItem '9' 'Domain migration' 'Assessment, inventory, trusts and migration packages' Warn
        Write-MenuItem '10' 'Directory protocol security' 'Kerberos/LDAP/SMB security posture for the Domain Controller' Good
        Write-MenuNavigation
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
            '9' { Show-DomainMigrationMenu }
            '10' { Show-DirectorySecurityMenu }
            'H' { $script:MainMenuRequested = $true; return }
            '0' { return }
            default { Write-Console 'Invalid option.' Yellow; Pause-ControlPlane }
        }
    }
}

function Show-MainMenu {
    while ($true) {
        $script:MainMenuRequested = $false
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
        Write-MenuItem '8' 'Domain migration center' 'Assessment, inventory and client-migration tooling' Warn
        if ($script:IsDomainController) {
            Write-MenuItem '9' 'Directory protocol security' 'Kerberos AES/RC4, LDAP signing/channel binding and strict SMB' Good
        }
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
            '8' {
                if ($script:IsDomainController) { Show-DomainMigrationMenu }
                else { Write-Console 'Domain migration center requires a Domain Controller.' Yellow; Pause-ControlPlane }
            }
            '9' {
                if ($script:IsDomainController) { Show-DirectorySecurityMenu }
                else { Write-Console 'Directory protocol security requires a Domain Controller.' Yellow; Pause-ControlPlane }
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

        'Migration' {
            Show-DomainMigrationMenu
        }

        'DirectorySecurity' {
            if ($script:IsDomainController) {
                Show-DirectorySecurityMenu
            }
            else {
                throw 'DirectorySecurity mode requires a Domain Controller.'
            }
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

    if ($script:MainMenuRequested) {
        $script:MainMenuRequested = $false
        Show-MainMenu
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
