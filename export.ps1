# Export Git-tracked ASP.NET Project Files to Single Text File
# Uses `git ls-files` so only committed/staged files are included.

param(
    [string]$ProjectPath = ".",
    [string]$OutputFile = "docs/llm/dump.txt"
)

# File extensions to include (without the leading dot)
$IncludeExtensions = @(
    "cs", "json", "xml", "csproj", "slnx", "sln", "config",
    "cshtml", "razor", "js", "css", "scss", "html",
    "yml", "yaml", "sql", "props", "targets", "sh",
    "ps1"
)

# Exact filenames (no extension match needed)
$IncludeSpecificFiles = @(
    "Dockerfile", ".dockerignore", ".editorconfig",
    ".gitignore", ".gitattributes"
)

# Directories to skip even if tracked (e.g. this script's own output)
$ExcludeDirectories = @("docs")

Write-Host "Starting project export..." -ForegroundColor Green
Write-Host "Project Path: $ProjectPath" -ForegroundColor Yellow
Write-Host "Output File: $OutputFile" -ForegroundColor Yellow

# ── Resolve paths ────────────────────────────────────────────────────────────
Push-Location $ProjectPath
$ResolvedRoot = (Resolve-Path ".").Path

$OutputPath = Join-Path $ResolvedRoot $OutputFile
$outputDir  = Split-Path $OutputPath -Parent
if (!(Test-Path $outputDir)) { New-Item -ItemType Directory -Path $outputDir -Force | Out-Null }

# ── Get tracked files from Git ───────────────────────────────────────────────
Write-Host "Querying git for tracked files..." -ForegroundColor Cyan

$gitFiles = git ls-files --cached --others --exclude-standard 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: git ls-files failed. Are you inside a git repository?" -ForegroundColor Red
    Pop-Location
    exit 1
}

# Filter to desired extensions / specific filenames, and exclude dirs
$AllFiles = $gitFiles | ForEach-Object {
    $rel = $_
    $name = Split-Path $rel -Leaf
    $ext  = ($name -replace '^.*\.', '').ToLower()

    # Skip excluded directories
    $skip = $false
    foreach ($d in $ExcludeDirectories) {
        if ($rel -like "$d/*" -or $rel -like "$d\*") { $skip = $true; break }
    }
    if ($skip) { return }

    # Match by extension or specific filename
    if ($IncludeExtensions -contains $ext -or $IncludeSpecificFiles -contains $name) {
        $fullPath = Join-Path $ResolvedRoot $rel
        if (Test-Path $fullPath) {
            [PSCustomObject]@{ Relative = $rel; Full = $fullPath }
        }
    }
} | Sort-Object Relative

Write-Host "Found $($AllFiles.Count) files to export" -ForegroundColor Green

# ── Write header ─────────────────────────────────────────────────────────────
$header = @"
===============================================================================
ASP.NET PROJECT EXPORT  (git-tracked files only)
Generated: $(Get-Date)
Project Path: $ResolvedRoot
===============================================================================

"@
$header | Out-File -FilePath $OutputPath -Encoding UTF8

# ── Directory tree (git ls-tree) ─────────────────────────────────────────────
"DIRECTORY STRUCTURE (tracked):" | Out-File -FilePath $OutputPath -Append -Encoding UTF8
"==============================" | Out-File -FilePath $OutputPath -Append -Encoding UTF8
""  | Out-File -FilePath $OutputPath -Append -Encoding UTF8

# Show a compact tree of tracked paths
$gitFiles | Sort-Object | Out-File -FilePath $OutputPath -Append -Encoding UTF8

""  | Out-File -FilePath $OutputPath -Append -Encoding UTF8
""  | Out-File -FilePath $OutputPath -Append -Encoding UTF8

# ── File contents ────────────────────────────────────────────────────────────
"FILE CONTENTS:" | Out-File -FilePath $OutputPath -Append -Encoding UTF8
"==============" | Out-File -FilePath $OutputPath -Append -Encoding UTF8
""  | Out-File -FilePath $OutputPath -Append -Encoding UTF8

$i = 0
foreach ($f in $AllFiles) {
    $i++
    $info = Get-Item $f.Full
    Write-Host "Processing ($i/$($AllFiles.Count)): $($f.Relative)" -ForegroundColor White

    $sep = "=" * 80
    @"
$sep
FILE: $($f.Relative)
SIZE: $([math]::Round($info.Length / 1KB, 2)) KB
MODIFIED: $($info.LastWriteTime)
$sep

"@ | Out-File -FilePath $OutputPath -Append -Encoding UTF8

    try {
        $content = Get-Content -Path $f.Full -Raw -ErrorAction Stop
        if ($content) {
            $content | Out-File -FilePath $OutputPath -Append -Encoding UTF8
        } else {
            "[EMPTY FILE]" | Out-File -FilePath $OutputPath -Append -Encoding UTF8
        }
    } catch {
        "[ERROR READING FILE: $($_.Exception.Message)]" | Out-File -FilePath $OutputPath -Append -Encoding UTF8
    }

    "" | Out-File -FilePath $OutputPath -Append -Encoding UTF8
    "" | Out-File -FilePath $OutputPath -Append -Encoding UTF8
}

# ── Footer ───────────────────────────────────────────────────────────────────
@"
===============================================================================
EXPORT COMPLETED: $(Get-Date)
Total Files Exported: $i
Output File: $OutputPath
===============================================================================
"@ | Out-File -FilePath $OutputPath -Append -Encoding UTF8

Pop-Location

Write-Host "`nExport completed!" -ForegroundColor Green
Write-Host "Total files exported: $i" -ForegroundColor Green
Write-Host "Output file size: $([math]::Round((Get-Item $OutputPath).Length / 1KB, 2)) KB" -ForegroundColor Cyan
