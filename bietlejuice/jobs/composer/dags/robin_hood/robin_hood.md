## Robin Hood

### Purpose

This DAG creates the full tables for Robin Hood, a digital wallet that has two main features: users financial data management and management of payment requests.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily. 

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output tables: 

1. In data lake raw: 
    - All tables available in source's database, except for operational table `schema_migrations`.

2. In data lake clean:

    - `accounting_entry`
    - `accounting_entry_balance` 
    - `accounting_entry_source`
    - `financial_data`
    - `payee`
    - `payee_account`
    - `payment_request`
    - `payment_request_lot` 
    - `tax`


### Responsible Data Engineering Team

For any questions or concerns about this DAG, please contact the Data Engineering Team or 
the Data Analytics Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
</details>
