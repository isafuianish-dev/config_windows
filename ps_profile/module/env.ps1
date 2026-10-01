# Environment variables for this session. GitHub tokens are backed by files under ~/Developer/secrets
# (a missing or empty file just leaves its variable unset); SECRET_DIR just points at that directory
# itself (creating it if needed); the Java and Android SDK blocks below instead detect an existing install.

# --- GitHub tokens (created by other/github_pat.ps1) ---
& {
    $dir = Join-Path $HOME 'Developer/secrets/github'
    $tokens = [ordered]@{
        GITHUB_PAT_READ      = 'pat_read.token'
        GITHUB_PAT_READWRITE = 'pat_readwrite.token'
    }

    foreach ($name in $tokens.Keys) {
        $file = Join-Path $dir $tokens[$name]
        if ((Test-Path -LiteralPath $file) -and ((Get-Item -LiteralPath $file).Length -gt 0)) {
            Set-Item -Path "Env:$name" -Value ((Get-Content -LiteralPath $file -Raw).Trim())
        }
    }
}

# --- Secrets directory root (holds Android signing keys, among other things) ---
& {
    $secretDir = Join-Path $HOME 'Developer\secrets'
    New-Item -ItemType Directory -Force -Path $secretDir | Out-Null
    $env:SECRET_DIR = $secretDir
}

# --- Java: only when Temurin OpenJDK 21 is installed (see other/java.ps1) ---
& {
    $jdkRoot = Get-ChildItem -Path 'C:\Program Files\Eclipse Adoptium' -Filter 'jdk-21*-hotspot' -Directory -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($jdkRoot) {
        $env:JAVA_HOME = $jdkRoot.FullName
        $env:Path = (Join-Path $env:JAVA_HOME 'bin') + ';' + $env:Path
    }
}

# --- Android SDK: only when it exists at Android Studio's default location (see other/android.ps1) ---
& {
    $androidHome = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
    if (Test-Path -LiteralPath $androidHome) {
        $env:ANDROID_HOME = $androidHome
        $env:ANDROID_SDK_ROOT = $androidHome
        $env:Path = (Join-Path $androidHome 'cmdline-tools\latest\bin') + ';' + (Join-Path $androidHome 'platform-tools') + ';' + (Join-Path $androidHome 'emulator') + ';' + $env:Path
    }
}
