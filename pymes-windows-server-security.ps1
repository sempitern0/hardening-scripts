#requires -RunAsAdministrator
<#
.SYNOPSIS
    PyME Windows Server Security Assistant - v0.2.0

.DESCRIPTION
    Interactive security audit and hardening assistant for Windows Server.
    Designed for administrators working on existing infrastructure.

    PRINCIPLES:
      - Audit first; never silently change configuration.
      - Every remediation requires explicit confirmation.
      - Changes are logged.
      - Dangerous/role-sensitive changes are skipped or require an extra confirmation.
      - Produces a final summary and current server state.
      - Supports Windows Server 2019/2022/2025 as primary targets; role-aware auditing is preferred over blind hardening.

    Usage:
      .\PyME-WindowsServer-Security.ps1
      .\PyME-WindowsServer-Security.ps1 -AuditOnly
      .\PyME-WindowsServer-Security.ps1 -ExportPath C:\SecurityAudit
#>

[CmdletBinding()]
param(
    [switch]$AuditOnly,
    [string]$ExportPath = "$env:ProgramData\PyMESecurity",
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Global state
# ---------------------------------------------------------------------------

$script:Results = [System.Collections.Generic.List[object]]::new()
$script:Changes = [System.Collections.Generic.List[object]]::new()
$script:Warnings = [System.Collections.Generic.List[string]]::new()
$script:Started = Get-Date
$script:ComputerName = $env:COMPUTERNAME
$script:LogFile = $null
$script:ReportFile = $null

New-Item -ItemType Directory -Path $ExportPath -Force | Out-Null
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:LogFile = Join-Path $ExportPath "security-assistant-$timestamp.log"
$script:ReportFile = Join-Path $ExportPath "security-report-$timestamp.json"

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','OK','WARN','ERROR','CHANGE')][string]$Level = 'INFO'
    )

    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -LiteralPath $script:LogFile -Value $line

    switch ($Level) {
        'OK'     { Write-Host $line -ForegroundColor Green }
        'WARN'   { Write-Host $line -ForegroundColor Yellow }
        'ERROR'  { Write-Host $line -ForegroundColor Red }
        'CHANGE' { Write-Host $line -ForegroundColor Magenta }
        default  { Write-Host $line }
    }
}

function Write-Section {
    param([string]$Title)
    Write-Host ''
    Write-Host ('=' * 78) -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host ('=' * 78) -ForegroundColor Cyan
}

function Add-Result {
    param(
        [string]$Category,
        [string]$Control,
        [ValidateSet('PASS','WARN','FAIL','INFO','SKIP','ERROR')][string]$Status,
        [string]$Current,
        [string]$Expected,
        [string]$Remediation = ''
    )

    $script:Results.Add([pscustomobject]@{
        Category    = $Category
        Control     = $Control
        Status      = $Status
        Current     = $Current
        Expected    = $Expected
        Remediation = $Remediation
    })

    $symbol = switch ($Status) {
        'PASS'  { '[PASS]' }
        'WARN'  { '[WARN]' }
        'FAIL'  { '[FAIL]' }
        'ERROR' { '[ERR ]' }
        'SKIP'  { '[SKIP]' }
        default { '[INFO]' }
    }

    $color = switch ($Status) {
        'PASS'  { 'Green' }
        'WARN'  { 'Yellow' }
        'FAIL'  { 'Red' }
        'ERROR' { 'Red' }
        'SKIP'  { 'DarkYellow' }
        default { 'Gray' }
    }

    Write-Host ("{0,-7} {1,-28} {2}" -f $symbol, $Control, $Current) -ForegroundColor $color
}

function Confirm-Action {
    param(
        [Parameter(Mandatory)][string]$Action,
        [Parameter(Mandatory)][string]$Reason,
        [string]$Impact = 'Low'
    )

    if ($NonInteractive -or $AuditOnly) {
        return $false
    }

    Write-Host ''
    Write-Host "ACTION REQUIRES CONFIRMATION" -ForegroundColor Yellow
    Write-Host "  Action : $Action"
    Write-Host "  Reason : $Reason"
    Write-Host "  Impact : $Impact"

    do {
        $answer = (Read-Host 'Apply this change? [Y/N]').Trim().ToUpperInvariant()
    } while ($answer -notin @('Y','N'))

    return $answer -eq 'Y'
}

function Invoke-Change {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Reason,
        [Parameter(Mandatory)][scriptblock]$Action,
        [string]$Impact = 'Low'
    )

    if (-not (Confirm-Action -Action $Name -Reason $Reason -Impact $Impact)) {
        Write-Log "Skipped: $Name" 'WARN'
        $script:Changes.Add([pscustomobject]@{
            Time = Get-Date
            Name = $Name
            Status = 'SKIPPED'
            Reason = $Reason
            Error = ''
        })
        return $false
    }

    try {
        & $Action
        Write-Log "Applied: $Name" 'CHANGE'
        $script:Changes.Add([pscustomobject]@{
            Time = Get-Date
            Name = $Name
            Status = 'APPLIED'
            Reason = $Reason
            Error = ''
        })
        return $true
    }
    catch {
        Write-Log "Failed: $Name :: $($_.Exception.Message)" 'ERROR'
        $script:Changes.Add([pscustomobject]@{
            Time = Get-Date
            Name = $Name
            Status = 'FAILED'
            Reason = $Reason
            Error = $_.Exception.Message
        })
        return $false
    }
}

function Test-Cmdlet {
    param([string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-ServerInfo {
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem

    [pscustomobject]@{
        ComputerName = $env:COMPUTERNAME
        Domain       = $cs.Domain
        PartOfDomain = $cs.PartOfDomain
        Manufacturer = $cs.Manufacturer
        Model        = $cs.Model
        OS           = $os.Caption
        Version      = $os.Version
        Build        = $os.BuildNumber
        InstallDate  = $os.InstallDate
        LastBoot     = $os.LastBootUpTime
        Architecture = $os.OSArchitecture
    }
}

function Test-IsDomainController {
    try {
        $cs = Get-CimInstance Win32_ComputerSystem
        # DomainRole: 4 Backup DC, 5 Primary DC
        return $cs.DomainRole -in 4,5
    }
    catch {
        return $false
    }
}

function Get-FeatureStateSafe {
    param([string]$Name)

    if (-not (Test-Cmdlet 'Get-WindowsFeature')) {
        return $null
    }

    try {
        return (Get-WindowsFeature -Name $Name -ErrorAction Stop).InstallState
    }
    catch {
        return $null
    }
}

# ---------------------------------------------------------------------------
# Audit functions
# ---------------------------------------------------------------------------

function Audit-System {
    Write-Section 'SYSTEM / ROLE'

    $info = Get-ServerInfo
    Write-Log "Server: $($info.ComputerName) | $($info.OS) | build $($info.Build)"
    Write-Log "Domain: $($info.Domain) | Domain joined: $($info.PartOfDomain)"

    $isDC = Test-IsDomainController
    if ($isDC) {
        Write-Log 'This server is a Domain Controller. Role-sensitive changes will be restricted.' 'WARN'
    }

    Add-Result 'System' 'Operating System' 'INFO' "$($info.OS), build $($info.Build)" 'Supported Windows Server release' ''
    Add-Result 'System' 'Domain Controller role' ($(if ($isDC) {'WARN'} else {'INFO'})) `
        ($(if ($isDC) {'YES'} else {'NO'})) 'Know server role before hardening' 'Do not blindly apply member-server settings to DCs.'
}

function Audit-NetworkBasics {
    Write-Section 'NETWORK BASICS'

    try {
        $adapters = Get-NetIPConfiguration | Where-Object { $_.IPv4Address -and $_.NetAdapter.Status -eq 'Up' }
        foreach ($a in $adapters) {
            $ips = @($a.IPv4Address | ForEach-Object { $_.IPv4Address }) -join ', '
            $dns = @($a.DnsServer.ServerAddresses) -join ', '
            Add-Result 'Network' "Adapter $($a.InterfaceAlias)" 'INFO' `
                "IPv4=$ips; Gateway=$($a.IPv4DefaultGateway.NextHop); DNS=$dns" `
                'Documented expected network configuration' `
                'Do not expose server management or domain services beyond required networks.'
        }
    }
    catch {
        Add-Result 'Network' 'Network configuration' 'WARN' $_.Exception.Message 'Readable' ''
    }
}

function Audit-Firewall {
    Write-Section 'WINDOWS FIREWALL'

    if (-not (Test-Cmdlet 'Get-NetFirewallProfile')) {
        Add-Result 'Network' 'Firewall cmdlets' 'ERROR' 'Unavailable' 'Available' ''
        return
    }

    $profiles = Get-NetFirewallProfile
    foreach ($p in $profiles) {
        $status = if ($p.Enabled -and $p.DefaultInboundAction -eq 'Block') {'PASS'} else {'FAIL'}
        Add-Result 'Network' "Firewall $($p.Name)" $status `
            "Enabled=$($p.Enabled), Inbound=$($p.DefaultInboundAction), Outbound=$($p.DefaultOutboundAction)" `
            'Enabled + default inbound block' `
            'Enable profile and default inbound block.'
    }
}

function Audit-Defender {
    Write-Section 'MICROSOFT DEFENDER'

    if (-not (Test-Cmdlet 'Get-MpComputerStatus')) {
        Add-Result 'Endpoint' 'Microsoft Defender' 'WARN' 'Cmdlets unavailable' 'Available/managed' ''
        return
    }

    $d = Get-MpComputerStatus

    Add-Result 'Endpoint' 'Defender service' `
        ($(if ($d.AMServiceEnabled) {'PASS'} else {'FAIL'})) `
        "AMServiceEnabled=$($d.AMServiceEnabled)" 'True' ''

    Add-Result 'Endpoint' 'Realtime protection' `
        ($(if ($d.RealTimeProtectionEnabled) {'PASS'} else {'FAIL'})) `
        "RealTimeProtectionEnabled=$($d.RealTimeProtectionEnabled)" 'True' ''

    Add-Result 'Endpoint' 'Behavior monitoring' `
        ($(if ($d.BehaviorMonitorEnabled) {'PASS'} else {'FAIL'})) `
        "BehaviorMonitorEnabled=$($d.BehaviorMonitorEnabled)" 'True' ''

    Add-Result 'Endpoint' 'IOAV protection' `
        ($(if ($d.IOAVProtectionEnabled) {'PASS'} else {'FAIL'})) `
        "IOAVProtectionEnabled=$($d.IOAVProtectionEnabled)" 'True' ''

    Add-Result 'Endpoint' 'Tamper protection' `
        ($(if ($d.IsTamperProtected) {'PASS'} else {'WARN'})) `
        "IsTamperProtected=$($d.IsTamperProtected)" 'True' 'Prefer managed tamper protection.'

    try {
        $pref = Get-MpPreference
        Add-Result 'Endpoint' 'PUA protection' `
            ($(if ($pref.PUAProtection -eq 1) {'PASS'} else {'WARN'})) `
            "PUAProtection=$($pref.PUAProtection)" 'Enabled' 'Enable PUA protection.'
    }
    catch {
        Add-Result 'Endpoint' 'Defender preferences' 'ERROR' $_.Exception.Message 'Readable' ''
    }
}

function Audit-BitLocker {
    Write-Section 'BITLOCKER'

    if (-not (Test-Cmdlet 'Get-BitLockerVolume')) {
        Add-Result 'Storage' 'BitLocker cmdlets' 'WARN' 'Unavailable' 'Available' ''
        return
    }

    try {
        $volumes = Get-BitLockerVolume
        foreach ($v in $volumes) {
            $encrypted = $v.VolumeStatus -eq 'FullyEncrypted'
            $status = if ($encrypted) {'PASS'} else {'WARN'}
            Add-Result 'Storage' "BitLocker $($v.MountPoint)" $status `
                "Status=$($v.VolumeStatus), Method=$($v.EncryptionMethod)" `
                'FullyEncrypted' `
                'Configure BitLocker through GPO/MDM and escrow recovery keys.'
        }
    }
    catch {
        Add-Result 'Storage' 'BitLocker' 'ERROR' $_.Exception.Message 'Readable' ''
    }
}

function Audit-TPM {
    Write-Section 'TPM / SECURE BOOT'

    try {
        $tpm = Get-Tpm
        Add-Result 'Platform' 'TPM present' `
            ($(if ($tpm.TpmPresent) {'PASS'} else {'FAIL'})) `
            "Present=$($tpm.TpmPresent), Ready=$($tpm.TpmReady)" 'Present and ready' ''
    }
    catch {
        Add-Result 'Platform' 'TPM' 'WARN' $_.Exception.Message 'Available' ''
    }

    try {
        $secureBoot = Confirm-SecureBootUEFI -ErrorAction Stop
        Add-Result 'Platform' 'Secure Boot' `
            ($(if ($secureBoot) {'PASS'} else {'WARN'})) `
            "$secureBoot" 'True' 'Enable Secure Boot where hardware/role supports it.'
    }
    catch {
        Add-Result 'Platform' 'Secure Boot' 'WARN' 'Not available/legacy boot/unsupported' 'True on supported hardware' ''
    }
}

function Audit-SMB {
    Write-Section 'SMB / LEGACY PROTOCOLS'

    if (Test-Cmdlet 'Get-WindowsOptionalFeature') {
        try {
            $smb1 = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol
            Add-Result 'Network' 'SMBv1' `
                ($(if ($smb1.State -eq 'Disabled') {'PASS'} else {'FAIL'})) `
                "State=$($smb1.State)" 'Disabled' 'Disable SMBv1 after compatibility testing.'
        }
        catch {
            Add-Result 'Network' 'SMBv1' 'INFO' 'Feature query unavailable' 'Disabled' ''
        }
    }

    if (Test-Cmdlet 'Get-SmbServerConfiguration') {
        try {
            $smb = Get-SmbServerConfiguration
            Add-Result 'Network' 'SMB signing' `
                ($(if ($smb.EnableSecuritySignature) {'PASS'} else {'WARN'})) `
                "EnableSecuritySignature=$($smb.EnableSecuritySignature), RequireSecuritySignature=$($smb.RequireSecuritySignature)" `
                'Signing enabled; requirement according to environment policy' `
                'Enable/require SMB signing after compatibility testing.'

            Add-Result 'Network' 'SMB signing requirement' `
                ($(if ($smb.RequireSecuritySignature) {'PASS'} elseif ($smb.EnableSecuritySignature) {'WARN'} else {'FAIL'})) `
                "EnableSecuritySignature=$($smb.EnableSecuritySignature), RequireSecuritySignature=$($smb.RequireSecuritySignature)" `
                'Signing enabled; requirement according to environment policy' `
                'Require SMB signing when compatibility and performance requirements permit.'

            if (Test-Cmdlet 'Get-SmbClientConfiguration') {
                $clientSmb = Get-SmbClientConfiguration
                Add-Result 'Network' 'SMB insecure guest logons' `
                    ($(if (-not $clientSmb.EnableInsecureGuestLogons) {'PASS'} else {'WARN'})) `
                    "EnableInsecureGuestLogons=$($clientSmb.EnableInsecureGuestLogons)" `
                    'False' `
                    'Disable insecure guest logons unless a documented legacy dependency exists.'
            }
        }
        catch {
            Add-Result 'Network' 'SMB configuration' 'ERROR' $_.Exception.Message 'Readable' ''
        }
    }
}

function Audit-RDP {
    Write-Section 'REMOTE DESKTOP'

    try {
        $ts = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
        $rdpEnabled = $ts.fDenyTSConnections -eq 0

        $nla = Get-ItemProperty `
            'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' `
            -ErrorAction Stop

        Add-Result 'Remote Access' 'RDP enabled' 'INFO' `
            "Enabled=$rdpEnabled" 'Documented and restricted' `
            'Do not expose RDP directly to Internet; prefer VPN/jump host.'

        Add-Result 'Remote Access' 'RDP NLA' `
            ($(if ($nla.UserAuthentication -eq 1) {'PASS'} else {'FAIL'})) `
            "UserAuthentication=$($nla.UserAuthentication)" '1' 'Enable Network Level Authentication.'
    }
    catch {
        Add-Result 'Remote Access' 'RDP configuration' 'ERROR' $_.Exception.Message 'Readable' ''
    }
}

function Audit-LocalAdmins {
    Write-Section 'LOCAL ADMINISTRATORS'

    try {
        $adminGroup = Get-LocalGroup | Where-Object { $_.SID -eq 'S-1-5-32-544' } | Select-Object -First 1
        if (-not $adminGroup) {
            throw 'Could not resolve the local Administrators group by well-known SID S-1-5-32-544.'
        }
        $members = @(Get-LocalGroupMember -SID $adminGroup.SID)
        foreach ($m in $members) {
            Write-Host "  $($m.Name) [$($m.ObjectClass)]"
        }

        $unexpected = @($members | Where-Object {
            $_.Name -notmatch '\\(Administrator|Domain Admins|Administrators)$'
        })

        if ($unexpected.Count -gt 0) {
            Add-Result 'Identity' 'Local Administrators' 'WARN' `
                "$($members.Count) members; review required" `
                'Minimum necessary membership' `
                'Remove unnecessary local administrator access.'
        }
        else {
            Add-Result 'Identity' 'Local Administrators' 'PASS' `
                "$($members.Count) members; no obvious unexpected entries" `
                'Minimum necessary membership' ''
        }
    }
    catch {
        Add-Result 'Identity' 'Local Administrators' 'ERROR' $_.Exception.Message 'Readable' ''
    }
}

function Audit-LAPS {
    Write-Section 'WINDOWS LAPS'

    if (Test-Cmdlet 'Get-LapsAADPasswordPolicy') {
        try {
            $policy = Get-LapsAADPasswordPolicy -ErrorAction Stop
            Add-Result 'Identity' 'Windows LAPS (Entra) capability' 'INFO' 'Cmdlets and policy query available' 'Policy configured and enforced' 'Capability check only; verify actual policy and password rotation separately.'
        }
        catch {
            Add-Result 'Identity' 'Windows LAPS' 'WARN' 'Cmdlets available but policy not readable' 'Managed LAPS' ''
        }
    }
    elseif (Test-Cmdlet 'Get-LapsADPasswordPolicy') {
        try {
            $policy = Get-LapsADPasswordPolicy -ErrorAction Stop
            Add-Result 'Identity' 'Windows LAPS (AD) capability' 'INFO' 'Cmdlets and policy query available' 'Policy configured and enforced' 'Capability check only; verify actual policy and password rotation separately.'
        }
        catch {
            Add-Result 'Identity' 'Windows LAPS' 'WARN' 'LAPS cmdlets available but policy not readable' 'Managed LAPS' ''
        }
    }
    else {
        Add-Result 'Identity' 'Windows LAPS' 'WARN' 'LAPS cmdlets unavailable' 'Windows LAPS where supported' `
            'Configure Windows LAPS through supported GPO/MDM/AD tooling.'
    }
}

function Audit-PowerShellLogging {
    Write-Section 'POWERSHELL LOGGING'

    $base = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell'

    $scriptBlock = Test-RegistryValue "$base\ScriptBlockLogging" 'EnableScriptBlockLogging'
    $module = Test-RegistryValue "$base\ModuleLogging" 'EnableModuleLogging'

    Add-Result 'Logging' 'PowerShell Script Block Logging' `
        ($(if ($scriptBlock) {'PASS'} else {'WARN'})) `
        ($(if ($scriptBlock) {'Enabled'} else {'Not detected'})) 'Enabled' `
        'Enable through GPO; validate log volume and SIEM ingestion.'

    Add-Result 'Logging' 'PowerShell Module Logging' `
        ($(if ($module) {'PASS'} else {'WARN'})) `
        ($(if ($module) {'Enabled'} else {'Not detected'})) 'Enabled' `
        'Enable through GPO; validate log volume and SIEM ingestion.'
}

function Test-RegistryValue {
    param(
        [string]$Path,
        [string]$Name
    )

    try {
        $v = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
        return [int]$v.$Name -eq 1
    }
    catch {
        return $false
    }
}

function Audit-LLMNR {
    Write-Section 'LEGACY NAME RESOLUTION'

    $path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'
    $disabled = Test-RegistryValue $path 'EnableMulticast'

    Add-Result 'Network' 'LLMNR' `
        ($(if ($disabled) {'PASS'} else {'WARN'})) `
        ($(if ($disabled) {'Disabled'} else {'Not explicitly disabled'})) `
        'Disabled' `
        'Disable LLMNR through GPO after validating legacy dependencies.'
}

function Audit-Updates {
    Write-Section 'UPDATES'

    try {
        $hotfixes = Get-HotFix | Sort-Object InstalledOn -Descending
        $latest = $hotfixes | Select-Object -First 1

        Add-Result 'Maintenance' 'Most recent installed hotfix' 'INFO' `
            ($(if ($latest) {"$($latest.HotFixID) - $($latest.InstalledOn)"} else {'No data'})) `
            'Evidence of current patching; not a compliance determination' `
            'Use your managed update platform for patch compliance; this assistant does not declare patch currency from Get-HotFix alone.'
    }
    catch {
        Add-Result 'Maintenance' 'Windows Update history' 'WARN' $_.Exception.Message 'Readable' ''
    }
}

# ---------------------------------------------------------------------------
# Remediation functions
# ---------------------------------------------------------------------------

function Remediate-Firewall {
    Invoke-Change `
        -Name 'Enable Windows Firewall on all profiles and block inbound by default' `
        -Reason 'Reduces unsolicited inbound network exposure.' `
        -Impact 'Medium' `
        -Action {
            Set-NetFirewallProfile `
                -Profile Domain,Private,Public `
                -Enabled True `
                -DefaultInboundAction Block
        } | Out-Null
}

function Remediate-Defender {
    Invoke-Change `
        -Name 'Enable core Microsoft Defender protections' `
        -Reason 'Ensures realtime, behavior and IOAV protection are enabled.' `
        -Impact 'Medium' `
        -Action {
            Set-MpPreference `
                -DisableRealtimeMonitoring $false `
                -DisableBehaviorMonitoring $false `
                -DisableIOAVProtection $false `
                -DisableScriptScanning $false
        } | Out-Null

    Invoke-Change `
        -Name 'Enable Microsoft Defender PUA protection' `
        -Reason 'Helps block potentially unwanted applications.' `
        -Impact 'Low/Medium' `
        -Action {
            Set-MpPreference -PUAProtection Enabled
        } | Out-Null
}

function Remediate-RDP-NLA {
    Invoke-Change `
        -Name 'Enable RDP Network Level Authentication' `
        -Reason 'Requires authentication before establishing the full RDP session.' `
        -Impact 'Medium' `
        -Action {
            Set-ItemProperty `
                -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' `
                -Name 'UserAuthentication' `
                -Type DWord `
                -Value 1
        } | Out-Null
}

function Remediate-SMB1 {
    if (Test-IsDomainController) {
        Write-Log 'SMBv1 remediation on a Domain Controller is role-sensitive; skipping automatic change.' 'WARN'
        return
    }

    Invoke-Change `
        -Name 'Disable SMBv1 on the server' `
        -Reason 'SMBv1 is obsolete and should be removed after compatibility validation.' `
        -Impact 'HIGH - may break legacy clients/applications; reboot may be required' `
        -Action {
            if (Test-Cmdlet 'Uninstall-WindowsFeature') {
                $feature = Get-WindowsFeature -Name 'FS-SMB1' -ErrorAction Stop
                if ($feature.InstallState -eq 'Installed') {
                    Uninstall-WindowsFeature -Name 'FS-SMB1' -Restart:$false | Out-Null
                }
            }
            elseif (Test-Cmdlet 'Disable-WindowsOptionalFeature') {
                Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart | Out-Null
            }
            else {
                throw 'No supported SMBv1 removal cmdlet is available.'
            }
        } | Out-Null
}

function Remediate-SMBSigning {
    Invoke-Change `
        -Name 'Enable SMB server signing' `
        -Reason 'Provides integrity protection for SMB traffic.' `
        -Impact 'Medium' `
        -Action {
            Set-SmbServerConfiguration -EnableSecuritySignature $true -Force
        } | Out-Null
}

function Remediate-SMBGuest {
    if (-not (Test-Cmdlet 'Set-SmbClientConfiguration')) {
        Write-Log 'Set-SmbClientConfiguration is unavailable; skipping insecure guest logon remediation.' 'WARN'
        return
    }

    Invoke-Change `
        -Name 'Disable insecure SMB guest logons on the SMB client' `
        -Reason 'Reduces anonymous/guest SMB exposure.' `
        -Impact 'Medium - may break legacy guest-only shares' `
        -Action {
            Set-SmbClientConfiguration -EnableInsecureGuestLogons $false -Force
        } | Out-Null
}

function Remediate-LLMNR {
    Invoke-Change `
        -Name 'Disable LLMNR through local policy registry setting' `
        -Reason 'Reduces legacy multicast name-resolution attack surface.' `
        -Impact 'Medium - may affect legacy environments' `
        -Action {
            $path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'
            New-Item -Path $path -Force | Out-Null
            New-ItemProperty `
                -Path $path `
                -Name 'EnableMulticast' `
                -PropertyType DWord `
                -Value 0 `
                -Force | Out-Null
        } | Out-Null
}

function Remediate-PowerShellLogging {
    Invoke-Change `
        -Name 'Enable PowerShell Script Block Logging' `
        -Reason 'Improves visibility into PowerShell execution.' `
        -Impact 'Low/Medium - increases event log volume' `
        -Action {
            $path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging'
            New-Item -Path $path -Force | Out-Null
            New-ItemProperty -Path $path -Name 'EnableScriptBlockLogging' `
                -PropertyType DWord -Value 1 -Force | Out-Null
        } | Out-Null

    Invoke-Change `
        -Name 'Enable PowerShell Module Logging' `
        -Reason 'Improves visibility into PowerShell module activity.' `
        -Impact 'Low/Medium - increases event log volume' `
        -Action {
            $path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging'
            New-Item -Path $path -Force | Out-Null
            New-ItemProperty -Path $path -Name 'EnableModuleLogging' `
                -PropertyType DWord -Value 1 -Force | Out-Null
        } | Out-Null
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

function Show-Summary {
    Write-Section 'FINAL SUMMARY'

    $counts = @{
        PASS  = @($script:Results | Where-Object Status -eq 'PASS').Count
        WARN  = @($script:Results | Where-Object Status -eq 'WARN').Count
        FAIL  = @($script:Results | Where-Object Status -eq 'FAIL').Count
        INFO  = @($script:Results | Where-Object Status -eq 'INFO').Count
        ERROR = @($script:Results | Where-Object Status -eq 'ERROR').Count
    }

    Write-Host ''
    Write-Host "PASS : $($counts.PASS)" -ForegroundColor Green
    Write-Host "WARN : $($counts.WARN)" -ForegroundColor Yellow
    Write-Host "FAIL : $($counts.FAIL)" -ForegroundColor Red
    Write-Host "INFO : $($counts.INFO)" -ForegroundColor Gray
    Write-Host "ERROR: $($counts.ERROR)" -ForegroundColor Red

    $applied = @($script:Changes | Where-Object Status -eq 'APPLIED').Count
    $skipped = @($script:Changes | Where-Object Status -eq 'SKIPPED').Count
    $failed  = @($script:Changes | Where-Object Status -eq 'FAILED').Count

    Write-Host ''
    Write-Host "Changes applied : $applied" -ForegroundColor Magenta
    Write-Host "Changes skipped : $skipped" -ForegroundColor Yellow
    Write-Host "Changes failed  : $failed" -ForegroundColor Red

    Write-Host ''
    Write-Host 'Priority findings:' -ForegroundColor Cyan

    $priority = $script:Results | Where-Object Status -in @('FAIL','WARN')
    if ($priority) {
        $priority | Select-Object Category, Control, Status, Current |
            Format-Table -AutoSize
    }
    else {
        Write-Host 'No WARN/FAIL findings were detected by this baseline.' -ForegroundColor Green
    }

    Write-Host ''
    Write-Host "Log    : $script:LogFile"
    Write-Host "Report : $script:ReportFile"

    $state = [pscustomobject]@{
        GeneratedAt = Get-Date
        Server      = Get-ServerInfo
        IsDC        = Test-IsDomainController
        Results     = $script:Results
        Changes     = $script:Changes
    }

    $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:ReportFile -Encoding UTF8
}

function Show-Menu {
    Write-Host ''
    Write-Host 'Select an action:' -ForegroundColor Cyan
    Write-Host '  [1] Run audit only'
    Write-Host '  [2] Audit + interactive hardening'
    Write-Host '  [3] Show current findings'
    Write-Host '  [4] Exit'
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

try {
    Clear-Host
    Write-Section 'PyME Windows Server Security Assistant v0.2.0'

    Write-Log 'Starting security assessment.'
    Write-Log "Export directory: $ExportPath"

    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Administrator privileges are required.'
    }

    Audit-System
    Audit-NetworkBasics
    Audit-Firewall
    Audit-Defender
    Audit-BitLocker
    Audit-TPM
    Audit-SMB
    Audit-RDP
    Audit-LocalAdmins
    Audit-LAPS
    Audit-PowerShellLogging
    Audit-LLMNR
    Audit-Updates

    if (-not $AuditOnly -and -not $NonInteractive) {
        Show-Menu
        $choice = Read-Host 'Choice'

        switch ($choice) {
            '1' {
                Write-Log 'Audit-only mode selected.'
            }

            '2' {
                Write-Section 'INTERACTIVE HARDENING'

                Remediate-Firewall
                Remediate-Defender
                Remediate-RDP-NLA
                Remediate-SMBSigning
                Remediate-SMBGuest
                Remediate-SMB1
                Remediate-LLMNR
                Remediate-PowerShellLogging

                Write-Log 'Hardening phase completed. Re-running audit.' 'INFO'

                # Clear findings so the final report reflects the current state.
                $script:Results.Clear()

                Audit-System
                Audit-NetworkBasics
                Audit-Firewall
                Audit-Defender
                Audit-BitLocker
                Audit-TPM
                Audit-SMB
                Audit-RDP
                Audit-LocalAdmins
                Audit-LAPS
                Audit-PowerShellLogging
                Audit-LLMNR
                Audit-Updates
            }

            '3' {
                $script:Results | Format-Table -AutoSize
            }

            default {
                Write-Log 'No hardening actions selected.'
            }
        }
    }

    Show-Summary
}
catch {
    Write-Log "FATAL: $($_.Exception.Message)" 'ERROR'
    throw
}
finally {
    Write-Log 'Security assistant finished.'
}
