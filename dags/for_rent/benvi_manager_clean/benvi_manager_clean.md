# benvi_manager_clean

Reads `datalake_benvi_manager_raw.lake_mirror` (filled by `bietlejuice.benvi_manager`)
and writes one clean table per Superlogica `resource_code`.

Schedule is 30 minutes after the CDC DAG so raw is already written. No shared
workflow changes.
