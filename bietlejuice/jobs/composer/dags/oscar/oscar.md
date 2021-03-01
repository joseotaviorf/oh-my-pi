## Oscar
​
### Purpose
​
This DAG extracts data from [Oscar](https://github.com/quintoandar/oscar), a service responsible for B2B Prime referrals.
​
### Execution​ Interval

This DAG is trigged daily.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces the following output tables:

1. Data lake raw:

    - All tables in database, except for the Operational ones.

2. Data lake clean:

    - `house_summary`
    - `house_summary_aud`
    - `referral`
    - `referral_aud`
    - `referral_referred`
    - `referral_referred_aud`
    - `referral_status`
    - `referral_summary_view`
    - `referred`
    - `referred_aud`
    - `rev_info`  
​
### Responsible Data Engineering Team
​
For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).