## DW User

### Purpose

Full load of the context `User` models into DW
with enriched data of amplitude, users and partners from ebdb.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Produces the following output tables, partitioned by `country_code`:

- `dim_owner_category`
- `dim_owner`
- `dim_partner`
- `dim_partner_agent`
- `dim_user`
- `dim_user_doorman`
- `dim_user_sales_rep`

