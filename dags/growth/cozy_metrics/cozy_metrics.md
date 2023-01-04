## Cozy Metrics

### Purpose

This is a pipeline to collect and transform data for measuring the evolution of Cozy at the Design Systems team. With these data, they can be monitoring libraries' versions and other metrics in PWAs.

Important docs about Cozy:

- [Cozy RFC Automation](https://www.notion.so/productquintoandar/RFC-Cozy-Metrics-Automation-9c36bc097a834a8ab85bd87c71266ebb)
- [Source Bucket](https://s3.console.aws.amazon.com/s3/buckets/cozy-metrics-automation-prod-s3?prefix=CozyFoundations/v1/&region=us-east-1)

*Disclaimer: the step to load data from PWAs' repositories is the responsibility of the Design System SWE's team. We getting data from their bucket.*

If you can read more about how Cozy Metrics works, you should access [this documentation](https://github.com/quintoandar/cozy/tree/master/packages/cozy-metrics).

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG runs daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Tables:

- datalake_cozy_metrics_raw.library_versions
- datalake_cozy_metrics_clean.library_versions
  
</details>