## Enrich EBDB User

### Purpose

Creates enriched tables for the context `User` from ebdb.

It will track detailed information about the QuintoAndar users, such as the affiliate, agents, end-user, doorman, and sales rep.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output tables:

1. In data lake enrich:
    - `affiliate_data`
    - `agent_data`
    - `user`
    - `user_doorman`
    - `user_merge` - Due to complexity to identify the historical users to a current user, we decided to create a notebook to create this historical. If one day this table is deleted and should be recreated, we need to run the 3 first cmd in this notebook before running the tasks of this table. https://dbc-931ee6e0-6803.cloud.databricks.com/?o=4531937035440038#notebook/3238664573531777/command/547319918007525
    - `user_revision_entity`
    - `user_sales_rep`

</details>
