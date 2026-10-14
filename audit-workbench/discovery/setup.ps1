[CmdletBinding()]
param([switch]$InstallTools)
$ErrorActionPreference='Stop'
$pythonPresent=$false
if(Get-Command py -ErrorAction SilentlyContinue){& py -3 -c 'import sys;sys.exit(0 if sys.version_info>=(3,9) else 1)' 2>$null;$pythonPresent=($LASTEXITCODE -eq 0)}
elseif(Get-Command python -ErrorAction SilentlyContinue){& python -c 'import sys;sys.exit(0 if sys.version_info>=(3,9) else 1)' 2>$null;$pythonPresent=($LASTEXITCODE -eq 0)}
$nmapPresent=[bool](Get-Command nmap -ErrorAction SilentlyContinue)
Write-Host "Python 3.9+: $pythonPresent; Nmap opcional: $nmapPresent; ping: $([bool](Get-Command ping -ErrorAction SilentlyContinue))"
if(-not $InstallTools){Write-Host 'Solo diagnóstico. Usa -InstallTools para autorizar instalaciones.';return}
if(-not(Get-Command winget -ErrorAction SilentlyContinue)){throw 'Instala Python 3 y Nmap manualmente: winget no disponible.'}
if(-not $pythonPresent){& winget install --exact --id Python.Python.3.13;if($LASTEXITCODE -ne 0){throw 'Error instalando Python'}}
if(-not $nmapPresent){& winget install --exact --id Insecure.Nmap;if($LASTEXITCODE -ne 0){throw 'Error instalando Nmap'}}
Write-Host 'Reabre PowerShell para actualizar PATH.'
