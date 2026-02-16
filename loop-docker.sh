#!/bin/bash
# Ralph Docker Loop
# Runs Claude in isolated container, backup/git runs on HOST
# Resilient: timeout per iteration, stuck detection, continues on failure

# NOTE: Do NOT use set -e — we handle errors per-iteration to keep the loop alive

# Configuration
IMAGE_NAME="ralph-loop"
PROJECT_DIR="$(pwd)"
PROJECT_NAME=$(basename "$PROJECT_DIR")
BACKUP_ENABLED="${RALPH_BACKUP:-true}"
MODEL="${RALPH_MODEL:-opus}"
ITERATION_TIMEOUT="${RALPH_TIMEOUT:-15m}"  # Max time per iteration (default 15 minutes)
MAX_STUCK="${RALPH_MAX_STUCK:-3}"          # Max failures on same task before skipping

# Validate model against whitelist (security: prevents command injection)
validate_model() {
  local model="$1"
  case "$model" in
    opus|sonnet|haiku) return 0 ;;
    *)
      echo "Error: Invalid model '$model'. Allowed: opus, sonnet, haiku"
      exit 1
      ;;
  esac
}
validate_model "$MODEL"
PLAN_FILE="IMPLEMENTATION_PLAN.md"
REPORT_FILE="REPORT.md"
LOG_FILE="ralph.log"
START_TIME=$(date +%s)

# SAFETY: Verify PROJECT_DIR is safe to mount
if [ -z "$PROJECT_DIR" ] || [ "$PROJECT_DIR" = "/" ] || [ "$PROJECT_DIR" = "$HOME" ]; then
  echo "FATAL: Refusing to mount unsafe directory: $PROJECT_DIR"
  echo "Run this script from inside a project directory, not ~ or /"
  exit 1
fi

# Verify we're in a Ralph project
if [ ! -f "PROMPT_build.md" ] && [ ! -f "PROMPT_plan.md" ]; then
  echo "FATAL: Not a Ralph project directory (no PROMPT_*.md files)"
  echo "Run /setup-ralph first or cd into a Ralph project"
  exit 1
fi

# Load OAuth token (with security checks)
TOKEN_FILE="$HOME/.claude-oauth-token"
if [ -z "$CLAUDE_CODE_OAUTH_TOKEN" ]; then
  if [ -f "$TOKEN_FILE" ]; then
    # Security: Check file permissions (should be 600 or more restrictive)
    if [[ "$OSTYPE" == "darwin"* ]]; then
      TOKEN_PERMS=$(stat -f %Lp "$TOKEN_FILE" 2>/dev/null)
    else
      TOKEN_PERMS=$(stat -c %a "$TOKEN_FILE" 2>/dev/null)
    fi

    if [ -n "$TOKEN_PERMS" ] && [ "$((TOKEN_PERMS % 100))" -ne 0 ]; then
      echo "Warning: $TOKEN_FILE has insecure permissions ($TOKEN_PERMS)"
      echo "   Run: chmod 600 $TOKEN_FILE"
      echo ""
    fi

    CLAUDE_CODE_OAUTH_TOKEN=$(cat "$TOKEN_FILE")
  else
    echo "Error: No OAuth token found"
    echo "Run 'claude setup-token' and save to ~/.claude-oauth-token"
    echo "Then: chmod 600 ~/.claude-oauth-token"
    exit 1
  fi
fi

# Handle --build-image flag
if [ "$1" = "--build-image" ]; then
  echo "Building Docker image..."
  docker build -t "$IMAGE_NAME" .
  echo "Image built: $IMAGE_NAME"
  exit 0
fi

# Check if image exists
if ! docker image inspect "$IMAGE_NAME" &>/dev/null; then
  echo "Docker image not found. Building..."
  docker build -t "$IMAGE_NAME" .
fi

# Parse arguments
MODE="build"
LIMIT=""
while [[ $# -gt 0 ]]; do
  case $1 in
    plan) MODE="plan"; shift ;;
    [0-9]*) LIMIT=$1; shift ;;
    --model) MODEL=$2; validate_model "$MODEL"; shift 2 ;;
    --timeout) ITERATION_TIMEOUT=$2; shift 2 ;;
    *)
      echo "Usage: $0 [plan] [limit] [--model opus|sonnet|haiku] [--timeout 15m]"
      echo ""
      echo "Examples:"
      echo "  $0              # Build mode, unlimited"
      echo "  $0 20           # Build mode, max 20 iterations"
      echo "  $0 plan         # Plan mode, 1 iteration"
      echo "  $0 --timeout 20m  # 20 min timeout per iteration"
      echo ""
      echo "Environment variables:"
      echo "  RALPH_MODEL=opus|sonnet|haiku  Default model"
      echo "  RALPH_TIMEOUT=15m              Timeout per iteration"
      echo "  RALPH_MAX_STUCK=3              Max failures before skipping task"
      echo "  RALPH_BACKUP=true|false        Push to remote after each iteration"
      exit 1
      ;;
  esac
done

# Plan mode: more time (planning reads a lot), defaults to 1 iteration
if [ "$MODE" = "plan" ]; then
  [ -z "$LIMIT" ] && LIMIT=1
  # Planning needs more time to read the full codebase
  [ "$ITERATION_TIMEOUT" = "15m" ] && ITERATION_TIMEOUT="30m"
fi

# ============================================================================
# REMOTE BACKUP (runs on HOST with your gh auth)
# ============================================================================

setup_remote_backup() {
  if [ "$BACKUP_ENABLED" != "true" ]; then
    echo "Remote backup: disabled (set RALPH_BACKUP=true to enable)"
    return 0
  fi

  if [ ! -d ".git" ]; then
    echo "Initializing git..."
    git init
    git add -A
    git commit -m "Initial commit" 2>/dev/null || true
  fi

  if git remote get-url origin &>/dev/null; then
    echo "Remote backup: $(git remote get-url origin)"
    return 0
  fi

  if ! command -v gh &>/dev/null; then
    echo "Warning: gh CLI not found. Backup disabled."
    BACKUP_ENABLED="false"
    return 1
  fi

  if ! gh auth status &>/dev/null; then
    echo "Warning: gh not authenticated. Backup disabled."
    BACKUP_ENABLED="false"
    return 1
  fi

  local repo_name="${PROJECT_NAME}-ralph-backup"
  echo "Creating private backup: $repo_name"

  if gh repo create "$repo_name" --private --source=. --push 2>/dev/null; then
    echo "Remote backup: https://github.com/$(gh api user -q .login)/$repo_name"
  else
    echo "Warning: Could not create repo. Backup disabled."
    BACKUP_ENABLED="false"
  fi
}

push_to_backup() {
  if [ "$BACKUP_ENABLED" = "true" ]; then
    git add -A 2>/dev/null || true
    git diff --quiet HEAD 2>/dev/null || git commit -m "Auto-save after iteration $ITERATION" 2>/dev/null || true
    git push origin HEAD 2>/dev/null && echo "Pushed to backup" || echo "Push failed (continuing)"
  fi
}

# ============================================================================
# COMPLETION DETECTION (runs on HOST)
# ============================================================================

check_complete() {
  if [ ! -f "$PLAN_FILE" ]; then
    return 1
  fi

  local incomplete=$(grep -c '^\s*- \[ \]' "$PLAN_FILE" 2>/dev/null || echo "0")
  if [ "$incomplete" -eq 0 ]; then
    local completed=$(grep -c '^\s*- \[x\]' "$PLAN_FILE" 2>/dev/null || echo "0")
    [ "$completed" -gt 0 ] && return 0
  fi
  return 1
}

get_current_task() {
  if [ ! -f "$PLAN_FILE" ]; then
    echo ""
    return
  fi
  grep '^\s*- \[ \]' "$PLAN_FILE" 2>/dev/null | head -1 | sed 's/.*- \[ \] //' | cut -c1-80 || echo ""
}

# ============================================================================
# STUCK DETECTION (runs on HOST)
# ============================================================================

STUCK_FILE=".ralph_stuck_tracker"
LAST_TASK=""
STUCK_COUNT=0
CONSECUTIVE_ERRORS=0
MAX_CONSECUTIVE_ERRORS=5  # Stop loop after 5 consecutive errors (not task-related)

init_stuck_tracker() {
  if [ -f "$STUCK_FILE" ]; then
    LAST_TASK=$(grep "^LAST_TASK=" "$STUCK_FILE" 2>/dev/null | cut -d'"' -f2 || echo "")
    STUCK_COUNT=$(grep "^STUCK_COUNT=" "$STUCK_FILE" 2>/dev/null | cut -d= -f2 || echo "0")
    [[ "$STUCK_COUNT" =~ ^[0-9]+$ ]] || STUCK_COUNT=0
  fi
}

update_stuck_tracker() {
  local current_task="$1"
  if [ "$current_task" = "$LAST_TASK" ] && [ -n "$current_task" ]; then
    STUCK_COUNT=$((STUCK_COUNT + 1))
  else
    LAST_TASK="$current_task"
    STUCK_COUNT=1
  fi
  echo "LAST_TASK=\"$LAST_TASK\"" > "$STUCK_FILE"
  echo "STUCK_COUNT=$STUCK_COUNT" >> "$STUCK_FILE"
}

is_stuck() {
  [ "$STUCK_COUNT" -ge "$MAX_STUCK" ]
}

# Cross-platform sed -i wrapper
sed_i() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

skip_stuck_task() {
  local task="$1"
  echo ""
  echo "STUCK: Failed $MAX_STUCK times on: $task"
  echo "Marking as blocked and moving on..."

  if ! grep -q "^## Blocked" "$PLAN_FILE" 2>/dev/null; then
    echo "" >> "$PLAN_FILE"
    echo "## Blocked" >> "$PLAN_FILE"
    echo "" >> "$PLAN_FILE"
  fi
  echo "- $task (stuck after $MAX_STUCK attempts)" >> "$PLAN_FILE"

  local escaped_task
  escaped_task=$(printf '%s\n' "$task" | sed 's/[[\.*^$()+?{|/]/\\&/g')
  sed_i "s/- \[ \] ${escaped_task}/- [S] $task/" "$PLAN_FILE"

  LAST_TASK=""
  STUCK_COUNT=0
  echo "LAST_TASK=\"\"" > "$STUCK_FILE"
  echo "STUCK_COUNT=0" >> "$STUCK_FILE"
}

# ============================================================================
# ITERATION SUMMARY & REPORT (runs on HOST)
# ============================================================================

print_iteration_summary() {
  local iteration_start="$1"
  local exit_status="$2"
  local iteration_end=$(date +%s)
  local duration=$((iteration_end - iteration_start))
  local mins=$((duration / 60))
  local secs=$((duration % 60))

  local completed=$(grep -c '^\s*- \[x\]' "$PLAN_FILE" 2>/dev/null || echo "0")
  local total_tasks=$(grep -c '^\s*- \[' "$PLAN_FILE" 2>/dev/null || echo "0")
  local pct=0
  [ "$total_tasks" -gt 0 ] && pct=$((completed * 100 / total_tasks))

  echo ""
  echo "--- Iteration $ITERATION (${mins}m ${secs}s) ---"

  if [ "$exit_status" = "timeout" ]; then
    echo "Result: TIMEOUT (exceeded $ITERATION_TIMEOUT)"
  elif [ "$exit_status" = "error" ]; then
    echo "Result: ERROR"
  else
    echo "Result: OK"
  fi

  echo "Progress: $completed/$total_tasks tasks ($pct%)"
  echo "-------------------------------------------"
}

generate_report() {
  local end_time=$(date +%s)
  local duration=$((end_time - START_TIME))
  local minutes=$((duration / 60))
  local seconds=$((duration % 60))

  local completed=$(grep -c '^\s*- \[x\]' "$PLAN_FILE" 2>/dev/null || echo "0")
  local skipped=$(grep -c '^\s*- \[S\]' "$PLAN_FILE" 2>/dev/null || echo "0")
  local remaining=$(grep -c '^\s*- \[ \]' "$PLAN_FILE" 2>/dev/null || echo "0")
  local total=$((completed + skipped + remaining))

  cat > "$REPORT_FILE" << EOF
# Ralph Session Report

Generated: $(date '+%Y-%m-%d %H:%M:%S')

## Summary

| Metric | Value |
|--------|-------|
| Duration | ${minutes}m ${seconds}s |
| Iterations | $ITERATION |
| Tasks Completed | $completed / $total |
| Tasks Skipped | $skipped |
| Tasks Remaining | $remaining |

## Exit Reason: $1

## Completed Tasks
$(grep '^\s*- \[x\]' "$PLAN_FILE" 2>/dev/null || echo "None")

EOF

  if [ "$skipped" -gt 0 ]; then
    echo "## Skipped Tasks (stuck)" >> "$REPORT_FILE"
    grep '^\s*- \[S\]' "$PLAN_FILE" 2>/dev/null >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
  fi

  echo "Report saved to $REPORT_FILE"
}

# ============================================================================
# MAIN
# ============================================================================

# Select prompt
if [ "$MODE" = "plan" ]; then
  PROMPT_FILE="PROMPT_plan.md"
  echo "Ralph Planning Mode (Docker)"
else
  PROMPT_FILE="PROMPT_build.md"
  echo "Ralph Building Mode (Docker)"

  if [ ! -f "$PLAN_FILE" ]; then
    echo ""
    echo "Error: $PLAN_FILE not found"
    echo "Run './loop-docker.sh plan' first to generate the implementation plan."
    exit 1
  fi

  init_stuck_tracker
fi

if [ ! -f "$PROMPT_FILE" ]; then
  echo "Error: $PROMPT_FILE not found"
  exit 1
fi

# Verify timeout command exists
if ! command -v timeout &>/dev/null && ! command -v gtimeout &>/dev/null; then
  echo "Warning: 'timeout' command not found."
  echo "  macOS: brew install coreutils"
  echo "  Continuing without timeout protection."
  TIMEOUT_CMD=""
elif command -v gtimeout &>/dev/null; then
  TIMEOUT_CMD="gtimeout"  # macOS with coreutils
else
  TIMEOUT_CMD="timeout"   # Linux
fi

# Display configuration
echo "Project: $PROJECT_DIR"
echo "Model: $MODEL"
echo "Timeout: $ITERATION_TIMEOUT per iteration"
echo "Stuck threshold: $MAX_STUCK failures"
[ -n "$LIMIT" ] && echo "Limit: $LIMIT iterations" || echo "Limit: until complete (Ctrl+C to stop)"
echo ""

setup_remote_backup
echo ""
echo "Starting loop..."
echo "---"

echo "=== Ralph Docker $(date '+%Y-%m-%d %H:%M:%S') ===" > "$LOG_FILE"
echo "Mode: $MODE | Model: $MODEL | Timeout: $ITERATION_TIMEOUT" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

# Cleanup on interrupt
cleanup() {
  echo ""
  echo "============================================"
  if [ "$MODE" = "build" ]; then
    generate_report "${1:-interrupted}"
  fi
  rm -f "$STUCK_FILE"
  echo "============================================"
}
trap 'cleanup "interrupted"; exit 130' INT

ITERATION=0
while true; do
  ITERATION=$((ITERATION + 1))
  ITERATION_START=$(date +%s)

  echo ""
  echo "Iteration $ITERATION - $(date '+%H:%M:%S')"

  # Check completion (build mode only)
  if [ "$MODE" = "build" ]; then
    if check_complete; then
      echo "ALL TASKS COMPLETE"
      push_to_backup
      cleanup "complete"
      exit 0
    fi

    # Stuck detection
    current_task=$(get_current_task)
    update_stuck_tracker "$current_task"

    if is_stuck; then
      skip_stuck_task "$current_task"
      push_to_backup
      continue
    fi

    echo "Task: $current_task"
  fi

  # Check iteration limit
  if [ -n "$LIMIT" ] && [ "$ITERATION" -gt "$LIMIT" ]; then
    echo "Reached limit ($LIMIT)"
    push_to_backup
    if [ "$MODE" = "build" ]; then
      cleanup "limit"
    fi
    exit 0
  fi

  # Check consecutive error limit
  if [ "$CONSECUTIVE_ERRORS" -ge "$MAX_CONSECUTIVE_ERRORS" ]; then
    echo ""
    echo "FATAL: $MAX_CONSECUTIVE_ERRORS consecutive errors. Stopping loop."
    echo "Check ralph.log for details."
    push_to_backup
    cleanup "consecutive_errors"
    exit 1
  fi

  # Build docker run command with optional timeout
  DOCKER_CMD=(docker run --rm
    -v "$PROJECT_DIR:/workspace"
    -w /workspace
    -e "CLAUDE_CODE_OAUTH_TOKEN=$CLAUDE_CODE_OAUTH_TOKEN"
    "$IMAGE_NAME"
    bash -c "cat '$PROMPT_FILE' | claude --model '$MODEL' -p --dangerously-skip-permissions --output-format text"
  )

  # Run iteration: with timeout if available, resilient to failures
  EXIT_STATUS="ok"

  if [ -n "$TIMEOUT_CMD" ]; then
    # --kill-after=30s: escalate to SIGKILL if SIGTERM is ignored
    # PIPESTATUS[0]: capture gtimeout's exit code, not tee's
    $TIMEOUT_CMD --kill-after=30s "$ITERATION_TIMEOUT" "${DOCKER_CMD[@]}" 2>&1 | tee -a "$LOG_FILE"
    EXIT_CODE=${PIPESTATUS[0]}

    if [ "$EXIT_CODE" -eq 0 ]; then
      CONSECUTIVE_ERRORS=0
    elif [ "$EXIT_CODE" -eq 124 ] || [ "$EXIT_CODE" -eq 137 ]; then
      EXIT_STATUS="timeout"
      echo ""
      echo "TIMEOUT: Iteration $ITERATION exceeded $ITERATION_TIMEOUT"
      echo "Killing orphan containers and moving to next iteration..."
      docker ps -q --filter "ancestor=$IMAGE_NAME" | xargs docker kill 2>/dev/null || true
      CONSECUTIVE_ERRORS=$((CONSECUTIVE_ERRORS + 1))
    else
      EXIT_STATUS="error"
      echo ""
      echo "ERROR: Iteration $ITERATION failed (exit code $EXIT_CODE)"
      CONSECUTIVE_ERRORS=$((CONSECUTIVE_ERRORS + 1))
    fi
  else
    # No timeout available — run without protection
    "${DOCKER_CMD[@]}" 2>&1 | tee -a "$LOG_FILE"
    EXIT_CODE=${PIPESTATUS[0]}

    if [ "$EXIT_CODE" -eq 0 ]; then
      CONSECUTIVE_ERRORS=0
    else
      EXIT_STATUS="error"
      echo "ERROR: Iteration $ITERATION failed (exit code $EXIT_CODE)"
      CONSECUTIVE_ERRORS=$((CONSECUTIVE_ERRORS + 1))
    fi
  fi

  # Log iteration result
  echo "" >> "$LOG_FILE"
  echo "=== Iteration $ITERATION finished: $EXIT_STATUS $(date '+%H:%M:%S') ===" >> "$LOG_FILE"
  echo "" >> "$LOG_FILE"

  # Print summary and backup (build mode)
  if [ "$MODE" = "build" ]; then
    print_iteration_summary "$ITERATION_START" "$EXIT_STATUS"
    push_to_backup
  else
    echo "Iteration $ITERATION complete ($EXIT_STATUS)"
  fi

  sleep 2
done
