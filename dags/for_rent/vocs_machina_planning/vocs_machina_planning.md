## VOCS Machina Planning

### Purpose

​
Collects a daily inference-status snapshot for the vocs-machina LLM
classification pipeline. Reads quintoml's active-prompt manifest, works out
which (day, prompt_id, prompt_hash) backfill partitions should exist, checks
whether quintoml has already finalized each one (`_SUCCESS` marker present),
and lands a done/missing snapshot in the raw datalake
(`datalake_vocs_machina_planning_raw.vocs_machina_inference_status`). From
there, the enrich layer materializes per-partition and per-prompt rollup
tables that quintoml reads to plan/monitor the vocs-machina backfill.

This DAG is hand-rolled (not DAG-Builder generated): it needs a hybrid cron +
dataset schedule (`DatasetOrTimeSchedule` + `CronTriggerTimetable`) that the
shared `BaseWorkflow` cannot express.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval

Hybrid schedule (VOCS-34 Slice 3): triggered by any of 14 upstream
`reverse_birdie` datasets firing, OR by a 6-hour cron safety net
(`0 */6 * * *`, America/Sao_Paulo), whichever comes first. A run triggered
only by the cron safety net skips entirely if the computed snapshot is
unchanged since the last published run.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

​
This pipeline produces the following output tables:

- Raw layer: `vocs_machina_inference_status`
- Enrich layer: `vocs_machina_backfill_status` (per-partition detail),
  `vocs_machina_backfill_status_summary` (per-prompt rollup -- its load task
  is the dataset quintoml subscribes to for backfill planning)
  ​
  ​</details>
