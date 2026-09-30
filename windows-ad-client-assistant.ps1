#requires -RunAsAdministrator
<#
.SYNOPSIS
    Windows AD Client Assistant - v1.1.0-resilient

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
$script:Version = '1.1.0-resilient'
$script:SnapshotRoot = Join-Path $StateRoot 'snapshots'
$script:CurrentState = Join-Path $StateRoot 'current.json'
$script:LogRoot = Join-Path $StateRoot 'logs'
$script:RunId = '{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $PID
$script:LogFile = Join-Path $script:LogRoot ("client-assistant-{0}.log" -f $script:RunId)
$script:NetSetupLog = Join-Path $env:SystemRoot 'debug\NetSetup.log'
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


function Get-BootMarker {
    try {
        return (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime.ToString('o')
    }
    catch {
        return 'unknown'
    }
}

function Set-CurrentStateValues {
    param([Parameter(Mandatory=$true)][hashtable]$Values)

    $state = Get-CurrentState
    if (-not $state) { return $false }

    foreach ($key in $Values.Keys) {
        if ($state.PSObject.Properties[$key]) {
            $state.$key = $Values[$key]
        }
        else {
            $state | Add-Member -NotePropertyName $key -NotePropertyValue $Values[$key]
        }
    }

    $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:CurrentState -Encoding UTF8
    return $true
}

function Get-RecommendedInterfaceIndex {
    param([Parameter(Mandatory=$true)][string]$RemoteIPAddress)

    try {
        $route = Find-NetRoute -RemoteIPAddress $RemoteIPAddress -ErrorAction Stop |
            Select-Object -First 1
        if ($route -and $route.InterfaceIndex) {
            return [uint32]$route.InterfaceIndex
        }
    }
    catch {}
    return $null
}

function Test-IPv4AddressList {
    param([Parameter(Mandatory=$true)][string[]]$Addresses)
    if ($Addresses.Count -eq 0) { return $false }
    foreach ($address in $Addresses) {
        $parsed = $null
        if (-not [System.Net.IPAddress]::TryParse($address, [ref]$parsed)) { return $false }
        if ($parsed.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) { return $false }
    }
    return $true
}

function Test-TcpPort {
    param(
        [Parameter(Mandatory=$true)][string]$ComputerName,
        [Parameter(Mandatory=$true)][int]$Port
    )
    try {
        return [bool](Test-NetConnection -ComputerName $ComputerName -Port $Port `
            -InformationLevel Quiet -WarningAction SilentlyContinue -ErrorAction Stop)
    }
    catch { return $false }
}

function Get-NetSetupTail {
    param([int]$Lines = 250)
    if (-not (Test-Path -LiteralPath $script:NetSetupLog)) { return @() }
    try { return @(Get-Content -LiteralPath $script:NetSetupLog -Tail $Lines -ErrorAction Stop) }
    catch { return @() }
}

function Write-NetSetupDiagnosis {
    param(
        [string]$SnapshotPath = '',
        [int]$StartLine = 0
    )

    $all = @()
    if (Test-Path -LiteralPath $script:NetSetupLog) {
        try { $all = @(Get-Content -LiteralPath $script:NetSetupLog -ErrorAction Stop) } catch {}
    }
    if ($all.Count -eq 0) {
        Write-Warn 'NetSetup.log is unavailable; no Windows domain-join diagnostics could be extracted.'
        return
    }

    if ($StartLine -gt 0 -and $StartLine -lt $all.Count) {
        $tail = @($all | Select-Object -Skip $StartLine | Select-Object -Last 300)
    }
    else {
        $tail = @($all | Select-Object -Last 300)
    }

    if ($SnapshotPath) {
        try { $tail | Set-Content -LiteralPath (Join-Path $SnapshotPath 'NetSetup-tail.txt') -Encoding UTF8 } catch {}
    }

    $joined = $tail -join "`n"
    if ($joined -match '(?i)0x0*AAC|NERR_AccountReuseBlockedByPolicy|account reuse.*blocked') {
        Write-ErrorUi 'Windows blocked reuse of an existing AD computer account (0xAAC).'
        Write-Warn 'Use an account/owner allowed by NetJoin hardening, correct delegation/trusted-owner policy,'
        Write-Warn 'delete only a genuinely stale computer object, or choose a different computer name.'
        Write-Warn 'This assistant will not apply legacy registry bypasses for account-reuse hardening.'
        return
    }
    if ($joined -match '(?i)0x0*54B|ERROR_NO_SUCH_DOMAIN|domain.*could not be contacted') {
        Write-Warn 'NetSetup indicates DC/domain discovery failure. Re-check AD DNS, routing and required ports.'
    }
    elseif ($joined -match '(?i)0x0*52E|ERROR_LOGON_FAILURE') {
        Write-Warn 'NetSetup indicates credential/logon failure. Verify the join account and Kerberos time.'
    }
    elseif ($joined -match '(?i)0x0*5\b|ERROR_ACCESS_DENIED') {
        Write-Warn 'NetSetup indicates access denied. Verify delegated computer-join permissions and OU ACLs.'
    }
    else {
        Write-Warn 'NetSetup.log output from this join attempt was captured in the snapshot for troubleshooting.'
    }
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
    param([string]$RemoteIPAddress = '')

    $items = @(Get-NetworkCandidates)
    if ($items.Count -eq 0) { throw 'No active IPv4 network interface was detected.' }

    $recommended = $null
    if ($RemoteIPAddress) { $recommended = Get-RecommendedInterfaceIndex -RemoteIPAddress $RemoteIPAddress }

    if ($items.Count -eq 1) {
        Write-Ok ("Single active IPv4 interface selected automatically: {0}" -f $items[0].InterfaceAlias)
        return $items[0]
    }

    Write-Ui ''
    Write-Ui 'NETWORK INTERFACES' Cyan
    $defaultChoice = 1
    for ($i = 0; $i -lt $items.Count; $i++) {
        $cfg = $items[$i]
        $ips = @($cfg.IPv4Address | ForEach-Object { $_.IPAddress }) -join ','
        $gw = if ($cfg.IPv4DefaultGateway) { @($cfg.IPv4DefaultGateway | ForEach-Object { $_.NextHop }) -join ',' } else { '-' }
        $metric = try { (Get-NetIPInterface -InterfaceIndex $cfg.InterfaceIndex -AddressFamily IPv4 -ErrorAction Stop).InterfaceMetric } catch { '-' }
        $mark = ''
        if ($recommended -and [uint32]$cfg.InterfaceIndex -eq [uint32]$recommended) {
            $mark = ' <- route to AD DNS'
            $defaultChoice = $i + 1
        }
        Write-Ui ("  [{0}] {1,-24} IPv4={2,-18} GW={3,-16} metric={4}{5}" -f `
            ($i + 1), $cfg.InterfaceAlias, $ips, $gw, $metric, $mark)
    }
    Write-Ui '  [M] Enter interface index manually'

    $choice = Read-Value -Prompt 'Select interface' -Default ([string]$defaultChoice)
    if ($choice -match '^(?i)m$') {
        $idxRaw = Read-Value -Prompt 'InterfaceIndex' -Default ''
        [uint32]$idx = 0
        if (-not [uint32]::TryParse($idxRaw, [ref]$idx)) { throw 'Invalid InterfaceIndex.' }
        return Get-NetIPConfiguration -InterfaceIndex $idx -ErrorAction Stop
    }

    [int]$number = 0
    if (-not [int]::TryParse($choice, [ref]$number) -or $number -lt 1 -or $number -gt $items.Count) {
        throw 'Invalid interface selection.'
    }
    $selected = $items[$number - 1]
    if ($recommended -and [uint32]$selected.InterfaceIndex -ne [uint32]$recommended) {
        Write-Warn ("Selected interface {0} differs from the current route to AD DNS (ifIndex {1})." -f `
            $selected.InterfaceAlias,$recommended)
        if (-not (Confirm-Choice -Prompt 'Continue without changing the Windows route table?' -Default N)) {
            throw 'Interface selection cancelled because routing does not match.'
        }
    }
    return $selected
}

function Get-InterfaceDnsState {
    param([Parameter(Mandatory=$true)][uint32]$InterfaceIndex)

    $adapter = Get-NetAdapter -InterfaceIndex $InterfaceIndex -ErrorAction Stop
    $dns4 = Get-DnsClientServerAddress -InterfaceIndex $InterfaceIndex -AddressFamily IPv4 -ErrorAction Stop
    $dns6 = Get-DnsClientServerAddress -InterfaceIndex $InterfaceIndex -AddressFamily IPv6 -ErrorAction SilentlyContinue

    $guidText = [string]$adapter.InterfaceGuid
    if (-not $guidText.StartsWith('{')) { $guidText = '{' + $guidText.Trim('{}') + '}' }

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
        InterfaceIndex    = $InterfaceIndex
        InterfaceAlias    = [string]$adapter.Name
        InterfaceGuid     = $guidText
        ServerAddresses   = @($dns4.ServerAddresses)
        IPv6ServerAddresses = @($dns6.ServerAddresses)
        DnsWasStatic      = -not [string]::IsNullOrWhiteSpace($nameServer)
        StaticNameServer  = $nameServer
        DhcpNameServer    = $dhcpNameServer
    }
}

function Test-IpAddressList {
    param([Parameter(Mandatory=$true)][string[]]$Addresses)
    return (Test-IPv4AddressList -Addresses $Addresses)
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
        SnapshotVersion = 2
        CreatedAt       = (Get-Date).ToString('o')
        SnapshotPath    = $snapshotPath
        TargetDomain    = $TargetDomain
        ComputerName    = [string]$env:COMPUTERNAME
        BootMarker      = Get-BootMarker
        PartOfDomain    = [bool]$cs.PartOfDomain
        Domain          = [string]$cs.Domain
        Workgroup       = [string]$cs.Workgroup
        ProductName     = $product.ProductName
        EditionID       = $product.EditionID
        Interface       = $dnsState
    }

    $snapshotFile = Join-Path $snapshotPath 'snapshot.json'
    $snapshot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $snapshotFile -Encoding UTF8
    Write-Ok ("Pre-join snapshot created: {0}" -f $snapshotPath)
    return [pscustomobject]$snapshot
}

function Save-CurrentState {
    param(
        [Parameter(Mandatory=$true)]$Snapshot,
        [Parameter(Mandatory=$true)][string]$Domain,
        [Parameter(Mandatory=$true)][string[]]$DnsServers,
        [Parameter(Mandatory=$true)][string]$RequestedComputerName,
        [ValidateSet('JOIN_PENDING_REBOOT','JOINED','JOINED_DEGRADED','LEAVE_PENDING_REBOOT','RESTORE_PENDING_REBOOT')]
        [string]$Phase = 'JOIN_PENDING_REBOOT'
    )

    $state = [ordered]@{
        StateVersion          = 2
        Phase                 = $Phase
        PhaseBootMarker       = Get-BootMarker
        JoinedAt              = (Get-Date).ToString('o')
        Domain                = $Domain
        DnsServers            = @($DnsServers)
        RequestedComputerName = $RequestedComputerName
        SnapshotPath          = [string]$Snapshot.SnapshotPath
    }

    $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $script:CurrentState -Encoding UTF8
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
    $adapter = $null
    if ($iface.InterfaceGuid) {
        $targetGuid = ([string]$iface.InterfaceGuid).Trim('{}')
        $adapter = Get-NetAdapter -ErrorAction SilentlyContinue |
            Where-Object { ([string]$_.InterfaceGuid).Trim('{}') -ieq $targetGuid } |
            Select-Object -First 1
    }
    if (-not $adapter -and $iface.InterfaceIndex) {
        $adapter = Get-NetAdapter -InterfaceIndex ([uint32]$iface.InterfaceIndex) -ErrorAction SilentlyContinue
    }
    if (-not $adapter -and $iface.InterfaceAlias) {
        $adapter = Get-NetAdapter -Name ([string]$iface.InterfaceAlias) -ErrorAction SilentlyContinue
    }
    if (-not $adapter) { throw 'Original network adapter could not be matched by GUID, index or alias.' }

    $index = [uint32]$adapter.ifIndex
    Write-Info ("Restoring DNS on {0} (ifIndex {1})" -f $adapter.Name, $index)

    if ([bool]$iface.DnsWasStatic) {
        $old = @($iface.ServerAddresses)
        if ($old.Count -gt 0) {
            Set-DnsClientServerAddress -InterfaceIndex $index -ServerAddresses $old -ErrorAction Stop
            Write-Ok ("Previous static IPv4 DNS restored: {0}" -f ($old -join ', '))
        }
        else {
            Set-DnsClientServerAddress -InterfaceIndex $index -ResetServerAddresses -ErrorAction Stop
            Write-Ok 'Previous DNS state reset to interface defaults.'
        }
    }
    else {
        Set-DnsClientServerAddress -InterfaceIndex $index -ResetServerAddresses -ErrorAction Stop
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


function Test-DomainDnsPreflight {
    param(
        [Parameter(Mandatory=$true)][string]$Domain,
        [Parameter(Mandatory=$true)][string[]]$DnsServers
    )
    $srvName = '_ldap._tcp.dc._msdcs.{0}' -f $Domain
    $okAll = $true
    foreach ($server in $DnsServers) {
        try {
            $answers = @(Resolve-DnsName -Name $srvName -Type SRV -Server $server -DnsOnly -ErrorAction Stop |
                Where-Object { $_.Type -eq 'SRV' -and $_.NameTarget })
            if ($answers.Count -eq 0) { throw 'No SRV answer.' }
            Write-Ok ("AD DNS preflight passed through {0}." -f $server)
        }
        catch {
            Write-ErrorUi ("AD DNS {0} does not return DC locator SRV records: {1}" -f $server,$_.Exception.Message)
            $okAll = $false
        }
    }
    return $okAll
}

function Get-FirstDomainControllerFromDns {
    param(
        [Parameter(Mandatory=$true)][string]$Domain,
        [Parameter(Mandatory=$true)][string]$DnsServer
    )
    $srvName = '_ldap._tcp.dc._msdcs.{0}' -f $Domain
    try {
        $answer = Resolve-DnsName -Name $srvName -Type SRV -Server $DnsServer -DnsOnly -ErrorAction Stop |
            Where-Object { $_.Type -eq 'SRV' -and $_.NameTarget } |
            Sort-Object Priority,Weight |
            Select-Object -First 1
        if ($answer) { return ([string]$answer.NameTarget).TrimEnd('.') }
    }
    catch {}
    return $null
}

function Test-AdNetworkReadiness {
    param(
        [Parameter(Mandatory=$true)][string]$Domain,
        [Parameter(Mandatory=$true)][string[]]$DnsServers
    )

    $dc = Get-FirstDomainControllerFromDns -Domain $Domain -DnsServer $DnsServers[0]
    if (-not $dc) {
        Write-ErrorUi 'Could not derive a domain controller hostname from DNS SRV records.'
        return $false
    }

    Write-Ui ''
    Write-Ui ("AD NETWORK READINESS - {0}" -f $dc) Cyan
    $required = @(
        @{Name='DNS';Port=53},
        @{Name='Kerberos';Port=88},
        @{Name='RPC';Port=135},
        @{Name='LDAP';Port=389},
        @{Name='SMB';Port=445}
    )
    $all = $true
    foreach ($check in $required) {
        if (Test-TcpPort -ComputerName $dc -Port $check.Port) {
            Write-Ok ("{0}/TCP {1} reachable." -f $check.Name,$check.Port)
        }
        else {
            Write-ErrorUi ("{0}/TCP {1} is not reachable." -f $check.Name,$check.Port)
            $all = $false
        }
    }
    Write-Info 'Dynamic RPC ports are negotiated by Windows and are validated by the actual join operation.'
    return $all
}

function Test-TimeAgainstDomainController {
    param([Parameter(Mandatory=$true)][string]$ComputerName)
    if (-not (Get-Command w32tm.exe -ErrorAction SilentlyContinue)) { return $true }
    $output = & w32tm.exe /stripchart "/computer:$ComputerName" /samples:3 /dataonly 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Ok ("Time samples from domain controller {0} succeeded." -f $ComputerName)
        return $true
    }
    Write-Warn ("Could not sample domain-controller time from {0}." -f $ComputerName)
    $output | Select-Object -Last 5 | ForEach-Object { Write-Ui ([string]$_) Gray }
    return $false
}

function Test-PostJoinAcceptance {
    param([Parameter(Mandatory=$true)][string]$Domain)
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    $fail = $false
    if ($cs.PartOfDomain -and $cs.Domain -ieq $Domain) { Write-Ok 'Windows reports the expected domain membership.' }
    else { Write-ErrorUi ("Windows domain membership is not {0}." -f $Domain); $fail=$true }

    try {
        if (Test-ComputerSecureChannel -ErrorAction Stop) { Write-Ok 'Computer secure channel is healthy.' }
        else { Write-ErrorUi 'Computer secure channel test returned False.'; $fail=$true }
    }
    catch { Write-ErrorUi ("Secure channel validation failed: {0}" -f $_.Exception.Message); $fail=$true }

    if (Get-Command nltest.exe -ErrorAction SilentlyContinue) {
        & nltest.exe "/dsgetdc:$Domain" 2>&1 | ForEach-Object { Write-Ui ([string]$_) Gray }
        if ($LASTEXITCODE -ne 0) { $fail=$true }
        & nltest.exe "/sc_verify:$Domain" 2>&1 | ForEach-Object { Write-Ui ([string]$_) Gray }
        if ($LASTEXITCODE -ne 0) { $fail=$true }
    }

    $srvName = '_ldap._tcp.dc._msdcs.{0}' -f $Domain
    try {
        $ans = @(Resolve-DnsName -Name $srvName -Type SRV -DnsOnly -ErrorAction Stop |
            Where-Object { $_.Type -eq 'SRV' -and $_.NameTarget })
        if ($ans.Count -gt 0) { Write-Ok 'System resolver returns AD DC locator SRV records.' }
        else { throw 'No SRV answer.' }
    }
    catch { Write-ErrorUi 'System resolver failed AD DC locator after reboot.'; $fail=$true }

    return (-not $fail)
}

function Sync-LifecycleState {
    $state = Get-CurrentState
    if (-not $state) { return }
    $phase = if ($state.PSObject.Properties['Phase']) { [string]$state.Phase } else { 'LEGACY' }
    $boot = Get-BootMarker
    $phaseBoot = if ($state.PSObject.Properties['PhaseBootMarker']) { [string]$state.PhaseBootMarker } else { '' }
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop

    if ($phase -eq 'JOIN_PENDING_REBOOT') {
        if ($phaseBoot -eq $boot) {
            Write-Warn 'Join accepted by Windows; final acceptance is pending a reboot.'
            return
        }
        if (Test-PostJoinAcceptance -Domain ([string]$state.Domain)) {
            [void](Set-CurrentStateValues -Values @{Phase='JOINED';PhaseBootMarker=$boot})
            Write-Ok 'Post-reboot domain acceptance passed; lifecycle state is JOINED.'
        }
        else {
            [void](Set-CurrentStateValues -Values @{Phase='JOINED_DEGRADED';PhaseBootMarker=$boot})
            Write-Warn 'Post-reboot domain acceptance is degraded.'
        }
        return
    }

    if ($phase -eq 'LEAVE_PENDING_REBOOT') {
        if ($phaseBoot -eq $boot) {
            Write-Warn 'Domain leave is pending reboot. AD DNS is intentionally retained until Windows completes the transition.'
            return
        }
        if ($cs.PartOfDomain) {
            Write-Warn 'Windows still reports domain membership after the expected leave reboot.'
            return
        }

        try {
            $snapshot = Get-Snapshot -SnapshotPath ([string]$state.SnapshotPath)
            Restore-DnsFromSnapshot -Snapshot $snapshot
            $needsRename = ($env:COMPUTERNAME -ine [string]$snapshot.ComputerName)
            $nameOk = Restore-ComputerNameFromSnapshot -Snapshot $snapshot
            if ($needsRename -and $nameOk) {
                [void](Set-CurrentStateValues -Values @{Phase='RESTORE_PENDING_REBOOT';PhaseBootMarker=$boot})
                Write-Warn 'Original hostname restoration is scheduled; one final reboot is required.'
            }
            elseif ($nameOk) {
                Remove-Item -LiteralPath $script:CurrentState -Force -ErrorAction SilentlyContinue
                Write-Ok 'Domain leave and pre-join network identity restoration completed.'
            }
        }
        catch { Write-ErrorUi ("Post-leave restore failed: {0}" -f $_.Exception.Message) }
        return
    }

    if ($phase -eq 'RESTORE_PENDING_REBOOT') {
        if ($phaseBoot -eq $boot) {
            Write-Warn 'Hostname restoration is pending reboot.'
            return
        }
        try {
            $snapshot = Get-Snapshot -SnapshotPath ([string]$state.SnapshotPath)
            if ($env:COMPUTERNAME -ieq [string]$snapshot.ComputerName) {
                Remove-Item -LiteralPath $script:CurrentState -Force -ErrorAction SilentlyContinue
                Write-Ok 'Pre-join hostname restoration completed.'
            }
            else {
                Write-Warn 'Expected pre-join hostname is still not active.'
            }
        }
        catch {}
    }
}

function Set-DomainDns {
    param(
        [Parameter(Mandatory=$true)][uint32]$InterfaceIndex,
        [Parameter(Mandatory=$true)][string[]]$DnsServers
    )

    if (Test-RemoteSession) {
        Write-Warn 'Remote/RDP session detected. DNS changes should preserve an existing IP session,'
        Write-Warn 'but incorrect DNS can prevent reconnecting by hostname.'
    }

    Set-DnsClientServerAddress -InterfaceIndex $InterfaceIndex -ServerAddresses $DnsServers -ErrorAction Stop
    Clear-DnsClientCache -ErrorAction SilentlyContinue
    Write-Ok ("AD DNS configured: {0}" -f ($DnsServers -join ', '))

    $v6 = @(Get-DnsClientServerAddress -InterfaceIndex $InterfaceIndex -AddressFamily IPv6 -ErrorAction SilentlyContinue).ServerAddresses
    if ($v6.Count -gt 0) {
        Write-Warn ("IPv6 DNS servers are also present on this interface: {0}" -f ($v6 -join ', '))
        Write-Warn 'Ensure they can resolve the AD zone or remove/fix them through the network policy that owns IPv6.'
    }
}

function Test-DomainDiscovery {
    param(
        [Parameter(Mandatory=$true)][string]$Domain,
        [Parameter(Mandatory=$true)][string[]]$DnsServers
    )

    if (-not (Test-DomainDnsPreflight -Domain $Domain -DnsServers $DnsServers)) { return $false }
    $srvName = '_ldap._tcp.dc._msdcs.{0}' -f $Domain
    try {
        $system = @(Resolve-DnsName -Name $srvName -Type SRV -DnsOnly -ErrorAction Stop |
            Where-Object { $_.Type -eq 'SRV' -and $_.NameTarget })
        if ($system.Count -eq 0) { throw 'No system resolver SRV answer.' }
        Write-Ok 'System resolver can discover Active Directory.'
    }
    catch {
        Write-ErrorUi ("System resolver cannot discover the AD domain: {0}" -f $_.Exception.Message)
        return $false
    }

    if (Get-Command nltest.exe -ErrorAction SilentlyContinue) {
        $nltestOutput = & nltest.exe "/dsgetdc:$Domain" 2>&1
        if ($LASTEXITCODE -eq 0) { Write-Ok 'nltest located a domain controller.' }
        else {
            Write-Warn ("nltest DC locator returned exit code {0}." -f $LASTEXITCODE)
            $nltestOutput | ForEach-Object { Write-Ui ([string]$_) Gray }
            return $false
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
        $dns4 = @(Get-DnsClientServerAddress -InterfaceIndex $cfg.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses
        $dns6 = @(Get-DnsClientServerAddress -InterfaceIndex $cfg.InterfaceIndex -AddressFamily IPv6 -ErrorAction SilentlyContinue).ServerAddresses
        Write-Ui ("  {0} / ifIndex {1} / IPv4 DNS {2}" -f $cfg.InterfaceAlias,$cfg.InterfaceIndex,($dns4 -join ', '))
        if ($dns6.Count -gt 0) { Write-Ui ("      IPv6 DNS: {0}" -f ($dns6 -join ', ')) Gray }
    }

    Test-TimeState
    Sync-LifecycleState
    $state = Get-CurrentState
    if ($state) {
        $phase = if ($state.PSObject.Properties['Phase']) { $state.Phase } else { 'legacy' }
        Write-Ok ("Assistant-managed state exists: {0} / phase {1}." -f $state.Domain,$phase)
    }
    else { Write-Info 'No assistant-managed join state exists.' }
}

function Invoke-GuidedJoin {
    Write-Header
    Write-Ui 'GUIDED DOMAIN JOIN' Cyan
    Write-Ui ''

    if (-not (Test-DomainJoinEdition)) { return }
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    if ($cs.PartOfDomain) { Write-Warn ("This computer is already joined to: {0}" -f $cs.Domain); return }

    $existingState = Get-CurrentState
    if ($existingState) {
        Write-Warn ("Assistant state already exists for {0}. Resolve/restore it before starting another join." -f $existingState.Domain)
        return
    }

    $domain = (Read-Value -Prompt 'AD DNS domain (for example corp.example.com)' -Default '').ToLowerInvariant()
    if ($domain -notmatch '^[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' -or $domain -match '\.\.') {
        Write-ErrorUi 'A valid DNS domain is required.'
        return
    }

    $dnsText = Read-Value -Prompt 'AD DNS server IPv4 addresses (comma separated)' -Default ''
    $dnsServers = @(Parse-DnsInput -Text $dnsText)
    if (-not (Test-IPv4AddressList -Addresses $dnsServers)) {
        Write-ErrorUi 'At least one valid IPv4 AD DNS server address is required.'
        return
    }

    if (-not (Test-DomainDnsPreflight -Domain $domain -DnsServers $dnsServers)) {
        Write-ErrorUi 'Direct AD DNS preflight failed before any local DNS change.'
        return
    }

    $iface = Select-NetworkInterface -RemoteIPAddress $dnsServers[0]
    $joinUser = Read-Value -Prompt 'Join account' -Default ("Administrator@{0}" -f $domain)
    $ouPath = Read-Value -Prompt 'Computer OU DN (optional)' -Default ''
    if ($ouPath -and $ouPath -notmatch '^(?i:OU|CN)=') {
        Write-Warn 'OU path does not look like a distinguished name beginning with OU= or CN=.'
        if (-not (Confirm-Choice -Prompt 'Use this OU value anyway?' -Default N)) { return }
    }

    $requestedName = Read-Value -Prompt 'Computer name' -Default $env:COMPUTERNAME
    if ($requestedName -notmatch '^[A-Za-z0-9][A-Za-z0-9-]{0,14}$') {
        Write-ErrorUi 'Computer name must be 1-15 characters using letters, digits or hyphen.'
        return
    }

    Write-Ui ''
    Write-Ui 'Plan:' Cyan
    Write-Ui ("  Domain       : {0}" -f $domain)
    Write-Ui ("  Interface    : {0} / ifIndex {1}" -f $iface.InterfaceAlias,$iface.InterfaceIndex)
    Write-Ui ("  DNS          : {0}" -f ($dnsServers -join ', '))
    Write-Ui ("  Computer     : {0}" -f $requestedName)
    Write-Ui ("  Join account : {0}" -f $joinUser)
    Write-Ui ("  OU           : {0}" -f $(if ($ouPath) { $ouPath } else { '(default container)' }))

    if (-not (Confirm-Choice -Prompt 'Create a reversible snapshot and continue?' -Default Y)) { return }
    $snapshot = New-PreJoinSnapshot -Interface $iface -TargetDomain $domain
    $joinAccepted = $false
    $addComputerAttempted = $false

    try {
        Set-DomainDns -InterfaceIndex ([uint32]$iface.InterfaceIndex) -DnsServers $dnsServers
        Test-TimeState

        if (-not (Test-DomainDiscovery -Domain $domain -DnsServers $dnsServers)) {
            throw 'AD discovery failed after applying the selected DNS configuration.'
        }
        if (-not (Test-AdNetworkReadiness -Domain $domain -DnsServers $dnsServers)) {
            throw 'Required AD ports are not reachable from the selected network path.'
        }

        $dc = Get-FirstDomainControllerFromDns -Domain $domain -DnsServer $dnsServers[0]
        if ($dc) { [void](Test-TimeAgainstDomainController -ComputerName $dc) }

        Write-Ui ''
        Write-Info 'Domain credentials are requested by Windows Credential UI/PowerShell.'
        Write-Info 'The password is not stored by this assistant.'
        $credential = Get-Credential -UserName $joinUser -Message ("Credentials authorized to join {0}" -f $domain)
        if (-not $credential) { throw 'Credential prompt was cancelled.' }

        $params = @{DomainName=$domain;Credential=$credential;PassThru=$true;Force=$true;ErrorAction='Stop'}
        if ($ouPath) { $params.OUPath = $ouPath }
        if ($requestedName -ine $env:COMPUTERNAME) { $params.NewName = $requestedName }

        $netSetupBefore = 0
        if (Test-Path -LiteralPath $script:NetSetupLog) {
            try { $netSetupBefore = @(Get-Content -LiteralPath $script:NetSetupLog -ErrorAction Stop).Count } catch {}
        }
        $addComputerAttempted = $true
        $result = Add-Computer @params
        if ($result -and $result.PSObject.Properties['HasSucceeded'] -and -not $result.HasSucceeded) {
            throw 'Add-Computer returned HasSucceeded=False.'
        }
        $joinAccepted = $true

        Save-CurrentState -Snapshot $snapshot -Domain $domain -DnsServers $dnsServers `
            -RequestedComputerName $requestedName -Phase JOIN_PENDING_REBOOT

        Write-Ok 'Windows accepted the domain join operation.'
        Write-Warn 'AD DNS is intentionally retained until Windows reboots and passes final secure-channel validation.'
        if (Confirm-Choice -Prompt 'Restart now?' -Default N) { Restart-Computer -Force }
    }
    catch {
        Write-ErrorUi ("Domain join failed: {0}" -f $_.Exception.Message)
        if ($addComputerAttempted) {
            Write-NetSetupDiagnosis -SnapshotPath ([string]$snapshot.SnapshotPath) -StartLine $netSetupBefore
        }

        if ($joinAccepted) {
            Write-Warn 'Add-Computer already accepted the join; AD DNS is retained to avoid breaking the pending domain transition.'
            Write-Warn ("Recovery snapshot: {0}" -f $snapshot.SnapshotPath)
            try {
                Save-CurrentState -Snapshot $snapshot -Domain $domain -DnsServers $dnsServers `
                    -RequestedComputerName $requestedName -Phase JOIN_PENDING_REBOOT
            }
            catch {
                Write-ErrorUi 'Could not persist lifecycle state after an accepted join. Do not restore DNS manually before reboot.'
            }
        }
        else {
            Write-Warn 'Restoring the pre-join DNS state because Add-Computer did not complete successfully.'
            try { Restore-DnsFromSnapshot -Snapshot $snapshot }
            catch {
                Write-ErrorUi ("Automatic DNS rollback failed: {0}" -f $_.Exception.Message)
                Write-Warn ("Snapshot remains available at: {0}" -f $snapshot.SnapshotPath)
            }
            try { [void](Restore-ComputerNameFromSnapshot -Snapshot $snapshot) } catch {}
        }
        Write-Warn 'No domain password was persisted.'
    }
}

function Invoke-Status {
    Write-Header
    Write-Ui 'DOMAIN CLIENT STATUS' Cyan
    Write-Ui ''

    Sync-LifecycleState
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    Write-Ui ("Computer      : {0}" -f $env:COMPUTERNAME)
    Write-Ui ("PartOfDomain  : {0}" -f $cs.PartOfDomain)
    Write-Ui ("Domain/Group  : {0}" -f $(if ($cs.PartOfDomain) { $cs.Domain } else { $cs.Workgroup }))

    if ($cs.PartOfDomain) {
        try {
            $secure = Test-ComputerSecureChannel -ErrorAction Stop
            if ($secure) { Write-Ok 'Computer secure channel is healthy.' }
            else { Write-Warn 'Computer secure channel test returned False.' }
        }
        catch { Write-Warn ("Secure channel test failed: {0}" -f $_.Exception.Message) }

        if (Get-Command nltest.exe -ErrorAction SilentlyContinue) {
            & nltest.exe "/dsgetdc:$($cs.Domain)" 2>&1 | ForEach-Object { Write-Ui ([string]$_) Gray }
        }
    }

    $state = Get-CurrentState
    if ($state) {
        Write-Ui ''
        Write-Ui 'Assistant state:' Cyan
        Write-Ui ("  Phase    : {0}" -f $(if ($state.PSObject.Properties['Phase']) {$state.Phase} else {'legacy'}))
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

    Sync-LifecycleState
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    if (-not $cs.PartOfDomain) {
        Write-Info 'This computer is not currently joined to a domain.'
        return
    }

    $state = Get-CurrentState
    $snapshot = $null
    if ($state -and $state.SnapshotPath) {
        try { $snapshot = Get-Snapshot -SnapshotPath ([string]$state.SnapshotPath) }
        catch { Write-Warn ("Recorded snapshot could not be loaded: {0}" -f $_.Exception.Message) }
    }

    $defaultWorkgroup = if ($snapshot -and $snapshot.Workgroup) { [string]$snapshot.Workgroup } else { 'WORKGROUP' }
    $unjoinUser = Read-Value -Prompt 'Account authorized to remove this computer from AD' `
        -Default ("Administrator@{0}" -f $cs.Domain)
    $workgroup = Read-Value -Prompt 'Workgroup after leaving the domain' -Default $defaultWorkgroup

    if (-not (Confirm-Literal -Prompt ("This computer will leave domain {0}." -f $cs.Domain) -Literal 'LEAVE')) { return }
    $credential = Get-Credential -UserName $unjoinUser -Message ("Credentials authorized to unjoin from {0}" -f $cs.Domain)
    if (-not $credential) { Write-Warn 'Credential prompt cancelled.'; return }

    try {
        $result = Remove-Computer -UnjoinDomainCredential $credential -WorkgroupName $workgroup `
            -PassThru -Force -ErrorAction Stop
        if ($result -and $result.PSObject.Properties['HasSucceeded'] -and -not $result.HasSucceeded) {
            throw 'Remove-Computer returned HasSucceeded=False.'
        }

        Write-Ok 'Windows accepted the domain leave operation.'
        if ($state -and $snapshot) {
            [void](Set-CurrentStateValues -Values @{Phase='LEAVE_PENDING_REBOOT';PhaseBootMarker=(Get-BootMarker)})
            Write-Warn 'AD DNS is intentionally retained until the leave reboot completes.'
            Write-Info 'After reboot, run this assistant or -Mode Status to restore DNS and hostname safely.'
        }
        else {
            Write-Warn 'No assistant snapshot exists; automatic post-reboot DNS/hostname restoration is unavailable.'
        }

        Write-Warn 'A reboot is required to complete the domain leave.'
        if (Confirm-Choice -Prompt 'Restart now?' -Default N) { Restart-Computer -Force }
    }
    catch {
        Write-ErrorUi ("Domain leave failed: {0}" -f $_.Exception.Message)
        Write-NetSetupDiagnosis
        Write-Warn 'No forced registry/domain-membership manipulation was attempted.'
    }
}

function Invoke-RestorePreJoin {
    Write-Header
    Write-Ui 'RESTORE PRE-JOIN STATE' Cyan
    Write-Ui ''

    Sync-LifecycleState
    $state = Get-CurrentState
    if (-not $state) { Write-ErrorUi 'No assistant-managed current state exists.'; return }

    $phase = if ($state.PSObject.Properties['Phase']) { [string]$state.Phase } else { 'LEGACY' }
    $phaseBoot = if ($state.PSObject.Properties['PhaseBootMarker']) { [string]$state.PhaseBootMarker } else { '' }
    $currentBoot = Get-BootMarker
    if ($phase -eq 'JOIN_PENDING_REBOOT' -and $phaseBoot -eq $currentBoot) {
        Write-ErrorUi 'The domain join is still pending its first reboot.'
        Write-Warn 'Reboot first; restoring DNS/hostname now could break the pending Windows domain transition.'
        return
    }
    if ($phase -eq 'LEAVE_PENDING_REBOOT' -and $phaseBoot -eq $currentBoot) {
        Write-ErrorUi 'The domain leave is still pending reboot.'
        Write-Warn 'AD DNS is intentionally retained until Windows materializes the leave operation.'
        return
    }
    if ($phase -eq 'RESTORE_PENDING_REBOOT' -and $phaseBoot -eq $currentBoot) {
        Write-ErrorUi 'Hostname restoration is already pending reboot.'
        return
    }

    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    if ($cs.PartOfDomain) {
        Write-ErrorUi ("This computer is still joined to {0}." -f $cs.Domain)
        Write-Warn 'Use Leave domain cleanly first. The assistant will not fake an unjoin via registry changes.'
        return
    }

    try { $snapshot = Get-Snapshot -SnapshotPath ([string]$state.SnapshotPath) }
    catch { Write-ErrorUi $_.Exception.Message; return }

    try {
        Restore-DnsFromSnapshot -Snapshot $snapshot
        $needsRename = ($env:COMPUTERNAME -ine [string]$snapshot.ComputerName)
        $nameRestored = Restore-ComputerNameFromSnapshot -Snapshot $snapshot
        if ($needsRename -and $nameRestored) {
            [void](Set-CurrentStateValues -Values @{Phase='RESTORE_PENDING_REBOOT';PhaseBootMarker=(Get-BootMarker)})
            Write-Warn 'DNS is restored and the original hostname is scheduled; reboot once more to finish.'
        }
        elseif ($nameRestored) {
            Remove-Item -LiteralPath $script:CurrentState -Force -ErrorAction SilentlyContinue
            Write-Ok 'Pre-join state restored.'
        }
    }
    catch { Write-ErrorUi ("Restore failed: {0}" -f $_.Exception.Message) }
}

# ---------------------------------------------------------------------------
# Interactive menu
# ---------------------------------------------------------------------------

function Show-MainMenu {
    while ($true) {
        Write-Header
        Sync-LifecycleState
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
