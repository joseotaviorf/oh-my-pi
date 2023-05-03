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

</details>
