# AGENTS.md — Test Runner Faye Operational Protocol

*Behavioral core lives in [SOUL.md](SOUL.md). This file governs operations.*

---

## 1. SESSION START (Summoning)

The validation specialist awakens when summoned via GitHub Actions or OpenClaw subagent invocation.

### Prerequisites Check
```bash
# Required environment
ARCEE_API_KEY=<valid_api_key>     # Analysis engine
MODEL=arcee/trinity-mini          # Default model

# Optional overrides
TEST_COMMAND="npm test"          # Override test command
COVERAGE_COMMAND="npm run coverage"  # Override coverage command
PASSES=test,coverage,delta        # Which skills to invoke
COVERAGE_THRESHOLD=70            # Minimum coverage percentage
```

### Validation Ritual
1. Verify `ARCEE_API_KEY` is set and non-empty
2. Confirm `skills/` directory exists and all skills are executable
3. Detect project type (Node, Python, Go, Rust)
4. Determine test and coverage commands
5. Run test suite first, then coverage analysis

### Checkpoint
```bash
echo "[Test Runner Faye] Project: $PROJECT_TYPE | Command: $TEST_COMMAND | Threshold: $COVERAGE_THRESHOLD%"
```

---

## 2. VALIDATION (Session Execution)

### Skill Invocation Order
Skills are invoked in the order specified by `PASSES`:

```
test → coverage → delta
```

Each skill:
- Runs the appropriate command
- Parses output into structured JSON
- Returns results to be aggregated

### Test Runner (`skills/test-runner.sh`)
- Executes test suite
- Parses results (Jest, Vitest, pytest, Go test, Cargo test)
- Returns: passed, failed, skipped, failures[]

### Coverage Analyzer (`skills/coverage-analyzer.sh`)
- Runs coverage command
- Parses coverage reports (JSON, lcov, cobertura)
- Returns: percent, lines_covered, lines_total, uncovered_files[]

### Delta Coverage (`skills/delta-coverage.sh`)
- Analyzes git diff for new code
- Cross-references with coverage data
- Returns: new_lines, coverage_on_new, risky_files[]

### Output Aggregation
All results merged into single report with:
- Test summary
- Coverage percentage
- Status (pass/warn/fail based on threshold)

---

## 3. SESSION END (Dismissal)

### Persistence
- `test-results.json` — Test execution results
- `coverage-results.json` — Coverage analysis
- `status` — `success` | `warning` | `failure`

### Status Determination
| Tests | Coverage | Status |
|-------|----------|--------|
| All pass | >= threshold | success |
| Some fail | >= threshold | warning |
| Any fail | < threshold | failure |

### Cleanup
- Remove temp files
- Leave `.test-runner-faye/` directory for inspection

### Handoff
If invoked as subagent, return:
```json
{
  "status": "warning",
  "tests": { "passed": 42, "failed": 2, "skipped": 5 },
  "coverage": 68,
  "threshold": 70,
  "risky_files": ["src/new-feature.ts"]
}
```

---

## 4. ERROR HANDLING

| Error | Response | Exit Code |
|-------|----------|-----------|
| Missing ARCEE_API_KEY | Log fatal, status=failure | 1 |
| No test command found | Log warning, skip tests | 0 |
| No coverage command | Log warning, skip coverage | 0 |
| Tests fail | status=warning | 0 |
| Coverage < threshold | status=failure | 1 |
| All skills fail | Log fatal | 1 |

---

## 5. EXTERNAL INTEGRATION

### GitHub Actions
Entry point: `action.yml`
- Automatic PR comment with test + coverage summary
- Check run creation
- Fails workflow if threshold not met

### OpenClaw Subagent
Entry point: `agent.yml`
- Spawn via: `openclaw agent --agent test-runner-faye --task "validate PR #N"`
- Returns structured JSON

### Local Invocation
```bash
# Run tests only
TEST_COMMAND="npm test" ./skills/test-runner.sh

# Full validation
ARCEE_API_KEY=xxx COVERAGE_THRESHOLD=80 ./scripts/validate.sh
```

---

## 6. EXTENDING FAYE

To add a new validation skill (e.g., `lint`):

1. Create `skills/lint-checker.sh`
2. Add prompt to `prompts/lint-checker.md`
3. Register in `agent.yml` passes section
4. Update `PASSES` default

---

## 7. SAFETY & PRIVACY

- **API Keys**: Never logged, passed via env only
- **Code**: Analyzed locally, only results shared
- **Logs**: File paths may appear; test output does not

---

## Quick Reference

| Task | Command |
|------|---------|
| Summon for PR validation | Uses GitHub Action |
| Summon as subagent | `openclaw agent --agent test-runner-faye` |
| Test single skill | `./skills/test-runner.sh` |
| Override threshold | `COVERAGE_THRESHOLD=80 ./scripts/validate.sh` |

---

*The tests run. The coverage speaks. Faye delivers truth.*
