# Collect SVG from nested icons/ folders into icons/font/ for icon_font_generator.
# Stroke-based icons are converted to filled paths (required for icon fonts).
#
# Run from project root:
#   powershell -File icons/collect_icons.ps1
#   flutter pub run icon_font_generator:generator -z icon_font.yaml

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$srcRoot = Join-Path $root 'icons'
$fontDir = Join-Path $srcRoot 'font'
$fontFixedDir = Join-Path $srcRoot 'font_fixed'

$specialRenamesFont = @{
    '10|Frame.svg'   = 'help'
    '14|Frame.svg'   = 'exit'
    '14|Frame-1.svg' = 'info_circle'
    '14|Frame-2.svg' = 'chat_bubble'
    '14|Frame-3.svg' = 'play'
    '14|Frame-4.svg' = 'layout_grid'
    '14|Frame-5.svg' = 'link'
    '14|Frame-6.svg' = 'smile_circle'
    '13|add-1.svg'   = 'add_filled'
    '04|mail-1.svg'  = 'mail_filled'
}

function Get-SectionPrefix([string]$folderName) {
    if ($folderName -match '^(\d+)') { return $Matches[1] }
    return $null
}

function Normalize-FontBase([string]$fileName) {
    $base = [System.IO.Path]::GetFileNameWithoutExtension($fileName).ToLower()
    $base = $base -replace '-', '_'
    $base = $base -replace '[^a-z0-9_]', '_'
    $base = $base -replace '_+', '_'
    return $base.Trim('_')
}

function Collect-Icons {
    param(
        [string]$OutputDir,
        [hashtable]$SpecialRenames,
        [scriptblock]$MakeTargetName,
        [scriptblock]$MakeIconBase
    )

    if (Test-Path $OutputDir) { Remove-Item $OutputDir -Recurse -Force }
    New-Item -ItemType Directory -Path $OutputDir | Out-Null

    $usedNames = @{}
    $count = 0

    Get-ChildItem -Path $srcRoot -Directory |
        Where-Object { $_.Name -ne 'font' -and $_.Name -ne 'font_fixed' } |
        ForEach-Object {
            $section = Get-SectionPrefix $_.Name
            if (-not $section) {
                Write-Warning "Skip folder without numeric prefix: $($_.Name)"
                return
            }

            Get-ChildItem -Path $_.FullName -Filter '*.svg' -File | ForEach-Object {
                $key = '{0}|{1}' -f $section, $_.Name
                $iconBase = if ($SpecialRenames.ContainsKey($key)) {
                    $SpecialRenames[$key]
                } else {
                    & $MakeIconBase $_.Name
                }

                $targetName = & $MakeTargetName $section $iconBase
                if ($usedNames.ContainsKey($targetName)) {
                    $i = 2
                    do {
                        $suffix = '{0}_{1}' -f $iconBase, $i
                        $targetName = & $MakeTargetName $section $suffix
                        $i++
                    } while ($usedNames.ContainsKey($targetName))
                }

                $usedNames[$targetName] = $true
                Copy-Item -Path $_.FullName -Destination (Join-Path $OutputDir $targetName) -Force
                $count++
            }
        }

    return $count
}

$fontCount = Collect-Icons -OutputDir $fontDir -SpecialRenames $specialRenamesFont -MakeIconBase {
    param($name)
    Normalize-FontBase $name
} -MakeTargetName {
    param($section, $iconBase)
    return ('icon_{0}_{1}.svg' -f $section, $iconBase)
}

if (Test-Path $fontFixedDir) { Remove-Item $fontFixedDir -Recurse -Force }
New-Item -ItemType Directory -Path $fontFixedDir | Out-Null
Write-Host "Converting strokes to fills (oslllo-svg-fixer)..."
& npx --yes oslllo-svg-fixer --source $fontDir --destination $fontFixedDir
if ($LASTEXITCODE -ne 0) { throw "svg-fixer failed with exit code $LASTEXITCODE" }
Remove-Item $fontDir -Recurse -Force
Move-Item $fontFixedDir $fontDir

Write-Host "Done: icons/font/ = $fontCount files (stroke-to-fill applied)"
