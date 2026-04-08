#!/usr/bin/env bash
# test-runner.sh - Run test suite and parse results

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🧪 Running test suite..."

TEST_COMMAND="${TEST_COMMAND:-npm test}"

PASSED=0
FAILED=0
SKIPPED=0
FAILURES="[]"
TEST_STATUS="success"

# If a working directory is set, change into it before running
if [ -n "$WORKING_DIRECTORY" ]; then
	echo "📂 Changing to directory: $WORKING_DIRECTORY"
	cd "$WORKING_DIRECTORY"
fi

if echo "$TEST_COMMAND" | grep -qE "jest|vitest"; then
	JSON_CMD="$TEST_COMMAND --reporter=json --outputFile=test-results.json"
	if echo "$TEST_COMMAND" | grep -q "jest"; then
		JSON_CMD="$TEST_COMMAND --json --outputFile=test-results.json"
	fi

	echo "Running: $JSON_CMD"
	if eval "$JSON_CMD" 2>&1; then
		TEST_STATUS="success"
	else
		TEST_STATUS="failure"
	fi

	if [ -f test-results.json ]; then
		# Debug: show keys and counts
		echo "DEBUG: test-results.json exists, size=$(wc -c < test-results.json)"
		jq 'keys' test-results.json 2>/dev/null && echo "DEBUG: numFailedTests=$(jq '.numFailedTests' test-results.json) numPassedTests=$(jq '.numPassedTests' test-results.json)"

		PASSED=$(jq '.numPassedTests // 0' test-results.json)
		FAILED=$(jq '.numFailedTests // 0' test-results.json)
		SKIPPED=$(jq '.numPendingTests // 0' test-results.json)

		# vitest/jest JSON format: .testResults[].assertionResults[] with status: "passed"|"failed"
		FAILURES=$(jq -c '[.testResults[].assertionResults[] | select(.status=="failed") | {name: .fullName, error: (.failureMessages[0] // .errors[0].message)}] | .[0:10]' test-results.json 2>/dev/null || echo "[]")

		echo "DEBUG: FAILURES=$FAILURES"
		rm -f test-results.json

		if [ "$FAILED" -gt 0 ]; then
			TEST_STATUS="failure"
		fi
	else
		echo "⚠️ Failed to produce test-results.json, falling back to basic execution"
		if eval "$TEST_COMMAND" 2>&1; then
			TEST_STATUS="success"
		else
			TEST_STATUS="failure"
			FAILED=1
		fi
	fi
elif echo "$TEST_COMMAND" | grep -q "pytest"; then
	if eval "$TEST_COMMAND --json-report --json-report-file=test-results.json" 2>&1; then
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
	if eval "$TEST_COMMAND" 2>&1; then
		PASSED=1
		TEST_STATUS="success"
	else
		FAILED=1
		TEST_STATUS="failure"
	fi
fi

if [ -n "$GITHUB_OUTPUT" ]; then
	RESULTS_JSON="{\"passed\":$PASSED,\"failed\":$FAILED,\"skipped\":$SKIPPED,\"failures\":$FAILURES}"
	echo "results=$RESULTS_JSON" >>"$GITHUB_OUTPUT"
	echo "test_status=$TEST_STATUS" >>"$GITHUB_OUTPUT"
fi

echo "✅ Test suite complete: $PASSED passed, $FAILED failed"

if [ "$FAILED" -gt 0 ] && [ -n "$ARCEE_API_KEY" ]; then
	echo ""
	echo "🤖 Running AI failure diagnosis..."

	if [ ! -f "$SCRIPT_DIR/ai-analyzer.sh" ]; then
		echo "   ❌ ai-analyzer.sh not found"
	else
		CODE_CONTEXT=$(git diff HEAD -- '*.js' '*.ts' '*.jsx' '*.tsx' '*.py' 2>/dev/null | head -200 || echo "")
		DIAGNOSIS=$("$SCRIPT_DIR/ai-analyzer.sh" failures "$FAILURES" "$CODE_CONTEXT")
		if [ -n "$DIAGNOSIS" ] && [ "$DIAGNOSIS" != "AI diagnosis unavailable" ]; then
			echo "$DIAGNOSIS"
			if [ -n "$GITHUB_OUTPUT" ]; then
				echo "ai_diagnosis=$DIAGNOSIS" >>"$GITHUB_OUTPUT"
			fi
		else
			echo "   ⚠️ AI diagnosis returned empty"
		fi
	fi
fi
