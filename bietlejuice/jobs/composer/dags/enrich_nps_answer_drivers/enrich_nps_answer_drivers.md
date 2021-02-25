## Enrich NPS Answer Drivers
### Purpose

Prepares [Tracksale](https://www.tracksale.co/) and EBDB ([Main's](https://github.com/quintoandar/main) database) data for business utilization. Tracksale is an external service that manages NPS data.

### Execution Interval

This DAG is triggered once per day via Mediator, after these DAGs: `enrich_tracksale` (task `load-answer-to-enrich`), `ebdb` (tasks `load-house`, `load-booking`, `load-offer` and `load-contract`) and `enrich_ebdb_listing` (task `load-house-listing-to-enrich`). Usually around 5:00 A.M. UTC.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table on enrich layer:

- `answer_drivers`

### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
