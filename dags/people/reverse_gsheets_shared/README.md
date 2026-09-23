# Shared reverse Google Sheets export

This directory contains the reusable Spark job used by People reverse-report
DAGs to export a partition of a lake table to a Google Sheets worksheet.

## Spark job contract

`spark_jobs/load_to_gsheet.py` receives these positional arguments:

```text
table_name execution_date environment sheet_id sheet_tab
```

The job:

1. Reads only the `year` / `month` / `day` partition for `execution_date` from
   `reverse_reports.<table_name>` (or the validation target).
2. Removes partition columns from the exported payload.
3. Creates the worksheet tab when it does not exist.
4. Clears the previous worksheet contents and writes the header and data in
   bounded batches.

When `environment` is `forno`, the configured Forno spreadsheet ID is used
instead of the spreadsheet ID argument.

## Operational notes

- Google Sheets credentials are read from the `people` Databricks secret scope.
- Rows are consumed with Spark `toLocalIterator()` and formatted in bounded
  batches, so the complete table is not collected into driver memory.
- Values beginning with `=`, `+`, `-`, or `@` are prefixed with `'` to prevent
  Google Sheets formula evaluation.
- The worksheet must remain within Google Sheets' workbook cell limit.
- The shared job is intentionally independent from the legacy
  `reverse_reports` wiring until the dedicated DAG migrations are completed.

## Tests

Tests live under:

`packages/bietlejuice-runtime/test/dags/people/reverse_gsheets_shared/spark_jobs/`

Run them with:

```bash
uv run --directory packages/bietlejuice-runtime pytest \
  test/dags/people/reverse_gsheets_shared/spark_jobs/test_load_to_gsheet.py
```
