# One-time setup for a new Windows machine. Run it from PowerShell:
#   irm https://raw.githubusercontent.com/isafuianish-dev/config_windows/main/install.ps1 | iex
# Everything lives in one function so `return` and `throw` behave the same whether this runs through iex or as a file.
# Keep every script in this repo ASCII-only: Windows PowerShell 5.1 reads a BOM-less .ps1 as ANSI, not UTF-8.

function Install-Config {
    $ErrorActionPreference = 'Stop'

    $GithubUser = 'isafuianish-dev'
    $RepoUrl = "https://github.com/$GithubUser/config_windows.git"
    $RawBase = "https://raw.githubusercontent.com/$GithubUser/config_windows/main"
    $RepoDir = Join-Path $HOME 'Developer\projects\configuration\config_windows'

    # Run a native command; native stderr (git's progress output) isn't an error, only a non-zero exit code is.
    function Invoke-Native([scriptblock]$Command, [string]$Failure) {
        $previous = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try { & $Command } finally { $ErrorActionPreference = $previous }
        if ($LASTEXITCODE -ne 0) { throw $Failure }
    }

    # 0. Let PowerShell run local scripts (this repo's, and the profile). Client Windows defaults to Restricted.
    try { Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force }
    catch { Write-Warning "Couldn't set the execution policy: $($_.Exception.Message)" }

    # 1. winget + git aren't guaranteed yet, so fetch and run this one file directly.
    Invoke-RestMethod "$RawBase/other/winget.ps1" | Invoke-Expression

    # Refresh PATH in this session so packages winget just installed (git, etc.) work right away.
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User') + ';' + $env:Path

    # 2. Folder the repo gets cloned into, then git now exists - get the rest of the repo.
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $RepoDir) | Out-Null
    if (Test-Path -LiteralPath (Join-Path $RepoDir '.git')) {
        Invoke-Native { git -C $RepoDir pull --ff-only $RepoUrl main } 'install: failed to update the repo, aborting.'
    } else {
        Invoke-Native { git clone $RepoUrl $RepoDir } 'install: failed to clone the repo, aborting.'
    }

    # 3. Git identity.
    & (Join-Path $RepoDir 'git_setup\git_config.ps1')

    # 4. Git aliases (git born, git bornr, git addremote, ...).
    & (Join-Path $RepoDir 'git_setup\git_alias.ps1')

    # 5. Put this repo's VSCodium settings in place. Windows symlinks need admin or Developer Mode, so try one first and fall back
    #    to a plain copy - if that fallback is used, re-run this script after editing settings.json to pick up changes.
    $vscodiumUserDir = Join-Path $env:APPDATA 'VSCodium\User'
    $settingsLink = Join-Path $vscodiumUserDir 'settings.json'
    $settingsSource = Join-Path $RepoDir 'app_config\vscodium\settings.json'
    New-Item -ItemType Directory -Force -Path $vscodiumUserDir | Out-Null
    Remove-Item -LiteralPath $settingsLink -Force -ErrorAction SilentlyContinue
    try { New-Item -ItemType SymbolicLink -Path $settingsLink -Value $settingsSource | Out-Null }
    catch { Copy-Item -LiteralPath $settingsSource -Destination $settingsLink -Force }

    # 6. Make every PowerShell session load this repo's profile. profile.ps1 (CurrentUserAllHosts) is read by both Windows
    #    PowerShell 5.1 and PowerShell 7. Any earlier line that loads a ps_profile\profile.ps1 (e.g. from before the repo was
    #    moved) is replaced, same effect as install.sh's grep -v/append dance for ~/.bash_profile.
    $profileScript = (Join-Path $RepoDir 'ps_profile\profile.ps1').Replace("'", "''")
    $loadLine = "if (Test-Path -LiteralPath '$profileScript') { . '$profileScript' }"
    $documents = [Environment]::GetFolderPath('MyDocuments')
    foreach ($folder in 'WindowsPowerShell', 'PowerShell') {
        $profileFile = Join-Path $documents "$folder\profile.ps1"
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $profileFile) | Out-Null
        $kept = @()
        if (Test-Path -LiteralPath $profileFile) {
            $kept = @(Get-Content -LiteralPath $profileFile | Where-Object { $_ -notlike '*ps_profile*profile.ps1*' })
        }
        Set-Content -LiteralPath $profileFile -Value ($kept + $loadLine) -Encoding UTF8
    }

    # 6b. Enable ANSI/VT escape processing for the classic console host, so the colored prompt (ps_profile\module\prompt.ps1)
    #     renders correctly outside Windows Terminal (which already supports it without this).
    Set-ItemProperty -Path 'HKCU:\Console' -Name VirtualTerminalLevel -Value 1 -Type DWord

    # 6c. This repo used to be cmd.exe based: drop the old AutoRun hook so cmd doesn't look for the profile.bat that's gone.
    $cmdKey = 'HKCU:\Software\Microsoft\Command Processor'
    $autoRun = (Get-ItemProperty -Path $cmdKey -Name AutoRun -ErrorAction SilentlyContinue).AutoRun
    if ($autoRun -like '*cmd_profile*profile.bat*') { Remove-ItemProperty -Path $cmdKey -Name AutoRun }

    # 7. Optional: Java (Temurin OpenJDK 21). Skip the prompt if there's no real console to ask on.
    if (-not [Console]::IsInputRedirected) {
        $installJava = Read-Host 'Install Java (Temurin OpenJDK 21)? (yes/no)'
        if ($installJava -match '^(?i)y') {
            & (Join-Path $RepoDir 'other\java.ps1')
        }
    }

    # 8. Optional: Android SDK command line tools + AVD emulator. Skip the prompt if there's no real console to ask on.
    if (-not [Console]::IsInputRedirected) {
        $installAndroid = Read-Host 'Install Android SDK command line tools and set up an AVD emulator? (yes/no)'
        if ($installAndroid -match '^(?i)y') {
            & (Join-Path $RepoDir 'other\android.ps1')
        }
    }

    # 9. GitHub tokens (GITHUB_PAT_READ / GITHUB_PAT_READWRITE). Runs before the SSH step so the public key is what's left on the clipboard.
    & (Join-Path $RepoDir 'other\github_pat.ps1')

    # 10. SSH key.
    & (Join-Path $RepoDir 'other\ssh.ps1')

    Write-Host 'Done. Restart your terminal to pick up the new shell and profile.'
}

Install-Config
Remove-Item Function:\Install-Config -ErrorAction SilentlyContinue
