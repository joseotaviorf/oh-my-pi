# tars-evals

Offline evaluation harness for TARS metric-entity golden queries. This package loads
YAML datasets, runs Inspect eval tasks against a local DataHub-shaped mock, scores
results, and aggregates per-dataset gate summaries.

## Quick start

```bash
cd packages/tars-evals
make install
make test
make lint
```

## Credentials

LiteLLM access for live eval runs is fetched from Vault via `qli`:

```bash
make creds
# or: scripts/setup_credentials.sh
```

## Layout

- `src/tars_evals/` — runtime (config, dataset loader, scorer, task, tools, gate)
- `datasets/` — YAML eval datasets (smoke fixture included for core tests)
- `scripts/` — credential helpers
- `tests/` — unit tests for the harness core

Follow-up PRs add dataset generation, gate orchestration, Woodpecker CI, local
parity commands, and optional S3 log archival.
