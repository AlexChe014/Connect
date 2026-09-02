#Requires -Version 5.1
<#
.SYNOPSIS
  Release-сборки Android: AAB для Play Store и/или split APK по ABI.

.EXAMPLE
  .\tool\build_android.ps1
  .\tool\build_android.ps1 -Format aab
  .\tool\build_android.ps1 -Format apk
#>
param(
    [ValidateSet("aab", "apk", "all")]
    [string]$Format = "all"
)

$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

# Телефоны: 32-bit ARM + arm64. x86_64 нужен только эмулятору / ChromeOS.
$platforms = "android-arm,android-arm64"

function Invoke-FlutterBuild([string[]]$FlutterArgs) {
    Write-Host ">> flutter $($FlutterArgs -join ' ')" -ForegroundColor Cyan
    & flutter @FlutterArgs
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

if ($Format -eq "aab" -or $Format -eq "all") {
    Invoke-FlutterBuild @(
        "build", "appbundle", "--release",
        "--target-platform", $platforms
    )
    Write-Host "AAB: build\app\outputs\bundle\release\app-release.aab"
}

if ($Format -eq "apk" -or $Format -eq "all") {
    Invoke-FlutterBuild @(
        "build", "apk", "--release", "--split-per-abi",
        "--target-platform", $platforms
    )
    Write-Host "APK: build\app\outputs\flutter-apk\app-armeabi-v7a-release.apk"
    Write-Host "APK: build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"
}
