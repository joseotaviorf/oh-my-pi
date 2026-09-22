# benvi_manager

CDC from `benvi_manager.integration_superlogica.lake_mirror` (Debezium connector `kcc-benvi-manager-dbz`).

Raw table: `datalake_benvi_manager_raw.lake_mirror`.

CDC clean of this DAG is the dump table `datalake_benvi_manager_clean.lake_mirror`.
Per-resource tables are `bietlejuice.benvi_manager_clean`.

## Trigger

Daily cron at `0 10 * * *`. The benvi-manager import runs at 09:00 and takes
around 11 minutes, so 10:00 leaves roughly 49 minutes for the Debezium and S3
sink pipe to land that write before this DAG reads it. Every other CDC DAG in
this repo is cron-scheduled for the same reason: a fixed gap removes the race
instead of defending against it.

A scheduled run needs no `conf`. `DagRunType.SCHEDULED` already resolves to
Impact Downstream Dependents in `DatasetService._get_run_type`, so the dataset
is emitted and `bietlejuice.benvi_manager_clean` fires on its own.

The declaration overrides the CDC load window. `RawCDCWorkflow` defaults
`load_end_date` to `data_interval_start`, which on a 10:00 daily cron is
yesterday, so the 09:00 import (written under today's `year=/month=/day=`
prefix) would be skipped until the next day and the DAG would sit permanently
one day behind. The override uses `data_interval_end`, which is today for a
scheduled run and equals the logical date for a manual one.

benvi-manager (backend-services) also POSTs
`/api/v1/dags/bietlejuice.benvi_manager/dagRuns` after import SUCCEEDED or
PARTIAL, passing `run_type: impact_downstream_dependents` plus
`expected_synced_at`, `expected_row_count` and `import_run_id` in `conf`. That
path stays available for ad-hoc runs, but the cron is the reliable daily one:
triggering immediately after the import can read the landing zone before CDC
has drained it.

Load task `load-clean-lake-mirror` (CDC dump, after raw) emits the dataset
`bietlejuice.benvi_manager:load-clean-lake-mirror` on success when the run type is
Impact Downstream Dependents (or reprocessing). Manual REST with empty `conf`
is a Test Run and does not emit that dataset. Follow-up service code should
pass `run_type: impact_downstream_dependents` in `conf`.
