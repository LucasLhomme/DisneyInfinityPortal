$ErrorActionPreference = "Stop"

$gameDir = "D:\SteamLibrary\steamapps\common\Disney Infinity 3.0 Gold Edition"
$modsTarget = Join-Path $gameDir "mods"
$destModDir = Join-Path $modsTarget "disneyinfinityportal"
$srcDir = $PSScriptRoot

if (!(Test-Path $gameDir)) {
    Write-Error "Dossier du jeu non trouve : $gameDir"
    exit 1
}

# 1. Create target directories
if (!(Test-Path $modsTarget)) { New-Item -ItemType Directory -Force -Path $modsTarget | Out-Null }
if (!(Test-Path $destModDir)) { New-Item -ItemType Directory -Force -Path $destModDir | Out-Null }

# 2. Copy mod files
Copy-Item -Path "$srcDir\mod.json" -Destination "$destModDir\mod.json" -Force
Write-Host "[OK] mod.json -> $destModDir" -ForegroundColor Green

foreach ($file in "portal.lua", "figure_progress.lua", "figure_skills.lua") {
    Copy-Item -Path "$srcDir\$file" -Destination "$destModDir\$file" -Force
    Write-Host "[OK] $file -> $destModDir" -ForegroundColor Green
}

# 3. Strip BOM from deployed Lua files to prevent syntax error in Lua 5.1
python -c "
from pathlib import Path
mod_dir = Path(r'$destModDir')
for f in mod_dir.rglob('*.lua'):
    try:
        data = f.read_bytes()
        if data.startswith(b'\xef\xbb\xbf'):
            f.write_bytes(data[3:])
    except Exception:
        pass
"

Write-Host "[OK] Deploiement DisneyInfinityPortal termine avec succes !" -ForegroundColor Cyan

