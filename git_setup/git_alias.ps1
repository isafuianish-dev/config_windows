# Git aliases (born, bornr, addremote, removeremote, enablepage, disablepage, kill, overridelocal, comparelocal) that run the
# functions in ps_profile/module/function.ps1 through Windows PowerShell, so they work as `git <alias>` even outside an
# interactive shell session.
$ErrorActionPreference = 'Continue'

# The alias runs under Git for Windows' sh, so keep the command free of double quotes and backslashes: forward slashes, and a
# literal $HOME that PowerShell (not sh) expands later, which also keeps a profile path with spaces in one piece.
$FunctionFile = (Resolve-Path (Join-Path $PSScriptRoot '../ps_profile/module/function.ps1')).Path -replace '\\', '/'
$HomeDir = $HOME -replace '\\', '/'
if ($FunctionFile.StartsWith($HomeDir, [StringComparison]::OrdinalIgnoreCase)) {
    $FunctionFile = '$HOME' + $FunctionFile.Substring($HomeDir.Length)
}

function Set-FunctionAlias([string]$Name, [string]$Function) {
    git config --global "alias.$Name" "!powershell -NoProfile -ExecutionPolicy Bypass -Command '. $FunctionFile; $Function; exit `$LASTEXITCODE'"
}

Set-FunctionAlias born gitborn
Set-FunctionAlias bornr gitbornr
Set-FunctionAlias addremote gitaddremote
Set-FunctionAlias removeremote gitremoveremote
Set-FunctionAlias enablepage gitenablepage
Set-FunctionAlias disablepage gitdisablepage
Set-FunctionAlias kill gitkill
Set-FunctionAlias overridelocal gitoverridelocal
Set-FunctionAlias comparelocal gitcomparelocal

# Plain git command shortcuts.
$shortcuts = [ordered]@{
    unstage      = 'reset HEAD --'                                    # unstage a file without losing its changes
    last         = 'log -1 HEAD'                                      # show the last commit
    amend        = 'commit --amend --no-edit'                         # amend the last commit without changing its message
    undo         = 'reset --soft HEAD~1'                              # undo the last commit, keeping its changes staged
    graph        = 'log --oneline --graph --decorate --all'           # compact graph log of every branch
    contributors = 'shortlog -sn'                                     # list contributors ranked by commit count
    aliases      = 'config --get-regexp ^alias\.'                     # list every configured git alias
    s            = 'status'                                           # show working tree status
    a            = 'add'                                              # stage a file
    aa           = 'add -A'                                           # stage all changes
    c            = 'commit'                                           # record a commit
    cm           = 'commit -m'                                        # record a commit with an inline message
    co           = 'checkout'                                         # switch branches or restore files
    b            = 'branch'                                           # list, create, or delete branches
    p            = 'push'                                             # push commits to a remote
    pl           = 'pull'                                             # fetch and merge from a remote
    l            = 'log --oneline --graph --decorate'                 # compact graph log of the current branch
    la           = 'log --oneline --graph --decorate --all'           # compact graph log of every branch
    d            = 'diff'                                             # show unstaged changes
    ds           = 'diff --staged'                                    # show staged changes
    st           = 'stash'                                            # stash uncommitted changes
    rh           = 'reset --hard'                                     # reset the working tree and index, discarding changes. DESTRUCTIVE
}
foreach ($name in $shortcuts.Keys) {
    git config --global "alias.$name" $shortcuts[$name]
}
