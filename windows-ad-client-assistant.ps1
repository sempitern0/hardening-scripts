#requires -RunAsAdministrator
<#
.SYNOPSIS
    Windows AD Client Assistant - v1.0.0

.DESCRIPTION
    Reversible assistant for joining Windows clients/member servers to
    Active Directory.

    Core flow:
      detect -> snapshot -> DNS -> discover -> join -> validate
      leave  -> restore DNS/hostname -> reboot

    No password is stored.
    No third-party package manager or repository is required.

.NOTES
    Run from Windows PowerShell 5.1+ as Administrator.
#>

[CmdletBinding()]
param(
    [ValidateSet('Interactive','Audit','Join','Status','Leave','Restore')]
    [string]$Mode = 'Interactive',

    [string]$StateRoot = "$env:ProgramData\ADClientAssistant",

    [switch]$NoColor
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:ProductName = 'Windows AD Client Assistant'
$script:Version = '1.0.0'
$script:SnapshotRoot = Join-Path $StateRoot 'snapshots'
$script:CurrentState = Join-Path $StateRoot 'current.json'
$script:LogRoot = Join-Path $StateRoot 'logs'
$script:RunId = '{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $PID
$script:LogFile = Join-Path $script:LogRoot ("client-assistant-{0}.log" -f $script:RunId)
$script:UseColor = (-not $NoColor) -and (-not [Console]::IsOutputRedirected)

# ---------------------------------------------------------------------------
# UI / logging
# ---------------------------------------------------------------------------

function Initialize-Runtime {
    New-Item -ItemType Directory -Force -Path $StateRoot | Out-Null
    New-Item -ItemType Directory -Force -Path $script:SnapshotRoot | Out-Null
    New-Item -ItemType Directory -Force -Path $script:LogRoot | Out-Null

    New-Item -ItemType File -Force -Path $script:LogFile | Out-Null
}

function Write-Log {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [ValidateSet('INFO','OK','WARN','ERROR')]
        [string]$Level = 'INFO'
    )

    $line = '{0} [{1}] {2}' -f (Get-Date -Format o), $Level, $Message
    Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8
}

function Write-Ui {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Text,
        [ValidateSet('Default','Cyan','Green','Yellow','Red','Gray')]
        [string]$Color = 'Default',
        [switch]$NoNewline
    )

    $params = @{}
    if ($NoNewline) { $params.NoNewline = $true }

    if (-not $script:UseColor -or $Color -eq 'Default') {
        Write-Host $Text @params
        return
    }

    Write-Host $Text -ForegroundColor $Color @params
}

function Write-Info {
    param([string]$Text)
    Write-Ui '[INFO] ' Cyan -NoNewline
    Write-Ui $Text
    Write-Log $Text INFO
}

function Write-Ok {
    param([string]$Text)
    Write-Ui '[ OK ] ' Green -NoNewline
    Write-Ui $Text
    Write-Log $Text OK
}

function Write-Warn {
    param([string]$Text)
    Write-Ui '[WARN] ' Yellow -NoNewline
    Write-Ui $Text
    Write-Log $Text WARN
}

function Write-ErrorUi {
    param([string]$Text)
    Write-Ui '[ERROR] ' Red -NoNewline
    Write-Ui $Text
    Write-Log $Text ERROR
}

function Pause-Ui {
    [void](Read-Host 'Press Enter to continue')
}

function Read-Value {
    param(
        [Parameter(Mandatory=$true)][string]$Prompt,
        [string]$Default = ''
    )

    if ($Default) {
        $value = Read-Host ("{0} [{1}]" -f $Prompt, $Default)
        if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
        return $value.Trim()
    }

    return (Read-Host $Prompt).Trim()
}

function Confirm-Choice {
    param(
        [Parameter(Mandatory=$true)][string]$Prompt,
        [ValidateSet('Y','N')][string]$Default = 'N'
    )

    $answer = Read-Host ("{0} [{1}]" -f $Prompt, $Default)
    if ([string]::IsNullOrWhiteSpace($answer)) { $answer = $Default }

    return ($answer -match '^(?i:y|yes|s|si|sí)$')
}

function Confirm-Literal {
    param(
        [Parameter(Mandatory=$true)][string]$Prompt,
        [Parameter(Mandatory=$true)][string]$Literal
    )

    Write-Ui $Prompt Yellow
    $answer = Read-Host ("Type {0} to continue" -f $Literal)
    return ($answer -ceq $Literal)
}

function Write-Header {
    Clear-Host
    Write-Ui $script:ProductName Cyan
    Write-Ui ("Version : {0}" -f $script:Version) Gray
    Write-Ui ("Computer: {0}" -f $env:COMPUTERNAME) Gray

    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $membership = if ($cs.PartOfDomain) { $cs.Domain } else { $cs.Workgroup }
        Write-Ui ("Identity: {0}" -f $membership) Gray
    }
    catch {
        Write-Ui 'Identity: unavailable' Gray
    }

    Write-Ui ('-' * 76) Gray
    Write-Ui ''
}

# ---------------------------------------------------------------------------
# Host / network discovery
# ---------------------------------------------------------------------------

function Get-ProductInfo {
    $cv = Get-ItemProperty `
        -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' `
        -ErrorAction Stop

    [pscustomobject]@{
        ProductName = [string]$cv.ProductName
        EditionID   = [string]$cv.EditionID
    }
}

function Test-DomainJoinEdition {
    $info = Get-ProductInfo

    if ($info.ProductName -match '(?i)\bHome\b' -or
        $info.EditionID -match '(?i)^Core') {
        Write-ErrorUi ("Windows edition does not support classic AD domain join: {0} / {1}" -f `
            $info.ProductName, $info.EditionID)
        return $false
    }

    return $true
}

function Get-NetworkCandidates {
    $configs = @(Get-NetIPConfiguration -ErrorAction Stop |
        Where-Object {
            $_.NetAdapter -and
            $_.NetAdapter.Status -eq 'Up' -and
            $_.IPv4Address
        })

    return @($configs | Sort-Object `
        @{ Expression = { if ($_.IPv4DefaultGateway) { 0 } else { 1 } } }, `
        InterfaceAlias)
}

function Select-NetworkInterface {
    $items = @(Get-NetworkCandidates)

    if ($items.Count -eq 0) {
        throw 'No active IPv4 network interface was detected.'
    }

    Write-Ui ''
    Write-Ui 'NETWORK INTERFACES' Cyan

    for ($i = 0; $i -lt $items.Count; $i++) {
        $cfg = $items[$i]
        $ips = @($cfg.IPv4Address | ForEach-Object { $_.IPAddress }) -join ','
        $gw = if ($cfg.IPv4DefaultGateway) {
            @($cfg.IPv4DefaultGateway | ForEach-Object { $_.NextHop }) -join ','
        }
        else {
            '-'
        }

        Write-Ui ("  [{0}] {1,-24} IPv4={2,-18} GW={3}" -f `
            ($i + 1), $cfg.InterfaceAlias, $ips, $gw)
    }

    Write-Ui '  [M] Enter interface index manually'

    $choice = Read-Value -Prompt 'Select interface' -Default '1'

    if ($choice -match '^(?i)m$') {
        $idxRaw = Read-Value -Prompt 'InterfaceIndex' -Default ''
        [uint32]$idx = 0
        if (-not [uint32]::TryParse($idxRaw, [ref]$idx)) {
            throw 'Invalid InterfaceIndex.'
        }

        return Get-NetIPConfiguration -InterfaceIndex $idx -ErrorAction Stop
    }

    [int]$number = 0
    if (-not [int]::TryParse($choice, [ref]$number) -or
        $number -lt 1 -or
        $number -gt $items.Count) {
        throw 'Invalid interface selection.'
    }

    return $items[$number - 1]
}

function Get-InterfaceDnsState {
    param([Parameter(Mandatory=$true)][uint32]$InterfaceIndex)

    $adapter = Get-NetAdapter -InterfaceIndex $InterfaceIndex -ErrorAction Stop
    $dns = Get-DnsClientServerAddress `
        -InterfaceIndex $InterfaceIndex `
        -AddressFamily IPv4 `
        -ErrorAction Stop

    $guidText = [string]$adapter.InterfaceGuid
    if (-not $guidText.StartsWith('{')) {
        $guidText = '{' + $guidText.Trim('{}') + '}'
    }

    $regPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\{0}' -f $guidText
    $nameServer = ''
    $dhcpNameServer = ''

    try {
        $props = Get-ItemProperty -LiteralPath $regPath -ErrorAction Stop
        $nameServer = [string]$props.NameServer
        $dhcpNameServer = [string]$props.DhcpNameServer
    }
    catch {}

    [pscustomobject]@{
        InterfaceIndex   = $InterfaceIndex
        InterfaceAlias   = [string]$adapter.Name
        InterfaceGuid    = $guidText
        ServerAddresses  = @($dns.ServerAddresses)
        DnsWasStatic     = -not [string]::IsNullOrWhiteSpace($nameServer)
        StaticNameServer = $nameServer
        DhcpNameServer   = $dhcpNameServer
    }
}

function Test-IpAddressList {
    param([Parameter(Mandatory=$true)][string[]]$Addresses)

    if ($Addresses.Count -eq 0) { return $false }

    foreach ($address in $Addresses) {
        $parsed = $null
        if (-not [System.Net.IPAddress]::TryParse($address, [ref]$parsed)) {
            return $false
        }
    }

    return $true
}

function Parse-DnsInput {
    param([Parameter(Mandatory=$true)][string]$Text)

    return @(
        $Text -split '[,;\s]+' |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { $_.Trim() }
    )
}

function Test-RemoteSession {
    $sender = Get-Variable -Name PSSenderInfo -ErrorAction SilentlyContinue
    if ($env:SESSIONNAME -match '^(?i)RDP-' -or $sender) {
        return $true
    }
    return $false
}

# ---------------------------------------------------------------------------
# Snapshot / persistence
# ---------------------------------------------------------------------------

function New-PreJoinSnapshot {
    param(
        [Parameter(Mandatory=$true)]$Interface,
        [Parameter(Mandatory=$true)][string]$TargetDomain
    )

    $snapshotPath = Join-Path $script:SnapshotRoot $script:RunId
    New-Item -ItemType Directory -Force -Path $snapshotPath | Out-Null

    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    $dnsState = Get-InterfaceDnsState -InterfaceIndex ([uint32]$Interface.InterfaceIndex)
    $product = Get-ProductInfo

    $snapshot = [ordered]@{
        SnapshotVersion = 1
        CreatedAt       = (Get-Date).ToString('o')
        SnapshotPath    = $snapshotPath
        TargetDomain    = $TargetDomain
        ComputerName    = [string]$env:COMPUTERNAME
        PartOfDomain    = [bool]$cs.PartOfDomain
        Domain          = [string]$cs.Domain
        Workgroup       = [string]$cs.Workgroup
        ProductName     = $product.ProductName
        EditionID       = $product.EditionID
        Interface       = $dnsState
    }

    $snapshotFile = Join-Path $snapshotPath 'snapshot.json'
    $snapshot |
        ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $snapshotFile -Encoding UTF8

    Write-Ok ("Pre-join snapshot created: {0}" -f $snapshotPath)
    return $snapshot
}

function Save-CurrentState {
    param(
        [Parameter(Mandatory=$true)]$Snapshot,
        [Parameter(Mandatory=$true)][string]$Domain,
        [Parameter(Mandatory=$true)][string[]]$DnsServers,
        [Parameter(Mandatory=$true)][string]$RequestedComputerName
    )

    $state = [ordered]@{
        StateVersion          = 1
        JoinedAt              = (Get-Date).ToString('o')
        Domain                = $Domain
        DnsServers            = @($DnsServers)
        RequestedComputerName = $RequestedComputerName
        SnapshotPath          = [string]$Snapshot.SnapshotPath
        LeavePending          = $false
    }

    $state |
        ConvertTo-Json -Depth 6 |
        Set-Content -LiteralPath $script:CurrentState -Encoding UTF8
}

function Get-CurrentState {
    if (-not (Test-Path -LiteralPath $script:CurrentState)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $script:CurrentState -Raw -ErrorAction Stop |
            ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Warn ("Current state file is unreadable: {0}" -f $_.Exception.Message)
        return $null
    }
}

function Get-Snapshot {
    param([Parameter(Mandatory=$true)][string]$SnapshotPath)

    $file = Join-Path $SnapshotPath 'snapshot.json'
    if (-not (Test-Path -LiteralPath $file)) {
        throw "Snapshot metadata not found: $file"
    }

    return Get-Content -LiteralPath $file -Raw -ErrorAction Stop |
        ConvertFrom-Json -ErrorAction Stop
}

function Restore-DnsFromSnapshot {
    param([Parameter(Mandatory=$true)]$Snapshot)

    $iface = $Snapshot.Interface
    $index = [uint32]$iface.InterfaceIndex

    $adapter = Get-NetAdapter -InterfaceIndex $index -ErrorAction Stop
    Write-Info ("Restoring DNS on {0} (ifIndex {1})" -f $adapter.Name, $index)

    if ([bool]$iface.DnsWasStatic) {
        $old = @($iface.ServerAddresses)
        if ($old.Count -gt 0) {
            Set-DnsClientServerAddress `
                -InterfaceIndex $index `
                -ServerAddresses $old `
                -ErrorAction Stop
            Write-Ok ("Previous static DNS restored: {0}" -f ($old -join ', '))
        }
        else {
            Set-DnsClientServerAddress `
                -InterfaceIndex $index `
                -ResetServerAddresses `
                -ErrorAction Stop
            Write-Ok 'Previous DNS state reset to interface defaults.'
        }
    }
    else {
        Set-DnsClientServerAddress `
            -InterfaceIndex $index `
            -ResetServerAddresses `
            -ErrorAction Stop
        Write-Ok 'DNS returned to DHCP/default behavior.'
    }

    Clear-DnsClientCache -ErrorAction SilentlyContinue
}

function Restore-ComputerNameFromSnapshot {
    param([Parameter(Mandatory=$true)]$Snapshot)

    $oldName = [string]$Snapshot.ComputerName
    if ([string]::IsNullOrWhiteSpace($oldName)) { return $true }

    $current = [string]$env:COMPUTERNAME
    if ($current -ieq $oldName) {
        return $true
    }

    try {
        Rename-Computer -NewName $oldName -Force -ErrorAction Stop
        Write-Ok ("Computer name restoration scheduled: {0}" -f $oldName)
        return $true
    }
    catch {
        Write-Warn ("Computer name could not be restored yet: {0}" -f $_.Exception.Message)
        Write-Warn 'After leaving the domain and rebooting, run -Mode Restore again.'
        return $false
    }
}

# ---------------------------------------------------------------------------
# DNS / AD discovery
# ---------------------------------------------------------------------------

function Set-DomainDns {
    param(
        [Parameter(Mandatory=$true)][uint32]$InterfaceIndex,
        [Parameter(Mandatory=$true)][string[]]$DnsServers
    )

    if (Test-RemoteSession) {
        Write-Warn 'Remote/RDP session detected. DNS changes should preserve an existing IP session,'
        Write-Warn 'but incorrect DNS can prevent reconnecting by hostname.'
    }

    Set-DnsClientServerAddress `
        -InterfaceIndex $InterfaceIndex `
        -ServerAddresses $DnsServers `
        -ErrorAction Stop

    Clear-DnsClientCache -ErrorAction SilentlyContinue
    Write-Ok ("AD DNS configured: {0}" -f ($DnsServers -join ', '))
}

function Test-DomainDiscovery {
    param(
        [Parameter(Mandatory=$true)][string]$Domain,
        [Parameter(Mandatory=$true)][string[]]$DnsServers
    )

    $srvName = '_ldap._tcp.dc._msdcs.{0}' -f $Domain

    try {
        $direct = @(Resolve-DnsName `
            -Name $srvName `
            -Type SRV `
            -Server $DnsServers[0] `
            -DnsOnly `
            -ErrorAction Stop)

        if ($direct.Count -eq 0) { throw 'No direct SRV answer.' }
        Write-Ok ("Direct SRV discovery succeeded through {0}." -f $DnsServers[0])
    }
    catch {
        Write-ErrorUi ("Selected AD DNS did not return DC locator SRV records: {0}" -f `
            $_.Exception.Message)
        return $false
    }

    try {
        $system = @(Resolve-DnsName `
            -Name $srvName `
            -Type SRV `
            -DnsOnly `
            -ErrorAction Stop)

        if ($system.Count -eq 0) { throw 'No system resolver SRV answer.' }
        Write-Ok 'System resolver can discover Active Directory.'
    }
    catch {
        Write-ErrorUi ("System resolver cannot discover the AD domain: {0}" -f `
            $_.Exception.Message)
        return $false
    }

    if (Get-Command nltest.exe -ErrorAction SilentlyContinue) {
        $nltestOutput = & nltest.exe "/dsgetdc:$Domain" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Ok 'nltest located a domain controller.'
        }
        else {
            Write-Warn ("nltest DC locator returned exit code {0}." -f $LASTEXITCODE)
            $nltestOutput | ForEach-Object { Write-Ui ([string]$_) Gray }
        }
    }

    return $true
}

function Test-TimeState {
    if (-not (Get-Command w32tm.exe -ErrorAction SilentlyContinue)) {
        return
    }

    $status = & w32tm.exe /query /status 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Ok 'Windows Time status is available.'
        return
    }

    Write-Warn 'Windows Time is not currently reporting synchronized status.'
    Write-Warn 'Kerberos is sensitive to clock skew; verify time if authentication fails.'
}

# ---------------------------------------------------------------------------
# Join / status
# ---------------------------------------------------------------------------

function Invoke-ReadinessAudit {
    Write-Header
    Write-Ui 'CLIENT READINESS' Cyan
    Write-Ui ''

    $product = Get-ProductInfo
    Write-Ui ("Windows       : {0}" -f $product.ProductName)
    Write-Ui ("Edition ID    : {0}" -f $product.EditionID)

    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    Write-Ui ("PartOfDomain  : {0}" -f $cs.PartOfDomain)
    Write-Ui ("Domain/Group  : {0}" -f $(if ($cs.PartOfDomain) { $cs.Domain } else { $cs.Workgroup }))

    [void](Test-DomainJoinEdition)

    $interfaces = @(Get-NetworkCandidates)
    Write-Ui ''
    Write-Ui 'Active IPv4 interfaces:' Cyan
    foreach ($cfg in $interfaces) {
        $dns = @(Get-DnsClientServerAddress `
            -InterfaceIndex $cfg.InterfaceIndex `
            -AddressFamily IPv4 `
            -ErrorAction SilentlyContinue).ServerAddresses

        Write-Ui ("  {0} / ifIndex {1} / DNS {2}" -f `
            $cfg.InterfaceAlias,
            $cfg.InterfaceIndex,
            ($dns -join ', '))
    }

    Test-TimeState

    $state = Get-CurrentState
    if ($state) {
        Write-Ok ("Assistant-managed state exists for domain {0}." -f $state.Domain)
    }
    else {
        Write-Info 'No assistant-managed join state exists.'
    }
}

function Invoke-GuidedJoin {
    Write-Header
    Write-Ui 'GUIDED DOMAIN JOIN' Cyan
    Write-Ui ''

    if (-not (Test-DomainJoinEdition)) { return }

    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    if ($cs.PartOfDomain) {
        Write-Warn ("This computer is already joined to: {0}" -f $cs.Domain)
        return
    }

    $iface = Select-NetworkInterface

    $domain = (Read-Value `
        -Prompt 'AD DNS domain (for example corp.example.com)' `
        -Default '').ToLowerInvariant()

    if ($domain -notmatch '^[A-Za-z0-9.-]+\.[A-Za-z]{2,}$') {
        Write-ErrorUi 'A valid DNS domain is required.'
        return
    }

    $dnsText = Read-Value `
        -Prompt 'AD DNS server IP addresses (comma separated)' `
        -Default ''

    $dnsServers = @(Parse-DnsInput -Text $dnsText)
    if (-not (Test-IpAddressList -Addresses $dnsServers)) {
        Write-ErrorUi 'At least one valid DNS server IP address is required.'
        return
    }

    $joinUser = Read-Value -Prompt 'Join account' -Default ("Administrator@{0}" -f $domain)
    $ouPath = Read-Value -Prompt 'Computer OU DN (optional)' -Default ''
    $requestedName = Read-Value `
        -Prompt 'Computer name' `
        -Default $env:COMPUTERNAME

    if ($requestedName -notmatch '^[A-Za-z0-9][A-Za-z0-9-]{0,14}$') {
        Write-ErrorUi 'Computer name must be 1-15 characters using letters, digits or hyphen.'
        return
    }

    Write-Ui ''
    Write-Ui 'Plan:' Cyan
    Write-Ui ("  Domain       : {0}" -f $domain)
    Write-Ui ("  Interface    : {0} / ifIndex {1}" -f `
        $iface.InterfaceAlias, $iface.InterfaceIndex)
    Write-Ui ("  DNS          : {0}" -f ($dnsServers -join ', '))
    Write-Ui ("  Computer     : {0}" -f $requestedName)
    Write-Ui ("  Join account : {0}" -f $joinUser)
    Write-Ui ("  OU           : {0}" -f $(if ($ouPath) { $ouPath } else { '(default container)' }))

    if (-not (Confirm-Choice -Prompt 'Create a reversible snapshot and continue?' -Default Y)) {
        return
    }

    $snapshot = New-PreJoinSnapshot -Interface $iface -TargetDomain $domain

    try {
        Set-DomainDns `
            -InterfaceIndex ([uint32]$iface.InterfaceIndex) `
            -DnsServers $dnsServers

        Test-TimeState

        if (-not (Test-DomainDiscovery -Domain $domain -DnsServers $dnsServers)) {
            throw 'AD discovery failed after applying the selected DNS configuration.'
        }

        Write-Ui ''
        Write-Info 'Domain credentials are requested by Windows Credential UI/PowerShell.'
        Write-Info 'The password is not stored by this assistant.'

        $credential = Get-Credential `
            -UserName $joinUser `
            -Message ("Credentials authorized to join {0}" -f $domain)

        if (-not $credential) {
            throw 'Credential prompt was cancelled.'
        }

        $params = @{
            DomainName  = $domain
            Credential  = $credential
            PassThru    = $true
            Force       = $true
            ErrorAction = 'Stop'
        }

        if ($ouPath) {
            $params.OUPath = $ouPath
        }

        if ($requestedName -ine $env:COMPUTERNAME) {
            $params.NewName = $requestedName
        }

        $result = Add-Computer @params

        if ($result -and
            $result.PSObject.Properties['HasSucceeded'] -and
            -not $result.HasSucceeded) {
            throw 'Add-Computer returned HasSucceeded=False.'
        }

        Save-CurrentState `
            -Snapshot $snapshot `
            -Domain $domain `
            -DnsServers $dnsServers `
            -RequestedComputerName $requestedName

        Write-Ok 'Windows accepted the domain join operation.'
        Write-Warn 'The join is not considered operationally complete until the reboot occurs.'

        if (Confirm-Choice -Prompt 'Restart now?' -Default N) {
            Restart-Computer -Force
        }
    }
    catch {
        Write-ErrorUi ("Domain join failed: {0}" -f $_.Exception.Message)
        Write-Warn 'Restoring the pre-join DNS state.'

        try {
            Restore-DnsFromSnapshot -Snapshot $snapshot
        }
        catch {
            Write-ErrorUi ("Automatic DNS rollback failed: {0}" -f $_.Exception.Message)
            Write-Warn ("Snapshot remains available at: {0}" -f $snapshot.SnapshotPath)
        }

        try {
            [void](Restore-ComputerNameFromSnapshot -Snapshot $snapshot)
        }
        catch {}

        Write-Warn 'No domain password was persisted.'
    }
}

function Invoke-Status {
    Write-Header
    Write-Ui 'DOMAIN CLIENT STATUS' Cyan
    Write-Ui ''

    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    Write-Ui ("Computer      : {0}" -f $env:COMPUTERNAME)
    Write-Ui ("PartOfDomain  : {0}" -f $cs.PartOfDomain)
    Write-Ui ("Domain/Group  : {0}" -f $(if ($cs.PartOfDomain) { $cs.Domain } else { $cs.Workgroup }))

    if ($cs.PartOfDomain) {
        try {
            $secure = Test-ComputerSecureChannel -ErrorAction Stop
            if ($secure) {
                Write-Ok 'Computer secure channel is healthy.'
            }
            else {
                Write-Warn 'Computer secure channel test returned False.'
            }
        }
        catch {
            Write-Warn ("Secure channel test failed: {0}" -f $_.Exception.Message)
        }

        if (Get-Command nltest.exe -ErrorAction SilentlyContinue) {
            & nltest.exe "/dsgetdc:$($cs.Domain)" 2>&1 |
                ForEach-Object { Write-Ui ([string]$_) Gray }
        }
    }

    $state = Get-CurrentState
    if ($state) {
        Write-Ui ''
        Write-Ui 'Assistant state:' Cyan
        Write-Ui ("  Domain   : {0}" -f $state.Domain)
        Write-Ui ("  DNS      : {0}" -f (@($state.DnsServers) -join ', '))
        Write-Ui ("  Snapshot : {0}" -f $state.SnapshotPath)
    }

    Test-TimeState
}

# ---------------------------------------------------------------------------
# Leave / restore
# ---------------------------------------------------------------------------

function Invoke-LeaveDomain {
    Write-Header
    Write-Ui 'LEAVE DOMAIN CLEANLY' Cyan
    Write-Ui ''

    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    if (-not $cs.PartOfDomain) {
        Write-Info 'This computer is not currently joined to a domain.'
        return
    }

    $state = Get-CurrentState
    $snapshot = $null
    if ($state -and $state.SnapshotPath) {
        try {
            $snapshot = Get-Snapshot -SnapshotPath ([string]$state.SnapshotPath)
        }
        catch {
            Write-Warn ("Recorded snapshot could not be loaded: {0}" -f $_.Exception.Message)
        }
    }

    $defaultWorkgroup = 'WORKGROUP'
    if ($snapshot -and $snapshot.Workgroup) {
        $defaultWorkgroup = [string]$snapshot.Workgroup
    }

    $unjoinUser = Read-Value `
        -Prompt 'Account authorized to remove this computer from AD' `
        -Default ("Administrator@{0}" -f $cs.Domain)

    $workgroup = Read-Value `
        -Prompt 'Workgroup after leaving the domain' `
        -Default $defaultWorkgroup

    if (-not (Confirm-Literal `
        -Prompt ("This computer will leave domain {0}." -f $cs.Domain) `
        -Literal 'LEAVE')) {
        return
    }

    $credential = Get-Credential `
        -UserName $unjoinUser `
        -Message ("Credentials authorized to unjoin from {0}" -f $cs.Domain)

    if (-not $credential) {
        Write-Warn 'Credential prompt cancelled.'
        return
    }

    try {
        $result = Remove-Computer `
            -UnjoinDomainCredential $credential `
            -WorkgroupName $workgroup `
            -PassThru `
            -Force `
            -ErrorAction Stop

        if ($result -and
            $result.PSObject.Properties['HasSucceeded'] -and
            -not $result.HasSucceeded) {
            throw 'Remove-Computer returned HasSucceeded=False.'
        }

        Write-Ok 'Windows accepted the domain leave operation.'

        if ($snapshot) {
            try {
                Restore-DnsFromSnapshot -Snapshot $snapshot
            }
            catch {
                Write-Warn ("DNS restore failed: {0}" -f $_.Exception.Message)
            }

            $nameRestored = Restore-ComputerNameFromSnapshot -Snapshot $snapshot

            if ($nameRestored) {
                Remove-Item -LiteralPath $script:CurrentState -Force -ErrorAction SilentlyContinue
            }
            else {
                Write-Warn 'Current state is retained so hostname restoration can be retried after reboot.'
            }
        }
        else {
            Write-Warn 'No assistant snapshot exists; local DNS/name state was not rewritten.'
        }

        Write-Warn 'A reboot is required to complete the domain leave.'

        if (Confirm-Choice -Prompt 'Restart now?' -Default N) {
            Restart-Computer -Force
        }
    }
    catch {
        Write-ErrorUi ("Domain leave failed: {0}" -f $_.Exception.Message)
        Write-Warn 'No forced registry/domain-membership manipulation was attempted.'
    }
}

function Invoke-RestorePreJoin {
    Write-Header
    Write-Ui 'RESTORE PRE-JOIN STATE' Cyan
    Write-Ui ''

    $state = Get-CurrentState
    if (-not $state) {
        Write-ErrorUi 'No assistant-managed current state exists.'
        return
    }

    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    if ($cs.PartOfDomain) {
        Write-ErrorUi ("This computer is still joined to {0}." -f $cs.Domain)
        Write-Warn 'Use Leave domain cleanly first.'
        Write-Warn 'The assistant will not fake a local unjoin by editing registry/NTDS-related state.'
        return
    }

    try {
        $snapshot = Get-Snapshot -SnapshotPath ([string]$state.SnapshotPath)
    }
    catch {
        Write-ErrorUi $_.Exception.Message
        return
    }

    try {
        Restore-DnsFromSnapshot -Snapshot $snapshot
        $nameRestored = Restore-ComputerNameFromSnapshot -Snapshot $snapshot

        if ($nameRestored) {
            Remove-Item -LiteralPath $script:CurrentState -Force -ErrorAction SilentlyContinue
            Write-Ok 'Pre-join state restored.'
        }
        else {
            Write-Warn 'DNS is restored; hostname restoration remains pending.'
        }

        if ($env:COMPUTERNAME -ine [string]$snapshot.ComputerName) {
            Write-Warn 'A reboot may be required for the restored computer name.'
        }
    }
    catch {
        Write-ErrorUi ("Restore failed: {0}" -f $_.Exception.Message)
    }
}

# ---------------------------------------------------------------------------
# Interactive menu
# ---------------------------------------------------------------------------

function Show-MainMenu {
    while ($true) {
        Write-Header
        Write-Ui 'CLIENT JOIN CONTROL PLANE' Cyan
        Write-Ui ''
        Write-Ui '  [1] Readiness audit'
        Write-Ui '  [2] Guided domain join'
        Write-Ui '  [3] Domain client status'
        Write-Ui '  [4] Leave domain cleanly'
        Write-Ui '  [5] Restore pre-join state'
        Write-Ui '  [0] Exit'
        Write-Ui ''

        $choice = Read-Value -Prompt 'Select operation' -Default '1'

        try {
            switch ($choice.ToUpperInvariant()) {
                '1' { Invoke-ReadinessAudit; Pause-Ui }
                '2' { Invoke-GuidedJoin; Pause-Ui }
                '3' { Invoke-Status; Pause-Ui }
                '4' { Invoke-LeaveDomain; Pause-Ui }
                '5' { Invoke-RestorePreJoin; Pause-Ui }
                '0' { return }
                default {
                    Write-Warn 'Unknown option.'
                    Pause-Ui
                }
            }
        }
        catch {
            Write-ErrorUi ("Recoverable menu error: {0}" -f $_.Exception.Message)
            Pause-Ui
        }
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

Initialize-Runtime

try {
    switch ($Mode) {
        'Interactive' { Show-MainMenu }
        'Audit'       { Invoke-ReadinessAudit }
        'Join'        { Invoke-GuidedJoin }
        'Status'      { Invoke-Status }
        'Leave'       { Invoke-LeaveDomain }
        'Restore'     { Invoke-RestorePreJoin }
    }
}
catch {
    Write-ErrorUi ("Unhandled operation error: {0}" -f $_.Exception.Message)
    exit 1
}
