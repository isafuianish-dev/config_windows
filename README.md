# config_windows

Personal Windows setup: dotfiles, install scripts, and app config. One command
takes a clean Windows machine to a working PowerShell shell. It mirrors
[config_macos](https://github.com/isafuianish-dev/config_macos): the same aliases,
functions, git aliases, prompt, and setup steps (see [Differences from macOS](#differences-from-macos)
for the few things that can't match).

## Bootstrap a new Windows machine

Run this in PowerShell (Windows PowerShell 5.1, which ships with Windows, or PowerShell 7):

```powershell
irm https://raw.githubusercontent.com/isafuianish-dev/config_windows/main/install.ps1 | iex
```

From `cmd.exe`, wrap it: `powershell -NoProfile -Command "irm https://raw.githubusercontent.com/isafuianish-dev/config_windows/main/install.ps1 | iex"`.

This installs winget packages, clones this repo, sets up git identity and aliases,
puts VSCodium settings in place, wires every new PowerShell session to load the shell
config below, prompts for GitHub tokens, and generates an SSH key.

Packages installed via [winget](https://learn.microsoft.com/windows/package-manager/winget/)
(ships with Windows 11 already, so no separate package-manager install step is
needed): `git`, `python`, `node`, `uv`, `jq`, `ripgrep`, `fzf`, `bat`, `eza`,
`wget`, `gh`, `vscodium`, plus the Meslo Nerd Font (fetched directly - see
[`other/winget.ps1`](other/winget.ps1), it isn't published on winget). `tree`
ships with Windows already, so it isn't installed separately.

**Optional: Java.** The bootstrap asks whether to install Temurin OpenJDK 21
([`other/java.ps1`](other/java.ps1)) via winget (`EclipseAdoptium.Temurin.21.JDK`). Once it's installed,
[`env.ps1`](ps_profile/module/env.ps1) sets `JAVA_HOME` and puts its `bin` on `PATH` automatically.
Skipped it? Run `.\other\java.ps1` later and restart your terminal.

**Optional: Android.** The bootstrap asks whether to set up the Android SDK
([`other/android.ps1`](other/android.ps1)). There's no winget package for the command line tools alone,
so this fetches Google's repository manifest to resolve the current Windows cmdline-tools archive (the
same source the `android` CLI itself uses for "latest") and installs everything into
`%LOCALAPPDATA%\Android\Sdk` - the same default location Android Studio uses, so this works whether or
not Android Studio is also installed. Everything goes through the `android` CLI, which superseded the
now-deprecated `sdkmanager`/`avdmanager` in current cmdline-tools releases: `android sdk install`
installs `platform-tools` and a platform/build-tools at API 34 (what an actual build targets), and
`android emulator create medium_phone` creates a `medium_phone` AVD, auto-provisioning whatever system
image it needs itself - the emulator is just for manual testing, so it doesn't need to be pinned to a
specific API level the way the build toolchain does. [`env.ps1`](ps_profile/module/env.ps1) sets
`ANDROID_HOME`/`ANDROID_SDK_ROOT` and puts `cmdline-tools`, `platform-tools`, and `emulator` on `PATH`
automatically whenever `%LOCALAPPDATA%\Android\Sdk` exists. Skipped it? Run `.\other\android.ps1` later
and restart your terminal. Launch the emulator with `android emulator start medium_phone`.

**GitHub tokens.** The bootstrap runs [`other/github_pat.ps1`](other/github_pat.ps1), which opens GitHub's
fine-grained token form (name and permissions pre-filled) once for a read-only token and once for a
read/write token, and asks you to paste each one. They're saved in `%USERPROFILE%\Developer\secrets\github`
(`pat_read.token`, `pat_readwrite.token`), and [`env.ps1`](ps_profile/module/env.ps1) exports them as
`GITHUB_PAT_READ` and `GITHUB_PAT_READWRITE` in every PowerShell session. Tokens that are already saved are skipped;
to replace one, delete its file and run `.\other\github_pat.ps1` again. Only PowerShell sessions (and programs
started from them) see these variables; `cmd.exe` and apps launched from the Start menu don't.

**Secrets directory.** [`env.ps1`](ps_profile/module/env.ps1) also creates `%USERPROFILE%\Developer\secrets`
if it doesn't exist and exports it as `SECRET_DIR` — for example, Android signing keys are kept there, and
a build script can read `$env:SECRET_DIR` instead of hardcoding the path.

**After bootstrapping**, run `gh auth login` once to authenticate the GitHub CLI —
without it, the `gh`-based aliases/functions below (`ghpr`, `ghrv`, `gitbornr`, etc.)
will fail with an auth error.

**Coming from the old cmd.exe version?** This repo used to be `.bat` files with a `cmd.exe`
AutoRun hook. Re-running the bootstrap removes that hook and wires PowerShell instead. The repo now
lives in `%USERPROFILE%\Developer\projects\configuration\config_windows`, so an older clone in
`Developer\projects\config_windows` is no longer used and can be deleted.

## Layout

```
.
├── install.ps1                 # entry point for a fresh machine
├── ps_profile/
│   ├── profile.ps1             # dot-sourced by your PowerShell profile, loads every module below
│   └── module/
│       ├── env.ps1             # GITHUB_PAT_READ / GITHUB_PAT_READWRITE / SECRET_DIR / JAVA_HOME / ANDROID_HOME
│       ├── alias.ps1           # shortcuts, grouped by the command they wrap
│       ├── function.ps1        # shell functions
│       ├── android.ps1         # Android functions (create_device, create_release_apk, ...), only when the SDK is installed
│       └── prompt.ps1          # powerline-style prompt with live git status
├── git_setup/
│   ├── git_config.ps1          # global git identity + settings
│   ├── git_alias.ps1           # git born / git kill / git addremote / ... aliases
│   └── gitignore_global        # git's core.excludesfile, applies to all repos
├── app_config/
│   └── vscodium/settings.json  # copied (symlinked if Developer Mode/admin allows) into VSCodium's User dir by install.ps1
└── other/
    ├── winget.ps1              # winget + packages
    ├── java.ps1                # optional: Temurin OpenJDK 21 (bootstrap asks first)
    ├── android.ps1             # optional: Android SDK cmdline-tools + AVD emulator (bootstrap asks first)
    ├── github_pat.ps1          # prompts for GitHub tokens, saves them to ~/Developer/secrets/github
    └── ssh.ps1                 # SSH key generation (skips if one already exists)
```

## How the shell config loads

`install.ps1` adds one line to the all-hosts `profile.ps1` in both `Documents\WindowsPowerShell`
(Windows PowerShell 5.1) and `Documents\PowerShell` (PowerShell 7). It dot-sources
[`ps_profile\profile.ps1`](ps_profile/profile.ps1) if that file exists, which loads `env.ps1`, `alias.ps1`,
`function.ps1`, and `prompt.ps1` in turn. It also sets the execution policy to `RemoteSigned` for your user,
since Windows defaults to `Restricted`, which refuses to load any profile.

- **Aliases are functions.** A PowerShell alias can't carry arguments, so each shortcut in `alias.ps1`
  (`ghpr`, `bi`, `nr`, ...) is a small function that passes extra arguments straight through. `ni` is a
  built-in alias for `New-Item`; the profile removes it so `ni` means `npm install`, like on macOS.
- **Everything is `global:`.** That lets `reload` re-run the profile from inside a function and still
  redefine everything in your session.
- **`function.ps1` is self-contained.** The `git born` / `git kill` / ... aliases run it through
  `powershell -NoProfile -Command ". function.ps1; gitborn"`, so they work as plain git subcommands
  without loading the rest of the profile.
- **The prompt is a live two-line powerline** (Windows logo, full path, git branch, status), the same
  layout as macOS: the branch segment is green for a clean tree and red for a dirty one, and the last
  segment is a check or an x for the previous command. It needs the Meslo Nerd Font (installed by the
  bootstrap) and a terminal that understands ANSI colors: Windows Terminal does, and the bootstrap turns
  it on for the classic console too. VSCodium's terminal is set to PowerShell in `settings.json`.

`app_config/vscodium/settings.json` gets put in place with a symlink if Developer Mode or an
elevated prompt allows it, otherwise a plain copy. If you see the copy fallback, re-run the
bootstrap after editing the file to pick up changes.

## Aliases

Defined in [`alias.ps1`](ps_profile/module/alias.ps1), grouped by the command they wrap.

**Navigation**

| Alias | Expands to |
|---|---|
| `..` / `...` / `....` | `cd ..` / `cd ../..` / `cd ../../..` |
| `~` | `cd ~` |

**ls** (`Get-ChildItem`)

| Alias | Expands to |
|---|---|
| `ll` / `la` | `Get-ChildItem -Force` |
| `l` | `Get-ChildItem` in columns (`Format-Wide`) |
| `lt` | `Get-ChildItem -Force`, newest first |

**github cli** (needs `gh auth login`)

| Alias | Expands to | Alias | Expands to |
|---|---|---|---|
| `ghpr` | `gh pr create` | `ghrv` | `gh repo view --web` |
| `ghprl` | `gh pr list` | `ghrl` | `gh repo list` |
| `ghprv` | `gh pr view --web` | `ghrc` | `gh repo clone` |
| `ghprco` | `gh pr checkout` | `ghrn` | `gh repo create` |
| `ghi` | `gh issue create` | `ghrd` | `gh repo delete` |
| `ghil` | `gh issue list` | `ghb` | `gh browse` |

**winget** (brew equivalent)

| Alias | Expands to |
|---|---|
| `bi` | `winget install` |
| `bu` | `winget source update; winget upgrade --all` |
| `bl` | `winget list` |

**npm / node**

| Alias | Expands to |
|---|---|
| `ni` | `npm install` |
| `nr` | `npm run` |
| `ns` | `npm start` |
| `nt` | `npm test` |

**python**

| Alias | Expands to |
|---|---|
| `venv` | `python -m venv .venv` |
| `activate` | `. ./.venv/Scripts/Activate.ps1` |

**Windows system**

| Alias | What it does |
|---|---|
| `cpwd` | Copy the current directory path to the clipboard |
| `showfiles` / `hidefiles` | Show/hide hidden files in Explorer |
| `hidedesktop` / `showdesktop` | Hide/show desktop icons |
| `flushdns` | Flush the DNS cache |
| `lock` | Lock the workstation |
| `sleepnow` | Sleep the whole machine now |
| `emptytrash` | Empty the Recycle Bin |
| `restartfinder` / `restartdock` | Restart Explorer (taskbar + file explorer live in one process on Windows) |
| `spotlightoff` / `spotlighton` | Stop/start the Windows Search indexer (needs an elevated prompt) |
| `screenshotdir` | Print the default Windows screenshot save location |

**misc**

| Alias | Expands to |
|---|---|
| `reload` | Re-run `ps_profile\profile.ps1` in this shell |
| `h` | `Get-History` (built into PowerShell already) |
| `c` | `Clear-Host` |
| `path` | Print `PATH`, one entry per line |

## Functions

Defined in [`function.ps1`](ps_profile/module/function.ps1). Same set, usage, and messages as macOS.

| Function | Usage | What it does |
|---|---|---|
| `mkcd` | `mkcd <dir>` | Create the directory (and parents), then `cd` into it |
| `up` | `up [n]` | `cd` up `n` directories (default 1) |
| `extract` | `extract <file>` | Extract almost any archive type based on its extension (`.zip`/`.tar*` via Windows' built-in `tar`; `.gz` natively; `.7z`/`.rar`/`.bz2` via `7z`/`unrar` if installed) |
| `backup` | `backup <path>` | Copy a file/dir alongside itself with a timestamp suffix |
| `port` | `port <n>` | Show what's listening on TCP port `n` |
| `killport` | `killport <n>` | Kill whatever's listening on TCP port `n` |
| `serve` | `serve [port]` | Serve the current directory over HTTP (default 8000) |
| `pj` | `pj [file]` | Pretty-print JSON from a file or stdin |
| `myip` | `myip` | Print this machine's public IP address |
| `git-clean-branches` | `git-clean-branches` | Delete local branches already merged into the current one (never `main`/`master`) |
| `note` | `note ["text"]` | Append a timestamped line to `~\notes.md`, or print it with no args |
| `caffeinate` | `caffeinate` | Keep this machine and its display awake until you Ctrl+C |
| `gitborn` | `gitborn` | For a plain, non-git directory: `git init`s and makes a first commit. No remote. Errors out if already inside a git repo. |
| `gitbornr` | `gitbornr` | For a plain, non-git directory: asks private/public, `git init`s, commits, creates a GitHub repo named after the folder, and pushes. If public, also asks whether to enable GitHub Pages for it. Errors out if already inside a git repo. |
| `gitaddremote` | `gitaddremote` | For a repo with no remote yet: asks private/public, creates a GitHub repo named after the root folder, and pushes. If public, also asks whether to enable GitHub Pages for it. Errors out if `origin` already exists. |
| `gitremoveremote` | `gitremoveremote` | **Destructive.** Deletes the linked GitHub repo and removes the local `origin` remote. Errors out if there's no local repo or no remote. |
| `gitenablepage` | `gitenablepage` | Enables GitHub Pages for the current repo, serving from the current branch's root. Errors out if there's no local repo, no remote, the repo is private, or Pages is already enabled. |
| `gitdisablepage` | `gitdisablepage` | Disables GitHub Pages for the current repo. Errors out if there's no local repo, no remote, or Pages isn't enabled. |
| `gitkill` | `gitkill` | **Destructive.** Deletes the GitHub repo (if one's linked) and wipes local git history. Asks for `yes` first. |
| `gitcomparelocal` | `gitcomparelocal` | Clones `main` fresh from the GitHub repo named after the current folder into a temp folder and compares it with the local folder, printing an `[A]`/`[D]`/`[M]` report of added/deleted/changed files. Works even if the folder isn't a git repo. |
| `gitoverridelocal` | `gitoverridelocal` | **Destructive.** Deletes everything in the current folder (including `.git`) and replaces it with a fresh clone of the GitHub remote named after the folder. Errors out if no such remote exists. Asks for `yes` first. |

## Android functions

Defined in [`android.ps1`](ps_profile/module/android.ps1), only loaded when the Android SDK is installed
(see Optional: Android above). Ported from macOS's `android.sh` so both platforms have the same commands,
prompts, and messages. They wrap the `android` CLI, `adb`, and Gradle. `create_signing_key`,
`create_release_apk`, and `run_release_apk` expect a standard Gradle project with an `:app` module and a
release `signingConfig` that reads `KEYSTORE_PATH`/`KEYSTORE_PASSWORD`/`KEY_ALIAS`/`KEY_PASSWORD` from the
environment. One platform difference: signing credentials are read from a dot-sourced
`credentials.ps1` (`$env:KEYSTORE_PATH = '...'` lines), not macOS's bash-style `credentials.env`, since
PowerShell has no `source` for `.env` files. Run `android_help` for a colorized cheat sheet of everything
below, printed straight to the terminal.

| Function | Usage | What it does |
|---|---|---|
| `android_help` | `android_help` | Print every function below with a one-line description, colorized, plus a few things worth remembering |
| `list_device` | `list_device` | List every AVD with its current status (running/stopped) |
| `start_device` | `start_device` | Ask which stopped AVD to start, launch it in the background, and wait (up to 2 minutes) for adb to see it |
| `stop_device` | `stop_device` | Ask which running AVD to stop, then stop it (`android emulator stop`) |
| `create_device` | `create_device` | Create a new AVD, asking which device profile to use (`android emulator create`) |
| `create_car_device` | `create_car_device` | Create a new Android Automotive (car) AVD, asking which dashboard profile to use and whether to include Google Play, installing its system image via `avdmanager` |
| `delete_device` | `delete_device` | **Destructive.** Ask which AVD to delete, confirm with `yes`, then delete it |
| `clone_device` | `clone_device` | Ask which AVD to clone and its new name, then duplicate its files (there's no native `android emulator clone`). Errors out if the source AVD is currently running |
| `wipe_device` | `wipe_device` | Ask which AVD to wipe, then clear its user data for a fresh start without deleting the device. Errors out if it's currently running |
| `create_signing_key` | `create_signing_key` | Run from a project root: generates a release signing key and `$env:SECRET_DIR\<project dir name>\credentials.ps1`. Errors out if a key already exists there |
| `create_debug_apk` | `create_debug_apk` | Run from a project root: `.\gradlew.bat assembleDebug`, then prints the built APK's path |
| `create_release_apk` | `create_release_apk [versionName] [versionCode]` | Run from a project root: dot-sources `$env:SECRET_DIR\<project dir name>\credentials.ps1`, builds `:app:assembleRelease`, verifies with `apksigner` that it's not debug-signed, and copies it to `dist\<name>_v<version>.apk` (older versions there are left alone). Errors out if `create_signing_key` hasn't been run yet |
| `run_debug_apk` | `run_debug_apk` | Installs and launches the most recently built debug APK on a running device/emulator. Errors out if none are running; asks which one if several are |
| `run_release_apk` | `run_release_apk` | Same as `run_debug_apk`, but with the most recently built release APK from `dist\` |

## Git aliases

Set up by [`git_alias.ps1`](git_setup/git_alias.ps1) (part of bootstrap). The first batch run the functions above through PowerShell so they also work as plain git subcommands:

| Command | Runs |
|---|---|
| `git born` | `gitborn` |
| `git bornr` | `gitbornr` |
| `git addremote` | `gitaddremote` |
| `git removeremote` | `gitremoveremote` |
| `git enablepage` | `gitenablepage` |
| `git disablepage` | `gitdisablepage` |
| `git kill` | `gitkill` |
| `git comparelocal` | `gitcomparelocal` |
| `git overridelocal` | `gitoverridelocal` |

The rest are plain git command shortcuts:

| Command | Runs | What it does |
|---|---|---|
| `git unstage` | `git reset HEAD --` | Unstage a file without losing its changes |
| `git last` | `git log -1 HEAD` | Show the last commit |
| `git amend` | `git commit --amend --no-edit` | Amend the last commit without changing its message |
| `git undo` | `git reset --soft HEAD~1` | Undo the last commit, keeping its changes staged |
| `git graph` | `git log --oneline --graph --decorate --all` | Compact graph log of every branch |
| `git contributors` | `git shortlog -sn` | List contributors ranked by commit count |
| `git aliases` | `git config --get-regexp ^alias\.` | List every configured git alias |

Short-command equivalents:

| Command | Runs | Command | Runs |
|---|---|---|---|
| `git s` | `git status` | `git l` | `git log --oneline --graph --decorate` |
| `git a` | `git add` | `git la` | `git log --oneline --graph --decorate --all` |
| `git aa` | `git add -A` | `git d` | `git diff` |
| `git c` | `git commit` | `git ds` | `git diff --staged` |
| `git cm` | `git commit -m` | `git st` | `git stash` |
| `git co` | `git checkout` | `git rh` | **Destructive.** `git reset --hard` |
| `git b` | `git branch` | | |
| `git p` | `git push` | | |
| `git pl` | `git pull` | | |

## Differences from macOS

Everything above has a macOS twin with the same name. What's left is tied to the platform:

- **Package manager:** winget instead of Homebrew, so there's no `bc` (`brew cleanup`) alias, and no `bash`, `htop`, or `tree` package (`tree` ships with Windows; Task Manager covers `htop`).
- **`grep`/`fgrep`/`egrep` color aliases, `py`, `pip`, `-`:** Windows has no matching commands (`py` and `pip` already exist there, and `cd -` is built into PowerShell 7).
- **System aliases** (`showfiles`, `restartdock`, `lock`, ...) do the Windows thing: Explorer, the registry, and Windows Search instead of Finder, Dock, and Spotlight.
- **Android signing credentials:** a dot-sourced `credentials.ps1` (`$env:KEYSTORE_PATH = '...'` lines) instead of macOS's bash-style `credentials.env`, since PowerShell has no `source` for `.env` files.

## Re-running

Every script here is idempotent — safe to re-run after pulling changes.
