#Requires -Version 7.0
<#
.SYNOPSIS
    Exports all git-tracked project files to a single dump file, formats the
    code, then commits and pushes everything to origin.

.DESCRIPTION
    Full workflow (each step timestamped):
      1. Push-Location into the project directory
      2. Ensure git user.name / user.email are configured (local repo scope)
      3. dotnet format (optional, skippable)
      4. Export git-tracked files to docs/llm/dump.txt
      5. git status / add / commit / push origin --all / remote show origin
      6. Pop-Location back to the original directory (always, via finally)

.EXAMPLE
    .\export.ps1
    .\export.ps1 -ProjectPath "D:\DEV\personal\appointme" -SkipFormat
    .\export.ps1 -SkipGit          # export only, no commit/push
#>

[CmdletBinding()]
param(
    [string]$ProjectPath   = "D:\DEV\personal\appointme",
    [string]$OutputFile    = "docs/llm/dump.txt",
    [string]$CommitMessage = "add all files",
    [string]$GitUserName   = "kushal",
    [string]$GitUserEmail  = "collabskus@gmail.com",
    [string]$Remote        = "origin",
    [switch]$SkipFormat,
    [switch]$SkipGit
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Helpers ──────────────────────────────────────────────────────────────────
function Write-Timestamp {
    Write-Host (Get-Date -Format "yyyy-MM-dd-HH-mm-ss") -ForegroundColor DarkGray
}

function Write-Step {
    param([string]$Message)
    Write-Timestamp
    Write-Host ">> $Message" -ForegroundColor Magenta
}

function Invoke-Git {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$AllowFailure
    )
    & git @Arguments
    if ($LASTEXITCODE -ne 0 -and -not $AllowFailure) {
        throw "git $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }
}

# File extensions to include (without the leading dot)
$IncludeExtensions = @(
    "cs", "json", "xml", "csproj", "slnx", "sln", "config",
    "cshtml", "razor", "js", "css", "scss", "html",
    "yml", "yaml", "sql", "props", "targets", "sh",
    "ps1", "md", "ts", "json"
)

# Exact filenames (no extension match needed)
$IncludeSpecificFiles = @(
    "Dockerfile", ".dockerignore", ".editorconfig",
    ".gitignore", ".gitattributes"
)

# Directories to skip even if tracked (e.g. this script's own output)
$ExcludeDirectories = @("docs")

# ── Main ─────────────────────────────────────────────────────────────────────
Push-Location $ProjectPath
try {
    $ResolvedRoot = (Resolve-Path ".").Path

    # ── Step 0: Sanity check — are we in a git repo? ─────────────────────────
    Write-Step "Verifying git repository at $ResolvedRoot"
    git rev-parse --is-inside-work-tree *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "Not a git repository: $ResolvedRoot"
    }

    # ── Step 1: Ensure git identity is configured (local scope) ─────────────
    if (-not $SkipGit) {
        Write-Step "Ensuring git identity (local repo config)"
        $currentEmail = git config user.email
        $currentName  = git config user.name
        if (-not $currentEmail) { Invoke-Git @('config', 'user.email', $GitUserEmail) }
        if (-not $currentName)  { Invoke-Git @('config', 'user.name',  $GitUserName)  }
        Write-Host "  user.name  = $(git config user.name)"  -ForegroundColor DarkCyan
        Write-Host "  user.email = $(git config user.email)" -ForegroundColor DarkCyan
    }

    # ── Step 2: dotnet format ────────────────────────────────────────────────
    if (-not $SkipFormat) {
        Write-Step "Running dotnet format"
        dotnet format
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "dotnet format exited with code $LASTEXITCODE — continuing anyway"
        }
    }

    # ── Step 3: Export ───────────────────────────────────────────────────────
    Write-Step "Starting project export"
    Write-Host "Project Path: $ResolvedRoot" -ForegroundColor Yellow
    Write-Host "Output File:  $OutputFile"   -ForegroundColor Yellow

    $OutputPath = Join-Path $ResolvedRoot $OutputFile
    $outputDir  = Split-Path $OutputPath -Parent
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    Write-Host "Querying git for tracked files..." -ForegroundColor Cyan
    $gitFiles = git ls-files --cached --others --exclude-standard
    if ($LASTEXITCODE -ne 0) {
        throw "git ls-files failed."
    }

    # Filter to desired extensions / specific filenames, exclude dirs
    $AllFiles = $gitFiles | ForEach-Object {
        $rel  = $_
        $name = Split-Path $rel -Leaf
        $ext  = ($name -replace '^.*\.', '').ToLower()

        foreach ($d in $ExcludeDirectories) {
            if ($rel -like "$d/*" -or $rel -like "$d\*") { return }
        }

        if ($IncludeExtensions -contains $ext -or $IncludeSpecificFiles -contains $name) {
            $fullPath = Join-Path $ResolvedRoot $rel
            if (Test-Path $fullPath) {
                [PSCustomObject]@{ Relative = $rel; Full = $fullPath }
            }
        }
    } | Sort-Object Relative

    Write-Host "Found $($AllFiles.Count) files to export" -ForegroundColor Green

    # Build the dump with a StringBuilder, then write once (fast + atomic-ish)
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine(@"
===============================================================================
ASP.NET PROJECT EXPORT  (git-tracked files only)
Generated: $(Get-Date)
Project Path: $ResolvedRoot
===============================================================================

DIRECTORY STRUCTURE (tracked):
==============================
"@)
    foreach ($p in ($gitFiles | Sort-Object)) { [void]$sb.AppendLine($p) }
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("FILE CONTENTS:")
    [void]$sb.AppendLine("==============")
    [void]$sb.AppendLine()

    $i = 0
    $sep = "=" * 80
    foreach ($f in $AllFiles) {
        $i++
        Write-Host "Processing ($i/$($AllFiles.Count)): $($f.Relative)" -ForegroundColor White
        $info = Get-Item -LiteralPath $f.Full

        [void]$sb.AppendLine($sep)
        [void]$sb.AppendLine("FILE: $($f.Relative)")
        [void]$sb.AppendLine("SIZE: $([math]::Round($info.Length / 1KB, 2)) KB")
        [void]$sb.AppendLine("MODIFIED: $($info.LastWriteTime)")
        [void]$sb.AppendLine($sep)
        [void]$sb.AppendLine()

        try {
            $content = Get-Content -LiteralPath $f.Full -Raw -ErrorAction Stop
            if ($content) { [void]$sb.AppendLine($content) }
            else          { [void]$sb.AppendLine("[EMPTY FILE]") }
        }
        catch {
            [void]$sb.AppendLine("[ERROR READING FILE: $($_.Exception.Message)]")
        }
        [void]$sb.AppendLine()
        [void]$sb.AppendLine()
    }

    [void]$sb.AppendLine(@"
===============================================================================
EXPORT COMPLETED: $(Get-Date)
Total Files Exported: $i
Output File: $OutputPath
===============================================================================
"@)

    [System.IO.File]::WriteAllText($OutputPath, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))

    Write-Host "`nExport completed!" -ForegroundColor Green
    Write-Host "Total files exported: $i" -ForegroundColor Green
    Write-Host "Output file size: $([math]::Round((Get-Item $OutputPath).Length / 1KB, 2)) KB" -ForegroundColor Cyan

    # ── Step 4: Git status / add / commit / push ─────────────────────────────
    if (-not $SkipGit) {
        Write-Step "git status"
        Invoke-Git @('status')

        Write-Step "git add ."
        Invoke-Git @('add', '.')

        Write-Step "git commit"
        $pending = git status --porcelain
        if ($pending) {
            Invoke-Git @('commit', '--message', $CommitMessage)
        }
        else {
            Write-Host "Nothing to commit, working tree clean" -ForegroundColor Yellow
        }

        Write-Step "git push $Remote --all"
        Invoke-Git @('push', $Remote, '--all')

        Write-Step "git remote show $Remote"
        Invoke-Git @('remote', 'show', $Remote)
    }

    Write-Timestamp
    Write-Host "All done." -ForegroundColor Green
}
finally {
    # Always return to the original directory, even on error
    Pop-Location
}
