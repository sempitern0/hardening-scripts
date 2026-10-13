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
    ip=if($ipv4){[string]$ipv4.IPAddress}else{''}
    notes='Captura local declarativa; verificar datos antes de incorporar.'
  })
  networks=@();software=@()
 }
}
$json=ConvertTo-Json -InputObject $data -Depth 8
$full=[IO.Path]::GetFullPath($Output)
$parent=[IO.Path]::GetDirectoryName($full)
if(-not [IO.Directory]::Exists($parent)){throw 'Destination directory does not exist.'}
$bytes=New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($full,$json,$bytes)
Write-Host "Saved $full"
