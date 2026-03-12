#!/usr/bin/env bash
# coverage-analyzer.sh - Analyze test coverage

set -e

echo "📊 Running coverage analysis..."

# Get coverage command from environment
COVERAGE_COMMAND="${COVERAGE_COMMAND:-npm run test:coverage}"

# Run coverage
$COVERAGE_COMMAND 2>&1 || true

# Try to find coverage reports
for report in coverage/coverage-summary.json coverage/lcov.info coverage/cobertura-coverage.xml; do
  if [ -f "$report" ]; then
    echo "Found coverage report: $report"
    # Extract key metrics
    if [ "$report" = "coverage/coverage-summary.json" ]; then
      cat "$report"
    fi
    break
  fi
done

echo "✅ Coverage analysis complete"
