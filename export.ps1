#Requires -Version 7.0
<#
.SYNOPSIS
    Exports project files to a single dump file, formats the code, then commits
    and pushes everything to origin.

.DESCRIPTION
    Full workflow (each step timestamped):
      1. Push-Location into the project directory
      2. Ensure git user.name / user.email are configured (local repo scope)
      3. dotnet format (optional, skippable)
      4. Export files to docs/llm/dump.txt
           - includes EVERY tracked (and untracked-but-not-ignored) file
           - excludes only the docs/llm directory (where this dump is written)
           - binary files are still listed, but their bytes are omitted
           - output opens with a visual directory TREE
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

# ── Configuration ──────────────────────────────────────────────────────────────

# Directory prefixes excluded from BOTH the tree and the file contents.
# docs/llm is excluded because the dump itself is written there — including it
# would embed a previous copy of the dump inside itself.
$ExcludeDirectories = @("docs/llm")

# Optional extra path globs to skip (matched against the forward-slash path).
# Empty by default, so EVERYTHING in git is exported. Enable to cut noise, e.g.:
#   "src/AppointMe.Frontend/yarn.lock"
#   "src/AppointMe.Frontend/src/api/*"      # generated Orval API client
$ExcludePathGlobs = @()

# Extensions whose bytes are not text. These files are still listed in the tree
# and still get a content entry, but their raw bytes are omitted. A NUL-byte
# scan (below) catches anything not listed here. NOTE: svg is text, so it is
# intentionally absent and will be dumped in full.
$BinaryExtensions = @(
    "png", "jpg", "jpeg", "gif", "bmp", "ico", "webp", "tiff",
    "pdf", "zip", "gz", "tar", "7z", "rar",
    "dll", "exe", "pdb", "so", "dylib",
    "woff", "woff2", "ttf", "otf", "eot",
    "mp3", "mp4", "mov", "avi", "wav", "ogg",
    "snk", "p12", "pfx"
)

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

function Test-PathExcluded {
    param([Parameter(Mandatory)][string]$RelativePath)
    $norm = $RelativePath -replace '\\', '/'
    foreach ($d in $ExcludeDirectories) {
        $dd = $d.TrimEnd('/')
        if ($norm -eq $dd -or $norm -like "$dd/*") { return $true }
    }
    foreach ($g in $ExcludePathGlobs) {
        if ($norm -like $g) { return $true }
    }
    return $false
}

function Test-FileIsBinary {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Extension = ''
    )
    if ($BinaryExtensions -contains $Extension) { return $true }
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        try {
            $buffer = [byte[]]::new(8192)
            $read   = $stream.Read($buffer, 0, $buffer.Length)
            for ($b = 0; $b -lt $read; $b++) {
                if ($buffer[$b] -eq 0) { return $true }   # NUL byte => binary
            }
        }
        finally { $stream.Dispose() }
    }
    catch {
        return $false
    }
    return $false
}

# Build a nested ordered-dictionary tree from a flat list of "/"-separated paths.
function ConvertTo-FileTree {
    param([string[]]$Paths = @())
    $root = [ordered]@{}
    foreach ($path in $Paths) {
        $parts = @(($path -replace '\\', '/') -split '/' | Where-Object { $_ -ne '' })
        $node  = $root
        for ($k = 0; $k -lt $parts.Count; $k++) {
            $part   = $parts[$k]
            $isLeaf = ($k -eq $parts.Count - 1)
            if ($isLeaf) {
                if (-not $node.Contains($part)) { $node[$part] = $null }   # file
            }
            else {
                if (-not $node.Contains($part) -or
                    $node[$part] -isnot [System.Collections.Specialized.OrderedDictionary]) {
                    $node[$part] = [ordered]@{}
                }
                $node = $node[$part]
            }
        }
    }
    return $root
}

# Render the tree into the StringBuilder using box-drawing connectors.
# Directories are listed first, then files, each group sorted alphabetically.
function Write-FileTree {
    param(
        [Parameter(Mandatory)][System.Collections.Specialized.OrderedDictionary]$Node,
        [Parameter(Mandatory)][System.Text.StringBuilder]$Builder,
        [string]$Prefix = ''
    )
    $dirNames  = @($Node.Keys | Where-Object { $Node[$_] -is    [System.Collections.Specialized.OrderedDictionary] } | Sort-Object)
    $fileNames = @($Node.Keys | Where-Object { $Node[$_] -isnot [System.Collections.Specialized.OrderedDictionary] } | Sort-Object)
    $names     = @($dirNames) + @($fileNames)

    for ($idx = 0; $idx -lt $names.Count; $idx++) {
        $name   = $names[$idx]
        $isLast = ($idx -eq $names.Count - 1)
        $isDir  = $Node[$name] -is [System.Collections.Specialized.OrderedDictionary]
        $branch = if ($isLast) { '└── ' } else { '├── ' }
        $label  = if ($isDir)  { "$name/" } else { $name }
        [void]$Builder.AppendLine("$Prefix$branch$label")
        if ($isDir) {
            $childPrefix = $Prefix + $(if ($isLast) { '    ' } else { '│   ' })
            Write-FileTree -Node $Node[$name] -Builder $Builder -Prefix $childPrefix
        }
    }
}

# ── Main ─────────────────────────────────────────────────────────────────────
Push-Location $ProjectPath
try {
    $ResolvedRoot = (Resolve-Path ".").Path
    $RepoName     = Split-Path $ResolvedRoot -Leaf

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

    Write-Host "Querying git for files..." -ForegroundColor Cyan
    # --cached  => tracked files
    # --others --exclude-standard => untracked files that are NOT gitignored
    #   (these get committed by 'git add .' below, so we dump them too)
    $gitFiles = git ls-files --cached --others --exclude-standard
    if ($LASTEXITCODE -ne 0) {
        throw "git ls-files failed."
    }

    # Everything git knows about, minus the configured exclusions.
    $TrackedPaths = $gitFiles |
        Where-Object { $_ -and -not (Test-PathExcluded $_) } |
        Sort-Object -Unique

    # Resolve to objects with metadata; keep only paths that exist on disk.
    $AllFiles = @(
        foreach ($rel in $TrackedPaths) {
            $full = Join-Path $ResolvedRoot $rel
            if (Test-Path -LiteralPath $full) {
                $name = Split-Path $rel -Leaf
                $ext  = if ($name -like '*.*') { ($name -replace '^.*\.', '').ToLower() } else { '' }
                [PSCustomObject]@{ Relative = $rel; Full = $full; Extension = $ext }
            }
        }
    )

    Write-Host "Found $($AllFiles.Count) files to export" -ForegroundColor Green

    # Build the dump with a StringBuilder, then write once (fast + atomic-ish)
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine(@"
===============================================================================
ASP.NET PROJECT EXPORT  (git-tracked files)
Generated: $(Get-Date)
Project Path: $ResolvedRoot
Excluded:   $($ExcludeDirectories -join ', ')
===============================================================================

DIRECTORY TREE:
===============
"@)

    [void]$sb.AppendLine("$RepoName/")
    $tree = ConvertTo-FileTree -Paths $AllFiles.Relative
    Write-FileTree -Node $tree -Builder $sb

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

        if (Test-FileIsBinary -Path $f.Full -Extension $f.Extension) {
            [void]$sb.AppendLine("[BINARY FILE — $([math]::Round($info.Length / 1KB, 2)) KB, contents omitted]")
        }
        else {
            try {
                $content = Get-Content -LiteralPath $f.Full -Raw -ErrorAction Stop
                if ($content) { [void]$sb.AppendLine($content) }
                else          { [void]$sb.AppendLine("[EMPTY FILE]") }
            }
            catch {
                [void]$sb.AppendLine("[ERROR READING FILE: $($_.Exception.Message)]")
            }
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
