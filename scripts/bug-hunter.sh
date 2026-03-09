#!/bin/bash
#
# 🧛‍♂️ Bug Hunter D33 — The Hunt Begins
#

set -euo pipefail

# Configuration
ARCEE_API_KEY="${ARCEE_API_KEY:-}"
MODEL="${MODEL:-arcee/trinity-mini}"
PASSES="${PASSES:-logic,security}"
SEVERITY_THRESHOLD="${SEVERITY_THRESHOLD:-warning}"
MAX_FILES="${MAX_FILES:-20}"
PR_NUMBER="${PR_NUMBER:-}"
BASE_REF="${BASE_REF:-main}"
HEAD_SHA="${HEAD_SHA:-}"

# Output files
FINDINGS_FILE=".bug-hunter/findings.json"
STATUS_FILE=".bug-hunter/status"

# Colors for logs (only in local mode)
RED='\033[0;31m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
NC='\033[0m'

log() {
  echo "[Bug Hunter D33] $1" >&2
}

# Get changed files
get_changed_files() {
  local files
  if [ -n "$PR_NUMBER" ]; then
    # In PR context
    files=$(git diff --name-only "origin/$BASE_REF...HEAD" -- '*.py' '*.js' '*.ts' '*.jsx' '*.tsx' '*.go' '*.rs' '*.java' '*.rb' '*.php' 2>/dev/null || true)
  else
    # Local mode - check uncommitted changes
    files=$(git diff --name-only HEAD -- '*.py' '*.js' '*.ts' '*.jsx' '*.tsx' '*.go' '*.rs' '*.java' '*.rb' '*.php' 2>/dev/null || true)
  fi
  
  # Limit files if specified
  if [ "$MAX_FILES" -gt 0 ]; then
    echo "$files" | head -n "$MAX_FILES"
  else
    echo "$files"
  fi
}

# Get file diff
get_file_diff() {
  local file="$1"
  if [ -n "$PR_NUMBER" ]; then
    git diff "origin/$BASE_REF...HEAD" -- "$file" 2>/dev/null || cat "$file" 2>/dev/null || echo ""
  else
    git diff HEAD -- "$file" 2>/dev/null || cat "$file" 2>/dev/null || echo ""
  fi
}

# Call Arcee API
hunt_with_arcee() {
  local prompt="$1"
  local diff_content="$2"
  
  # Truncate if too large
  local truncated_diff
  truncated_diff=$(echo "$diff_content" | head -c 15000)
  
  local full_prompt="${prompt}

=== CODE CHANGES ===
${truncated_diff}

=== OUTPUT FORMAT ===
Return ONLY a JSON array of findings. Each finding must have:
- file: string (filename)
- line: number or null
- severity: "critical", "warning", or "note"
- message: string (description of the issue)
- suggestion: string (how to fix it, optional)

Example: [{\"file\":\"main.py\",\"line\":42,\"severity\":\"critical\",\"message\":\"Potential null dereference\",\"suggestion\":\"Add null check before accessing\"}]

If no issues found, return empty array: []"

  local response
  local attempt=0
  local max_attempts=3
  
  while [ $attempt -lt $max_attempts ]; do
    response=$(curl -s -w "\n%{http_code}" \
      -X POST "https://api.arcee.ai/api/v1/chat/completions" \
      -H "Authorization: Bearer $ARCEE_API_KEY" \
      -H "Content-Type: application/json" \
      -d "{
        \"model\": \"$MODEL\",
        \"messages\": [
          {\"role\": \"system\", \"content\": \"You are Bug Hunter D33, a relentless code reviewer who finds bugs that others miss. Be precise. Only report real issues.\"},
          {\"role\": \"user\", \"content\": $(echo "$full_prompt" | jq -Rs .)}
        ],
        \"temperature\": 0.1,
        \"max_tokens\": 4000
      }" 2>/dev/null || echo -e "\n000")
    
    local http_code
    http_code=$(echo "$response" | tail -n1)
    local body
    body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" = "200" ]; then
      # Extract JSON array from response
      local content
      content=$(echo "$body" | jq -r '.choices[0].message.content // empty' 2>/dev/null || echo "")
      
      if [ -n "$content" ]; then
        # Try to parse as JSON array
        if echo "$content" | jq -e 'if type == "array" then . else error("not array") end' >/dev/null 2>&1; then
          echo "$content"
          return 0
        fi
        
        # Try to extract JSON array from markdown
        local extracted
        extracted=$(echo "$content" | grep -oP '\[.*\]' | tail -1)
        if [ -n "$extracted" ] && echo "$extracted" | jq -e '.' >/dev/null 2>&1; then
          echo "$extracted"
          return 0
        fi
      fi
    fi
    
    attempt=$((attempt + 1))
    log "Attempt $attempt failed (HTTP $http_code). Retrying..."
    sleep 2
  done
  
  log "⚠️ Hunt failed after $max_attempts attempts"
  echo "[]"
  return 1
}

# Run a specific pass
run_pass() {
  local pass_name="$1"
  local file="$2"
  local diff_content="$3"
  
  local prompt_file=".bug-hunter/prompts/${pass_name}-hunter.md"
  if [ ! -f "$prompt_file" ]; then
    prompt_file="${ACTION_PATH:-.}/prompts/${pass_name}-hunter.md"
  fi
  
  if [ ! -f "$prompt_file" ]; then
    log "⚠️ Prompt not found: $prompt_file"
    echo "[]"
    return
  fi
  
  local prompt
  prompt=$(cat "$prompt_file")
  
  # Add file context
  prompt="${prompt}

File: $file"
  
  hunt_with_arcee "$prompt" "$diff_content"
}

# Main hunt
main() {
  log "🧛‍♂️ Bug Hunter D33 awakens..."
  log "Model: $MODEL | Passes: $PASSES | Max files: $MAX_FILES"
  
  # Validate API key
  if [ -z "$ARCEE_API_KEY" ]; then
    log "🔴 ARCEE_API_KEY not set. The hunter cannot hunt without tools."
    echo "failure" > "$STATUS_FILE"
    echo "[]" | jq '.' > "$FINDINGS_FILE"
    exit 1
  fi
  
  # Get changed files
  local files
  files=$(get_changed_files)
  
  if [ -z "$files" ]; then
    log "No code files changed. The night is quiet."
    echo "success" > "$STATUS_FILE"
    echo "[]" | jq '.' > "$FINDINGS_FILE"
    
    # Set outputs for GitHub Actions
    echo "status=success" >> "$GITHUB_OUTPUT"
    echo "findings=[]" >> "$GITHUB_OUTPUT"
    echo "critical-count=0" >> "$GITHUB_OUTPUT"
    echo "warning-count=0" >> "$GITHUB_OUTPUT"
    exit 0
  fi
  
  log "Tracking $(echo "$files" | wc -l) files..."
  
  # Initialize findings array
  local all_findings="[]"
  
  # Parse passes
  IFS=',' read -ra PASS_ARRAY <<< "$PASSES"
  
  # Process each file
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    [ ! -f "$file" ] && continue
    
    log "Hunting in: $file"
    
    local diff_content
    diff_content=$(get_file_diff "$file")
    
    if [ -z "$diff_content" ]; then
      continue
    fi
    
    # Run each pass
    for pass in "${PASS_ARRAY[@]}"; do
      pass=$(echo "$pass" | xargs)  # trim
      log "  → Running $pass hunter..."
      
      local findings
      findings=$(run_pass "$pass" "$file" "$diff_content")
      
      # Add file to each finding if missing
      findings=$(echo "$findings" | jq --arg file "$file" '[.[] | .file = ($file // .file)]')
      
      # Merge into all_findings
      all_findings=$(echo "$all_findings" "$findings" | jq -s 'add // []')
    done
  done <<< "$files"
  
  # Count severities
  local critical_count
  local warning_count
  critical_count=$(echo "$all_findings" | jq '[.[] | select(.severity == "critical")] | length')
  warning_count=$(echo "$all_findings" | jq '[.[] | select(.severity == "warning")] | length')
  
  log "Hunt complete. Found: $critical_count critical, $warning_count warnings"
  
  # Determine status
  local status="success"
  if [ "$critical_count" -gt 0 ]; then
    status="failure"
  elif [ "$warning_count" -gt 0 ]; then
    status="warning"
  fi
  
  # Save outputs
  echo "$status" > "$STATUS_FILE"
  echo "$all_findings" | jq '.' > "$FINDINGS_FILE"
  
  # Set GitHub Actions outputs
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "status=$status" >> "$GITHUB_OUTPUT"
    echo "findings=$all_findings" >> "$GITHUB_OUTPUT"
    echo "critical-count=$critical_count" >> "$GITHUB_OUTPUT"
    echo "warning-count=$warning_count" >> "$GITHUB_OUTPUT"
  fi
  
  log "🧛‍♂️ The hunter rests. Status: $status"
  
  if [ "$status" = "failure" ]; then
    exit 1
  fi
}

main "$@"
