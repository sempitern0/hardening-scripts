#requires -RunAsAdministrator
<#
.SYNOPSIS
    Windows AD Client Assistant - v1.4.0-remote-readiness-adaptive-timeouts

.DESCRIPTION
    Reversible, transaction-aware assistant for joining Windows clients and
    member servers to classic Active Directory.

    Core flow:
      detect -> preflight -> snapshot -> DNS -> discover -> join -> validate
      recover interrupted transactions without guessing membership state
      leave -> reboot -> restore pre-join DNS/hostname

    The assistant never stores domain passwords and does not add third-party
    package managers or repositories.

.NOTES
    Run from Windows PowerShell 5.1+ as Administrator.
    Test domain lifecycle changes in a lab before broad deployment.
#>

[CmdletBinding()]
param(
    [ValidateSet('Interactive','Audit','Join','Status','Leave','Switch','Connectivity','Troubleshoot','Diagnostics','RemoteSetup','Restore','Snapshots','Recover')]
    [string]$Mode = 'Interactive',

    [ValidateSet('en','es')]
    [string]$Language = 'en',

    [string]$StateRoot = "$env:ProgramData\ADClientAssistant",

    [string]$ExternalDnsProbe = 'www.microsoft.com',

    [ValidateRange(5,300)]
    [int]$NetworkOperationTimeoutSeconds = 60,

    [ValidateRange(1000,60000)]
    [int]$TcpProbeTimeoutMs = 8000,

    # AD clients should normally use only AD DNS. By default, every configured
    # AD DNS server must also resolve a name outside the AD zone before the
    # client resolver is replaced. This switch is an explicit exception for
    # intentionally isolated environments.
    [switch]$AllowAdDnsWithoutExternalResolution,

    [switch]$NoColor
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Runtime state
# ---------------------------------------------------------------------------

$script:ProductName = 'Windows AD Client Assistant'
$script:Version = '1.4.0-remote-readiness-adaptive-timeouts'
$script:StartedAt = Get-Date
$script:SnapshotRoot = Join-Path $StateRoot 'snapshots'
$script:CurrentState = Join-Path $StateRoot 'current.json'
$script:LogRoot = Join-Path $StateRoot 'logs'
$script:ReportRoot = Join-Path $StateRoot 'reports'
$script:RunId = '{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $PID
$script:LogFile = Join-Path $script:LogRoot ("client-assistant-{0}.log" -f $script:RunId)
$script:ReportFile = Join-Path $script:ReportRoot ("client-assistant-{0}.json" -f $script:RunId)
$script:NetSetupLog = Join-Path $env:SystemRoot 'debug\NetSetup.log'
$script:UseColor = (-not $NoColor) -and (-not [Console]::IsOutputRedirected)
$script:Events = New-Object 'System.Collections.Generic.List[object]'
$script:LockStream = $null
$script:RunOutcome = 'COMPLETE'
$script:UiLanguage = $Language.ToLowerInvariant()

# ---------------------------------------------------------------------------
# UI / logging / persistence
# ---------------------------------------------------------------------------

function Initialize-Runtime {
    foreach ($path in @($StateRoot,$script:SnapshotRoot,$script:LogRoot,$script:ReportRoot)) {
        New-Item -ItemType Directory -Force -Path $path | Out-Null
    }

    New-Item -ItemType File -Force -Path $script:LogFile | Out-Null

    $lockPath = Join-Path $StateRoot 'assistant.lock'
    try {
        $script:LockStream = [System.IO.File]::Open(
            $lockPath,
            [System.IO.FileMode]::OpenOrCreate,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None
        )
    }
    catch {
        throw 'Another Windows AD Client Assistant process appears to be running.'
    }
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

function Add-RunEvent {
    param(
        [Parameter(Mandatory=$true)][string]$Type,
        [Parameter(Mandatory=$true)][string]$Message
    )

    $script:Events.Add([pscustomobject]@{
        Time    = (Get-Date).ToString('o')
        Type    = $Type
        Message = $Message
    }) | Out-Null
}

function Write-Ui {
    param(
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Text,
        [ValidateSet('Default','Cyan','Green','Yellow','Red','Gray','White','Magenta')]
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
    Add-RunEvent INFO $Text
}

function Write-Ok {
    param([string]$Text)
    Write-Ui '[ OK ] ' Green -NoNewline
    Write-Ui $Text
    Write-Log $Text OK
    Add-RunEvent OK $Text
}

function Write-Warn {
    param([string]$Text)
    Write-Ui '[WARN] ' Yellow -NoNewline
    Write-Ui $Text
    Write-Log $Text WARN
    Add-RunEvent WARN $Text
}

function Write-ErrorUi {
    param([string]$Text)
    Write-Ui '[ERROR] ' Red -NoNewline
    Write-Ui $Text
    Write-Log $Text ERROR
    Add-RunEvent ERROR $Text
}

$script:UiSpanish = @{
    'Press Enter to continue' = 'Pulsa Enter para continuar'
    'Select operation' = 'Selecciona una operación'
    'Readiness audit' = 'Auditoría de preparación'
    'Guided domain join' = 'Unión guiada al dominio'
    'Domain client status' = 'Estado del cliente de dominio'
    'Leave domain cleanly' = 'Salir limpiamente del dominio'
    'Switch to another domain' = 'Cambiar a otro dominio'
    'AD connectivity test' = 'Prueba de conectividad AD'
    'Troubleshoot / repair' = 'Diagnóstico / reparación'
    'Export diagnostic bundle' = 'Exportar paquete de diagnóstico'
    'Restore pre-join state' = 'Restaurar estado previo a la unión'
    'List recovery snapshots' = 'Listar snapshots de recuperación'
    'Recover interrupted lifecycle' = 'Recuperar ciclo interrumpido'
    'Language / Idioma' = 'Idioma / Language'
    'Exit' = 'Salir'
    'AD DNS domain (for example corp.example.com)' = 'Dominio DNS de AD (por ejemplo corp.example.com)'
    'AD DNS server IPv4 addresses (comma separated)' = 'Direcciones IPv4 de los DNS de AD (separadas por comas)'
    'Target AD DNS domain (for example corp.example.com)' = 'Dominio DNS de AD destino (por ejemplo corp.example.com)'
    'Target AD DNS server IPv4 addresses (comma separated)' = 'Direcciones IPv4 de los DNS AD destino (separadas por comas)'
    'Join account' = 'Cuenta autorizada para unir el equipo'
    'Source-domain unjoin account' = 'Cuenta autorizada para salir del dominio origen'
    'Target-domain join account' = 'Cuenta autorizada para unir al dominio destino'
    'Computer OU DN (optional)' = 'DN de la OU del equipo (opcional)'
    'Computer name' = 'Nombre del equipo'
    'Workgroup after leaving the domain' = 'Grupo de trabajo tras abandonar el dominio'
    'Restart now?' = '¿Reiniciar ahora?'
}

function Get-UiText {
    param([Parameter(Mandatory=$true)][string]$Text)
    if ($script:UiLanguage -eq 'es' -and $script:UiSpanish.ContainsKey($Text)) {
        return [string]$script:UiSpanish[$Text]
    }
    return $Text
}

function Switch-UiLanguage {
    $script:UiLanguage = if ($script:UiLanguage -eq 'en') { 'es' } else { 'en' }
}

function Pause-Ui {
    if (-not [Console]::IsInputRedirected) {
        [void](Read-Host (Get-UiText 'Press Enter to continue'))
    }
}

function Read-Value {
    param(
        [Parameter(Mandatory=$true)][string]$Prompt,
        [string]$Default = ''
    )

    if ($Default) {
        $value = Read-Host ("{0} [{1}]" -f (Get-UiText $Prompt), $Default)
        if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
        return $value.Trim()
    }

    return (Read-Host (Get-UiText $Prompt)).Trim()
}

function Confirm-Choice {
    param(
        [Parameter(Mandatory=$true)][string]$Prompt,
        [ValidateSet('Y','N')][string]$Default = 'N'
    )

    $shownDefault = $Default
    if ($script:UiLanguage -eq 'es' -and $Default -eq 'Y') { $shownDefault = 'S' }
    $answer = Read-Host ("{0} [{1}]" -f (Get-UiText $Prompt), $shownDefault)
    if ([string]::IsNullOrWhiteSpace($answer)) { $answer = $Default }
    return ($answer -match '^(?i:y|yes|s|si|sí)$')
}

function Confirm-Literal {
    param(
        [Parameter(Mandatory=$true)][string]$Prompt,
        [Parameter(Mandatory=$true)][string]$Literal
    )

    Write-Ui (Get-UiText $Prompt) Yellow
    $literalPrompt = if ($script:UiLanguage -eq 'es') { "Escribe {0} para continuar" -f $Literal } else { "Type {0} to continue" -f $Literal }
    $answer = Read-Host $literalPrompt
    return ($answer -ceq $Literal)
}

function Write-JsonAtomic {
    param(
        [Parameter(Mandatory=$true)]$Object,
        [Parameter(Mandatory=$true)][string]$Path,
        [int]$Depth = 10
    )

    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }

    $tmp = '{0}.tmp.{1}' -f $Path,$PID
    try {
        $Object | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $tmp -Encoding UTF8
        Move-Item -LiteralPath $tmp -Destination $Path -Force
    }
    finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

function Get-CurrentState {
    if (-not (Test-Path -LiteralPath $script:CurrentState)) { return $null }
    try {
        return Get-Content -LiteralPath $script:CurrentState -Raw -ErrorAction Stop |
            ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Warn ("Current state file is unreadable: {0}" -f $_.Exception.Message)
        return $null
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

    if ($state.PSObject.Properties['UpdatedAt']) {
        $state.UpdatedAt = (Get-Date).ToString('o')
    }
    else {
        $state | Add-Member -NotePropertyName UpdatedAt -NotePropertyValue (Get-Date).ToString('o')
    }

    Write-JsonAtomic -Object $state -Path $script:CurrentState
    return $true
}

function Remove-CurrentState {
    Remove-Item -LiteralPath $script:CurrentState -Force -ErrorAction SilentlyContinue
}

function Get-BootMarker {
    try {
        return (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime.ToString('o')
    }
    catch {
        return 'unknown'
    }
}

function Get-LifecycleLabel {
    $state = Get-CurrentState
    if (-not $state) { return 'none' }
    if ($state.PSObject.Properties['Phase']) { return [string]$state.Phase }
    return 'legacy'
}

function Write-Header {
    try { Clear-Host } catch {}

    Write-Ui ('  {0}' -f $script:ProductName) Cyan
    Write-Ui ('  v{0}' -f $script:Version) Gray
    Write-Ui ('-' * 88) Gray

    $identity = 'unavailable'
    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        $identity = if ($cs.PartOfDomain) { $cs.Domain } else { $cs.Workgroup }
    }
    catch {}

    $remote = if (Test-RemoteSession) { 'remote' } else { 'local' }
    Write-Ui ('  Computer={0}  Identity={1}  Session={2}' -f $env:COMPUTERNAME,$identity,$remote) White
    Write-Ui ('  Lifecycle={0}  Log={1}' -f (Get-LifecycleLabel),$script:LogFile) Gray
    Write-Ui ('-' * 88) Gray
    Write-Ui ''
}

function Write-RunReport {
    try {
        $cs = $null
        try { $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop } catch {}

        $state = Get-CurrentState
        $report = [ordered]@{
            SchemaVersion = 1
            Assistant     = $script:ProductName
            Version       = $script:Version
            Mode          = $Mode
            StartedAt     = $script:StartedAt.ToString('o')
            CompletedAt   = (Get-Date).ToString('o')
            Outcome       = $script:RunOutcome
            Computer      = $env:COMPUTERNAME
            PartOfDomain  = $(if ($cs) { [bool]$cs.PartOfDomain } else { $null })
            Domain        = $(if ($cs) { [string]$cs.Domain } else { $null })
            CurrentState  = $state
            LogFile       = $script:LogFile
            Events        = @($script:Events)
        }
        Write-JsonAtomic -Object $report -Path $script:ReportFile -Depth 12
    }
    catch {
        try { Write-Log ("Could not write run report: {0}" -f $_.Exception.Message) WARN } catch {}
    }
}

# ---------------------------------------------------------------------------
# Host / network discovery
# ---------------------------------------------------------------------------

function Test-RemoteSession {
    $sender = Get-Variable -Name PSSenderInfo -ErrorAction SilentlyContinue
    return ($env:SESSIONNAME -match '^(?i)RDP-' -or [bool]$sender)
}

function Get-ProductInfo {
    $cv = Get-ItemProperty `
        -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' `
        -ErrorAction Stop

    return [pscustomobject]@{
        ProductName = [string]$cv.ProductName
        EditionID   = [string]$cv.EditionID
    }
}

function Test-DomainJoinEdition {
    $info = Get-ProductInfo
    if ($info.ProductName -match '(?i)\bHome\b' -or $info.EditionID -match '(?i)^Core') {
        Write-ErrorUi ("Windows edition does not support classic AD domain join: {0} / {1}" -f `
            $info.ProductName,$info.EditionID)
        return $false
    }
    return $true
}

function Test-DnsDomainName {
    param([Parameter(Mandatory=$true)][string]$Name)

    if ($Name.Length -lt 3 -or $Name.Length -gt 253) { return $false }
    if ($Name -notmatch '\.' -or $Name.StartsWith('.') -or $Name.EndsWith('.') -or $Name.Contains('..')) {
        return $false
    }

    foreach ($label in $Name.Split('.')) {
        if ($label.Length -lt 1 -or $label.Length -gt 63) { return $false }
        if ($label -notmatch '^[A-Za-z0-9][A-Za-z0-9-]*[A-Za-z0-9]$' -and $label.Length -gt 1) {
            return $false
        }
        if ($label.Length -eq 1 -and $label -notmatch '^[A-Za-z0-9]$') { return $false }
    }
    return $true
}

function Test-ComputerNameValue {
    param([Parameter(Mandatory=$true)][string]$Name)
    if ($Name.Length -lt 1 -or $Name.Length -gt 15) { return $false }
    return ($Name -match '^[A-Za-z0-9](?:[A-Za-z0-9-]{0,13}[A-Za-z0-9])?$' -or $Name -match '^[A-Za-z0-9]$')
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

function Parse-DnsInput {
    param([Parameter(Mandatory=$true)][string]$Text)
    return @(
        $Text -split '[,;\s]+' |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { $_.Trim() }
    )
}

function Test-TcpPort {
    param(
        [Parameter(Mandatory=$true)][string]$ComputerName,
        [Parameter(Mandatory=$true)][int]$Port,
        [int]$TimeoutMs = $TcpProbeTimeoutMs
    )

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect($ComputerName,$Port,$null,$null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs,$false)) { return $false }
        $client.EndConnect($async)
        return $true
    }
    catch { return $false }
    finally { $client.Close() }
}

function Get-RecommendedInterfaceIndex {
    param([Parameter(Mandatory=$true)][string]$RemoteIPAddress)
    try {
        $route = Find-NetRoute -RemoteIPAddress $RemoteIPAddress -ErrorAction Stop |
            Select-Object -First 1
        if ($route -and $route.InterfaceIndex) { return [uint32]$route.InterfaceIndex }
    }
    catch {}
    return $null
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
        $gw = if ($cfg.IPv4DefaultGateway) {
            @($cfg.IPv4DefaultGateway | ForEach-Object { $_.NextHop }) -join ','
        }
        else { '-' }
        $metric = try {
            (Get-NetIPInterface -InterfaceIndex $cfg.InterfaceIndex -AddressFamily IPv4 -ErrorAction Stop).InterfaceMetric
        }
        catch { '-' }
        $mark = ''
        if ($recommended -and [uint32]$cfg.InterfaceIndex -eq [uint32]$recommended) {
            $mark = ' <- route to AD DNS'
            $defaultChoice = $i + 1
        }
        Write-Ui ("  [{0}] {1,-24} IPv4={2,-18} GW={3,-16} metric={4}{5}" -f `
            ($i + 1),$cfg.InterfaceAlias,$ips,$gw,$metric,$mark)
    }
    Write-Ui '  [M] Enter interface index manually'

    $choice = Read-Value -Prompt 'Select interface' -Default ([string]$defaultChoice)
    if ($choice -match '^(?i)m$') {
        $idxRaw = Read-Value -Prompt 'InterfaceIndex' -Default ''
        [uint32]$idx = 0
        if (-not [uint32]::TryParse($idxRaw,[ref]$idx)) { throw 'Invalid InterfaceIndex.' }
        return Get-NetIPConfiguration -InterfaceIndex $idx -ErrorAction Stop
    }

    [int]$number = 0
    if (-not [int]::TryParse($choice,[ref]$number) -or $number -lt 1 -or $number -gt $items.Count) {
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

    return [pscustomobject]@{
        InterfaceIndex      = $InterfaceIndex
        InterfaceAlias      = [string]$adapter.Name
        InterfaceGuid       = $guidText
        ServerAddresses     = @($dns4.ServerAddresses)
        IPv6ServerAddresses = @($dns6.ServerAddresses)
        DnsWasStatic        = -not [string]::IsNullOrWhiteSpace($nameServer)
        StaticNameServer    = $nameServer
        DhcpNameServer      = $dhcpNameServer
    }
}

# ---------------------------------------------------------------------------
# NetSetup evidence
# ---------------------------------------------------------------------------

function Get-NetSetupLineCount {
    if (-not (Test-Path -LiteralPath $script:NetSetupLog)) { return 0 }
    try { return @(Get-Content -LiteralPath $script:NetSetupLog -ErrorAction Stop).Count }
    catch { return 0 }
}

function Get-NetSetupAttemptLines {
    param([int]$StartLine = 0)

    if (-not (Test-Path -LiteralPath $script:NetSetupLog)) { return @() }
    try {
        $all = @(Get-Content -LiteralPath $script:NetSetupLog -ErrorAction Stop)
        if ($StartLine -gt 0 -and $StartLine -lt $all.Count) {
            return @($all | Select-Object -Skip $StartLine | Select-Object -Last 500)
        }
        return @($all | Select-Object -Last 500)
    }
    catch { return @() }
}

function Get-JoinCommitEvidence {
    param(
        [Parameter(Mandatory=$true)][string]$Domain,
        [int]$NetSetupStartLine = 0
    )

    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        if ($cs.PartOfDomain -and $cs.Domain -ieq $Domain) {
            return [pscustomobject]@{Outcome='Accepted';Reason='Windows reports target-domain membership'}
        }
    }
    catch {}

    $lines = @(Get-NetSetupAttemptLines -StartLine $NetSetupStartLine)
    $text = $lines -join "`n"

    if ($text -match '(?i)Netp(?:Do)?JoinDomain[^\r\n]*status:\s*0x0\b' -or
        $text -match '(?i)machine is now joined to the domain') {
        return [pscustomobject]@{Outcome='Accepted';Reason='NetSetup.log contains a successful join result'}
    }

    if ($text -match '(?i)Netp(?:Do)?JoinDomain[^\r\n]*status:\s*0x(?!0\b)[0-9a-f]+' -or
        $text -match '(?i)NERR_AccountReuseBlockedByPolicy|ERROR_NO_SUCH_DOMAIN|ERROR_LOGON_FAILURE') {
        return [pscustomobject]@{Outcome='Failed';Reason='NetSetup.log contains an explicit join failure'}
    }

    return [pscustomobject]@{Outcome='Ambiguous';Reason='No conclusive membership result was found'}
}

function Write-NetSetupDiagnosis {
    param(
        [string]$SnapshotPath = '',
        [int]$StartLine = 0
    )

    $tail = @(Get-NetSetupAttemptLines -StartLine $StartLine)
    if ($tail.Count -eq 0) {
        Write-Warn 'NetSetup.log is unavailable; no Windows domain-join diagnostics could be extracted.'
        return
    }

    if ($SnapshotPath) {
        try { $tail | Set-Content -LiteralPath (Join-Path $SnapshotPath 'NetSetup-tail.txt') -Encoding UTF8 } catch {}
    }

    $joined = $tail -join "`n"
    if ($joined -match '(?i)0x0*AAC|NERR_AccountReuseBlockedByPolicy|account reuse.*blocked') {
        Write-ErrorUi 'Windows blocked reuse of an existing AD computer account (0xAAC).'
        Write-Warn 'Use a delegated account/owner allowed by NetJoin hardening, or inspect the stale computer object.'
        Write-Warn 'This assistant will not apply legacy registry bypasses for account-reuse hardening.'
    }
    elseif ($joined -match '(?i)0x0*54B|ERROR_NO_SUCH_DOMAIN|domain.*could not be contacted') {
        Write-Warn 'NetSetup indicates DC/domain discovery failure. Re-check AD DNS, routing and required ports.'
    }
    elseif ($joined -match '(?i)0x0*52E|ERROR_LOGON_FAILURE') {
        Write-Warn 'NetSetup indicates credential/logon failure. Verify the join identity and Kerberos time.'
    }
    elseif ($joined -match '(?i)0x0*5\b|ERROR_ACCESS_DENIED') {
        Write-Warn 'NetSetup indicates access denied. Verify delegated computer-join permissions and OU ACLs.'
    }
    else {
        Write-Warn 'NetSetup.log evidence from the attempt was captured for troubleshooting.'
    }
}

# ---------------------------------------------------------------------------
# Snapshots / transaction state
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
    $netSetupStartLine = Get-NetSetupLineCount

    $snapshot = [ordered]@{
        SnapshotVersion   = 3
        CreatedAt         = (Get-Date).ToString('o')
        SnapshotPath      = $snapshotPath
        TargetDomain      = $TargetDomain
        ComputerName      = [string]$env:COMPUTERNAME
        BootMarker        = Get-BootMarker
        PartOfDomain      = [bool]$cs.PartOfDomain
        Domain            = [string]$cs.Domain
        Workgroup         = [string]$cs.Workgroup
        ProductName       = $product.ProductName
        EditionID         = $product.EditionID
        NetSetupStartLine = $netSetupStartLine
        Interface         = $dnsState
    }

    Write-JsonAtomic -Object $snapshot -Path (Join-Path $snapshotPath 'snapshot.json')
    @(Get-NetSetupAttemptLines -StartLine 0 | Select-Object -Last 250) |
        Set-Content -LiteralPath (Join-Path $snapshotPath 'NetSetup-before.txt') -Encoding UTF8

    Write-Ok ("Pre-join snapshot created: {0}" -f $snapshotPath)
    return [pscustomobject]$snapshot
}

function Get-Snapshot {
    param([Parameter(Mandatory=$true)][string]$SnapshotPath)

    $file = Join-Path $SnapshotPath 'snapshot.json'
    if (-not (Test-Path -LiteralPath $file)) { throw "Snapshot metadata not found: $file" }
    return Get-Content -LiteralPath $file -Raw -ErrorAction Stop |
        ConvertFrom-Json -ErrorAction Stop
}

function New-JoinState {
    param(
        [Parameter(Mandatory=$true)]$Snapshot,
        [Parameter(Mandatory=$true)][string]$Domain,
        [Parameter(Mandatory=$true)][string[]]$DnsServers,
        [Parameter(Mandatory=$true)][string]$RequestedComputerName,
        [ValidateSet('Join','Switch')][string]$Operation = 'Join',
        [string]$SourceDomain = ''
    )

    $state = [ordered]@{
        StateVersion          = 4
        Operation             = $Operation
        SourceDomain          = $SourceDomain
        Phase                 = 'SNAPSHOT_CREATED'
        PhaseBootMarker       = Get-BootMarker
        TransactionStartedAt  = (Get-Date).ToString('o')
        UpdatedAt             = (Get-Date).ToString('o')
        Domain                = $Domain
        DnsServers            = @($DnsServers)
        RequestedComputerName = $RequestedComputerName
        SnapshotPath          = [string]$Snapshot.SnapshotPath
        NetSetupStartLine     = [int]$Snapshot.NetSetupStartLine
        JoinAttempted         = $false
        MembershipCommitted   = $false
    }

    Write-JsonAtomic -Object $state -Path $script:CurrentState
}

function Show-Snapshots {
    Write-Header
    Write-Ui 'RECOVERY SNAPSHOTS' Cyan
    Write-Ui ''

    $dirs = @(Get-ChildItem -LiteralPath $script:SnapshotRoot -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending)
    if ($dirs.Count -eq 0) {
        Write-Info 'No snapshots found.'
        return
    }

    $current = Get-CurrentState
    Write-Ui ('  {0,-22} {1,-28} {2,-16} {3,-22} {4}' -f 'CREATED','TARGET DOMAIN','COMPUTER','INTERFACE','STATE') Gray
    foreach ($dir in $dirs) {
        try {
            $snap = Get-Snapshot -SnapshotPath $dir.FullName
            $stateText = ''
            if ($current -and [string]$current.SnapshotPath -eq $dir.FullName) {
                $stateText = [string]$current.Phase
            }
            Write-Ui ('  {0,-22} {1,-28} {2,-16} {3,-22} {4}' -f `
                ([string]$snap.CreatedAt).Substring(0,[Math]::Min(19,([string]$snap.CreatedAt).Length)),
                [string]$snap.TargetDomain,
                [string]$snap.ComputerName,
                [string]$snap.Interface.InterfaceAlias,
                $stateText)
            Write-Ui ('    {0}' -f $dir.FullName) Gray
        }
        catch {
            Write-Warn ("Unreadable snapshot: {0}" -f $dir.FullName)
        }
    }
}

# ---------------------------------------------------------------------------
# DNS / discovery / readiness
# ---------------------------------------------------------------------------

function Test-AdDnsServers {
    param(
        [Parameter(Mandatory=$true)][string]$Domain,
        [Parameter(Mandatory=$true)][string[]]$DnsServers
    )

    $srvName = '_ldap._tcp.dc._msdcs.{0}' -f $Domain
    $adOk = $true
    $forwardingOk = $true
    $dcNames = New-Object 'System.Collections.Generic.List[string]'

    foreach ($server in $DnsServers) {
        try {
            $answers = @(Resolve-DnsName -Name $srvName -Type SRV -Server $server -DnsOnly -ErrorAction Stop |
                Where-Object { $_.Type -eq 'SRV' -and $_.NameTarget })
            if ($answers.Count -eq 0) { throw 'No SRV answer.' }
            Write-Ok ("AD DNS preflight passed through {0}." -f $server)
            foreach ($answer in $answers) {
                $dc = ([string]$answer.NameTarget).TrimEnd('.')
                if ($dc -and -not $dcNames.Contains($dc)) { $dcNames.Add($dc) | Out-Null }
            }
        }
        catch {
            Write-ErrorUi ("AD DNS {0} does not return DC locator SRV records: {1}" -f $server,$_.Exception.Message)
            $adOk = $false
            continue
        }

        try {
            $external = @(Resolve-DnsName -Name $ExternalDnsProbe -Type A -Server $server -DnsOnly -ErrorAction Stop |
                Where-Object { $_.IPAddress })
            if ($external.Count -eq 0) { throw 'No external A answer.' }
            Write-Ok ("AD DNS {0} resolves names outside the AD zone." -f $server)
        }
        catch {
            Write-Warn ("AD DNS {0} cannot resolve the external probe {1}." -f $server,$ExternalDnsProbe)
            $forwardingOk = $false
        }
    }

    return [pscustomobject]@{
        AdDiscoveryOk = $adOk
        ForwardingOk  = $forwardingOk
        DomainControllers = @($dcNames)
    }
}

function Wait-SystemAdDiscovery {
    param(
        [Parameter(Mandatory=$true)][string]$Domain,
        [int]$Attempts = 0
    )

    if ($Attempts -le 0) {
        $Attempts = [Math]::Max(8,[Math]::Ceiling($NetworkOperationTimeoutSeconds / 2))
    }

    $srvName = '_ldap._tcp.dc._msdcs.{0}' -f $Domain
    for ($i = 1; $i -le $Attempts; $i++) {
        try {
            $answers = @(Resolve-DnsName -Name $srvName -Type SRV -DnsOnly -ErrorAction Stop |
                Where-Object { $_.Type -eq 'SRV' -and $_.NameTarget })
            if ($answers.Count -gt 0) { return $true }
        }
        catch {}
        Start-Sleep -Seconds 2
    }
    return $false
}

function Test-AdNetworkReadiness {
    param([Parameter(Mandatory=$true)][string]$DomainController)

    Write-Ui ''
    Write-Ui ("AD NETWORK READINESS - {0}" -f $DomainController) Cyan

    $required = @(
        @{Name='DNS';Port=53},
        @{Name='Kerberos';Port=88},
        @{Name='RPC';Port=135},
        @{Name='LDAP';Port=389},
        @{Name='SMB';Port=445}
    )
    $optional = @(
        @{Name='Kerberos password';Port=464},
        @{Name='Global Catalog';Port=3268}
    )

    $all = $true
    foreach ($check in $required) {
        if (Test-TcpPort -ComputerName $DomainController -Port $check.Port) {
            Write-Ok ("{0}/TCP {1} reachable." -f $check.Name,$check.Port)
        }
        else {
            Write-ErrorUi ("{0}/TCP {1} is not reachable." -f $check.Name,$check.Port)
            $all = $false
        }
    }

    foreach ($check in $optional) {
        if (Test-TcpPort -ComputerName $DomainController -Port $check.Port) {
            Write-Ok ("{0}/TCP {1} reachable." -f $check.Name,$check.Port)
        }
        else {
            Write-Warn ("{0}/TCP {1} is not reachable from this path." -f $check.Name,$check.Port)
        }
    }

    Write-Info 'Dynamic RPC ports are validated by the actual Windows domain-join operation.'
    return $all
}

function Test-TimeState {
    if (-not (Get-Command w32tm.exe -ErrorAction SilentlyContinue)) { return $true }

    $status = & w32tm.exe /query /status 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Ok 'Windows Time status is available.'
        return $true
    }

    Write-Warn 'Windows Time is not currently reporting synchronized status.'
    Write-Warn 'Kerberos is sensitive to clock skew; verify time if authentication fails.'
    return $false
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

function Set-DomainDns {
    param(
        [Parameter(Mandatory=$true)][uint32]$InterfaceIndex,
        [Parameter(Mandatory=$true)][string[]]$DnsServers
    )

    if (Test-RemoteSession) {
        Write-Warn 'Remote/RDP session detected. DNS changes normally preserve an existing IP session,'
        Write-Warn 'but incorrect DNS can prevent reconnecting by hostname.'
    }

    Set-DnsClientServerAddress -InterfaceIndex $InterfaceIndex -ServerAddresses $DnsServers -ErrorAction Stop
    Clear-DnsClientCache -ErrorAction SilentlyContinue
    Write-Ok ("AD DNS configured: {0}" -f ($DnsServers -join ', '))

    $v6 = @(Get-DnsClientServerAddress -InterfaceIndex $InterfaceIndex -AddressFamily IPv6 -ErrorAction SilentlyContinue).ServerAddresses
    if ($v6.Count -gt 0) {
        Write-Warn ("IPv6 DNS servers are also present on this interface: {0}" -f ($v6 -join ', '))
        Write-Warn 'Ensure they can resolve the AD zone or correct them through the network policy that owns IPv6.'
    }
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
    Write-Info ("Restoring DNS on {0} (ifIndex {1})." -f $adapter.Name,$index)

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
    if ($env:COMPUTERNAME -ieq $oldName) { return $true }

    try {
        Rename-Computer -NewName $oldName -Force -ErrorAction Stop
        Write-Ok ("Computer name restoration scheduled: {0}" -f $oldName)
        return $true
    }
    catch {
        Write-Warn ("Computer name could not be restored yet: {0}" -f $_.Exception.Message)
        return $false
    }
}

# ---------------------------------------------------------------------------
# Join validation and lifecycle observation
# ---------------------------------------------------------------------------

function Test-PostJoinAcceptance {
    param([Parameter(Mandatory=$true)][string]$Domain)

    $fail = $false
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop

    if ($cs.PartOfDomain -and $cs.Domain -ieq $Domain) {
        Write-Ok 'Windows reports the expected domain membership.'
    }
    else {
        Write-ErrorUi ("Windows domain membership is not {0}." -f $Domain)
        $fail = $true
    }

    try {
        if (Test-ComputerSecureChannel -ErrorAction Stop) {
            Write-Ok 'Computer secure channel is healthy.'
        }
        else {
            Write-ErrorUi 'Computer secure channel test returned False.'
            $fail = $true
        }
    }
    catch {
        Write-ErrorUi ("Secure channel validation failed: {0}" -f $_.Exception.Message)
        $fail = $true
    }

    if (Get-Command nltest.exe -ErrorAction SilentlyContinue) {
        & nltest.exe "/dsgetdc:$Domain" 2>&1 | ForEach-Object { Write-Ui ([string]$_) Gray }
        if ($LASTEXITCODE -ne 0) { $fail = $true }
        & nltest.exe "/sc_verify:$Domain" 2>&1 | ForEach-Object { Write-Ui ([string]$_) Gray }
        if ($LASTEXITCODE -ne 0) { $fail = $true }
    }

    if (Wait-SystemAdDiscovery -Domain $Domain -Attempts 2) {
        Write-Ok 'System resolver can discover AD DC locator records.'
    }
    else {
        Write-ErrorUi 'System resolver cannot discover AD DC locator records.'
        $fail = $true
    }

    [void](Test-TimeState)
    return (-not $fail)
}

function Sync-LifecycleState {
    # This function only reconciles lifecycle metadata and performs acceptance
    # checks. It does not restore DNS, rename the host, unjoin, or change AD.
    $state = Get-CurrentState
    if (-not $state -or -not $state.PSObject.Properties['Phase']) { return }

    $phase = [string]$state.Phase
    $currentBoot = Get-BootMarker
    $phaseBoot = if ($state.PSObject.Properties['PhaseBootMarker']) { [string]$state.PhaseBootMarker } else { '' }

    if ($phase -in @('JOIN_SUBMITTED','JOIN_AMBIGUOUS')) {
        $startLine = if ($state.PSObject.Properties['NetSetupStartLine']) { [int]$state.NetSetupStartLine } else { 0 }
        $evidence = Get-JoinCommitEvidence -Domain ([string]$state.Domain) -NetSetupStartLine $startLine
        if ($evidence.Outcome -eq 'Accepted') {
            [void](Set-CurrentStateValues -Values @{
                Phase='JOIN_PENDING_REBOOT'
                PhaseBootMarker=$currentBoot
                MembershipCommitted=$true
            })
            Write-Warn 'A previously interrupted join now has acceptance evidence. Keep AD DNS and reboot before final validation.'
            return
        }
    }

    if ($phase -eq 'JOINED_DEGRADED') {
        Write-Info 'Re-checking previously degraded domain membership.'
        if (Test-PostJoinAcceptance -Domain ([string]$state.Domain)) {
            [void](Set-CurrentStateValues -Values @{Phase='JOINED';PhaseBootMarker=$currentBoot;MembershipCommitted=$true})
            Write-Ok 'The repaired client now passes domain acceptance checks.'
        }
        return
    }

    if ($phase -eq 'JOIN_PENDING_REBOOT' -and $phaseBoot -and $phaseBoot -ne $currentBoot) {
        Write-Info 'Post-reboot join transition detected; running final acceptance checks.'
        if (Test-PostJoinAcceptance -Domain ([string]$state.Domain)) {
            [void](Set-CurrentStateValues -Values @{Phase='JOINED';PhaseBootMarker=$currentBoot;MembershipCommitted=$true})
            Write-Ok 'Post-reboot domain acceptance passed.'
        }
        else {
            [void](Set-CurrentStateValues -Values @{Phase='JOINED_DEGRADED';PhaseBootMarker=$currentBoot;MembershipCommitted=$true})
            Write-Warn 'Domain membership exists but one or more post-reboot checks are degraded.'
        }
        return
    }

    if ($phase -eq 'LEAVE_PENDING_REBOOT' -and $phaseBoot -and $phaseBoot -ne $currentBoot) {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        if (-not $cs.PartOfDomain) {
            [void](Set-CurrentStateValues -Values @{Phase='RESTORE_READY';PhaseBootMarker=$currentBoot})
            Write-Info 'Domain leave completed after reboot. Pre-join local state is ready to restore.'
        }
        else {
            Write-Warn ("The leave reboot occurred, but Windows still reports domain membership: {0}." -f $cs.Domain)
        }
        return
    }

    if ($phase -eq 'RESTORE_PENDING_REBOOT' -and $phaseBoot -and $phaseBoot -ne $currentBoot) {
        try {
            $snap = Get-Snapshot -SnapshotPath ([string]$state.SnapshotPath)
            $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
            if (-not $cs.PartOfDomain -and $env:COMPUTERNAME -ieq [string]$snap.ComputerName) {
                Remove-CurrentState
                Write-Ok 'Pre-join hostname restoration completed after reboot.'
            }
            else {
                Write-Warn 'Post-restore reboot occurred, but the original local identity is not fully materialized.'
            }
        }
        catch {
            Write-Warn ("Could not finalize restore lifecycle: {0}" -f $_.Exception.Message)
        }
    }
}

# ---------------------------------------------------------------------------
# Audit / status
# ---------------------------------------------------------------------------

function Get-RemoteManagementReadiness {
    $result = [ordered]@{
        OpenSshInstalled = $false
        SshdService      = $false
        SshdRunning      = $false
        SshdAutomatic    = $false
        FirewallRule     = $false
        Tcp22Listening   = $false
        WinRMRunning     = $false
    }

    try {
        $cap = Get-WindowsCapability -Online -Name 'OpenSSH.Server*' -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($cap -and $cap.State -eq 'Installed') { $result.OpenSshInstalled = $true }
    }
    catch {}

    $svc = Get-Service -Name sshd -ErrorAction SilentlyContinue
    if ($svc) {
        $result.SshdService = $true
        $result.SshdRunning = ($svc.Status -eq 'Running')
        try {
            $svcCim = Get-CimInstance Win32_Service -Filter "Name='sshd'" -ErrorAction Stop
            $result.SshdAutomatic = ($svcCim.StartMode -eq 'Auto')
        }
        catch {}
    }

    try {
        $rules = @(Get-NetFirewallRule -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -eq 'AD Client Assistant - OpenSSH' -or $_.Name -eq 'OpenSSH-Server-In-TCP' })
        $result.FirewallRule = ($rules.Count -gt 0 -and @($rules | Where-Object Enabled -eq 'True').Count -gt 0)
    }
    catch {}

    try {
        $result.Tcp22Listening = @(
            Get-NetTCPConnection -State Listen -LocalPort 22 -ErrorAction SilentlyContinue
        ).Count -gt 0
    }
    catch {}

    $winrm = Get-Service -Name WinRM -ErrorAction SilentlyContinue
    if ($winrm) { $result.WinRMRunning = ($winrm.Status -eq 'Running') }

    return [pscustomobject]$result
}

function Show-RemoteManagementReadiness {
    Write-Ui ''
    Write-Ui 'REMOTE MANAGEMENT READINESS' Cyan
    $r = Get-RemoteManagementReadiness

    if ($r.OpenSshInstalled) { Write-Ok 'OpenSSH Server capability is installed.' }
    else { Write-Warn 'OpenSSH Server capability is not installed.' }

    if ($r.SshdRunning) { Write-Ok 'sshd service is running.' }
    elseif ($r.SshdService) { Write-Warn 'sshd service exists but is not running.' }
    else { Write-Warn 'sshd service is not installed.' }

    if ($r.SshdAutomatic) { Write-Ok 'sshd startup type is Automatic.' }
    elseif ($r.SshdService) { Write-Warn 'sshd startup type is not Automatic.' }

    if ($r.Tcp22Listening) { Write-Ok 'TCP/22 is listening locally.' }
    else { Write-Warn 'TCP/22 is not listening locally.' }

    if ($r.FirewallRule) { Write-Ok 'An enabled inbound OpenSSH firewall rule exists.' }
    else { Write-Warn 'No enabled inbound OpenSSH firewall rule was detected.' }

    if ($r.WinRMRunning) { Write-Info 'WinRM is also running; Windows-native administration is available where policy permits.' }
    else { Write-Info 'WinRM is not required by the Debian remote-operations console; OpenSSH is its primary full-control transport.' }

    return $r
}

function Enable-RemoteManagementReadiness {
    [CmdletBinding()]
    param([switch]$NonInteractive)

    if (-not $NonInteractive) {
        if (-not (Confirm-Choice -Prompt 'Enable remote administration readiness (OpenSSH Server) on this domain client?' -Default Y)) {
            Write-Info 'Remote administration setup skipped.'
            return $false
        }
    }

    Write-Ui ''
    Write-Ui 'REMOTE MANAGEMENT SETUP' Cyan

    $cap = $null
    try {
        $cap = Get-WindowsCapability -Online -Name 'OpenSSH.Server*' -ErrorAction Stop |
            Select-Object -First 1
    }
    catch {
        Write-Warn ("Unable to query OpenSSH capability: {0}" -f $_.Exception.Message)
    }

    if (-not $cap -or $cap.State -ne 'Installed') {
        Write-Info 'Installing Windows OpenSSH Server capability. This may take time on WSUS/FOD-backed systems.'
        try {
            Add-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0' -ErrorAction Stop | Out-Null
            Write-Ok 'OpenSSH Server capability installed.'
        }
        catch {
            Write-ErrorUi ("OpenSSH Server installation failed: {0}" -f $_.Exception.Message)
            Write-Warn 'Domain membership is unaffected. Install the Windows OpenSSH Server capability manually and rerun Remote Setup.'
            return $false
        }
    }

    try {
        Set-Service -Name sshd -StartupType Automatic -ErrorAction Stop
        Start-Service -Name sshd -ErrorAction Stop
        Write-Ok 'sshd enabled and started.'
    }
    catch {
        Write-ErrorUi ("Unable to start/configure sshd: {0}" -f $_.Exception.Message)
        return $false
    }

    try {
        $existing = Get-NetFirewallRule -DisplayName 'AD Client Assistant - OpenSSH' -ErrorAction SilentlyContinue
        if (-not $existing) {
            New-NetFirewallRule `
                -DisplayName 'AD Client Assistant - OpenSSH' `
                -Direction Inbound `
                -Action Allow `
                -Protocol TCP `
                -LocalPort 22 `
                -Profile Domain,Private `
                -ErrorAction Stop | Out-Null
        }
        else {
            $existing | Enable-NetFirewallRule -ErrorAction SilentlyContinue | Out-Null
        }
        Write-Ok 'OpenSSH inbound firewall rule enabled for Domain/Private profiles.'
    }
    catch {
        Write-Warn ("Could not configure the OpenSSH firewall rule: {0}" -f $_.Exception.Message)
    }

    [void](Show-RemoteManagementReadiness)
    Write-Info 'No local/domain account was granted additional administrator rights by this setup.'
    return $true
}

function Invoke-ReadinessAudit {
    Write-Header
    Write-Ui 'CLIENT READINESS' Cyan
    Write-Ui ''

    $product = Get-ProductInfo
    Write-Ui ("Windows       : {0}" -f $product.ProductName)
    Write-Ui ("Edition ID    : {0}" -f $product.EditionID)
    Write-Ui ("Remote session: {0}" -f (Test-RemoteSession))

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

    [void](Test-TimeState)
    [void](Show-RemoteManagementReadiness)

    $state = Get-CurrentState
    if ($state) {
        Write-Warn ("Assistant-managed lifecycle exists: {0} / {1}." -f $state.Domain,$state.Phase)
        if ([string]$state.Phase -in @('SNAPSHOT_CREATED','DNS_APPLIED','JOIN_SUBMITTED','JOIN_AMBIGUOUS','RESTORE_READY')) {
            Write-Warn 'Review -Mode Recover before starting another domain lifecycle operation.'
        }
    }
    else {
        Write-Info 'No assistant-managed lifecycle state exists.'
    }
}

function Invoke-Status {
    Sync-LifecycleState
    Write-Header
    Write-Ui 'DOMAIN CLIENT STATUS' Cyan
    Write-Ui ''

    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    Write-Ui ("Computer      : {0}" -f $env:COMPUTERNAME)
    Write-Ui ("PartOfDomain  : {0}" -f $cs.PartOfDomain)
    Write-Ui ("Domain/Group  : {0}" -f $(if ($cs.PartOfDomain) { $cs.Domain } else { $cs.Workgroup }))

    if ($cs.PartOfDomain) {
        try {
            if (Test-ComputerSecureChannel -ErrorAction Stop) { Write-Ok 'Computer secure channel is healthy.' }
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
        Write-Ui 'Assistant lifecycle:' Cyan
        Write-Ui ("  Phase    : {0}" -f $state.Phase)
        Write-Ui ("  Domain   : {0}" -f $state.Domain)
        Write-Ui ("  DNS      : {0}" -f (@($state.DnsServers) -join ', '))
        Write-Ui ("  Snapshot : {0}" -f $state.SnapshotPath)
        if ([string]$state.Phase -eq 'RESTORE_READY') {
            Write-Warn 'Domain leave is complete. Run -Mode Restore (or Recover) to restore pre-join DNS/hostname.'
        }
        elseif ([string]$state.Phase -eq 'JOIN_PENDING_REBOOT') {
            Write-Warn 'Final domain acceptance is pending a reboot.'
        }
        elseif ([string]$state.Phase -eq 'JOIN_AMBIGUOUS') {
            Write-Warn 'Join commit state is ambiguous. Run -Mode Recover before changing DNS.'
        }
    }

    [void](Test-TimeState)
}

# ---------------------------------------------------------------------------
# IT administrator diagnostics / domain transition
# ---------------------------------------------------------------------------

function Test-DomainDnsThroughServers {
    param(
        [Parameter(Mandatory=$true)][string]$Domain,
        [Parameter(Mandatory=$true)][string[]]$DnsServers
    )

    $srv = '_ldap._tcp.dc._msdcs.{0}' -f $Domain
    $ok = $true
    foreach ($server in $DnsServers) {
        try {
            $answers = @(Resolve-DnsName -Name $srv -Type SRV -Server $server -DnsOnly -ErrorAction Stop |
                Where-Object { $_.Type -eq 'SRV' -and $_.NameTarget })
            if ($answers.Count -eq 0) { throw 'No DC locator SRV records returned.' }
            Write-Ok ("DNS {0} resolves {1}." -f $server,$Domain)
        }
        catch {
            Write-ErrorUi ("DNS {0} cannot resolve {1}: {2}" -f $server,$Domain,$_.Exception.Message)
            $ok = $false
        }
    }
    return $ok
}

function Invoke-ConnectivityTest {
    Sync-LifecycleState
    Write-Header
    Write-Ui 'AD CONNECTIVITY TEST' Cyan
    Write-Ui ''

    $state = Get-CurrentState
    $defaultDomain = if ($state -and $state.Domain) { [string]$state.Domain } else {
        try { $c = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop; if ($c.PartOfDomain) { [string]$c.Domain } else { '' } } catch { '' }
    }
    $defaultDns = if ($state -and $state.DnsServers) { (@($state.DnsServers) -join ',') } else { '' }

    $domain = (Read-Value -Prompt 'AD DNS domain (for example corp.example.com)' -Default $defaultDomain).ToLowerInvariant()
    if (-not (Test-DnsDomainName -Name $domain)) { Write-ErrorUi 'A valid AD DNS domain is required.'; return }
    $dnsServers = @(Parse-DnsInput -Text (Read-Value -Prompt 'AD DNS server IPv4 addresses (comma separated)' -Default $defaultDns))
    if (-not (Test-IPv4AddressList -Addresses $dnsServers)) { Write-ErrorUi 'At least one valid IPv4 AD DNS server is required.'; return }

    $dns = Test-AdDnsServers -Domain $domain -DnsServers $dnsServers
    $iface = Select-NetworkInterface -RemoteIPAddress $dnsServers[0]
    $dcName = @($dns.DomainControllers | Select-Object -First 1)
    $portsOk = $false
    if ($dcName.Count -gt 0) { $portsOk = Test-AdNetworkReadiness -DomainController ([string]$dcName[0]) }
    $timeOk = Test-TimeState

    Write-Ui ''
    Write-Ui 'SYSTEM RESOLVER' Cyan
    if (Wait-SystemAdDiscovery -Domain $domain -Attempts 2) { Write-Ok 'System resolver can discover Active Directory.' }
    else { Write-Warn 'System resolver cannot currently discover the domain.' }

    Write-Ui ''
    Write-Ui 'MEMBERSHIP / SECURE CHANNEL' Cyan
    try {
        $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
        if ($cs.PartOfDomain) {
            Write-Ok ("Current domain membership: {0}" -f $cs.Domain)
            try {
                if (Test-ComputerSecureChannel -ErrorAction Stop) { Write-Ok 'Windows secure channel is healthy.' }
                else { Write-Warn 'Windows secure channel test returned false.' }
            } catch { Write-Warn ("Secure-channel test could not complete: {0}" -f $_.Exception.Message) }
        } else { Write-Info 'Computer is not currently domain joined.' }
    } catch {}

    Write-Ui ''
    if ($dns.AdDiscoveryOk -and $portsOk -and $timeOk) { Write-Ok 'READY: AD DNS, required ports and local time checks passed.' }
    else { Write-ErrorUi 'BLOCKED/DEGRADED: one or more readiness checks failed.' }
}

function Invoke-Troubleshoot {
    Sync-LifecycleState
    Write-Header
    Write-Ui 'AD TROUBLESHOOTER' Cyan
    Write-Ui ''

    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    Write-Ui ("Computer : {0}" -f $env:COMPUTERNAME)
    if ($cs) { Write-Ui ("Identity : {0}" -f $(if ($cs.PartOfDomain) { $cs.Domain } else { $cs.Workgroup })) }
    Write-Ui ("Lifecycle: {0}" -f (Get-LifecycleLabel))

    Write-Ui ''
    Write-Ui 'NETWORK' Cyan
    Get-NetIPConfiguration -ErrorAction SilentlyContinue | ForEach-Object {
        $dns = @($_.DNSServer.ServerAddresses) -join ','
        Write-Ui ("  {0} ifIndex={1} IPv4={2} DNS={3}" -f $_.InterfaceAlias,$_.InterfaceIndex,(@($_.IPv4Address.IPAddress) -join ','),$dns)
    }

    Write-Ui ''
    Write-Ui 'SECURE CHANNEL' Cyan
    if ($cs -and $cs.PartOfDomain) {
        $secure = $false
        try { $secure = Test-ComputerSecureChannel -ErrorAction Stop } catch { Write-Warn $_.Exception.Message }
        if ($secure) { Write-Ok 'Secure channel is healthy.' }
        else {
            Write-ErrorUi 'Secure channel is unhealthy or could not be validated.'
            if (Confirm-Choice -Prompt 'Attempt secure-channel repair with explicit domain credentials?' -Default N) {
                $user = Read-Value -Prompt 'Join account' -Default ("Administrator@{0}" -f $cs.Domain)
                $cred = Get-Credential -UserName $user -Message ("Credentials authorized to repair secure channel for {0}" -f $cs.Domain)
                if ($cred) {
                    try {
                        if (Test-ComputerSecureChannel -Repair -Credential $cred -ErrorAction Stop) { Write-Ok 'Secure channel repaired.' }
                        else { Write-ErrorUi 'Windows did not confirm secure-channel repair.' }
                    } catch { Write-ErrorUi ("Secure-channel repair failed: {0}" -f $_.Exception.Message) }
                }
            }
        }
    } else { Write-Info 'Secure-channel test is not applicable while off-domain.' }

    Write-Ui ''
    Write-Ui 'NETSETUP DIAGNOSTICS' Cyan
    $state = Get-CurrentState
    $start = if ($state -and $state.PSObject.Properties['NetSetupStartLine']) { [int]$state.NetSetupStartLine } else { 0 }
    Write-NetSetupDiagnosis -SnapshotPath $(if ($state) { [string]$state.SnapshotPath } else { '' }) -StartLine $start

    if (Confirm-Choice -Prompt 'Flush DNS client cache and restart Netlogon now?' -Default N) {
        try { Clear-DnsClientCache -ErrorAction Stop; Write-Ok 'DNS client cache cleared.' } catch { Write-Warn $_.Exception.Message }
        if (Get-Service Netlogon -ErrorAction SilentlyContinue) {
            try { Restart-Service Netlogon -Force -ErrorAction Stop; Write-Ok 'Netlogon restarted.' } catch { Write-Warn $_.Exception.Message }
        }
    }
}

function Export-DiagnosticBundle {
    Sync-LifecycleState
    Write-Header
    Write-Ui 'EXPORT DIAGNOSTIC BUNDLE' Cyan
    Write-Ui ''

    $root = Join-Path $script:ReportRoot ("diagnostic-{0}" -f $script:RunId)
    $zip = "{0}.zip" -f $root
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    try {
        Get-ComputerInfo -ErrorAction SilentlyContinue | Out-File (Join-Path $root 'computer-info.txt') -Width 240 -Encoding utf8
        Get-NetIPConfiguration -Detailed -ErrorAction SilentlyContinue | Out-File (Join-Path $root 'network.txt') -Width 240 -Encoding utf8
        Get-NetRoute -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Format-Table -AutoSize | Out-String -Width 240 | Set-Content (Join-Path $root 'routes.txt') -Encoding utf8
        Get-DnsClientServerAddress -ErrorAction SilentlyContinue | Format-List * | Out-String -Width 240 | Set-Content (Join-Path $root 'dns.txt') -Encoding utf8
        $state = Get-CurrentState
        if ($state) { $state | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $root 'lifecycle.json') -Encoding utf8 }
        @(Get-NetSetupAttemptLines -StartLine 0 | Select-Object -Last 500) | Set-Content (Join-Path $root 'NetSetup-tail.txt') -Encoding utf8
        try { Test-ComputerSecureChannel -Verbose 4>&1 | Out-File (Join-Path $root 'secure-channel.txt') -Encoding utf8 } catch { $_ | Out-File (Join-Path $root 'secure-channel.txt') -Encoding utf8 }
        Compress-Archive -Path (Join-Path $root '*') -DestinationPath $zip -Force
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        Write-Ok ("Diagnostic bundle created: {0}" -f $zip)
        Write-Warn 'Review the archive before sharing; it contains host/network/domain metadata. Credentials are not collected.'
    }
    catch { Write-ErrorUi ("Diagnostic bundle export failed: {0}" -f $_.Exception.Message) }
}

function Invoke-DomainSwitch {
    Sync-LifecycleState
    Write-Header
    Write-Ui 'GUIDED DOMAIN SWITCH' Cyan
    Write-Ui ''

    if (-not (Test-DomainJoinEdition)) { return }
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    if (-not $cs.PartOfDomain) { Write-Info 'Computer is not domain joined; starting normal guided join.'; Invoke-GuidedJoin; return }

    $existing = Get-CurrentState
    if ($existing -and [string]$existing.Phase -notin @('JOINED','JOINED_DEGRADED')) {
        Write-ErrorUi ("Unfinished lifecycle exists: {0}. Recover it before switching domains." -f $existing.Phase); return
    }

    $sourceDomain = [string]$cs.Domain
    $targetDomain = (Read-Value -Prompt 'Target AD DNS domain (for example corp.example.com)' -Default '').ToLowerInvariant()
    if (-not (Test-DnsDomainName -Name $targetDomain) -or $targetDomain -ieq $sourceDomain) { Write-ErrorUi 'A different valid target domain is required.'; return }
    $dnsServers = @(Parse-DnsInput -Text (Read-Value -Prompt 'Target AD DNS server IPv4 addresses (comma separated)' -Default ''))
    if (-not (Test-IPv4AddressList -Addresses $dnsServers)) { Write-ErrorUi 'At least one valid target AD DNS IPv4 address is required.'; return }

    $targetPreflight = Test-AdDnsServers -Domain $targetDomain -DnsServers $dnsServers
    if (-not $targetPreflight.AdDiscoveryOk) { Write-ErrorUi 'Target AD DNS discovery failed. Nothing was changed.'; return }
    if (-not $targetPreflight.ForwardingOk -and -not $AllowAdDnsWithoutExternalResolution) { Write-ErrorUi 'Target AD DNS external forwarding check failed.'; return }
    if (-not (Test-DomainDnsThroughServers -Domain $sourceDomain -DnsServers $dnsServers)) {
        Write-ErrorUi 'Target DNS cannot resolve the source domain. Configure conditional forwarding/coexistence before an automated switch.'; return
    }

    $iface = Select-NetworkInterface -RemoteIPAddress $dnsServers[0]
    $targetDc = @($targetPreflight.DomainControllers | Select-Object -First 1)
    if ($targetDc.Count -eq 0) { Write-ErrorUi 'No target DC FQDN was discovered.'; return }
    $targetDcName = ([string]$targetDc[0]).TrimEnd('.')
    if (-not (Test-AdNetworkReadiness -DomainController $targetDcName)) { Write-ErrorUi 'Target-domain required ports are not reachable.'; return }
    [void](Test-TimeState); [void](Test-TimeAgainstDomainController -ComputerName $targetDcName)

    $sourceUser = Read-Value -Prompt 'Source-domain unjoin account' -Default ("Administrator@{0}" -f $sourceDomain)
    $targetUser = Read-Value -Prompt 'Target-domain join account' -Default ("Administrator@{0}" -f $targetDomain)
    $ouPath = Read-Value -Prompt 'Computer OU DN (optional)' -Default ''
    $requestedName = Read-Value -Prompt 'Computer name' -Default $env:COMPUTERNAME
    if (-not (Test-ComputerNameValue -Name $requestedName)) { Write-ErrorUi 'Invalid computer name.'; return }

    Write-Ui ''
    Write-Ui ("  Source domain : {0}" -f $sourceDomain)
    Write-Ui ("  Target domain : {0}" -f $targetDomain)
    Write-Ui ("  Target DC     : {0}" -f $targetDcName)
    Write-Ui ("  Target DNS    : {0}" -f ($dnsServers -join ', '))
    Write-Ui ("  Computer      : {0}" -f $requestedName)
    Write-Ui '  Transition    : direct domain-to-domain, one reboot, no stored passwords' Gray
    if (-not (Confirm-Literal -Prompt 'The computer will move directly to the target domain after all preflight checks passed.' -Literal 'SWITCH')) { return }

    $sourceCredential = Get-Credential -UserName $sourceUser -Message ("Credentials authorized to unjoin from {0}" -f $sourceDomain)
    if (-not $sourceCredential) { return }
    $targetCredential = Get-Credential -UserName $targetUser -Message ("Credentials authorized to join {0}" -f $targetDomain)
    if (-not $targetCredential) { return }

    $snapshot = New-PreJoinSnapshot -Interface $iface -TargetDomain $targetDomain
    New-JoinState -Snapshot $snapshot -Domain $targetDomain -DnsServers $dnsServers -RequestedComputerName $requestedName -Operation Switch -SourceDomain $sourceDomain

    try {
        Set-DomainDns -InterfaceIndex ([uint32]$iface.InterfaceIndex) -DnsServers $dnsServers
        [void](Set-CurrentStateValues -Values @{Phase='DNS_APPLIED';PhaseBootMarker=(Get-BootMarker)})
        if (-not (Wait-SystemAdDiscovery -Domain $targetDomain)) { throw 'System resolver cannot discover target AD after applying target DNS.' }
        if (-not (Wait-SystemAdDiscovery -Domain $sourceDomain)) { throw 'Target DNS stopped resolving source AD after resolver transition.' }

        [void](Set-CurrentStateValues -Values @{Phase='JOIN_SUBMITTED';PhaseBootMarker=(Get-BootMarker);JoinAttempted=$true})
        $params = @{
            DomainName=$targetDomain; Server=$targetDcName; Credential=$targetCredential;
            UnjoinDomainCredential=$sourceCredential; PassThru=$true; Force=$true; ErrorAction='Stop'
        }
        if ($ouPath) { $params.OUPath = $ouPath }
        if ($requestedName -ine $env:COMPUTERNAME) { $params.NewName = $requestedName }
        $result = Add-Computer @params
        if ($result -and $result.PSObject.Properties['HasSucceeded'] -and -not $result.HasSucceeded) { throw 'Add-Computer returned HasSucceeded=False.' }
        [void](Set-CurrentStateValues -Values @{Phase='JOIN_PENDING_REBOOT';PhaseBootMarker=(Get-BootMarker);MembershipCommitted=$true})
        Write-Ok 'Windows accepted the direct domain-to-domain transition.'
        [void](Enable-RemoteManagementReadiness)
        Write-Warn 'Target AD DNS is retained until reboot and secure-channel validation.'
        if (Confirm-Choice -Prompt 'Restart now?' -Default N) { $script:RunOutcome='REBOOT_REQUESTED'; Write-RunReport; Restart-Computer -Force }
    }
    catch {
        Write-ErrorUi ("Domain switch stopped: {0}" -f $_.Exception.Message)
        $state = Get-CurrentState
        $phase = if ($state) { [string]$state.Phase } else { '' }
        if ($phase -in @('SNAPSHOT_CREATED','DNS_APPLIED')) {
            try { Restore-DnsFromSnapshot -Snapshot $snapshot; Remove-CurrentState; Write-Ok 'Pre-switch DNS restored; membership transition was not submitted.' } catch { Write-ErrorUi $_.Exception.Message }
        }
        else {
            Write-NetSetupDiagnosis -SnapshotPath ([string]$snapshot.SnapshotPath) -StartLine ([int]$snapshot.NetSetupStartLine)
            $evidence = Get-JoinCommitEvidence -Domain $targetDomain -NetSetupStartLine ([int]$snapshot.NetSetupStartLine)
            if ($evidence.Outcome -eq 'Accepted') {
                [void](Set-CurrentStateValues -Values @{Phase='JOIN_PENDING_REBOOT';PhaseBootMarker=(Get-BootMarker);MembershipCommitted=$true})
                Write-Warn 'Target-domain acceptance evidence exists. Keep target DNS and reboot.'
            } elseif ($evidence.Outcome -eq 'Failed') {
                Write-ErrorUi 'Windows reported an explicit transition failure. Membership may still require operator verification before DNS rollback.'
                Write-Warn 'Run Recover/Status and inspect NetSetup evidence before another membership operation.'
            } else {
                [void](Set-CurrentStateValues -Values @{Phase='JOIN_AMBIGUOUS';PhaseBootMarker=(Get-BootMarker)})
                Write-ErrorUi 'Domain-switch membership state is ambiguous. Automatic rollback is blocked intentionally.'
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Guided join
# ---------------------------------------------------------------------------

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

    $existingState = Get-CurrentState
    if ($existingState) {
        Write-ErrorUi ("Assistant lifecycle already exists: {0}." -f $existingState.Phase)
        Write-Warn 'Run -Mode Recover, Restore, or Status before starting another join.'
        return
    }

    $domain = (Read-Value -Prompt 'AD DNS domain (for example corp.example.com)' -Default '').ToLowerInvariant()
    if (-not (Test-DnsDomainName -Name $domain)) {
        Write-ErrorUi 'A valid DNS domain is required.'
        return
    }

    $dnsText = Read-Value -Prompt 'AD DNS server IPv4 addresses (comma separated)' -Default ''
    $dnsServers = @(Parse-DnsInput -Text $dnsText)
    if (-not (Test-IPv4AddressList -Addresses $dnsServers)) {
        Write-ErrorUi 'At least one valid IPv4 AD DNS server address is required.'
        return
    }

    Write-Ui ''
    Write-Ui 'DIRECT DNS PREFLIGHT' Cyan
    $dnsPreflight = Test-AdDnsServers -Domain $domain -DnsServers $dnsServers
    if (-not $dnsPreflight.AdDiscoveryOk) {
        Write-ErrorUi 'At least one configured DNS server cannot locate the target Active Directory domain.'
        Write-ErrorUi 'No local DNS change has been made.'
        return
    }

    if (-not $dnsPreflight.ForwardingOk -and -not $AllowAdDnsWithoutExternalResolution) {
        Write-ErrorUi 'One or more AD DNS servers cannot resolve the configured external probe.'
        Write-Warn 'Do not add public DNS as a client fallback; repair forwarding on the AD DNS service instead.'
        Write-Warn 'For an intentionally isolated network, rerun with -AllowAdDnsWithoutExternalResolution.'
        return
    }
    elseif (-not $dnsPreflight.ForwardingOk) {
        Write-Warn 'Continuing without external DNS resolution because the explicit override switch was supplied.'
    }

    $iface = Select-NetworkInterface -RemoteIPAddress $dnsServers[0]
    $joinUser = Read-Value -Prompt 'Join account' -Default ("Administrator@{0}" -f $domain)
    $ouPath = Read-Value -Prompt 'Computer OU DN (optional)' -Default ''
    if ($ouPath -and $ouPath -notmatch '^(?i:OU|CN)=') {
        Write-Warn 'OU path does not look like a distinguished name beginning with OU= or CN=.'
        if (-not (Confirm-Choice -Prompt 'Use this OU value anyway?' -Default N)) { return }
    }

    $requestedName = Read-Value -Prompt 'Computer name' -Default $env:COMPUTERNAME
    if (-not (Test-ComputerNameValue -Name $requestedName)) {
        Write-ErrorUi 'Computer name must be 1-15 characters using letters, digits or hyphen.'
        return
    }

    Write-Ui ''
    Write-Ui 'PLAN' Cyan
    Write-Ui ("  Domain       : {0}" -f $domain)
    Write-Ui ("  Interface    : {0} / ifIndex {1}" -f $iface.InterfaceAlias,$iface.InterfaceIndex)
    Write-Ui ("  DNS          : {0}" -f ($dnsServers -join ', '))
    Write-Ui ("  Computer     : {0}" -f $requestedName)
    Write-Ui ("  Join account : {0}" -f $joinUser)
    Write-Ui ("  OU           : {0}" -f $(if ($ouPath) { $ouPath } else { '(default container)' }))
    Write-Ui '  Rollback     : automatic only before membership commit; commit-aware after Add-Computer starts' Gray

    if (-not (Confirm-Choice -Prompt 'Create a recovery snapshot and continue?' -Default Y)) { return }

    $snapshot = New-PreJoinSnapshot -Interface $iface -TargetDomain $domain
    New-JoinState -Snapshot $snapshot -Domain $domain -DnsServers $dnsServers -RequestedComputerName $requestedName

    try {
        Set-DomainDns -InterfaceIndex ([uint32]$iface.InterfaceIndex) -DnsServers $dnsServers
        [void](Set-CurrentStateValues -Values @{Phase='DNS_APPLIED';PhaseBootMarker=(Get-BootMarker)})

        if (-not (Wait-SystemAdDiscovery -Domain $domain)) {
            throw 'System resolver cannot discover the target AD domain after applying AD DNS.'
        }
        Write-Ok 'System resolver can discover Active Directory.'

        $dc = @($dnsPreflight.DomainControllers | Select-Object -First 1)
        if ($dc.Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$dc[0])) {
            throw 'No domain controller hostname was returned by DNS preflight.'
        }
        $dcName = [string]$dc[0]

        if (-not (Test-AdNetworkReadiness -DomainController $dcName)) {
            throw 'Required AD ports are not reachable from the selected network path.'
        }
        [void](Test-TimeState)
        [void](Test-TimeAgainstDomainController -ComputerName $dcName)

        Write-Ui ''
        Write-Info 'Domain credentials are requested by Windows and are held in memory only.'
        $credential = Get-Credential -UserName $joinUser -Message ("Credentials authorized to join {0}" -f $domain)
        if (-not $credential) { throw 'Credential prompt was cancelled.' }

        $params = @{
            DomainName  = $domain
            Credential  = $credential
            PassThru    = $true
            Force       = $true
            ErrorAction = 'Stop'
        }
        if ($ouPath) { $params.OUPath = $ouPath }
        if ($requestedName -ine $env:COMPUTERNAME) { $params.NewName = $requestedName }

        [void](Set-CurrentStateValues -Values @{
            Phase='JOIN_SUBMITTED'
            PhaseBootMarker=(Get-BootMarker)
            JoinAttempted=$true
        })

        Write-Info 'Submitting the domain join to Windows.'
        $result = Add-Computer @params
        if ($result -and $result.PSObject.Properties['HasSucceeded'] -and -not $result.HasSucceeded) {
            throw 'Add-Computer returned HasSucceeded=False.'
        }

        [void](Set-CurrentStateValues -Values @{
            Phase='JOIN_PENDING_REBOOT'
            PhaseBootMarker=(Get-BootMarker)
            MembershipCommitted=$true
        })

        Write-Ok 'Windows accepted the domain join operation.'
        Write-Warn 'AD DNS is intentionally retained until reboot and final secure-channel validation.'
        Write-Info ("Recovery snapshot: {0}" -f $snapshot.SnapshotPath)

        [void](Enable-RemoteManagementReadiness)

        if (Confirm-Choice -Prompt 'Restart now?' -Default N) {
            $script:RunOutcome = 'REBOOT_REQUESTED'
            Write-RunReport
            Restart-Computer -Force
        }
    }
    catch {
        Write-ErrorUi ("Domain join workflow stopped: {0}" -f $_.Exception.Message)

        $state = Get-CurrentState
        $phase = if ($state -and $state.PSObject.Properties['Phase']) { [string]$state.Phase } else { '' }
        $startLine = if ($state -and $state.PSObject.Properties['NetSetupStartLine']) { [int]$state.NetSetupStartLine } else { [int]$snapshot.NetSetupStartLine }

        if ($phase -in @('SNAPSHOT_CREATED','DNS_APPLIED')) {
            Write-Warn 'AD membership was not submitted; restoring the local pre-join state.'
            try {
                Restore-DnsFromSnapshot -Snapshot $snapshot
                Remove-CurrentState
                Write-Ok 'Pre-join DNS state restored.'
            }
            catch {
                Write-ErrorUi ("Automatic rollback failed: {0}" -f $_.Exception.Message)
                Write-Warn ("Snapshot remains available at: {0}" -f $snapshot.SnapshotPath)
            }
        }
        else {
            Write-NetSetupDiagnosis -SnapshotPath ([string]$snapshot.SnapshotPath) -StartLine $startLine
            $evidence = Get-JoinCommitEvidence -Domain $domain -NetSetupStartLine $startLine

            if ($evidence.Outcome -eq 'Accepted') {
                [void](Set-CurrentStateValues -Values @{
                    Phase='JOIN_PENDING_REBOOT'
                    PhaseBootMarker=(Get-BootMarker)
                    MembershipCommitted=$true
                })
                Write-Warn ("Join acceptance evidence exists: {0}." -f $evidence.Reason)
                Write-Warn 'AD DNS has been retained. Reboot, then run -Mode Status.'
            }
            elseif ($evidence.Outcome -eq 'Failed') {
                Write-Warn ("Join failure is explicit: {0}. Restoring local DNS." -f $evidence.Reason)
                try {
                    Restore-DnsFromSnapshot -Snapshot $snapshot
                    Remove-CurrentState
                    Write-Ok 'Pre-join DNS state restored after explicit join failure.'
                }
                catch {
                    Write-ErrorUi ("DNS rollback failed: {0}" -f $_.Exception.Message)
                }
            }
            else {
                [void](Set-CurrentStateValues -Values @{Phase='JOIN_AMBIGUOUS';PhaseBootMarker=(Get-BootMarker)})
                Write-ErrorUi 'Join commit state is ambiguous. The assistant will not guess and will not restore DNS automatically.'
                Write-Warn 'Keep AD DNS in place, inspect NetSetup evidence, and run -Mode Recover.'
            }
        }

        Write-Warn 'No domain password was persisted.'
    }
}

# ---------------------------------------------------------------------------
# Leave / restore / recovery
# ---------------------------------------------------------------------------

function Invoke-LeaveDomain {
    Sync-LifecycleState
    Write-Header
    Write-Ui 'LEAVE DOMAIN CLEANLY' Cyan
    Write-Ui ''

    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    if (-not $cs.PartOfDomain) {
        Write-Info 'This computer is not currently joined to a domain.'
        return
    }

    $state = Get-CurrentState
    if ($state -and [string]$state.Phase -eq 'JOIN_PENDING_REBOOT' -and
        [string]$state.PhaseBootMarker -eq (Get-BootMarker)) {
        Write-ErrorUi 'The join is still pending its first reboot. Complete that transition before attempting a leave.'
        return
    }

    $snapshot = $null
    if ($state -and $state.SnapshotPath) {
        try { $snapshot = Get-Snapshot -SnapshotPath ([string]$state.SnapshotPath) }
        catch { Write-Warn ("Recorded snapshot could not be loaded: {0}" -f $_.Exception.Message) }
    }

    $defaultWorkgroup = if ($snapshot -and $snapshot.Workgroup) { [string]$snapshot.Workgroup } else { 'WORKGROUP' }
    $unjoinUser = Read-Value -Prompt 'Account authorized to remove this computer from AD' `
        -Default ("Administrator@{0}" -f $cs.Domain)
    $workgroup = Read-Value -Prompt 'Workgroup after leaving the domain' -Default $defaultWorkgroup
    if ($workgroup.Length -lt 1 -or $workgroup.Length -gt 15 -or $workgroup -notmatch '^[A-Za-z0-9][A-Za-z0-9-]*$') {
        Write-ErrorUi 'Workgroup must be 1-15 characters using letters, digits or hyphen.'
        return
    }

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

        if ($state) {
            [void](Set-CurrentStateValues -Values @{
                Phase='LEAVE_PENDING_REBOOT'
                PhaseBootMarker=(Get-BootMarker)
            })
            Write-Warn 'AD DNS is intentionally retained until the leave reboot completes.'
            if ($snapshot) {
                Write-Info 'After reboot, run -Mode Restore or -Mode Recover to restore the original local state.'
            }
            else {
                Write-Warn 'The recorded pre-join snapshot is unavailable; automatic DNS/hostname restoration may not be possible.'
            }
        }
        else {
            Write-Warn 'No assistant pre-join lifecycle exists; automatic DNS/hostname restoration is unavailable.'
            Write-Warn 'The assistant will not invent a pre-domain resolver configuration.'
        }

        Write-Warn 'A reboot is required to complete the domain leave.'
        if (Confirm-Choice -Prompt 'Restart now?' -Default N) {
            $script:RunOutcome = 'REBOOT_REQUESTED'
            Write-RunReport
            Restart-Computer -Force
        }
    }
    catch {
        Write-ErrorUi ("Domain leave failed: {0}" -f $_.Exception.Message)
        Write-NetSetupDiagnosis
        Write-Warn 'No forced registry/domain-membership manipulation was attempted.'
    }
}

function Invoke-RestorePreJoin {
    Sync-LifecycleState
    Write-Header
    Write-Ui 'RESTORE PRE-JOIN STATE' Cyan
    Write-Ui ''

    $state = Get-CurrentState
    if (-not $state) {
        Write-ErrorUi 'No assistant-managed current state exists.'
        return
    }

    $phase = [string]$state.Phase
    $currentBoot = Get-BootMarker
    $phaseBoot = if ($state.PSObject.Properties['PhaseBootMarker']) { [string]$state.PhaseBootMarker } else { '' }

    if ($phase -eq 'JOIN_PENDING_REBOOT' -and $phaseBoot -eq $currentBoot) {
        Write-ErrorUi 'The domain join is still pending its first reboot.'
        Write-Warn 'Restoring DNS/hostname now could break the pending Windows domain transition.'
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
        Write-Warn 'Use Leave domain cleanly first. The assistant will not fake an unjoin through registry changes.'
        return
    }

    try { $snapshot = Get-Snapshot -SnapshotPath ([string]$state.SnapshotPath) }
    catch { Write-ErrorUi $_.Exception.Message; return }

    try {
        Restore-DnsFromSnapshot -Snapshot $snapshot
        $needsRename = ($env:COMPUTERNAME -ine [string]$snapshot.ComputerName)
        $nameRestored = Restore-ComputerNameFromSnapshot -Snapshot $snapshot

        if ($needsRename -and $nameRestored) {
            [void](Set-CurrentStateValues -Values @{
                Phase='RESTORE_PENDING_REBOOT'
                PhaseBootMarker=(Get-BootMarker)
            })
            Write-Warn 'DNS is restored and the original hostname is scheduled; reboot once more to finish.'
            if (Confirm-Choice -Prompt 'Restart now?' -Default N) {
                $script:RunOutcome = 'REBOOT_REQUESTED'
                Write-RunReport
                Restart-Computer -Force
            }
        }
        elseif ($nameRestored) {
            Remove-CurrentState
            Write-Ok 'Pre-join state restored. Snapshot retained for evidence.'
        }
    }
    catch {
        Write-ErrorUi ("Restore failed: {0}" -f $_.Exception.Message)
    }
}

function Invoke-Recovery {
    Sync-LifecycleState
    Write-Header
    Write-Ui 'LIFECYCLE RECOVERY' Cyan
    Write-Ui ''

    $state = Get-CurrentState
    if (-not $state) {
        Write-Info 'No interrupted or pending assistant lifecycle exists.'
        return
    }

    $phase = [string]$state.Phase
    Write-Ui ("Phase    : {0}" -f $phase)
    Write-Ui ("Domain   : {0}" -f $state.Domain)
    Write-Ui ("Snapshot : {0}" -f $state.SnapshotPath)
    Write-Ui ''

    $snapshot = $null
    try { $snapshot = Get-Snapshot -SnapshotPath ([string]$state.SnapshotPath) }
    catch { Write-ErrorUi ("Snapshot cannot be loaded: {0}" -f $_.Exception.Message) }

    switch ($phase) {
        'SNAPSHOT_CREATED' {
            Write-Info 'The transaction stopped before DNS or membership changes were applied.'
            if (Confirm-Choice -Prompt 'Clear the stale transaction state and keep the snapshot as evidence?' -Default Y) {
                Remove-CurrentState
                Write-Ok 'Stale transaction state cleared.'
            }
        }

        'DNS_APPLIED' {
            if (-not $snapshot) { return }
            Write-Warn 'AD DNS was applied, but Add-Computer was not submitted.'
            if (Confirm-Choice -Prompt 'Restore the pre-join DNS state now?' -Default Y) {
                Restore-DnsFromSnapshot -Snapshot $snapshot
                Remove-CurrentState
                Write-Ok 'Interrupted pre-membership transaction rolled back safely.'
            }
        }

        { $_ -in @('JOIN_SUBMITTED','JOIN_AMBIGUOUS') } {
            $startLine = if ($state.PSObject.Properties['NetSetupStartLine']) { [int]$state.NetSetupStartLine } else { 0 }
            $evidence = Get-JoinCommitEvidence -Domain ([string]$state.Domain) -NetSetupStartLine $startLine
            Write-Info ("Join evidence: {0} - {1}" -f $evidence.Outcome,$evidence.Reason)
            Write-NetSetupDiagnosis -SnapshotPath ([string]$state.SnapshotPath) -StartLine $startLine

            if ($evidence.Outcome -eq 'Accepted') {
                [void](Set-CurrentStateValues -Values @{
                    Phase='JOIN_PENDING_REBOOT'
                    PhaseBootMarker=(Get-BootMarker)
                    MembershipCommitted=$true
                })
                Write-Warn 'Membership acceptance is evidenced. Keep AD DNS and reboot before final validation.'
            }
            elseif ($evidence.Outcome -eq 'Failed') {
                if (-not $snapshot) { return }
                if (Confirm-Choice -Prompt 'Explicit join failure detected. Restore pre-join DNS?' -Default Y) {
                    Restore-DnsFromSnapshot -Snapshot $snapshot
                    Remove-CurrentState
                    Write-Ok 'Failed join transaction rolled back.'
                }
            }
            else {
                Write-ErrorUi 'Membership state is still ambiguous. Automatic rollback is intentionally blocked.'
                Write-Warn 'If an administrator has independently verified that AD membership was NOT committed,'
                Write-Warn 'the local DNS state can be restored with an explicit high-impact acknowledgement.'
                if ($snapshot -and (Confirm-Literal `
                    -Prompt 'Restoring DNS during an ambiguous join can break a partially committed membership.' `
                    -Literal 'ROLLBACK-LOCAL')) {
                    Restore-DnsFromSnapshot -Snapshot $snapshot
                    Remove-CurrentState
                    Write-Ok 'Local pre-join DNS restored by explicit operator decision.'
                }
            }
        }

        'JOIN_PENDING_REBOOT' {
            if ([string]$state.PhaseBootMarker -eq (Get-BootMarker)) {
                Write-Warn 'Domain join is accepted and waiting for its first reboot. Keep AD DNS unchanged.'
            }
            else {
                Sync-LifecycleState
                Invoke-Status
            }
        }

        'JOINED' {
            Write-Ok 'Managed domain membership is healthy; no recovery action is pending.'
        }

        'JOINED_DEGRADED' {
            Write-Warn 'Managed membership is degraded. Re-running acceptance checks.'
            if (Test-PostJoinAcceptance -Domain ([string]$state.Domain)) {
                [void](Set-CurrentStateValues -Values @{Phase='JOINED';PhaseBootMarker=(Get-BootMarker)})
                Write-Ok 'The client now passes domain acceptance checks.'
            }
        }

        'LEAVE_PENDING_REBOOT' {
            if ([string]$state.PhaseBootMarker -eq (Get-BootMarker)) {
                Write-Warn 'Domain leave is accepted and waiting for reboot. Keep AD DNS unchanged.'
            }
            else {
                Sync-LifecycleState
                $newState = Get-CurrentState
                if ($newState -and [string]$newState.Phase -eq 'RESTORE_READY') {
                    Invoke-RestorePreJoin
                }
            }
        }

        'RESTORE_READY' {
            Invoke-RestorePreJoin
        }

        'RESTORE_PENDING_REBOOT' {
            if ([string]$state.PhaseBootMarker -eq (Get-BootMarker)) {
                Write-Warn 'Original hostname restoration is waiting for reboot.'
            }
            else {
                Sync-LifecycleState
                if (-not (Get-CurrentState)) { Write-Ok 'Restore lifecycle is complete.' }
            }
        }

        default {
            Write-Warn ("Unknown lifecycle phase: {0}. No automatic recovery was attempted." -f $phase)
        }
    }
}

# ---------------------------------------------------------------------------
# Interactive control plane
# ---------------------------------------------------------------------------

function Show-MainMenu {
    while ($true) {
        Sync-LifecycleState
        Write-Header
        Write-Ui 'AD CLIENT OPERATIONS' Cyan
        Write-Ui ''
        Write-Ui ("  [1] {0}" -f (Get-UiText 'Readiness audit'))
        Write-Ui ("  [2] {0}" -f (Get-UiText 'Guided domain join'))
        Write-Ui ("  [3] {0}" -f (Get-UiText 'Domain client status'))
        Write-Ui ("  [4] {0}" -f (Get-UiText 'Leave domain cleanly'))
        Write-Ui ("  [5] {0}" -f (Get-UiText 'Switch to another domain')) Yellow
        Write-Ui ("  [6] {0}" -f (Get-UiText 'AD connectivity test'))
        Write-Ui ("  [7] {0}" -f (Get-UiText 'Troubleshoot / repair'))
        Write-Ui ("  [8] {0}" -f (Get-UiText 'Export diagnostic bundle'))
        Write-Ui ("  [9] {0}" -f (Get-UiText 'Restore pre-join state'))
        Write-Ui ("  [10] {0}" -f (Get-UiText 'List recovery snapshots'))
        Write-Ui ("  [11] {0}" -f (Get-UiText 'Recover interrupted lifecycle')) Yellow
        Write-Ui ("  [12] Remote management setup / readiness")
        Write-Ui ("  [L] {0} [{1}]" -f (Get-UiText 'Language / Idioma'),$script:UiLanguage.ToUpperInvariant())
        Write-Ui ("  [0] {0}" -f (Get-UiText 'Exit'))
        Write-Ui ''

        $default = if ((Get-CurrentState) -and (Get-LifecycleLabel) -in @(
            'SNAPSHOT_CREATED','DNS_APPLIED','JOIN_SUBMITTED','JOIN_AMBIGUOUS','RESTORE_READY')) { '11' } else { '1' }
        $choice = Read-Value -Prompt 'Select operation' -Default $default

        try {
            switch ($choice.ToUpperInvariant()) {
                '1' { Invoke-ReadinessAudit; Pause-Ui }
                '2' { Invoke-GuidedJoin; Pause-Ui }
                '3' { Invoke-Status; Pause-Ui }
                '4' { Invoke-LeaveDomain; Pause-Ui }
                '5' { Invoke-DomainSwitch; Pause-Ui }
                '6' { Invoke-ConnectivityTest; Pause-Ui }
                '7' { Invoke-Troubleshoot; Pause-Ui }
                '8' { Export-DiagnosticBundle; Pause-Ui }
                '9' { Invoke-RestorePreJoin; Pause-Ui }
                '10' { Show-Snapshots; Pause-Ui }
                '11' { Invoke-Recovery; Pause-Ui }
                '12' { [void](Enable-RemoteManagementReadiness); Pause-Ui }
                'L' { Switch-UiLanguage }
                '0' { return }
                default { Write-Warn 'Unknown option.'; Pause-Ui }
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

try {
    Initialize-Runtime
    Write-Log ("Starting {0} v{1}; mode={2}." -f $script:ProductName,$script:Version,$Mode)

    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Administrator privileges are required.'
    }

    switch ($Mode) {
        'Interactive' { Show-MainMenu }
        'Audit'       { Invoke-ReadinessAudit }
        'Join'        { Invoke-GuidedJoin }
        'Status'      { Invoke-Status }
        'Leave'       { Invoke-LeaveDomain }
        'Switch'      { Invoke-DomainSwitch }
        'Connectivity' { Invoke-ConnectivityTest }
        'Troubleshoot' { Invoke-Troubleshoot }
        'Diagnostics' { Export-DiagnosticBundle }
        'RemoteSetup' { [void](Enable-RemoteManagementReadiness -NonInteractive) }
        'Restore'     { Invoke-RestorePreJoin }
        'Snapshots'   { Show-Snapshots }
        'Recover'     { Invoke-Recovery }
    }
}
catch {
    $script:RunOutcome = 'ERROR'
    try { Write-ErrorUi ("Unhandled operation error: {0}" -f $_.Exception.Message) } catch {}
    exit 1
}
finally {
    Write-RunReport
    if ($script:LockStream) {
        try { $script:LockStream.Dispose() } catch {}
    }
}
