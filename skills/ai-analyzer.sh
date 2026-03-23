#!/usr/bin/env bash
# ai-analyzer.sh - AI-powered test analysis using Arcee
# Analyzes failures, explains coverage gaps, suggests test priorities

set -e

ARCEE_API_KEY="${ARCEE_API_KEY:-}"
MODEL="${MODEL:-trinity-large-preview}"
BASE_URL="https://api.arcee.ai/api/v1"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
	echo -e "${GREEN}[AI Analyzer]${NC} $1" >&2
}

error() {
	echo -e "${RED}[AI Analyzer]${NC} $1" >&2
}

# Call Arcee API
call_arcee() {
	local prompt="$1"
	local system="${2:-You are an expert software engineer and test analyst. Analyze test failures and coverage gaps. Provide clear, actionable insights.}"

	if [ -z "$ARCEE_API_KEY" ]; then
		error "ARCEE_API_KEY not set"
		return 1
	fi

	# DEBUG: Log what we're about to do
	log "🌐 Calling Arcee API..."
	log "   Model: $MODEL"
	log "   Endpoint: $BASE_URL/chat/completions"
	log "   API Key: ${ARCEE_API_KEY:0:8}... (${#ARCEE_API_KEY} chars)"

	# Build JSON payload using jq for proper escaping
	local json_payload
	json_payload=$(jq -n \
		--arg model "$MODEL" \
		--arg system "$system" \
		--arg prompt "$prompt" \
		'{
			model: $model,
			messages: [
				{role: "system", content: $system},
				{role: "user", content: $prompt}
			],
			max_tokens: 2000,
			temperature: 0.3
		}')

	local response
	response=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/chat/completions" \
		-H "Authorization: Bearer $ARCEE_API_KEY" \
		-H "Content-Type: application/json" \
		-d "$json_payload")

	local http_code
	http_code=$(echo "$response" | tail -n1)
	local body
	body=$(echo "$response" | sed '$d')

	# DEBUG: Log response
	log "   HTTP Status: $http_code"

	if [ "$http_code" != "200" ]; then
		error "API call failed with status $http_code"
		error "Response: $body"
		return 1
	fi

	echo "$body" | jq -r '.choices[0].message.content // empty'
}

# Analyze test failures
analyze_failures() {
	local failures_json="$1"
	local code_context="$2"

	if [ -z "$failures_json" ] || [ "$failures_json" = "[]" ]; then
		log "No failures to analyze"
		return 0
	fi

	log "🔍 Analyzing test failures..."

	local prompt="You are a test failure analyst. Given the following test failures, explain WHY they failed and suggest HOW to fix them.

TEST FAILURES:
$failures_json

CODE CONTEXT (relevant source files):
$code_context

Respond in this format:
## Root Cause
[Explain the underlying cause of the failures]

## Suggested Fixes
1. [Specific fix for failure 1]
2. [Specific fix for failure 2]
...

## Prevention
[How to prevent similar failures]"

	call_arcee "$prompt" "You are an expert software engineer. Analyze test failures, explain root causes, and suggest fixes. Be specific and actionable."
}

# Explain uncovered code
explain_coverage() {
	local uncovered_json="$1"
	local code_context="$2"

	if [ -z "$uncovered_json" ] || [ "$uncovered_json" = "[]" ]; then
		log "No uncovered code to analyze"
		return 0
	fi

	log "📖 Explaining uncovered code..."

	local prompt="You are a coverage analyst. Given the following uncovered code paths, explain what each does in PLAIN ENGLISH and why it matters.

UNCOVERED CODE:
$uncovered_json

CODE SOURCE:
$code_context

Respond in this format:
## Uncovered Code Explained
### File: [name]
- **Function/Line**: What it does
- **Why it matters**: Business logic impact
- **Test suggestion**: What test would cover it"

	call_arcee "$prompt" "You are a code coverage expert. Explain what uncovered code does in simple terms and why testing it matters."
}

# Smart test selection
predict_important_tests() {
	local changed_files="$1"
	local test_list="$2"

	if [ -z "$changed_files" ]; then
		log "No changed files to analyze"
		return 0
	fi

	log "🎯 Predicting important tests for changed code..."

	local prompt="You are a test selection expert. Given the following code changes, predict which tests are MOST LIKELY to catch regressions.

CHANGED FILES:
$changed_files

AVAILABLE TESTS:
$test_list

Respond in this format:
## Priority Tests (run these first)
1. [test name] - why it matters for [changed file]
2. [test name] - why it matters for [changed file]

## Lower Priority
- [test name] - unlikely to be affected"

	call_arcee "$prompt" "You are a test selection expert. Predict which tests are most important given code changes. Prioritize tests that cover the changed functionality."
}

# Main
COMMAND="${1:-help}"

case "$COMMAND" in
failures)
	analyze_failures "$2" "$3"
	;;
coverage)
	explain_coverage "$2" "$3"
	;;
predict)
	predict_important_tests "$2" "$3"
	;;
*)
	echo "Usage: $0 {failures|coverage|predict} [json_data] [code_context]"
	echo ""
	echo "Commands:"
	echo "  failures <failures_json> <code_context> - Analyze test failures"
	echo "  coverage  <uncovered_json>  <code_context>  - Explain uncovered code"
	echo "  predict   <changed_files>   <test_list>    - Predict important tests"
	;;
esac
