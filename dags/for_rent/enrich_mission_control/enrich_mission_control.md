## Enrich Mission Control

### Purpose
This DAG creates the enriched tables from Mission Control.
It deduplicates de tables due to incremental load from raw/clean ingestion.
<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily, via Mediator, after `firestore` DAG.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
This pipeline produces the following tables in enrich layer, via full load:
- `contract`
- `onboarding`
- `onboarding_action`
- `onboarding_bill`
- `onboarding_task`
- `onboarding_task_types`

​</details>