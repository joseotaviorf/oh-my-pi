## Metric Fintech Losses

### Purpose

This DAG loads to the DW the metric table for the daily losses snapshot.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily, via Mediator. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table in DW, by incremental load:

- `metric_fintech.pdd`