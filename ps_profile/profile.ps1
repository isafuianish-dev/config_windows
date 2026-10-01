# Loads every module next to this file. Dot-sourced from the PowerShell profile that install.ps1 sets up.
# Everything the modules define is global: (functions, prompt), so `reload` can re-run this from inside a function.
# Keep every file in this folder ASCII-only: Windows PowerShell 5.1 reads a BOM-less .ps1 as ANSI, not UTF-8.

. "$PSScriptRoot/module/env.ps1"
. "$PSScriptRoot/module/alias.ps1"
. "$PSScriptRoot/module/function.ps1"
# Android functions: only when the SDK is installed (see other/android.ps1). Loaded after function.ps1
# since they use its shared _fail helper.
if (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'Android\Sdk')) {
    . "$PSScriptRoot/module/android.ps1"
}
. "$PSScriptRoot/module/prompt.ps1"
