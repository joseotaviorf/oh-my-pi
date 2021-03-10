## Enrich EBDB User

### Purpose

Creates enriched tables for the context `User` from ebdb.

It will track detailed information about the QuintoAndar users, such as the affiliate, agents, end-user, doorman, and sales rep.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output tables:

1. In data lake enrich:
    - `user`
    - `agent_data`
    - `user_doorman`
    - `user_sales_rep`
    - `affiliate_data`

### Responsible Data Engineering Team

For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
