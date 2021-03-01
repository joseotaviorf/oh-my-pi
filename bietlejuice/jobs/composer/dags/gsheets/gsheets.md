## GSHEETS
​
### Purpose
​
This DAG extracts data from Google Sheets files.
​
### Execution​ Interval

This DAG is trigged daily.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces the following output tables:

1. Data lake raw:
    - All gsheets defined in `gsheets_files.yaml`

2. Data lake clean:
    - `auxiliary_region`
    - `from_to_cancellation`
    - `marketing_manual_costs_google`
    - `taxonomy_demand`
    - `reorganize_leads`
​
### Responsible Data Engineering Team
​
For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the 
[DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).