## Batch Inference

### Purpose

This DAG is responsible for loading prediction input and outputs from our collections batch prediction ML pipelines into our Data Lake.

Batch prediction pipelines are being developed in our ML environment through the usage of a monorepo approach. More info about this process in [this doc](https://docs.google.com/document/d/1sZwikQ8pxCN1mobkdEy09zyDCfdyfpQIkSLpdW_NYv4).

The monorepo batch predictions write data to a standardized bucket in s3, from which data will be loaded incrementally into our datalake

<details>
  <summary><strong> DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG is triggered once a day.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This DAG produces, via incremental load, the following tables in Raw layer:

- `batch_inference`

</details>
