# prm — branch + PR + squash-merge a staged change in one command.
#
# Routes a normal commit through a branch+PR+merge cycle so each change
# earns Pull Shark credit, without changing your default git workflow.
# Designed for personal repos where direct push to main is otherwise fine.
#
# Install (opt-in, per session):
#   . C:\Dev\tenzinsachievement-farm\tools\prm.ps1
#
# Or add the same dot-source line to your PowerShell profile to make it
# permanent: $PROFILE  (Microsoft.PowerShell_profile.ps1)
#
# Use:
#   git add src/foo.ts
#   prm "fix: handle empty input in foo"
#
# Flags:
#   -All        run `git add -u` first (modified/deleted tracked files only)
#   -Coauthor   add Claude Co-Authored-By trailer (only when truthful)
#   -Branch x   use a specific branch name instead of auto/<timestamp>
#   -KeepBranch leave the remote branch after merge

function Invoke-PRMerge {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Message,
        [string]$Branch,
        [switch]$All,
        [switch]$Coauthor,
        [switch]$KeepBranch
    )

    git rev-parse --is-inside-work-tree 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "prm: not inside a git repository." -ForegroundColor Red
        return
    }

    $remoteUrl = git config --get remote.origin.url 2>$null
    if (-not $remoteUrl -or $remoteUrl -notmatch 'github\.com') {
        Write-Host "prm: no GitHub remote 'origin' found." -ForegroundColor Red
        return
    }

    $defaultRef = git symbolic-ref refs/remotes/origin/HEAD 2>$null
    if ($defaultRef) {
        $defaultBranch = $defaultRef -replace '^refs/remotes/origin/', ''
    }
    else {
        $headLine = git remote show origin 2>$null | Select-String 'HEAD branch'
        if ($headLine) { $defaultBranch = ($headLine -split ':')[1].Trim() } else { $defaultBranch = 'main' }
    }

    $current = git symbolic-ref --short HEAD 2>$null
    if ($current -ne $defaultBranch) {
        Write-Host "prm: must be on default branch ($defaultBranch). Currently on: $current." -ForegroundColor Yellow
        return
    }

    if ($All) { git add -u }

    $staged = git diff --cached --name-only
    if (-not $staged) {
        Write-Host "prm: nothing staged. Stage files with 'git add', or pass -All for tracked modifications." -ForegroundColor Yellow
        return
    }

    git pull --ff-only
    if ($LASTEXITCODE -ne 0) {
        Write-Host "prm: could not fast-forward $defaultBranch. Resolve manually first." -ForegroundColor Red
        return
    }

    if (-not $Branch) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $Branch = "auto/$stamp"
    }

    git checkout -b $Branch
    if ($LASTEXITCODE -ne 0) { return }

    $commitMsg = $Message
    if ($Coauthor) {
        $commitMsg = "$Message`n`nCo-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
    }

    git commit -m $commitMsg
    if ($LASTEXITCODE -ne 0) {
        Write-Host "prm: commit failed; rolling back branch." -ForegroundColor Red
        git checkout $defaultBranch
        git branch -D $Branch 2>$null | Out-Null
        return
    }

    git push -u origin $Branch
    if ($LASTEXITCODE -ne 0) { return }

    $prUrl = gh pr create --title $Message --body "Auto via prm." --base $defaultBranch --head $Branch
    if ($LASTEXITCODE -ne 0) { return }
    Write-Host "prm: PR created — $prUrl"

    if ($KeepBranch) {
        gh pr merge $Branch --squash
    }
    else {
        gh pr merge $Branch --squash --delete-branch
    }
    if ($LASTEXITCODE -ne 0) { return }

    git checkout $defaultBranch | Out-Null
    git pull --ff-only | Out-Null

    Write-Host "prm: squash-merged into $defaultBranch." -ForegroundColor Green
}

Set-Alias prm Invoke-PRMerge
