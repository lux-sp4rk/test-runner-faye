# Test Runner Faye 🤖

> *"The test that passes is worthless. The test that fails tells the truth."*

A GitHub Action and OpenClaw subagent for running test suites and analyzing code coverage on pull requests.

## Features

- **Test Execution** — Runs your test suite (Jest, Vitest, pytest, Go test, Cargo test)
- **Coverage Analysis** — Measures line, branch, and function coverage
- **Delta Coverage** — Analyzes coverage on new/changed code in PRs
- **Threshold Enforcement** — Fails if coverage drops below your threshold

## Usage

### GitHub Actions

```yaml
name: Test Runner Faye
on: [pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: lux-sp4rk/test-runner-faye@v1
        with:
          arcee-api-key: ${{ secrets.ARCEE_API_KEY }}
          coverage-threshold: 70
```

### Configuration

| Input | Description | Default |
|-------|-------------|---------|
| `arcee-api-key` | Arcee API key | Required |
| `model` | Model to use | `arcee/trinity-mini` |
| `passes` | Which passes to run | `test,coverage,delta` |
| `coverage-threshold` | Min coverage % | `70` |
| `test-command` | Override test command | Auto-detect |
| `coverage-command` | Override coverage command | Auto-detect |

## For Arachne

Faye is one of Arachne's summonable sub-agents. See `dotfiles` for integration.

## License

MIT

---

## Canonical Location

This repo is the canonical home for Test Runner Faye.  
Mirror: [lux-sp4rk/test-runner-faye](https://github.com/lux-sp4rk/test-runner-faye) (archived)
