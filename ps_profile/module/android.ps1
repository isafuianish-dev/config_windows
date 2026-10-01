# Functions for working with the Android SDK via the `android` CLI (see other/android.ps1). Only loaded
# by profile.ps1 when %LOCALAPPDATA%\Android\Sdk exists, so these are undefined until Android is set up.
# Ported from config_macos's android.sh, so the two platforms have the same commands and messages where
# the platforms allow it. Names prefixed with _android_ are internal helpers, not meant to be called
# directly. Signing credentials are read from a dot-sourced credentials.ps1 (not bash-style
# credentials.env - see create_signing_key) since PowerShell has no `source` for .env files.
# Keep this file ASCII-only: Windows PowerShell 5.1 reads a BOM-less .ps1 as ANSI, not UTF-8.

function global:_android_cli {
    Join-Path $env:ANDROID_HOME 'cmdline-tools\latest\bin\android.exe'
}

# avdmanager binary - only needed for car AVDs (see create_car_device): the `android` CLI's own
# `emulator create` only offers phone/tablet/desktop profiles, not Android Automotive.
function global:_android_avdmanager_bin {
    Join-Path $env:ANDROID_HOME 'cmdline-tools\latest\bin\avdmanager.bat'
}

# Is this host ARM64 (e.g. Windows on Arm / Snapdragon X)? Google ships no native Windows-ARM64 build of
# the emulator, and its x86_64 Windows build refuses arm64-v8a system images outright - so on these
# hosts the AVD (always x86_64, see other/android.ps1) can only run unaccelerated. See start_device.
function global:_android_is_arm64_host {
    $env:PROCESSOR_ARCHITECTURE -eq 'ARM64'
}

# Raw emulator.exe path. Needed on an ARM64 host to pass -no-accel directly, since the `android` CLI's
# own `emulator start` has no flag for that.
function global:_android_emulator_bin {
    Join-Path $env:ANDROID_HOME 'emulator\emulator.exe'
}

# Newest installed build-tools directory (holds aapt.exe/aapt2.exe/apksigner.bat).
function global:_android_build_tools_dir {
    Get-ChildItem -LiteralPath (Join-Path $env:ANDROID_HOME 'build-tools') -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name |
        Select-Object -Last 1 -ExpandProperty FullName
}

# Run an `android` subcommand, printing its output. Some subcommands (e.g. `emulator create` on a name
# that already exists) print "Error: ..." but still exit 0, so check the output too, not just the status.
function global:_android_run {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$CliArgs)
    $output = & (_android_cli) "--sdk=$env:ANDROID_HOME" @CliArgs 2>&1
    $status = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
    if ($status -ne 0) { return $false }
    return -not ($output -match '^Error:')
}

# AVD names, one per line.
function global:_android_avd_names {
    & (_android_cli) "--sdk=$env:ANDROID_HOME" emulator list 2>$null
}

# "label|serial" for every device adb sees as ready, resolving emulators to their AVD name.
function global:_android_running_devices {
    $lines = adb devices 2>$null
    foreach ($line in $lines) {
        if ($line -notmatch '^(?<serial>\S+)\s+(?<state>\S+)$') { continue }
        $serial = $Matches['serial']
        $state = $Matches['state']
        if ($state -ne 'device') { continue }
        if ($serial -like 'emulator-*') {
            $avd = (adb -s $serial emu avd name 2>$null | Select-Object -First 1)
            if ($avd) { "$avd|$serial" } else { "$serial|$serial" }
        } else {
            "$serial|$serial"
        }
    }
}

# Prompt to pick one of the given names, printing numbered options. Auto-picks if there's only one.
# Returns $null (and prints nothing further) if the list is empty or the choice is invalid.
function global:_android_pick {
    param([string]$Prompt, [string[]]$Names)
    if (-not $Names -or $Names.Count -eq 0) { return $null }
    if ($Names.Count -eq 1) { return $Names[0] }
    Write-Host $Prompt
    for ($i = 0; $i -lt $Names.Count; $i++) {
        Write-Host ("  {0}) {1}" -f ($i + 1), $Names[$i])
    }
    $choice = Read-Host 'Enter a number'
    if ($choice -notmatch '^\d+$' -or [int]$choice -lt 1 -or [int]$choice -gt $Names.Count) {
        Write-Host 'Invalid selection.'
        return $null
    }
    return $Names[[int]$choice - 1]
}

# Is the given AVD currently running? (adb, not the `android` CLI's own status column, is the ground truth.)
function global:_android_avd_running([string]$Name) {
    foreach ($entry in (_android_running_devices)) {
        if ($entry.Split('|')[0] -eq $Name) { return $true }
    }
    return $false
}

# List every virtual device with its current status (running/stopped).
function global:list_device {
    $names = @(_android_avd_names)
    if ($names.Count -eq 0) { return (_fail 'list_device: no virtual devices found.') }

    foreach ($name in $names) {
        $status = if (_android_avd_running $name) { 'running' } else { 'stopped' }
        Write-Host ("{0,-30} {1}" -f $name, $status)
    }
    $global:LASTEXITCODE = 0
}

# Ask which stopped virtual device to start, launch it in the background, and wait for adb to see it.
function global:start_device {
    $names = @(_android_avd_names)
    if ($names.Count -eq 0) { return (_fail 'start_device: no virtual devices found.') }

    $name = _android_pick 'Which device to start?' $names
    if (-not $name) { $global:LASTEXITCODE = 1; return }

    if (_android_avd_running $name) {
        return (_fail "start_device: '$name' is already running.")
    }

    if (_android_is_arm64_host) {
        Write-Host "start_device: this host has no emulator hardware acceleration (ARM64 Windows), launching '$name' with software emulation - this is much slower than normal, can take several minutes..."
        Start-Process -FilePath (_android_emulator_bin) -ArgumentList @('-avd', $name, '-no-accel', '-no-window') -WindowStyle Hidden
    } else {
        Write-Host "start_device: launching '$name' in the background, this can take a minute..."
        Start-Process -FilePath (_android_cli) -ArgumentList @("--sdk=$env:ANDROID_HOME", 'emulator', 'start', $name) -WindowStyle Hidden
    }

    $maxWaitSeconds = if (_android_is_arm64_host) { 600 } else { 120 }
    for ($waited = 0; $waited -lt $maxWaitSeconds; $waited += 2) {
        if (_android_avd_running $name) {
            Write-Host "start_device: '$name' is up."
            $global:LASTEXITCODE = 0
            return
        }
        Start-Sleep -Seconds 2
    }

    return (_fail "start_device: '$name' didn't come up within $($maxWaitSeconds / 60) minutes, check it manually.")
}

# Ask which running virtual device to stop, then stop it.
function global:stop_device {
    $names = @(_android_avd_names)
    if ($names.Count -eq 0) { return (_fail 'stop_device: no virtual devices found.') }

    $running = @($names | Where-Object { _android_avd_running $_ })
    if ($running.Count -eq 0) { return (_fail 'stop_device: no running devices found.') }

    $name = _android_pick 'Which device to stop?' $running
    if (-not $name) { $global:LASTEXITCODE = 1; return }

    if (_android_run emulator stop $name) { $global:LASTEXITCODE = 0 } else { $global:LASTEXITCODE = 1 }
}

# Create a new virtual device, asking which device profile to use.
function global:create_device {
    $profiles = & (_android_cli) "--sdk=$env:ANDROID_HOME" emulator create --list-profiles 2>$null
    if (-not $profiles) { return (_fail "create_device: couldn't list device profiles, aborting.") }

    $profile = _android_pick 'Which device profile?' $profiles
    if (-not $profile) { $global:LASTEXITCODE = 1; return }

    if (_android_run emulator create $profile) { $global:LASTEXITCODE = 0 } else { $global:LASTEXITCODE = 1 }
}

# avdmanager device-definition ids (e.g. "automotive_1024p_landscape") for every Android Automotive
# dashboard profile avdmanager knows about.
function global:_android_car_profiles {
    $id = $null
    & (_android_avdmanager_bin) list device 2>$null | ForEach-Object {
        if ($_ -match '^id: .*"([^"]*)"') {
            $id = $Matches[1]
        } elseif ($_ -match '^    Tag : (.*)$') {
            if ($Matches[1] -match 'automotive') { $id }
        }
    }
}

# Package id (e.g. "system-images/android-34/android-automotive-playstore/x86_64") of the newest
# available android-automotive[-playstore] system image for the host's ABI. $Variant is "playstore" or
# "aosp".
function global:_android_car_system_image([string]$Variant) {
    $abi = 'x86_64'
    if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { $abi = 'arm64-v8a' }
    $tag = 'android-automotive'
    if ($Variant -eq 'playstore') { $tag = 'android-automotive-playstore' }

    $pattern = "^  (system-images/[^/]+/$tag/$abi)\s"
    & (_android_cli) "--sdk=$env:ANDROID_HOME" sdk list --all "system-images/*/$tag/$abi" 2>$null |
        ForEach-Object { if ($_ -match $pattern) { $Matches[1] } } |
        Sort-Object { [int]($_ -replace '.*android-(\d+).*', '$1') } |
        Select-Object -Last 1
}

# Create a new AVD for Android Automotive (car), asking which dashboard profile to use and whether to
# include Google Play. Unlike create_device, this goes through avdmanager directly and installs the
# system image itself: the `android` CLI's own `emulator create --list-profiles` only knows about
# phone/tablet/desktop, not car, so it can't create or provision one.
function global:create_car_device {
    $profiles = @(_android_car_profiles)
    if ($profiles.Count -eq 0) { return (_fail "create_car_device: couldn't list car device profiles, aborting.") }

    $profile = _android_pick 'Which car dashboard profile?' $profiles
    if (-not $profile) { $global:LASTEXITCODE = 1; return }

    $confirm = Read-Host 'Include Google Play? [y/N]'
    $variant = 'aosp'
    if ($confirm -match '^[Yy]') { $variant = 'playstore' }

    $imageSlash = _android_car_system_image $variant
    if (-not $imageSlash) {
        return (_fail 'create_car_device: no car system image found for this host, aborting.')
    }
    $image = $imageSlash -replace '/', ';'

    $name = Read-Host "New AVD name [$profile]"
    if (-not $name) { $name = $profile }

    $avdRoot = Join-Path $HOME '.android\avd'
    if ((Test-Path -LiteralPath (Join-Path $avdRoot "$name.avd")) -or (Test-Path -LiteralPath (Join-Path $avdRoot "$name.ini"))) {
        return (_fail "create_car_device: '$name' already exists, aborting.")
    }

    Write-Host "create_car_device: installing '$imageSlash' (this can take a while the first time)..."
    & (_android_cli) "--sdk=$env:ANDROID_HOME" sdk install $imageSlash
    if ($LASTEXITCODE -ne 0) {
        return (_fail "create_car_device: failed to install '$imageSlash', aborting.")
    }

    'no' | & (_android_avdmanager_bin) create avd --name $name --package $image --device $profile
    if ($LASTEXITCODE -ne 0) {
        return (_fail "create_car_device: avdmanager failed to create '$name', aborting.")
    }

    Write-Host "create_car_device: created '$name' ($profile, $image)."
    $global:LASTEXITCODE = 0
}

# Ask which virtual device to delete, then delete it. DESTRUCTIVE.
function global:delete_device {
    $names = @(_android_avd_names)
    if ($names.Count -eq 0) { return (_fail 'delete_device: no virtual devices found.') }

    $name = _android_pick 'Which device to delete?' $names
    if (-not $name) { $global:LASTEXITCODE = 1; return }

    $confirm = Read-Host "Type 'yes' to permanently delete '$name'"
    if ($confirm -cne 'yes') {
        Write-Host 'delete_device: aborted.'
        $global:LASTEXITCODE = 1
        return
    }

    if (_android_run emulator remove $name) { $global:LASTEXITCODE = 0 } else { $global:LASTEXITCODE = 1 }
}

# Clone a virtual device to a new name. There's no native `android emulator clone`, so this copies the
# AVD's files directly and rewrites the name/paths inside them.
function global:clone_device {
    $names = @(_android_avd_names)
    if ($names.Count -eq 0) { return (_fail 'clone_device: no virtual devices found.') }

    $src = _android_pick 'Which device to clone?' $names
    if (-not $src) { $global:LASTEXITCODE = 1; return }

    if (_android_avd_running $src) {
        return (_fail "clone_device: '$src' is currently running, stop it first ('android emulator stop $src'), aborting.")
    }

    $dest = Read-Host 'New device name'
    if (-not $dest) { return (_fail "clone_device: name can't be empty, aborting.") }

    $avdRoot = Join-Path $HOME '.android\avd'
    $srcDir = Join-Path $avdRoot "$src.avd"
    $destDir = Join-Path $avdRoot "$dest.avd"
    $srcIni = Join-Path $avdRoot "$src.ini"
    $destIni = Join-Path $avdRoot "$dest.ini"

    if (-not (Test-Path -LiteralPath $srcDir)) {
        return (_fail "clone_device: couldn't find '$srcDir', aborting.")
    }
    if ((Test-Path -LiteralPath $destDir) -or (Test-Path -LiteralPath $destIni)) {
        return (_fail "clone_device: '$dest' already exists, aborting.")
    }

    try { Copy-Item -LiteralPath $srcDir -Destination $destDir -Recurse -ErrorAction Stop }
    catch { return (_fail 'clone_device: failed to copy the AVD directory, aborting.') }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    $iniLines = Get-Content -LiteralPath $srcIni | ForEach-Object {
        if ($_ -match '^path=') { "path=$destDir" }
        elseif ($_ -match '^path\.rel=') { "path.rel=avd\$dest.avd" }
        else { $_ }
    }
    [System.IO.File]::WriteAllLines($destIni, $iniLines, $utf8NoBom)

    $configPath = Join-Path $destDir 'config.ini'
    $configLines = Get-Content -LiteralPath $configPath | ForEach-Object {
        if ($_ -match '^AvdId=') { "AvdId=$dest" }
        elseif ($_ -match '^avd\.ini\.displayname=') { "avd.ini.displayname=$dest" }
        else { $_ }
    }
    [System.IO.File]::WriteAllLines($configPath, $configLines, $utf8NoBom)

    Write-Host "clone_device: cloned '$src' to '$dest'."
    $global:LASTEXITCODE = 0
}

# Wipe a virtual device's user data (installed apps, settings) for a fresh start, without deleting the
# device itself.
function global:wipe_device {
    $names = @(_android_avd_names)
    if ($names.Count -eq 0) { return (_fail 'wipe_device: no virtual devices found.') }

    $name = _android_pick 'Which device to wipe?' $names
    if (-not $name) { $global:LASTEXITCODE = 1; return }

    if (_android_avd_running $name) {
        return (_fail "wipe_device: '$name' is currently running, stop it first ('android emulator stop $name'), aborting.")
    }

    $avdDir = Join-Path $HOME ".android\avd\$name.avd"
    if (-not (Test-Path -LiteralPath $avdDir)) {
        return (_fail "wipe_device: couldn't find '$avdDir', aborting.")
    }

    # -Path with a trailing '\*' (not -LiteralPath $avdDir) is required for -Include to actually filter;
    # otherwise Get-ChildItem silently ignores -Include and returns everything, including config.ini.
    Get-ChildItem -Path (Join-Path $avdDir '*') -Include '*.img', '*.img.qcow2', '*.lock' -File -ErrorAction SilentlyContinue |
        Remove-Item -Force
    Remove-Item -LiteralPath (Join-Path $avdDir 'snapshots') -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "wipe_device: '$name' wiped, will start fresh next launch."
    $global:LASTEXITCODE = 0
}

# Generate an APK signing key + $env:SECRET_DIR\<current dir name>\credentials.ps1, e.g. run from your
# project root. Your app's build.gradle.kts release signingConfig should read KEYSTORE_PATH/
# KEYSTORE_PASSWORD/KEY_ALIAS/KEY_PASSWORD from the environment; create_release_apk dot-sources this
# file before building so those variables are set.
function global:create_signing_key {
    if (-not (Get-Command keytool -ErrorAction SilentlyContinue)) {
        return (_fail "create_signing_key: keytool not found (needs Java: .\other\java.ps1), aborting.")
    }
    if (-not $env:SECRET_DIR) {
        return (_fail 'create_signing_key: $env:SECRET_DIR is not set, aborting.')
    }

    $project = Split-Path -Leaf (Get-Location).Path
    $displayName = $project -replace '^android_', ''
    $keyDir = Join-Path $env:SECRET_DIR $project
    $keystore = Join-Path $keyDir 'release.jks'

    if (Test-Path -LiteralPath $keystore) {
        return (_fail "create_signing_key: '$keystore' already exists, aborting.")
    }

    $alias = Read-Host "Key alias [$displayName]"
    if (-not $alias) { $alias = $displayName }

    $storeSecure = Read-Host 'Keystore password (hidden)' -AsSecureString
    $storePass = (New-Object System.Net.NetworkCredential('', $storeSecure)).Password
    $keySecure = Read-Host 'Key password (hidden, Enter to reuse keystore password)' -AsSecureString
    $keyPass = (New-Object System.Net.NetworkCredential('', $keySecure)).Password
    if (-not $keyPass) { $keyPass = $storePass }

    New-Item -ItemType Directory -Force -Path $keyDir | Out-Null
    keytool -genkeypair -v `
        -keystore $keystore `
        -alias $alias `
        -keyalg RSA -keysize 2048 -validity 10000 `
        -dname "CN=$alias" `
        -storepass $storePass -keypass $keyPass
    if ($LASTEXITCODE -ne 0) { return (_fail 'create_signing_key: keytool failed, aborting.') }

    $credentialsPath = Join-Path $keyDir 'credentials.ps1'
    @(
        "`$env:KEYSTORE_PATH = '$keystore'"
        "`$env:KEYSTORE_PASSWORD = '$storePass'"
        "`$env:KEY_ALIAS = '$alias'"
        "`$env:KEY_PASSWORD = '$keyPass'"
    ) | Set-Content -LiteralPath $credentialsPath -Encoding UTF8

    Write-Host "create_signing_key: created '$keystore' (alias '$alias') and '$credentialsPath'."
    $global:LASTEXITCODE = 0
}

# Build a debug APK from the Gradle project in the current directory.
function global:create_debug_apk {
    if (-not (Test-Path -LiteralPath '.\gradlew.bat')) {
        return (_fail "create_debug_apk: no .\gradlew.bat found in $((Get-Location).Path), aborting.")
    }
    & .\gradlew.bat assembleDebug
    if ($LASTEXITCODE -ne 0) { return (_fail 'create_debug_apk: gradle build failed, aborting.') }

    Get-ChildItem -Recurse -Filter '*.apk' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\outputs\\apk\\debug\\' } |
        Select-Object -ExpandProperty FullName
    $global:LASTEXITCODE = 0
}

# Build, sign-verify, and version-name a release APK from the Gradle project in the current directory,
# copying it to dist\<name>_v<version>.apk (older versions there are left alone). Reads signing
# credentials from $env:SECRET_DIR\<current dir name>\credentials.ps1 (see create_signing_key).
# Usage: create_release_apk [versionName] [versionCode]
function global:create_release_apk {
    param([string]$VersionName, [string]$VersionCode)

    if (-not (Test-Path -LiteralPath '.\gradlew.bat')) {
        return (_fail "create_release_apk: no .\gradlew.bat found in $((Get-Location).Path), aborting.")
    }
    if (-not $env:SECRET_DIR) {
        return (_fail 'create_release_apk: $env:SECRET_DIR is not set, aborting.')
    }

    $project = Split-Path -Leaf (Get-Location).Path
    $displayName = $project -replace '^android_', ''
    $credentials = Join-Path $env:SECRET_DIR "$project\credentials.ps1"

    if (-not (Test-Path -LiteralPath $credentials)) {
        return (_fail "create_release_apk: no signing credentials at '$credentials'. Run create_signing_key first, aborting.")
    }
    . $credentials

    $gradleArgs = @()
    if ($VersionName) { $gradleArgs += "-PversionName=$VersionName" }
    if ($VersionCode) { $gradleArgs += "-PversionCode=$VersionCode" }

    $apk = '.\app\build\outputs\apk\release\app-release.apk'
    Remove-Item -LiteralPath $apk -Force -ErrorAction SilentlyContinue

    & .\gradlew.bat ':app:assembleRelease' @gradleArgs
    if ($LASTEXITCODE -ne 0) { return (_fail 'create_release_apk: gradle build failed, aborting.') }
    if (-not (Test-Path -LiteralPath $apk)) {
        return (_fail "create_release_apk: build succeeded but '$apk' wasn't produced, aborting.")
    }

    $buildTools = _android_build_tools_dir
    $apksigner = if ($buildTools) { Join-Path $buildTools 'apksigner.bat' }
    $aapt2 = if ($buildTools) { Join-Path $buildTools 'aapt2.exe' }
    if (-not $apksigner -or -not (Test-Path -LiteralPath $apksigner) -or -not (Test-Path -LiteralPath $aapt2)) {
        Write-Host "create_release_apk: built '$apk' (apksigner/aapt2 not found, so the signature/version wasn't checked)."
        $global:LASTEXITCODE = 0
        return
    }

    $certs = & $apksigner verify --verbose --print-certs $apk 2>&1
    if ($certs -match 'CN=Android Debug') {
        return (_fail 'create_release_apk: the APK is signed with the debug key, not your release key, aborting.')
    }

    $badging = & $aapt2 dump badging $apk 2>$null
    $versionMatch = $badging | Select-String "^package:.* versionName='([^']*)'" | Select-Object -First 1
    if (-not $versionMatch) {
        return (_fail "create_release_apk: couldn't read the version from '$apk', aborting.")
    }
    $version = $versionMatch.Matches[0].Groups[1].Value

    $distDir = '.\dist'
    New-Item -ItemType Directory -Force -Path $distDir | Out-Null
    $namedApk = Join-Path $distDir "${displayName}_v$version.apk"
    Copy-Item -LiteralPath $apk -Destination $namedApk -Force

    $sizeMb = [math]::Round((Get-Item -LiteralPath $namedApk).Length / 1MB, 1)
    Write-Host "Release APK: $namedApk ($sizeMb MB)"
    $certs | Select-String 'certificate DN' | Select-Object -First 1 | ForEach-Object { Write-Host "  $($_.Line.Trim())" }
    $certs | Select-String 'certificate SHA-256' | Select-Object -First 1 | ForEach-Object { Write-Host "  $($_.Line.Trim())" }
    $global:LASTEXITCODE = 0
}

# Install and launch the most recently built APK whose full path matches $ApkPattern (a regex), on a
# running device, asking which one if more than one is running. Shared by run_debug_apk/run_release_apk.
function global:_android_deploy {
    param([string]$ApkPattern, [string]$Verb)

    $apk = Get-ChildItem -Recurse -Filter '*.apk' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match $ApkPattern } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1 -ExpandProperty FullName

    if (-not $apk) {
        return (_fail "${Verb}: no built APK found under $((Get-Location).Path), build one first.")
    }

    $entries = @(_android_running_devices)
    if ($entries.Count -eq 0) {
        return (_fail "${Verb}: no running device or emulator found. Start one first (e.g. 'android emulator start <name>'), aborting.")
    }

    if ($entries.Count -eq 1) {
        $serial = $entries[0].Split('|')[1]
    } else {
        Write-Host 'Multiple devices are running:'
        for ($i = 0; $i -lt $entries.Count; $i++) {
            Write-Host ("  {0}) {1}" -f ($i + 1), $entries[$i].Split('|')[0])
        }
        $choice = Read-Host 'Deploy to which one? Enter a number'
        if ($choice -notmatch '^\d+$' -or [int]$choice -lt 1 -or [int]$choice -gt $entries.Count) {
            return (_fail "${Verb}: invalid selection, aborting.")
        }
        $serial = $entries[[int]$choice - 1].Split('|')[1]
    }

    Write-Host "Installing $apk on $serial..."
    adb -s $serial install -r $apk
    if ($LASTEXITCODE -ne 0) { return (_fail "${Verb}: install failed, aborting.") }

    $buildTools = _android_build_tools_dir
    $aapt = if ($buildTools) { Join-Path $buildTools 'aapt.exe' }
    if (-not $aapt -or -not (Test-Path -LiteralPath $aapt)) {
        Write-Host "${Verb}: installed, but couldn't find aapt to determine the launch activity."
        $global:LASTEXITCODE = 0
        return
    }

    $badging = & $aapt dump badging $apk 2>$null
    $pkgMatch = $badging | Select-String "^package: name='([^']*)'" | Select-Object -First 1
    $activityMatch = $badging | Select-String "^launchable-activity: name='([^']*)'" | Select-Object -First 1
    if (-not $pkgMatch -or -not $activityMatch) {
        Write-Host "${Verb}: installed, but couldn't determine the launch activity."
        $global:LASTEXITCODE = 0
        return
    }
    $pkg = $pkgMatch.Matches[0].Groups[1].Value
    $activity = $activityMatch.Matches[0].Groups[1].Value

    adb -s $serial shell am start -n "$pkg/$activity" | Out-Null
    Write-Host "${Verb}: launched $pkg on $serial."
    $global:LASTEXITCODE = 0
}

# Deploy the most recently built debug APK to a running device, asking which one if several are running.
function global:run_debug_apk {
    _android_deploy '\\outputs\\apk\\debug\\.*\.apk$' 'run_debug_apk'
}

# Deploy the most recently built release APK (from dist\, see create_release_apk) to a running device,
# asking which one if several are running.
function global:run_release_apk {
    _android_deploy '\\dist\\[^\\]*\.apk$' 'run_release_apk'
}

# Print every function in this file with a one-line description, plus a few things worth remembering.
function global:android_help {
    $esc = [char]27
    $reset = "$esc[0m"; $bold = "$esc[1m"
    $title = "$esc[1;36m"; $fn = "$esc[1;33m"; $destr = "$esc[1;31m"; $desc = "$esc[0;37m"; $note = "$esc[1;35m"

    # name, alias, description - DESTRUCTIVE entries are colored as a warning instead of the normal function color.
    $entries = @(
        [pscustomobject]@{ Name = 'list_device'; Alias = 'adld'; Desc = 'List every AVD with its status (running/stopped).' }
        [pscustomobject]@{ Name = 'start_device'; Alias = 'adstd'; Desc = 'Start a chosen AVD in the background, waits for adb to see it.' }
        [pscustomobject]@{ Name = 'stop_device'; Alias = 'adspd'; Desc = 'Stop a chosen running AVD.' }
        [pscustomobject]@{ Name = 'create_device'; Alias = 'adcrd'; Desc = 'Create a new AVD, asking which device profile to use.' }
        [pscustomobject]@{ Name = 'create_car_device'; Alias = 'adccd'; Desc = 'Create a new Android Automotive (car) AVD, installing its system image.' }
        [pscustomobject]@{ Name = 'delete_device'; Alias = 'addd'; Desc = 'DESTRUCTIVE: permanently delete an AVD.' }
        [pscustomobject]@{ Name = 'clone_device'; Alias = 'adcld'; Desc = "Duplicate an AVD's files under a new name." }
        [pscustomobject]@{ Name = 'wipe_device'; Alias = 'adwd'; Desc = "Clear an AVD's user data for a fresh start, keeping the AVD." }
        [pscustomobject]@{ Name = 'create_signing_key'; Alias = 'adcsk'; Desc = 'Generate a release keystore + credentials.ps1 for the current project dir.' }
        [pscustomobject]@{ Name = 'create_debug_apk'; Alias = 'adcda'; Desc = 'Build a debug APK with Gradle for the current project dir.' }
        [pscustomobject]@{ Name = 'create_release_apk'; Alias = 'adcra'; Desc = 'Build, sign-verify, and version a release APK for the current project dir.' }
        [pscustomobject]@{ Name = 'run_debug_apk'; Alias = 'adrda'; Desc = 'Install + launch the latest debug APK on a running device.' }
        [pscustomobject]@{ Name = 'run_release_apk'; Alias = 'adrra'; Desc = 'Install + launch the latest release APK on a running device.' }
    )

    Write-Host ($title + $bold + 'Android functions' + $reset + "`n")

    foreach ($entry in $entries) {
        $color = if ($entry.Desc.StartsWith('DESTRUCTIVE:')) { $destr } else { $fn }
        $namePadded = $entry.Name.PadRight(19)
        Write-Host ('  ' + $color + $bold + $namePadded + $reset + ' ' + $desc + '(' + $entry.Alias + ') ' + $entry.Desc + $reset)
    }

    Write-Host ("`n" + $note + $bold + 'Remember' + $reset)
    Write-Host ('  ' + $note + '*' + $reset + ' "device" = AVD, never a physical phone.')
    Write-Host ('  ' + $note + '*' + $reset + ' Needs $env:ANDROID_HOME set up (other\android.ps1).')
    Write-Host ('  ' + $note + '*' + $reset + ' On ARM64 Windows (e.g. Snapdragon X), start_device falls back to slow, unaccelerated software emulation - there is no accelerated path on that hardware.')
    Write-Host ('  ' + $note + '*' + $reset + " create_signing_key/create_debug_apk/create_release_apk/run_debug_apk/run_release_apk run from the project's root directory.")
    Write-Host ('  ' + $note + '*' + $reset + ' create_signing_key and create_release_apk need $env:SECRET_DIR set.')
    Write-Host ('  ' + $note + '*' + $reset + " create_car_device uses avdmanager, not the 'android' CLI, and can be slow first run.")
    Write-Host ('  ' + $note + '*' + $destr + $bold + 'delete_device/wipe_device are irreversible' + $reset + $note + ' - both confirm first.' + $reset)
    Write-Host ('  ' + $note + '*' + $reset + ' run_debug_apk/run_release_apk need a device already running (start_device first).')
}

# Short aliases for the functions above, each prefixed "ad" (Android Dev) + the function's word initials.
function global:adld { list_device @args }
function global:adstd { start_device @args }
function global:adspd { stop_device @args }
function global:adcrd { create_device @args }
function global:adccd { create_car_device @args }
function global:addd { delete_device @args }
function global:adcld { clone_device @args }
function global:adwd { wipe_device @args }
function global:adcsk { create_signing_key @args }
function global:adcda { create_debug_apk @args }
function global:adcra { create_release_apk @args }
function global:adrda { run_debug_apk @args }
function global:adrra { run_release_apk @args }
function global:adah { android_help @args }
