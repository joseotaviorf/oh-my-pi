## Jaiminho
### Purpose

Retrieves data from the Jaiminho database (PostgreSQL). [Jaiminho](https://github.com/quintoandar/jaiminho) is a microservice that handles notification schedule processing.

<details>
  <summary><strong> > DAG details (click to expand)</strong></summary>

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

Load the following tables into the datalake clean (via incremental load):

- `user_notifications`

### Responsible Data Team
​
For any questions or concerns about this DAG, please contact its owner.

</details>