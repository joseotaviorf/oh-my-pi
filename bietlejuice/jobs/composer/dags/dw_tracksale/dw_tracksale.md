## DW Chattermill
### Purpose
​
This DAG loads the DW tables with [Tracksale](https://www.tracksale.co/) data. This data is related to NPS.
​
### Execution​ Interval
This DAG is triggered once per day via Mediator, after `enrich_tracksale`, `enrich_nps_answer_drivers` and `enrich_ebdb_customer_contact_identification` DAGs, usually around 5:30 A.M. UTC.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces the following output tables:
​
- `dim_nps_answer_`
- `dim_nps_campaign_`
- `fact_nps_answer_justifications_`
- `fact_nps_customer_metrics_`
- `fact_nps_dispatches_`
​
### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
