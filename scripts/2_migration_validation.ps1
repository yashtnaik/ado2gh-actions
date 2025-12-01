
#requires -Version 7.0
<#
.SYNOPSIS
  ADO → GitHub post-migration validation

.DESCRIPTION
  Validates migrated repositories by reading rows from a CSV and performing checks
  (existence in the target GitHub org via gh CLI). Script is dynamic: values come
  from environment variables but can be overridden via parameters. If GhOrg is not
  provided, it is derived from the CSV's first row `github_org` (fallback `GH_ORG`).

.PARAMETER CsvPath
  Path to CSV (defaults to $env:CSV_PATH)

.PARAMETER GhOrg
  GitHub organization (defaults to $env:GH_ORG, otherwise derived from CSV)

.EXPECTED CSV COLUMNS
  org, teamproject, repo, url, last-push-date, pipeline-count,
  compressed-repo-size-in-bytes, most-active-contributor, pr-count,
  commits-past-year, github_org, github_repo, gh_repo_visibility

.OUTPUTS
  - validation-log-<timestamp>.txt
  - validation-results-<timestamp>.json
  - validation_summary.csv

.NOTES
  Only comments and #requires may appear above the param(...) block.
#>

param(
  [Parameter(Mandatory = $false)]
  [string] $CsvPath = $env:CSV_PATH,

  [Parameter(Mandatory = $false)]
  [string] $GhOrg = $env:GH_ORG
)

# ---- Executable statements start after param ----
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Timestamp for artifacts
$stamp    = Get-Date -Format 'yyyyMMdd-HHmmss'
$logPath  = "validation-log-$stamp.txt"
$jsonPath = "validation-results-$stamp.json"

function Write-Log {
  param([string]$Message)
  Write-Host $Message
  Add-Content -LiteralPath $logPath -Value $Message
}

# Validate CSV path
if (-not $CsvPath) {
  throw "CSV path is missing. Set env CSV_PATH or pass -CsvPath."
}
if (-not (Test-Path -LiteralPath $CsvPath)) {
  throw "CSV path '$CsvPath' does not exist. Check the path or ensure the file is checked out."
}

# Read the CSV and ensure it's always treated as an array
try {
  $rows = @(Import-Csv -LiteralPath $CsvPath)
} catch {
  throw "Failed to read CSV '$CsvPath'. $_"
}

if (@($rows).Count -eq 0) {
  throw "CSV '$CsvPath' has no data rows."
}

# Derive GhOrg from CSV if missing
if (-not $GhOrg) {
  $first = $rows | Select-Object -First 1
  $GhOrg = $first.github_org
  if (-not $GhOrg) { $GhOrg = $first.GH_ORG } # fallback if column named GH_ORG
  if (-not $GhOrg) {
    throw "GH org is missing. Provide -GhOrg, set env GH_ORG, or include 'github_org' in the CSV."
  }
}

Write-Host "Validation in progress... please wait ..."

# Check GH CLI availability
$ghAvailable = $false
try {
  $null = & gh --version
  $ghAvailable = $true
} catch {
  $ghAvailable = $false
}

# If GH_PAT is set, feed it to gh via GH_TOKEN and authenticate if needed
if ($env:GH_PAT) {
  $env:GH_TOKEN = $env:GH_PAT
  if ($ghAvailable) {
    try {
      gh auth status
    } catch {
      Write-Host "Authenticating gh with GH_TOKEN..."
      Write-Output $env:GH_TOKEN | gh auth login --with-token
      # Optional: avoid org prompts
      gh config set git_protocol https
    }
  }
}

# Prepare results as a List to always have Count
$results = New-Object System.Collections.Generic.List[object]

# Iterate rows and perform checks
foreach ($r in $rows) {
  $org                   = $r.org
  $teamProject           = $r.teamproject
  $repo                  = $r.repo
  $sourceUrl             = $r.url
  $lastPushDate          = $r.'last-push-date'
  $pipelineCount         = $r.'pipeline-count'
  $compressedSizeBytes   = $r.'compressed-repo-size-in-bytes'
  $mostActiveContributor = $r.'most-active-contributor'
  $prCount               = $r.'pr-count'
  $commitsPastYear       = $r.'commits-past-year'
  $rowGhOrg              = $r.github_org
  $rowGhRepo             = $r.github_repo
  $ghRepoVisibility      = $r.gh_repo_visibility

  # Prefer per-row org from CSV; fallback to derived/global GhOrg
  $targetOrg      = if ($rowGhOrg) { $rowGhOrg } else { $GhOrg }
  $targetRepoName = if ($rowGhRepo) { $rowGhRepo } else { $repo }
  $fullGhRepo     = if ($targetOrg -and $targetRepoName) { "$targetOrg/$targetRepoName" } else { $null }

  $existsInGh = 'Unknown'
  $notes = @()

  if ($null -eq $fullGhRepo) {
    $existsInGh = 'Skipped'
    $notes += "Missing target org/repo name."
  }
  elseif ($ghAvailable) {
    try {
      $null = & gh repo view $fullGhRepo --json name --jq '.name'
      $existsInGh = 'Yes'
    } catch {
      $existsInGh = 'No'
      $notes += "Repo not found in GH org."
    }
  } else {
    $existsInGh = 'Unknown'
    $notes += "gh CLI unavailable on runner; existence check skipped."
  }

  $results.Add([pscustomobject]@{
    source_org                 = $org
    source_teamproject         = $teamProject
    source_repo                = $repo
    source_url                 = $sourceUrl
    last_push_date             = $lastPushDate
    pipeline_count             = $pipelineCount
    compressed_repo_size_bytes = $compressedSizeBytes
    most_active_contributor    = $mostActiveContributor
    pr_count                   = $prCount
    commits_past_year          = $commitsPastYear
    github_org                 = $targetOrg
    github_repo                = $targetRepoName
    gh_repo_visibility         = $ghRepoVisibility
    gh_full_name               = $fullGhRepo
    exists_in_github           = $existsInGh
    notes                      = ($notes -join '; ')
  })
}

# Robust counts (wrap pipelines in array to avoid 'Count' on single object)
$total   = @($results).Count
$yesCnt  = @( $results | Where-Object { $_.exists_in_github -eq 'Yes' } ).Count
$noCnt   = @( $results | Where-Object { $_.exists_in_github -eq 'No' } ).Count
$skipCnt = @( $results | Where-Object { $_.exists_in_github -eq 'Skipped' } ).Count
$unkCnt  = @( $results | Where-Object { $_.exists_in_github -eq 'Unknown' } ).Count

Write-Log "======================"
Write-Log "Validation Summary"
Write-Log "======================"
Write-Log "Total rows: $total"
Write-Log "Exists in GitHub: $yesCnt"
Write-Log "Missing in GitHub: $noCnt"
Write-Log "Skipped: $skipCnt"
Write-Log "Unknown: $unkCnt"
Write-Log ""

# Save artifacts
try {
  $results | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
  Write-Log "Saved JSON: $jsonPath"
} catch {
  Write-Log "Failed to write JSON results: $_"
}

# Console table
$results | Select-Object github_org, github_repo, exists_in_github, notes | Format-Table -AutoSize | Out-Host

# CSV summary
$summaryCsvPath = "validation_summary.csv"
try {
  $results | Export-Csv -LiteralPath $summaryCsvPath -NoTypeInformation
  Write-Log "Saved CSV summary: $summaryCsvPath"
} catch {
  Write-Log "Failed to write CSV summary: $_"
}

# Non-fatal: keep job success even if some repos missing
## Uncomment to fail when missing repos exist:
