# Installs the Android SDK into %LOCALAPPDATA%\Android\Sdk (the same default location Android Studio
# uses), installs platform-tools + a platform/build-tools/emulator via the `android` CLI, and creates a
# medium_phone AVD. `android sdk install` replaces sdkmanager (deprecated in current cmdline-tools - it
# still works as a compatibility shim, but the new tool is what Google now ships going forward, and no
# longer needs a separate license-acceptance step). AVD creation uses `android emulator create`, not
# avdmanager: it only takes a fixed device profile (phone/tablet/desktop, small/medium/large) and
# auto-provisions whatever system image it needs itself, rather than a pinned API level/custom name -
# fine here since the API-34 platform/build-tools installed below are what an actual build targets; the
# emulator is just for manual testing.
# AVD creation always ends up on an x86_64 system image, even on an ARM64 host (Windows on Arm, e.g.
# Snapdragon X Elite): Google ships no native Windows-ARM64 build of the emulator, and the x86_64
# Windows build refuses arm64-v8a images outright ("System image must match the host architecture").
# So x86_64 is correct here even without real VT-x/AMD-V - see module/android.ps1's start_device, which
# falls back to unaccelerated (software) emulation on an ARM64 host since that's the only way these can
# run there at all.
# There's no winget package for the command-line tools alone, so this fetches Google's repository
# manifest to resolve the current Windows cmdline-tools archive - the same source sdkmanager/android
# itself use to resolve "latest" - instead of hardcoding a build number that goes stale.
# ANDROID_HOME and PATH are set by ps_profile\module\env.ps1 once it's installed.
# Keep this file ASCII-only: Windows PowerShell 5.1 reads a BOM-less .ps1 as ANSI, not UTF-8.
$ErrorActionPreference = 'Stop'

$AndroidHome = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$CmdlineDir = Join-Path $AndroidHome 'cmdline-tools\latest'
$AndroidCli = Join-Path $CmdlineDir 'bin\android.exe'

if (-not (Test-Path -LiteralPath $AndroidCli)) {
    $ProgressPreference = 'SilentlyContinue'   # Windows PowerShell 5.1 downloads much faster without the progress bar

    [xml]$manifest = (Invoke-WebRequest -UseBasicParsing -Uri 'https://dl.google.com/android/repository/repository2-3.xml').Content
    $archive = $manifest.SelectSingleNode("//remotePackage[@path='cmdline-tools;latest']/archives/archive[host-os='windows']/complete/url")
    if (-not $archive) { throw 'Could not find the Windows cmdline-tools download in the Android repository manifest.' }
    $zipUrl = "https://dl.google.com/android/repository/$($archive.InnerText)"

    $zipFile = Join-Path $env:TEMP 'android-cmdline-tools.zip'
    $extractDir = Join-Path $env:TEMP 'android-cmdline-tools-extract'
    Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $zipUrl -OutFile $zipFile
        Expand-Archive -LiteralPath $zipFile -DestinationPath $extractDir -Force

        # The archive's top-level folder is named "cmdline-tools"; the tools expect it at .../cmdline-tools/latest.
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $CmdlineDir) | Out-Null
        Remove-Item -LiteralPath $CmdlineDir -Recurse -Force -ErrorAction SilentlyContinue
        Move-Item -LiteralPath (Join-Path $extractDir 'cmdline-tools') -Destination $CmdlineDir
    } finally {
        Remove-Item -LiteralPath $zipFile -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$ApiLevel = '34'
$packages = @(
    'platform-tools'
    "platforms/android-$ApiLevel"
    "build-tools/$ApiLevel.0.0"
    'emulator'
)
& $AndroidCli "--sdk=$AndroidHome" sdk install @packages
if ($LASTEXITCODE -ne 0) { throw 'android sdk install failed to install the requested packages.' }

$AvdProfile = 'medium_phone'
$existingAvds = & $AndroidCli "--sdk=$AndroidHome" emulator list
if (-not ($existingAvds -contains $AvdProfile)) {
    & $AndroidCli "--sdk=$AndroidHome" emulator create $AvdProfile
}

Write-Host "Android SDK ready at $AndroidHome. Restart your terminal, then run: android emulator start $AvdProfile"
