## Owner Fees

### Purpose
​
This DAG creates the tables from [Ownerfees](https://github.com/quintoandar/owner-fees), a service that deals with fees related to the contract, listing and bills that are charged to the owner.
​
### Execution​ Interval

Daily at 1 AM Sao_Paulo/America.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
The ingestion type is defined in a `.config` file for each table, with their respective date column names for incremental ingestion type tables.
This pipeline produces the following output tables, both in `raw` and `clean` layers:

1. Full load:
    - `admin_fee_option_aud`
    - `contract_aud`
    - `contract_brokerage_fee_aud`
    - `house_aud`
    - `house_brokerage_fee_aud`
    - `user_rev_info`
    - `users_aud`

2. Incremental load:
    - `admin_fee_option`
    - `charge_delay`
    - `charge_delay_aud`
    - `contract`
    - `contract_brokerage_fee`
    - `house`
    - `house_brokerage_fee`
    - `installment_option`
    - `installment_option_aud`
    - `users`
​
### Responsible Data Engineering Team
​
For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
