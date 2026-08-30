<#
.SYNOPSIS
    Packages MyLootHistory into a zip ready to upload to CurseForge.

.DESCRIPTION
    Validates the .toc, checks that every file it lists exists, copies the
    addon into dist\MyLootHistory (dev-only files excluded) and zips it as
    dist\MyLootHistory-<version>.zip. Also prints the metadata CurseForge
    asks for on the upload form (game version, changelog).

.PARAMETER Version
    Overrides the version. Rewrites ## Version in the .toc before packaging.

.PARAMETER Clean
    Removes dist\ before building.

.EXAMPLE
    .\tools\build.ps1
    .\tools\build.ps1 -Version 1.5.0

.NOTES
    If PowerShell's execution policy blocks the script, run it per-process:
        powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build.ps1
#>
[CmdletBinding()]
param(
    [string]$Version,
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'

$AddonName = 'MyLootHistory'
# the script lives in tools\, so the repo root is one level up
$Root      = Split-Path $PSScriptRoot -Parent
$TocPath   = Join-Path $Root "$AddonName.toc"
$DistDir   = Join-Path $Root 'dist'
$StageDir  = Join-Path $DistDir $AddonName

# What never ships to CurseForge. Note that the staging step copies from the
# filesystem, not from git, so being gitignored does NOT keep a file out of the
# zip - everything has to be excluded here.
#
# Anything whose name starts with a dot is dropped at any depth, which covers
# .git, .github, .vscode, .claude, .luacheckrc, .busted, .gitignore, .DS_Store
# and any tool config added later without anyone having to remember this file.
$ExcludeDirs  = @('dist', 'node_modules', 'tests', 'tools', 'web')
$ExcludeFiles = @('DEVELOPMENT.md')

function Fail($msg) { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }
function Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Warn($msg) { Write-Host "  ! $msg" -ForegroundColor Yellow }

# True when a repo-relative path must not be packaged. `$rel` uses the platform
# separator, as produced by trimming $Root off a full path.
function Test-Excluded([string]$rel) {
    foreach ($part in ($rel -split '[\\/]')) {
        if ($part.StartsWith('.')) { return $true }
    }
    foreach ($d in $ExcludeDirs)  { if ($rel -like "$d\*" -or $rel -like "$d/*") { return $true } }
    foreach ($f in $ExcludeFiles) { if ((Split-Path $rel -Leaf) -eq $f)          { return $true } }

    return $false
}

if (-not (Test-Path $TocPath)) { Fail "$AddonName.toc not found in $Root" }

# --- version -----------------------------------------------------------------
$toc = Get-Content $TocPath -Encoding UTF8

if ($Version) {
    if ($Version -notmatch '^\d+\.\d+\.\d+$') { Fail "Version must look like 1.5.0, got '$Version'" }
    Step "Setting version to $Version in $AddonName.toc"
    $toc = $toc | ForEach-Object { $_ -replace '^##\s*Version:.*$', "## Version: $Version" }
    Set-Content -Path $TocPath -Value $toc -Encoding UTF8
}

$versionLine = $toc | Where-Object { $_ -match '^##\s*Version:' } | Select-Object -First 1
if (-not $versionLine) { Fail 'No "## Version:" line in the .toc' }
$AddonVersion = ($versionLine -replace '^##\s*Version:\s*', '').Trim()

$ifaceLine = $toc | Where-Object { $_ -match '^##\s*Interface:' } | Select-Object -First 1
if (-not $ifaceLine) { Fail 'No "## Interface:" line in the .toc' }
$Interface = ($ifaceLine -replace '^##\s*Interface:\s*', '').Trim()
# 120100 -> 12.1.0
if ($Interface -match '^(\d+)(\d{2})(\d{2})$') {
    $GameVersion = "$([int]$Matches[1]).$([int]$Matches[2]).$([int]$Matches[3])"
} else {
    $GameVersion = $Interface
    Warn "Interface '$Interface' is not the expected 6-digit form"
}

Step "$AddonName $AddonVersion (Interface $Interface / WoW $GameVersion)"

# --- validate the file list --------------------------------------------------
Step 'Checking files referenced by the .toc'
$missing = @()
foreach ($line in $toc) {
    $entry = $line.Trim()
    if (-not $entry -or $entry.StartsWith('#')) { continue }
    $entry = ($entry -split '\s+')[0]           # strip any trailing load conditions
    $path  = Join-Path $Root ($entry -replace '\\', [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path $path)) { $missing += $entry }
}
if ($missing.Count) { Fail "Listed in the .toc but missing on disk:`n  " + ($missing -join "`n  ") }
Write-Host "  ok" -ForegroundColor Green

# --- lua syntax check (optional, only if luac/luacheck is installed) ---------
$luacheck = Get-Command luacheck -ErrorAction SilentlyContinue
$luac     = Get-Command luac -ErrorAction SilentlyContinue
$luaFiles = Get-ChildItem $Root -Recurse -Filter *.lua -Force |
    Where-Object { -not (Test-Excluded $_.FullName.Substring($Root.Length + 1)) }
if ($luacheck) {
    Step 'Running luacheck'
    # from $Root, so luacheck finds .luacheckrc: it looks in the current
    # directory, not next to the files it was handed
    Push-Location $Root
    try {
        & luacheck . --no-color
        if (-not $?) { Warn 'luacheck reported problems (not fatal)' }
    } finally { Pop-Location }
} elseif ($luac) {
    Step "Syntax-checking $($luaFiles.Count) Lua files with luac"
    $bad = @()
    foreach ($f in $luaFiles) {
        & luac -p $f.FullName
        if ($LASTEXITCODE -ne 0) { $bad += $f.FullName }
    }
    if ($bad.Count) { Fail "Lua syntax errors in:`n  " + ($bad -join "`n  ") }
    Write-Host "  ok" -ForegroundColor Green
} else {
    Warn 'Neither luacheck nor luac found on PATH - skipping the Lua syntax check'
}

# --- unit tests (optional, only if busted is installed) ----------------------
# Unlike luacheck this is fatal: a failing test means the logic is wrong, and
# that should not be packaged for upload.
$busted = Get-Command busted -ErrorAction SilentlyContinue
if ($busted) {
    Step 'Running tests'
    Push-Location $Root
    try {
        & busted --output=plainTerminal
        if ($LASTEXITCODE -ne 0) { Fail 'tests failed' }
    } finally { Pop-Location }
} else {
    Warn 'busted not found on PATH - skipping the tests (luarocks install busted)'
}

# --- changelog ---------------------------------------------------------------
$ChangelogPath = Join-Path $Root 'CHANGELOG.md'
$ChangelogBody = $null
if (Test-Path $ChangelogPath) {
    $cl = Get-Content $ChangelogPath -Encoding UTF8
    $start = ($cl | Select-String -Pattern '^##\s' | Select-Object -First 1).LineNumber
    if ($start) {
        $head = $cl[$start - 1]
        if ($head -notmatch [regex]::Escape($AddonVersion)) {
            Warn "CHANGELOG.md's newest entry is '$head' but the .toc says $AddonVersion"
        }
        $rest = $cl[$start..($cl.Count - 1)]
        $next = ($rest | Select-String -Pattern '^##\s' | Select-Object -First 1).LineNumber
        $ChangelogBody = if ($next) { $rest[0..($next - 2)] } else { $rest }
        $ChangelogBody = ($ChangelogBody -join "`n").Trim()
    }
} else {
    Warn 'No CHANGELOG.md'
}

# --- stage -------------------------------------------------------------------
if ($Clean -and (Test-Path $DistDir)) {
    Step 'Cleaning dist\'
    Remove-Item $DistDir -Recurse -Force
}
if (Test-Path $StageDir) { Remove-Item $StageDir -Recurse -Force }
New-Item -ItemType Directory -Path $StageDir -Force | Out-Null

Step "Staging into dist\$AddonName"
$copied = 0
# -Force so hidden files are enumerated rather than silently skipped: they have
# to be seen to be excluded on purpose, not missed by accident
Get-ChildItem $Root -Recurse -File -Force | ForEach-Object {
    $rel = $_.FullName.Substring($Root.Length + 1)
    if (Test-Excluded $rel) { return }

    $dest = Join-Path $StageDir $rel
    $destDir = Split-Path $dest -Parent
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
    Copy-Item $_.FullName $dest -Force
    $script:copied++
}
Write-Host "  $copied files" -ForegroundColor Green

# --- zip ---------------------------------------------------------------------
$ZipPath = Join-Path $DistDir "$AddonName-$AddonVersion.zip"
if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
Step "Zipping $AddonName-$AddonVersion.zip"
Compress-Archive -Path $StageDir -DestinationPath $ZipPath -CompressionLevel Optimal
$sizeKb = [math]::Round((Get-Item $ZipPath).Length / 1KB, 1)

# --- summary -----------------------------------------------------------------
Write-Host ''
Write-Host "Package:      $ZipPath ($sizeKb KB)" -ForegroundColor Green
Write-Host "Display name: $AddonName-$AddonVersion"
Write-Host "Release type: release"
Write-Host "Game version: $GameVersion (Retail)"
if ($ChangelogBody) {
    Write-Host ''
    Write-Host '--- changelog for the upload form ---'
    Write-Host $ChangelogBody
    Write-Host '-------------------------------------'
}
Write-Host ''
Write-Host 'Upload at: https://legacy.curseforge.com/wow/addons/<your-project>/upload-file'
