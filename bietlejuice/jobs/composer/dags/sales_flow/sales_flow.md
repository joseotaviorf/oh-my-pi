## Sales Flow

### Purpose

This DAG imports the tables from [Sales Flow](https://github.com/quintoandar/sales-flow), a service responsible for the management of ForSale's operations after receiving an offer.

### Execution Interval

This DAG is triggered daily. 

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces, in **datalake raw and clean**, tables via incremental load:
    - `address_data`
    - `address_data_aud`
    - `ccv`
    - `ccv_aud`
    - `ccv_party`
    - `ccv_party_aud`
    - `house`
    - `house_aud`
    - `offer`
    - `offer_aud`
    - `payment`
    - `payment_aud`
    - `rev_info`
    - `sales_flow`
    - `sales_flow_aud`
    - `user_sample`
    - `user_sample_aud`
    - `users`
    - `users_aud`

If you need to add a new table that does not have an `updated_at` column, you must update the raw spark job (load_incremental_sales_flow_into_datalake), adding the table and the column name (timestamp/date type)
for the incremental load on the `COLUMN_MAPPING` dict, and then create the clean query. 

### Responsible Data Teams
For any questions or concerns about this DAG and data, please contact the Data Engineering Team or
Data Analytics Team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).