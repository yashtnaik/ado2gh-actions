
#requires -Version 7.0
<#
.SYNOPSIS
  ADO → GitHub post-migration validation.
.DESCRIPTION
  Reads repositories from a CSV and performs validation checks against the migrated repos in the target GitHub org.
  Script is dynamic: values come from environment variables but can be overridden via parameters.

  Expected environment variables (all optional if you pass parameters):
    - CSV_PATH        : Path to CSV containing repositories (header-only ref is fine; we'll validate existence)
    - GH_ORG          : Target GitHub organization
    - GH_PAT          : GitHub token (if the script uses gh/REST calls internally)
    - ADO_ORG_URL     : (optional if needed by your validation logic)

.PARAMETER CsvPath
  Path to CSV file. Defaults to $env:CSV_PATH.

.PARAMETER GhOrg
  GitHub organization. Defaults to $env:GH_ORG.

.NOTES
  Keep ONLY comments or `#requires` above `param(...)`. No executable statements before `param`.
#>

param(
  [Parameter(Mandatory = $false)]
  [string] $CsvPath = $env:CSV_PATH,

  [Parameter(Mandatory = $false)]
  [string] $GhOrg = $env:GH_ORG
)

# ---- Executable statements start after param ----

# Prefer strict mode after param
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Optional: read GH_PAT if needed by your internal validation calls
$ghPat = $env:GH_PAT

# Basic input validation
if (-not $CsvPath) {
  throw "CSV path is missing. Set env CSV_PATH or pass -CsvPath."
}
if (-not (Test-Path -LiteralPath $CsvPath)) {
  throw "CSV path '$CsvPath' does not exist. Check the path or ensure the file is checked out."
}
if (-not $GhOrg) {
  throw "GH org is missing. Set env GH_ORG or pass -GhOrg."
}

Write-Host "Validation in progress... please wait ..."

# ===== Your existing validation logic =====
# The below is a safe scaffold—plug in your real checks.
# It keeps the script dynamic and prints a concise summary.

# Load CSV
try {
  $repos = Import-Csv -LiteralPath $CsvPath
} catch {
  throw "Failed to read CSV '$CsvPath'. $_"
}

if (-not $repos) {
  Write-Warning "CSV '$CsvPath' is empty. Nothing to validate."
  return
}

# Example: Ensure GH CLI is authenticated if you're using it downstream
if ($ghPat) {
  # This sets GH token for the session if needed (optional)
  $env:GH_TOKEN = $ghPat
}

# Placeholder: perform your repo validation loop
$results = @()
foreach ($r in $repos) {
  # Assuming CSV has a column like 'RepoName' or 'Repository'
  $repoName = $r.RepoName
  if (-not $repoName) {
    $repoName = $r.Repository
  }

  if (-not $repoName) {
    $results += [pscustomobject]@{
      Repository = "(missing name)"
      Status     = "Skipped"
      Notes      = "No repository name in CSV row."
    }
    continue
  }

  # ---- Replace the sample check with your actual validation logic ----
  # Example simple check: does the repo exist in GH?
  # Using gh CLI (optional):
  # $exists = $false
  # try {
  #   $null = gh repo view "$GhOrg/$repoName" --json name --jq .name
  #   $exists = $true
  # } catch {
  #   $exists = $false
  # }

  # For illustration, we mark every repo as Validated
  $results += [pscustomobject]@{
    Repository = "$GhOrg/$repoName"
    Status     = "Validated"
    Notes      = "Sample validation succeeded (replace with real checks)."
  }
}

# Output a summary table
Write-Host ""
Write-Host "======================"
Write-Host "Validation Summary"
Write-Host "======================"
$results | Format-Table -AutoSize | Out-Host

# Optionally write results to a CSV for artifacts
$summaryPath = Join-Path (Split-Path -Parent $CsvPath) "validation_summary.csv"
try {
  $results | Export-Csv -LiteralPath $summaryPath -NoTypeInformation
  Write-Host "Saved summary: $summaryPath"
} catch {
  Write-Warning "Failed to write summary CSV. $_"
}
