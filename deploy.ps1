param(
    [string]$GamePath = ""
)

$ErrorActionPreference = "Stop"

$candidateDirs = @(
    $GamePath,
    "D:\SteamLibrary\steamapps\common\Disney Infinity 3.0 Gold Edition",
    "C:\Program Files (x86)\Steam\steamapps\common\Disney Infinity 3.0 Gold Edition",
    "C:\SteamLibrary\steamapps\common\Disney Infinity 3.0 Gold Edition",
    "E:\SteamLibrary\steamapps\common\Disney Infinity 3.0 Gold Edition"
)

$resolvedGameDir = $null
foreach ($dir in $candidateDirs) {
    if (![string]::IsNullOrWhiteSpace($dir) -and (Test-Path (Join-Path $dir "DisneyInfinity3.exe"))) {
        $resolvedGameDir = $dir
        break
    }
}

if (!$resolvedGameDir) {
    # Check Steam registry
    try {
        $steamPath = Get-ItemPropertyValue -Path "HKCU:\Software\Valve\Steam" -Name "SteamPath" -ErrorAction SilentlyContinue
        if ($steamPath) {
            $regDir = Join-Path $steamPath "steamapps\common\Disney Infinity 3.0 Gold Edition"
            if (Test-Path (Join-Path $regDir "DisneyInfinity3.exe")) {
                $resolvedGameDir = $regDir
            }
        }
    } catch {}
}

if (!$resolvedGameDir) {
    Write-Error "Could not locate Disney Infinity 3.0 Gold Edition. Please pass -GamePath 'C:\Path\To\Game'."
    exit 1
}

$destModDir = Join-Path $resolvedGameDir "mods\disneyinfinityportal"
$files = @("mod.json", "portal.lua", "figure_progress.lua")

Write-Host "Deploying DisneyInfinityPortal to: $destModDir" -ForegroundColor Cyan

New-Item -ItemType Directory -Force -Path $destModDir | Out-Null
foreach ($file in $files) {
    $srcPath = Join-Path $PSScriptRoot $file
    if (!(Test-Path $srcPath)) {
        Write-Warning "File not found: $srcPath"
        continue
    }
    $bytes = [System.IO.File]::ReadAllBytes($srcPath)
    # Strip UTF-8 BOM if present
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $bytes = $bytes[3..($bytes.Length - 1)]
    }
    [System.IO.File]::WriteAllBytes((Join-Path $destModDir $file), $bytes)
    Write-Host "  [+] $file -> $destModDir" -ForegroundColor Green
}

# Clean stale files in destination mod folder
Get-ChildItem $destModDir -File | Where-Object { $files -notcontains $_.Name } | ForEach-Object {
    Remove-Item $_.FullName -Force
    Write-Host "  [-] removed stale $($_.Name)" -ForegroundColor Yellow
}

Write-Host "[OK] DisneyInfinityPortal successfully deployed!" -ForegroundColor Green
