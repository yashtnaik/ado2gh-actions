# ADO to GitHub Migration - GitHub Actions Automation

Automated Azure DevOps to GitHub repository migration using GitHub Actions with concurrent job processing.

## 🎯 Overview

This repository provides a GitHub Actions workflow that automates the migration of repositories from Azure DevOps to GitHub using the `gh ado2gh` CLI extension. The workflow implements **Option B: Single Runner with Concurrent Jobs**, processing multiple repositories in parallel on a single runner for optimal resource utilization.

### Key Features

- ✅ **Concurrent Migrations**: Process 1-5 repositories simultaneously
- ✅ **Real-time Monitoring**: Live console output with status updates
- ✅ **Comprehensive Logging**: Individual log files for each repository
- ✅ **CSV Tracking**: Real-time CSV updates with migration status
- ✅ **Artifact Storage**: 90-day retention of logs and results
- ✅ **Detailed Summaries**: Visual reports with success/failure breakdowns
- ✅ **Flexible Configuration**: Customizable via workflow inputs

## 📋 Prerequisites

### Required Accounts & Permissions

1. **Azure DevOps Account** with:
   - Read access to source repositories
   - Permission to create Personal Access Tokens (PAT)

2. **GitHub Account** with:
   - Admin access to target organization
   - Permission to create repositories
   - Actions enabled on the repository

### Required Tools

- GitHub CLI (`gh`) - Pre-installed on GitHub-hosted runners
- `gh ado2gh` extension - Automatically installed by workflow
- PowerShell 7+ - Pre-installed on windows-latest runners

## 🚀 Quick Start

### 1. Fork or Clone This Repository

```bash
gh repo clone vamsicherukuri/ado2gh_actions
cd ado2gh_actions
```

### 2. Configure Secrets

Navigate to your repository settings and add the following secrets:

**Settings → Secrets and variables → Actions → New repository secret**

| Secret Name | Description | How to Generate |
|-------------|-------------|-----------------|
| `GH_PAT` | GitHub Personal Access Token | [Create PAT](https://github.com/settings/tokens/new) with `repo`, `workflow`, `admin:org` scopes |
| `ADO_PAT` | Azure DevOps Personal Access Token | [Create ADO PAT](https://dev.azure.com) with `Code (Read)`, `Project and Team (Read)` scopes |

#### Creating GitHub PAT (GH_PAT)

1. Go to https://github.com/settings/tokens/new
2. Select scopes:
   - ✅ `repo` (Full control of private repositories)
   - ✅ `workflow` (Update GitHub Action workflows)
   - ✅ `admin:org` (Full control of orgs and teams)
3. Click **Generate token**
4. Copy and save as `GH_PAT` secret

#### Creating Azure DevOps PAT (ADO_PAT)

1. Go to https://dev.azure.com/{your-org}/_usersSettings/tokens
2. Click **+ New Token**
3. Select scopes:
   - ✅ `Code` → Read
   - ✅ `Project and Team` → Read
4. Click **Create**
5. Copy and save as `ADO_PAT` secret

### 3. Prepare Repository List

Edit the `repos.csv` file with your repositories to migrate:

```csv
org,teamproject,repo,github_org,github_repo,gh_repo_visibility
contosodevopstest,ContosoProject,ContosoBackendAPI,my-github-org,ContosoBackendAPI,private
contosodevopstest,ContosoProject,ContosoWebApp,my-github-org,ContosoWebApp,private
```

**Column Descriptions:**

| Column | Description | Example |
|--------|-------------|---------|
| `org` | Azure DevOps organization name | `contosodevopstest` |
| `teamproject` | ADO Team Project name | `ContosoProject` |
| `repo` | Source repository name in ADO | `ContosoBackendAPI` |
| `github_org` | Target GitHub organization | `my-github-org` |
| `github_repo` | Target repository name in GitHub | `ContosoBackendAPI` |
| `gh_repo_visibility` | Repository visibility: `private`, `public`, or `internal` | `private` |

## 🔄 Available Workflows

This repository contains five workflows that can run sequentially or independently:

### 1. Migration Readiness Check (`0_pr_pipeline_check.ps1`)

**Workflow**: `0-pr-pipeline-check.yml`

Validates that repositories are ready for migration by checking for:
- Active Pull Requests
- Running Builds
- Running Releases

**When to run**: Before starting migration to identify potential blockers

**How to run**:
1. Navigate to **Actions** → **0-pr-pipeline-check**
2. Click **Run workflow**
3. Configure:
   - **CSV path**: Path to repository list (default: `repos.csv`)
   - **Trigger migration**: Whether to automatically start migration (default: `false`)

**Outputs**: Readiness report identifying any blockers

---

### 2. Concurrent Migration (`1_migration.ps1`)

**Workflow**: `1-migration.yml`

Performs the actual repository migration with concurrent processing.

**When to run**: After readiness check passes or independently if you're confident

**How to run**:
1. Navigate to **Actions** → **1-migration**
2. Click **Run workflow**
3. Configure:
   - **Maximum concurrent migrations**: Choose 1-5 (default: `3`)
   - **CSV path**: Path to repository list (default: `repos.csv`)
   - **Trigger validation**: Auto-start validation after migration (default: `false`)

**Outputs**: Migration logs, status CSV, individual repository logs

---

### 3. Migration Validation (`2_migration_validation.ps1`)

**Workflow**: `2-migration-validation.yml`

Validates migrated repositories by comparing:
- Branch counts between ADO and GitHub
- Branch names (identifies missing branches)
- Commit counts per branch
- Latest commit SHA per branch

**When to run**: After migration completes to verify data integrity

**How to run**:
1. Navigate to **Actions** → **2-migration-validation**
2. Click **Run workflow**
3. Configure:
   - **CSV path**: Path to repository list (default: `repos.csv`)
   - **Trigger mannequins**: Auto-start mannequin validation (default: `false`)
   - **GitHub org**: Organization name (required if triggering mannequins)

**Outputs**: Validation log with detailed comparison results, JSON files per repository

---

### 4. Mannequin Validation (`3_mannequins_validation.ps1`)

**Workflow**: `3-mannequins-validation.yml`

Detects mannequin users (placeholder users created during migration) and generates a CSV file for reclamation.

**What are mannequins?**
When migrating from Azure DevOps, GitHub creates "mannequin" users for ADO users who don''t have matching GitHub accounts. These mannequins need to be reclaimed (mapped to real GitHub users).

**When to run**: After migration validation completes

**How to run**:
1. Navigate to **Actions** → **3-mannequins-validation**
2. Click **Run workflow**
3. Configure:
   - **GitHub org**: Your GitHub organization name
   - **Output file**: CSV filename (default: `mannequins.csv`)
   - **Trigger reclaim**: Auto-start mannequin reclaim (default: `false`)

**Outputs**: 
- `mannequins.csv` with list of mannequins to reclaim
- Artifact: `mannequins-csv-{run_number}` (90-day retention)
- Workflow summary showing count and preview of mannequins

---

### 5. Mannequin Reclaim (`4_mannequins_reclaim.ps1`)

**Workflow**: `4-mannequins-reclaim.yml`

Reclaims mannequin users by mapping them to actual GitHub users in your organization.

**When to run**: After mannequin validation generates the CSV

**How to run**:
1. Navigate to **Actions** → **4-mannequins-reclaim**
2. Click **Run workflow**
3. Configure:
   - **GitHub org**: Your GitHub organization name
   - **CSV file**: Path to mannequin CSV (leave empty to download from artifacts)
   - **Skip invitation**: Skip sending email invitations (default: `false`)
   - **Artifact run number**: Run number to download CSV from (if csv_file is empty)

**Outputs**: 
- Reclaim results and logs
- Artifact: `mannequin-reclaim-results-{run_number}` (90-day retention)
- Workflow summary showing processed mannequins and invitation status

---

### 4. Run the Workflows (Step-by-Step)

#### Option A: Sequential Execution (Recommended)

1. **Run Readiness Check First**:
   - Actions → 0_pr_pipeline_check → Run workflow
   - Review output for any blockers
   - Fix any issues identified

2. **Run Migration**:
   - Actions → 1_migration → Run workflow
   - Set "Trigger validation" to `true` for automatic validation

3. **Validation runs automatically** (or run manually if trigger_validation was false)

#### Option B: Independent Execution

Run any workflow independently based on your needs:
- **Readiness only**: Test multiple times before migration
- **Migration only**: Skip readiness if you're confident
- **Validation only**: Re-validate after fixes or changes

## 📊 Monitoring Migration Progress

### Real-Time Console Output

Once the workflow starts, you can monitor live progress:

```
[INFO] Starting migration with 3 concurrent jobs...
[INFO] Processing 10 repositories from: repos.csv
[INFO] Initialized migration status output: repo_migration_output-20251109-143022.csv

QUEUE: 7 | IN PROGRESS: 3 | MIGRATED: 0 | MIGRATION FAILED: 0

[2025-11-09 14:30:25] [START] Migration: ContosoProject/ContosoBackendAPI -> my-github-org/ContosoBackendAPI
[2025-11-09 14:30:25] [DEBUG] Running: gh ado2gh migrate-repo...
✓ Migration ID: 12345 created
⏳ Migration state: IN_PROGRESS (Exporting: 45% complete)
✓ Migration state: SUCCEEDED

[2025-11-09 14:35:12] [SUCCESS] Migration: ContosoProject/ContosoBackendAPI -> my-github-org/ContosoBackendAPI

QUEUE: 6 | IN PROGRESS: 3 | MIGRATED: 1 | MIGRATION FAILED: 0
```

### Status Bar Updates

The workflow displays a live status bar that updates every 5 seconds:

- **QUEUE**: Repositories waiting to be processed
- **IN PROGRESS**: Currently migrating
- **MIGRATED**: Successfully completed
- **MIGRATION FAILED**: Failed migrations

### Workflow Summary

After completion, a detailed summary is generated:

```markdown
# 🚀 Migration Execution Summary

## 📊 Overall Statistics
- **Total Repositories**: 10
- **Successfully Migrated**: ✅ 9
- **Failed Migrations**: ❌ 1
- **Success Rate**: 90%
- **Concurrent Jobs**: 3

## ❌ Failed Migrations
| Repository | ADO Org | ADO Team Project | GitHub Org | Log File |
|------------|---------|------------------|------------|----------|
| LegacyRepo | contosodevopstest | OldProject | my-github-org | migration-LegacyRepo-20251109-143045.txt |

## ✅ Successfully Migrated Repositories
| Repository | GitHub URL |
|------------|------------|
| ContosoBackendAPI | https://github.com/my-github-org/ContosoBackendAPI |
| ContosoWebApp | https://github.com/my-github-org/ContosoWebApp |
...
```

## 📂 Accessing Logs and Results

### Workflow Artifacts

Each workflow produces specific artifacts:

#### 1. 0-pr-pipeline-check
- **readiness-check-results-{run_number}**: Readiness validation report
- **Retention**: 30 days

#### 2. 1-migration
- **migration-logs-{run_id}**: Individual log files for each repository
- **migration-output-csv-{run_id}**: Summary CSV with migration status
- **Retention**: 90 days

#### 3. 2-migration-validation
- **validation-results-{run_number}**: Validation logs and JSON files
- **Retention**: 30 days

#### 4. 3-mannequins-validation
- **mannequins-csv-{run_number}**: CSV file with mannequin user list
- **Retention**: 90 days

#### 5. 4-mannequins-reclaim
- **mannequin-reclaim-results-{run_number}**: Reclaim results and logs
- **Retention**: 90 days

### Method 1: GitHub Actions Artifacts (Recommended)

After the workflow completes:

1. Scroll to the bottom of the workflow run page
2. Locate the **Artifacts** section
3. Download artifacts:
   - **migration-logs-{run_id}.zip** - All individual migration logs
   - **migration-output-csv-{run_id}.zip** - Summary CSV with status
   - **validation-results-{run_number}.zip** - Validation comparison data

**Artifact Contents:**

```
migration-logs/
├── migration-ContosoBackendAPI-20251109-143022.txt
├── migration-ContosoWebApp-20251109-143030.txt
└── [... more log files]

migration-output-csv/
└── repo_migration_output-20251109-143022.csv

validation-results/
├── validation-log-20251109.txt
├── validation-ContosoBackendAPI.json
└── [... more validation files]
```

### Method 2: GitHub CLI

```powershell
# List recent workflow runs
gh run list --workflow="migration-concurrent.yml" --limit 5

# Download artifacts for specific run
gh run download <RUN_ID> --dir ./migration-artifacts

# View specific log
Get-Content ./migration-artifacts/migration-logs/migration-ContosoBackendAPI-*.txt
```

### Method 3: During Execution

The CSV file is updated in real-time during migration. Each entry shows:

| org | teamproject | repo | github_org | github_repo | gh_repo_visibility | Migration_Status | Log_File |
|-----|-------------|------|------------|-------------|-------------------|------------------|----------|
| contosodevopstest | ContosoProject | ContosoBackendAPI | my-github-org | ContosoBackendAPI | private | Success | migration-ContosoBackendAPI-20251109-143022.txt |
| contosodevopstest | ContosoProject | ContosoWebApp | my-github-org | ContosoWebApp | private | Failure | migration-ContosoWebApp-20251109-143030.txt |

**Status Values:**
- `Pending` - Not started yet
- (No status) - Currently migrating
- `Success` - Completed successfully
- `Failure` - Migration failed

## ⚙️ Configuration Options

### Workflow Inputs

| Input | Description | Default | Options |
|-------|-------------|---------|---------|
| `max_concurrent` | Maximum concurrent migrations | `3` | `1`, `2`, `3`, `4`, `5` |
| `csv_path` | Path to repos CSV file | `repos.csv` | Any valid path |

### Adjusting Concurrency

**For smaller batches (1-20 repos):**
- Use `max_concurrent: 2-3` for stability
- Lower concurrency = easier to monitor

**For larger batches (50+ repos):**
- Use `max_concurrent: 4-5` for faster completion
- Higher concurrency = faster but more resource-intensive

### Timeout Settings

The workflow has an 8-hour timeout (`480 minutes`). For very large migrations, you can adjust this in the workflow YAML:

```yaml
jobs:
  migrate-repositories:
    timeout-minutes: 720  # 12 hours
```

## 🔧 Troubleshooting

### Common Issues

#### 1. Authentication Failures

**Error:** `gh auth status` fails or `gh ado2gh` commands return 401/403

**Solution:**
- Verify `GH_PAT` and `ADO_PAT` secrets are correctly set
- Ensure PATs have required scopes
- Check PAT expiration dates

#### 2. CSV Validation Errors

**Error:** `[ERROR] Missing required columns: ...`

**Solution:**
- Verify CSV has all required columns: `org`, `teamproject`, `repo`, `github_org`, `github_repo`, `gh_repo_visibility`
- Check for typos in column names (case-sensitive)
- Ensure no empty rows

#### 3. Migration Failures

**Error:** `[FAILED] Migration: ...` or `State: FAILED` in logs

**Solution:**
- Check individual log files for detailed error messages
- Common causes:
  - Repository already exists in target org
  - Insufficient permissions
  - Repository too large
  - Network timeouts

**Review the log file:**
```powershell
# Download artifacts and extract
Get-Content ./migration-logs/migration-{repo-name}-*.txt | Select-String -Pattern "ERROR|FAILED|State:"
```

#### 4. Workflow Timeout

**Error:** Workflow exceeds 8-hour limit

**Solution:**
- Split migration into smaller batches
- Increase timeout in workflow YAML
- Use higher concurrency (4-5)

### Debug Mode

To enable verbose logging, modify the script:

```powershell
# In 1_migration.ps1, add at the top:
$VerbosePreference = 'Continue'
$DebugPreference = 'Continue'
```

## 📈 Scalability

### Performance Benchmarks

| Repos | Concurrency | Est. Time | Notes |
|-------|-------------|-----------|-------|
| 10 | 3 | 15-20 min | Small batch, easy monitoring |
| 50 | 4 | 1-1.5 hrs | Medium batch, optimal |
| 100 | 5 | 2-3 hrs | Large batch, max efficiency |
| 200+ | 5 | 4-6 hrs | Consider splitting into multiple runs |

**Factors Affecting Time:**
- Repository size (larger repos take longer)
- Network speed
- GitHub API rate limits
- Azure DevOps throttling

### Scaling Beyond 200 Repos

For very large migrations (500+ repos), consider:

1. **Split CSV into multiple files:**
   ```
   repos-batch-1.csv (1-100)
   repos-batch-2.csv (101-200)
   repos-batch-3.csv (201-300)
   ```

2. **Run multiple workflow executions:**
   - Queue multiple workflows with different CSV files
   - Workflows run independently

3. **Alternative: Matrix Strategy** (see [ADVANCED.md](ADVANCED.md) for implementation)

## 🛡️ Security Best Practices

### PAT Management

- ✅ Use fine-grained PATs with minimum required scopes
- ✅ Set expiration dates (90 days recommended)
- ✅ Rotate PATs regularly
- ✅ Never commit PATs to repository
- ✅ Use separate PATs for different environments

### Secrets Rotation

To rotate secrets:

1. Generate new PAT
2. Update secret in repository settings
3. Delete old PAT from GitHub/ADO

### Access Control

- Limit who can trigger workflows (use environment protection rules)
- Review workflow runs regularly
- Monitor for unauthorized access attempts

## 📚 Additional Resources

### Official Documentation

- [gh ado2gh CLI Documentation](https://github.com/github/gh-ado2gh)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Azure DevOps Migration Guide](https://docs.github.com/en/migrations)

### Related Tools

- [gh-gei](https://github.com/github/gh-gei) - GitHub Enterprise Importer
- [Azure DevOps CLI](https://docs.microsoft.com/en-us/cli/azure/devops)

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Submit a pull request with detailed description

## 📄 License

This project is licensed under the MIT License - see LICENSE file for details.

## 💬 Support

For issues, questions, or feature requests:

- Open an issue in this repository
- Contact: [Your Contact Info]
- Documentation: [Link to wiki/docs]

---

**Happy Migrating! 🚀**




