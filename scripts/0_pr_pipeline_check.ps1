# Azure DevOps Migration Readiness Check Script
# Checks for active PRs, running builds, and running releases before migration

param(
    [Parameter(Mandatory=$false)]
    [string]$CsvPath = "repos.csv"
)

# Azure DevOps Personal Access Token
# Set your ADO PAT here or as an environment variable
$ADO_PAT = $env:ADO_PAT
if (-not $ADO_PAT) {
    Write-Host "[ERROR] ADO_PAT environment variable is not set. Please set your Azure DevOps Personal Access Token." -ForegroundColor Red
    Write-Host "You can set it by running: `$env:ADO_PAT = 'your-pat-token-here'" -ForegroundColor Yellow
    Write-Host "Or add it directly to the script by replacing the line above with: `$ADO_PAT = 'your-pat-token-here'" -ForegroundColor Yellow
    exit 1
}

# Declare arrays for validation results and flags for REST API failures
$activePRSummary = @()
$runningBuildSummary = @()
$runningReleaseSummary = @()
$buildCheckFailed = $false
$releaseCheckFailed = $false
$prCheckFailed = $false

# Read CSV file
if (-not (Test-Path $CsvPath)) {
    Write-Host "CSV file $CsvPath not found. Exiting..."
    exit 1
}
else {
    Write-Host "`nReading input from file: '$CsvPath'"
}

$orgRepoList = Import-Csv -Path $CsvPath

# Test ADO PAT token with the first organization
$testOrg = $orgRepoList[0].org
$testUri = "https://dev.azure.com/$testOrg/_apis/projects?api-version=7.1"
try {
    $response = Invoke-WebRequest -Uri $testUri -Method Get -Headers @{
        Authorization  = "Bearer $ADO_PAT"
        "Content-Type" = "application/json"
    } -ErrorAction Stop

    if ($response.StatusCode -ne 200) {
         Write-Host "✗ ADO PAT token authentication failed. Please verify your ADO_PAT environment variable is set correctly."
         exit 1
    }
}
catch {
     Write-Host "✗ ADO PAT token authentication failed. Please verify your ADO_PAT environment variable is set correctly."
    exit 1
}

Write-Host "`nScanning repositories for active pull requests..."
# Get active pull requests
foreach ($entry in $orgRepoList) {
    $ADO_ORG = $entry.org
    $ADO_PROJECT = $entry.teamproject
    $selectedRepoName = $entry.repo
    try {
        # Get repository ID
        $repoUri = "https://dev.azure.com/$ADO_ORG/$ADO_PROJECT/_apis/git/repositories/${selectedRepoName}?api-version=7.1"
        $repo = Invoke-RestMethod -Method GET -Uri $repoUri -Headers @{Authorization = "Bearer $ADO_PAT"; "Content-Type" = "application/json" } -ErrorAction Stop

        $repoId = $repo.id
        $repoName = $repo.name

        # Get active pull requests using repository ID
        $prUri = "https://dev.azure.com/$ADO_ORG/$ADO_PROJECT/_apis/git/repositories/${repoId}/pullrequests?searchCriteria.status=active&api-version=7.1"
        $prs = Invoke-RestMethod -Method GET -Uri $prUri -Headers @{Authorization = "Bearer $ADO_PAT"; "Content-Type" = "application/json" } -ErrorAction Stop

        foreach ($pr in $prs.value) {
            $activePRSummary += @{
                Project    = $ADO_PROJECT
                Repository = $repoName
                Title      = $pr.title
                Status     = $pr.status
            }
        }
    }
    catch {
        $prCheckFailed = $true
        Write-Host "[ERROR] Failed to process PRs for repository '$selectedRepoName' in project '$ADO_PROJECT'." -ForegroundColor Red
    }
}

$uniqueProjects = $orgRepoList | Select-Object org, teamproject -Unique
Write-Host "`nScanning projects for active running build and release pipelines..."
foreach ($project in $uniqueProjects) {
    $ADO_ORG = $project.org
    $ADO_PROJECT = $project.teamproject

    # Check active pipelines
    try {
        $buildsUri = "https://dev.azure.com/$ADO_ORG/$ADO_PROJECT/_apis/build/builds?api-version=7.1"
        $allBuilds = Invoke-RestMethod -Method GET -Uri $buildsUri -Headers @{Authorization = "Bearer $ADO_PAT"; "Content-Type" = "application/json" } -ErrorAction Stop
        
        $notCompletedBuilds = $allBuilds.value | Where-Object { $_.status -eq "inProgress" -or $_.status -eq "notStarted" }
        # Note: This step filters build pipelines that are currently running or in a queued state.
        # Reference: List of available build status values – https://learn.microsoft.com/en-us/rest/api/azure/devops/build/builds/list?view=azure-devops-rest-7.1#buildstatus

        foreach ($build in $notCompletedBuilds) {
            $runningBuildSummary += @{
                Project  = $ADO_PROJECT
                Pipeline = $build.definition.name
                Status   = "In Progress/ Queued"
            }
        }
    }
    catch {
        $buildCheckFailed = $true
        Write-Host "[ERROR] Failed to retrieve builds for project '$ADO_PROJECT'." -ForegroundColor Red
    }

    # Check active release pipelines
    try {
        $releasesUri = "https://vsrm.dev.azure.com/$ADO_ORG/$ADO_PROJECT/_apis/release/releases?api-version=7.1"
        $releaseIds = Invoke-RestMethod -Method GET -Uri $releasesUri -Headers @{Authorization = "Bearer $ADO_PAT"; "Content-Type" = "application/json" } -ErrorAction Stop

        foreach ($releaseId in $releaseIds.value.id) {
            try {
                $releaseDetailsUri = "https://vsrm.dev.azure.com/$ADO_ORG/$ADO_PROJECT/_apis/release/releases/${releaseId}?api-version=7.1"
                $releaseDetails = Invoke-RestMethod -Method GET -Uri $releaseDetailsUri -Headers @{Authorization = "Bearer $ADO_PAT"; "Content-Type" = "application/json" } -ErrorAction Stop

                # Check if any environments in the release are still running
                # A release is considered "running" if any of its environments are in progress
                $runningEnvironments = $releaseDetails.environments | Where-Object { 
                    $_.status -eq "inProgress" 
                }
                # Note: This checks individual environment statuses within the release
                # Reference: Environment status values – https://learn.microsoft.com/en-us/rest/api/azure/devops/release/releases/get-release?view=azure-devops-rest-7.1&tabs=HTTP#environmentstatus

                if ($runningEnvironments -and @($runningEnvironments).Count -gt 0) {
                    $environmentStatuses = ($runningEnvironments | ForEach-Object { "$($_.name): $($_.status)" }) -join ", "
                    $runningReleaseSummary += @{
                        Project = $ADO_PROJECT
                        Name    = $releaseDetails.name
                        Status  = "In Progress ($environmentStatuses)"
                    }
                }
            }
            catch {
                $releaseCheckFailed = $true
                Write-Host "[ERROR] Failed to retrieve release ID $releaseId." -ForegroundColor Red
            }
        }
    }
    catch {
        $releaseCheckFailed = $true
        Write-Host "[ERROR] Failed to retrieve release list for project '$ADO_PROJECT'." -ForegroundColor Red
    }
}

# Final Summary
Write-Host "`nPre-Migration Validation Summary"
Write-Host "================================"

if (-not $prCheckFailed) {
    if ($activePRSummary.Count -gt 0) {
        Write-Host "`n[BLOCKER] Detected Active Pull Request(s):" -ForegroundColor Red
        foreach ($entry in $activePRSummary) {
            Write-Host "Project: $($entry.Project) | Repository: $($entry.Repository) | Title: $($entry.Title) | Status: $($entry.Status)"
        }
    }
    else {
        Write-Host "`nPull Request Summary --> No Active Pull Requests" -ForegroundColor Green
    }
}

if (-not $buildCheckFailed) {
    if ($runningBuildSummary.Count -gt 0) {
        Write-Host "`n[BLOCKER] Detected Running Build Pipeline(s):" -ForegroundColor Red
        foreach ($entry in $runningBuildSummary) {
            Write-Host "Project: $($entry.Project) | Pipeline: $($entry.Pipeline) | Status: $($entry.Status)"
        }
    }
    else {
        Write-Host "`nBuild Pipeline Summary --> No Active Running Builds" -ForegroundColor Green
    }
}
if (-not $releaseCheckFailed) {
    if ($runningReleaseSummary.Count -gt 0) {
        Write-Host "`n[BLOCKER] Detected Running Release Pipeline(s):" -ForegroundColor Red
        foreach ($entry in $runningReleaseSummary) {
            Write-Host "Project: $($entry.Project) | Release Name: $($entry.Name) | Status: $($entry.Status)"
        }
    }
    else {
        Write-Host "`nRelease Pipeline Summary --> No Active Running Releases" -ForegroundColor Green
    }
}
if (
    $activePRSummary.Count -eq 0 -and 
    $runningBuildSummary.Count -eq 0 -and 
    $runningReleaseSummary.Count -eq 0 -and 
    -not $prCheckFailed -and 
    -not $buildCheckFailed -and 
    -not $releaseCheckFailed
) {
    Write-Host "`nNo active pull requests or running pipelines found. You may proceed with migration.`n" -ForegroundColor Green
}
else {
    Write-Host "`nMigration blocked due to active PRs or running pipelines. Please resolve these issues before starting the migration.`n" -ForegroundColor Red
}
