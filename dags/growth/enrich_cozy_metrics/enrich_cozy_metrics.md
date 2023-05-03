## Enrich Cozy Metrics
​
### Purpose
​
This DAG creates the enriched tables of the first layer of enrichment from Cozy Metrics to Design Systems team.

This data is enriched with rules created by product team, to measure and evolute the metrics on PWAs systems.

​
<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution​ Interval

This DAG is triggered daily.

More information about run time [here]({chart_url}{dag_id})

### Outputs

This pipeline produces the following output table:
​

- `library_version`: Contains core versions split (in major, minor and patches) and type of pwa.

</details>
