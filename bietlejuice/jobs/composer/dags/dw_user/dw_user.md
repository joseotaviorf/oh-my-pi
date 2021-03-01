## DW User

### Purpose

Full load of the context `User` models into DW
with enriched data of amplitude, users and partners from ebdb.

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output tables:

- `dim_partner`
- `dim_partner_agent`
- `dim_user`
- `dim_user_doorman`

### Responsible Data Engineering Team

For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
