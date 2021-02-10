## Robin Hood
​
### Purpose
​
This DAG creates the full tables for Robin Hood, a digital wallet that has two main features: users financial data management and management of payment requests.
​
### Execution​ Interval
This DAG is triggered daily. 

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces the following output tables: 

1. In data lake raw: 
- All tables available in source's database, except for `accounting_entry_balance` and operational table `schema_migrations`.

2. In data lake clean:​
​
- `accounting_entry`
- `accounting_entry_source`
- `financial_data`
- `payee`
- `payee_account`
- `payment_request`
- `payment_request_lot` 
- `tax`

​
### Responsible Data Engineering Team
​
For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
