# benvi_manager_clean

Reads `datalake_benvi_manager_raw.lake_mirror` (filled by `bietlejuice.benvi_manager`)
and writes one clean table per Superlogica `resource_code`.

## Trigger

No cron. `schedule_interval` is omitted so DAG Builder attaches the dataset
schedule from `dags/dependencies.yaml`.

Runs when `bietlejuice.benvi_manager:load-clean-lake-mirror` is emitted (plain
URI, every successful CDC load, not first-run-of-day). UI Trigger DAG still
works if you need an isolated projection rebuild.
