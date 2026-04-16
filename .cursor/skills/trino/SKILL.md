---
name: trino
description: "TD Trino SQL with TD-specific functions (td_interval, td_time_range, td_time_string, td_sessionize). Use for writing and executing SQL against Trino/Treasure Data. Handles CLI detection, setup guidance, and Python-based execution."
---

# Treasure Data Trino SQL

You are a senior data engineer specializing in Treasure Data (TD) Trino SQL. Your goal is to write efficient, high-performance queries and execute them while ensuring the environment is properly configured.

## Trino Query Checklist
- **Always include a time filter** on the `time` column to ensure partition pruning.
- **Prefer `td_interval`** for relative time windows.
- **Use `approx_distinct()` and `approx_percentile()`** for large datasets.
- **Check environment** for `trino` CLI or `trino-python-client` before executing.
- **Prompt for setup** if no execution path is found.

## Execution Workflow

### 1. Pre-requisite Check
Ensure `pandas` and `keyring` are installed in the `.venv`.

### 2. Environment Setup
The default Trino host for this repository is **`trino.apps.data-prd.habitat.zone`**. Users are expected to have this as `TRINO_HOST` in their `.env` (`TRINO_HOST=trino.apps.data-prd.habitat.zone`). If `TRINO_HOST` is not set, fall back to this default — in last case, ask the user to prompt the value.

### 3. Execution
Use the bundled `execute_trino.py` script for all queries. This script handles OAuth2/SSO authentication and caches tokens to prevent repeated prompts. Always pass the default host explicitly so the call works even when the user has not exported `TRINO_HOST`:

```bash
.venv/bin/python3 scripts/execute_trino.py \
    --host "${TRINO_HOST:-trino.apps.data-prd.habitat.zone}" \
    --query "YOUR_SQL_HERE" \
    --external-auth
```

**Mandatory Parameters:**
- `--query`: The SQL query to execute.
- `--external-auth`: Always include this flag for SSO environments.
- `--host`: Always pass `"${TRINO_HOST:-trino.apps.data-prd.habitat.zone}"` so the default host is applied when the env var is not set.

**Optional Parameters:**
- `--port`: Defaults to 443 (HTTPS).
- `--catalog` / `--schema`: Target specific data locations.

*Note: Do NOT use the `trino` CLI directly. The Python script is the primary and only execution path to ensure token caching works correctly.*

## Time-Based Filtering (Syntax)

### Relative Time with `td_interval`
```sql
where td_interval(time, '-1d', 'JST')      -- Yesterday (JST)
where td_interval(time, '-1w', 'JST')      -- Previous week
```

### Explicit Ranges with `td_time_range`
```sql
where td_time_range(time, '2024-01-01', '2024-01-31')
```

## Company Usage Examples

To trigger this skill for company-specific queries, use prompts like:

- **"Execute a Trino query to count the number of active users in the last 7 days from the `web_logs` database."**
- **"Run a Trino SQL on `marketing.campaign_performance` to get the conversion rate for yesterday (JST)."**
- **"Connect to Trino and show me the first 10 rows of the `transactions` table in the `sales` schema."**
- **"Check if I have the Trino CLI installed, and if so, run `SELECT count(*) FROM access_logs`."**
- **"I need to sessionize user events from `raw_events`. Can you write the Trino query and execute it for the last 24 hours?"**

## Performance Guidelines
- **Good:** `where td_time_range(time, '2024-01-01', '2024-01-02')`
- **Bad:** `where event_type = 'click'` (Missing time filter)

## Common Error Resolution
- **Memory limit**: Add narrower time filters or use `approx_` functions.
- **CLI not found**: Fallback to Python mode or prompt for installation.
- **Timezone issues**: Specify timezone explicitly (e.g., 'JST', 'UTC').

## Reference Resources
- [Trino Official Documentation](https://trino.io/docs/current/)
- [Treasure Data Trino Functions Reference](https://docs.treasuredata.com/display/public/PD/Trino+SQL+Reference)
