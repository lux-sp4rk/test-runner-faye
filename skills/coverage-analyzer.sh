#!/usr/bin/env bash
# coverage-analyzer.sh - Analyze test coverage

set -e

echo "📊 Running coverage analysis..."

if [ -n "$WORKING_DIRECTORY" ]; then
	echo "📂 Changing to directory: $WORKING_DIRECTORY"
	cd "$WORKING_DIRECTORY"
fi

# Get coverage command from environment
COVERAGE_COMMAND="${COVERAGE_COMMAND:-npm run test:coverage}"
COVERAGE_THRESHOLD="${COVERAGE_THRESHOLD:-70}"

# Run coverage
echo "Running: $COVERAGE_COMMAND"
COVERAGE_OUTPUT=$(mktemp)
$COVERAGE_COMMAND 2>&1 | tee "$COVERAGE_OUTPUT" || true

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

# Fallback: parse vitest/jest text output for line coverage
if [ "$PERCENT" = "0" ] || [ -z "$PERCENT" ]; then
	# Look for line like: "All files          |   79.25 |    82.16 |   67.22 |   79.25 |"
	LINES_PCT=$(grep "^All files" "$COVERAGE_OUTPUT" | awk -F'|' '{gsub(/ /,"",$5); print $5}' | head -1)
	if [ -n "$LINES_PCT" ]; then
		PERCENT="$LINES_PCT"
		echo "Extracted line coverage from text output: $PERCENT%"
	fi
fi

rm -f "$COVERAGE_OUTPUT"

# If percent is 0 and we didn't find a report, maybe it failed
if [ -z "$PERCENT" ]; then PERCENT=0; fi

# Determine status
if (($(echo "$PERCENT >= $COVERAGE_THRESHOLD" | bc -l))); then
	STATUS="success"
else
	STATUS="failure"
fi

# Set outputs for GitHub Actions
if [ -n "$GITHUB_OUTPUT" ]; then
	echo "percent=$PERCENT" >>"$GITHUB_OUTPUT"
	echo "status=$STATUS" >>"$GITHUB_OUTPUT"
fi

echo "✅ Coverage analysis complete: $PERCENT% (threshold: $COVERAGE_THRESHOLD%)"

# Get script directory for AI analyzer
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# AI-powered coverage narrative (if uncovered code exists and model is large)
if [ "$PERCENT" -lt 100 ] && [ -n "$ARCEE_API_KEY" ]; then
	echo ""
	echo "🤖 Generating coverage narrative..."

	# Extract uncovered files/lines
	UNCOVERED=""
	if [ -f "coverage/coverage-summary.json" ]; then
		UNCOVERED=$(jq -r '. | to_entries | .[] | select(.value.lines.pct < 100) | "\(.key): \(.value.lines.pct)% uncovered"' coverage/coverage-summary.json 2>/dev/null | head -20 || echo "")
	fi

	if [ -n "$UNCOVERED" ]; then
		# Get source code for uncovered files
		CODE_CONTEXT=""
		for file in $(echo "$UNCOVERED" | cut -d: -f1 | head -5); do
			if [ -f "$file" ]; then
				CODE_CONTEXT="$CODE_CONTEXT\n\n## $file\n$(head -50 "$file")"
			fi
		done

		# Call AI analyzer
		echo "   🔍 Calling explain_coverage for uncovered code..."

		NARRATIVE=$("$SCRIPT_DIR/ai-analyzer.sh" coverage "$UNCOVERED" "$CODE_CONTEXT")

		if [ -n "$NARRATIVE" ] && [ "$NARRATIVE" != "AI narrative unavailable" ]; then
			echo ""
			echo "$NARRATIVE"
			if [ -n "$GITHUB_OUTPUT" ]; then
				echo "ai_narrative=$NARRATIVE" >>"$GITHUB_OUTPUT"
			fi
		else
			echo "   ⚠️ AI narrative returned empty or unavailable"
		fi
	fi
fi
