## Risk and Mortgage

### Purpose
This DAG imports the tables from [Risk And Mortgage](https://github.com/quintoandar/risk-and-mortgage), a service that makes an interface with Itau bank for financing credit approval.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval
This DAG is triggered daily. 

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces, in datalake raw and clean:

Via **incremental load**:
    - `bank_application`
    - `bank_application_aud`
    - `credit_application`
    - `credit_application_aud`
    - `credit_proposal`
    - `financing_options`
    - `financing_options_aud`
    - `offer_pre_analysis`

### Responsible Data Teams
For any questions or concerns about this DAG and data, please contact the Data Engineering Team or
Data Analytics Team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
</details>