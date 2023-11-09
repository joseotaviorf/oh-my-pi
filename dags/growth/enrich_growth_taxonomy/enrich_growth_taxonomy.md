## Enrich Growth Taxonomy

### Purpose
This DAG enrich manual inputs to generate Growth Taxonomy related tables that will be used to share Media results and costs between marketing and operation channels.
More info about Growth Taxonomy and media setup params in [this doc](https://docs.google.com/presentation/d/1BylJwYp9-yoqEqNvzcIvzHLVhZbOOomAjDH5XmIaXtY/edit?usp=sharing).

​<details>

<summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Currently, there is the following output table in our enrich layer:

-`datalake_growth_taxonomy.media_setup`
-`datalake_growth_taxonomy.demand_operation_flow`
-`datalake_growth_taxonomy.demand_user_path`

