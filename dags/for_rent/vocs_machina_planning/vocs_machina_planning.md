## VOCS Machina Planning

### Purpose

​
VOCS-34 Slice 1: collects a daily inference-status snapshot for the vocs-machina
LLM classification pipeline. Reads quintoml's active-prompt manifest, works out
which (day, prompt_id, prompt_hash) backfill partitions should exist, checks
whether quintoml has already finalized each one (`_SUCCESS` marker present),
and lands a done/missing snapshot in the raw datalake
(`datalake_vocs_machina_planning_raw.vocs_machina_inference_status`) for
downstream planning/monitoring of the vocs-machina backfill.

This DAG is hand-rolled (not DAG-Builder generated): a later slice needs a
hybrid cron + dataset schedule (`DatasetOrTimeSchedule` +
`CronTriggerTimetable`) that the shared `BaseWorkflow` cannot express.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval

Placeholder schedule for this slice (`schedule_interval=None`): manual or
dataset-triggered runs only. A hybrid cron + dataset schedule lands in a later
slice.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

​
This pipeline produces the following output table on the raw layer:

- `vocs_machina_inference_status`
  ​
  ​</details>
