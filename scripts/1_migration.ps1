#!/usr/bin/env bash
# ADO -> GitHub parallel migration runner (GitHub Actions optimized) - Bash version
# - Configurable via parameters for GitHub Actions workflow
# - Keeps your status bar and CSV writes
# - Ensures background job emits only the final result object (no log noise on the output stream)
# - Robust result parsing so $failed increments correctly
# - Mirrors functionality of the original PowerShell script

set -euo pipefail

# -------------------- Arg parsing --------------------
MAX_CONCURRENT=3
CSV_PATH="repos.csv"
OUTPUT_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -MaxConcurrent)
      MAX_CONCURRENT="$2"; shift 2;;
    -CsvPath)
      CSV_PATH="$2"; shift 2;;
    -OutputPath)
      OUTPUT_PATH="$2"; shift 2;;
    *)
      echo "[ERROR] Unknown parameter: $1" >&2
      exit 1;;
  esac
done

# -------------------- Settings --------------------
# Validate max concurrent limit
if ! [[ "$MAX_CONCURRENT" =~ ^[0-9]+$ ]]; then
  echo "[ERROR] MaxConcurrent must be numeric." >&2
  exit 1
fi
if (( MAX_CONCURRENT > 5 )); then
  echo "[ERROR] Maximum concurrent migrations ($MAX_CONCURRENT) exceeds the allowed limit of 5." >&2
  echo "[ERROR] Please set MaxConcurrent to 5 or less." >&2
  exit 1
fi
if (( MAX_CONCURRENT < 1 )); then
  echo "[ERROR] MaxConcurrent must be at least 1." >&2
  exit 1
fi

timestamp="$(date +'%Y%m%d-%H%M%S')"
if [[ -z "$OUTPUT_PATH" ]]; then
  outputCsvPath="repo_migration_output-${timestamp}.csv"
else
  outputCsvPath="$OUTPUT_PATH"
fi

if [[ ! -f "$CSV_PATH" ]]; then
  echo "[ERROR] CSV file not found at path: $CSV_PATH" >&2
  exit 1
fi

# Read header and repos
HEADER="$(head -n1 "$CSV_PATH")"
mapfile -t REPO_LINES < <(tail -n +2 "$CSV_PATH")

if (( ${#REPO_LINES[@]} == 0 )); then
  echo "[ERROR] CSV file is empty: $CSV_PATH" >&2
  exit 1
fi

# Validate required columns
requiredColumns=("org" "teamproject" "repo" "github_org" "github_repo" "gh_repo_visibility")
function has_col() {
  local col="$1"
  [[ ",$HEADER," == *",$col,"* ]]
}
missing=()
for c in "${requiredColumns[@]}"; do
  if ! has_col "$c"; then
    missing+=("$c")
  fi
done
if (( ${#missing[@]} > 0 )); then
  echo "[ERROR] CSV is missing required columns: ${missing[*]}" >&2
  echo "[ERROR] Required columns: ${requiredColumns[*]}" >&2
  exit 1
fi

# Determine column positions
IFS=',' read -r -a header_cols <<< "$HEADER"
declare -A COLPOS
for i in "${!header_cols[@]}"; do COLPOS["${header_cols[$i]}"]="$i"; done

# Storage
declare -A statuses
declare -A logfiles

# Initialize statuses/logfiles
for i in "${!REPO_LINES[@]}"; do
  statuses["$i"]="Pending"
  logfiles["$i"]=""
done

# Write migration status CSV
function write_migration_status_csv() {
  {
    echo "${HEADER},Migration_Status,Log_File"
    for i in "${!REPO_LINES[@]}"; do
      echo "${REPO_LINES[$i]},${statuses[$i]},${logfiles[$i]}"
    done
  } > "$outputCsvPath"
}

write_migration_status_csv
echo "[INFO] Starting migration with $MAX_CONCURRENT concurrent jobs..."
echo "[INFO] Processing ${#REPO_LINES[@]} repositories from: $CSV_PATH"
echo "[INFO] Initialized migration status output: $outputCsvPath"

# -------------------- MAIN: parallel migration with concurrent jobs --------------------
# Queue holds indices
queue=()
for i in "${!REPO_LINES[@]}"; do queue+=("$i"); done
inProgress=()  # list of PIDs
declare -A idxForPid    # pid -> repo index
declare -A lastSizeForPid  # pid -> last printed byte size
migrated=()
failed=()

StatusLineWidth=0

function show_status_bar() {
  local queueCount="${#queue[@]}"
  local progressCount="${#inProgress[@]}"
  local migratedCount="${#migrated[@]}"
  local failedCount="${#failed[@]}"
  local statusLine="QUEUE: ${queueCount} | IN PROGRESS: ${progressCount} | MIGRATED: ${migratedCount} | MIGRATION FAILED: ${failedCount}"
  local len="${#statusLine}"
  if (( len > StatusLineWidth )); then
    StatusLineWidth="$len"
  fi
  printf "\r%-${StatusLineWidth}s" "$statusLine"
}

mkdir -p job_results

function parse_field() {
  # naive CSV split by comma (assumes fields don't contain commas)
  local line="$1" pos="$2"
  IFS=',' read -r -a cols <<< "$line"
  echo "${cols[$pos]}"
}

function start_job_for_repo() {
  local idx="$1"
  local line="${REPO_LINES[$idx]}"

  local adoOrg="$(parse_field "$line" "${COLPOS[org]}")"
  local adoTeamProject="$(parse_field "$line" "${COLPOS[teamproject]}")"
  local adoRepo="$(parse_field "$line" "${COLPOS[repo]}")"
  local githubOrg="$(parse_field "$line" "${COLPOS[github_org]}")"
  local githubRepo="$(parse_field "$line" "${COLPOS[github_repo]}")"
  local gh_repo_visibility="$(parse_field "$line" "${COLPOS[gh_repo_visibility]}")"

  local logFile="migration-${githubRepo}-$(date +'%Y%m%d-%H%M%S').txt"
  logfiles["$idx"]="$logFile"
  write_migration_status_csv

  local resultFile="job_results/job_${idx}.result"

  # Background job - writes only to logFile and resultFile
  (
    {
      printf "[%s] [START] Migration: %s/%s -> %s/%s (gh_repo_visibility: %s)\n" "$(date)" "$adoTeamProject" "$adoRepo" "$githubOrg" "$githubRepo" "$gh_repo_visibility"
      printf "[%s] [DEBUG] Running: gh ado2gh migrate-repo --ado-org %s --ado-team-project %s --ado-repo %s --github-org %s --github-repo %s --target-repo-visibility %s\n" "$(date)" "$adoOrg" "$adoTeamProject" "$adoRepo" "$githubOrg" "$githubRepo" "$gh_repo_visibility"
    } >> "$logFile"

    # Execute migration command (append all output to log)
    set +e
    gh ado2gh migrate-repo \
      --ado-org "$adoOrg" \
      --ado-team-project "$adoTeamProject" \
      --ado-repo "$adoRepo" \
      --github-org "$githubOrg" \
      --github-repo "$githubRepo" \
      --target-repo-visibility "$gh_repo_visibility" >> "$logFile" 2>&1
    migrateExit=$?
    set -e

    # Evaluate success based on log content and exit code
    success="false"
    if grep -q "No operation will be performed" "$logFile"; then
      success="false"
    elif ! grep -q "State: SUCCEEDED" "$logFile"; then
      success="false"
    elif [[ "$migrateExit" -eq 0 ]]; then
      success="true"
    else
      success="false"
    fi

    if [[ "$success" == "true" ]]; then
      printf "[%s] [SUCCESS] Migration: %s/%s -> %s/%s\n" "$(date)" "$adoTeamProject" "$adoRepo" "$githubOrg" "$githubRepo" >> "$logFile"
      echo "true" > "$resultFile"
    else
      printf "[%s] [FAILED] Migration: %s/%s -> %s/%s\n" "$(date)" "$adoTeamProject" "$adoRepo" "$githubOrg" "$githubRepo" >> "$logFile"
      echo "false" > "$resultFile"
    fi
  ) &

  local pid=$!
  inProgress+=("$pid")
  idxForPid["$pid"]="$idx"
  lastSizeForPid["$pid"]=0
}

# Main loop
while (( ${#queue[@]} > 0 || ${#inProgress[@]} > 0 )); do
  # Start new jobs if below max concurrent
  while (( ${#inProgress[@]} < MAX_CONCURRENT && ${#queue[@]} > 0 )); do
    next="${queue[0]}"
    queue=("${queue[@]:1}")
    start_job_for_repo "$next"
    show_status_bar
  done

  # Stream new output from each job's log file to the console
  for pid in "${inProgress[@]}"; do
    idx="${idxForPid[$pid]}"
    logfile="${logfiles[$idx]}"
    if [[ -f "$logfile" ]]; then
      size=$(wc -c < "$logfile")
      last="${lastSizeForPid[$pid]}"
      if (( size > last )); then
        delta=$(tail -c +"$((last + 1))" "$logfile")
        lastSizeForPid["$pid"]="$size"
        if [[ -n "$delta" ]]; then
          echo ""
          # Print delta trimmed of trailing newlines for tidier status bar
          printf "%s" "$delta" | sed -e ':a;N;$!ba;s/\r\{0,1}\n\{1,}$//'
          show_status_bar
        fi
      fi
    fi
  done

  # Check completed jobs
  stillRunning=()
  for pid in "${inProgress[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      stillRunning+=("$pid")
    else
      idx="${idxForPid[$pid]}"
      resultFile="job_results/job_${idx}.result"
      result="false"
      if [[ -f "$resultFile" ]]; then
        result="$(cat "$resultFile" | tr -d '\r\n' )"
      fi
      if [[ "$result" == "true" ]]; then
        migrated+=("$idx")
        statuses["$idx"]="Success"
      else
        failed+=("$idx")
        statuses["$idx"]="Failure"
      fi
      write_migration_status_csv
      show_status_bar
    fi
  done
  inProgress=("${stillRunning[@]}")

  sleep 5
done

echo -e "\n[INFO] All migrations completed."
echo "[SUMMARY] Total: ${#REPO_LINES[@]} | Migrated: ${#migrated[@]} | Failed: ${#failed[@]}"
write_migration_status_csv
echo "[INFO] Wrote migration results with Migration_Status column: $outputCsvPath"

# Exit with error code if there were failures (for GitHub Actions)
if (( ${#failed[@]} > 0 )); then
  echo "[WARNING] Migration completed with ${#failed[@]} failures"
  # Don't exit with error - let workflow handle it
