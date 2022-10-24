## Datamarts Fintech

### Purpose

Creates/updates the datamart tables that don't have cross squad dependencies, for the context of Fintech, in data lake.

​<details>

  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline creates the following full tables in the schema `dw_datamarts` of data lake:

- `doubtful_debtors_provision`

### Responsible Data Engineering Team

For any questions or concerns about this DAG, please contact the Data Fintech team.

### Additional Information

The file [fintech.yml](https://github.com/quintoandar/bi-etl-ejuice/blob/master/bietlejuice/dags/dw_datamarts_spark/fintech/fintech.yml)
declares the datamarts that should be created in this DAG.
So **to add/remove a datamart table** from the DAG you only need to **update this file**.

</details>
