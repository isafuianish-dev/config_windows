# Basic global git setup. Edit the values below whenever you like.
$ErrorActionPreference = 'Continue'

if (-not (git config --global --get user.name)) { git config --global user.name 'Anish' }
if (-not (git config --global --get user.email)) { git config --global user.email '167506558+isafuianish-dev@users.noreply.github.com' }
git config --global init.defaultBranch main
git config --global pull.rebase false
git config --global push.autoSetupRemote true
git config --global color.ui auto
git config --global credential.helper manager
git config --global core.excludesfile ((Join-Path $PSScriptRoot 'gitignore_global') -replace '\\', '/')
