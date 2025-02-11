## Copilot Judge Metrics

### Purpose

This DAG is responsible for loading copilot llm-as-a-judge metrics into our Data Lake.

The judge writes the result metrics in an S3 bucket, from which data will be loaded into our database.

<details>
  <summary><strong> DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG is triggered once a day.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This DAG produces, via incremental load, the following tables in Raw layer:

- `copilot_judge_metrics`

</details>
