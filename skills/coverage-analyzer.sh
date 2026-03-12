#!/usr/bin/env bash
# coverage-analyzer.sh - Analyze test coverage

set -e

echo "📊 Running coverage analysis..."

# Get coverage command from environment
COVERAGE_COMMAND="${COVERAGE_COMMAND:-npm run test:coverage}"
COVERAGE_THRESHOLD="${COVERAGE_THRESHOLD:-70}"

# Run coverage
echo "Running: $COVERAGE_COMMAND"
$COVERAGE_COMMAND 2>&1 || true

PERCENT=0
STATUS="failure"

# Try to find coverage reports
for report in coverage/coverage-summary.json coverage/lcov.info coverage/cobertura-coverage.xml; do
  if [ -f "$report" ]; then
    echo "Found coverage report: $report"
    # Extract key metrics
    if [ "$report" = "coverage/coverage-summary.json" ]; then
      PERCENT=$(jq '.total.lines.pct' "$report" 2>/dev/null || echo "0")
      break
    elif [ "$report" = "coverage/lcov.info" ]; then
      # Basic lcov.info parser (extract LF/LH)
      TOTAL_LINES=$(grep "LF:" "$report" | awk -F: '{sum+=$2} END {print sum}')
      COVERED_LINES=$(grep "LH:" "$report" | awk -F: '{sum+=$2} END {print sum}')
      if [ "$TOTAL_LINES" -gt 0 ]; then
        PERCENT=$(echo "scale=2; $COVERED_LINES * 100 / $TOTAL_LINES" | bc 2>/dev/null || echo "0")
      fi
      break
    fi
  fi
done

# If percent is 0 and we didn't find a report, maybe it failed
if [ -z "$PERCENT" ]; then PERCENT=0; fi

# Determine status
if (( $(echo "$PERCENT >= $COVERAGE_THRESHOLD" | bc -l) )); then
  STATUS="success"
else
  STATUS="failure"
fi

# Set outputs for GitHub Actions
if [ -n "$GITHUB_OUTPUT" ]; then
  echo "percent=$PERCENT" >> "$GITHUB_OUTPUT"
  echo "status=$STATUS" >> "$GITHUB_OUTPUT"
fi

echo "✅ Coverage analysis complete: $PERCENT% (threshold: $COVERAGE_THRESHOLD%)"
