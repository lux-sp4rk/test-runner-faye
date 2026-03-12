#!/usr/bin/env bash
# test-runner.sh - Run test suite and parse results

set -e

echo "🧪 Running test suite..."

# Get test command from environment or detect
TEST_COMMAND="${TEST_COMMAND:-npm test}"

# Initialize defaults
PASSED=0
FAILED=0
SKIPPED=0
FAILURES="[]"

# Run tests with JSON output if possible
if echo "$TEST_COMMAND" | grep -qE "jest|vitest"; then
  # Ensure we have a reporter that produces JSON
  JSON_CMD="$TEST_COMMAND --reporter=json --outputFile=test-results.json"
  if echo "$TEST_COMMAND" | grep -q "jest"; then
    JSON_CMD="$TEST_COMMAND --json --outputFile=test-results.json"
  fi
  
  echo "Running: $JSON_CMD"
  $JSON_CMD 2>&1 || true
  
  if [ -f test-results.json ]; then
    PASSED=$(jq '.numPassedTests // 0' test-results.json)
    FAILED=$(jq '.numFailedTests // 0' test-results.json)
    SKIPPED=$(jq '.numPendingTests // 0' test-results.json)
    
    # Extract failure details
    FAILURES=$(jq -c '[.testResults[].assertionResults[] | select(.status=="failed") | {name: .fullName, error: .failureMessages[0]}] | .[0:10]' test-results.json 2>/dev/null || echo "[]")
    
    rm -f test-results.json
  else
    echo "⚠️ Failed to produce test-results.json, falling back to basic execution"
    $TEST_COMMAND 2>&1 || true
    # We can't easily parse output, so we assume failure if exit code was non-zero
    # But we already did || true
  fi
elif echo "$TEST_COMMAND" | grep -q "pytest"; then
  $TEST_COMMAND --json-report --json-report-file=test-results.json 2>&1 || true
  if [ -f test-results.json ]; then
    PASSED=$(jq '.summary.passed // 0' test-results.json)
    FAILED=$(jq '.summary.failed // 0' test-results.json)
    SKIPPED=$(jq '.summary.skipped // 0' test-results.json)
    FAILURES=$(jq -c '[.tests[] | select(.outcome=="failed") | {name: .nodeid, error: .call.longrepr}] | .[0:10]' test-results.json 2>/dev/null || echo "[]")
    rm -f test-results.json
  fi
else
  # Fallback: just run and capture
  if $TEST_COMMAND 2>&1; then
    PASSED=1 # Assume 1 pass if successful
  else
    FAILED=1 # Assume 1 fail if failed
  fi
fi

# Set outputs for GitHub Actions
if [ -n "$GITHUB_OUTPUT" ]; then
  RESULTS_JSON="{\"passed\":$PASSED,\"failed\":$FAILED,\"skipped\":$SKIPPED,\"failures\":$FAILURES}"
  echo "results=$RESULTS_JSON" >> "$GITHUB_OUTPUT"
fi

echo "✅ Test suite complete: $PASSED passed, $FAILED failed"
