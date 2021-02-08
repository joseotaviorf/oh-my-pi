## Enrich Braze Events Dispatches
​
### Purpose
​
This DAG load the DW tables for Chatttermill data. Those data are related to NPS.
​
### Execution​ Interval
This DAG is triggered once per day via Mediator, after enrich_chattermill DAG, usually around 5 A.M. UTC.

More information about run time [here]({chart_url}{dag_id}).

### Outputs
​
This pipeline produces the following output tables:
​
- `fact_answer_category` – Contains sentiments, score, comments among other informations.
- `dim_answer_category` – Contains category and theme of the NPS response categorization.
​
### Responsible Data Engineering Team
​
For any questions or concerns about this DAG, please contact the Data Engineering Team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
​
### Additional Information
​​
The Data Analytics team responsible for Chattermill data is also on aforementioned document.
