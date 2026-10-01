# Powerline-style segmented prompt (oh-my-posh look): os | folder | git | status. Same layout as config_macos's prompt.sh.
# Needs a Nerd Font (other/winget.ps1 installs Meslo) and a terminal that understands ANSI colors (install.ps1 enables that
# for the classic console). The glyphs are built from code points so this file stays ASCII-only.

function global:prompt {
    $ok = $?
    $exit = $global:LASTEXITCODE   # the git calls below would otherwise overwrite the user's last exit code
    $esc = [char]27
    $sep = [string][char]0xE0B0

    $segs = New-Object System.Collections.Generic.List[string]
    $bgs = New-Object System.Collections.Generic.List[int]

    $segs.Add([string][char]0xF17A); $bgs.Add(33)                  # windows logo
    $segs.Add((Get-Location).Path); $bgs.Add(39)                   # current folder

    $branch = git symbolic-ref --short HEAD 2>$null
    if ($branch) {
        $gbg = 28
        if (git status --porcelain 2>$null) { $gbg = 160 }         # dirty tree
        $remote = git config --get "branch.$branch.remote" 2>$null
        if (-not $remote) { $remote = git remote 2>$null | Select-Object -First 1 }
        $seg = "$([char]0xEC6F) $branch"
        if ($remote) { $seg += " $([char]0xEB00) $remote" }
        $segs.Add($seg); $bgs.Add($gbg)
    }

    if ($ok) { $segs.Add([string][char]0xF00C); $bgs.Add(29) }
    else { $segs.Add([string][char]0xF00D); $bgs.Add(160) }

    $prompt = ''
    for ($i = 0; $i -lt $segs.Count; $i++) {
        $prompt += "$esc[48;5;$($bgs[$i])m$esc[97m $($segs[$i]) $esc[0m"
        if ($i -lt $segs.Count - 1) {
            $prompt += "$esc[38;5;$($bgs[$i])m$esc[48;5;$($bgs[$i + 1])m$sep$esc[0m"
        }
    }

    $global:LASTEXITCODE = $exit
    "$prompt`n$esc[1;33m > $esc[0m"
}
