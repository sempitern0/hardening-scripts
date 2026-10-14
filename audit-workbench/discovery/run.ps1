$ErrorActionPreference='Stop'
$engine=Join-Path $PSScriptRoot 'discover.py'
if(Get-Command py -ErrorAction SilentlyContinue){& py -3 $engine @args}
elseif(Get-Command python -ErrorAction SilentlyContinue){& python $engine @args}
else{throw 'Python 3.9+ no disponible. Ejecuta discovery/setup.ps1.'}
exit $LASTEXITCODE
