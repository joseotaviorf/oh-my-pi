## DW Shared Metrics
​
### Purpose
​
Creates the [business metrics](https://data.quintoandar.com.br/metrics/) on DW. This DAG fetches the select queries from S3, creates a table for each metric query, and finally loads the metrics into its respective table on DW, using CTAS(create table as select) approach.

​<details>
  <summary><strong> DAG details (click to expand)</strong></summary>

### Execution​ Interval
Daily. More information about run time [here]({chart_url}{dag_id}).


### Outputs
​
This pipeline produces the tables listed [here](https://data.quintoandar.com.br/metrics/) on DW.
​
### Responsible Data Engineering Team
​
For any questions or concerns about this DAG, please contact the Dag Owner Team.

​</details>