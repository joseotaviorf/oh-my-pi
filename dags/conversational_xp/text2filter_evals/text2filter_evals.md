## Text2Filter Evals

### Purpose

This DAG is responsible for loading evaluation results from the text2filter LLM as Judge pipeline into our Data Lake.

The text2filter evals batch job writes data to a standardized bucket in S3, from which data will be loaded incrementally into our datalake.

<details>
  <summary><strong> DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG is triggered once a day, after the upstream `quintoml.copilot.text2filter_evals.inference` DAG completes.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This DAG produces, via incremental load, the following tables in Raw layer:

- `text2filter_evals`

</details>
