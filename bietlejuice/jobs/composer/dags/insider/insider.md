## Insider
### Purpose

Retrieves data from the Insider database (PostgreSQL). [Insider](https://github.com/quintoandar/insider) is a manager for follow ups. In other words, the purpose of it is to store and manage Follow Ups (A.K.A. reviews).

### Execution Interval

Daily. More information about run time [here]({chart_url}{dag_id}).

### Outputs

We load the following tables into the datalake Raw and Clean:

- `user_revision_entity`
- `template`
- `template_feature`
- `review`
- `review_feature`
- `review_aud`
- `resource`
- `feature`

### Responsible Data Team
​
For any questions or concerns about this DAG, please contact the Data Engineering or Data Analytics team responsible listed in the [DAG owners](https://www.notion.so/productquintoandar/DAG-Owners-01810df413074722b014ac1cf033b7bd).
