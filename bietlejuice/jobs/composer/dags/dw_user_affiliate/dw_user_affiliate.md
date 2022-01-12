## DW User Affiliate

### Purpose

Creates incremental DW dimension table of the context of `User Affiliate` model, relating enriched data of Amplitude, users and regions, and data of taxonomy sheets. This dimension is stored at the Janus schema to audit its content to the older ODS table content.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs
This pipeline produces the following output tables in DW layer:

- `public.dim_user_affiliate`

### Responsible Data Engineering Team

For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
</details>