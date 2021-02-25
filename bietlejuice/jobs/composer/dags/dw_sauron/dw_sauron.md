## DW Sauron
### Purpose
​
This DAG loads the DW tables with the **sessions** data from our Sauron database. [Sauron](https://github.com/quintoandar/sauron) is the messaging orchestration service, and it controls the user session when someone contact our customer service lines.
​
### Execution​ Interval
This DAG is triggered once per day via Mediator, after `enrich_sauron` and `enrich_ebdb_customer_contact_identification` DAGs, and `load-channel-to-enrich` task from `enrich_quinto_messenger` DAG. Usually, it runs around 6:00 A.M. UTC.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces the following output tables:
​
- `dim_session`
- `fact_session_tags`
- `fact_sessions`

### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
