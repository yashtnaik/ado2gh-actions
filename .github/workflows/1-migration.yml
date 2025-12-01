name: 1-migration

on:
  workflow_dispatch:
    inputs:
      max_concurrent:
        description: 'Maximum concurrent migrations (1-5)'
        required: false
        default: '3'
        type: choice
        options:
          - '1'
          - '2'
          - '3'
          - '4'
          - '5'
      csv_path:
        description: 'Path to repos CSV file'
        required: false
        default: 'repos.csv'
      trigger_validation:
        description: 'Automatically trigger validation after migration'
        required: false
        default: false
        type: boolean
  workflow_call:
    inputs:
      max_concurrent:
        description: 'Maximum concurrent migrations (1-5)'
        required: false
        default: '3'
        type: string
      csv_path:
        description: 'Path to repos CSV file'
        required: false
        default: 'repos.csv'
        type: string
      trigger_validation:
        description: 'Automatically trigger validation after migration'
        required: false
        default: false
        type: boolean
      
jobs:
  migrate-repositories:
    runs-on: windows-latest
    timeout-minutes: 360  # 6 hours (GitHub Free/Pro/Team limit)
    # Note: GitHub Enterprise supports up to 24 hours (1,440 minutes)
    # Adjust based on your GitHub plan
    environment: PAT tokens
    
    steps:
      - name: Checkout Repository
        uses: actions/checkout@v4
      
      - name: Setup GitHub CLI
        run: |
          Write-Host "GitHub CLI Version:" -ForegroundColor Cyan
          gh --version
          
          Write-Host "`nAuthentication Status:" -ForegroundColor Cyan
          gh auth status
        env:
          GH_TOKEN: ${{ secrets.GH_PAT }}
      
      - name: Install ADO2GH Extension
        run: |
          Write-Host "Installing gh-ado2gh extension..." -ForegroundColor Cyan
          gh extension install github/gh-ado2gh
          
          Write-Host "`nVerifying installation:" -ForegroundColor Cyan
          gh ado2gh --version
        env:
          GH_TOKEN: ${{ secrets.GH_PAT }}
      
      - name: Validate CSV File
        shell: pwsh
        run: |
          $csvPath = "${{ inputs.csv_path }}"
          
          if (-not (Test-Path $csvPath)) {
            Write-Host "[ERROR] CSV file not found: $csvPath" -ForegroundColor Red
            exit 1
          }
          
          $repos = Import-Csv -Path $csvPath
          Write-Host "[INFO] Found $($repos.Count) repositories to migrate" -ForegroundColor Green
          
          # Validate required columns
          $requiredColumns = @('org', 'teamproject', 'repo', 'github_org', 'github_repo', 'gh_repo_visibility')
          $missingColumns = $requiredColumns | Where-Object { $_ -notin $repos[0].PSObject.Properties.Name }
          
          if ($missingColumns) {
            Write-Host "[ERROR] Missing required columns: $($missingColumns -join ', ')" -ForegroundColor Red
            exit 1
          }
          
          Write-Host "[SUCCESS] CSV validation passed" -ForegroundColor Green
      
      - name: Run Concurrent Migration
        shell: pwsh
        env:
          GH_PAT: ${{ secrets.GH_PAT }}
          ADO_PAT: ${{ secrets.ADO_PAT }}
          GH_TOKEN: ${{ secrets.GH_PAT }}
        run: |
          # Execute migration script with parameters
          .\scripts\1_migration.ps1 `
            -MaxConcurrent ${{ inputs.max_concurrent }} `
            -CsvPath "${{ inputs.csv_path }}"
      
      - name: Generate Workflow Summary
        if: always()
        shell: pwsh
        run: |
          # Find the most recent output CSV
          $outputCsv = Get-ChildItem -Filter "repo_migration_output-*.csv" | 
                       Sort-Object LastWriteTime -Descending | 
                       Select-Object -First 1
          
          if ($outputCsv) {
            $results = Import-Csv -Path $outputCsv.FullName
            
            $total = $results.Count
            $success = ($results | Where-Object { $_.Migration_Status -eq 'Success' }).Count
            $failed = ($results | Where-Object { $_.Migration_Status -eq 'Failure' }).Count
            $pending = ($results | Where-Object { $_.Migration_Status -eq 'Pending' }).Count
            
            $successRate = if ($total -gt 0) { [math]::Round(($success / $total) * 100, 2) } else { 0 }
            
            # Create summary markdown
            $summary = @"
          # 🚀 Migration Execution Summary
          
          ## 📊 Overall Statistics
          - **Total Repositories**: $total
          - **Successfully Migrated**: ✅ $success
          - **Failed Migrations**: ❌ $failed
          - **Pending/Not Started**: ⏳ $pending
          - **Success Rate**: $successRate%
          - **Concurrent Jobs**: ${{ inputs.max_concurrent }}
          
          ## 📁 Artifacts
          - All migration logs available in artifacts section below
          - Output CSV: ``$($outputCsv.Name)``
          
          "@ 
            
            # Add failed migrations table if any
            if ($failed -gt 0) {
              $summary += "`n## ❌ Failed Migrations`n`n"
              $summary += "| Repository | ADO Org | ADO Team Project | GitHub Org | Log File |`n"
              $summary += "|------------|---------|------------------|------------|----------|`n"
              
              $failedRepos = $results | Where-Object { $_.Migration_Status -eq 'Failure' }
              foreach ($repo in $failedRepos) {
                $summary += "| $($repo.repo) | $($repo.org) | $($repo.teamproject) | $($repo.github_org) | $($repo.Log_File) |`n"
              }
            }
            
            # Add successful migrations summary
            if ($success -gt 0) {
              $summary += "`n## ✅ Successfully Migrated Repositories`n`n"
              $successRepos = $results | Where-Object { $_.Migration_Status -eq 'Success' }
              $summary += "Total: $success repositories migrated successfully`n`n"
              
              # Show first 10 successful migrations
              $showCount = [Math]::Min(10, $success)
              $summary += "| Repository | GitHub URL |`n"
              $summary += "|------------|------------|`n"
              
              $successRepos | Select-Object -First $showCount | ForEach-Object {
                $githubUrl = "https://github.com/$($_.github_org)/$($_.github_repo)"
                $summary += "| $($_.repo) | $githubUrl |`n"
              }
              
              if ($success -gt 10) {
                $summary += "`n*... and $($success - 10) more*`n"
              }
            }
            
            # Write to GitHub Actions summary
            $summary | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Encoding utf8
            
            Write-Host $summary
          } else {
            Write-Host "[WARNING] No output CSV found" -ForegroundColor Yellow
          }
      
      - name: Upload Migration Logs
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: migration-logs-${{ github.run_id }}
          path: migration-*.txt
          retention-days: 90
          if-no-files-found: warn
      
      - name: Upload Output CSV
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: migration-output-csv-${{ github.run_id }}
          path: repo_migration_output-*.csv
          retention-days: 90
          if-no-files-found: error
      
      - name: Check for Failures
        if: always()
        shell: pwsh
        run: |
          $outputCsv = Get-ChildItem -Filter "repo_migration_output-*.csv" |
                       Sort-Object LastWriteTime -Descending |
                       Select-Object -First 1

          if ($outputCsv) {
            $results = Import-Csv -Path $outputCsv.FullName
            $failed = ($results | Where-Object { $_.Migration_Status -eq 'Failure' }).Count

            if ($failed -gt 0) {
              Write-Host "::warning::$failed repositories failed to migrate. Check the logs for details." -ForegroundColor Yellow
              # Don't fail the workflow, just warn
            } else {
              Write-Host "::notice::All migrations completed successfully!" -ForegroundColor Green
            }
          }
  
  trigger-validation:
    name: Trigger Migration Validation
    needs: migrate-repositories
    if: github.event.inputs.trigger_validation == 'true' || inputs.trigger_validation == true
    runs-on: ubuntu-latest
    
    steps:
      - name: Trigger Validation Workflow
        uses: actions/github-script@v7
        with:
          github-token: ${{ secrets.GH_PAT }}
          script: |
            await github.rest.actions.createWorkflowDispatch({
              owner: context.repo.owner,
              repo: context.repo.repo,
              workflow_id: '2-migration-validation.yml',
              ref: context.ref,
              inputs: {
                csv_path: '${{ inputs.csv_path }}'
              }
            });
            console.log('✅ Migration validation workflow triggered successfully');
