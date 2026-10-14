$ErrorActionPreference='Stop'
$engine=Join-Path $PSScriptRoot 'discover.py'
if ($args.Count -eq 0) { $commandArgs = @('wizard') } else { $commandArgs = $args }
if(Get-Command py -ErrorAction SilentlyContinue){& py -3 $engine @commandArgs}
elseif(Get-Command python -ErrorAction SilentlyContinue){& python $engine @commandArgs}
else{throw 'Python 3.9+ no disponible. Ejecuta discovery/setup.ps1.'}
exit $LASTEXITCODE
