# Installs the winget packages this setup needs. winget itself ships with Windows 11 (via the "App Installer"), so - like
# brew.sh assumes Homebrew's installer is the only external fetch - this is the only external fetch here.
# install.ps1 runs this through iex before the repo is cloned, so it must stay self-contained.

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw 'winget was not found. Install "App Installer" from the Microsoft Store (https://apps.microsoft.com/detail/9nblggh4nns1), then re-run this script.'
}

$packages = @(
    'Git.Git'
    'Python.Python.3.13'
    'OpenJS.NodeJS.LTS'
    'astral-sh.uv'
    'jqlang.jq'
    'BurntSushi.ripgrep.MSVC'
    'junegunn.fzf'
    'sharkdp.bat'
    'eza-community.eza'
    'GNU.Wget2'
    'GitHub.cli'
    'VSCodium.VSCodium'
)
foreach ($id in $packages) {
    winget install -e --accept-package-agreements --accept-source-agreements --silent --id $id
}

# `tree` ships with Windows already and Task Manager covers what htop does on macOS - neither has (or needs) a winget package,
# so both are skipped.

# --- Meslo Nerd Font: not reliably published on winget, so fetch the release archive directly (same idea as brew.sh's font cask)
# and register it per-user. Installs just the "MesloLGS NF Mono" family (the 4 regular/bold/italic weights) since that's what
# app_config/vscodium/settings.json asks for. ---
$fontZip = Join-Path $env:TEMP 'Meslo.zip'
$fontExtract = Join-Path $env:TEMP 'MesloNerdFont'
$fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
$ProgressPreference = 'SilentlyContinue'   # Windows PowerShell 5.1 downloads much faster without the progress bar
try {
    Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Meslo.zip' -OutFile $fontZip -ErrorAction Stop
    Expand-Archive -LiteralPath $fontZip -DestinationPath $fontExtract -Force -ErrorAction Stop
    New-Item -ItemType Directory -Force -Path $fontDir | Out-Null
    foreach ($font in Get-ChildItem -Path $fontExtract -Filter 'MesloLGSNerdFontMono-*.ttf') {
        $installed = Join-Path $fontDir $font.Name
        Copy-Item -LiteralPath $font.FullName -Destination $installed -Force
        New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts' -Name "$($font.BaseName) (TrueType)" -Value $installed -PropertyType String -Force | Out-Null
    }
} catch {
    Write-Warning 'Could not download the Meslo Nerd Font automatically; install it manually from https://www.nerdfonts.com/font-downloads'
} finally {
    Remove-Item -LiteralPath $fontExtract -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $fontZip -Force -ErrorAction SilentlyContinue
}
