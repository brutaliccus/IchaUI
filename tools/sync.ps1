# Re-copy the IchaUI addon folders from the live AddOns folder into this repo.
# Usage (from anywhere):
#   powershell -ExecutionPolicy Bypass -File tools\sync.ps1
#   powershell -ExecutionPolicy Bypass -File tools\sync.ps1 -AddOns "D:\Games\WoW\Interface\AddOns"
# Each suite folder is mirrored (files deleted in AddOns are deleted here too).
# Dev leftovers (*.py, *.png, *.bak, __pycache__, _* scratch files) are never copied.

param(
    [string]$AddOns = "F:\RavenCraft\Interface\AddOns"
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot

$folders = @(
    "IchaUI",
    "IchaUI_Bars",
    "IchaUI_BuffBars",
    "IchaUI_Chat",
    "IchaUI_CustomDrawers",
    "IchaUI_Hero",
    "IchaUI_Minimap",
    "IchaUI_Plates",
    "IchaUI_Shaman",
    "IchaUI_SmartMark",
    "IchaUI_SmartTab",
    "IchaUI_UnitFrames",
    "IchaUI_XP"
)

foreach ($name in $folders) {
    $src = Join-Path $AddOns $name
    $dst = Join-Path $repo $name
    if (-not (Test-Path $src)) {
        Write-Warning "Missing in AddOns: $name (skipped)"
        continue
    }
    robocopy $src $dst /MIR /NJH /NJS /NP /NDL `
        /XF *.py *.pyc *.png *.bak _* `
        /XD __pycache__ _* | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed for $name (exit $LASTEXITCODE)" }
    Write-Host "Synced $name"
}

$extra = Get-ChildItem $AddOns -Directory -Filter "IchaUI*" |
    Where-Object { $folders -notcontains $_.Name } | Select-Object -ExpandProperty Name
if ($extra) { Write-Warning ("IchaUI folders in AddOns not in the suite list: " + ($extra -join ", ")) }
exit 0
