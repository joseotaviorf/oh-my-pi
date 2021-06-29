## Enrich Tracksale
### Purpose

Prepares [Tracksale](https://www.tracksale.co/) data for business utilization. Tracksale is an external service that manages NPS data.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG is triggered once per day via Mediator, after `dispatch` and `answer` tasks of the `tracksale` DAG, usually around 4:30 A.M. UTC.

More information about run time [here]({chart_url}{dag_id}).

### Outputs

This pipeline produces the following output tables on the enrich layer:

- `campaign`
- `answer_tags`
- `answer`
- `answer_justifications`
- `customer_conversions`
- `dispatch`
- `dispatch_attributes`

### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).

</details>