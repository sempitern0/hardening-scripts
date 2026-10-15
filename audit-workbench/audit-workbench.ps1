# Audit Workbench — instalador offline Windows, PowerShell 5.1+ / 7+.
[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path $env:LOCALAPPDATA 'SysadminTools\AuditWorkbench'),
    [string]$Ref = 'main',
    [string]$Repository = 'sempitern0/sysadmin',
    [switch]$Update,
    [switch]$NoOpen
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($Repository -notmatch '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$') { throw 'Repositorio inválido (owner/repo).' }
if ($Ref -notmatch '^[A-Za-z0-9._/-]+$' -or $Ref.Contains('..') -or $Ref.StartsWith('//')) { throw 'Referencia Git inválida.' }
$files = @(
    'index.html','css/normalize.css','css/styles.css','css/team.css','css/contrast.css','css/relations.css','css/templates.css','css/quality.css','css/retest.css','css/comparison.css','css/glossary.css','css/print.css','css/atkinson.css','css/workspace-ux.css',
    'js/app.js','js/audit-storage.js','js/audit-relations.js','js/audit-identifiers.js','js/control-templates.js','js/field-assist.js','js/audit-quality.js','js/audit-retest.js','js/audit-comparison.js','js/hardware-catalog.js','js/software-catalog.js','js/os-catalog.js','js/glossary.js','js/inventory-import.js','js/input-guidance.js','js/secure-transfer.js','js/secure-transfer-ui.js','js/document-control.js','js/pwa-updates.js','js/offline-health.js','js/exporters.js','sw.js','manifest.webmanifest','collect-local.sh','collect-local.ps1','discovery/discover.py','discovery/wizard.py','discovery/iniciar.cmd','discovery/run.sh','discovery/run.ps1','discovery/setup.sh','discovery/setup.ps1','discovery/README_ES.md',
    'fonts/AtkinsonHyperlegible-Regular.woff2','fonts/AtkinsonHyperlegible-Bold.woff2',
    'fonts/AtkinsonHyperlegible-Italic.woff2','fonts/AtkinsonHyperlegible-BoldItalic.woff2',
    'icons/os-windows.svg','icons/os-linux.svg','icons/os-macos.svg','icons/dragon.svg','icons/icon-192.png','icons/icon-512.png'
)
$source = if ($PSScriptRoot) { $PSScriptRoot } else { $null }
$required = $Update.IsPresent
foreach ($name in $files) {
    $path = Join-Path $OutputDirectory $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -eq 0) { $required = $true }
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
            if (-not (Test-Path -LiteralPath $stagedFile -PathType Leaf) -or (Get-Item -LiteralPath $stagedFile).Length -eq 0) {
                throw "Archivo vacío: $name"
            }
        }
        if (-not (Select-String -LiteralPath (Join-Path $stage 'index.html') -Pattern 'Audit Workbench' -SimpleMatch -Quiet) -or
            -not (Select-String -LiteralPath (Join-Path $stage 'js/audit-relations.js') -Pattern 'AuditRelations' -SimpleMatch -Quiet)) {
            throw 'Los archivos no corresponden con Audit Workbench.'
        }
        foreach ($name in $files) {
            $parent = Split-Path -Parent (Join-Path $OutputDirectory $name)
            if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            Move-Item -LiteralPath (Join-Path $stage $name) -Destination (Join-Path $OutputDirectory $name) -Force
        }
        Write-Host "[OK] Aplicación instalada en: $OutputDirectory"
    } finally {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
}
$index = Join-Path $OutputDirectory 'index.html'
Write-Host "[OK] Archivo local: $index"
Write-Host 'Expedientes: en el navegador. Exporta copias JSON y conserva los originales de evidencias.'
if (-not $NoOpen) { Start-Process -FilePath $index }
