# Shell functions. Add more here whenever you want.
# Ported from config_macos's function.sh, so the two platforms have the same commands, prompts and messages.
# Self-contained on purpose: git_setup/git_alias.ps1 dot-sources just this file to back `git born`, `git kill`, etc.

# Print an error to stderr and set a failing exit code (a function has no real exit status). Use as `return (_fail '...')`.
function global:_fail([string]$Message) {
    [Console]::Error.WriteLine($Message)
    $global:LASTEXITCODE = 1
}

# Make a directory and cd into it.
function global:mkcd([string]$Path) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    Set-Location -LiteralPath $Path
}

# cd up N directories (default 1), e.g. `up 3`.
function global:up([int]$N = 1) {
    if ($N -lt 1) { return }
    Set-Location -LiteralPath ('../' * $N)
}

# Extract almost any archive type. .zip/.tar* use the tar that ships with Windows; .7z/.rar/.bz2 need 7z (or unrar) installed.
function global:extract([string]$File) {
    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) {
        return (_fail "extract: '$File' is not a valid file")
    }
    switch -Regex ($File.ToLower()) {
        '\.tar\.bz2$' { tar xjf $File; break }
        '\.tar\.gz$' { tar xzf $File; break }
        '\.tar\.xz$' { tar xJf $File; break }
        '\.tar$' { tar xf $File; break }
        '\.gz$' {
            $source = (Resolve-Path -LiteralPath $File).Path
            $input_stream = [System.IO.File]::OpenRead($source)
            try {
                $gzip = New-Object System.IO.Compression.GZipStream($input_stream, [System.IO.Compression.CompressionMode]::Decompress)
                $output_stream = [System.IO.File]::Create(($source -replace '\.gz$', ''))
                try { $gzip.CopyTo($output_stream) } finally { $output_stream.Dispose(); $gzip.Dispose() }
            } finally { $input_stream.Dispose() }
            break
        }
        '\.bz2$' { 7z x $File; break }
        '\.zip$' { tar xf $File; break }
        '\.rar$' {
            if (Get-Command unrar -ErrorAction SilentlyContinue) { unrar x $File } else { 7z x $File }
            break
        }
        '\.7z$' { 7z x $File; break }
        default { return (_fail "extract: don't know how to extract '$File'") }
    }
}

# Back up a file/dir alongside itself with a timestamp suffix.
function global:backup([string]$Path) {
    $Path = $Path.TrimEnd('\', '/')
    Copy-Item -LiteralPath $Path -Destination "$Path.bak.$(Get-Date -Format yyyyMMddHHmmss)" -Recurse
}

# Find what's listening on a port, e.g. `port 3000`.
function global:port([int]$Number) {
    if (-not $Number) { return (_fail 'port: usage: port <n>') }
    Get-NetTCPConnection -State Listen -LocalPort $Number -ErrorAction SilentlyContinue | ForEach-Object {
        [pscustomobject]@{
            LocalAddress = $_.LocalAddress
            LocalPort    = $_.LocalPort
            PID          = $_.OwningProcess
            Process      = (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName
        }
    }
}

# Kill whatever's listening on a port, e.g. `killport 3000`.
function global:killport([int]$Number) {
    if (-not $Number) { return (_fail 'killport: usage: killport <n>') }
    Get-NetTCPConnection -State Listen -LocalPort $Number -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty OwningProcess -Unique |
        ForEach-Object { Stop-Process -Id $_ -Force }
}

# Serve the current directory over HTTP, e.g. `serve 8000`.
function global:serve([int]$Port = 8000) {
    python -m http.server $Port
}

# Pretty-print JSON from a file or stdin, e.g. `pj file.json` or `Get-Content f.json | pj`.
function global:pj([string]$File) {
    if ($File) { python -m json.tool $File } else { $input | python -m json.tool }
}

# Look up the public IP address of this machine. curl.exe, because `curl` is an Invoke-WebRequest alias in Windows PowerShell.
function global:myip {
    $curl = 'curl'
    if (Get-Command curl.exe -ErrorAction SilentlyContinue) { $curl = 'curl.exe' }
    & $curl -s https://ifconfig.me
}

# Quick scratch note appended to ~/notes.md, e.g. `note "buy milk"`.
function global:note {
    $file = Join-Path $HOME 'notes.md'
    if ($args.Count -eq 0) {
        if (Test-Path -LiteralPath $file) { Get-Content -LiteralPath $file }
    } else {
        Add-Content -LiteralPath $file -Value ('{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), ($args -join ' '))
    }
}

# Keep this machine (and its display) awake until you press Ctrl+C.
function global:caffeinate {
    Add-Type -Namespace Win32 -Name Power -ErrorAction SilentlyContinue -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint flags);'
    # ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED, in decimal because PowerShell reads 0x8000000x as a negative int.
    [Win32.Power]::SetThreadExecutionState([uint32]2147483651) | Out-Null
    Write-Host 'caffeinate: keeping this machine awake. Press Ctrl+C to stop.'
    try {
        while ($true) { Start-Sleep -Seconds 60 }
    } finally {
        [Win32.Power]::SetThreadExecutionState([uint32]2147483648) | Out-Null
    }
}

# Delete local branches already merged into the current one (never main/master).
function global:git-clean-branches {
    git branch --merged | ForEach-Object {
        $branch = $_.Trim()
        if ($branch -and $branch -notmatch '^[*+] ' -and $branch -notin 'main', 'master') {
            git branch -d $branch
        }
    }
}

# Ask private/public and return the matching gh flag. Reports the error and returns nothing for any other answer.
function global:_ask_visibility([string]$RepoName, [string]$Caller) {
    $answer = Read-Host "Make '$RepoName' private or public?"
    switch ("$answer".ToLower()) {
        'private' { return '--private' }
        'public' { return '--public' }
        default { _fail "${Caller}: please answer 'private' or 'public', aborting." }
    }
}

# Offer to enable GitHub Pages for a freshly created public repo.
function global:_offer_pages([string]$OwnerRepo) {
    $answer = Read-Host "Enable GitHub Pages for '$OwnerRepo'? (yes/no)"
    if ("$answer".ToLower() -eq 'yes') { gitenablepage }
}

# Create a local git repo with a first commit. Fails if a git repo already exists here.
function global:gitborn {
    git rev-parse --is-inside-work-tree *> $null
    if ($LASTEXITCODE -eq 0) { return (_fail 'gitborn: already inside a git repository, aborting.') }

    git init
    if ($LASTEXITCODE -ne 0) { return (_fail 'gitborn: git init failed, aborting.') }

    git add -A
    if ($LASTEXITCODE -ne 0) { return (_fail 'gitborn: git add failed, aborting.') }

    git commit -m 'Hello World'
    if ($LASTEXITCODE -ne 0) { return (_fail 'gitborn: git commit failed, aborting.') }

    $global:LASTEXITCODE = 0
}

# Create a local git repo with a first commit, then a GitHub remote named after the root folder, then push. Fails if a git repo already exists here.
function global:gitbornr {
    git rev-parse --is-inside-work-tree *> $null
    if ($LASTEXITCODE -eq 0) { return (_fail 'gitbornr: already inside a git repository, aborting.') }

    $repoName = Split-Path -Leaf (Get-Location).Path
    $visibility = _ask_visibility $repoName 'gitbornr'
    if (-not $visibility) { return }

    git init
    if ($LASTEXITCODE -ne 0) { return (_fail 'gitbornr: git init failed, aborting.') }

    git add -A
    if ($LASTEXITCODE -ne 0) { return (_fail 'gitbornr: git add failed, aborting.') }

    git commit -m 'Hello World'
    if ($LASTEXITCODE -ne 0) { return (_fail 'gitbornr: git commit failed, aborting.') }

    gh repo create $repoName $visibility
    if ($LASTEXITCODE -ne 0) { return (_fail "gitbornr: failed to create GitHub repo '$repoName', aborting.") }

    $ownerRepo = gh repo view $repoName --json nameWithOwner -q .nameWithOwner 2>$null
    if (-not $ownerRepo) { return (_fail "gitbornr: repo was created but couldn't be looked up, aborting.") }

    git remote add origin "git@github.com:$ownerRepo.git"
    if ($LASTEXITCODE -ne 0) { return (_fail "gitbornr: failed to add remote 'origin', aborting.") }

    $branch = git branch --show-current
    git push -u origin $branch
    if ($LASTEXITCODE -ne 0) { return (_fail 'gitbornr: git push failed, aborting.') }

    if ($visibility -eq '--public') { _offer_pages $ownerRepo }
    $global:LASTEXITCODE = 0
}

# Wire up a GitHub remote for a local repo that doesn't have one yet, named after the root folder.
function global:gitaddremote {
    git rev-parse --is-inside-work-tree *> $null
    if ($LASTEXITCODE -ne 0) { return (_fail 'gitaddremote: not inside a git repository') }
    Set-Location (git rev-parse --show-toplevel)

    git remote get-url origin *> $null
    if ($LASTEXITCODE -eq 0) {
        return (_fail "gitaddremote: remote 'origin' already exists ($(git remote get-url origin)), aborting.")
    }

    $repoName = Split-Path -Leaf (Get-Location).Path
    $visibility = _ask_visibility $repoName 'gitaddremote'
    if (-not $visibility) { return }

    gh repo create $repoName $visibility
    if ($LASTEXITCODE -ne 0) { return (_fail "gitaddremote: failed to create GitHub repo '$repoName', aborting.") }

    $ownerRepo = gh repo view $repoName --json nameWithOwner -q .nameWithOwner 2>$null
    if (-not $ownerRepo) { return (_fail "gitaddremote: repo was created but couldn't be looked up, aborting.") }

    git remote add origin "git@github.com:$ownerRepo.git"
    if ($LASTEXITCODE -ne 0) { return (_fail "gitaddremote: failed to add remote 'origin', aborting.") }

    $branch = git branch --show-current
    if (-not $branch) { return (_fail 'gitaddremote: no commits yet on this branch, commit something before pushing.') }

    git push -u origin $branch
    if ($LASTEXITCODE -ne 0) { return (_fail 'gitaddremote: git push failed, aborting.') }

    if ($visibility -eq '--public') { _offer_pages $ownerRepo }
    $global:LASTEXITCODE = 0
}

# Remove the GitHub remote for a local repo. Fails if there's no local repo or no remote.
function global:gitremoveremote {
    git rev-parse --is-inside-work-tree *> $null
    if ($LASTEXITCODE -ne 0) { return (_fail 'gitremoveremote: not inside a git repository') }
    Set-Location (git rev-parse --show-toplevel)

    git remote get-url origin *> $null
    if ($LASTEXITCODE -ne 0) { return (_fail "gitremoveremote: no remote 'origin' configured, aborting.") }

    $repo = gh repo view --json nameWithOwner -q .nameWithOwner 2>$null
    if (-not $repo) { return (_fail "gitremoveremote: couldn't look up the GitHub repo for 'origin', aborting.") }

    gh repo delete $repo --yes
    if ($LASTEXITCODE -ne 0) { return (_fail "gitremoveremote: failed to delete GitHub repo '$repo', aborting.") }

    git remote remove origin
    if ($LASTEXITCODE -ne 0) { return (_fail "gitremoveremote: deleted '$repo' but failed to remove local remote 'origin'.") }

    $global:LASTEXITCODE = 0
}

# Enable GitHub Pages for the current repo, serving from the current branch's root. Requires a public repo.
function global:gitenablepage {
    git rev-parse --is-inside-work-tree *> $null
    if ($LASTEXITCODE -ne 0) { return (_fail 'gitenablepage: not inside a git repository') }
    Set-Location (git rev-parse --show-toplevel)

    git remote get-url origin *> $null
    if ($LASTEXITCODE -ne 0) { return (_fail "gitenablepage: no remote 'origin' configured, aborting.") }

    $repo = gh repo view --json nameWithOwner -q .nameWithOwner 2>$null
    if (-not $repo) { return (_fail "gitenablepage: couldn't look up the GitHub repo for 'origin', aborting.") }

    if ((gh repo view $repo --json isPrivate -q .isPrivate 2>$null) -eq 'true') {
        return (_fail "gitenablepage: '$repo' is private, GitHub Pages needs a public repo (or a paid plan), aborting.")
    }

    gh api "repos/$repo/pages" *> $null
    if ($LASTEXITCODE -eq 0) { return (_fail "gitenablepage: GitHub Pages is already enabled for '$repo', aborting.") }

    $branch = git branch --show-current
    gh api -X POST "repos/$repo/pages" -f "source[branch]=$branch" -f 'source[path]=/' | Out-Null
    if ($LASTEXITCODE -ne 0) { return (_fail "gitenablepage: failed to enable GitHub Pages for '$repo', aborting.") }

    $global:LASTEXITCODE = 0
}

# Disable GitHub Pages for the current repo.
function global:gitdisablepage {
    git rev-parse --is-inside-work-tree *> $null
    if ($LASTEXITCODE -ne 0) { return (_fail 'gitdisablepage: not inside a git repository') }
    Set-Location (git rev-parse --show-toplevel)

    git remote get-url origin *> $null
    if ($LASTEXITCODE -ne 0) { return (_fail "gitdisablepage: no remote 'origin' configured, aborting.") }

    $repo = gh repo view --json nameWithOwner -q .nameWithOwner 2>$null
    if (-not $repo) { return (_fail "gitdisablepage: couldn't look up the GitHub repo for 'origin', aborting.") }

    gh api "repos/$repo/pages" *> $null
    if ($LASTEXITCODE -ne 0) { return (_fail "gitdisablepage: GitHub Pages isn't enabled for '$repo', aborting.") }

    gh api -X DELETE "repos/$repo/pages" | Out-Null
    if ($LASTEXITCODE -ne 0) { return (_fail "gitdisablepage: failed to disable GitHub Pages for '$repo', aborting.") }

    $global:LASTEXITCODE = 0
}

# Delete the current GitHub repo (if linked) and wipe local git history. DESTRUCTIVE.
function global:gitkill {
    git rev-parse --is-inside-work-tree *> $null
    if ($LASTEXITCODE -ne 0) { return (_fail 'gitkill: not inside a git repository') }
    Set-Location (git rev-parse --show-toplevel)

    $repo = ''
    $hasRemote = $false
    git remote get-url origin *> $null
    if ($LASTEXITCODE -eq 0) {
        $repo = gh repo view --json nameWithOwner -q .nameWithOwner 2>$null
        if ($repo) { $hasRemote = $true }
    }

    if ($hasRemote) {
        Write-Host "This will PERMANENTLY delete the GitHub repo '$repo' and wipe this directory's local git history."
    } else {
        Write-Host 'No remote is configured on this repo. This will wipe its local git history only.'
    }
    $confirm = Read-Host "Type 'yes' to continue, anything else to abort"
    if ($confirm -cne 'yes') {
        Write-Host 'gitkill: aborted.'
        $global:LASTEXITCODE = 1
        return
    }

    if ($hasRemote) {
        gh repo delete $repo --yes
        if ($LASTEXITCODE -ne 0) { return (_fail "gitkill: failed to delete GitHub repo '$repo', aborting.") }
    }

    try { Remove-Item -LiteralPath .git -Recurse -Force -ErrorAction Stop }
    catch { return (_fail 'gitkill: failed to remove .git, aborting.') }

    $global:LASTEXITCODE = 0
}

# Map of relative path -> full path for every file under a folder, skipping .git and anything a .gitignore pattern matches by name.
function global:_file_map([string]$Root, [string[]]$Ignore) {
    $map = @{}
    $prefix = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\', '/')
    Get-ChildItem -LiteralPath $Root -Recurse -File -Force | ForEach-Object {
        $relative = $_.FullName.Substring($prefix.Length + 1)
        $parts = $relative -split '[\\/]'
        if ($parts -contains '.git') { return }
        foreach ($part in $parts) {
            foreach ($pattern in $Ignore) {
                if ($part -like $pattern) { return }
            }
        }
        $map[$relative] = $_.FullName
    }
    return $map
}

# Look up a GitHub repo named after the current folder, clone it fresh into a temp folder, and compare it against the local folder,
# reporting added/deleted/changed files. Works even if the local folder isn't a git repo, e.g. `gitcomparelocal`.
function global:gitcomparelocal {
    $repoName = Split-Path -Leaf (Get-Location).Path
    $ownerRepo = gh repo view $repoName --json nameWithOwner -q .nameWithOwner 2>$null
    if (-not $ownerRepo) { return (_fail "gitcomparelocal: no GitHub repo named '$repoName' found, aborting.") }

    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
    $clone = Join-Path $tmp $repoName
    git clone --quiet --branch main --single-branch "git@github.com:$ownerRepo.git" $clone *> $null
    if ($LASTEXITCODE -ne 0) {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        return (_fail "gitcomparelocal: failed to clone 'main' from '$ownerRepo', aborting.")
    }

    # Like `diff -X .gitignore`: each pattern is matched against file and folder names.
    $ignore = @()
    if (Test-Path -LiteralPath .gitignore) {
        $ignore = @(Get-Content -LiteralPath .gitignore |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and -not $_.StartsWith('#') -and -not $_.StartsWith('!') } |
            ForEach-Object { $_.Trim('/') })
    }

    $there = _file_map $clone $ignore
    $here = _file_map (Get-Location).Path $ignore

    $added = 0; $deleted = 0; $changed = 0
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($relative in (@($there.Keys) + @($here.Keys) | Sort-Object -Unique)) {
        if ($there.ContainsKey($relative) -and -not $here.ContainsKey($relative)) {
            $lines.Add("[D] $relative"); $deleted++
        } elseif ($here.ContainsKey($relative) -and -not $there.ContainsKey($relative)) {
            $lines.Add("[A] $relative"); $added++
        } else {
            $remoteFile = Get-Item -LiteralPath $there[$relative]
            $localFile = Get-Item -LiteralPath $here[$relative]
            if ($remoteFile.Length -ne $localFile.Length -or
                (Get-FileHash -LiteralPath $remoteFile.FullName).Hash -ne (Get-FileHash -LiteralPath $localFile.FullName).Hash) {
                $lines.Add("[M] $relative"); $changed++
            }
        }
    }
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue

    if (($added + $deleted + $changed) -eq 0) {
        "gitcomparelocal: local folder matches '$ownerRepo' (main), no differences."
        $global:LASTEXITCODE = 0
        return
    }

    "Comparing local folder against '$ownerRepo' (main):"
    ''
    $lines
    ''
    "Summary: $added added, $deleted deleted, $changed changed"
    $global:LASTEXITCODE = 0
}

# Wipe everything in the current folder (including .git) and replace it with a fresh clone of the GitHub remote named after the folder. DESTRUCTIVE.
function global:gitoverridelocal {
    $repoName = Split-Path -Leaf (Get-Location).Path
    $ownerRepo = gh repo view $repoName --json nameWithOwner -q .nameWithOwner 2>$null
    if (-not $ownerRepo) { return (_fail "gitoverridelocal: no GitHub repo named '$repoName' found, aborting.") }

    Write-Host "This will PERMANENTLY delete everything in '$((Get-Location).Path)' (including .git) and replace it with a fresh clone of '$ownerRepo'."
    $confirm = Read-Host "Type 'yes' to continue, anything else to abort"
    if ($confirm -cne 'yes') {
        Write-Host 'gitoverridelocal: aborted.'
        $global:LASTEXITCODE = 1
        return
    }

    try { Get-ChildItem -Force | Remove-Item -Recurse -Force -ErrorAction Stop }
    catch { return (_fail "gitoverridelocal: failed to clear '$((Get-Location).Path)', aborting.") }

    git clone "git@github.com:$ownerRepo.git" .
    if ($LASTEXITCODE -ne 0) { return (_fail 'gitoverridelocal: git clone failed.') }

    $global:LASTEXITCODE = 0
}
