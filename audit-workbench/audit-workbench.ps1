# Audit Workbench - launcher for Windows PowerShell 5.1+ and PowerShell 7.
# One-time HTTPS download; the actual audit app works offline afterwards.
[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path $env:LOCALAPPDATA 'SysadminTools\AuditWorkbench'),
    [string]$Ref = 'main',
    [string]$Repository = 'sempitern0/hardening-scripts',
    [switch]$Update,
    [switch]$NoOpen
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($Repository -notmatch '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$') { throw 'Repositorio inválido (esperado owner/repo).' }
if ($Ref -notmatch '^[A-Za-z0-9._/-]+$' -or $Ref.Contains('..') -or $Ref.StartsWith('//')) {
    throw 'Ref de Git inválida.'
}
$files = @('index.html','styles.css','app.js','manifest.webmanifest','sw.js','icons/icon-192.png','icons/icon-512.png')
# $PSScriptRoot is empty when executed via Invoke-Expression (irm ... | iex).
# Local checkout takes precedence; piped one-liners download the app once.
$source = if ($PSScriptRoot) { $PSScriptRoot } else { $null }
$required = $Update.IsPresent
foreach ($name in $files) {
    $path = Join-Path $OutputDirectory $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -eq 0) {
        $required = $true
    }
}
if ($required) {
    New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
    $stage = Join-Path $OutputDirectory ('.staging-' + [guid]::NewGuid().ToString('N'))
    New-Item -Path $stage -ItemType Directory -Force | Out-Null
    try {
        foreach ($name in $files) {
            $sourceFile = if ($source) { Join-Path $source $name } else { $null }
            $stagedFile = Join-Path $stage $name
            $parent = Split-Path -Parent $stagedFile
            if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            if ($source -and (Test-Path -LiteralPath $sourceFile -PathType Leaf)) {
                Copy-Item -LiteralPath $sourceFile -Destination $stagedFile
            } else {
                $url = "https://raw.githubusercontent.com/$Repository/$Ref/audit-workbench/$name"
                Invoke-WebRequest -Uri $url -OutFile $stagedFile -UseBasicParsing -TimeoutSec 90 | Out-Null
            }
            if (-not (Test-Path -LiteralPath $stagedFile -PathType Leaf) -or (Get-Item $stagedFile).Length -eq 0) {
                throw "Archivo de aplicación vacío: $name"
            }
        }
        if (-not (Select-String -LiteralPath (Join-Path $stage 'index.html') -Pattern 'Audit Workbench' -Quiet) -or
            -not (Select-String -LiteralPath (Join-Path $stage 'app.js') -Pattern 'sysadmin-tools:audit-workbench:v2' -SimpleMatch -Quiet)) {
            throw 'La descarga no corresponde con Audit Workbench.'
        }
        foreach ($name in $files) {
            $destinationParent = Split-Path -Parent (Join-Path $OutputDirectory $name)
            if (-not (Test-Path -LiteralPath $destinationParent)) { New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null }
            Move-Item -LiteralPath (Join-Path $stage $name) -Destination (Join-Path $OutputDirectory $name) -Force
        }
        Write-Host "[OK] Aplicación instalada: $OutputDirectory"
    } finally {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
}
$index = Join-Path $OutputDirectory 'index.html'
Write-Host "[OK] Archivo local: $index"
Write-Host 'Guarda el JSON frecuentemente y utiliza Generar PDF > Guardar como PDF.'
if (-not $NoOpen) { Start-Process -FilePath $index }
