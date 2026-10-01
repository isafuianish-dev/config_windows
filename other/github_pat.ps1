# Walks through creating the GitHub personal access tokens that other tools read from the environment:
#   GITHUB_PAT_READ       read-only      -> %USERPROFILE%\Developer\secrets\github\pat_read.token
#   GITHUB_PAT_READWRITE  read and write -> %USERPROFILE%\Developer\secrets\github\pat_readwrite.token
# ps_profile\module\env.ps1 sets the variables from those files. Tokens that are already saved are skipped;
# to replace one, delete its file and run this again.
# Keep this file ASCII-only: Windows PowerShell 5.1 reads a BOM-less .ps1 as ANSI, not UTF-8.
$ErrorActionPreference = 'Stop'

$SecretsDir = Join-Path $env:USERPROFILE 'Developer\secrets\github'
$NewTokenUrl = 'https://github.com/settings/personal-access-tokens/new'

# Prompts need a real console; skip if input is piped.
if ([Console]::IsInputRedirected) {
    Write-Host '==> No terminal to prompt on, skipping GitHub tokens. Run other\github_pat.ps1 later.'
    exit 0
}

New-Item -ItemType Directory -Force -Path $SecretsDir | Out-Null

# True if GitHub accepts the token.
function Test-Token([string]$Token) {
    try {
        Invoke-RestMethod -Uri 'https://api.github.com/user' -Headers @{ Authorization = "Bearer $Token" } -TimeoutSec 15 | Out-Null
        return $true
    } catch {
        return $false
    }
}

# Save-Token <env var> <file name> <permissions query string> <access description>
function Save-Token([string]$Var, [string]$FileName, [string]$Permissions, [string]$Access) {
    $file = Join-Path $SecretsDir $FileName

    if ((Test-Path $file) -and ((Get-Item $file).Length -gt 0)) {
        Write-Host "==> $Var already saved in $file, skipping."
        return
    }

    $name = ("${Var}-${env:COMPUTERNAME}" -replace '_', '-').ToLower()
    if ($name.Length -gt 40) { $name = $name.Substring(0, 40) }
    $url = "${NewTokenUrl}?name=${name}&description=Exposed+as+${Var}+by+config_windows&${Permissions}"

    Write-Host ''
    Write-Host "==> $Var ($Access token)"
    Write-Host '    GitHub will open with the name and permissions filled in. Pick an expiration and'
    Write-Host "    'Repository access' (All repositories, if you'll use it across projects), click"
    Write-Host "    'Generate token', copy it, and paste it here."
    Write-Host "    $url"
    $answer = Read-Host "    Press Enter to open it (or type 'skip')"
    if ($answer -eq 'skip') {
        Write-Host "    Skipped $Var."
        return
    }
    try { Start-Process $url } catch { }

    while ($true) {
        $secure = Read-Host '    Paste the token (hidden; Enter to skip)' -AsSecureString
        $token = (New-Object System.Net.NetworkCredential('', $secure)).Password -replace '\s', ''
        if (-not $token) {
            Write-Host "    Skipped $Var."
            return
        }
        if (Test-Token $token) { break }
        Write-Host '    GitHub rejected that token (or could not be reached). Try again.'
    }

    [System.IO.File]::WriteAllText($file, $token)   # UTF-8 without BOM, no trailing newline
    try { Set-Clipboard -Value $null } catch { }    # don't leave the token on the clipboard
    Write-Host "    Saved to $file"
}

Save-Token 'GITHUB_PAT_READ' 'pat_read.token' 'contents=read&pull_requests=read&issues=read' 'read-only'
Save-Token 'GITHUB_PAT_READWRITE' 'pat_readwrite.token' 'contents=write&pull_requests=write&issues=write&workflows=write' 'read and write'
