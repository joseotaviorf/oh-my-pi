## Terminator

### Purpose
This DAG imports the tables from [Terminator](https://github.com/quintoandar/terminator), our service to orchestrate the offboard contract process.

### Execution Interval
This DAG is triggered daily. 

More information about run time [here]({chart_url}{dag_id}).

### Outputs
This pipeline produces, via full load:

1. In datalake raw:
    - All tables available in source's database.
    

2. In datalake clean:
    - `attachment`
    - `attachment_aud`
    - `contract` 
    - `inspection`
    - `inspection_aud` 
    - `member`
    - `negotiation` 
    - `negotiation_aud`
    - `rev_info`
    - `termination` 
    - `termination_aud`
    - `termination_fee`
    - `termination_fee_aud`
    - `termination_fee_negotiation`
    - `termination_fee_negotiation_aud`
    - `utility_bill`
    - `utility_bill_aud`

### Responsible Data Engineering Team
For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).