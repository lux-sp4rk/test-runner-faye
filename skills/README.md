# Test Runner Faye — Skill Registry

This directory contains the validation skills that power Test Runner Faye.

Each skill is a self-contained script that can be invoked independently.

## Available Skills

| Skill | File | Purpose |
|-------|------|---------|
| Test Runner | `test-runner.sh` | Execute test suite, parse results |
| Coverage Analyzer | `coverage-analyzer.sh` | Measure coverage, identify blind spots |

## Usage

```bash
# Run test suite
./skills/test-runner.sh

# Analyze coverage
./skills/coverage-analyzer.sh
```

Each skill outputs JSON to stdout for parsing by the action.

## Adding New Skills

1. Create `skills/your_skill.sh`
2. Add prompt to `prompts/your-skill.md`
3. Register in `agent.yml` passes configuration
4. Update this README

---
*In the skills/ folder, validation is modular.*
