#!/usr/bin/env bash
# test-runner.sh - Run test suite and parse results

set -e

# Get script directory for sourcing other scripts
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🧪 Running test suite..."

# Get test command from environment or detect
TEST_COMMAND="${TEST_COMMAND:-npm test}"

# Initialize defaults
PASSED=0
FAILED=0
SKIPPED=0
FAILURES="[]"
TEST_STATUS="success"

# Run tests with JSON output if possible
if echo "$TEST_COMMAND" | grep -qE "jest|vitest"; then
	# Ensure we have a reporter that produces JSON
	JSON_CMD="$TEST_COMMAND --reporter=json --outputFile=test-results.json"
	if echo "$TEST_COMMAND" | grep -q "jest"; then
		JSON_CMD="$TEST_COMMAND --json --outputFile=test-results.json"
	fi

	echo "Running: $JSON_CMD"
	if $JSON_CMD 2>&1; then
		TEST_STATUS="success"
	else
		TEST_STATUS="failure"
	fi

	if [ -f test-results.json ]; then
		PASSED=$(jq '.numPassedTests // 0' test-results.json)
		FAILED=$(jq '.numFailedTests // 0' test-results.json)
		SKIPPED=$(jq '.numPendingTests // 0' test-results.json)

		# Extract failure details - vitest 3 uses "fail" status in nested tasks
		# Also handles jest's "failed" status in assertionResults
		FAILURES=$(jq -c '[.. | objects | select(.status == "fail") | {name: (.title // .fullName), error: ((.errors[0].message // .failureMessages[0]) | split("\n")[0])}] | .[0:10]' test-results.json 2>/dev/null || echo "[]")

		rm -f test-results.json

		# Override status based on parsed results
		if [ "$FAILED" -gt 0 ]; then
			TEST_STATUS="failure"
		fi
	else
		echo "⚠️ Failed to produce test-results.json, falling back to basic execution"
		if $TEST_COMMAND 2>&1; then
			TEST_STATUS="success"
		else
			TEST_STATUS="failure"
			FAILED=1
		fi
	fi
elif echo "$TEST_COMMAND" | grep -q "pytest"; then
	if $TEST_COMMAND --json-report --json-report-file=test-results.json 2>&1; then
		TEST_STATUS="success"
	else
		TEST_STATUS="failure"
	fi
	if [ -f test-results.json ]; then
		PASSED=$(jq '.summary.passed // 0' test-results.json)
		FAILED=$(jq '.summary.failed // 0' test-results.json)
		SKIPPED=$(jq '.summary.skipped // 0' test-results.json)
		FAILURES=$(jq -c '[.tests[] | select(.outcome=="failed") | {name: .nodeid, error: .call.longrepr}] | .[0:10]' test-results.json 2>/dev/null || echo "[]")
		rm -f test-results.json
		if [ "$FAILED" -gt 0 ]; then
			TEST_STATUS="failure"
		fi
	fi
else
	# Fallback: just run and capture
	if $TEST_COMMAND 2>&1; then
		PASSED=1 # Assume 1 pass if successful
		TEST_STATUS="success"
	else
		FAILED=1 # Assume 1 fail if failed
		TEST_STATUS="failure"
	fi
fi

# Set outputs for GitHub Actions
if [ -n "$GITHUB_OUTPUT" ]; then
	RESULTS_JSON="{\"passed\":$PASSED,\"failed\":$FAILED,\"skipped\":$SKIPPED,\"failures\":$FAILURES}"
	echo "results=$RESULTS_JSON" >>"$GITHUB_OUTPUT"
	echo "test_status=$TEST_STATUS" >>"$GITHUB_OUTPUT"
fi

echo "✅ Test suite complete: $PASSED passed, $FAILED failed"

# AI-powered failure diagnosis (if failures exist and API key is set)
if [ "$FAILED" -gt 0 ] && [ -n "$ARCEE_API_KEY" ]; then
	echo ""
	echo "🤖 Running AI failure diagnosis..."
	echo "   SCRIPT_DIR: $SCRIPT_DIR"
	echo "   AI Analyzer: $SCRIPT_DIR/ai-analyzer.sh"

	# Check if ai-analyzer.sh exists
	if [ ! -f "$SCRIPT_DIR/ai-analyzer.sh" ]; then
		echo "   ❌ ai-analyzer.sh not found at $SCRIPT_DIR/ai-analyzer.sh"
	else
		echo "   ✅ ai-analyzer.sh found"
	fi

	# Get git diff for context
	CODE_CONTEXT=$(git diff HEAD -- '*.js' '*.ts' '*.jsx' '*.tsx' '*.py' 2>/dev/null | head -200 || echo "")

	# Call AI analyzer
	echo "   🔍 Calling analyze_failures with $FAILED failures..."
	echo "   FAILURES data: $FAILURES"

	# Call the AI analyzer script directly with arguments
	DIAGNOSIS=$("$SCRIPT_DIR/ai-analyzer.sh" failures "$FAILURES" "$CODE_CONTEXT")

	if [ -n "$DIAGNOSIS" ] && [ "$DIAGNOSIS" != "AI diagnosis unavailable" ]; then
		echo ""
		echo "$DIAGNOSIS"
		if [ -n "$GITHUB_OUTPUT" ]; then
			echo "ai_diagnosis=$DIAGNOSIS" >>"$GITHUB_OUTPUT"
		fi
	else
		echo "   ⚠️ AI diagnosis returned empty or unavailable"
	fi
fi
