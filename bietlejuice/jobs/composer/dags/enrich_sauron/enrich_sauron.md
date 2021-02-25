## Enrich Sauron
### Purpose

Prepares [Sauron](github.com/quintoandar/sauron) data for business utilization. Sauron is the messageing orchestration service, and controls the user session when someone contact our customer services.

### Execution Interval

This DAG is triggered once per day via Mediator, after `load-session-to-clean` task of the Sauron extraction DAG, usually around 4:30 A.M. UTC.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table on enrich layer:

- `session`

### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
