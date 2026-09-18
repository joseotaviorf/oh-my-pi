# benvi_manager

CDC from `benvi_manager.integration_superlogica.lake_mirror` (Debezium connector `kcc-benvi-manager-dbz`).

Raw table: `datalake_benvi_manager_raw.lake_mirror`.

CDC clean of this DAG is the dump table `datalake_benvi_manager_clean.lake_mirror`.
Per-resource tables are `bietlejuice.benvi_manager_clean`.

## Trigger

No cron. `schedule_interval` is YAML `null` so the DAG is unscheduled (same
effect as Airflow `schedule=None`). It stays unpaused. A run starts only from
Airflow REST or UI Trigger DAG.

benvi-manager (backend-services) POSTs
`/api/v1/dags/bietlejuice.benvi_manager/dagRuns` after import SUCCEEDED or
PARTIAL. Body is `{"conf": {...}}` only (no `dag_run_id`, no `logical_date`).
`conf` may be empty or include `import_run_id` later.

Load task `load-clean-lake-mirror` (CDC dump, after raw) emits the dataset
`bietlejuice.benvi_manager:load-clean-lake-mirror` on success when the run type is
Impact Downstream Dependents (or reprocessing). Manual REST with empty `conf`
is a Test Run and does not emit that dataset. Follow-up service code should
pass `run_type: impact_downstream_dependents` in `conf`.
