$ErrorActionPreference = "Stop"

$gameDir = "D:\SteamLibrary\steamapps\common\Disney Infinity 3.0 Gold Edition"
$destModDir = Join-Path $gameDir "mods\disneyinfinityportal"
$files = "mod.json", "portal.lua", "figure_progress.lua"

if (!(Test-Path $gameDir)) {
    Write-Error "Game folder not found: $gameDir"
    exit 1
}

New-Item -ItemType Directory -Force -Path $destModDir | Out-Null
foreach ($file in $files) {
    $bytes = [System.IO.File]::ReadAllBytes((Join-Path $PSScriptRoot $file))
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $bytes = $bytes[3..($bytes.Length - 1)]
    }
    [System.IO.File]::WriteAllBytes((Join-Path $destModDir $file), $bytes)
    Write-Host "[OK] $file -> $destModDir" -ForegroundColor Green
}

Get-ChildItem $destModDir -File | Where-Object { $files -notcontains $_.Name } | ForEach-Object {
    Remove-Item $_.FullName
    Write-Host "[OK] removed stale $($_.Name)" -ForegroundColor Yellow
}

Write-Host "[OK] DisneyInfinityPortal deployed." -ForegroundColor Cyan
