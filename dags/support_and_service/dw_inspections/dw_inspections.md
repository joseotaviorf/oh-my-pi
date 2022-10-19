## DW Inspections

### Purpose

This DAG loads the DW tables for Inspection Services and PWA data (old data). These data are mainly related to the entry and exit inspections carried out by QuintoAndar.​

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval

This DAG is triggered once per day via Mediator, after enrich_chattermill DAG, usually around 5 A.M. UTC.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output tables:
​
- `dim_assessment` (incremental load)
- `dim_inspection` (full load)
- `dim_inspector` (full load)
- `fact_inspection` (full load)

### Responsible Data Engineering Team

For any questions or concerns about this DAG, please contact the Data Support and Service team.

</details>
