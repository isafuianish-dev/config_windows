# Shortcuts, grouped by the command they wrap. Add more here whenever you want.
# A PowerShell alias can't carry arguments, so each shortcut is a small function; extra arguments pass straight through.

# --- Navigation ---
function global:.. { Set-Location .. }
function global:... { Set-Location ../.. }
function global:.... { Set-Location ../../.. }
function global:~ { Set-Location ~ }

# --- ls ---
function global:ll { Get-ChildItem -Force @args }
function global:la { Get-ChildItem -Force @args }
function global:l { Get-ChildItem @args | Format-Wide -AutoSize }
function global:lt { Get-ChildItem -Force @args | Sort-Object LastWriteTime -Descending }

# --- github cli ---
function global:ghpr { gh pr create @args }
function global:ghprl { gh pr list @args }
function global:ghprv { gh pr view --web @args }
function global:ghprco { gh pr checkout @args }
function global:ghi { gh issue create @args }
function global:ghil { gh issue list @args }
function global:ghrv { gh repo view --web @args }
function global:ghrl { gh repo list @args }
function global:ghrc { gh repo clone @args }
function global:ghrn { gh repo create @args }
function global:ghrd { gh repo delete @args }
function global:ghb { gh browse @args }

# --- winget (brew equivalent) ---
function global:bi { winget install @args }
function global:bu { winget source update; winget upgrade --all }
function global:bl { winget list @args }

# --- npm / node ---
# `ni` is a built-in alias for New-Item, and aliases win over functions, so drop it first.
Remove-Item Alias:ni -Force -ErrorAction SilentlyContinue
function global:ni { npm install @args }
function global:nr { npm run @args }
function global:ns { npm start @args }
function global:nt { npm test @args }

# --- python ---
function global:venv { python -m venv .venv @args }
function global:activate { . ./.venv/Scripts/Activate.ps1 }

# --- Windows system ---
function global:cpwd { (Get-Location).Path | Set-Clipboard }
function global:flushdns { ipconfig /flushdns }
function global:lock { rundll32.exe 'user32.dll,LockWorkStation' }
function global:sleepnow { rundll32.exe 'powrprof.dll,SetSuspendState' '0,1,0' }
function global:emptytrash { Clear-RecycleBin -Force }
function global:screenshotdir { "$HOME\Pictures\Screenshots" }

# Explorer shows the desktop and Windows shell together, so "Finder" and "Dock" are both it.
function global:restartfinder {
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
    if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
}
function global:restartdock { restartfinder }

function global:_explorer_option([string]$Name, [int]$Value) {
    Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name $Name -Value $Value
    restartfinder
}
function global:showfiles { _explorer_option Hidden 1 }
function global:hidefiles { _explorer_option Hidden 2 }
function global:hidedesktop { _explorer_option HideIcons 1 }
function global:showdesktop { _explorer_option HideIcons 0 }

# Needs an elevated prompt.
function global:spotlightoff { Stop-Service WSearch }
function global:spotlighton { Start-Service WSearch }

# --- misc ---
# `h` is already a built-in alias for Get-History.
function global:reload { . "$PSScriptRoot/../profile.ps1" }
function global:c { Clear-Host }
function global:path { $env:PATH -split [System.IO.Path]::PathSeparator | Where-Object { $_ } }
