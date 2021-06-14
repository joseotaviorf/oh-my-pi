## Enrich Survicate
### Purpose

Transform survey response collected from [Survicate](https://developers.survicate.com/data-export/#get-the-list-of-surveys). 

### Execution Interval

This DAG is triggered once per day via Mediator, after `load-surveys-to-clean` task of the Survicate extraction DAG.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output table on enrich layer (via incremental load):

- `surveys`

### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
