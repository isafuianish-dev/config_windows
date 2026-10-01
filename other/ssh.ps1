# Generates an SSH key for this machine (if one doesn't already exist), using Windows' built-in OpenSSH Client
# (ssh-keygen/ssh-agent/ssh-add ship with Windows 10 1803+ / 11 already - no extra tool needed).
$ErrorActionPreference = 'Continue'

$SshEmail = 'isafuianish.dev@outlook.com'
$SshDir = Join-Path $HOME '.ssh'
$SshKey = Join-Path $SshDir 'id_ssh_isafuianish-dev'

if (-not (Get-Command ssh-keygen -ErrorAction SilentlyContinue)) {
    throw 'ssh-keygen was not found. Enable it via Settings > Apps > Optional Features > Add a feature > "OpenSSH Client", then re-run this script.'
}

New-Item -ItemType Directory -Force -Path $SshDir | Out-Null

if (-not (Test-Path -LiteralPath $SshKey)) {
    # Start-Process rather than `ssh-keygen ... -N ""`: Windows PowerShell 5.1 silently drops an empty-string argument to a native command.
    $keygen = Start-Process -FilePath 'ssh-keygen' -ArgumentList "-t ed25519 -C `"$SshEmail`" -f `"$SshKey`" -N `"`"" -NoNewWindow -Wait -PassThru
    if ($keygen.ExitCode -ne 0) { throw 'ssh-keygen failed.' }
}

$config = Join-Path $SshDir 'config'
$configured = (Test-Path -LiteralPath $config) -and (Select-String -LiteralPath $config -SimpleMatch $SshKey -Quiet)
if (-not $configured) {
    Add-Content -LiteralPath $config -Value @('Host github.com', '  AddKeysToAgent yes', "  IdentityFile $SshKey")
}

# The ssh-agent service is often disabled by default on Windows and needs an elevated prompt the first time it's enabled; best-effort here.
$agent = Get-Service ssh-agent -ErrorAction SilentlyContinue
if ($agent -and $agent.Status -ne 'Running') { Start-Service ssh-agent -ErrorAction SilentlyContinue }
ssh-add $SshKey 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Couldn't add the key to ssh-agent automatically - the service may need enabling once from an elevated prompt:"
    Write-Host '  Set-Service ssh-agent -StartupType Automatic; Start-Service ssh-agent'
    Write-Host 'The key was still generated successfully.'
}

Write-Host '==> Public key (copied to clipboard):'
Get-Content -LiteralPath "$SshKey.pub" | Set-Clipboard
Get-Content -LiteralPath "$SshKey.pub"
Write-Host 'Add it at: https://github.com/settings/keys'
