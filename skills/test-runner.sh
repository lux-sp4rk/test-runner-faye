#!/usr/bin/env bash
# test-runner.sh - Run test suite and parse results

set -e

echo "🧪 Running test suite..."

# Get test command from environment or detect
TEST_COMMAND="${TEST_COMMAND:-npm test}"

# Run tests with JSON output if possible
if echo "$TEST_COMMAND" | grep -q "jest"; then
  $TEST_COMMAND --json --outputFile=test-results.json 2>&1 || true
  if [ -f test-results.json ]; then
    cat test-results.json
    rm -f test-results.json
  fi
elif echo "$TEST_COMMAND" | grep -q "vitest"; then
  $TEST_COMMAND --reporter=json --outputFile=test-results.json 2>&1 || true
  if [ -f test-results.json ]; then
    cat test-results.json
    rm -f test-results.json
  fi
elif echo "$TEST_COMMAND" | grep -q "pytest"; then
  $TEST_COMMAND --json-report --json-report-file=test-results.json 2>&1 || true
  if [ -f test-results.json ]; then
    cat test-results.json
    rm -f test-results.json
  fi
else
  # Fallback: just run and capture
  $TEST_COMMAND 2>&1 || true
fi

echo "✅ Test suite complete"
