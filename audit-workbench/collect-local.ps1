# Audit Workbench local collection. Read-only. No remote connections.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Output)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Output exists. Choose a new file name.'}
$computer=Get-CimInstance Win32_ComputerSystem
$os=Get-CimInstance Win32_OperatingSystem
$proc=Get-CimInstance Win32_Processor | Select-Object -First 1
$ipv4=Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object {$_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*'} | Select-Object -First 1
$ipAddress=if($ipv4){[string]$ipv4.IPAddress}else{''}
$networks=@(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object {$_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*'} | Select-Object -First 24 | ForEach-Object {
 [ordered]@{name=[string]$_.InterfaceAlias;cidr=([string]$_.IPAddress+'/'+[string]$_.PrefixLength);notes='Interfaz local detectada. Segmentación y firewall por verificar.'}
})
$serviceRows=@(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object {$_.State -eq 'Running'} | Select-Object -First 35 | ForEach-Object {
 [ordered]@{name=[string]$_.Name;asset=[string]$env:COMPUTERNAME;notes='Servicio en ejecución detectado; versión y exposición por verificar.'}
})
$diskRows=@(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction SilentlyContinue | Select-Object -First 12 | ForEach-Object {
 [string]$_.DeviceID+' '+('{0:N1} GiB' -f ($_.Size/1GB))
})
$data=[ordered]@{
 kind='audit-workbench-discovery-v1';schemaVersion=1;capturedAt=(Get-Date).ToUniversalTime().ToString('o')
 source=[ordered]@{platform='Windows';collector='collect-local.ps1';scope='local';mode='read-only'}
 items=[ordered]@{
  assets=@([ordered]@{
    name=[string]$env:COMPUTERNAME
    vendor=[string]$computer.Manufacturer
    model=[string]$computer.Model
    os=[string]$os.Caption
    cpu=[string]$proc.Name
    ram=('{0:N1} GiB' -f ($computer.TotalPhysicalMemory / 1GB))
    ip=$ipAddress
    storage=($diskRows -join '; ')
    notes='Captura local declarativa; verificar datos antes de incorporar.'
  })
  networks=$networks;software=$serviceRows
 }
}
$json=ConvertTo-Json -InputObject $data -Depth 8
$full=[IO.Path]::GetFullPath($Output)
$parent=[IO.Path]::GetDirectoryName($full)
if(-not [IO.Directory]::Exists($parent)){throw 'Destination directory does not exist.'}
$bytes=New-Object System.Text.UTF8Encoding($false)
$stream=[IO.File]::Open($full,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try {
  $writer=New-Object IO.StreamWriter($stream,$bytes)
  try { $writer.Write($json); $writer.Flush() } finally { $writer.Dispose() }
} finally { $stream.Dispose() }
Write-Host "Saved $full"
