## Enrich Tracksale Casa Mineira
### Purpose

Prepares [Tracksale](https://www.tracksale.co/) data for business utilization. Tracksale is an external service that manages NPS data.

This DAG was built specifcally to enrich the historical data gathered from Tracksale Casa Mineira's account and will not run daily.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

This DAG will run only once (or on demand), since it processes historical data from an old Tracksale account.

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
For any questions or concerns about this DAG, please contact the Dag Owner Team.

</details>