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
    - `user_revision_entity`
    - `user_sales_rep`

</details>
