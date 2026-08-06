# DataHub / TARS pivot benchmarks

> **Historical (2026-08):** The in-repo TARS skill was removed in [#26095](https://github.com/quintoandar/bi-etl-ejuice/pull/26095). TARS now lives in [`ai-tools/marketplace/tars/`](https://github.com/quintoandar/ai-tools/tree/main/marketplace/tars). Artifacts below document the pivot ROI; `.cursor/skills/trino/` remains as a standalone Trino utility.

Evaluation artifacts and scripts for the [TARS → DataHub MCP pivot RFC](../../rfc/datahub/tars_pivot.md). Not part of the DataHub publish pipeline in `dags/governance/datahub_business_context/`.

## Reports and fixtures

| File | Description |
|------|-------------|
| [`benchmark_report.md`](./benchmark_report.md) | Context-efficiency ROI summary (old file-read flow vs DataHub MCP). |
| [`benchmark_results.json`](./benchmark_results.json) | Raw benchmark run data. |
| [`quality_report.md`](./quality_report.md) | Golden SQL quality eval pass/fail narrative. |
| [`quality_results.json`](./quality_results.json) | Raw quality eval data. |
| [`eval_cases.yml`](./eval_cases.yml) | Golden SQL test cases for the quality harness. |

## Scripts

From the repo root (requires `DATAHUB_*` and/or Trino access as noted in each script):

```bash
export DATAHUB_GRAPHQL_URL="https://<datahub-host>/api/graphql"
export DATAHUB_TOKEN="<token>"

# Context-efficiency benchmark (regenerates benchmark_report.md + benchmark_results.json)
uv run python docs/benchmark/datahub/benchmark_tars_pivot.py

# Golden SQL quality eval (regenerates quality_report.md + quality_results.json)
uv run python docs/benchmark/datahub/evaluate_sql_quality.py
```
